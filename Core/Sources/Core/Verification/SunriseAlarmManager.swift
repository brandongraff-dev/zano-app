// Core/Sources/Core/Verification/SunriseAlarmManager.swift
//
// docs/spec.md §5.10 ★ Bedtime Gate & Sunrise Alarm — the Sunrise Alarm half ("the alarm you can
// only kill by getting up"): fires with escalating sound/haptics; the only default dismiss is
// tapping the physical Sunrise Tag; a single 5-min snooze exists but otherwise breaks the morning
// goal; a successful dismiss turns the alarm off, verifies the morning goal, and arms the day's
// lock automatically; distracting apps stay locked from wake until the day's goals are earned;
// and there is always a 60-second-hold "I'm not home" escape hatch — no one gets trapped.
// docs/spec.md §3 "Morning routine / Sunrise Alarm" row (Tier A): verified by tapping the Sunrise
// Tag before a cutoff, with Steps/Focus as fallbacks; anti-cheat: "Tag must be physically scanned
// (proximity); snooze limited to 1."
// docs/spec.md §24 point 2 ("Emergency access... provide an in-app emergency unlock with a short
// hold. Never trap users.") and CLAUDE.md's mirror of it: "Any lock/alarm feature must always keep
// an escape hatch — never trap the user."
//
// IMPORTANT — real-consumer reconciliation (see this task's `decisions`): `App/ZANO/Features/
// SunriseAlarm/{AlarmRingingView,SunriseAlarmSetupView,BedtimeGateSetupView}.swift` already exist
// on disk (an earlier wave's session, not this task's to edit) and already call a `SunriseAlarmManager`
// against a fully-specified "ASSUMED API" documented in their own header comments. That is the
// real, already-built consumer of this file, so this file's public shape matches that ASSUMED API
// as closely as the real spec §5.10 requirements allow — not a shape invented independently of it
// — specifically:
//   - `@MainActor @Observable` (not a plain `@MainActor final class`): `AlarmRingingView` reads
//     `manager.isRinging`/`.ringingSince`/`.snoozesRemainingToday`/`.stepsWalked` as live
//     `@Observable`-tracked state (`.onChange(of: manager.isRinging)`, `.task(id: manager.
//     stepsWalked)`), not as values it re-fetches itself.
//   - Nested `DismissVariant`/`EscapeReason`/`Settings` types, `currentSettings()`/`saveSettings(_:)`,
//     and the exact `dismissViaTag(tagID:)`/`dismissViaSteps()`/`dismissViaFocusCompletion()`/
//     `dismissViaSquadConfirmation()`/`snooze()`/`triggerEscapeHatch(reason:)` method set — all
//     matched signature-for-signature against `SunriseAlarmSetupView.swift`'s documented block.
//   - `Settings` carries **both** `bedtime` and `wakeTime` in one shared row (`BedtimeGateSetupView`'s
//     own header: "This screen owns exactly the bedtime + wind-down-reminder half of the shared
//     `SunriseAlarmManager.Settings` row... since the two are one feature (spec §5.10) presented as
//     companion screens"). `BedtimeGateManager` (this same task) reads bedtime/wind-down from here
//     rather than owning a second, competing settings blob — see that file's own header.
//   - One gap in the documented ASSUMED `Settings`: neither setup screen exposes an on/off toggle,
//     yet spec §5.10 frames this as opt-in. `enabled: Bool` is added as an *additional*, trailing,
//     defaulted parameter (`= true`) so `Settings()` — exactly what both screens already call —
//     keeps compiling unchanged; there is simply no UI yet to turn it off. Flagged in knownIssues,
//     not silently resolved.
//   - What is *not* reconciled: `Core/Sources/Core/Copy`'s real, established convention (this
//     codebase's `ShieldCopy`/`NFCTagSetupInstructions`/etc. — flat, top-level, one enum per
//     feature) versus the three App-layer files' own `Copy.<screen>.<key>` nested-namespace guess.
//     This task was explicitly told to own `Core/Sources/Core/Copy/SunriseAlarmCopy.swift` as that
//     same flat, top-level shape (see that file), which this codebase's real Copy files all use —
//     inventing a ~70-key `Copy` umbrella enum under a different, non-established naming
//     convention is a different, much larger task than this one's three-file scope, and would
//     likely conflict with whichever session actually owns that umbrella. Flagged in knownIssues
//     for whoever reconciles those three App files' Copy references.
//
// This task's other required reading shaped two more decisions, at their call sites below:
//   - `LockEngineManager.startLock(...)` is never called directly from here — `BedtimeGateManager.
//     armDayLockAfterWake(...)` (this same task) is, per this task's own brief ("days lock arms
//     automatically — call BedtimeGateManager/LockEngineManager"), matching the same "arm once,
//     only if nothing already has" guard `SunriseKeyIntent.perform()` (not owned by this task)
//     already implements inline for its own Tag-dismiss path.
//   - `dismissViaTag(tagID:)` never re-logs the `.complete` GoalEvent `SunriseKeyIntent.perform()`
//     already wrote for a Tag dismiss (`AlarmRingingView`'s own two-step handshake: `NFCTagMapper.
//     shared.scanAndHandle` dispatches to the real `SunriseKeyIntent` first, *then* calls this
//     method) — it only silences this file's own alarm mechanics (notifications/AlarmKit/Live
//     Activity/monitoring), which that call chain has no way to reach.

import Foundation
import SwiftData
import UserNotifications
import CoreMotion
import ActivityKit
import AppIntents
import Observation
#if canImport(AlarmKit)
import AlarmKit
#endif
import os

// MARK: - AlarmKit "open app" stop-button intent (best-effort — see `scheduleViaAlarmKit`)

/// The App Intent AlarmKit's system alert "stop" button invokes on the AlarmKit tier. Deliberately
/// does *not* silently stop the alarm: spec §5.10 requires the alarm to keep running until the
/// configured dismiss variant is actually verified, so this button is wayfinding into the app's
/// dismiss flow (`AlarmRingingView`), not the real dismiss. `SunriseAlarmManager.completeDismiss`
/// is what actually calls `AlarmManager.shared.stop(id:)` once verification succeeds. Defined at
/// file scope (not inside the `#if canImport(AlarmKit)` block below) because `AppIntent` itself
/// ships independently of AlarmKit — this type compiles and is inert on every iOS version.
public struct SunriseAlarmOpenAppIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open ZANO"
    public static let openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Ringing Live Activity (notification-fallback tier only — spec §5.10: "iOS 17–18
// fallback: ... plus a Live Activity." The AlarmKit tier's own system alert already is the
// "Live-Activity-style alert UI" spec §5.10 describes, so this is never started alongside it.)

/// Kept in this file rather than a fourth `Core/Sources/Core/LiveActivity` file — this task's file
/// list names exactly one new LiveActivity file (`BedtimeWindDownActivityAttributes.swift`). Every
/// field below is a plain `String`/`Int`/`Bool`, mirroring every sibling `ActivityAttributes`
/// type's shape exactly.
public struct SunriseAlarmRingingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var secondsSinceRinging: Int
        public var snoozeAvailable: Bool
        /// `SunriseAlarmManager.DismissVariant.rawValue` — kept as a plain `String` (not the enum
        /// itself) so this Activity's content-state shape never has to change if that enum's cases
        /// do.
        public var dismissVariant: String

        public init(secondsSinceRinging: Int, snoozeAvailable: Bool, dismissVariant: String) {
            self.secondsSinceRinging = secondsSinceRinging
            self.snoozeAvailable = snoozeAvailable
            self.dismissVariant = dismissVariant
        }
    }

    public var wakeHourMinuteLabel: String

    public init(wakeHourMinuteLabel: String) {
        self.wakeHourMinuteLabel = wakeHourMinuteLabel
    }
}

