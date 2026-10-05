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
    }
}
