// WeeklyRecapCopy.swift
// Core / Copy
//
// The weekly recap's coach line, written on device from templates (docs/spec.md §9.6 asks for "one
// specific win, one specific suggestion, no shame, max 60 words, coach voice"; the server LLM job
// doesn't exist yet and Apple's Foundation Models framework isn't in the SDK we build with, so
// this is the template version). `WeeklyRecapBuilder` picks the facts; this file only phrases them
// per voice (spec §5.13).
//
// Rules: a win is always something that happened (never "you only..."); a suggestion is one small
// additive step (spec §24: additive goals only, §8 rule 9: no shame). Under 60 words in every case.

import Foundation

extension Copy {
    public enum weeklyRecap {

        /// The one win the line leads with, most specific first.
        public enum Win: Sendable, Equatable {
            /// More goals completed than last week.
            case improved(by: Int)
            /// Days with an earned unlock.
            case earnedDays(Int)
            /// Total time locked in, in minutes.
            case lockedMinutes(Int)
            /// Goals completed this week.
            case goalsCompleted(Int)
            /// Times the user closed a shielded app instead of opening it.
            case closes(Int)
        }

        /// The one suggestion it ends on.
        public enum Suggestion: Sendable, Equatable {
            /// Give the goal with the lowest ring a set time next week.
            case planGoal(title: String)
            /// Repeat what worked on the best day.
            case repeatBestDay(String)
            /// Everything closed: keep the plan.
            case keepPlan
        }

        public static func coachLine(voice: CoachVoice, win: Win, suggestion: Suggestion) -> String {
            "\(winSentence(voice: voice, win: win)) \(suggestionSentence(voice: voice, suggestion: suggestion))"
        }

        static func winSentence(voice: CoachVoice, win: Win) -> String {
            switch win {
            case .improved(let n):
                let goals = n == 1 ? "1 more goal" : "\(n) more goals"
                switch voice {
                case .hype: return "\(goals) than last week. That's real progress!"
                case .toughLove: return "\(goals) than last week. That's the direction."
                case .chill: return "\(goals) than last week. Nice and steady."
                case .data: return "Goals completed: +\(n) vs last week."
                }
            case .earnedDays(let n):
                let days = n == 1 ? "1 day" : "\(n) days"
                switch voice {
                case .hype: return "You earned your apps back \(days) this week!"
                case .toughLove: return "\(days) earned this week. You did the work."
                case .chill: return "\(days) earned this week. Good stuff."
                case .data: return "Earned days: \(n) of 7."
                }
            case .lockedMinutes(let minutes):
                let time = hours(minutes)
                switch voice {
                case .hype: return "\(time) locked in this week. Huge!"
                case .toughLove: return "\(time) locked in. That time was yours."
                case .chill: return "\(time) locked in this week. That's time back."
                case .data: return "Locked in: \(time)."
                }
            case .goalsCompleted(let n):
                let goals = n == 1 ? "1 goal" : "\(n) goals"
                switch voice {
                case .hype: return "\(goals) done this week. Let's build on it!"
                case .toughLove: return "\(goals) done. Build on it."
                case .chill: return "\(goals) done this week."
                case .data: return "Goals completed: \(n)."
                }
            case .closes(let n):
                let times = n == 1 ? "once" : "\(n) times"
                switch voice {
                case .hype: return "You closed a locked app \(times) instead of scrolling!"
                case .toughLove: return "You closed a locked app \(times). That's discipline."
                case .chill: return "You closed a locked app \(times) this week."
                case .data: return "Locked-app closes: \(n)."
                }
            }
        }

