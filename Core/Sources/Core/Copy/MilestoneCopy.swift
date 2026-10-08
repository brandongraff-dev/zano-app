// MilestoneCopy.swift
// Core / Copy
//
// `Copy.milestone`: every user-facing string for the shareable milestone moments
// (`Retention/Milestones.swift`, `App/ZANO/Features/Share/{MilestoneCardView,MilestoneMomentView,
// MonthlyStoryView}.swift`).
//
// Rules this file keeps:
//   - Honest numbers only. Hours are "hours locked in" (time the apps were locked), never "screen
//     time saved": real screen time is only visible inside the Screen Time report extension.
//   - Additive and positive. Nothing here celebrates eating less, weight, or restriction; every line
//     is about showing up, earning, and doing the work.
//   - The poster lines are first person and voice-neutral (they get posted publicly). The coach line
//     under the poster on screen is per voice (Hype / Tough Love / Chill / Data).
//   - Share text names ZANO so a post leads back to the app.

import Foundation

extension Copy {
    public enum milestone {

        // MARK: Moment chrome

        /// Above the card on the moment screen.
        public static let momentHeadline = "New milestone"
        public static let monthlyMomentHeadline = "Your month, ready to post"
        public static let notNowLabel = "Not now"
        /// VoiceOver hint on the monthly story pager.
        public static let monthlySwipeHint = "Swipe left or right to change page"

        // MARK: Poster: eyebrow, numeral, unit, line

        public static func eyebrow(for milestone: Milestone) -> String {
            switch milestone {
            case .streak: "Streak milestone"
            case .lockedHours: "Hours locked in"
            case .earnedUnlocks(let count): count == 1 ? "First earned unlock" : "Earned unlocks"
            case .earlyBird: "Early bird"
            case .monthlyStory(let story): monthEyebrow(monthName: story.monthName())
            case .yearInReview(let review): yearEyebrow(year: review.year)
            }
        }

        /// The giant numeral. The early bird shows the check-in time ("5:48 AM").
        public static func numeral(for milestone: Milestone) -> String {
            switch milestone {
            case .streak(let days): "\(days)"
            case .lockedHours(let hours): "\(hours)"
            case .earnedUnlocks(let count): "\(count)"
            case .earlyBird(let checkInAt): checkInAt.formatted(date: .omitted, time: .shortened)
            case .monthlyStory(let story): "\(story.earnedDays)"
            case .yearInReview(let review): "\(review.earnedDays)"
            }
        }

        /// The unit under the numeral.
        public static func unit(for milestone: Milestone) -> String {
            switch milestone {
            case .streak: "day streak"
            case .lockedHours: "hours locked in"
            case .earnedUnlocks(let count): count == 1 ? "earned unlock" : "earned unlocks"
            case .earlyBird: "gym check-in"
            case .monthlyStory, .yearInReview: monthDaysUnit
            }
        }

        /// The poster's one line: first person, voice-neutral, made to be posted.
        public static func posterLine(for milestone: Milestone) -> String {
            switch milestone {
            case .streak(let days):
                "\(days) days in a row of earning my screen time back."
            case .lockedHours:
                "My apps stayed locked while I did the work."
            case .earnedUnlocks(let count):
                count == 1
                    ? "First time I earned my apps back. Not the last."
                    : "\(count) times I earned my apps back."
            case .earlyBird:
                "At the gym before 7 AM. My apps waited."
            case .monthlyStory:
                monthIntroLine
            case .yearInReview:
                yearIntroLine
            }
        }

        // MARK: Coach line (on screen, per voice)

