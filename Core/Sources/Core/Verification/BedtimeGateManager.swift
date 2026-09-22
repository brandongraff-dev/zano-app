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
//     below applies the exact same idempotency guard, so `SunriseAlarmManager`'s other three
//     dismiss variants (Steps/Focus/Squad, this task's own file) get the identical "arm once,
//     never double-arm" behavior that Tag dismiss already has, without duplicating
//     `SunriseKeyIntent`'s logic — this is that logic's one other legitimate call site, not a
//     second competing implementation of it.
//
// Cross-module integration points (same shape/convention as `GymDwellActivityAttributes`'s,
// `FocusActivityAttributes`'s, and `EarnMeterActivityManager`'s own documented TODOs — real,
// working code on this side, an explicit, narrow gap on the other side):
//   - `Extensions/ZANOMonitor`'s `DeviceActivityMonitor` subclass (a different target, not owned by
//     this task) should call `BedtimeGateManager.shared.autoArmBedtimeLock(trigger: .schedule)`
//     from its `intervalDidStart(for:)` when `activity == .zanoBedtimeGate` — that is the correct,
//     "fires even if the app isn't running" trigger for this feature. Until that one call is
//     wired, `evaluateOnForeground(now:)` below is the honest fallback this file *can* build:
//     called from app launch/foreground (also not this task's file to wire — `App/ZANO/ZANOApp.swift`
//     — but a one-line, well-precedented call, matching `ShieldCopy`'s own "the deep link exists,
//     the `onOpenURL` handler is a TODO" pattern), it catches up on a bedtime that passed while the
//     app was closed.
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
import os

// MARK: - Settings

/// User-configurable Bedtime Gate settings (spec §5.10). Persisted as a small JSON blob in the
/// App Group's shared `UserDefaults` suite under this file's own key — the same storage pattern
/// `NFCTagMapper.swift` and `SquadManager.swift`'s shared-freeze state already establish for
/// "device-local configuration with nothing in `Core/Sources/Core/Models`/§13's frozen Data Model
/// table to mirror it" (bedtime settings appear nowhere in spec §13's table, and adding a column
/// there is Session 1's Models file to extend, not this task's to guess at — flagged in
/// knownIssues). Deliberately **not** added to `Store/SharedDefaults.swift`: that file is owned by
/// a different session, and per its own header comment it's a flat "one value per key" mirror for
/// state an extension needs to render *instantly* — this is multi-field configuration read only by
/// this manager and (indirectly) by whichever future settings screen edits it.
public struct BedtimeGateSettings: Codable, Sendable, Equatable {
    /// Whether the Bedtime Gate is turned on at all. `false` by default — this is an opt-in
    /// feature the user turns on during Sunrise Alarm/Bedtime setup, never a silent default lock.
    public var enabled: Bool
    /// Local wall-clock hour (0–23) the lock auto-arms.
    public var bedtimeHour: Int
    /// Local wall-clock minute (0–59).
    public var bedtimeMinute: Int
    /// Spec §5.10: "Optional wind-down Live Activity." On by default once the Gate itself is
    /// enabled — it's the softer, advance-notice half of the feature.
    public var windDownEnabled: Bool
    /// Minutes of advance notice — spec §5.10's own example is "10 min".
    public var windDownLeadMinutes: Int
    /// Which `LockSet` to arm at bedtime. `nil` means "the user's default `LockSet`" (resolved via
    /// `LockSetManager.shared.defaultLockSet(for:)` at arm time, never re-guessed here).
    public var lockSetID: UUID?
    /// Which goals must be verified to earn the way out of the bedtime-armed lock. `nil` means
    /// "every currently-active goal" (`IntentSupport.activeGoalIDs(for:in:)`), matching
    /// `SunriseKeyIntent`'s own default for its own auto-armed lock.
    public var requiredGoalIDs: [UUID]?
    /// `.full` (hard block until goals earned) vs `.earn` (Time Bank). Spec §5.10 describes the
    /// Bedtime Gate as a hard lock ("phone becomes a clock") — `.full` is the correct default; kept
    /// configurable rather than hardcoded so a future Earn-Mode-at-night variant isn't blocked on
    /// changing this struct's shape.
    public var mode: LockMode

    public init(
        enabled: Bool = false,
        bedtimeHour: Int = 22,
        bedtimeMinute: Int = 30,
        windDownEnabled: Bool = true,
        windDownLeadMinutes: Int = 10,
        lockSetID: UUID? = nil,
        requiredGoalIDs: [UUID]? = nil,
        mode: LockMode = .full
    ) {
        self.enabled = enabled
        self.bedtimeHour = bedtimeHour
        self.bedtimeMinute = bedtimeMinute
        self.windDownEnabled = windDownEnabled
        self.windDownLeadMinutes = windDownLeadMinutes
        self.lockSetID = lockSetID
        self.requiredGoalIDs = requiredGoalIDs
        self.mode = mode
    }

