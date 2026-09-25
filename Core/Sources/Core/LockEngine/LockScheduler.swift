// Core/Sources/Core/LockEngine/LockScheduler.swift
//
// Scheduled daily locks (docs/spec.md §2 "Lock triggers: Schedule (e.g., 7:00 AM daily)", §4 v1
// "Lock via: manual button, NFC tag, daily schedule", §11 "LockEngine (shields, schedules, unlock
// rules, Time Bank)") and the App Group state the `ZANOMonitor` DeviceActivity extension needs to
// act on them without the app running (§27: extensions are tiny, no networking, App Group only).
//
// Where things persist (deliberately NOT SwiftData — see "Why not a model field" below):
//   - `LockSchedule` per lock set: App Group `UserDefaults`, one JSON blob (`LockEngineSharedState`).
//   - A mirror of each lock set's `appTokensBlob` + the default lock set id, so the monitor can
//     shield without opening the SwiftData store (written by `LockSetManager`).
//   - A "pending scheduled lock" record the monitor writes when it shields at a scheduled start;
//     the app turns it into a real `LockSession` on its next foreground (`LockScheduler.reconcile`).
//   - The Earn Mode spend window (`SpendWindow`) and the "intended shield" selection, so whichever
//     process notices the window is over can put the shield back.
//
// Why not a model field: `LockSet` (Models/, spec §13 `lock_sets`) is a synced table whose shape
// mirrors Postgres; adding columns means a SwiftData schema migration plus a Supabase migration,
// and the monitor extension can't cheaply read SwiftData anyway. A device-local Codable blob in the
// App Group is the least risky store, the same way `BedtimeGateAdvancedSettings` and
// `NFCTagMapper` already persist their settings. Schedules are therefore NOT synced across devices
// (they're paired with device-local app tokens, so that's also the honest behaviour).
//
// Flow:
//   app: LockScheduleEditor → `LockScheduler.shared.save(_:)` → DeviceActivityCenter registration
//   (one repeating daily schedule, or one weekly schedule per chosen weekday).
//   monitor: `intervalDidStart` → `ScheduledLockMonitor.intervalDidStart` → shield + pending record.
//   app foreground: `LockScheduler.shared.reconcile()` → `LockEngineManager.startLock(trigger:
//   .schedule)` so goals, emergency unlock, earned unlock, tiers and the Earn Meter all work.
//   monitor: `intervalDidEnd` → shield off + a pending "schedule end" the app records as
//   `.scheduleEnd`. "Until goals are done" windows end at 23:59 (goals are per day).
//
// Emergency unlock is untouched: every shield this file applies either becomes a real `LockSession`
// (which `EmergencyUnlock` can end) on the next app open, or is removed by `reconcile` if it can't.
// A shield is never left in place without a session the user can end.

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import SwiftData
import os

// MARK: - LockSchedule

/// When a lock set locks by itself. Times are minutes after local midnight; weekdays use
/// `Calendar`'s numbering (1 = Sunday ... 7 = Saturday).
public struct LockSchedule: Codable, Sendable, Hashable {
    public static let minutesPerDay = 1_440
    /// Spec §27: "DeviceActivity schedules have a minimum interval of 15 minutes".
    public static let minimumWindowMinutes = 15
    /// 23:59 — where an "until goals are done" window ends (the goals are daily).
    public static let endOfDayMinute = 1_439
    public static let allWeekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    public var lockSetID: UUID
    public var isEnabled: Bool
    public var weekdays: Set<Int>
    public var startMinuteOfDay: Int
    /// `nil` = "until goals are done" (the default, and what onboarding's plan promises: "Locks
    /// each morning until your goals are done"). Otherwise the lock also ends at this time.
    public var endMinuteOfDay: Int?
    public var mode: LockMode
    /// `nil` = every goal that's active when the lock starts.
    public var requiredGoalIDs: [UUID]?

    public init(
        lockSetID: UUID,
        isEnabled: Bool = true,
        weekdays: Set<Int> = LockSchedule.allWeekdays,
        startMinuteOfDay: Int = 7 * 60,
        endMinuteOfDay: Int? = nil,
        mode: LockMode = .full,
        requiredGoalIDs: [UUID]? = nil
    ) {
        self.lockSetID = lockSetID
        self.isEnabled = isEnabled
        self.weekdays = weekdays
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.mode = mode
        self.requiredGoalIDs = requiredGoalIDs
    }

