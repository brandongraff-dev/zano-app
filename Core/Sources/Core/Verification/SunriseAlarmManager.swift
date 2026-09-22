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
// This task's required reading shaped three real decisions, documented at their call sites below:
//   - `LockEngineManager.startLock(...)` is never called directly from here — `BedtimeGateManager.
//     armDayLockAfterWake(...)` (this same task, `Verification/BedtimeGateManager.swift`) is,
//     exactly per this task's own brief ("days lock arms automatically — call
//     BedtimeGateManager/LockEngineManager"), and exactly matching the "arm once, only if nothing
//     already has" guard `SunriseKeyIntent.perform()` (not owned by this task) already implements
//     inline for its own Tag-dismiss path.
//   - `NFCTagMapper.handleScannedURL`/`SunriseKeyIntent.perform()` (not owned by this task) already
//     fully implement the Tag-dismiss path end to end: they log the `.complete` `GoalEvent` for the
//     `.sunriseAlarm` goal themselves and call `LockEngineManager.startLock` themselves. This file
//     does not duplicate that (a second `.complete` write would double-log the same dismiss). What
//     it *does* own for Tag dismiss is the alarm-mechanics half that call chain cannot reach from
//     here (silencing the escalating notification chain / AlarmKit alarm) — see
//     `evaluateAndReconcileDismissal` below for how that's bridged without editing either file.
//   - `SunriseAlarmSettings` has no home in `Core/Sources/Core/Models`/spec §13's Data Model table
//     (frozen, Session 1's file to extend) — persisted the same App-Group-`UserDefaults`-blob way
//     `NFCTagMapper.swift`/`BedtimeGateManager.swift` (this same task) already do, for the same
//     documented reason.
//
// Cross-module integration points left open (same documented-gap convention as
// `GymDwellActivityAttributes`/`FocusActivityAttributes`/`EarnMeterActivityManager`):
//   - A notification tap, `zano://` deep link, or app-foreground event should call
//     `beginRingingIfDue(now:)` (starts the fallback-tier Live Activity + Steps monitoring/Squad
//     timer) and `evaluateAndReconcileDismissal(now:)` (catches a Tag dismiss that happened via
//     `SunriseKeyIntent` while this manager wasn't watching). Both are cheap, idempotent, and safe
//     to call from anywhere convenient in `App/ZANO` — not this task's target to wire the call
//     into, matching `ShieldCopy`'s own documented "deep link exists, `onOpenURL` wiring is a
//     TODO" gap.
//   - `registerNotificationCategories()` should run once at app launch (`ZANOApp.init`, alongside
//     `Analytics.shared.setup`) — not called from within this file for the same reason
//     `Analytics.setup` isn't self-invoking either.

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

// MARK: - Dismiss variants (spec §5.10 "Variants (settings)")

public enum SunriseDismissVariant: String, Codable, CaseIterable, Sendable {
    /// Default. The only variant with no fallback attached — tap the Sunrise Tag.
    case tag
    /// Fallback for a user without a tag yet: walk `SunriseAlarmSettings.stepsTarget` steps
    /// (Core Motion). Spec §5.10: "Sells the tag pack: 'Do it with a tag instead.'"
    case steps
    /// 3-minute journal/stretch timer.
    case focus
    /// Decision (see this file's `decisions`): spec §5.10 frames Squad as "a friend gets notified
    /// if you don't dismiss within 10 min," not as a dismiss action of its own — nothing about
    /// being notified turns an alarm off. Modeled here as: Tag remains the actual dismiss
    /// mechanism, and choosing `.squad` additionally arms the 10-minute friend-notify timer
    /// (`scheduleSquadNotifyIfNeeded`). `sourceFor(_:)` below reflects the same choice.
    case squad
}

// MARK: - Settings

