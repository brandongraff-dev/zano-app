// HouseholdQuietTimeScheduler.swift
// Core / Household
//
// Keeps this phone's joined household screen-free times (session 44, docs/spec.md §5.31) registered with
// `DeviceActivityCenter`, the same way `LockScheduler` registers lock schedules and `BedtimeGateManager`
// registers the night window: repeating windows (daily, or weekly per day, ending on the next day when the
// window crosses midnight). From there the existing path takes over: `ScheduledLockMonitor.quietTimeDidStart`
// shields at the start and leaves a `.household` pending record, `LockScheduler.reconcile` turns it into a
// real `LockSession` with no goals (like a focus window), and `quietTimeDidEnd` lifts it at the end.
//
// Overlaps follow the existing rule: a window never stacks on a lock that is already running.
// Emergency unlock is untouched: a screen-free-time lock is an ordinary `LockSession`, and nothing re-arms the
// same occurrence afterwards (`HouseholdQuietTimeStore.hasDecided`).
//
// Also plans the "Dinner in 10 min" heads-up notifications, replacing only its own.
//
// UNVERIFIED (no device): the same DeviceActivity unknowns session 38 lists for the Bedtime Gate, i.e. repeating
// schedules whose end is earlier than the start, and weekly windows whose end weekday differs from the start.

import Foundation
import DeviceActivity
import os