        public static func coachLine(for milestone: Milestone, voice: CoachVoice) -> String {
            switch milestone {
            case .streak(let days):
                switch voice {
                case .hype: return "\(days) DAYS. You're on fire. Show them!"
                case .toughLove: return "\(days) days of keeping your word. Don't stop now."
                case .chill: return "\(days) days, one at a time. Nice rhythm."
                case .data: return "Streak: \(days) consecutive earned days."
                }
            case .lockedHours(let hours):
                switch voice {
                case .hype: return "\(hours) hours locked in! That's real focus."
                case .toughLove: return "\(hours) hours your apps couldn't touch. Keep it that way."
                case .chill: return "\(hours) hours of quiet. That adds up."
                case .data: return "Locked time: \(hours) hours total."
                }
            case .earnedUnlocks(let count):
                switch voice {
                case .hype:
                    return count == 1 ? "Your first earned unlock! Many more coming." : "\(count) earned unlocks! Let's go!"
                case .toughLove:
                    return count == 1 ? "First one's done. Now make it a habit." : "\(count) unlocks, every one earned. Good."
                case .chill:
                    return count == 1 ? "First one down. Easy does it." : "\(count) unlocks earned. Steady."
                case .data:
                    return count == 1 ? "Earned unlocks: 1. Baseline set." : "Earned unlocks: \(count)."
                }
            case .earlyBird:
                switch voice {
                case .hype: return "Up before the sun and already at the gym!"
                case .toughLove: return "Early start. Most people were still asleep."
                case .chill: return "Early gym, quiet morning. Nice."
                case .data: return "Gym check-in logged before 7:00."
                }
            case .monthlyStory(let story):
                let month = story.monthName()
                switch voice {
                case .hype: return "\(month) was a big one. Show it off!"
                case .toughLove: return "\(story.earnedDays) days earned in \(month). Beat it this month."
                case .chill: return "That was your \(month). Not bad at all."
                case .data: return "\(month): \(story.earnedDays) earned days, best run \(story.bestStreak)."
                }
            case .yearInReview(let review):
                switch voice {
                case .hype: return "\(review.year) was YOURS. \(review.earnedDays) days earned. Show it off!"
                case .toughLove: return "\(review.earnedDays) days earned in \(review.year). Now beat it."
                case .chill: return "That was your \(review.year). A lot of quiet wins."
                case .data: return "\(review.year): \(review.earnedDays) earned days, best run \(review.bestStreak), \(review.lockedHours) hours locked."
                }
            }
        }

        // MARK: Share text (sent alongside the image)

        public static func shareMessage(for milestone: Milestone) -> String {
            switch milestone {
            case .streak(let days):
                "\(days)-day streak on ZANO. My apps stay locked until I hit my goals. #zano"
            case .lockedHours(let hours):
                "\(hours) hours locked in with ZANO. My apps stay locked until I do the work. #zano"
            case .earnedUnlocks(let count):
                count == 1
                    ? "Just earned my apps back on ZANO for the first time. #zano"
                    : "\(count) earned unlocks on ZANO. Goals first, apps after. #zano"
            case .earlyBird:
                "Gym before 7 AM. ZANO kept my apps locked till I showed up. #zano"
            case .monthlyStory(let story):
                "My \(story.monthName()) on ZANO: \(story.earnedDays) days earned. #zano"
            case .yearInReview(let review):
                "My \(review.year) on ZANO: \(review.earnedDays) days earned. #zano"
            }
        }

        /// The share sheet's preview title.
        public static func sharePreviewTitle(for milestone: Milestone) -> String {
            "\(numeral(for: milestone)) \(unit(for: milestone))"
        }

        // MARK: Year in review pages

        public static let yearlyMomentHeadline = "Your year, ready to post"
        public static func yearEyebrow(year: Int) -> String { "Your \(year)" }
        public static let yearIntroLine = "A whole year of earning my screen time back."
        public static let yearHoursLine = "A year of keeping the apps that eat my day locked away."
        public static func yearBestMonthEyebrow(monthName: String) -> String { "Best month: \(monthName)" }
        public static let yearBestMonthUnit = "days earned in one month"
        public static let yearBestMonthLine = "The month I showed up the most."
        public static func yearTopGoalLine(goal: String) -> String { "Top goal of the year: \(goal)" }
        public static func yearUnlocksLine(count: Int) -> String {
            count == 1 ? "1 earned unlock this year." : "\(count) earned unlocks this year."
        }

        // MARK: Monthly story pages

        public static func monthEyebrow(monthName: String) -> String { "Your \(monthName)" }
        public static let monthDaysUnit = "days earned"
        public static let monthIntroLine = "A month of earning my screen time back."

        public static let monthHoursEyebrow = "Hours locked in"
        public static func monthHoursUnit(hours: Int) -> String { hours == 1 ? "hour locked in" : "hours locked in" }
        public static let monthHoursLine = "Locked away from the apps that eat my day."

        public static let monthStreakEyebrow = "Best streak"
        public static func monthStreakUnit(days: Int) -> String { days == 1 ? "day in a row" : "days in a row" }
        public static func monthTopGoalLine(goal: String) -> String { "Top goal: \(goal)" }
        public static func monthUnlocksLine(count: Int) -> String {
            count == 1 ? "1 earned unlock this month." : "\(count) earned unlocks this month."
        }
    }
}
