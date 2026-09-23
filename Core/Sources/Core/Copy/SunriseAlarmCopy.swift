// Core/Sources/Core/Copy/SunriseAlarmCopy.swift
//
// User-facing copy for the Bedtime Gate & Sunrise Alarm (docs/spec.md §5.10 — "This is a headline
// v2 feature, not a footnote"). Per CLAUDE.md ("user-facing copy lives in Core/Sources/Core/Copy
// — no hardcoded UI strings elsewhere") and this task's own instruction ("own a new
// Core/Sources/Core/Copy/SunriseAlarmCopy.swift"), `SunriseAlarmManager` and `BedtimeGateManager`
// (Core/Sources/Core/Verification, same task) never build a `String` for a notification, Live
// Activity, or on-screen alarm/wind-down moment themselves — they call into this file and render
// whatever it returns, exactly like `ShieldCopy` already does for the Living Shield.
//
// The one hard rule this file exists partly to enforce (docs/spec.md §5.10, last line): **never
// promise a guaranteed wake-up.** "A real alarm that makes you get up," never "this will always
// wake you." Every string below that touches the alarm itself was written to keep that promise;
// `onboardingDisclaimer` and `standardAlarmReminder` say it outright so it shows up in setup, not
// just implicitly through careful phrasing elsewhere.
//
// Voice (docs/spec.md §5.13: Hype/Tough Love/Chill/Data): NOTHING in this file takes a voice today
// — this header used to claim the ring, wind-down and dismissed-confirmation copy were voice-aware,
// but none of those functions accepts one (docs/design/writing-findings.md §2.1). Voicing them
// needs a `CoachVoice` parameter and is future work. Every string touching the **escape hatch**,
// the **no-guarantee disclaimer**, or the **snooze penalty** must stay fixed across voices in any
// case, mirroring `ShieldCopy.Buttons`'s and `.emergencyNotification`'s documented reasoning:
// these are safety/wayfinding moments, not personality moments, and a half-asleep user reading
// them at 6 AM needs exactly the same, predictable words every time.

import Foundation

public enum SunriseAlarmCopy {

    // MARK: - Onboarding / setup (never promise a guaranteed wake-up — spec §5.10)

    /// Shown once during Sunrise Alarm setup, before the user turns it on. Voice-invariant by
    /// design — see this file's header comment.
    public static let onboardingDisclaimer =
        "This is a real alarm that makes you get up — not a guaranteed wake-up. Keep your phone's " +
        "standard alarm on too, just in case."

    /// Shorter version for a settings-screen footnote/tooltip, once the user already has it on.
    public static let standardAlarmReminder =
        "Keep a standard alarm as backup. ZANO makes staying in bed harder. It can't guarantee you'll wake up."

    /// Explains why the tier differs by iOS version (spec §5.10: "Be explicit in onboarding about
    /// which tier the user's phone supports").
    public static func tierExplanation(tier: SunriseAlarmTier) -> String {
        switch tier {
        case .alarmKit:
            "Your phone supports ZANO's full alarm: it can sound even in Silent Mode and through Focus."
        case .notifications:
            "Your phone uses ZANO's fallback alarm: a chain of escalating alerts. It respects Silent " +
            "Mode and Focus the way any notification does — for the strongest alarm, update to the " +
            "newest iOS when you can."
        }
    }

    // MARK: - Ringing (escalating notification/Live Activity copy)

    /// One escalation step's title/body for the notification-chain fallback tier (spec §5.10:
    /// "iOS 17–18 fallback: scheduled local notifications... ≤30s each, chained"). `index` is
    /// `0` for the first alert, increasing with every 30-second step — later steps read more
    /// urgent, capping out rather than escalating forever.
    public static func ringingNotification(escalationIndex index: Int, variant: SunriseAlarmManager.DismissVariant) -> (title: String, body: String) {
        let title = index == 0 ? "Wake up" : (index < 4 ? "Still asleep?" : "ZANO alarm — get up")
        let body: String
        switch variant {
        case .tag:
            body = "Tap the Sunrise Tag to turn this off."
        case .steps:
            body = "Walk to turn it off — this stops once you've taken enough steps."
        case .focus:
            body = "Open ZANO and start your 3-minute wake-up timer to stop this."
        case .squad:
            // Squad check-in is hold-to-confirm in `AlarmRingingView` (no tag scan), so every
            // string for this variant says that, once and the same way.
            body = "Open ZANO and hold to confirm you're up. A squadmate gets pinged if you don't."
        }
        return (title, body)
    }

    /// The alert shown by the system alarm UI itself for the AlarmKit tier (iOS 26+, spec §5.10).
    /// AlarmKit's own presentation renders this, so it stays short and does not repeat escalation
    /// language the notification-chain fallback needs (the system alert is already unmissable).
    public static func alarmKitAlertTitle(variant: SunriseAlarmManager.DismissVariant) -> String { "Wake up" }

    public static func alarmKitStopButtonLabel(variant: SunriseAlarmManager.DismissVariant) -> String {
        switch variant {
        // "I'm up" read as self-attestation dismissing the alarm — the opposite of the tag
        // mechanic, and not what the squad variant does either. Both finish inside ZANO.
        case .tag, .squad: "Open ZANO"
        case .steps: "Walking"
        case .focus: "Start wake-up timer"
        }
    }