// MARK: - SunriseAlarmManager

/// `@MainActor @Observable` — see this file's header `decisions` note: matches `AlarmRingingView`'s
/// live state-reading exactly, and `@Observable` on a `@MainActor final class` is the same pattern
/// `LockEngine/EmergencyUnlock.swift` already establishes in this codebase.
@MainActor
@Observable
public final class SunriseAlarmManager {
    public static let shared = SunriseAlarmManager()

    // MARK: Nested types (ASSUMED API shape — see header)

    public enum DismissVariant: String, Codable, Sendable, CaseIterable {
        case tag
        case steps
        case focus
        case squad
    }

    public enum EscapeReason: String, Codable, Sendable {
        case imNotHome
        case other
    }

    public struct Settings: Codable, Sendable, Equatable {
        public var bedtime: Date
        public var wakeTime: Date
        public var dismissVariant: DismissVariant
        public var windDownReminderEnabled: Bool
        /// Spec §5.10: "walk N steps" without a pinned N; `40` is this file's own assumption (a
        /// short real walk, not a workout) — flagged in knownIssues exactly like `TapRateLimiter.
        /// Policy.protein`'s own flagged daily-cap guess.
        public var stepsTarget: Int
        public var squadIDToNotify: UUID?
        /// Additional field beyond the documented ASSUMED shape — see this file's header
        /// `decisions` note. Trailing + defaulted so `Settings()` (both setup screens' exact call)
        /// keeps compiling unchanged.
        public var enabled: Bool
        /// Weekdays the alarm rings (`Calendar` weekday numbers, 1 = Sunday). Empty = "Never": it
        /// rings once, at the next wake time, then switches itself off (like the Clock app).
        public var repeatDays: Set<Int>
        /// The wake-up sound (bundled tones, `AlarmSoundChoice`).
        public var sound: AlarmSoundChoice
        /// A plain second alarm that rings `backupMinutes` after the Sunrise Alarm if you haven't
        /// got up. Cancelled by a verified dismiss or the escape hatch. Off by default.
        public var backupAlarmEnabled: Bool
        public var backupMinutes: Int

        /// The backup delays offered in the picker.
        public static let backupMinuteOptions = [5, 10, 15]

        public init(
            bedtime: Date = Settings.defaultTime(hour: 22, minute: 30),
            wakeTime: Date = Settings.defaultTime(hour: 6, minute: 30),
            dismissVariant: DismissVariant = .tag,
            windDownReminderEnabled: Bool = true,
            stepsTarget: Int = 40,
            squadIDToNotify: UUID? = nil,
            enabled: Bool = true,
            repeatDays: Set<Int> = RepeatDays.everyDay,
            sound: AlarmSoundChoice = .daybreak,
            backupAlarmEnabled: Bool = false,
            backupMinutes: Int = 10
        ) {
            self.repeatDays = repeatDays
            self.sound = sound
            self.backupAlarmEnabled = backupAlarmEnabled
            self.backupMinutes = backupMinutes
            self.bedtime = bedtime
            self.wakeTime = wakeTime
            self.dismissVariant = dismissVariant
            self.windDownReminderEnabled = windDownReminderEnabled
            self.stepsTarget = stepsTarget
            self.squadIDToNotify = squadIDToNotify
            self.enabled = enabled
        }

        private enum CodingKeys: String, CodingKey {
            case bedtime, wakeTime, dismissVariant, windDownReminderEnabled, stepsTarget
            case squadIDToNotify, enabled, repeatDays, sound, backupAlarmEnabled, backupMinutes
        }

        /// Custom decoding so a row saved before repeat days, sounds and the backup alarm existed
        /// still loads: the new keys are optional and fall back to the old behaviour (every day,
        /// the first sound, no backup). Synthesized decoding would throw on the missing keys, and
        /// `currentSettings()` would silently hand back defaults, wiping the person's alarm.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bedtime = try container.decode(Date.self, forKey: .bedtime)
            wakeTime = try container.decode(Date.self, forKey: .wakeTime)
            dismissVariant = try container.decode(DismissVariant.self, forKey: .dismissVariant)
            windDownReminderEnabled = try container.decode(Bool.self, forKey: .windDownReminderEnabled)
            stepsTarget = try container.decode(Int.self, forKey: .stepsTarget)
            squadIDToNotify = try container.decodeIfPresent(UUID.self, forKey: .squadIDToNotify)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            repeatDays = try container.decodeIfPresent(Set<Int>.self, forKey: .repeatDays) ?? RepeatDays.everyDay
            sound = try container.decodeIfPresent(AlarmSoundChoice.self, forKey: .sound) ?? .daybreak
            backupAlarmEnabled = try container.decodeIfPresent(Bool.self, forKey: .backupAlarmEnabled) ?? false
            backupMinutes = try container.decodeIfPresent(Int.self, forKey: .backupMinutes) ?? 10
        }

