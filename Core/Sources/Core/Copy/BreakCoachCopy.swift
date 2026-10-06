// BreakCoachCopy.swift
// Core / Copy
//
// Display copy for the focus break nudge (session 25; docs/spec.md §5.29). Kind and short.

import Foundation

extension Copy {
    public enum breakCoach {
        public static let done = "Done"

        public static func title(_ suggestion: BreakSuggestion) -> String {
            suggestion.isLong
                ? "Nice run. Take a proper \(suggestion.minutes)-minute break."
                : "Nice block. Take \(suggestion.minutes) minutes."
        }

        public static func line(_ activity: BreakActivity) -> String {
            switch activity {
            case .water: return "Drink a glass of water."
            case .stretch: return "Stand up and stretch your back and neck."
            case .lookAway: return "Look at something far away for a minute to rest your eyes."
            case .walk: return "Walk to another room and back."
            }
        }
    }
}