public struct SunriseAlarmSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Local wall-clock hour (0–23) the alarm fires.
    public var hour: Int
    public var minute: Int
    public var dismissVariant: SunriseDismissVariant
    /// Steps dismiss target. Spec §5.10 says "walk N steps" without pinning N; `40` is this file's
    /// own assumption (a short, real walk to a mirror/kitchen, not a workout) — flagged in
    /// knownIssues exactly like `TapRateLimiter.Policy.protein`'s own flagged daily-cap guess.
    public var stepsTarget: Int
    /// Focus dismiss duration. Spec §5.10: "3-minute journal/stretch timer" — kept configurable
    /// rather than hardcoded `3` so a future settings screen isn't blocked on this struct's shape.
    public var focusMinutes: Int
    /// Squad add-on target (spec §5.10: "a friend gets notified"). Both must be set for the
    /// Squad add-on to actually arm — see `scheduleSquadNotifyIfNeeded`.
    public var squadID: UUID?
    public var squadFriendUserID: UUID?
    /// Spec §5.10: "within 10 min".
    public var squadNotifyAfterMinutes: Int

    public init(
        enabled: Bool = false,
        hour: Int = 6,
        minute: Int = 30,
        dismissVariant: SunriseDismissVariant = .tag,
        stepsTarget: Int = 40,
        focusMinutes: Int = 3,
        squadID: UUID? = nil,
        squadFriendUserID: UUID? = nil,
        squadNotifyAfterMinutes: Int = 10
    ) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.dismissVariant = dismissVariant
        self.stepsTarget = stepsTarget
        self.focusMinutes = focusMinutes
        self.squadID = squadID
        self.squadFriendUserID = squadFriendUserID
        self.squadNotifyAfterMinutes = squadNotifyAfterMinutes
    }

    public static let `default` = SunriseAlarmSettings()
}

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
}

// MARK: - Errors

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
    case dismissed(SunriseDismissVariant)
    case escapeHatch
    case disabled
}

// MARK: - Ringing Live Activity (notification-fallback tier only — spec §5.10: "iOS 17–18
// fallback: ... plus a Live Activity." The AlarmKit tier's own system alert already is the
// "Live-Activity-style alert UI" spec §5.10 describes, so this is never started alongside it —
// see `startRingingActivityIfNeeded`'s guard.)

/// Kept in this file rather than a fourth `Core/Sources/Core/LiveActivity` file: this task's file
/// list names exactly one new LiveActivity file (`BedtimeWindDownActivityAttributes.swift`) — see
/// CLAUDE.md "own exactly what you were told to." A second `ActivityAttributes` type living inside
/// the manager that starts/updates/ends it is not a new architectural pattern for this codebase
/// either — every field below is a plain `String`/`Int`/`Bool`, mirroring every sibling
/// `ActivityAttributes` type's shape exactly.
public struct SunriseAlarmRingingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var secondsSinceRinging: Int
        public var snoozeAvailable: Bool
        /// `SunriseDismissVariant.rawValue` — kept as a plain `String` here (not the enum itself)
        /// so this Activity's content-state shape never has to change if that enum's cases do.
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

// MARK: - AlarmKit "open app" stop-button intent (best-effort — see `scheduleViaAlarmKit`)

/// The App Intent AlarmKit's alert "stop" button invokes on the notification-fallback... no — on
/// the **AlarmKit** tier's system alert. Deliberately does *not* silently stop the alarm: spec
/// §5.10 requires the alarm to keep running until the configured dismiss variant is actually
/// verified, so this button is wayfinding into the app's dismiss flow, not the real dismiss.
/// `SunriseAlarmManager.completeDismiss` is what actually calls `AlarmManager.shared.stop(id:)`
/// once verification succeeds. Defined at file scope (not inside the `#if canImport(AlarmKit)`
/// block below) because `AppIntent` itself ships independently of AlarmKit — this type compiles
/// and is inert on every iOS version, and is only ever referenced from the AlarmKit-gated code.
public struct SunriseAlarmOpenAppIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open ZANO"
    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - SunriseAlarmManager

