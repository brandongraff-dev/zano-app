// GoalsCopy.swift
// Core / Copy
//
// `Copy.goals` — the goal picker, per-type descriptions, "how it's verified" chips, setup next
// steps, and the Apple Health permission primer (App/ZANO/Features/Goals). docs/spec.md §3 (goal
// catalog and verification tiers), §24 (additive goals only; Health data stays on device; no health
// outcome claims — say "consistency", not "lose weight").
//
// The verification lines describe what the app does today, not the full §3 design: goals the app
// currently logs with a confirmation tap say so, rather than promising a timer or photo check that
// isn't built yet.

import Foundation

extension Copy {
    public enum goals {
        // MARK: - Picker

        public static let pickerTitle = "Add a goal"
        public static let pickerSubtitle = "Pick something to do more of. You earn your apps back by doing it."
        public static let pickerAlreadyAdded = "Added"
        public static func pickerAlreadyAddedSpoken(title: String) -> String { "\(title), already on your plan" }

        public static let categoryMove = "Move"
        public static let categoryFuel = "Fuel"
        public static let categoryMind = "Mind"
        public static let categoryMornings = "Mornings"
        public static let categoryCustom = "Your own"

        /// One line under the goal name in the picker.
        public static func description(for type: GoalType) -> String {
            switch type {
            case .workoutGym: "Get to the gym and stay for a real session."
            case .workoutHomeOutdoor: "Train anywhere. Your watch or fitness app logs it."
            case .steps: "Walk your step count."
            case .stretchMobility: "A few minutes of mobility work."
            case .protein: "Hit your protein for the day."
            case .water: "Drink your water."
            case .creatine: "Take your daily creatine."
            case .mealPrep: "Prep your meals for the week."
            case .focusSession: "Deep work with your distracting apps locked."
            case .reading: "Read a book, not a feed."
            case .sunriseAlarm: "Get out of bed to turn the alarm off."
            case .sleepOnTime: "In bed on time, phone down."
            case .coldShowerSauna: "A cold shower or a sauna session."
            case .custom: "Name any habit you want to build."
            }
        }

        /// The "how it's verified" chip.
        public static func verification(for type: GoalType) -> String {
            switch type {
            case .workoutGym: "Verified by gym location"
            case .workoutHomeOutdoor, .steps, .sleepOnTime: "Verified by Apple Health"
            case .focusSession: "Timer on this phone"
            case .protein: "NFC tap, barcode, or one tap"
            case .water, .creatine: "NFC tap or one tap"
            case .sunriseAlarm: "Verified by your Sunrise Tag"
            case .reading, .stretchMobility, .mealPrep: "One tap to log"
            case .coldShowerSauna, .custom: "Honor system"
            }
        }

        public static func tierSpoken(_ tier: VerificationTier) -> String {
            switch tier {
            case .a: "Automatic"
            case .b: "One tap"
            case .c: "Honor system"
            }
        }

        public static func verificationSpoken(tier: VerificationTier, type: GoalType) -> String {
            "\(tierSpoken(tier)). \(verification(for: type))"
        }

        // MARK: - Target step

        public static let targetEyebrow = "Your target"
        public static let targetFooter = "Start smaller than you think. You can raise it anytime."
        public static let targetBinaryMessage = "Once a day. Log it when it's done and it counts."
        public static let targetWeeklyMessage = "Once a week. Log it when it's done and it counts."
        public static let addGoalButton = "Add goal"
        public static let customNameEyebrow = "Name it"
        public static let customNamePlaceholder = "e.g. Practice guitar"
        public static let customNameFooter = "Something to do more of. Keep it short."
        public static let customNameRestrictiveMessage = "ZANO goals are about doing more of something good, so calorie limits, fasting, and weight targets aren't available. Try something you want to build instead."
        public static func targetSpoken(title: String, summary: String) -> String { "\(title) target, \(summary)" }

        // MARK: - Next step

        public static let nextStepEyebrow = "Next step"
        public static func addedTitle(title: String) -> String { "\(title) added" }
        public static let setupLaterButton = "Later"
        public static let doneButton = "Done"

        public static let setupGymTitle = "Save your gym"
        public static let setupGymMessage = "Workouts count when you arrive at your gym and stay for a session. Save its location once."
        public static let setupGymButton = "Set up gym"

        public static let setupTagTitle = "Set up a tag"
        public static let setupTagMessage = "Stick an NFC tag where it happens. One tap logs it, no app to open."
        public static let setupTagButton = "Set up a tag"

        public static let setupHealthTitle = "Connect Apple Health"
        public static let setupHealthMessage = "This goal checks itself off from Apple Health, so there's nothing to log."
        public static let setupHealthButton = "Connect Apple Health"

        // MARK: - Editor cards

        public static let setupNeededLabel = "Needs setup"
        public static let setupGymShort = "Set up gym"
        public static let setupTagShort = "Set up a tag"
        public static let setupHealthShort = "Connect Health"

        // MARK: - Health permission primer

        public static let healthTitle = "Let Apple Health do the logging"
        public static let healthMessage = "ZANO reads your steps, workouts, heart rate, and sleep to check goals off automatically."
        public static let healthPointReadOnly = "Read-only. ZANO never writes to Health."
        public static let healthPointOnDevice = "Stays on this iPhone. Only \"goal done\" is saved."
        public static let healthPointOnlyNeeded = "Only what your goals use."
        public static let healthContinueButton = "Continue"
        public static let healthNotNowButton = "Not now"
        public static let healthDoneTitle = "You're connected"
        public static let healthDoneMessage = "Goals that use Health now check themselves off. Apple doesn't tell apps what you allowed, so if one never counts, check the setting below."
        public static let healthHowToEnableTitle = "To change it later"
        public static let healthHowToEnableSteps = "Open Settings, then Privacy & Security, then Health, then ZANO. Turn on the data you want counted."
        public static let healthUnavailableTitle = "Apple Health isn't available"
        public static let healthUnavailableMessage = "This device doesn't have Apple Health. Log these goals with one tap instead."
        public static let healthFailedMessage = "The Health permission sheet didn't open. Try again in a moment."
        public static let healthTryAgainButton = "Try again"
    }
}