    /// 7:00 every day, until goals are done — the onboarding plan's promise.
    public static func morningDefault(lockSetID: UUID, mode: LockMode = LockPreferences.defaultMode) -> LockSchedule {
        LockSchedule(lockSetID: lockSetID, mode: mode)
    }

    public var isUntilGoalsDone: Bool { endMinuteOfDay == nil }
    public var effectiveEndMinuteOfDay: Int { endMinuteOfDay ?? Self.endOfDayMinute }

    public enum ValidationError: Error, Sendable, Equatable {
        case noWeekdays
        case startOutOfRange
        case endOutOfRange
        /// End not at least 15 minutes after start (also rejects windows crossing midnight —
        /// overnight locking is the Bedtime Gate's job, spec §5.10).
        case windowTooShort
    }

    public func validate() -> ValidationError? {
        guard !weekdays.isEmpty, weekdays.isSubset(of: Self.allWeekdays) else { return .noWeekdays }
        guard (0..<Self.minutesPerDay).contains(startMinuteOfDay) else { return .startOutOfRange }
        if let endMinuteOfDay, !(0...Self.endOfDayMinute).contains(endMinuteOfDay) { return .endOutOfRange }
        guard effectiveEndMinuteOfDay - startMinuteOfDay >= Self.minimumWindowMinutes else { return .windowTooShort }
        return nil
    }

    public var isValid: Bool { validate() == nil }

    /// Whether `date` falls inside one of this schedule's windows.
    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, isValid else { return false }
        guard weekdays.contains(calendar.component(.weekday, from: date)) else { return false }
        let minute = Self.minuteOfDay(date, calendar: calendar)
        return minute >= startMinuteOfDay && minute < effectiveEndMinuteOfDay
    }

    /// The first window start strictly after `date`, or `nil` when disabled/invalid.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled, isValid else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = Self.date(on: day, minuteOfDay: startMinuteOfDay, calendar: calendar)
            else { continue }
            if start > date { return start }
        }
        return nil
    }

    /// The DeviceActivity registrations this schedule needs: one daily repeating window when every
    /// weekday is on, otherwise one weekly window per weekday. Pure, so it's unit-tested.
    public var deviceActivityWindows: [LockScheduleWindow] {
        guard isValid else { return [] }
        let end = effectiveEndMinuteOfDay
        let endSecond = isUntilGoalsDone ? 59 : 0
        let days: [Int?] = weekdays == Self.allWeekdays ? [nil] : weekdays.sorted().map { Optional($0) }
        return days.map { weekday in
            LockScheduleWindow(
                weekday: weekday,
                startHour: startMinuteOfDay / 60,
                startMinute: startMinuteOfDay % 60,
                endHour: end / 60,
                endMinute: end % 60,
                endSecond: endSecond
            )
        }
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(on day: Date, minuteOfDay: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)
    }
}

/// One `DeviceActivitySchedule` worth of a `LockSchedule`.
public struct LockScheduleWindow: Sendable, Hashable {
    /// `nil` = every day (daily repeat); otherwise the weekly repeat's weekday.
    public let weekday: Int?
    public let startHour: Int
    public let startMinute: Int
    public let endHour: Int
    public let endMinute: Int
    public let endSecond: Int

    public var startComponents: DateComponents {
        DateComponents(hour: startHour, minute: startMinute, second: 0, weekday: weekday)
    }

    public var endComponents: DateComponents {
        DateComponents(hour: endHour, minute: endMinute, second: endSecond, weekday: weekday)
    }
}

// MARK: - DeviceActivity names

/// Stable `DeviceActivityName`s for scheduled locks and Earn Mode spend windows. Raw-string helpers
/// are pure so the naming/parsing round trip is unit-tested.
public enum LockScheduleActivity {
    static let schedulePrefix = "com.zano.app.schedule."
    static let spendRawName = "com.zano.app.spend"