/// `@MainActor`, matching every other engine in this codebase that owns a `ModelContext` plus an
/// Apple framework object best driven from the main thread (`LockEngineManager`,
/// `FocusSessionVerifier`, `BedtimeGateManager` — this same task).
@MainActor
public final class SunriseAlarmManager {
    public static let shared = SunriseAlarmManager()

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "SunriseAlarmManager")

    /// `CMPedometer` predates Swift 6 and isn't SDK-marked `Sendable`; `nonisolated(unsafe)`
    /// mirrors `MotionAntiCheat.manager`'s identical, fully-documented rationale in this same
    /// directory — created once, never reassigned, only ever touched from this `@MainActor` type.
    nonisolated(unsafe) private let pedometer = CMPedometer()
    private var stepsMonitoringActive = false

    private var ringingActivity: Activity<SunriseAlarmRingingActivityAttributes>?
    private var focusDismissTask: Task<Void, Never>?
    private var squadNotifyTask: Task<Void, Never>?

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
    }

    // MARK: - Settings persistence

    public func settings() -> SunriseAlarmSettings {
        guard
            let data = Self.defaults.data(forKey: Self.settingsKey),
            let decoded = try? JSONDecoder().decode(SunriseAlarmSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    /// Saves new settings and immediately reschedules — a bedtime/wake-time or dismiss-variant
    /// change takes effect for tonight, not just future nights.
    public func updateSettings(_ newSettings: SunriseAlarmSettings) async {
        guard let data = try? JSONEncoder().encode(newSettings) else { return }
        Self.defaults.set(data, forKey: Self.settingsKey)
        _ = await scheduleAlarm()
    }

    // MARK: - Schedule (spec §5.10 "Technical path")

    /// Computes tonight/tomorrow's fire time, clears any previous scheduling for this alarm, and
    /// schedules via AlarmKit (iOS 26+, best-effort) or the local-notification chain (17–18
    /// fallback), recording which tier actually got used.
    ///
    /// - Returns: the scheduled fire date, or `nil` if the alarm is disabled (in which case any
    ///   previous scheduling is torn down instead).
    @discardableResult
    public func scheduleAlarm(now: Date = .now) async -> Date? {
        let settings = settings()
        guard settings.enabled else {
            await cancelAlarm(reason: .disabled)
            clearDailyState()
            return nil
        }

        let fireDate = Self.nextFireDate(hour: settings.hour, minute: settings.minute, after: now)
        let dayKey = Self.dayKey(for: fireDate)

        await cancelPendingNotifications()
        if #available(iOS 26.0, *) { await stopAlarmKitAlarmIfNeeded() }
        await endRingingActivity(now: now)
        stopStepsDismissMonitoring()
        focusDismissTask?.cancel(); focusDismissTask = nil
        squadNotifyTask?.cancel(); squadNotifyTask = nil

        var tier: SunriseAlarmTier = .notifications
        var scheduledViaAlarmKit = false
        if #available(iOS 26.0, *) {
            do {
                try await scheduleViaAlarmKit(fireDate: fireDate, variant: settings.dismissVariant)
                tier = .alarmKit
                scheduledViaAlarmKit = true
            } catch {
                logger.error("AlarmKit scheduling failed, falling back to notifications: \(String(describing: error), privacy: .public)")
            }
        }
        if !scheduledViaAlarmKit {
            await scheduleNotificationFallback(fireDate: fireDate, dayKey: dayKey, variant: settings.dismissVariant)
        }

        saveDailyState(DailyState(dayKey: dayKey, fireDate: fireDate, tier: tier, snoozeCount: 0, dismissedAt: nil))
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
    private func scheduleViaAlarmKit(fireDate: Date, variant: SunriseDismissVariant) async throws {
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
            stopIntent: SunriseAlarmOpenAppIntent()
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
    private func rescheduleAlarmKitForSnooze(fireDate: Date) async {
        #if canImport(AlarmKit)
        try? await AlarmManager.shared.stop(id: Self.alarmKitID)
        try? await scheduleViaAlarmKit(fireDate: fireDate, variant: settings().dismissVariant)
        #endif
    }

    private static let alarmKitID = UUID(uuidString: "5A171550-A1A2-4A1A-9000-000000005A17") ?? UUID()

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
    private func scheduleNotificationFallback(fireDate: Date, dayKey: String, variant: SunriseDismissVariant) async {
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
            content.sound = .default
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
        let pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.notificationIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

        let deliveredIDs = await center.deliveredNotifications().map(\.identifier)
            .filter { $0.hasPrefix(Self.notificationIdentifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    /// Registers the "Open ZANO" notification action + category this file's notifications use.
    /// Intended to run once at app launch (see this file's header comment) — safe to call
    /// repeatedly (`setNotificationCategories` replaces, it doesn't accumulate).
    public func registerNotificationCategories() {
        let openAction = UNNotificationAction(identifier: "zano.sunriseAlarm.open", title: "Open ZANO", options: [.foreground])
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

    /// Call when the app is opened around/after the alarm's fire time (a notification tap, a
    /// `zano://` deep link, or a foreground check) — see this file's header comment for exactly
    /// where that call belongs. Idempotent and cheap to call speculatively.
    public func beginRingingIfDue(now: Date = .now) async {
        guard let state = loadDailyState(), state.dismissedAt == nil else { return }
        guard now >= state.fireDate else { return }
        // Past the escalation window (plus a minute of grace) — don't resurrect a stale alarm
        // just because the app happened to open hours later; `evaluateAndReconcileDismissal`
        // still runs independently to catch a late Tag dismiss.
        guard now <= state.fireDate.addingTimeInterval(SunriseAlarmEngineDefaults.escalationWindow + 60) else { return }

        await startRingingActivityIfNeeded(state: state, now: now)

        let settings = settings()
        if settings.dismissVariant == .steps {
            startStepsDismissMonitoring(now: now)
        }
        scheduleSquadNotifyIfNeeded(state: state, settings: settings)
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

        let variant = settings().dismissVariant
        let attributes = SunriseAlarmRingingActivityAttributes(wakeHourMinuteLabel: Self.timeLabel(for: state.fireDate))
        let content = ActivityContent(
            state: SunriseAlarmRingingActivityAttributes.ContentState(
                secondsSinceRinging: max(0, Int(now.timeIntervalSince(state.fireDate))),
                snoozeAvailable: state.snoozeCount < SunriseAlarmEngineDefaults.maxSnoozes,
                dismissVariant: variant.rawValue
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
        let content = ActivityContent(
            state: SunriseAlarmRingingActivityAttributes.ContentState(
                secondsSinceRinging: max(0, Int(now.timeIntervalSince(state.fireDate))),
                snoozeAvailable: state.snoozeCount < SunriseAlarmEngineDefaults.maxSnoozes,
                dismissVariant: settings().dismissVariant.rawValue
            ),
            staleDate: nil
        )
        await ringingActivity.update(content)
    }

    private func endRingingActivity(now: Date) async {
        guard let activity = ringingActivity else { return }
        ringingActivity = nil
        let fireDate = loadDailyState()?.fireDate ?? now
        let content = ActivityContent(
            state: SunriseAlarmRingingActivityAttributes.ContentState(
                secondsSinceRinging: max(0, Int(now.timeIntervalSince(fireDate))),
                snoozeAvailable: false,
                dismissVariant: settings().dismissVariant.rawValue
            ),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .immediate)
    }

    // MARK: - Dismiss: Tag (spec §5.10 point 2 — the default, and "the ONLY dismiss by default")
    //
    // `SunriseKeyIntent.perform()` (`Intents/SunriseKeyIntent.swift`, not owned by this task)
    // already logs the `.complete` GoalEvent and arms the day's lock for a Tag tap, independently
    // of this manager (see this file's header comment). `evaluateAndReconcileDismissal` is this
    // file's bridge to that: it cannot be *called from* `SunriseKeyIntent` (this task doesn't own
    // that file), so instead it watches for the effect `SunriseKeyIntent` already produces — a
    // verified `.complete` GoalEvent for the `.sunriseAlarm` goal — and reacts to it opportunistically.

    /// Call from the same places `beginRingingIfDue` is called from (app foreground, notification
    /// tap, deep link) — see this file's header comment. If a Tag dismiss already landed via
    /// `SunriseKeyIntent` while this manager wasn't watching, this silences the still-escalating
    /// notification chain / AlarmKit alarm and ends the ringing Live Activity, so the phone
    /// actually stops escalating instead of continuing to ring past a dismiss that already
    /// happened. A real gap this can't close: between the Tag tap and the next time this method
    /// runs, further chained notifications can still fire — flagged in knownIssues, an unavoidable
    /// consequence of local notification chains not being cancellable by code that isn't running.
    public func evaluateAndReconcileDismissal(now: Date = .now) async {
        guard let state = loadDailyState(), state.dismissedAt == nil else { return }
        guard now >= state.fireDate else { return }
        guard await isSunriseGoalVerifiedToday(asOf: now) else { return }

        var updated = state
        updated.dismissedAt = now
        saveDailyState(updated)
        await cancelAlarm(reason: .dismissed(.tag))
        _ = await BedtimeGateManager.shared.armDayLockAfterWake(now: now)
        Analytics.shared.capture(event: "sunrise_alarm_dismissed", properties: ["variant": "tag"])
    }

    // MARK: - Dismiss: Steps (spec §5.10 "Variants" — Core Motion)

    /// Starts live pedometer updates from `now`, auto-dismissing the moment the step count crosses
    /// `settings().stepsTarget`. A no-op if the current dismiss variant isn't `.steps`, Core
    /// Motion step counting isn't available on this device, or monitoring is already running.
    public func startStepsDismissMonitoring(now: Date = .now) {
        guard settings().dismissVariant == .steps else { return }
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
                await self?.handleStepsUpdate(count: steps, now: .now)
            }
        }
    }

    public func stopStepsDismissMonitoring() {
        guard stepsMonitoringActive else { return }
        pedometer.stopUpdates()
        stepsMonitoringActive = false
    }

    private func handleStepsUpdate(count: Int, now: Date) async {
        guard stepsMonitoringActive else { return } // already dismissed/cancelled since the update fired
        guard settings().dismissVariant == .steps else { return }
        guard count >= settings().stepsTarget else { return }
        stopStepsDismissMonitoring()
        await completeDismiss(variant: .steps, writeGoalEvent: true, meta: ["steps": .number(Double(count))], now: now)
    }

    // MARK: - Dismiss: Focus (spec §5.10 "Variants" — "3-minute journal/stretch timer")

    /// Starts the Focus dismiss countdown. A no-op if the current dismiss variant isn't `.focus`.
    /// Call `cancelFocusDismiss()` if the user backs out — per spec §5.10 point 6, backing out of
    /// the timer is never itself an escape hatch (the alarm just keeps escalating); the real
    /// escape hatch is the 60-second hold (`SunriseAlarmEscapeHatch`, below).
    public func beginFocusDismiss(now: Date = .now) {
        guard settings().dismissVariant == .focus else { return }
        focusDismissTask?.cancel()
        let minutes = max(1, settings().focusMinutes)
        focusDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled, let self else { return }
            await self.completeDismiss(
                variant: .focus,
                writeGoalEvent: true,
                meta: ["focusMinutes": .number(Double(minutes))],
                now: .now
            )
        }
    }

    public func cancelFocusDismiss() {
        focusDismissTask?.cancel()
        focusDismissTask = nil
    }

    // MARK: - Squad add-on (spec §5.10: "a friend gets notified if you don't dismiss within 10 min")

    private func scheduleSquadNotifyIfNeeded(state: DailyState, settings: SunriseAlarmSettings) {
        squadNotifyTask?.cancel()
        guard settings.dismissVariant == .squad,
              let squadID = settings.squadID,
              let friendID = settings.squadFriendUserID
        else { return }

        let delaySeconds = Double(settings.squadNotifyAfterMinutes) * 60
        squadNotifyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self else { return }
            guard let current = self.loadDailyState(), current.dayKey == state.dayKey, current.dismissedAt == nil else { return }
            guard let userID = try? self.fetchCurrentUser().id else { return }
            _ = try? await SquadManager.shared.sendNudge(squadID: squadID, from: userID, to: friendID, tone: .toughLove, on: .now)
            Analytics.shared.capture(event: "sunrise_alarm_squad_notified", properties: [:])
            self.logger.notice("Notified squad friend — alarm not dismissed within the configured window.")
        }
    }

    // MARK: - Snooze (spec §5.10 point 3: "1 snooze max (5 min), or it breaks the morning goal")

    @discardableResult
    public func snooze(now: Date = .now) async throws -> Date {
        guard var state = loadDailyState(), state.dismissedAt == nil else {
            throw SunriseAlarmError.notCurrentlyRinging
        }
        guard state.snoozeCount < SunriseAlarmEngineDefaults.maxSnoozes else {
            try? logGoalEvent(
                kind: .miss,
                verified: false,
                source: .manual,
                meta: .object(["reason": .string("snoozeLimitExceeded")]),
                now: now
            )
            Analytics.shared.capture(event: "sunrise_alarm_snooze_limit_broke_goal", properties: [:])
            throw SunriseAlarmError.snoozeLimitReached
        }

        state.snoozeCount += 1
        state.fireDate = now.addingTimeInterval(SunriseAlarmEngineDefaults.snoozeDuration)
        saveDailyState(state)

        await cancelPendingNotifications()
        if state.tier == .alarmKit, #available(iOS 26.0, *) {
            await rescheduleAlarmKitForSnooze(fireDate: state.fireDate)
        } else {
            await scheduleNotificationFallback(fireDate: state.fireDate, dayKey: state.dayKey, variant: settings().dismissVariant)
        }
        await endRingingActivity(now: now)

        Analytics.shared.capture(event: "sunrise_alarm_snoozed", properties: [:])
        logger.notice("Snoozed sunrise alarm to \(state.fireDate.description, privacy: .public).")
        return state.fireDate
    }

    // MARK: - Dismiss completion (shared by Steps/Focus; Tag goes through `evaluateAndReconcileDismissal`)

    /// `writeGoalEvent` is `false` only for the Tag path (whose `.complete` GoalEvent is already
    /// written by `SunriseKeyIntent` — see this file's header comment); every other variant writes
    /// its own here.
    private func completeDismiss(variant: SunriseDismissVariant, writeGoalEvent: Bool, meta: [String: JSONValue], now: Date) async {
        if writeGoalEvent {
            do {
                try logGoalEvent(kind: .complete, verified: true, source: sourceFor(variant), meta: .object(meta), now: now)
            } catch {
                logger.error("completeDismiss: failed to log GoalEvent: \(String(describing: error), privacy: .public)")
            }
        }
        if var state = loadDailyState() {
            state.dismissedAt = now
            saveDailyState(state)
        }
        await cancelAlarm(reason: .dismissed(variant))
        // Spec §5.10 point 4: "Tapping the tag = alarm off + morning goal verified + the day's
        // lock arms automatically" — applies identically to every variant that actually verifies
        // the morning goal, not just Tag.
        _ = await BedtimeGateManager.shared.armDayLockAfterWake(now: now)

        Analytics.shared.capture(event: "sunrise_alarm_dismissed", properties: ["variant": variant.rawValue])
        logger.notice("Sunrise alarm dismissed via \(variant.rawValue, privacy: .public).")
    }

    /// `GoalEventSource` (`Models/GoalEvent.swift`, not owned by this task) has no case for
    /// "Core Motion step count" or "friend-notify add-on" — the closest real fits used here:
    /// `.timer` for Focus (a genuine timer, matching `FocusSessionVerifier`'s own use of the same
    /// case), `.nfc` for Tag/Squad (Squad still dismisses via the physical tag per this file's own
    /// `.squad` case decision), and `.manual` for Steps as the least-wrong remaining option —
    /// flagged in knownIssues as a case this enum would ideally grow, not a guess presented as
    /// correct.
    private func sourceFor(_ variant: SunriseDismissVariant) -> GoalEventSource {
        switch variant {
        case .tag: return .nfc
        case .steps: return .manual
        case .focus: return .timer
        case .squad: return .nfc
        }
    }

    // MARK: - Cancel

    public func cancelAlarm(reason: SunriseAlarmCancelReason) async {
        focusDismissTask?.cancel(); focusDismissTask = nil
        squadNotifyTask?.cancel(); squadNotifyTask = nil
        stopStepsDismissMonitoring()
        await cancelPendingNotifications()
        if #available(iOS 26.0, *) { await stopAlarmKitAlarmIfNeeded() }
        await endRingingActivity(now: .now)
        logger.notice("Cancelled sunrise alarm: \(String(describing: reason), privacy: .public).")
    }

    // MARK: - Escape hatch (spec §5.10 point 6 / §24 point 2 — never trap the user)

    /// Ends the alarm unconditionally with no verification — the escape hatch's whole point. Logs
    /// a `.miss` GoalEvent (this was not a completed morning goal) but never arms the day's lock:
    /// "I'm not home" means there's no one there for a lock to gate anything useful for.
    public func releaseViaEscapeHatch(now: Date = .now) async {
        do {
            try logGoalEvent(kind: .miss, verified: false, source: .manual, meta: .object(["reason": .string("escapeHatch")]), now: now)
        } catch {
            logger.error("releaseViaEscapeHatch: failed to log GoalEvent: \(String(describing: error), privacy: .public)")
        }
        if var state = loadDailyState() {
            state.dismissedAt = now
            saveDailyState(state)
        }
        await cancelAlarm(reason: .escapeHatch)
        Analytics.shared.capture(event: "sunrise_alarm_escape_hatch", properties: [:])
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

    private static func nextFireDate(hour: Int, minute: Int, after date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return date.addingTimeInterval(86_400) }
        if candidate > date { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86_400)
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
    // comment's `decisions` note on why this doesn't live in `Store/SharedDefaults.swift`)

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

    private static let settingsKey = "core.sunriseAlarm.settings.v1"
    private static let dailyStateKey = "core.sunriseAlarm.dailyState.v1"
}

#if canImport(AlarmKit)
/// Best-effort `AlarmMetadata` payload — see `scheduleViaAlarmKit`'s header warning. Empty on
/// purpose: nothing in this alert needs data beyond what `AlarmPresentation.Alert`'s title/stop
/// button already carry.
struct SunriseAlarmMetadata: AlarmMetadata {}
#endif

// MARK: - Escape hatch UI state (spec §5.10 point 6 / §24 point 2)

/// Drives one 60-second escape-hatch hold. Mirrors `LockEngine/EmergencyUnlock.swift`'s exact
/// state-machine shape (same phases, same tick-loop mechanics) — that file already established
/// the correct pattern for "a hold gesture that must reliably fire exactly once, cancel cleanly on
/// early release, and never itself become a place the user can get stuck" for this codebase, and
/// re-deriving a different one here would be the actual risk, not reusing it. Create a fresh
/// instance per hold attempt (e.g. when the escape-hatch sheet appears), same as `EmergencyUnlock`.
@MainActor
@Observable
public final class SunriseAlarmEscapeHatch {
    public enum Phase: Sendable, Equatable {
        case idle
        case holding
        case completing
        case released
    }

    public static let holdDuration: TimeInterval = SunriseAlarmEngineDefaults.escapeHatchHoldDuration
    private static let tickInterval: TimeInterval = 0.05

    public private(set) var phase: Phase = .idle
    public private(set) var progress: Double = 0
    public private(set) var secondsRemaining: Int = Int(SunriseAlarmEscapeHatch.holdDuration)

    private var tickTask: Task<Void, Never>?

    public init() {}

    deinit { tickTask?.cancel() }

    public func beginHold() {
        guard phase == .idle else { return }
        phase = .holding
        progress = 0
        secondsRemaining = Int(Self.holdDuration)

        tickTask?.cancel()
        let startedAt = Date.now
        tickTask = Task { [weak self] in
            await self?.runHold(startedAt: startedAt)
        }
    }

    public func cancelHold() {
        guard phase == .holding else { return }
        tickTask?.cancel()
        tickTask = nil
        progress = 0
        secondsRemaining = Int(Self.holdDuration)
        phase = .idle
    }

    private func runHold(startedAt: Date) async {
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(startedAt)
            if elapsed >= Self.holdDuration {
                progress = 1
                secondsRemaining = 0
                await completeHold()
                return
            }
            progress = elapsed / Self.holdDuration
            secondsRemaining = max(0, Int((Self.holdDuration - elapsed).rounded(.up)))
            try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
        }
    }

    private func completeHold() async {
        phase = .completing
        await SunriseAlarmManager.shared.releaseViaEscapeHatch()
        phase = .released
    }
}
