// SleepCopy.swift
// Core / Copy
//
// Display copy for the sleep wind-down (session 18; docs/spec.md §5.25). Plain, calm, never medical,
// never shaming; like the other settings explainers it is not voice-switched.

import Foundation

extension Copy {
    public enum sleep {
        // MARK: Morning check-in (Today)
        public static let checkInTitle = "How rested do you feel?"
        public static let checkInThanks = "Thanks, noted."
        public static let skipButton = "Skip"
        public static func ratingLabel(_ rating: Int) -> String {
            switch rating {
            case 1: "Drained"
            case 2: "Tired"
            case 3: "Okay"
            case 4: "Good"
            default: "Great"
            }
        }

        // MARK: Settings
        public static let rowLabel = "Sleep insights"
        public static let screenTitle = "Sleep"
        public static let intro = "One tap each morning. After a few weeks ZANO shows what actually helps you sleep better, and can suggest a gentler bedtime. It all stays on your phone."
        public static let checkInToggle = "Morning check-in"
        public static let healthToggle = "Use Apple Health sleep"
        public static let healthDetail = "Reads how long you slept. ZANO never writes to Health."
        public static func nightsRated(_ count: Int) -> String {
            count == 1 ? "1 night rated" : "\(count) nights rated"
        }
        public static let needsMoreNights = "ZANO needs 10 rated nights before it shows patterns."
        public static let insightsTitle = "What seems to help you"
        public static let noPatternYet = "No clear pattern yet. That's normal; keep checking in."
        public static let footer = "These are patterns in your own notes, not medical advice."
        public static let deleteButton = "Delete my sleep notes"

        private static func score(_ value: Double) -> String { String(format: "%.1f", value) }

        public static func insightLine(_ insight: SleepInsight) -> String {
            let when: String
            switch insight.kind {
            case .windDown: when = "you left your phone alone after bedtime"
            case .duration: when = "you slept 7 hours or more"
            case .consistency: when = "you went to bed near your usual time"
            }
            return "On nights \(when) you felt \(score(insight.betterAverage)) out of 5, vs \(score(insight.otherAverage)) on other nights (\(insight.betterNights) and \(insight.otherNights) nights)."
        }

        // MARK: Bedtime suggestion
        public static let suggestionTitle = "Try a slightly earlier bedtime?"
        public static func suggestionBody(bedtime: Date, suggestion: SleepBedtimeSuggestion) -> String {
            let time = bedtime.formatted(.dateTime.hour().minute())
            return "Nights around \(time) you felt \(score(suggestion.groupAverage)) out of 5, vs \(score(suggestion.overallAverage)) overall (\(suggestion.basedOnNights) nights). It's only a suggestion."
        }
        public static func useBedtimeButton(bedtime: Date) -> String {
            "Use \(bedtime.formatted(.dateTime.hour().minute()))"
        }
        public static let notNowButton = "Not now"

        // MARK: A rough stretch
        public static let roughStretch = "Rough few mornings? That happens. ZANO won't push a sleep plan right now. If sleep stays hard, it can be worth mentioning to a doctor."
    }
}