    static func rawName(lockSetID: UUID, weekday: Int?) -> String {
        let base = schedulePrefix + lockSetID.uuidString
        guard let weekday else { return base }
        return base + ".d\(weekday)"
    }

    /// The lock set a schedule activity belongs to, or `nil` for any other activity name.
    static func lockSetID(fromRawName raw: String) -> UUID? {
        guard raw.hasPrefix(schedulePrefix) else { return nil }
        let rest = raw.dropFirst(schedulePrefix.count)
        return UUID(uuidString: String(rest.prefix(36)))
    }

    public static func name(lockSetID: UUID, weekday: Int?) -> DeviceActivityName {
        DeviceActivityName(rawName(lockSetID: lockSetID, weekday: weekday))
    }

    public static var spend: DeviceActivityName { DeviceActivityName(spendRawName) }
}

// MARK: - App Group records

/// A lock the monitor extension started (shield applied) that the app hasn't turned into a
/// `LockSession` yet.
public struct PendingScheduledLock: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case schedule
        case bedtime
    }

    public var id: UUID
    public var source: Source
    public var lockSetID: UUID?
    public var activityRawName: String
    public var startedAt: Date
    /// Set when the window ended before the app ever opened (recorded as history only).
    public var endedAt: Date?
    public var mode: LockMode
    public var requiredGoalIDs: [UUID]?
}

/// A schedule window ended while its `LockSession` was active; the app records `.scheduleEnd`.
public struct PendingScheduleEnd: Codable, Sendable, Equatable {
    public var sessionID: UUID
    public var endedAt: Date
}

/// Which session a schedule started, so only *that* window's end can end it (a bedtime or manual
/// lock on the same lock set is never ended by a morning window closing).
public struct ScheduleOwnedLock: Codable, Sendable, Equatable {
    public var sessionID: UUID
    public var lockSetID: UUID
    public var activityRawName: String
}

/// Earn Mode: the shield is lifted until `endsAt` because the user spent Time Bank minutes.
public struct SpendWindow: Codable, Sendable, Equatable {
    public var sessionID: UUID
    public var startedAt: Date
    public var endsAt: Date
}

// MARK: - LockPreferences

/// User-level lock preferences (App Group, device-local).
public enum LockPreferences {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let defaultModeKey = "lockEngine.defaultMode.v1"

    /// The mode a new lock starts in when the caller doesn't choose (Lock tab, Today, schedules).
    /// Defaults to `.earn`, matching what the Lock tab and Today already start today.
    public static var defaultMode: LockMode {
        get { defaults.string(forKey: defaultModeKey).flatMap(LockMode.init(rawValue:)) ?? .earn }
        set { defaults.set(newValue.rawValue, forKey: defaultModeKey) }
    }
}

// MARK: - LockEngineSharedState

