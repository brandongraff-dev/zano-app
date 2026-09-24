// ProgressCopy.swift
// Core / Copy
//
// `Copy.progress` — every user-facing string `App/ZANO/Features/Progress/ProgressView.swift` calls,
// under the `Copy.<area>.<key>` umbrella this codebase actually uses (see `Copy.swift`'s header).
// This is a reconciliation, not new scope: `ProgressView.swift`'s own "ASSUMED API" header comment
// already documents this exact key list — this file adds the umbrella shape that view already
// calls. `Copy.badges.*` (`TrophyCosmeticsCopy.swift`, this same directory) and `Copy.common.ok`
// (`CommonCopy.swift`) are reused as-is, not redeclared here, per that same header's own note that
// they're shared with `TrophyCaseView.swift`. `App/ZANO/Features/Share/WeeklyRecapShareView.swift`
// also reuses `Copy.progress.bestDayLabel(day:)`/`.unknownGoalLabel` from this file rather than
// declaring its own near-duplicates (see that file's own header + `ShareCopy.swift`, this same
// sweep). Repo-wide sweep (2026-09-22): this namespace was referenced but never declared anywhere
// in `Core/Sources/Core/Copy`, which would have failed to compile.

import Foundation

extension Copy {
    public enum progress {
        public static let screenTitle = "Progress"
        public static let timeReclaimedTitle = "Time reclaimed"
        /// Day 1, before any lock has ended: what the number will count and how to start it.
        public static let timeReclaimedEmptyMessage =
            "Every minute your apps stay locked lands here. Finish your first lock to start the count."
        /// Under the hero numeral: "4h 0m in the last 7 days".
        public static func last7DaysReclaimedLabel(duration: String) -> String { "\(duration) in the last 7 days" }
        /// The hero's context line when this week is empty but earlier weeks are not.
        public static let last7DaysEmptyLabel = "Nothing reclaimed in the last 7 days yet"

        public static let streakSectionTitle = "Streak"
        /// The streak numeral: "14 days" (the number renders big, "days" as its unit).
        public static func streakValue(days: Int) -> String { "\(days) \(days == 1 ? "day" : "days")" }
        /// Day 1: no earned day yet, so the calendar shows one week and this line says what fills it.
        public static let streakEmptyMessage =
            "Your streak starts with your first earned unlock. Finish today's goals to light up the first day."
        /// VoiceOver for the streak calendar: "12 of 28 days earned".
        public static func streakCalendarAccessibilityLabel(earned: Int, total: Int) -> String {
            "\(earned) of \(total) days earned"
        }
        public static func streakBestLabel(best: Int) -> String { "Best: \(best) \(best == 1 ? "day" : "days")" }
        public static func streakFreezesLabel(freezesLeft: Int) -> String {
            "\(freezesLeft) freeze\(freezesLeft == 1 ? "" : "s") left"
        }

        public static let badgesSectionTitle = "Trophy Case"
        public static let badgesEmptyMessage = "Your first badge comes with your first earned unlock."

        public static let recapSectionTitle = "This week"
        public static let recapEmptyMessage = "Your first weekly recap shows up once a full week of data is in."

        public static func weekLabel(weekStart: Date) -> String {
            "Week of \(weekLabelFormatter.string(from: weekStart))"
        }

        public static func goalsCompletedLabel(completed: Int, planned: Int) -> String {
            "\(completed) of \(planned) goals"
        }

        public static func timeReclaimedLabel(duration: String) -> String { "\(duration) reclaimed" }
        public static func bestDayLabel(day: String) -> String { "Best day: \(day)" }

        /// Says what moved ("Up 2 ranks"), not a bare number, and uses "slipped" rather than
        /// "Down" — the only loss word in Progress (docs/spec.md §8 rule 9).
        public static func rankMovementLabel(delta: Int) -> String {
            if delta > 0 { return "Up \(delta) \(delta == 1 ? "rank" : "ranks")" }
            if delta < 0 { return "Slipped \(-delta) \(delta == -1 ? "rank" : "ranks")" }
            return "Holding steady"
        }

        public static let unknownGoalLabel = "A goal"

        // MARK: - Durations (shared by Progress and the weekly recap share)

        /// Compact duration for numerals, bars and cards: "45m", "1h 10m".
        public static func duration(minutes: Int) -> String {
            let safe = max(0, minutes)
            let hours = safe / 60
            let mins = safe % 60
            guard hours > 0 else { return "\(mins)m" }
            return "\(hours)h \(mins)m"
        }

        /// The same duration as VoiceOver should say it: "45 minutes", "1 hour 10 minutes", "2 hours".
        /// "12m" read aloud is "12 meters".
        public static func spokenDuration(minutes: Int) -> String {
            let safe = max(0, minutes)
            let hours = safe / 60
            let mins = safe % 60
            let minutePart = "\(mins) \(mins == 1 ? "minute" : "minutes")"
            guard hours > 0 else { return minutePart }
            let hourPart = "\(hours) \(hours == 1 ? "hour" : "hours")"
            return mins == 0 ? hourPart : "\(hourPart) \(minutePart)"
        }

        // MARK: - First week (empty-states pass 2026-09-24)
        //
        // Before any lock has ended: the hero at 0, a row of seven empty days starting today, and a
        // short list of what this screen will show once there is data.

        /// Over the seven empty day dots.
        public static let firstWeekStartsToday = "Your first week starts today"
        /// VoiceOver for the seven dots.
        public static let firstWeekDotsAccessibility = "Your first week starts today. Seven days to fill."
        /// Heading over the preview list.
        public static let firstWeekComingUpTitle = "What shows up here"
        public static let firstWeekComingUpDaily = "Time reclaimed, day by day"
        public static let firstWeekComingUpStreak = "Your streak, one earned day at a time"
        public static let firstWeekComingUpRecap = "A weekly recap you can share"

        /// The streak numeral before any earned day: today is day one, not "0 days".
        public static let streakDayOne = "Day 1"
        /// VoiceOver for the streak header before any earned day.
        public static let streakDayOneAccessibility = "Streak, day 1. Your first earned unlock starts it."

        private static let weekLabelFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d"
            formatter.timeZone = .current
            return formatter
        }()
    }
}