    public static let alarmKitSnoozeButtonLabel = "Snooze"

    /// The notification-fallback tier's action button label (`UNNotificationAction`) — shown when
    /// the user long-presses/expands a ringing notification.
    public static let notificationOpenActionLabel = "Open ZANO"

    // MARK: - Live Activity (17–18 fallback tier — spec §5.10: "plus a Live Activity")

    public static func ringingActivityTitle(variant: SunriseAlarmManager.DismissVariant) -> String { "ZANO alarm" }

    public static func ringingActivitySubtitle(variant: SunriseAlarmManager.DismissVariant) -> String {
        switch variant {
        case .tag: "Tap the Sunrise Tag to stop it"
        case .steps: "Keep walking to stop it"
        case .focus: "Start your wake-up timer to stop it"
        case .squad: "Hold to confirm you're up — or a squadmate gets pinged in 10 min"
        }
    }

    // MARK: - Dismiss confirmations

    public static func dismissedConfirmation(variant: SunriseAlarmManager.DismissVariant) -> String {
        switch variant {
        case .tag: "Morning verified. Locked in for the day."
        case .steps: "Steps counted. Morning verified — locked in for the day."
        case .focus: "Wake-up timer done. Morning verified — locked in for the day."
        case .squad: "Morning verified. Locked in for the day."
        }
    }

    public static func stepsProgress(steps: Int, target: Int) -> String {
        let remaining = max(0, target - steps)
        return remaining == 0
            ? "Steps done — dismissing…"
            : "\(steps)/\(target) steps. \(remaining) more to go."
    }

    public static func focusProgress(secondsRemaining: Int) -> String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%d:%02d left — stay in the app", minutes, seconds)
    }

    // MARK: - Snooze (voice-invariant — a penalty/limit rule, not a personality moment)

    public static let snoozeConfirmation = "Snoozed for 5 minutes. That's your one for today."

    public static let snoozeUnavailable =
        "You've used your snooze. Snoozing again would break your morning goal."

    public static let snoozeLimitBrokeGoal =
        "Morning goal slipped: that was your second snooze. Tomorrow's alarm is a fresh start."

    // MARK: - Escape hatch (spec §5.10 point 6, §24 — voice-invariant, never trap the user)

    public static let escapeHatchLabel = "I'm not home"

    public static let escapeHatchExplanation =
        "Hold for 60 seconds to turn the alarm off without verifying your morning goal. Use this if " +
        "you're traveling or the alarm went off somewhere you can't reach your Sunrise Tag."

    public static func escapeHatchHolding(secondsRemaining: Int) -> String {
        "Keep holding — \(secondsRemaining)s"
    }

    public static let escapeHatchReleased = "Alarm off. Your morning goal wasn't verified today — that's okay."

    // MARK: - Squad add-on (spec §5.10: "a friend gets notified if you don't dismiss within 10 min")

    public static func squadFriendNotified(friendName: String?) -> String {
        let name = friendName ?? "Your squadmate"
        return "\(name) got pinged — you hadn't dismissed your alarm in 10 minutes."
    }

    public static let squadWillNotifySoon = "Still not dismissed. A squadmate gets notified in a few minutes."

    // MARK: - Bedtime Gate: wind-down (spec §5.10 — "Bedtime lock in 10 min")

    public static func windDownNotification(minutesUntilBedtime: Int) -> (title: String, body: String) {
        (
            title: "Bedtime lock in \(minutesUntilBedtime) min",
            body: "Distracting apps lock at bedtime. Wrap it up."
        )
    }

    public static func windDownActivityTitle(minutesUntilBedtime: Int) -> String {
        minutesUntilBedtime > 0 ? "Bedtime lock in \(minutesUntilBedtime) min" : "Locking up for the night"
    }

    public static let bedtimeLockedNotificationTitle = "Locked in for the night"
    public static let bedtimeLockedNotificationBody = "Your phone's a clock now. See you at sunrise."

    // MARK: - Sleep goal / pickups after bedtime (spec §3 "Sleep on time" anti-cheat)

    public static let pickupAfterBedtimeTitle = "Late-night pickup"
    public static let pickupAfterBedtimeBody =
        "Phone picked up after bedtime. It counts against tonight's Sleep goal. You'll see it in the morning recap."

    // MARK: - Settings summary lines

    public static func dismissVariantSummary(_ variant: SunriseAlarmManager.DismissVariant) -> String {
        switch variant {
        case .tag: "Tap your Sunrise Tag to turn off the alarm."
        case .steps: "Walk to turn off the alarm — no tag needed yet."
        case .focus: "A 3-minute wake-up timer turns off the alarm."
        case .squad: "Hold to confirm you're up. A squadmate is pinged if you don't within 10 min."
        }
    }
}

/// Which technical tier is scheduling the alarm right now (spec §5.10's own split) — used only to
/// pick the right onboarding/settings copy; `SunriseAlarmManager` owns the actual scheduling
/// decision and passes its result in here.
public enum SunriseAlarmTier: String, Sendable, Equatable, Codable {
    case alarmKit
    case notifications
}