/// The App Group state shared by the app and `ZANOMonitor`. Cheap `UserDefaults` reads only —
/// safe inside a memory-limited extension. Owned by the LockEngine folder; nothing else writes it.
public enum LockEngineSharedState {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let schedules = "lockEngine.schedules.v1"
        static let lockSetSelections = "lockEngine.lockSetSelections.v1"
        static let defaultLockSetID = "lockEngine.defaultLockSetID.v1"
        static let activeGoalCount = "lockEngine.activeGoalCount.v1"
        static let intendedShield = "lockEngine.intendedShieldSelection.v1"
        static let pendingStart = "lockEngine.pendingScheduledLock.v1"
        static let finishedPending = "lockEngine.finishedPendingLocks.v1"
        static let pendingEnds = "lockEngine.pendingScheduleEnds.v1"
        static let scheduleOwned = "lockEngine.scheduleOwnedLock.v1"
        static let spendWindow = "lockEngine.spendWindow.v1"
        static let lastEarnedUnlockAt = "lockEngine.lastEarnedUnlockAt.v1"
    }

    // Schedules

    public static var schedules: [LockSchedule] {
        get { read([LockSchedule].self, key: Keys.schedules) ?? [] }
        set { write(newValue, key: Keys.schedules) }
    }

    public static func schedule(for lockSetID: UUID) -> LockSchedule? {
        schedules.first { $0.lockSetID == lockSetID }
    }

    static func upsert(_ schedule: LockSchedule) {
        var all = schedules.filter { $0.lockSetID != schedule.lockSetID }
        all.append(schedule)
        schedules = all
    }

    static func removeSchedule(for lockSetID: UUID) {
        schedules = schedules.filter { $0.lockSetID != lockSetID }
    }

    /// Earliest upcoming start across every enabled schedule.
    public static func nextScheduledStart(after date: Date, calendar: Calendar = .current) -> Date? {
        schedules.compactMap { $0.nextStart(after: date, calendar: calendar) }.min()
    }

    /// Writes `SharedDefaults.nextScheduledLockAt` (widget, Earn Meter, Lock tab "Next lock").
    public static func refreshNextScheduledLockAt(now: Date = .now) {
        SharedDefaults.nextScheduledLockAt = nextScheduledStart(after: now)
    }

    // Lock set mirrors (written by `LockSetManager`)

    public static func lockSetSelectionData(for lockSetID: UUID) -> Data? {
        (defaults.dictionary(forKey: Keys.lockSetSelections) as? [String: Data])?[lockSetID.uuidString]
    }

    static func replaceLockSetSelections(_ selections: [UUID: Data]) {
        var dict: [String: Data] = [:]
        for (id, data) in selections { dict[id.uuidString] = data }
        defaults.set(dict, forKey: Keys.lockSetSelections)
    }

    static func setLockSetSelectionData(_ data: Data?, for lockSetID: UUID) {
        var dict = (defaults.dictionary(forKey: Keys.lockSetSelections) as? [String: Data]) ?? [:]
        dict[lockSetID.uuidString] = data
        defaults.set(dict, forKey: Keys.lockSetSelections)
    }

    public static var defaultLockSetID: UUID? {
        get { defaults.string(forKey: Keys.defaultLockSetID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Keys.defaultLockSetID) }
    }

    /// How many goals are active — a schedule with `requiredGoalIDs == nil` shows this on the
    /// shield until the app resolves the real list.
    public static var activeGoalCount: Int {
        get { defaults.integer(forKey: Keys.activeGoalCount) }
        set { defaults.set(newValue, forKey: Keys.activeGoalCount) }
    }

    // Shield

    /// JSON `FamilyActivitySelection` that *should* be shielded for the active lock (full set, or
    /// what partial tiers leave locked). Survives a spend window so the shield can come back.
    public static var intendedShieldSelection: Data? {
        get { defaults.data(forKey: Keys.intendedShield) }
        set { defaults.set(newValue, forKey: Keys.intendedShield) }
    }

    // Monitor ↔ app hand-off

    public static var pendingStart: PendingScheduledLock? {
        get { read(PendingScheduledLock.self, key: Keys.pendingStart) }
        set { write(newValue, key: Keys.pendingStart) }
    }

    static var finishedPendingLocks: [PendingScheduledLock] {
        get { read([PendingScheduledLock].self, key: Keys.finishedPending) ?? [] }
        set { write(Array(newValue.suffix(14)), key: Keys.finishedPending) }
    }

    static var pendingEnds: [PendingScheduleEnd] {
        get { read([PendingScheduleEnd].self, key: Keys.pendingEnds) ?? [] }
        set { write(Array(newValue.suffix(14)), key: Keys.pendingEnds) }
    }

    public static var scheduleOwnedLock: ScheduleOwnedLock? {
        get { read(ScheduleOwnedLock.self, key: Keys.scheduleOwned) }
        set { write(newValue, key: Keys.scheduleOwned) }
    }

    public static var spendWindow: SpendWindow? {
        get { read(SpendWindow.self, key: Keys.spendWindow) }
        set { write(newValue, key: Keys.spendWindow) }
    }

    /// Stamped by `LockEngineManager.endLock(.earned)`. A schedule whose goals are "every active
    /// goal" doesn't re-lock on a day those goals were already earned.
    public static var lastEarnedUnlockAt: Date? {
        get { defaults.object(forKey: Keys.lastEarnedUnlockAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastEarnedUnlockAt) }
    }

    // Codable helpers

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