@MainActor
public final class HouseholdQuietTimeScheduler {
    public static let shared = HouseholdQuietTimeScheduler()

    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "HouseholdQuietTimeScheduler")

    init(activityCenter: DeviceActivityCenter = DeviceActivityCenter()) {
        self.activityCenter = activityCenter
    }

    // MARK: Server

    /// Fetches the household's windows into the App Group cache, then syncs. Offline or signed out: keeps the
    /// cache and still syncs what's there. `householdID == nil` (no household): clears the cache.
    public func refresh(householdID: UUID?, now: Date = .now) async {
        if let householdID {
            if let fresh = try? await HouseholdClient.shared.quietTimes(householdID: householdID) {
                await apply(fresh, now: now)
                return
            }
        } else {
            await apply([], now: now)
            return
        }
        await sync(now: now)
    }

    /// Foreground: find this person's household (the first, as the Household screen does) and refresh.
    public func refreshOnForeground(now: Date = .now) async {
        guard HouseholdAvailability.isLive else {
            await standDown(now: now)
            return
        }
        guard await HouseholdClient.shared.isConfigured else { return }
        guard let households = try? await HouseholdClient.shared.households() else {
            await sync(now: now)
            return
        }
        await refresh(householdID: households.first?.id, now: now)
    }

    /// A fresh list from the server (or the screen after an edit).
    public func apply(_ windows: [HouseholdQuietTime], now: Date = .now) async {
        HouseholdQuietTimeStore.replaceWindows(windows)
        await sync(now: now)
    }

    // MARK: Join / leave (this phone only)

    /// Joins `window` with one of this phone's lock sets (`nil` = the default). If the window is already under
    /// way it starts next time, so joining never locks the phone by surprise.
    @discardableResult
    public func join(_ window: HouseholdQuietTime, lockSetID: UUID?, now: Date = .now) async -> Bool {
        guard HouseholdQuietTimePlanner.canJoin(window, joined: HouseholdQuietTimeStore.joinedWindows) else { return false }
        let existing = HouseholdQuietTimeStore.optIn(for: window.id)
        if existing == nil, let running = window.occurrence(containing: now) {
            HouseholdQuietTimeStore.markDecided(windowID: window.id, occurrenceStart: running.start)
        }
        HouseholdQuietTimeStore.setOptIn(
            HouseholdQuietTimeOptIn(windowID: window.id, lockSetID: lockSetID, joinedAt: existing?.joinedAt ?? now),
            for: window.id
        )
        await sync(now: now)
        return true
    }

    /// Leaves `window`. A lock this window started right now ends too: leaving is always allowed.
    public func leave(_ window: HouseholdQuietTime, now: Date = .now) async {
        HouseholdQuietTimeStore.setOptIn(nil, for: window.id)
        await endRunningLock(windowIDs: [window.id], now: now)
        await sync(now: now)
    }

    // MARK: Sync

    /// Re-registers only when the joined set changed or registrations went missing, then re-plans reminders.
    public func sync(now: Date = .now) async {
        let wanted = HouseholdQuietTimePlanner.schedulable(HouseholdQuietTimeStore.joinedWindows)
        let signature = HouseholdQuietTimePlanner.signature(wanted)
        let wantedNames = Set(wanted.flatMap { window in
            window.deviceActivityWindows.map { HouseholdQuietTimeActivity.rawName(windowID: window.id, weekday: $0.startWeekday) }
        })
        let registered = activityCenter.activities.filter { HouseholdQuietTimeActivity.isQuietTimeActivity($0.rawValue) }
        let registeredNames = Set(registered.map(\.rawValue))
        if signature != HouseholdQuietTimeStore.registrationSignature || registeredNames != wantedNames {
            register(wanted, replacing: registered)
            HouseholdQuietTimeStore.registrationSignature = signature
        }
        // A window that was left or deleted while its lock runs: end that lock (never trap anyone).
        let wantedIDs = Set(wanted.map(\.id))
        if let id = runningQuietTimeID(), !wantedIDs.contains(id) {
            await endRunningLock(windowIDs: [id], now: now)
        }
        await planReminders(joined: wanted, now: now)
    }

    /// Household not live (signed out, no backend): stop every registration and reminder, end a running
    /// screen-free-time lock. Joins are kept, so signing back in picks them up again.
    public func standDown(now: Date = .now) async {
        let registered = activityCenter.activities.filter { HouseholdQuietTimeActivity.isQuietTimeActivity($0.rawValue) }
        if !registered.isEmpty { activityCenter.stopMonitoring(registered) }
        HouseholdQuietTimeStore.registrationSignature = nil
        NotificationPermission.cancel(identifiers: HouseholdQuietTimeStore.scheduledReminderIDs)
        HouseholdQuietTimeStore.scheduledReminderIDs = []
        if let id = runningQuietTimeID() {
            await endRunningLock(windowIDs: [id], now: now)
        }
    }

    // MARK: Internals

    /// The screen-free time whose lock is running now (adopted, or still pending from the monitor).
    private func runningQuietTimeID() -> UUID? {
        let raw = LockEngineSharedState.scheduleOwnedLock?.activityRawName ?? LockEngineSharedState.pendingStart?.activityRawName
        return raw.flatMap(HouseholdQuietTimeActivity.windowID(fromRawName:))
    }

    private func register(_ wanted: [HouseholdQuietTime], replacing registered: [DeviceActivityName]) {
        if !registered.isEmpty { activityCenter.stopMonitoring(registered) }
        for window in wanted {
            for slot in window.deviceActivityWindows {
                let name = DeviceActivityName(HouseholdQuietTimeActivity.rawName(windowID: window.id, weekday: slot.startWeekday))
                let schedule = DeviceActivitySchedule(intervalStart: slot.startComponents, intervalEnd: slot.endComponents, repeats: true)
                do {
                    try activityCenter.startMonitoring(name, during: schedule)
                } catch {
                    logger.error("Registering a screen-free time failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Ends the lock a screen-free time started (adopted or still pending), recorded as a manual end.
    private func endRunningLock(windowIDs: Set<UUID>, now: Date) async {
        await LockScheduler.shared.adoptPendingScheduledLock(now: now)
        guard let owned = LockEngineSharedState.scheduleOwnedLock,
              let id = HouseholdQuietTimeActivity.windowID(fromRawName: owned.activityRawName),
              windowIDs.contains(id)
        else { return }
        try? await LockEngineManager.shared.endLock(sessionID: owned.sessionID, unlockKind: .manual, at: now)
    }

    private func planReminders(joined: [HouseholdQuietTime], now: Date) async {
        NotificationPermission.cancel(identifiers: HouseholdQuietTimeStore.scheduledReminderIDs)
        var scheduled: [String] = []
        for item in HouseholdQuietTimePlanner.reminders(joined: joined, now: now) {
            let ok = await NotificationPermission.scheduleOneShot(
                identifier: item.identifier, title: item.title, body: item.body,
                at: item.fireDate, deepLink: "zano://today", now: now
            )
            if ok { scheduled.append(item.identifier) }
        }
        HouseholdQuietTimeStore.scheduledReminderIDs = scheduled
    }
}