        static func suggestionSentence(voice: CoachVoice, suggestion: Suggestion) -> String {
            switch suggestion {
            case .planGoal(let title):
                switch voice {
                case .hype: return "Next week: give \(title) a set time and watch it climb."
                case .toughLove: return "Next week, put \(title) on a set time."
                case .chill: return "Maybe give \(title) a set time next week."
                case .data: return "Suggestion: schedule \(title) at a fixed time."
                }
            case .repeatBestDay(let day):
                switch voice {
                case .hype: return "\(day) was your best day. Do it again!"
                case .toughLove: return "\(day) was your best. Repeat it."
                case .chill: return "\(day) went well. Same again next week?"
                case .data: return "Best day: \(day). Repeat that setup."
                }
            case .keepPlan:
                switch voice {
                case .hype: return "Every ring closed. Same plan, next week!"
                case .toughLove: return "Every ring closed. Keep the plan."
                case .chill: return "Everything closed. Keep doing what you're doing."
                case .data: return "All rings closed. No change suggested."
                }
            }
        }

        /// "45 min", "3h", "4.5h".
        static func hours(_ minutes: Int) -> String {
            if minutes < 60 { return "\(minutes) min" }
            let tenths = Int((Double(minutes) / 6).rounded())
            return tenths % 10 == 0 ? "\(tenths / 10)h" : "\(tenths / 10).\(tenths % 10)h"
        }

        // MARK: - Screen time saved (session 37)
        //
        // An estimate from ZANO's own locks and shield taps. Apple's Screen Time numbers can only be
        // read inside the DeviceActivityReport extension, so this copy never says "screen time" as
        // if it were Apple's figure: it names exactly what was counted. These are stat labels on
        // the recap card and poster (like `Copy.progress`'s), so they aren't voiced; the voiced part
        // of the recap is the coach line above.

        /// Story page eyebrow and the full name of the stat.
        public static let appsLockedTitle = "Time your apps stayed locked"
        /// Short form under a big numeral (poster hero caption).
        public static let appsLockedCaption = "Apps stayed locked"

        /// Recap card stat cell: "6h 40m apps stayed locked" (numeral, then the unit line).
        public static func appsLockedLabel(duration: String) -> String { "\(duration) apps stayed locked" }

        /// Change against last week, stated as a fact (spec §8 rule 9: no shame for a lower week).
        public static func appsLockedVsLastWeek(deltaMinutes: Int) -> String {
            if deltaMinutes > 0 { return "+\(Copy.progress.duration(minutes: deltaMinutes)) vs last week" }
            if deltaMinutes < 0 { return "\(Copy.progress.duration(minutes: -deltaMinutes)) less than last week" }
            return "Same as last week"
        }

        /// "Reached for a locked app 12 times, closed it 5". `nil` when neither happened.
        public static func reachedLine(attempts: Int, closes: Int) -> String? {
            let reached = "Reached for a locked app \(attempts) \(attempts == 1 ? "time" : "times")"
            switch (attempts > 0, closes > 0) {
            case (true, true): return "\(reached), closed it \(closes)"
            case (true, false): return reached
            case (false, true): return "Closed a locked app \(closes) \(closes == 1 ? "time" : "times")"
            case (false, false): return nil
            }
        }

        /// Short form for the share poster's one-line sticker. `nil` when neither happened.
        public static func reachedPill(attempts: Int, closes: Int) -> String? {
            if attempts > 0 { return "Reached for a locked app \(attempts)×" }
            if closes > 0 { return "Closed a locked app \(closes)×" }
            return nil
        }

        /// Says where the numbers come from, wherever they're shown in-app.
        public static let screenTimeFootnote = "Counted from your ZANO locks, not Apple Screen Time."

        /// The quiet lines under the recap card's stats: the comparison with last week (when there
        /// was a last week) and the reached/closed counts.
        public static func timeSavedNotes(appsLockedDeltaMinutes: Int?, attempts: Int, closes: Int) -> [String] {
            var notes: [String] = []
            if let appsLockedDeltaMinutes { notes.append(appsLockedVsLastWeek(deltaMinutes: appsLockedDeltaMinutes)) }
            if let reached = reachedLine(attempts: attempts, closes: closes) { notes.append(reached) }
            return notes
        }
    }
}
