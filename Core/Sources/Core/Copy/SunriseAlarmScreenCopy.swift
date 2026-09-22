// SunriseAlarmScreenCopy.swift
// Core / Copy
//
// `Copy.alarmRinging`, `Copy.sunriseAlarm`, `Copy.bedtimeGate` — every user-facing string the
// three Sunrise Alarm / Bedtime Gate screens (`App/ZANO/Features/SunriseAlarm/*.swift`) call,
// under the `Copy.<area>.<key>` umbrella this codebase actually uses (see `Copy.swift`'s header;
// `OnboardingCopy.swift`/`PaywallCopy.swift` are the precedent this follows). Every key below is
// taken directly from those three files' own "ASSUMED API" header comments — not re-derived — so
// they compile unchanged against this file.
//
// This is a reconciliation, not new scope: the task that built `SunriseAlarmManager.swift`/
// `BedtimeGateManager.swift` (same directory) was independently instructed to "own a new
// Core/Sources/Core/Copy/SunriseAlarmCopy.swift" as a flat top-level enum, without visibility into
// the `Copy.<area>` umbrella convention `Copy.swift`/`OnboardingCopy.swift` had already
// established, or into these three UI files' own assumed `Copy.alarmRinging`/`Copy.sunriseAlarm`/
// `Copy.bedtimeGate` shape (built concurrently, same wave). Both were reasonable given what each
// could see; only one can be real. This file adds the umbrella shape the UI actually calls, and
// reuses `SunriseAlarmCopy`'s existing wording wherever the two overlap in meaning — the
// safety-critical strings (escape hatch, snooze penalty, "never promise a guaranteed wake-up",
// pickup-after-bedtime) stay defined in exactly one place, `SunriseAlarmCopy`, rather than
// drifting into two. Pure UI chrome (screen titles, section headers, helper text) that
// `SunriseAlarmCopy` never needed is authored fresh here.

import Foundation

// MARK: - Copy.alarmRinging (App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift)

extension Copy {
    public enum alarmRinging {
        public static let headline = "Get up to turn this off."
        public static let eyebrowWaking = "Wake up"
        public static let eyebrowUrgent = "Still asleep?"
        public static let eyebrowCritical = "Get up"

        // Tag
        public static let tagPromptLabel = "Tap your Sunrise Tag to turn off the alarm."
        public static let tagScanButtonLabel = "Scan Sunrise Tag"
        public static let tagScanAlertMessage = "Hold your phone near your Sunrise Tag."
        public static let tagScanNoMatchMessage =
            "That tag isn't set up yet — hold it near your phone again to register it as your Sunrise Tag."
        public static let wrongTagErrorText = "That's a different ZANO tag — find your Sunrise Tag instead."

        // Steps
        public static func stepsPromptLabel(target: Int) -> String {
            "Walk \(target) steps to turn off the alarm."
        }

        // Focus
        public static let focusPromptLabel = "Finish a 3-minute wake-up timer to turn off the alarm."
        public static let focusStartButtonLabel = "Start wake-up timer"

        // Squad
        public static let squadPromptLabel = "Hold to confirm you're up. Your squad gets pinged if you don't."
        public static let squadConfirmButtonLabel = "I'm up"

        // Snooze — reuses SunriseAlarmCopy's voice-invariant snooze-limit wording (see that file's header)
        public static func snoozeButtonLabel(remaining: Int) -> String {
            "Snooze (\(remaining) left)"
        }
        public static let snoozeUsedLabel = SunriseAlarmCopy.snoozeUnavailable

        // Escape hatch — spec §5.10 point 6 / §24, voice-invariant. Reuses SunriseAlarmCopy's
        // escape-hatch/standard-alarm strings directly rather than re-authoring the same promise.
        public static let escapeHatchSectionLabel = "Emergency"
        public static let escapeHatchHoldLabel = "Hold to turn off the alarm without verifying your morning goal"
        public static let escapeHatchHoldHint = SunriseAlarmCopy.escapeHatchExplanation
        public static let imNotHomeToggleLabel = SunriseAlarmCopy.escapeHatchLabel
        public static let standardAlarmFootnote = SunriseAlarmCopy.standardAlarmReminder
    }
}

// MARK: - Copy.sunriseAlarm (App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift)

extension Copy {
    public enum sunriseAlarm {
        public static let screenTitle = "Sunrise Alarm"
        public static let saveButtonLabel = "Save"
        public static let saveErrorTitle = "Couldn't save"

        // Wake time
        public static let wakeTimeSectionHeader = "Wake time"
        public static let wakeTimeLabel = "Wake up at"