        public static func defaultTime(hour: Int, minute: Int) -> Date {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            return Calendar.current.date(from: components) ?? .now
        }
    }

    // MARK: Live ringing state (ASSUMED API — read by `AlarmRingingView` via `@Observable` tracking)

    public private(set) var isRinging: Bool = false
    public private(set) var ringingSince: Date?
    public private(set) var snoozesRemainingToday: Int = SunriseAlarmEngineDefaults.maxSnoozes
    public private(set) var stepsWalked: Int = 0

    // MARK: Private state

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "SunriseAlarmManager")

    /// `CMPedometer` predates Swift 6 and isn't SDK-marked `Sendable`; `nonisolated(unsafe)`
    /// mirrors `MotionAntiCheat.manager`'s identical, fully-documented rationale in this same
    /// directory — created once, never reassigned, only ever touched from this `@MainActor` type.
    nonisolated(unsafe) private let pedometer = CMPedometer()
    private var stepsMonitoringActive = false

    private var ringingActivity: Activity<SunriseAlarmRingingActivityAttributes>?
    private var squadNotifyTask: Task<Void, Never>?

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
    }

    // MARK: - Settings (ASSUMED API)

    /// Whether the person ever saved Sunrise Alarm / Bedtime Gate settings (`saveSettings`).
    /// `Settings.enabled` defaults to `true`, so this — not `enabled` — is what tells an app
    /// foreground hook it may keep the alarm scheduled: someone who never opened the setup screen
    /// never gets a surprise 06:30 alarm (spec §5.10 frames the feature as opt-in). Reads one App
    /// Group key; `nonisolated` so any caller can ask without a hop. Cleared by `resetAll()`.
    public nonisolated static var hasBeenConfigured: Bool {
        defaults.data(forKey: settingsKey) != nil
    }

    /// The saved settings row, or `nil` if it was never set up (unlike `currentSettings()`, which
    /// hands back defaults). Nonisolated, one App Group read, so `ZANOMonitor` can read bedtime and
    /// wake time without the main actor (`BedtimeGateSharedState.currentSchedule`, session 38).
    public nonisolated static func storedSettings() -> Settings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    public func currentSettings() async -> Settings {
        guard
            let data = Self.defaults.data(forKey: Self.settingsKey),
            let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            return Settings()
        }
        return decoded
    }

    /// Saves the shared settings row and immediately reschedules both halves of the feature: the
    /// wake alarm itself (this file) and the Bedtime Gate's recurring daily schedule
    /// (`BedtimeGateManager`, this same task) — a bedtime/wake-time/variant change takes effect
    /// for tonight, not just future nights.
    public func saveSettings(_ newSettings: Settings) async throws {
        guard let data = try? JSONEncoder().encode(newSettings) else {
            throw SunriseAlarmError.dismissConditionNotMet(reason: "Could not encode Sunrise Alarm settings.")
        }
        Self.defaults.set(data, forKey: Self.settingsKey)
        _ = await scheduleAlarm()
        do { try await BedtimeGateManager.shared.rearmDailySchedule() }
        catch { logger.error("saveSettings: Bedtime Gate re-registration failed: \(String(describing: error), privacy: .public)") }
    }

    // MARK: - Schedule (spec §5.10 "Technical path")

    /// Computes tonight/tomorrow's fire time from `Settings.wakeTime`, clears any previous
    /// scheduling for this alarm, and schedules via AlarmKit (iOS 26+, best-effort) or the
    /// local-notification chain (17–18 fallback), recording which tier actually got used.
    ///
    /// - Returns: the scheduled fire date, or `nil` if the alarm is disabled (in which case any
    ///   previous scheduling is torn down instead).
    @discardableResult
    public func scheduleAlarm(now: Date = .now) async -> Date? {
        let settings = await currentSettings()
        guard settings.enabled else {
            await cancelAlarm(reason: .disabled)
            clearDailyState()
            isRinging = false
            ringingSince = nil
            return nil
        }

        let wakeComponents = Calendar.current.dateComponents([.hour, .minute], from: settings.wakeTime)
        let fireDate = Self.nextFireDate(
            hour: wakeComponents.hour ?? 6,
            minute: wakeComponents.minute ?? 30,
            after: now,
            repeatDays: settings.repeatDays
        )
        let dayKey = Self.dayKey(for: fireDate)

        await cancelPendingNotifications()
        await cancelBackupAlarm()
        if #available(iOS 26.0, *) { await stopAlarmKitAlarmIfNeeded() }
        await endRingingActivity(now: now)
        stopStepsDismissMonitoring()
        squadNotifyTask?.cancel(); squadNotifyTask = nil
        isRinging = false
        ringingSince = nil

        var tier: SunriseAlarmTier = .notifications
        var scheduledViaAlarmKit = false
        if #available(iOS 26.0, *) {
            do {
                try await scheduleViaAlarmKit(fireDate: fireDate, variant: settings.dismissVariant, sound: settings.sound)
                tier = .alarmKit
                scheduledViaAlarmKit = true
            } catch {
                logger.error("AlarmKit scheduling failed, falling back to notifications: \(String(describing: error), privacy: .public)")
            }
        }
        if !scheduledViaAlarmKit {
            await scheduleNotificationFallback(fireDate: fireDate, dayKey: dayKey, variant: settings.dismissVariant, sound: settings.sound)
        }
        if settings.backupAlarmEnabled {
            await scheduleBackupAlarm(after: fireDate, minutes: settings.backupMinutes, sound: settings.sound)
        }

        saveDailyState(DailyState(dayKey: dayKey, fireDate: fireDate, tier: tier, snoozeCount: 0, dismissedAt: nil))
        snoozesRemainingToday = SunriseAlarmEngineDefaults.maxSnoozes

        Analytics.shared.capture(event: "sunrise_alarm_scheduled", properties: ["tier": tier.rawValue])
        logger.notice("Scheduled sunrise alarm for \(fireDate.description, privacy: .public) via \(tier.rawValue, privacy: .public).")
        return fireDate
    }

    // MARK: - AlarmKit (iOS 26+ — best-effort, see header warning)
    //
    // ============================================================================================
    // KNOWN-UNVERIFIED BLOCK. AlarmKit (Apple's third-party-alarm framework, introduced at WWDC
    // 2025 for iOS 26) postdates any environment this task could check a real SDK/Xcode/docs
    // against. Every symbol below — `AlarmManager`, `.shared`, `requestAuthorization()`,
    // `AlarmPresentation`/`.Alert`, `AlarmButton`, `AlarmAttributes<Metadata>`, `AlarmMetadata`,
    // `AlarmManager.AlarmConfiguration`, `Alarm.Schedule.fixed(_:)`, `.schedule(id:configuration:)`,
    // `.stop(id:)` — is written from partial recollection of that framework's announced shape, not
    // verified against real headers. Treat this as a structural sketch of the intended
    // integration (real authorization request → real alert configuration → real schedule call →
    // real stop call, with the app-opening intent above standing in for "must open the dismiss
    // flow, not silently stop"), not verified working code. Expect to fix symbol/parameter names
    // against Apple's actual AlarmKit documentation before this compiles on a real iOS 26 SDK.
    // Isolated behind `#if canImport(AlarmKit)` + `@available(iOS 26.0, *)` specifically so a
    // wrong guess here cannot break the fully-verified notification-fallback tier, which is what
    // actually carries this feature on iOS 17/18 today.
    // ============================================================================================

    @available(iOS 26.0, *)
    private func scheduleViaAlarmKit(fireDate: Date, variant: DismissVariant, sound: AlarmSoundChoice) async throws {
        #if canImport(AlarmKit)
        let manager = AlarmManager.shared
        _ = try await manager.requestAuthorization()

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: SunriseAlarmCopy.alarmKitAlertTitle(variant: variant)),
            stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: SunriseAlarmCopy.alarmKitStopButtonLabel(variant: variant)))
        )
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes<SunriseAlarmMetadata>(presentation: presentation, metadata: SunriseAlarmMetadata())
        let configuration = AlarmManager.AlarmConfiguration<SunriseAlarmMetadata>(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: SunriseAlarmOpenAppIntent(),
            // Custom sound by file name (the `sound:` parameter and `.named(_:)` are in Apple's
            // AlarmKit docs). UNVERIFIED: where the file must live and its format limits — the
            // docs pages read didn't say; it is bundled the same way as the notification sounds.
            sound: .named(sound.fileName)
        )
        try await manager.schedule(id: Self.alarmKitID, configuration: configuration)
        #else
        throw SunriseAlarmError.dismissConditionNotMet(reason: "AlarmKit not available in this SDK build")
        #endif
    }

    @available(iOS 26.0, *)
    private func stopAlarmKitAlarmIfNeeded() async {
        #if canImport(AlarmKit)
        try? await AlarmManager.shared.stop(id: Self.alarmKitID)
        #endif
    }

    @available(iOS 26.0, *)
    private func rescheduleAlarmKitForSnooze(fireDate: Date, variant: DismissVariant, sound: AlarmSoundChoice) async {
        #if canImport(AlarmKit)
        try? await AlarmManager.shared.stop(id: Self.alarmKitID)
        try? await scheduleViaAlarmKit(fireDate: fireDate, variant: variant, sound: sound)
        #endif
    }

    private static let alarmKitID = UUID(uuidString: "5A171550-A1A2-4A1A-9000-000000005A17") ?? UUID()

    // MARK: - Backup alarm (a plain second alarm after the Sunrise Alarm)

    private static let backupNotificationPrefix = "zano.sunriseBackup."
    private static let backupAlarmKitID = UUID(uuidString: "5A171550-A1A2-4A1A-9000-000000005B0B") ?? UUID()

    /// Schedules the backup `minutes` after `fireDate` on the same tier the main alarm uses (AlarmKit
    /// on iOS 26+, a notification chain otherwise). It is a plain alarm: no tag, no verification;
    /// it rings until stopped. A verified dismiss or the escape hatch cancels it (both end in
    /// `scheduleAlarm`, which starts with `cancelBackupAlarm()`), so it only rings if you are
    /// still not up. Spec §5.10 / §27: a backup is the honest answer to "never promise it will
    /// always wake you".
    private func scheduleBackupAlarm(after fireDate: Date, minutes: Int, sound: AlarmSoundChoice) async {
        let backupFire = fireDate.addingTimeInterval(Double(max(1, minutes)) * 60)
        if #available(iOS 26.0, *) {
            if (try? await scheduleBackupViaAlarmKit(fireDate: backupFire, sound: sound)) != nil { return }
        }
        let center = UNUserNotificationCenter.current()
        let maxCount = max(1, Int(SunriseAlarmEngineDefaults.escalationWindow / SunriseAlarmEngineDefaults.notificationInterval))
        let dayKey = Self.dayKey(for: fireDate)
        for index in 0..<maxCount {
            let content = UNMutableNotificationContent()
            content.title = Copy.sunriseAlarm.backupNotificationTitle
            content.body = Copy.sunriseAlarm.backupNotificationBody(minutes: minutes)
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
            content.interruptionLevel = .timeSensitive
            let fire = backupFire.addingTimeInterval(Double(index) * SunriseAlarmEngineDefaults.notificationInterval)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let request = UNNotificationRequest(
                identifier: "\(Self.backupNotificationPrefix)\(dayKey).\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    @available(iOS 26.0, *)
    private func scheduleBackupViaAlarmKit(fireDate: Date, sound: AlarmSoundChoice) async throws {
        #if canImport(AlarmKit)
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: Copy.sunriseAlarm.backupNotificationTitle),
            stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: Copy.sunriseAlarm.backupStopButtonLabel))
        )
        let attributes = AlarmAttributes<SunriseAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SunriseAlarmMetadata()
        )
        let configuration = AlarmManager.AlarmConfiguration<SunriseAlarmMetadata>(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: SunriseAlarmOpenAppIntent(),
            sound: .named(sound.fileName)
        )
        try await AlarmManager.shared.schedule(id: Self.backupAlarmKitID, configuration: configuration)
        #else
        throw SunriseAlarmError.dismissConditionNotMet(reason: "AlarmKit not available in this SDK build")
        #endif
    }

    private func cancelBackupAlarm() async {
        if #available(iOS 26.0, *) {
            #if canImport(AlarmKit)
            try? await AlarmManager.shared.stop(id: Self.backupAlarmKitID)
            #endif
        }
        let center = UNUserNotificationCenter.current()
        let pendingIDs = await NotificationCenterQueries.pendingIdentifiers()
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs.filter { $0.hasPrefix(Self.backupNotificationPrefix) })
        let deliveredIDs = await NotificationCenterQueries.deliveredIdentifiers()
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs.filter { $0.hasPrefix(Self.backupNotificationPrefix) })
    }

    // MARK: - Notification fallback (iOS 17–18 — spec §5.10, fully verified UserNotifications API)

    /// Chains escalating local notifications ≤30s apart for `SunriseAlarmEngineDefaults.
    /// escalationWindow` (spec §5.10 point 1: "fires... with escalating sound/haptics"; "iOS
    /// 17–18 fallback: scheduled local notifications with a custom sound (≤30s each, chained)").
    ///
    /// `interruptionLevel = .timeSensitive` (available since iOS 15, no special entitlement
    /// needed — unlike `.critical`, which does) is the strongest urgency this tier can honestly
    /// claim without Apple's separate Critical Alerts entitlement; spec §5.10 itself frames this
    /// whole tier as "weaker, but acceptable as a fallback," so this doesn't try to fake
    /// AlarmKit's silent-mode-breaking behavior.
    private func scheduleNotificationFallback(fireDate: Date, dayKey: String, variant: DismissVariant, sound: AlarmSoundChoice) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        registerNotificationCategories()

        let maxCount = max(1, Int(SunriseAlarmEngineDefaults.escalationWindow / SunriseAlarmEngineDefaults.notificationInterval))
        for index in 0..<maxCount {
            let fireOffset = fireDate.addingTimeInterval(Double(index) * SunriseAlarmEngineDefaults.notificationInterval)
            let copy = SunriseAlarmCopy.ringingNotification(escalationIndex: index, variant: variant)

            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = Self.notificationCategoryIdentifier
            content.userInfo = ["zano.sunriseAlarm": true, "escalationIndex": index]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireOffset)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier(dayKey: dayKey, index: index),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private func cancelPendingNotifications() async {
        let center = UNUserNotificationCenter.current()
        // Identifiers only, read through `NotificationCenterQueries` (nonisolated callbacks: a
        // callback written in this main-actor type would trap when called off the main queue).
        let pendingIDs = await NotificationCenterQueries.pendingIdentifiers()
        center.removePendingNotificationRequests(
            withIdentifiers: pendingIDs.filter { $0.hasPrefix(Self.notificationIdentifierPrefix) }
        )

        let deliveredIDs = await NotificationCenterQueries.deliveredIdentifiers()
        center.removeDeliveredNotifications(
            withIdentifiers: deliveredIDs.filter { $0.hasPrefix(Self.notificationIdentifierPrefix) }
        )
    }

    /// Registers the "Open ZANO" notification action + category this file's notifications use.
    /// Intended to run once at app launch (`ZANOApp.init`, alongside `Analytics.shared.setup` —
    /// not this task's file to wire that specific call into). Safe to call repeatedly
    /// (`setNotificationCategories` replaces, it doesn't accumulate).
    public func registerNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: "zano.sunriseAlarm.open",
            title: SunriseAlarmCopy.notificationOpenActionLabel,
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryIdentifier,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    public static let notificationCategoryIdentifier = "zano.sunriseAlarm.ringing"
    private static let notificationIdentifierPrefix = "zano.sunriseAlarm."
    private static func notificationIdentifier(dayKey: String, index: Int) -> String {
        "\(notificationIdentifierPrefix)\(dayKey).\(index)"
    }

    // MARK: - Ringing state (starts monitoring + the fallback-tier Live Activity)

    /// Call when the app is opened around/after the alarm's fire time — a notification tap, a
    /// `zano://` deep link, or a foreground check — then present `AlarmRingingView` (App-level
    /// scene/notification routing, outside this task's three-file scope, matching that view's own
    /// header comment about exactly this gap). Idempotent and cheap to call speculatively;
    /// flips `isRinging` true, which is what `AlarmRingingView` actually watches.
    public func beginRingingIfDue(now: Date = .now) async {
        guard let state = loadDailyState(), state.dismissedAt == nil else { return }
        guard now >= state.fireDate else { return }
        // Past the escalation window (plus a minute of grace) — don't resurrect a stale alarm
        // just because the app happened to open hours later.
        guard now <= state.fireDate.addingTimeInterval(SunriseAlarmEngineDefaults.escalationWindow + 60) else { return }

        isRinging = true
        ringingSince = state.fireDate
        snoozesRemainingToday = max(0, SunriseAlarmEngineDefaults.maxSnoozes - state.snoozeCount)
        stepsWalked = 0

        await startRingingActivityIfNeeded(state: state, now: now)

        let settings = await currentSettings()
        if settings.dismissVariant == .steps {
            startStepsDismissMonitoring(now: now)
        }
        scheduleSquadNotifyIfNeeded(fireDate: state.fireDate, settings: settings)
    }

    /// Re-schedules if nothing is currently scheduled, or the last scheduled fire date is stale
    /// (more than a day old — this cycle already ran its course with nothing picking up the next
    /// one). Nothing in this file has a background hook that fires exactly at "tomorrow's wake
    /// time is now known" the way a real `DeviceActivityMonitor`/`BGTaskScheduler` registration
    /// would — see this file's header for the same class of gap `BedtimeGateManager` documents for
    /// its own recurring schedule. Until that's wired, call this from the same app-launch/
    /// foreground hook as `beginRingingIfDue`/`reconcileIfDismissedElsewhere` so a normal daily
    /// "open the app in the morning" cadence keeps tonight's/tomorrow's cycle alive on its own;
    /// flagged in knownIssues as the honest limit of what's achievable without that hook.
    ///
    /// Recurrence (audit V1): the alarm is scheduled one occurrence at a time (AlarmKit `.fixed`,
    /// or one notification chain), so each occurrence must be followed by the next. That happens
    /// right after a dismiss or the escape hatch (`completeDismiss`, `triggerEscapeHatch`), and
    /// here for everything else: an occurrence whose ringing window passed with nobody dismissing
    /// it, or one that was already dismissed. The alarm repeats every day — `Settings` has no
    /// weekday selection, and no setup screen offers one.
    ///
    /// The app calls this on every foreground, but only when `hasBeenConfigured` is true.
    public func ensureScheduledIfNeeded(now: Date = .now) async {
        let settings = await currentSettings()
        guard settings.enabled else { return }
        guard let state = loadDailyState() else {
            _ = await scheduleAlarm(now: now)
            return
        }
        if Self.needsNextOccurrence(fireDate: state.fireDate, dismissedAt: state.dismissedAt, now: now) {
            if settings.repeatDays.isEmpty {
                await switchOffOneTimeAlarm(settings)
            } else {
                _ = await scheduleAlarm(now: now)
            }
        }
    }

    /// Pure rule behind `ensureScheduledIfNeeded`: schedule the next occurrence once this one is
    /// over — dismissed (and its fire time passed), or past its ringing window plus a minute of
    /// grace (the same window `beginRingingIfDue` honours). An upcoming or still-ringing occurrence
    /// is left alone.
    nonisolated static func needsNextOccurrence(fireDate: Date, dismissedAt: Date?, now: Date) -> Bool {
        guard now >= fireDate else { return false }
        if dismissedAt != nil { return true }
        return now > fireDate.addingTimeInterval(SunriseAlarmEngineDefaults.escalationWindow + 60)
    }

    /// Schedules tomorrow's occurrence after this one ended (dismiss or escape hatch), so the
    /// alarm recurs even if the app isn't opened again before the next wake time (audit V1).
    private func scheduleNextOccurrence(after now: Date) async {
        let settings = await currentSettings()
        guard settings.enabled else { return }
        if settings.repeatDays.isEmpty {
            await switchOffOneTimeAlarm(settings)
            return
        }
        _ = await scheduleAlarm(now: now)
    }

    /// "Never" repeat: the one occurrence has run, so the alarm turns itself off, as in the Clock
    /// app. Saving the setup screen again turns it back on.
    private func switchOffOneTimeAlarm(_ settings: Settings) async {
        var updated = settings
        updated.enabled = false
        if let data = try? JSONEncoder().encode(updated) {
            Self.defaults.set(data, forKey: Self.settingsKey)
        }
        _ = await scheduleAlarm()
    }

    /// Defensive-only reconciliation for a Tag dismiss that happened via `SunriseKeyIntent`
    /// through some path other than `AlarmRingingView`'s own two-step handshake (e.g. an NFC
    /// background-read automation while that screen wasn't presented) — see this file's header.
    /// Safe and cheap to call opportunistically from the same places `beginRingingIfDue` is.
    public func reconcileIfDismissedElsewhere(now: Date = .now) async {
        guard isRinging else { return }
        guard await isSunriseGoalVerifiedToday(asOf: now) else { return }
        try? await dismissViaTag(tagID: UUID())
    }

    private func startRingingActivityIfNeeded(state: DailyState, now: Date) async {
        // The AlarmKit tier's own system alert already is spec §5.10's "Live-Activity-style alert
        // UI" — a second, ZANO-drawn Live Activity on top of it would compete with it, not add to
        // it. Only the notification-fallback tier needs its own (spec §5.10: "plus a Live
        // Activity").
        guard state.tier == .notifications else { return }
        guard ringingActivity == nil else {
            await updateRingingActivity(now: now)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities disabled; running sunrise alarm without one.")
            return
        }

        let settings = await currentSettings()
        let attributes = SunriseAlarmRingingActivityAttributes(wakeHourMinuteLabel: Self.timeLabel(for: state.fireDate))
        let content = ActivityContent(
            state: SunriseAlarmRingingActivityAttributes.ContentState(
                secondsSinceRinging: max(0, Int(now.timeIntervalSince(state.fireDate))),
                snoozeAvailable: state.snoozeCount < SunriseAlarmEngineDefaults.maxSnoozes,
                dismissVariant: settings.dismissVariant.rawValue
            ),
            staleDate: nil
        )
        do {
            ringingActivity = try Activity<SunriseAlarmRingingActivityAttributes>.request(attributes: attributes, content: content)
        } catch {
            logger.error("Failed to start Sunrise Alarm Live Activity: \(String(describing: error), privacy: .public)")
        }
    }

    private func updateRingingActivity(now: Date) async {
        guard let ringingActivity, let state = loadDailyState() else { return }
        let settings = await currentSettings()
        let content = ActivityContent(
            state: SunriseAlarmRingingActivityAttributes.ContentState(
                secondsSinceRinging: max(0, Int(now.timeIntervalSince(state.fireDate))),
                snoozeAvailable: state.snoozeCount < SunriseAlarmEngineDefaults.maxSnoozes,
                dismissVariant: settings.dismissVariant.rawValue
            ),
            staleDate: nil
        )
        nonisolated(unsafe) let activity = ringingActivity
        await activity.update(content)
    }

    private func endRingingActivity(now: Date) async {
        guard let liveActivity = ringingActivity else { return }
        ringingActivity = nil
        nonisolated(unsafe) let activity = liveActivity
        let fireDate = loadDailyState()?.fireDate ?? now
        let variant = (await currentSettings()).dismissVariant
        let content = ActivityContent(
            state: SunriseAlarmRingingActivityAttributes.ContentState(
                secondsSinceRinging: max(0, Int(now.timeIntervalSince(fireDate))),
                snoozeAvailable: false,
                dismissVariant: variant.rawValue
            ),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .immediate)
    }

    // MARK: - Dismiss: Tag (spec §5.10 point 2 — the default, and "the ONLY dismiss by default")
    //
    // `SunriseKeyIntent.perform()` (`Intents/SunriseKeyIntent.swift`, not owned by this task)
    // already logs the `.complete` GoalEvent and arms the day's lock for a Tag tap, independently
    // of this manager — see this file's header. This method only silences the alarm mechanics.

    public func dismissViaTag(tagID: UUID) async throws {
        await completeDismiss(variant: .tag, writeGoalEvent: false, meta: ["tagID": .string(tagID.uuidString)])
    }

    // MARK: - Dismiss: Steps (spec §5.10 "Variants" — Core Motion)

    /// `AlarmRingingView` reactively calls this once its own `.task(id: manager.stepsWalked)`
    /// observes `stepsWalked` crossing `Settings.stepsTarget` — this method re-checks that
    /// condition itself (never trusts the caller blindly) before completing the dismiss.
    public func dismissViaSteps() async throws {
        let settings = await currentSettings()
        guard stepsWalked >= settings.stepsTarget else {
            throw SunriseAlarmError.dismissConditionNotMet(
                reason: "Not enough steps yet (\(stepsWalked)/\(settings.stepsTarget))."
            )
        }
        stopStepsDismissMonitoring()
        await completeDismiss(variant: .steps, writeGoalEvent: true, meta: ["steps": .number(Double(stepsWalked))])
    }

    /// Starts live pedometer updates from `now`, updating the observable `stepsWalked` as they
    /// arrive. A no-op if Core Motion step counting isn't available on this device or monitoring
    /// is already running. Called from `beginRingingIfDue` when the current variant is `.steps`.
    public func startStepsDismissMonitoring(now: Date = .now) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        guard !stepsMonitoringActive else { return }
        stepsMonitoringActive = true

        // The handler runs on whatever internal queue CoreMotion uses, not the main actor —
        // exactly like `MotionAntiCheat`'s own documented reasoning for the same SDK. Only a
        // plain `Int` is extracted here; everything else hops back onto this `@MainActor` type
        // through the `Task { await ... }` below before touching any of its state.
        pedometer.startUpdates(from: now) { [weak self] data, error in
            guard let data, error == nil else { return }
            let steps = data.numberOfSteps.intValue
            Task { [weak self] in
                await self?.handleStepsUpdate(count: steps)
            }
        }
    }

    public func stopStepsDismissMonitoring() {
        guard stepsMonitoringActive else { return }
        pedometer.stopUpdates()
        stepsMonitoringActive = false
    }

    private func handleStepsUpdate(count: Int) async {
        guard stepsMonitoringActive else { return } // already dismissed/cancelled since the update fired
        stepsWalked = count
    }

    // MARK: - Dismiss: Focus (spec §5.10 "Variants" — "3-minute journal/stretch timer")

    /// `AlarmRingingView` owns the 3-minute countdown UI/loop itself and calls this once it
    /// completes — this manager has no internal focus-timer task of its own (matching the ASSUMED
    /// API's parameterless `dismissViaFocusCompletion()`, which presumes the caller already ran
    /// the timer).
    public func dismissViaFocusCompletion() async throws {
        await completeDismiss(variant: .focus, writeGoalEvent: true, meta: [:])
    }

    // MARK: - Dismiss: Squad (spec §5.10 "Variants" — hold-to-commit self-confirmation, plus the
    // friend-notify safety net below)

    /// `AlarmRingingView`'s Squad variant is a hold-to-commit "I'm up" confirmation (its own
    /// `PrimaryButton(style: .holdToCommit)`) — the actual dismiss action for this variant.
    public func dismissViaSquadConfirmation() async throws {
        await completeDismiss(variant: .squad, writeGoalEvent: true, meta: [:])
    }

    /// Spec §5.10: "a friend gets notified if you don't dismiss within 10 min." `Settings.
    /// squadIDToNotify` names a squad, not a specific friend (the ASSUMED `Settings` shape has no
    /// second field for one) — this notifies the first other member of that squad, the closest
    /// honest reading of "a friend" available from that shape. Flagged in knownIssues: a squad
    /// picker with no specific-friend field means this can't target a chosen person by name.
    private func scheduleSquadNotifyIfNeeded(fireDate: Date, settings: Settings) {
        squadNotifyTask?.cancel()
        guard settings.dismissVariant == .squad, let squadID = settings.squadIDToNotify else { return }

        let delaySeconds = Double(SunriseAlarmEngineDefaults.squadNotifyAfterMinutes) * 60
        squadNotifyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self, self.isRinging else { return }
            guard let userID = try? self.fetchCurrentUser().id else { return }
            guard let members = try? await SquadManager.shared.members(of: squadID) else { return }
            guard let friend = members.first(where: { $0.userID != userID }) else { return }
            _ = try? await SquadManager.shared.sendNudge(squadID: squadID, from: userID, to: friend.userID, tone: .toughLove, on: .now)
            Analytics.shared.capture(event: "sunrise_alarm_squad_notified", properties: [:])
            self.logger.notice("Notified squad friend — alarm not dismissed within the configured window.")
        }
    }

    // MARK: - Snooze (spec §5.10 point 3: "1 snooze max (5 min), or it breaks the morning goal")

    @discardableResult
    public func snooze() async throws -> Date {
        guard var state = loadDailyState(), state.dismissedAt == nil else {
            throw SunriseAlarmError.notCurrentlyRinging
        }
        guard state.snoozeCount < SunriseAlarmEngineDefaults.maxSnoozes else {
            try? logGoalEvent(
                kind: .miss,
                verified: false,
                source: .manual,
                meta: .object(["reason": .string("snoozeLimitExceeded")]),
                now: .now
            )
            Analytics.shared.capture(event: "sunrise_alarm_snooze_limit_broke_goal", properties: [:])
            throw SunriseAlarmError.snoozeLimitReached
        }

        state.snoozeCount += 1
        state.fireDate = Date.now.addingTimeInterval(SunriseAlarmEngineDefaults.snoozeDuration)
        saveDailyState(state)

        let settings = await currentSettings()
        await cancelPendingNotifications()
        if state.tier == .alarmKit, #available(iOS 26.0, *) {
            await rescheduleAlarmKitForSnooze(fireDate: state.fireDate, variant: settings.dismissVariant, sound: settings.sound)
        } else {
            await scheduleNotificationFallback(fireDate: state.fireDate, dayKey: state.dayKey, variant: settings.dismissVariant, sound: settings.sound)
        }
        await endRingingActivity(now: .now)
        stopStepsDismissMonitoring()
        squadNotifyTask?.cancel(); squadNotifyTask = nil

        isRinging = false
        ringingSince = nil
        snoozesRemainingToday = max(0, SunriseAlarmEngineDefaults.maxSnoozes - state.snoozeCount)

        Analytics.shared.capture(event: "sunrise_alarm_snoozed", properties: [:])
        logger.notice("Snoozed sunrise alarm to \(state.fireDate.description, privacy: .public).")
        return state.fireDate
    }

    // MARK: - Dismiss completion (shared by every variant except Tag's GoalEvent write — see header)

    private func completeDismiss(variant: DismissVariant, writeGoalEvent: Bool, meta: [String: JSONValue], now: Date = .now) async {
        if writeGoalEvent {
            do {
                let event = try logGoalEvent(kind: .complete, verified: true, source: sourceFor(variant), meta: .object(meta), now: now)
                if let goalID = event.goal?.id { await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID) }
            } catch {
                logger.error("completeDismiss: failed to log GoalEvent: \(String(describing: error), privacy: .public)")
            }
        }
        if var state = loadDailyState() {
            state.dismissedAt = now
            saveDailyState(state)
        }
        isRinging = false
        ringingSince = nil
        await cancelAlarm(reason: .dismissed(variant))
        // Spec §5.10 point 4: "Tapping the tag = alarm off + morning goal verified + the day's
        // lock arms automatically" — applies identically to every variant that actually verifies
        // the morning goal, not just Tag.
        _ = await BedtimeGateManager.shared.armDayLockAfterWake(now: now)
        // Recurrence (audit V1): the next wake time is scheduled now, not on some later app open.
        await scheduleNextOccurrence(after: now)

        Analytics.shared.capture(event: "sunrise_alarm_dismissed", properties: ["variant": variant.rawValue])
        logger.notice("Sunrise alarm dismissed via \(variant.rawValue, privacy: .public).")
    }

    /// `GoalEventSource` (`Models/GoalEvent.swift`, not owned by this task) has no case for
    /// "Core Motion step count" or "hold-to-commit self-confirmation" — the closest real fits:
    /// `.timer` for Focus (a genuine timer, matching `FocusSessionVerifier`'s own use of the same
    /// case), `.nfc` for Tag, `.manual` for Steps/Squad as the least-wrong remaining option —
    /// flagged in knownIssues as a case this enum would ideally grow, not a guess presented as
    /// correct.
    private func sourceFor(_ variant: DismissVariant) -> GoalEventSource {
        switch variant {
        case .tag: return .nfc
        case .steps: return .manual
        case .focus: return .timer
        case .squad: return .manual
        }
    }

    // MARK: - Cancel

    public func cancelAlarm(reason: SunriseAlarmCancelReason) async {
        squadNotifyTask?.cancel(); squadNotifyTask = nil
        stopStepsDismissMonitoring()
        await cancelPendingNotifications()
        await cancelBackupAlarm()
        if #available(iOS 26.0, *) { await stopAlarmKitAlarmIfNeeded() }
        await endRingingActivity(now: .now)
        logger.notice("Cancelled sunrise alarm: \(String(describing: reason), privacy: .public).")
    }

    /// "Delete all my data": stops the alarm on every tier (AlarmKit + notification chain + the
    /// ringing Live Activity) and forgets the settings and today's state, so `hasBeenConfigured`
    /// is `false` again and no foreground hook reschedules it.
    public func resetAll() async {
        await cancelAlarm(reason: .disabled)
        Self.defaults.removeObject(forKey: Self.settingsKey)
        clearDailyState()
        isRinging = false
        ringingSince = nil
        snoozesRemainingToday = SunriseAlarmEngineDefaults.maxSnoozes
        stepsWalked = 0
    }

    // MARK: - Escape hatch (spec §5.10 point 6 / §24 point 2 — never trap the user)
    //
    // `AlarmRingingView` implements its own 60-second hold gesture directly (reusing `EmergencyUnlock.
    // holdDuration` as the shared constant, per that view's own header) and calls this method once
    // the hold completes — this manager does not duplicate a second hold-timer implementation.

    /// Ends the alarm unconditionally with no verification — the escape hatch's whole point. Logs
    /// a `.miss` GoalEvent (this was not a completed morning goal) but never arms the day's lock:
    /// "I'm not home" means there's no one there for a lock to gate anything useful for. Never
    /// actually fails in practice — `throws` is kept in the signature to match the real consumer's
    /// ASSUMED API and for future flexibility, but "no one gets trapped" must never depend on a
    /// GoalEvent write succeeding, so a logging failure here is swallowed, not rethrown.
    public func triggerEscapeHatch(reason: EscapeReason) async throws {
        do {
            try logGoalEvent(
                kind: .miss,
                verified: false,
                source: .manual,
                meta: .object(["reason": .string("escapeHatch"), "detail": .string(reason.rawValue)]),
                now: .now
            )
        } catch {
            logger.error("triggerEscapeHatch: failed to log GoalEvent: \(String(describing: error), privacy: .public)")
        }
        if var state = loadDailyState() {
            state.dismissedAt = .now
            saveDailyState(state)
        }
        isRinging = false
        ringingSince = nil
        await cancelAlarm(reason: .escapeHatch)
        // The escape hatch ends today's alarm, not the feature: tomorrow's still rings (audit V1).
        await scheduleNextOccurrence(after: .now)
        Analytics.shared.capture(event: "sunrise_alarm_escape_hatch", properties: ["reason": reason.rawValue])
    }

    // MARK: - SwiftData / GoalEvent

    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw SunriseAlarmError.noSignedInUser
        }
        return user
    }

    @discardableResult
    private func logGoalEvent(kind: GoalEventKind, verified: Bool, source: GoalEventSource, meta: JSONValue, now: Date) throws -> GoalEvent {
        let user = try fetchCurrentUser()
        guard let goal = try IntentSupport.activeGoal(ofType: .sunriseAlarm, for: user.id, in: context) else {
            throw SunriseAlarmError.noActiveGoalConfigured
        }
        let event = GoalEvent(ts: now, kind: kind, source: source, verified: verified, meta: meta, user: user, goal: goal)
        context.insert(event)
        try context.save()
        return event
    }

    /// Mirrors `LockEngineManager.isGoalVerified`'s documented `#Predicate`-conservatism tradeoff
    /// (`Bool`/`Date` fields in the predicate, the relationship/enum comparison filtered after).
    private func isSunriseGoalVerifiedToday(asOf date: Date) async -> Bool {
        guard let user = try? fetchCurrentUser() else { return false }
        guard let goal = try? IntentSupport.activeGoal(ofType: .sunriseAlarm, for: user.id, in: context) else { return false }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= startOfDay }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains { $0.goal?.id == goal.id && $0.kind == .complete }
    }

    // MARK: - Time helpers

    /// The next time the alarm should ring: the first day on or after `date` whose weekday is in
    /// `repeatDays` (`Calendar` weekday numbers) at `hour:minute`, strictly after `date`. An empty
    /// set means "Never": just the next occurrence of that time, any day.
    nonisolated static func nextFireDate(
        hour: Int,
        minute: Int,
        after date: Date,
        repeatDays: Set<Int> = RepeatDays.everyDay,
        calendar: Calendar = .current
    ) -> Date {
        for offset in 0...8 {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: date),
                let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                candidate > date
            else { continue }
            if repeatDays.isEmpty || repeatDays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }
        return date.addingTimeInterval(86_400)
    }

    private static func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func dayKey(for date: Date) -> String { dayFormatter.string(from: date) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    // MARK: - Daily state persistence (own App Group UserDefaults key — see this file's header
    // `decisions` note on why the durable Settings row lives here rather than in
    // `Store/SharedDefaults.swift`)

    private struct DailyState: Codable {
        var dayKey: String
        var fireDate: Date
        var tier: SunriseAlarmTier
        var snoozeCount: Int
        var dismissedAt: Date?
    }

    private func loadDailyState() -> DailyState? {
        guard let data = Self.defaults.data(forKey: Self.dailyStateKey) else { return nil }
        return try? JSONDecoder().decode(DailyState.self, from: data)
    }

    private func saveDailyState(_ state: DailyState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        Self.defaults.set(data, forKey: Self.dailyStateKey)
    }

    private func clearDailyState() {
        Self.defaults.removeObject(forKey: Self.dailyStateKey)
    }

    /// Mirrors `NFCTagMapper`/`SquadManager`/`BedtimeGateManager`'s identical `nonisolated(unsafe)`
    /// App Group `UserDefaults` fallback pattern.
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    nonisolated private static let settingsKey = "core.sunriseAlarm.settings.v1"
    private static let dailyStateKey = "core.sunriseAlarm.dailyState.v1"
}

