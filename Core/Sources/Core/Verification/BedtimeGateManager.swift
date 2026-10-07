// Core/Sources/Core/Verification/BedtimeGateManager.swift
//
// docs/spec.md §5.10 ★ Bedtime Gate & Sunrise Alarm — the Bedtime Gate half:
//   "Lock auto-arms at the user's set bedtime; phone becomes a clock."
//   "Optional wind-down Live Activity: 'Bedtime lock in 10 min.'"
//   "Pickups after bedtime break the Sleep goal (§3) and are shown gently in the morning recap."
// docs/spec.md §3 "Sleep on time" row (Tier A): "Phone locked & no pickups after bedtime
//   (DeviceActivity threshold) + HealthKit sleep." Anti-cheat: "Pickups after bedtime break the
//   goal."
// docs/spec.md §24 point 2 / CLAUDE.md: "Any lock/alarm feature must always keep an escape hatch
//   — never trap the user." This file never invents a second escape hatch of its own: a
//   Bedtime-Gate-armed lock is an ordinary `LockSession` (started via `LockEngineManager.
//   startLock(trigger: .schedule)`), so the existing `EmergencyUnlock` 60-second hold
//   (`LockEngine/EmergencyUnlock.swift`) already covers it — see `autoArmBedtimeLock`'s doc
//   comment.
//
// IMPORTANT — real-consumer reconciliation (see `SunriseAlarmManager.swift`'s own header
// `decisions` note, same task, in full): `App/ZANO/Features/SunriseAlarm/BedtimeGateSetupView.swift`
// already exists (an earlier wave's session, not this task's to edit) and already reads/writes
// bedtime + the wind-down toggle through **`SunriseAlarmManager.Settings`** — one settings row
// shared with the wake-alarm half, not a second `BedtimeGateManager`-owned settings row (that
// view's own header: "This screen owns exactly the bedtime + wind-down-reminder half of the
// shared `SunriseAlarmManager.Settings` row"). `BedtimeGateManager` never appears in that file (or
// in `SunriseAlarmSetupView.swift`/`AlarmRingingView.swift`) at all — this engine's job (arming,
// the wind-down Live Activity, pickup anti-cheat) is autonomous background behavior those screens
// don't call directly, exactly matching this task's brief. So this file reads `bedtime`/
// `windDownReminderEnabled`/`enabled` from `SunriseAlarmManager.shared.currentSettings()` (this
// same task's other file) instead of maintaining a second, competing settings blob for the same
// two fields — `BedtimeGateAdvancedSettings` below covers only what that shared row has no field
// for (which `LockSet`/goals/mode to actually arm; neither setup screen has a lock-set picker).
//
// This file's own read of `LockEngineManager.swift`/`NFCTagMapper.swift`/`SunriseKeyIntent.swift`
// (this task's required reading) shapes two decisions:
//   - `LockEngineManager.startLock(lockSetID:mode:requiredGoalIDs:trigger:)` is called exactly per
//     its real signature (`LockEngine/LockEngineManager.swift`) — `trigger: .schedule` for the
//     bedtime auto-arm itself (a `DeviceActivity`-driven event, matching that enum case's own
//     meaning), `trigger: .auto` for `armDayLockAfterWake` (arming automatically as a *consequence*
//     of a verified morning dismiss, not a schedule firing or a manual/NFC tap — the one
//     `LockTrigger` case that fits neither of the other three).
//   - `SunriseKeyIntent.perform()` (`Intents/SunriseKeyIntent.swift`, not owned by this task)
//     already arms the day's lock itself after a Tag dismiss, calling `LockEngineManager.
//     startLock` directly with its own "if no lock is already active" guard. `armDayLockAfterWake`
//     below applies the exact same idempotency guard, so `SunriseAlarmManager`'s other dismiss
//     variants (Steps/Focus/Squad, this task's own file) get the identical "arm once, never
//     double-arm" behavior that Tag dismiss already has, without duplicating `SunriseKeyIntent`'s
//     logic — this is that logic's one other legitimate call site, not a second competing
//     implementation of it.
//
// How the gate runs while the app is closed (session 38):
//   - `rearmDailySchedule()` registers the night window (bedtime to wake time, usually across
//     midnight; `BedtimeGateSchedule`) with DeviceActivity under `BedtimeGateActivity`'s names.
//   - `ZANOMonitor` → `ScheduledLockMonitor.intervalDidStart` shields the gate's lock set from App
//     Group state alone and leaves a `.bedtime` pending record. The app turns it into a real
//     `LockSession` (`adoptMonitorArmedLock`, via `LockScheduler.reconcile`/`adoptPendingScheduledLock`)
//     the next time it runs, so emergency unlock, goals and the Earn Meter all work.
//   - At wake time (`intervalDidEnd`) a bedtime lock with goals keeps going: morning goals are its
//     key (spec §4 v2 "Bedtime lock with morning goals as key", §5.10 step 5). One with no goals to
//     earn ends there, since nothing else could end it but the emergency unlock.
//   - `evaluateOnForeground(now:)` is the backstop: it re-registers lost or outdated registrations
//     and arms a night the monitor missed. Both paths share one "this night is decided" record
//     (`BedtimeGateSharedState.hasArmed`), so they never double-arm or re-arm after an emergency
//     unlock, and neither ever stacks on a lock that's already running.
//   - Real "no pickups after bedtime" detection (`DeviceActivityEvent` device-wide threshold, or
//     `ZANOMonitor.eventDidReachThreshold(_:activity:)`) is Extensions/ZANOMonitor territory too.
//     `recordPickupIfAfterBedtime(at:)` below is the complete, correct *consequence* of a detected
//     pickup — the detection signal itself is the documented gap, flagged in this task's
//     knownIssues (the DeviceActivity event shape for "any pickup, not usage of specific apps" is
//     genuinely uncertain without a Mac/SDK to check against, per CLAUDE.md rule 5).