    public static let `default` = BedtimeGateSettings()
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

// MARK: - DeviceActivity naming (this file's own extension member — additive, does not touch
// `LockEngine/LockEngineManager.swift`'s own `DeviceActivityName` extension in the same type)

extension DeviceActivityName {
    /// The recurring daily `DeviceActivityCenter` registration for the Bedtime Gate's auto-arm —
    /// see this file's header comment for the `ZANOMonitor` wiring this name is meant for.
    static let zanoBedtimeGate = DeviceActivityName("com.zano.app.bedtimeGate")
}

// MARK: - BedtimeGateManager

/// Owns Bedtime Gate settings, the recurring bedtime schedule, the wind-down Live Activity, and
/// the "arm the day's lock automatically" call both the bedtime side (`autoArmBedtimeLock`) and
/// the Sunrise Alarm's dismiss flow (`armDayLockAfterWake`, called from `SunriseAlarmManager`,
/// this same task) share.
///
/// `@MainActor`, matching `LockEngineManager`/`FocusSessionVerifier`/`EarnMeterActivityManager`'s
/// identical reasoning: this type owns a `DeviceActivityCenter` and an ActivityKit `Activity`,
/// both Apple APIs whose own sample code always drives them from the main actor, and every real
/// call site (SwiftUI settings screens, `SunriseAlarmManager`'s own `@MainActor` methods, and —
/// once wired — `ZANOMonitor`) is already on/happy to hop to the main actor.
@MainActor
public final class BedtimeGateManager {
    public static let shared = BedtimeGateManager()

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "BedtimeGateManager")

