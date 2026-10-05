// OnboardingPlanCopy.swift
// Core / Copy
//
// The if-then plan (implementation intention) on onboarding's plan step, and the reminder nudge it
// seeds. Research item 2 in docs/design/growth-and-ml-research.md: "If it's Mon/Wed/Fri at 6 PM,
// then I go to the gym." Read by `Screen10PlanReveal` (the "When will you do it?" picker and the
// sentence it builds) and `NudgeScheduler` (the reminder ~45 minutes before a planned time).
//
// Wording rules: the plan is the user's own words played back, so it's first person ("I go to the
// gym"), never a command. No stats we can't back up. The reminder names the next step, never a
// loss (spec §8 rules 7 and 9).

import Foundation

extension Copy {
    public enum ifThenPlan {

        // MARK: Picker (plan step)

        public static let sectionLabel = "When will you do it?"
        public static let sectionDetail = "Pick when. A plan with a time is easier to keep."
        public static let daysLabel = "Days"
        public static let timeLabel = "Time"
        public static let noDaysHint = "Pick at least one day."

        /// Row title above a goal's picker.
        public static func rowTitle(for type: GoalType) -> String {
            switch type {
            case .workoutGym: "Gym"
            case .focusSession: "Focus"
            default: "Your goal"
            }
        }

        // MARK: The sentence

        /// "If it's Mon/Wed/Fri at 6 PM, I go to the gym." / "Every day at 9 AM, I start a focus
        /// session." `dayNames` are short day names in week order; `time` is pre-formatted.
        public static func sentence(for type: GoalType, dayNames: [String], isEveryDay: Bool, time: String) -> String {
            let action = actionPhrase(for: type)
            if isEveryDay || dayNames.isEmpty {
                return "Every day at \(time), \(action)."
            }
            return "If it's \(dayNames.joined(separator: "/")) at \(time), \(action)."
        }

        static func actionPhrase(for type: GoalType) -> String {
            switch type {
            case .workoutGym: "I go to the gym"
            case .workoutHomeOutdoor: "I work out"
            case .focusSession: "I start a focus session"
            case .reading: "I read"
            case .stretchMobility: "I stretch"
            default: "I do my goal"
            }
        }

        // MARK: Reminder nudge (NudgeScheduler, ~45 min before the planned time)

        /// Short noun for the planned activity, used in reminder titles.
        static func activityNoun(for type: GoalType) -> String {
            switch type {
            case .workoutGym: "Gym"
            case .workoutHomeOutdoor: "Workout"
            case .focusSession: "Focus"
            case .reading: "Reading"
            case .stretchMobility: "Stretch"
            default: "Your goal"
            }
        }

        /// The reminder before a planned time. `time` is pre-formatted ("6 PM"); `minutesBefore` is
        /// how long until it.
        public static func reminder(tone: NudgeTone, goalType: GoalType, time: String, minutesBefore: Int) -> (title: String, body: String) {
            let noun = activityNoun(for: goalType)
            switch tone {
            case .hype:
                return ("\(noun) at \(time). Let's go!", "That's your plan. \(minutesBefore) minutes to get moving.")
            case .toughLove:
                return ("\(noun) at \(time)", "You planned this. Start getting ready now.")
            case .chill:
                return ("\(noun) at \(time), like you planned", "Just a heads-up. You've got \(minutesBefore) minutes.")
            case .data:
                return ("Plan: \(noun.lowercased()) at \(time)", "Starts in \(minutesBefore) min.")
            }
        }
    }
}