// MARK: - ScheduledLockMonitor (called from Extensions/ZANOMonitor)

/// Everything `ZANOMonitor` does, kept in Core so the extension is a thin shim and the logic lives
/// next to the engine it hands off to. Nonisolated, synchronous, App Group `UserDefaults` +
/// `ManagedSettingsStore` only: no SwiftData, no networking (spec §27).
public enum ScheduledLockMonitor {
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "ScheduledLockMonitor")

    /// A scheduled window (or the Bedtime Gate's nightly schedule) started.
    public static func intervalDidStart(for activity: DeviceActivityName, now: Date = .now) {
        let raw = activity.rawValue
        defer { LockEngineSharedState.refreshNextScheduledLockAt(now: now) }

        if raw == DeviceActivityName.zanoBedtimeGate.rawValue {
            // The Bedtime Gate arms the user's default set now; the app's reconcile hands off to
            // `BedtimeGateManager.autoArmBedtimeLock`, which applies its own lock-set/mode settings.
            arm(
                source: .bedtime,
                lockSetID: LockEngineSharedState.defaultLockSetID,
                activityRawName: raw,
                mode: .full,
                requiredGoalIDs: nil,
                now: now
            )
            return
        }

        guard let lockSetID = LockScheduleActivity.lockSetID(fromRawName: raw) else { return }
        guard let schedule = LockEngineSharedState.schedule(for: lockSetID), schedule.isEnabled else {
            logger.notice("Ignoring stale schedule activity \(raw, privacy: .public).")
            return
        }
        if schedule.requiredGoalIDs == nil,
           let earned = LockEngineSharedState.lastEarnedUnlockAt,
           Calendar.current.isDate(earned, inSameDayAs: now) {
            logger.notice("Goals already earned today; scheduled lock skipped.")
            return
        }
        arm(
            source: .schedule,
            lockSetID: lockSetID,
            activityRawName: raw,
            mode: schedule.mode,
            requiredGoalIDs: schedule.requiredGoalIDs,
            now: now
        )
    }

    /// A window ended. Scheduled locks end with it; Earn Mode spend windows re-shield.
    public static func intervalDidEnd(for activity: DeviceActivityName, now: Date = .now) {
        let raw = activity.rawValue
        if raw == LockScheduleActivity.spendRawName {
            spendWindowDidEnd(now: now)
            return
        }
        // Bedtime and per-session keep-alive registrations end at 23:59 but their locks continue
        // until goals are earned — only a lock schedule's own window end ends its lock.
        guard LockScheduleActivity.lockSetID(fromRawName: raw) != nil else { return }
        endScheduledLock(activityRawName: raw, now: now)
        LockEngineSharedState.refreshNextScheduledLockAt(now: now)
    }

    /// Spend windows under 15 minutes are registered as a 15-minute interval whose end *warning*
    /// lands at the real end (see `LockEngineManager.beginSpendWindow`).
    public static func intervalWillEndWarning(for activity: DeviceActivityName, now: Date = .now) {
        guard activity.rawValue == LockScheduleActivity.spendRawName else { return }
        spendWindowDidEnd(now: now)
    }

    // MARK: Internals

    private static func arm(
        source: PendingScheduledLock.Source,
        lockSetID: UUID?,
        activityRawName: String,
        mode: LockMode,
        requiredGoalIDs: [UUID]?,
        now: Date
    ) {
        // Never stack a second lock on an active one.
        guard SharedDefaults.activeLockSessionID == nil, LockEngineSharedState.pendingStart == nil else { return }
        guard let lockSetID,
              let blob = LockEngineSharedState.lockSetSelectionData(for: lockSetID),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
        else {
            logger.error("No mirrored app selection for the scheduled lock set; nothing shielded.")
            return
        }

        ManagedSettingsStore(named: .zanoLock).applyZanoShield(selection)
        LockEngineSharedState.intendedShieldSelection = blob
        LockEngineSharedState.pendingStart = PendingScheduledLock(
            id: UUID(),
            source: source,
            lockSetID: lockSetID,
            activityRawName: activityRawName,
            startedAt: now,
            endedAt: nil,
            mode: mode,
            requiredGoalIDs: requiredGoalIDs
        )
        SharedDefaults.activeLockSetID = lockSetID
        SharedDefaults.activeLockMode = mode
        SharedDefaults.goalsRemainingForActiveLock = requiredGoalIDs?.count ?? LockEngineSharedState.activeGoalCount
        logger.notice("Scheduled lock armed from the monitor (\(source.rawValue, privacy: .public)).")
    }

    private static func endScheduledLock(activityRawName raw: String, now: Date) {
        if var pending = LockEngineSharedState.pendingStart, pending.activityRawName == raw {
            // The app never opened during the window: lift the shield, keep a history record.
            pending.endedAt = now
            LockEngineSharedState.pendingStart = nil
            LockEngineSharedState.finishedPendingLocks.append(pending)
            liftLock()
            return
        }
        guard let owned = LockEngineSharedState.scheduleOwnedLock, owned.activityRawName == raw else { return }
        LockEngineSharedState.scheduleOwnedLock = nil
        guard SharedDefaults.activeLockSessionID == owned.sessionID else { return }
        LockEngineSharedState.pendingEnds.append(PendingScheduleEnd(sessionID: owned.sessionID, endedAt: now))
        liftLock()
    }

    private static func liftLock() {
        ManagedSettingsStore(named: .zanoLock).clearAllSettings()
        LockEngineSharedState.intendedShieldSelection = nil
        LockEngineSharedState.spendWindow = nil
        SharedDefaults.activeLockSessionID = nil
        SharedDefaults.activeLockSetID = nil
        SharedDefaults.activeLockMode = nil
        SharedDefaults.goalsRemainingForActiveLock = 0
    }

    /// Re-shields after a spend window, unless a newer (longer) window replaced it or the lock
    /// already ended. 90 s tolerance: DeviceActivity callbacks can be early/late (spec §27).
    static func spendWindowDidEnd(now: Date) {
        guard let window = LockEngineSharedState.spendWindow else { return }
        guard now.addingTimeInterval(90) >= window.endsAt else { return }
        LockEngineSharedState.spendWindow = nil
        guard SharedDefaults.activeLockSessionID == window.sessionID,
              let blob = LockEngineSharedState.intendedShieldSelection,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
        else { return }
        ManagedSettingsStore(named: .zanoLock).applyZanoShield(selection)
    }
}