    private var windDownActivity: Activity<BedtimeWindDownActivityAttributes>?

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container — mirrors `LockEngineManager`/`FocusSessionVerifier`'s identical
    /// testability convention. Every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup, activityCenter: DeviceActivityCenter = DeviceActivityCenter()) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.activityCenter = activityCenter
    }

    // MARK: - Settings persistence

    public func settings() -> BedtimeGateSettings {
        guard
            let data = Self.defaults.data(forKey: Self.settingsKey),
            let decoded = try? JSONDecoder().decode(BedtimeGateSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    /// Persists new settings and, if enabled, re-registers the recurring `DeviceActivity`
    /// schedule so a bedtime-time change takes effect for tonight rather than tomorrow's stale
    /// registration. Never throws: `DeviceActivityCenter.startMonitoring` failing here is
    /// best-effort exactly like `LockEngineManager.armScheduleMonitoring`'s own non-fatal
    /// handling — the settings themselves are still saved and `evaluateOnForeground`'s catch-up
    /// path still works without the recurring registration.
    public func updateSettings(_ newSettings: BedtimeGateSettings) {
        guard let data = try? JSONEncoder().encode(newSettings) else { return }
        Self.defaults.set(data, forKey: Self.settingsKey)

        if newSettings.enabled {
            do { try rearmDailySchedule(settings: newSettings) }
            catch {
                logger.error("updateSettings: DeviceActivity re-registration failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            activityCenter.stopMonitoring([.zanoBedtimeGate])
        }
    }

    // MARK: - Recurring schedule (see header comment: the correct, not-yet-wired trigger path)

    /// Registers (or replaces) a repeating daily `DeviceActivitySchedule` starting at the
    /// configured bedtime, mirroring `LockEngineManager.armScheduleMonitoring`'s exact
    /// `DeviceActivitySchedule` construction shape (same `DateComponents` pattern, this file's
    /// only real point of uncertainty about the live `DeviceActivity` API surface being the same
    /// one that file already flags — see this task's knownIssues) with two differences: the
    /// interval starts at bedtime rather than "now," and `repeats: true` since this needs to fire
    /// every night, not once.
    public func rearmDailySchedule(settings: BedtimeGateSettings? = nil) throws {
        let settings = settings ?? self.settings()
        var start = DateComponents()
        start.hour = settings.bedtimeHour
        start.minute = settings.bedtimeMinute
        start.second = 0
        var end = DateComponents()
        end.hour = 23
        end.minute = 59
        end.second = 59
        let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
        try activityCenter.startMonitoring(.zanoBedtimeGate, during: schedule)
    }

    public func disableDailySchedule() {
        activityCenter.stopMonitoring([.zanoBedtimeGate])
    }

    // MARK: - Foreground catch-up (the honest fallback while the DeviceActivityMonitor wiring is a TODO)

    /// Call whenever the app becomes active/launches. Starts the wind-down Live Activity if
    /// `now` falls inside its window and it hasn't started yet tonight, and arms tonight's lock
    /// if bedtime already passed today and this device hasn't armed it yet — exactly what a real
    /// `intervalDidStart` callback would have done, just running late (only as late as the next
    /// time the app is opened, which is an honest, documented degradation, not silent breakage).
    public func evaluateOnForeground(now: Date = .now) async {
        let settings = settings()
        guard settings.enabled else { return }

        if settings.windDownEnabled, isWithinWindDownWindow(settings: settings, now: now) {
            await startWindDownIfNeeded(settings: settings, now: now)
        }
        if isPastBedtimeToday(settings: settings, now: now) {
            _ = try? await autoArmBedtimeLock(trigger: .schedule, now: now)
        }
    }

    // MARK: - Auto-arm (spec §5.10: "Lock auto-arms at the user's set bedtime")

    /// Arms tonight's lock. Idempotent per calendar day (checked via `hasArmedToday`) so both the
    /// (documented-TODO) `DeviceActivityMonitor` callback and this file's own foreground catch-up
    /// can safely call this without ever double-arming.
    ///
    /// Escape hatch: deliberately not reimplemented here. The `LockSession` this starts is an
    /// ordinary session (`LockEngineManager.startLock`), so `LockEngine/EmergencyUnlock.swift`'s
    /// existing 60-second hold already applies to it exactly like any other lock — spec §24 point
    /// 2 / CLAUDE.md's "never trap the user" is satisfied by *reusing* that path, not by this file
    /// inventing a second one (a second, subtly-different emergency-unlock implementation would be
    /// the actual risk here, not a missing one).
    ///
    /// - Returns: the new `LockSession.id`, or `nil` if the Gate is disabled, already armed today,
    ///   or a lock is already active for some other reason (never double-arms on top of an
    ///   existing session).
    @discardableResult
    public func autoArmBedtimeLock(trigger: LockTrigger = .schedule, now: Date = .now) async throws -> UUID? {
        let settings = settings()
        guard settings.enabled else { return nil }
        guard !hasArmedToday(asOf: now) else { return nil }

        let user = try fetchCurrentUser()
        guard try IntentSupport.activeLockSession(for: user.id, in: context) == nil else {
            // Something else already has a lock running (e.g. a manual lock, or last night's
            // bedtime lock still active past midnight) — never stack a second shield on top.
            markArmedToday(now: now)
            return nil
        }

        let lockSetID = try await resolveLockSetID(settings: settings, userID: user.id)
        let requiredGoalIDs = try settings.requiredGoalIDs ?? IntentSupport.activeGoalIDs(for: user.id, in: context)

        let sessionID = try await LockEngineManager.shared.startLock(
            lockSetID: lockSetID,
            mode: settings.mode,
            requiredGoalIDs: requiredGoalIDs,
            trigger: trigger
        )
        markArmedToday(now: now)
        await endWindDownActivity(isLocked: true, now: now)
        Analytics.shared.capture(event: "bedtime_gate_armed", properties: ["trigger": trigger.rawValue])
        logger.notice("Auto-armed Bedtime Gate lock \(sessionID.uuidString, privacy: .public).")
        return sessionID
    }

    // MARK: - Day-lock arming after wake (spec §5.10 step 4: "the day's lock arms automatically" —
    // the call site the task brief names explicitly: "call BedtimeGateManager/LockEngineManager")

    /// The `SunriseAlarmManager` (this same task) call site for its Steps/Focus/Squad dismiss
    /// variants — the exact "arm the day's lock, but only if nothing already has" behavior
    /// `SunriseKeyIntent.perform()` (not owned by this task) already implements inline for its own
    /// Tag-dismiss path. Kept here, not duplicated in `SunriseAlarmManager`, so both call sites
    /// share one implementation of "how does a verified morning dismiss arm today's lock."
    ///
    /// - Returns: the new `LockSession.id`, or `nil` if a lock is already active (nothing to arm)
    ///   or no `User`/`LockSet` can be resolved.
    @discardableResult
    public func armDayLockAfterWake(requiredGoalIDs: [UUID]? = nil, mode: LockMode = .full, now: Date = .now) async -> UUID? {
        guard let user = try? fetchCurrentUser() else { return nil }
        guard (try? IntentSupport.activeLockSession(for: user.id, in: context)) == nil else { return nil }

        guard let lockSetID = try? await resolveLockSetID(settings: settings(), userID: user.id) else { return nil }
        let goalIDs = (try? requiredGoalIDs ?? IntentSupport.activeGoalIDs(for: user.id, in: context)) ?? []

        let sessionID = try? await LockEngineManager.shared.startLock(
            lockSetID: lockSetID,
            mode: mode,
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

    public func startWindDownIfNeeded(settings: BedtimeGateSettings? = nil, now: Date = .now) async {
        let settings = settings ?? self.settings()
        guard settings.enabled, settings.windDownEnabled else { return }
        guard windDownActivity == nil else {
            await updateWindDownActivity(settings: settings, now: now)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities disabled; running wind-down without one.")
            return
        }

        let minutesRemaining = minutesUntilBedtime(settings: settings, now: now)
        let attributes = BedtimeWindDownActivityAttributes(bedtimeLabel: Self.bedtimeLabel(settings: settings))
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

    public func updateWindDownActivity(settings: BedtimeGateSettings? = nil, now: Date = .now) async {
        guard let windDownActivity else { return }
        let settings = settings ?? self.settings()
        let minutesRemaining = minutesUntilBedtime(settings: settings, now: now)
        let content = ActivityContent(
            state: BedtimeWindDownActivityAttributes.ContentState(minutesUntilBedtime: max(0, minutesRemaining), isLocked: false),
            staleDate: nil
        )
        await windDownActivity.update(content)
    }

    public func endWindDownActivity(isLocked: Bool, now: Date = .now) async {
        guard let activity = windDownActivity else { return }
        windDownActivity = nil
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
        let settings = settings()
        guard settings.enabled else { return }
        guard let nightStart = bedtimeAnchor(settings: settings, coveringPickupAt: date) else { return }
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

    private func hasPickupMissLogged(goalID: UUID, forNightOf nightStart: Date) -> Bool {
        guard let nightEnd = Calendar.current.date(byAdding: .day, value: 1, to: nightStart) else { return false }
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.kind == .miss && $0.ts >= nightStart && $0.ts < nightEnd }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains {
            $0.goal?.id == goalID && $0.source == .manual
        }
    }

    // MARK: - Time helpers

    private func bedtimeDate(settings: BedtimeGateSettings, on date: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = settings.bedtimeHour
        components.minute = settings.bedtimeMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func isPastBedtimeToday(settings: BedtimeGateSettings, now: Date) -> Bool {
        guard let bedtime = bedtimeDate(settings: settings, on: now) else { return false }
        return now >= bedtime
    }

    private func isWithinWindDownWindow(settings: BedtimeGateSettings, now: Date) -> Bool {
        guard let bedtime = bedtimeDate(settings: settings, on: now) else { return false }
        let windDownStart = bedtime.addingTimeInterval(-Double(settings.windDownLeadMinutes) * 60)
        return now >= windDownStart && now < bedtime
    }

    private func minutesUntilBedtime(settings: BedtimeGateSettings, now: Date) -> Int {
        guard let bedtime = bedtimeDate(settings: settings, on: now) else { return 0 }
        return max(0, Int((bedtime.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// The most recent bedtime at/before `date`, treating the "night" as starting at bedtime and
    /// running until the next day's bedtime — used to check a pickup timestamp against the bedtime
    /// that actually governs it, whether that bedtime was earlier tonight or (for a pickup in the
    /// small hours) yesterday evening. `nil` when `date` is more than 24h after any resolvable
    /// bedtime, which never happens for a real "just picked up the phone" call.
    private func bedtimeAnchor(settings: BedtimeGateSettings, coveringPickupAt date: Date, calendar: Calendar = .current) -> Date? {
        guard let todayBedtime = bedtimeDate(settings: settings, on: date, calendar: calendar) else { return nil }
        if date >= todayBedtime { return todayBedtime }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return bedtimeDate(settings: settings, on: yesterday, calendar: calendar)
    }

    private static func bedtimeLabel(settings: BedtimeGateSettings) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = settings.bedtimeHour
        components.minute = settings.bedtimeMinute
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? .now
        return formatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    // MARK: - Resolving what to arm

    private func resolveLockSetID(settings: BedtimeGateSettings, userID: UUID) async throws -> UUID {
        if let lockSetID = settings.lockSetID { return lockSetID }
        if let defaultSet = try await LockSetManager.shared.defaultLockSet(for: userID) {
            return defaultSet.id
        }
        throw BedtimeGateError.noLockSetAvailable
    }

    // MARK: - "Armed today" idempotency (own App Group UserDefaults key — see settings' doc comment)

    private func hasArmedToday(asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let stored = Self.defaults.object(forKey: Self.lastArmedDayKey) as? Date else { return false }
        return calendar.isDate(stored, inSameDayAs: date)
    }

    private func markArmedToday(now: Date) {
        Self.defaults.set(now, forKey: Self.lastArmedDayKey)
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

    // MARK: - Storage

    /// Mirrors `NFCTagMapper`/`SquadManager`'s identical `nonisolated(unsafe)` App Group
    /// `UserDefaults` fallback pattern (see either file's doc comment for the full rationale).
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private static let settingsKey = "core.bedtimeGate.settings.v1"
    private static let lastArmedDayKey = "core.bedtimeGate.lastArmedDay.v1"
}
