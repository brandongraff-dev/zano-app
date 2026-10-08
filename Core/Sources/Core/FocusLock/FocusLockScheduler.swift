// FocusLockScheduler.swift
// Core / FocusLock
//
// Keeps the work-hours focus lock (docs/spec.md §5.24) in step with the calendar. `refresh()` reads
// the next two days of events, runs the pure `FocusLockPlanner`, and splits the result three ways:
// windows to lock for (the user said yes to this one, or said yes twice to this recurring event),
// windows to ask about, and nothing for the ones they said no to. Locked windows are registered with
// `DeviceActivityCenter` as one-off schedules; `ScheduledLockMonitor` (the `ZANOMonitor` extension)
// shields the apps at the window's start and `LockScheduler.reconcile` turns that into a real
// `LockSession` (no required goals, so it ends at the window's end, by emergency unlock, or by hand).
//
// When it runs: on every app foreground and after any change in Settings. iOS gives no background
// hook for calendar changes, so a meeting added while the app is closed is picked up the next time
// the app opens (UNVERIFIED: a background refresh task could narrow that gap; not built here).
//
// Limits: Apple caps how many activities one app can monitor (believed 20, UNVERIFIED), so the focus
// lock arms at most `FocusLockSettings.maxWindows`. One-off DeviceActivity schedules with a full
// year/month/day start and end are used from memory of the API and have not run on a device.
//
// Emergency unlock is untouched: a focus lock is an ordinary `LockSession` the user can end any time.

import Foundation
import DeviceActivity
import os

@MainActor
public final class FocusLockScheduler {
    public static let shared = FocusLockScheduler()

    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "FocusLockScheduler")

    init(activityCenter: DeviceActivityCenter = DeviceActivityCenter()) {
        self.activityCenter = activityCenter
    }

    // MARK: Refresh

    /// Re-plans from the calendar. Safe to call often: only windows that changed are re-registered.
    public func refresh(now: Date = .now) {
        let settings = FocusLockStore.settings
        guard settings.isEnabled, FocusLockCalendarSource.hasAccess else {
            clearAll()
            return
        }
        let horizon = now.addingTimeInterval(TimeInterval(FocusLockSettings.horizonHours * 3_600))
        let events = FocusLockCalendarSource.shared.events(from: now, to: horizon)
        let proposals = FocusLockPlanner.plan(events: events, settings: settings, memory: FocusLockStore.memory, now: now)
        apply(proposals)
    }

    /// Settings changed: save, then re-plan (or stand down if turned off).
    public func save(_ settings: FocusLockSettings, now: Date = .now) {
        FocusLockStore.settings = settings
        refresh(now: now)
    }

    /// The user said yes to asking-first window `proposal` (counts toward locking this event by itself).
    public func accept(_ proposal: FocusLockProposal, now: Date = .now) {
        var answers = FocusLockStore.answers
        answers[proposal.id] = true
        FocusLockStore.answers = answers
        var memory = FocusLockStore.memory
        memory.recordAccept(proposal.window.patternKey)
        FocusLockStore.memory = memory
        refresh(now: now)
    }

    /// The user said no to `proposal` (two no's and it stops asking).
    public func decline(_ proposal: FocusLockProposal, now: Date = .now) {
        var answers = FocusLockStore.answers
        answers[proposal.id] = false
        FocusLockStore.answers = answers
        var memory = FocusLockStore.memory
        memory.recordDecline(proposal.window.patternKey)
        FocusLockStore.memory = memory
        refresh(now: now)
    }

    /// Settings: forget what was learned about one recurring event (it asks again).
    public func forget(patternKey: String, now: Date = .now) {
        var memory = FocusLockStore.memory
        memory.forget(patternKey)
        FocusLockStore.memory = memory
        refresh(now: now)
    }

    // MARK: Apply

    /// Splits `proposals` into armed windows and pending questions, then syncs DeviceActivity.
    func apply(_ proposals: [FocusLockProposal]) {
        let answers = FocusLockStore.answers
        var wanted: [FocusLockWindow] = []
        var pending: [FocusLockProposal] = []
        for proposal in proposals {
            switch (proposal.decision, answers[proposal.id]) {
            case (.skip, _), (_, .some(false)): continue
            case (_, .some(true)), (.autoLock, nil): wanted.append(proposal.window)
            case (.ask, nil): pending.append(proposal)
            }
        }
        // Answers only matter for windows still in the plan; drop the rest so the list doesn't grow.
        let live = Set(proposals.map(\.id))
        FocusLockStore.answers = answers.filter { live.contains($0.key) }

        FocusLockStore.armedWindows = register(wanted)
        FocusLockStore.pendingProposals = pending
    }

    /// Registers `wanted` and unregisters anything else; returns the windows that are actually armed.
    private func register(_ wanted: [FocusLockWindow]) -> [FocusLockWindow] {
        let previous = Dictionary(uniqueKeysWithValues: FocusLockStore.armedWindows.map { ($0.id, $0) })
        let wantedNames = Set(wanted.map { FocusLockActivity.rawName(windowID: $0.id) })

        // Stop windows that are gone or changed (a joined window grew, an event moved).
        let registered = activityCenter.activities.filter { FocusLockActivity.isFocusActivity($0.rawValue) }
        let stale = registered.filter { name in
            guard wantedNames.contains(name.rawValue) else { return true }
            guard let id = FocusLockActivity.windowID(fromRawName: name.rawValue),
                  let old = previous[id], let new = wanted.first(where: { $0.id == id })
            else { return false }
            return old.start != new.start || old.end != new.end
        }
        if !stale.isEmpty { activityCenter.stopMonitoring(stale) }
        let stillRegistered = Set(registered.map(\.rawValue)).subtracting(stale.map(\.rawValue))

        var armed: [FocusLockWindow] = []
        for window in wanted {
            let name = DeviceActivityName(FocusLockActivity.rawName(windowID: window.id))
            if stillRegistered.contains(name.rawValue) {
                armed.append(window)
                continue
            }
            do {
                try activityCenter.startMonitoring(name, during: Self.schedule(for: window))
                armed.append(window)
            } catch {
                logger.error("Arming a focus window failed: \(String(describing: error), privacy: .public)")
            }
        }
        return armed
    }

    /// A one-off schedule with a full date on both ends (not a repeating one).
    static func schedule(for window: FocusLockWindow, calendar: Calendar = .current) -> DeviceActivitySchedule {
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: window.start),
            intervalEnd: calendar.dateComponents(parts, from: window.end),
            repeats: false
        )
    }

    /// Feature off (or Calendar access gone): unregister every focus window and forget the plan.
    /// Settings and what the memory learned are kept.
    private func clearAll() {
        let registered = activityCenter.activities.filter { FocusLockActivity.isFocusActivity($0.rawValue) }
        if !registered.isEmpty { activityCenter.stopMonitoring(registered) }
        FocusLockStore.armedWindows = []
        FocusLockStore.pendingProposals = []
    }
}