// MARK: - LockScheduler

public enum LockSchedulerError: Error, Sendable, LocalizedError {
    case invalidSchedule(LockSchedule.ValidationError)
    case deviceActivityRegistrationFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSchedule(let reason): "Invalid lock schedule: \(reason)."
        case .deviceActivityRegistrationFailed(let reason): "Could not register the lock schedule: \(reason)"
        }
    }
}

/// Saves lock schedules, registers them with `DeviceActivityCenter`, and reconciles whatever the
/// monitor extension did while the app wasn't running.
///
/// Limit: Apple caps how many activities one app can monitor at once (believed to be 20 —
/// UNVERIFIED). A lock set scheduled on every day uses 1; a subset of weekdays uses 1 per day.
@MainActor
public final class LockScheduler {
    public static let shared = LockScheduler()

    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "LockScheduler")

    init(activityCenter: DeviceActivityCenter = DeviceActivityCenter()) {
        self.activityCenter = activityCenter
    }

    public func schedule(for lockSetID: UUID) -> LockSchedule? {
        LockEngineSharedState.schedule(for: lockSetID)
    }

    /// Persists `schedule` and (re)registers its DeviceActivity windows. If "now" is already inside
    /// a window, iOS may start the interval right away, which locks immediately — by design.
    public func save(_ schedule: LockSchedule, now: Date = .now) throws {
        if let problem = schedule.validate() { throw LockSchedulerError.invalidSchedule(problem) }
        LockEngineSharedState.upsert(schedule)
        defer { LockEngineSharedState.refreshNextScheduledLockAt(now: now) }
        try register(schedule)
    }

    public func removeSchedule(for lockSetID: UUID, now: Date = .now) {
        stopMonitoring(lockSetID: lockSetID)
        LockEngineSharedState.removeSchedule(for: lockSetID)
        LockEngineSharedState.refreshNextScheduledLockAt(now: now)
    }

    /// Re-registers every saved schedule (e.g. after a restore, or if registrations were lost).
    public func rearmAll(now: Date = .now) {
        for schedule in LockEngineSharedState.schedules {
            do { try register(schedule) } catch {
                logger.error("Re-arming schedule failed: \(String(describing: error), privacy: .public)")
            }
        }
        LockEngineSharedState.refreshNextScheduledLockAt(now: now)
    }

    /// Call on every app foreground (first thing). Turns the monitor's hand-off records into real
    /// `LockSession`s, records schedule ends, restores a shield after an expired spend window,
    /// removes any shield no session owns (never trap the user), and syncs the Earn Meter.
    public func reconcile(now: Date = .now) async {
        let engine = LockEngineManager.shared
        await LockSetManager.shared.refreshMonitorMirrors()

        let ends = LockEngineSharedState.pendingEnds
        LockEngineSharedState.pendingEnds = []
        for end in ends {
            try? await engine.endLock(sessionID: end.sessionID, unlockKind: .scheduleEnd, at: end.endedAt)
        }

        let finished = LockEngineSharedState.finishedPendingLocks
        LockEngineSharedState.finishedPendingLocks = []
        for record in finished { engine.recordFinishedScheduledLock(record) }

        if let pending = LockEngineSharedState.pendingStart {
            LockEngineSharedState.pendingStart = nil
            await convert(pending, now: now)
        }

        engine.restoreShieldIfSpendWindowExpired(now: now)
        engine.removeShieldIfNoActiveLock()
        await engine.syncEarnMeter()
        LockEngineSharedState.refreshNextScheduledLockAt(now: now)
    }

    private func convert(_ pending: PendingScheduledLock, now: Date) async {
        let engine = LockEngineManager.shared
        switch pending.source {
        case .bedtime:
            do {
                _ = try await BedtimeGateManager.shared.autoArmBedtimeLock(trigger: .schedule, now: now)
            } catch {
                logger.error("Bedtime hand-off failed: \(String(describing: error), privacy: .public)")
            }
        case .schedule:
            guard let lockSetID = pending.lockSetID else { return }
            var sessionID: UUID?
            do {
                let goals = try pending.requiredGoalIDs ?? engine.activeGoalIDsForCurrentUser()
                sessionID = try await engine.startLock(
                    lockSetID: lockSetID,
                    mode: pending.mode,
                    requiredGoalIDs: goals,
                    trigger: .schedule,
                    startedAt: pending.startedAt
                )
            } catch LockEngineError.deviceActivitySchedulingFailed {
                // The session exists; only the rest-of-day keep-alive registration failed.
                sessionID = SharedDefaults.activeLockSessionID
            } catch {
                logger.error("Scheduled lock hand-off failed: \(String(describing: error), privacy: .public)")
            }
            guard let sessionID else { return }
            LockEngineSharedState.scheduleOwnedLock = ScheduleOwnedLock(
                sessionID: sessionID,
                lockSetID: lockSetID,
                activityRawName: pending.activityRawName
            )
            // Goals may already be done (applies partial tiers too).
            if await engine.evaluateUnlockEligibility(sessionID: sessionID) {
                try? await engine.endLock(sessionID: sessionID, unlockKind: .earned)
            }
        }
    }

    // MARK: DeviceActivity

    private func register(_ schedule: LockSchedule) throws {
        stopMonitoring(lockSetID: schedule.lockSetID)
        guard schedule.isEnabled else { return }
        var registered: [DeviceActivityName] = []
        do {
            for window in schedule.deviceActivityWindows {
                let name = LockScheduleActivity.name(lockSetID: schedule.lockSetID, weekday: window.weekday)
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
            throw LockSchedulerError.deviceActivityRegistrationFailed(reason: String(describing: error))
        }
    }

    private func stopMonitoring(lockSetID: UUID) {
        let names = activityCenter.activities.filter {
            LockScheduleActivity.lockSetID(fromRawName: $0.rawValue) == lockSetID
        }
        if !names.isEmpty { activityCenter.stopMonitoring(names) }
    }
}
