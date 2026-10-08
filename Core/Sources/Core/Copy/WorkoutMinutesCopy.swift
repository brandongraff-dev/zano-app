// WorkoutMinutesCopy.swift
// Core / Copy
//
// Session 42: workout minutes logged by hand (docs/spec.md §3, Tier C). Used by the "Log minutes"
// sheet (`App/ZANO/Features/Today/LogWorkoutMinutesSheet.swift`), Today's workout tiles, the gym
// check-in screen and `LogWorkoutMinutesIntent`. Honest and plain (spec §9.8): an entry by hand counts
// and is labelled "logged by hand", never questioned.

extension Copy {
    public enum workoutMinutes {
        // MARK: Today

        /// The workout tile's action.
        public static let todayAction = "Log minutes"
        /// The tile's second line once minutes were logged by hand.
        public static let loggedByHand = "logged by hand"
        /// The tile's second line when minutes came from Health/Strava and by hand.
        public static let trackedAndByHand = "tracked + logged by hand"

        // MARK: Sheet

        public static let sheetTitle = "Log minutes"
        public static let headline = "How long did you work out?"
        public static let message = "Home, a park, a hotel room: anywhere counts. Minutes add up through the day."
        public static let tierBadge = "Logged by hand · counts"
        public static func minutesValue(_ minutes: Int) -> String { "\(minutes) min" }
        public static func chipLabel(_ minutes: Int) -> String { "\(minutes)" }
        public static func chipSpoken(_ minutes: Int) -> String { "\(minutes) minutes" }
        public static let decreaseLabel = "Fewer minutes"
        public static let increaseLabel = "More minutes"
        public static let stepperSpokenLabel = "Minutes to log"
        public static func stepperSpokenValue(_ minutes: Int) -> String { "\(minutes) minutes" }
        public static func holdButton(minutes: Int) -> String { "Hold to log \(minutes) min" }
        public static func progressLine(total: Int, required: Int) -> String { "\(total) of \(required) min today" }
        public static func leftLine(_ left: Int) -> String { "\(left) min to go" }
        public static let alreadyDone = "Today's workout is already done. Extra minutes still go in today's total."
        public static let entriesHeader = "Logged today"
        public static func entryLine(minutes: Int) -> String { "\(minutes) min · logged by hand" }
        public static let connectHealthLink = "Connect Apple Health to log workouts on their own"
        public static let setUpGymLink = "Save your gym to check in on its own"
        public static let failed = "Couldn't save that. Try again."
        public static func savedAnnouncement(minutes: Int) -> String { "Logged \(minutes) minutes." }
        public static let completedAnnouncement = "Workout done for today."

        // MARK: Gym screen and setup

        /// Shown wherever gym check-in could look required.
        public static let homeHint = "Working out at home? Log your minutes by hand."
        public static let gymLogInsteadLink = "Worked out somewhere else? Log minutes"
        public static let gymDoneTitle = "Logged by hand"
        public static func gymDoneDetail(minutes: Int) -> String {
            "\(minutes) minutes today. It counts, marked as logged by hand."
        }

        // MARK: Siri / Shortcuts

        public static func intentDialog(minutes: Int, result: ManualWorkoutLogResult) -> String {
            switch result {
            case .completed(let total):
                "Logged \(minutes) minutes. That's \(total) today, and your workout is done."
            case .logged(let total, let required):
                "Logged \(minutes) minutes. \(total) of \(required) today."
            case .loggedAfterDone(let total):
                "Logged \(minutes) minutes. \(total) today, and your workout was already done."
            }
        }
    }
}