import Foundation
import SwiftData
import ActivityKit
import DeviceActivity
import UserNotifications
import os

// MARK: - Advanced settings (what `SunriseAlarmManager.Settings` has no field for — see header)

/// Which `LockSet`/goals/mode the Bedtime Gate arms. Neither `BedtimeGateSetupView` nor
/// `SunriseAlarmSetupView` (App layer, not owned by this task) exposes a picker for any of these —
/// they stay sensible internal defaults (the user's default `LockSet`, every active goal, `.full`
/// mode) unless a future settings screen adds one. Persisted the same App-Group-`UserDefaults`-blob
/// way `NFCTagMapper.swift`/`SunriseAlarmManager.swift` (this same task) already do, for the same
/// documented reason (spec §13's frozen Data Model table has no row for this either).
public struct BedtimeGateAdvancedSettings: Codable, Sendable, Equatable {
    /// Which `LockSet` to arm at bedtime. `nil` means "the user's default `LockSet`" (resolved via
    /// `LockSetManager.shared.defaultLockSet(for:)` at arm time, never re-guessed here).
    public var lockSetID: UUID?
    /// Which goals must be verified to earn the way out of the bedtime-armed lock. `nil` means
    /// "every currently-active goal" (`IntentSupport.activeGoalIDs(for:in:)`), matching
    /// `SunriseKeyIntent`'s own default for its own auto-armed lock.
    public var requiredGoalIDs: [UUID]?
    /// `.full` (hard block until goals earned) vs `.earn` (Time Bank). Spec §5.10 describes the
    /// Bedtime Gate as a hard lock ("phone becomes a clock") — `.full` is the correct default.
    public var mode: LockMode
    /// Which nights the gate runs (`Calendar` weekdays, the day bedtime falls on). Every night by
    /// default; spec §5.10 names no day picker, so nothing in the app changes this yet. A night that's
    /// off gets no DeviceActivity registration and no foreground catch-up (session 38).
    public var nights: Set<Int>

    public init(
        lockSetID: UUID? = nil,
        requiredGoalIDs: [UUID]? = nil,
        mode: LockMode = .full,
        nights: Set<Int> = BedtimeGateSchedule.everyNight
    ) {
        self.lockSetID = lockSetID
        self.requiredGoalIDs = requiredGoalIDs
        self.mode = mode
        self.nights = nights
    }

    public static let `default` = BedtimeGateAdvancedSettings()

    private enum CodingKeys: String, CodingKey {
        case lockSetID, requiredGoalIDs, mode, nights
    }