#if canImport(AlarmKit)
/// Best-effort `AlarmMetadata` payload — see `scheduleViaAlarmKit`'s header warning. Empty on
/// purpose: nothing in this alert needs data beyond what `AlarmPresentation.Alert`'s title/stop
/// button already carry.
///
/// `@available(iOS 26.0, *)` here, not just on the functions that use it: `#if canImport(AlarmKit)`
/// is a compile-time SDK check, not a runtime OS check — this type is compiled into every build
/// whose *SDK* includes AlarmKit regardless of this app's deployment target, so if `AlarmMetadata`
/// itself carries iOS 26 availability (likely, as a brand-new-in-iOS-26 protocol), conforming to it
/// needs the same annotation or the compiler rejects the conformance outright on a <26 deployment
/// target. Best-effort, same confidence caveat as the rest of this block.
@available(iOS 26.0, *)
struct SunriseAlarmMetadata: AlarmMetadata {}
#endif

// MARK: - Engine constants / errors / cancel reason

/// Engine-wide constants, kept together so every escalation/snooze number spec §5.10 names lives
/// in one place instead of scattered through the scheduling code.
public enum SunriseAlarmEngineDefaults {
    /// Spec §5.10: "scheduled local notifications... ≤30s each, chained." `30` is the spec-given
    /// maximum, used as the actual interval (the tightest, most alarm-like chaining the ceiling
    /// allows).
    public static let notificationInterval: TimeInterval = 30
    /// How long the escalation chain (and the Squad friend-notify window) runs before this file
    /// stops actively re-checking — not a spec-pinned number; 10 minutes matches spec §5.10's own
    /// Squad-variant window so both features share one "how long is too long" sense of scale.
    public static let escalationWindow: TimeInterval = 10 * 60
    /// Spec §5.10 point 3: "1 snooze max."
    public static let maxSnoozes = 1
    /// Spec §5.10 point 3: "(5 min)".
    public static let snoozeDuration: TimeInterval = 5 * 60
    /// Spec §5.10 point 6 / §24 point 2: "a 60-second hold."
    public static let escapeHatchHoldDuration: TimeInterval = 60
    /// Spec §5.10: "within 10 min".
    public static let squadNotifyAfterMinutes = 10
}

public enum SunriseAlarmError: Error, Sendable, Equatable, LocalizedError {
    case noSignedInUser
    /// No active `Goal` of type `.sunriseAlarm` exists to attach a dismiss/miss `GoalEvent` to.
    case noActiveGoalConfigured
    case notCurrentlyRinging
    case snoozeLimitReached
    case dismissConditionNotMet(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        case .noActiveGoalConfigured: "No active Sunrise Alarm goal is configured."
        case .notCurrentlyRinging: "The alarm isn't currently ringing."
        case .snoozeLimitReached: "You've already used today's one snooze."
        case .dismissConditionNotMet(let reason): reason
        }
    }
}

public enum SunriseAlarmCancelReason: Sendable, Equatable {
    case dismissed(SunriseAlarmManager.DismissVariant)
    case escapeHatch
    case disabled
}