        // Dismiss method
        public static let dismissMethodSectionHeader = "How you turn it off"
        public static let dismissMethodFooter =
            "The only way to stop the alarm is completing the step you pick below — that's the point."

        public static func variantTitle(_ variant: SunriseAlarmManager.DismissVariant) -> String {
            switch variant {
            case .tag: "Tap a tag"
            case .steps: "Walk it off"
            case .focus: "Wake-up timer"
            case .squad: "Squad check-in"
            }
        }

        public static func variantDescription(_ variant: SunriseAlarmManager.DismissVariant) -> String {
            switch variant {
            case .tag: "Tap your Sunrise Tag — placed away from your bed — to turn off the alarm."
            case .steps: "Walk a set number of steps to turn off the alarm. Good if you don't have a tag yet."
            case .focus: "Finish a 3-minute wake-up timer to turn off the alarm."
            case .squad: "Hold to confirm you're up. A squadmate is pinged if you don't within 10 minutes."
            }
        }

        // Tag
        public static let tagSectionHeader = "Sunrise Tag"
        public static func tagMappedStatus(count: Int) -> String {
            switch count {
            case 0: "No tag set up yet."
            case 1: "1 tag set up."
            default: "\(count) tags set up."
            }
        }
        public static let tagScanButtonLabel = "Add a Sunrise Tag"
        public static let tagScanAlertMessage = "Hold your phone near your Sunrise Tag."
        public static let tagScanNoMatchMessage = "That tag isn't registered yet — scan again to add it."
        public static let tagScanErrorTitle = "Couldn't read tag"
        public static let tagPlacementHeader =
            "Put it somewhere you have to get up for — bathroom mirror, kitchen, coffee machine."
        public static let tagBackgroundReadHeader = "Turn it off without opening ZANO"
        public static let tagBackgroundReadFooter =
            "Set up a Shortcuts Automation so scanning your tag works even when ZANO isn't open."
        public static let tagTroubleshootingHeader = "Tag not scanning?"
        public static let defaultTagLabel = "Sunrise Tag"
        public static let forgetTagButtonLabel = "Remove"
        public static let forgetTagConfirmTitle = "Remove this Sunrise Tag?"

        // Steps
        public static let stepsSectionHeader = "Steps"
        public static func stepsTargetLabel(target: Int) -> String { "\(target) steps" }
        public static let stepsHelperText = "A short walk, not a workout — enough to prove you're up."

        // Focus
        public static let focusSectionHeader = "Wake-up timer"
        public static let focusHelperText = "A 3-minute timer you have to stay in the app for."

        // Squad
        public static let squadSectionHeader = "Squad"
        public static let squadPickerLabel = "Notify"
        public static let squadNoneOption = "None"
        public static let squadEmptyStateText = "Join a squad to use this option."
        public static let squadHelperText =
            "If you haven't dismissed the alarm in 10 minutes, someone in this squad gets a notification."

        // Tech tier — spec §5.10: "Be explicit in onboarding about which tier the user's phone supports."
        public static let techSectionHeader = "Alarm strength"
        public static let techTierAlarmKitLabel = "Full alarm"
        public static let techTierAlarmKitDetail =
            "Your phone supports ZANO's full alarm — it can sound even in Silent Mode and through Focus."
        public static let techTierFallbackLabel = "Fallback alarm"
        public static let techTierFallbackDetail =
            "Your phone uses ZANO's fallback alarm — a chain of escalating alerts. Update iOS for the strongest version."
        public static let standardAlarmReminderText = SunriseAlarmCopy.standardAlarmReminder
    }
}

// MARK: - Copy.bedtimeGate (App/ZANO/Features/SunriseAlarm/BedtimeGateSetupView.swift)

extension Copy {
    public enum bedtimeGate {
        public static let screenTitle = "Bedtime Gate"
        public static let saveButtonLabel = "Save"
        public static let saveErrorTitle = "Couldn't save"

        public static let bedtimeSectionHeader = "Bedtime"
        public static let bedtimeLabel = "Lock at"

        public static let windDownSectionHeader = "Wind-down reminder"
        public static let windDownToggleLabel = "Remind me 10 minutes before"
        public static let windDownHelperText =
            "A heads-up before your phone locks for the night, so you're not caught mid-scroll."

        public static let pickupsInfoHeader = "Picking up after bedtime"
        public static let pickupsInfoText = SunriseAlarmCopy.pickupAfterBedtimeBody

        public static let wakeAlarmLinkLabel = "Sunrise Alarm"
        public static let wakeAlarmLinkDetail = "Set how you turn off tomorrow's alarm"
    }
}