    /// A blob saved before `nights` existed still loads (every night), instead of failing to decode
    /// and silently dropping the saved lock set and mode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lockSetID = try container.decodeIfPresent(UUID.self, forKey: .lockSetID)
        requiredGoalIDs = try container.decodeIfPresent([UUID].self, forKey: .requiredGoalIDs)
        mode = try container.decodeIfPresent(LockMode.self, forKey: .mode) ?? .full
        nights = try container.decodeIfPresent(Set<Int>.self, forKey: .nights) ?? BedtimeGateSchedule.everyNight
    }
}

// MARK: - Errors

public enum BedtimeGateError: Error, Sendable, LocalizedError {
    case noSignedInUser
    case noLockSetAvailable

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        case .noLockSetAvailable: "No LockSet exists to arm — set one up first."
        }
    }
}

// DeviceActivity names: `BedtimeGateActivity` (BedtimeGateSchedule.swift), shared with the monitor.

// MARK: - BedtimeGateManager

/// Owns the Bedtime Gate's recurring schedule, wind-down Live Activity, pickup anti-cheat, and the
/// "arm the day's lock automatically" call both the bedtime side (`autoArmBedtimeLock`) and the
/// Sunrise Alarm's dismiss flow (`armDayLockAfterWake`, called from `SunriseAlarmManager`, this
/// same task) share. Bedtime/wind-down *preferences* live in `SunriseAlarmManager.Settings` (see
/// header); this file reads them from there rather than owning a competing copy.
///
/// `@MainActor`, matching `LockEngineManager`/`FocusSessionVerifier`/`EarnMeterActivityManager`'s
/// identical reasoning: this type owns a `DeviceActivityCenter` and an ActivityKit `Activity`,
/// both Apple APIs whose own sample code always drives them from the main actor, and every real
/// call site (`SunriseAlarmManager`, `LockScheduler`, the app shell) is on the main actor.
/// `ZANOMonitor` never touches this type: it uses the nonisolated `BedtimeGateSharedState` and
/// `ScheduledLockMonitor` instead.
@MainActor
public final class BedtimeGateManager {
    public static let shared = BedtimeGateManager()

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "BedtimeGateManager")

    /// Spec §5.10's own example: "Bedtime lock in 10 min." Not exposed in either setup screen, so
    /// kept as a constant rather than a settings field — nothing to configure yet.
    private static let windDownLeadMinutes = 10

    private var windDownActivity: Activity<BedtimeWindDownActivityAttributes>?

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container — mirrors `LockEngineManager`/`FocusSessionVerifier`'s identical
    /// testability convention. Every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup, activityCenter: DeviceActivityCenter = DeviceActivityCenter()) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.activityCenter = activityCenter
    }

    // MARK: - Advanced settings persistence

    public func advancedSettings() -> BedtimeGateAdvancedSettings {
        BedtimeGateSharedState.advancedSettings
    }

    /// Saves the advanced settings and re-registers the night windows if `nights` changed them.
    public func updateAdvancedSettings(_ newSettings: BedtimeGateAdvancedSettings) {
        BedtimeGateSharedState.advancedSettings = newSettings
        syncDailySchedule()
    }

    // MARK: - Night schedule (DeviceActivity, so the gate arms while the app is closed)

    /// Registers (or replaces) the night windows from the saved settings: one daily repeating
    /// bedtime-to-wake `DeviceActivitySchedule`, or one weekly window per night when some nights are
    /// off (`BedtimeGateSchedule.deviceActivityWindows`). Built the same way `LockScheduler.register`
    /// builds a lock schedule's windows. Called from `SunriseAlarmManager.saveSettings(_:)` whenever
    /// the shared settings row changes, so a bedtime edit takes effect tonight. If "now" is already
    /// inside tonight's window, iOS may start the interval straight away; the monitor then arms
    /// unless this night was already decided.
    public func rearmDailySchedule() async throws {
        guard let schedule = BedtimeGateSharedState.currentSchedule(),
              let settings = SunriseAlarmManager.storedSettings()
        else {
            stopMonitoringAllNights()
            await cancelWindDownNotification()
            return
        }
        try register(schedule)

        if settings.windDownReminderEnabled {
            await scheduleWindDownNotification(bedtime: settings.bedtime)
        } else {
            await cancelWindDownNotification()
        }
    }

    public func disableDailySchedule() {
        stopMonitoringAllNights()
        Task { await cancelWindDownNotification() }
    }

    /// Cheap foreground check: re-registers only when the saved settings no longer match what was
    /// registered (e.g. an install that still has the pre-session-38 bedtime-to-23:59 window) or the
    /// registrations were lost (a restore). Turns everything off when the gate is off.
    public func syncDailySchedule() {
        let registered = Set(activityCenter.activities.map(\.rawValue).filter(BedtimeGateActivity.isBedtimeActivity))
        guard let schedule = BedtimeGateSharedState.currentSchedule() else {
            if !registered.isEmpty || BedtimeGateSharedState.registrationSignature != nil { stopMonitoringAllNights() }
            return
        }
        let wanted = Set(schedule.deviceActivityWindows.map(\.activityRawName))
        guard BedtimeGateSharedState.registrationSignature != schedule.registrationSignature || registered != wanted else { return }
        do { try register(schedule) } catch {
            logger.error("Re-registering the Bedtime Gate failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func register(_ schedule: BedtimeGateSchedule) throws {
        stopMonitoringAllNights()
        var registered: [DeviceActivityName] = []
        do {
            for window in schedule.deviceActivityWindows {
                let name = DeviceActivityName(window.activityRawName)
                let activitySchedule = DeviceActivitySchedule(
                    intervalStart: window.startComponents,
                    intervalEnd: window.endComponents,
                    repeats: true
                )
                try activityCenter.startMonitoring(name, during: activitySchedule)
                registered.append(name)
            }
        } catch {
            activityCenter.stopMonitoring(registered)
            throw error
        }
        BedtimeGateSharedState.registrationSignature = schedule.registrationSignature
    }

    private func stopMonitoringAllNights() {
        let names = activityCenter.activities.filter { BedtimeGateActivity.isBedtimeActivity($0.rawValue) }
        if !names.isEmpty { activityCenter.stopMonitoring(names) }
        BedtimeGateSharedState.registrationSignature = nil
    }

    /// A daily-repeating local notification at `bedtime` minus `windDownLeadMinutes` (spec §5.10:
    /// "Bedtime lock in 10 min") — the reliable, OS-level companion to the wind-down Live Activity
    /// above: a Live Activity can only be *started* by running code, which can't happen from a
    /// killed/backgrounded app with no push infrastructure, but a `UNCalendarNotificationTrigger`
    /// with `repeats: true` fires from the OS every night regardless. `evaluateOnForeground`'s
    /// `startWindDownIfNeeded` still starts the richer Live Activity whenever the app happens to
    /// be open for the window; this notification is what reaches the user the rest of the time.
    private func scheduleWindDownNotification(bedtime: Date) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        center.removePendingNotificationRequests(withIdentifiers: [Self.windDownNotificationIdentifier])

        guard let windDownTime = Calendar.current.date(byAdding: .minute, value: -Self.windDownLeadMinutes, to: bedtime) else { return }
        let copy = SunriseAlarmCopy.windDownNotification(minutesUntilBedtime: Self.windDownLeadMinutes)

        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        // Wind-down: the buddy, sleepy. None if the image can't be made.
        if let attachment = BuddyNotificationImage.attachment(pose: .sleepy) {
            content.attachments = [attachment]
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: windDownTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.windDownNotificationIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func cancelWindDownNotification() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.windDownNotificationIdentifier])
    }

    private static let windDownNotificationIdentifier = "zano.bedtimeGate.windDown"

    // MARK: - Foreground backstop (the monitor is the primary path; see header)

    /// Call on every app foreground, after `LockScheduler.reconcile()` (which adopts anything the
    /// monitor armed). Keeps the night registrations current, starts the wind-down Live Activity in
    /// its window, and arms tonight's lock if `now` is inside a night the monitor didn't arm (a
    /// delayed or missed callback, or registrations that were lost). Does nothing if the gate was
    /// never set up or is off.
    public func evaluateOnForeground(now: Date = .now) async {
        syncDailySchedule()
        guard let settings = SunriseAlarmManager.storedSettings(), settings.enabled else { return }

        if settings.windDownReminderEnabled, isWithinWindDownWindow(bedtime: settings.bedtime, now: now) {
            await startWindDownIfNeeded(bedtime: settings.bedtime, now: now)
        }
        do {
            try await autoArmBedtimeLock(trigger: .schedule, now: now)
        } catch {
            logger.error("Bedtime Gate catch-up failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Auto-arm (spec §5.10: "Lock auto-arms at the user's set bedtime")

    /// Arms tonight's lock from the app (the foreground backstop). At most once per night, shared with
    /// the monitor through `BedtimeGateSharedState.hasArmed`, so the two paths never both arm one night
    /// and nothing re-arms a night the user already left by emergency unlock.
    ///
    /// Escape hatch: deliberately not reimplemented here. The `LockSession` this starts is an
    /// ordinary session (`LockEngineManager.startLock`), so `LockEngine/EmergencyUnlock.swift`'s
    /// existing 60-second hold already applies to it exactly like any other lock — spec §24 point
    /// 2 / CLAUDE.md's "never trap the user" is satisfied by *reusing* that path, not by this file
    /// inventing a second one (a second, subtly-different emergency-unlock implementation would be
    /// the actual risk here, not a missing one).
    ///
    /// - Returns: the new `LockSession.id`, or `nil` if the gate is off, `now` is outside tonight's
    ///   window, the night was already decided, the monitor's hand-off is still waiting to be adopted,
    ///   or another lock is running (never stacked; the night then counts as decided).
    @discardableResult
    public func autoArmBedtimeLock(trigger: LockTrigger = .schedule, now: Date = .now) async throws -> UUID? {
        guard let schedule = BedtimeGateSharedState.currentSchedule(),
              let night = schedule.night(containing: now)
        else { return nil }
        guard !BedtimeGateSharedState.hasArmed(nightStartingAt: night.start) else { return nil }
        // The monitor already armed something; `LockScheduler` adopts it, never a second arm here.
        guard LockEngineSharedState.pendingStart == nil else { return nil }

        let user = try fetchCurrentUser()
        guard try IntentSupport.activeLockSession(for: user.id, in: context) == nil else {
            // Something else already has a lock running (e.g. a manual lock, or a morning lock
            // still waiting for goals) — never stack a second shield on top.
            BedtimeGateSharedState.markArmed(nightStartingAt: night.start)
            return nil
        }

        let advanced = advancedSettings()
        let lockSetID = try await resolveLockSetID(advanced: advanced, userID: user.id)
        let requiredGoalIDs = try advanced.requiredGoalIDs ?? IntentSupport.activeGoalIDs(for: user.id, in: context)

        let sessionID: UUID
        do {
            sessionID = try await LockEngineManager.shared.startLock(
                lockSetID: lockSetID,
                mode: advanced.mode,
                requiredGoalIDs: requiredGoalIDs,
                trigger: trigger
            )
        } catch LockEngineError.deviceActivitySchedulingFailed(let reason) {
            // The session and shield exist; only the rest-of-day keep-alive registration failed
            // (e.g. under 15 minutes left before 23:59). Same handling as `LockScheduler.convert`.
            guard let activeID = SharedDefaults.activeLockSessionID else {
                throw LockEngineError.deviceActivitySchedulingFailed(reason: reason)
            }
            sessionID = activeID
        }
        BedtimeGateSharedState.markArmed(nightStartingAt: night.start)
        await finishArming(
            sessionID: sessionID,
            lockSetID: lockSetID,
            activityRawName: schedule.activityRawName(forNightStartingAt: night.start),
            night: night,
            trigger: trigger,
            now: now
        )
        return sessionID
    }

    // MARK: - Monitor hand-off (session 38)

    /// Turns the lock `ZANOMonitor` shielded at bedtime (`ScheduledLockMonitor`, `.bedtime` pending
    /// record) into a real `LockSession`, started at the time the monitor shielded. Called by
    /// `LockScheduler.convert`, which has already cleared the pending record; when this returns
    /// `nil` the caller's `removeShieldIfNoActiveLock()` lifts the shield, so a hand-off that can't
    /// complete (gate switched off since, no user, lock set deleted) never leaves a shield with no
    /// session to end.
    @discardableResult
    public func adoptMonitorArmedLock(_ pending: PendingScheduledLock, now: Date = .now) async -> UUID? {
        guard let schedule = BedtimeGateSharedState.currentSchedule() else { return nil }
        guard let user = try? fetchCurrentUser() else { return nil }
        // The monitor never arms over a running lock; if one appeared since, don't stack.
        guard (try? IntentSupport.activeLockSession(for: user.id, in: context)) == nil else { return nil }

        let advanced = advancedSettings()
        var resolvedLockSetID = pending.lockSetID
        if resolvedLockSetID == nil {
            resolvedLockSetID = try? await resolveLockSetID(advanced: advanced, userID: user.id)
        }
        guard let lockSetID = resolvedLockSetID else { return nil }
        let goalIDs = (try? pending.requiredGoalIDs ?? IntentSupport.activeGoalIDs(for: user.id, in: context)) ?? []
        let night = schedule.night(containing: pending.startedAt)
            ?? DateInterval(start: pending.startedAt, duration: TimeInterval(schedule.durationMinutes * 60))

        var sessionID: UUID?
        do {
            sessionID = try await LockEngineManager.shared.startLock(
                lockSetID: lockSetID,
                mode: pending.mode,
                requiredGoalIDs: goalIDs,
                trigger: .schedule,
                startedAt: pending.startedAt
            )
        } catch LockEngineError.deviceActivitySchedulingFailed {
            sessionID = SharedDefaults.activeLockSessionID
        } catch {
            logger.error("Bedtime hand-off failed: \(String(describing: error), privacy: .public)")
        }
        guard let sessionID else { return nil }
        BedtimeGateSharedState.markArmed(nightStartingAt: night.start)
        await finishArming(
            sessionID: sessionID,
            lockSetID: lockSetID,
            activityRawName: pending.activityRawName,
            night: night,
            trigger: .schedule,
            now: now
        )
        return sessionID
    }

    /// Shared tail of both arming paths. A bedtime lock with no goals to earn (no active goals, or
    /// only ones that can't gate a lock) is a timed night lock: it's owned by its night's window so
    /// `ScheduledLockMonitor.intervalDidEnd` ends it at wake time, and if wake time has already passed
    /// it ends now, recorded at wake time. A lock with goals keeps going until they're earned.
    private func finishArming(
        sessionID: UUID,
        lockSetID: UUID,
        activityRawName: String,
        night: DateInterval,
        trigger: LockTrigger,
        now: Date
    ) async {
        // `startLock` drops goals that can't gate a lock before mirroring the count; read the mirror.
        if SharedDefaults.activeLockSessionID == sessionID, SharedDefaults.goalsRemainingForActiveLock == 0 {
            if now >= night.end {
                try? await LockEngineManager.shared.endLock(sessionID: sessionID, unlockKind: .scheduleEnd, at: night.end)
            } else {
                LockEngineSharedState.scheduleOwnedLock = ScheduleOwnedLock(
                    sessionID: sessionID,
                    lockSetID: lockSetID,
                    activityRawName: activityRawName
                )
            }
        }
        await endWindDownActivity(isLocked: true, now: now)
        Analytics.shared.capture(event: "bedtime_gate_armed", properties: ["trigger": trigger.rawValue])
        logger.notice("Bedtime Gate lock \(sessionID.uuidString, privacy: .public) armed.")
    }

    // MARK: - Day-lock arming after wake (spec §5.10 step 4: "the day's lock arms automatically" —
    // the call site the task brief names explicitly: "call BedtimeGateManager/LockEngineManager")

    /// The `SunriseAlarmManager` (this same task) call site for its dismiss variants — the exact
    /// "arm the day's lock, but only if nothing already has" behavior `SunriseKeyIntent.perform()`
    /// (not owned by this task) already implements inline for its own Tag-dismiss path. Kept here,
    /// not duplicated in `SunriseAlarmManager`, so both call sites share one implementation.
    ///
    /// - Returns: the new `LockSession.id`, or `nil` if a lock is already active (nothing to arm)
    ///   or no `User`/`LockSet` can be resolved.
    @discardableResult
    public func armDayLockAfterWake(requiredGoalIDs: [UUID]? = nil, mode: LockMode? = nil, now: Date = .now) async -> UUID? {
        guard let user = try? fetchCurrentUser() else { return nil }
        guard (try? IntentSupport.activeLockSession(for: user.id, in: context)) == nil else { return nil }

        let advanced = advancedSettings()
        guard let lockSetID = try? await resolveLockSetID(advanced: advanced, userID: user.id) else { return nil }
        let goalIDs = (try? requiredGoalIDs ?? advanced.requiredGoalIDs ?? IntentSupport.activeGoalIDs(for: user.id, in: context)) ?? []

        let sessionID = try? await LockEngineManager.shared.startLock(
            lockSetID: lockSetID,
            mode: mode ?? advanced.mode,
            requiredGoalIDs: goalIDs,
            trigger: .auto
        )
        if let sessionID {
            Analytics.shared.capture(event: "day_lock_armed_after_wake", properties: [:])
            logger.notice("Armed day lock \(sessionID.uuidString, privacy: .public) after a verified morning dismiss.")
        }
        return sessionID
    }

    // MARK: - Wind-down Live Activity (spec §5.10: "Bedtime lock in 10 min")

    public func startWindDownIfNeeded(bedtime: Date, now: Date = .now) async {
        guard windDownActivity == nil else {
            await updateWindDownActivity(bedtime: bedtime, now: now)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities disabled; running wind-down without one.")
            return
        }

        let minutesRemaining = minutesUntilBedtime(bedtime: bedtime, now: now)
        let attributes = BedtimeWindDownActivityAttributes(bedtimeLabel: Self.bedtimeLabel(bedtime: bedtime))
        let content = ActivityContent(
            state: BedtimeWindDownActivityAttributes.ContentState(minutesUntilBedtime: minutesRemaining, isLocked: false),
            staleDate: nil
        )
        do {
            windDownActivity = try Activity<BedtimeWindDownActivityAttributes>.request(attributes: attributes, content: content)
            logger.notice("Started Bedtime wind-down Live Activity: \(minutesRemaining, privacy: .public) min remaining.")
        } catch {
            logger.error("Failed to start Bedtime wind-down Live Activity: \(String(describing: error), privacy: .public)")
        }
    }

    public func updateWindDownActivity(bedtime: Date, now: Date = .now) async {
        guard let liveActivity = windDownActivity else { return }
        nonisolated(unsafe) let activity = liveActivity
        let minutesRemaining = minutesUntilBedtime(bedtime: bedtime, now: now)
        let content = ActivityContent(
            state: BedtimeWindDownActivityAttributes.ContentState(minutesUntilBedtime: max(0, minutesRemaining), isLocked: false),
            staleDate: nil
        )
        await activity.update(content)
    }

    public func endWindDownActivity(isLocked: Bool, now: Date = .now) async {
        guard let liveActivity = windDownActivity else { return }
        windDownActivity = nil
        nonisolated(unsafe) let activity = liveActivity
        let content = ActivityContent(
            state: BedtimeWindDownActivityAttributes.ContentState(minutesUntilBedtime: 0, isLocked: isLocked),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .after(now.addingTimeInterval(30)))
    }

    // MARK: - Pickups after bedtime (spec §3 "Sleep on time" anti-cheat — real logic; the live
    // pickup-detection signal itself is the documented ZANOMonitor gap, see header comment)

    /// Records that the phone was picked up at `date`. If `date` falls after tonight's bedtime and
    /// before the next morning's cutoff, this breaks the Sleep goal for tonight (spec §3: "Pickups
    /// after bedtime break the goal") by logging a `.miss` `GoalEvent` — idempotent per night, so a
    /// string of pickups only ever logs the one break, not one per pickup (spec §5.10: "shown
    /// gently in the morning recap," not compounded into a pile of misses).
    ///
    /// `source: .manual` is this method's own flagged choice, not a spec-exact fit: `GoalEvent.
    /// source` (`Models/GoalEvent.swift`, not owned by this task) has no case for "detected by a
    /// DeviceActivity/system signal" — the closest real options are `.manual`, `.timer`,
    /// `.geofence`, `.healthKit`, none of which accurately describe a pickup-threshold trigger.
    /// `.manual` is used with an explicit `meta` marker so this is never confused with an actual
    /// user-entered log; flagged in this task's knownIssues as a case this enum should probably
    /// grow (`Models/GoalEvent.swift` is a different session's file to extend).
    public func recordPickupIfAfterBedtime(at date: Date = .now) async {
        let settings = await SunriseAlarmManager.shared.currentSettings()
        guard settings.enabled else { return }
        guard let nightStart = bedtimeAnchor(bedtime: settings.bedtime, coveringPickupAt: date) else { return }
        guard date >= nightStart else { return }

        guard let user = try? fetchCurrentUser() else { return }
        guard let sleepGoal = try? IntentSupport.activeGoal(ofType: .sleepOnTime, for: user.id, in: context) else { return }
        guard !hasPickupMissLogged(goalID: sleepGoal.id, forNightOf: nightStart) else { return }

        let event = GoalEvent(
            ts: date,
            kind: .miss,
            source: .manual,
            verified: false,
            meta: .object([
                "reason": .string("pickupAfterBedtime"),
                "detectionSource": .string("deviceActivityPickup"),
                "nightOf": .string(Self.dayFormatter.string(from: nightStart)),
            ]),
            user: user,
            goal: sleepGoal
        )
        context.insert(event)
        try? context.save()
        logger.notice("Sleep goal broken by a pickup after bedtime.")
    }

    /// Whether the phone was picked up after bedtime on the night that began at `nightStart`.
    /// `nil` when there is no user or no Sleep goal to say (the sleep wind-down treats that as unknown).
    public func pickedUpAfterBedtime(nightStarting nightStart: Date) -> Bool? {
        guard let user = try? fetchCurrentUser(),
              let sleepGoal = try? IntentSupport.activeGoal(ofType: .sleepOnTime, for: user.id, in: context)
        else { return nil }
        return hasPickupMissLogged(goalID: sleepGoal.id, forNightOf: nightStart)
    }

    /// Mirrors `LockEngineManager.isGoalVerified`/`StreakEngine`'s documented `#Predicate`-
    /// conservatism tradeoff: only the `Date` field goes into the predicate (this session has no
    /// Mac/Swift toolchain to compile-verify how SwiftData's `#Predicate` macro handles a custom
    /// `Codable` enum's equality or optional-relationship chaining on this SDK version); `kind`,
    /// `goal`, and `source` are filtered in plain Swift after the fetch.
    private func hasPickupMissLogged(goalID: UUID, forNightOf nightStart: Date) -> Bool {
        guard let nightEnd = Calendar.current.date(byAdding: .day, value: 1, to: nightStart) else { return false }
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= nightStart && $0.ts < nightEnd }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains {
            $0.kind == .miss && $0.goal?.id == goalID && $0.source == .manual
        }
    }

    // MARK: - Time helpers

    private func bedtimeDate(bedtime: Date, on date: Date, calendar: Calendar = .current) -> Date? {
        let bedComponents = calendar.dateComponents([.hour, .minute], from: bedtime)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = bedComponents.hour
        components.minute = bedComponents.minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func isWithinWindDownWindow(bedtime: Date, now: Date) -> Bool {
        guard let anchor = bedtimeDate(bedtime: bedtime, on: now) else { return false }
        let windDownStart = anchor.addingTimeInterval(-Double(Self.windDownLeadMinutes) * 60)
        return now >= windDownStart && now < anchor
    }

    private func minutesUntilBedtime(bedtime: Date, now: Date) -> Int {
        guard let anchor = bedtimeDate(bedtime: bedtime, on: now) else { return 0 }
        return max(0, Int((anchor.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// The most recent bedtime at/before `date`, treating the "night" as starting at bedtime and
    /// running until the next day's bedtime — used to check a pickup timestamp against the bedtime
    /// that actually governs it, whether that bedtime was earlier tonight or (for a pickup in the
    /// small hours) yesterday evening. `nil` when `date` is more than 24h after any resolvable
    /// bedtime, which never happens for a real "just picked up the phone" call.
    private func bedtimeAnchor(bedtime: Date, coveringPickupAt date: Date, calendar: Calendar = .current) -> Date? {
        guard let todayBedtime = bedtimeDate(bedtime: bedtime, on: date, calendar: calendar) else { return nil }
        if date >= todayBedtime { return todayBedtime }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return bedtimeDate(bedtime: bedtime, on: yesterday, calendar: calendar)
    }

    private static func bedtimeLabel(bedtime: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: bedtime)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    // MARK: - Resolving what to arm

    private func resolveLockSetID(advanced: BedtimeGateAdvancedSettings, userID: UUID) async throws -> UUID {
        if let lockSetID = advanced.lockSetID { return lockSetID }
        if let defaultSet = try await LockSetManager.shared.defaultLockSet(for: userID) {
            return defaultSet.id
        }
        throw BedtimeGateError.noLockSetAvailable
    }

    // MARK: - SwiftData

    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw BedtimeGateError.noSignedInUser
        }
        return user
    }

    // App Group storage (advanced settings, the per-night record, the registration signature) lives
    // in `BedtimeGateSharedState` (BedtimeGateSchedule.swift) so `ZANOMonitor` can read it too.
}
