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

// MARK: - Ranks, seasons, monthly challenges (spec §5.9) and Gym Home Turf (spec §5.8)
//
// Wave 3J. Rank/season/challenge keys come from `Retention/SeasonsAndRanks.swift`; leaderboard
// states from `Social/GymLeaderboard.swift`. No shame (spec §8 rule 9): Bronze is a starting
// tier, never "below" anything, and a quiet board never says anyone is losing.

extension Copy.progress {
    public static let rankSectionTitle = "Rank"

    public static func rankName(_ rank: SeasonsAndRanks.Rank) -> String {
        switch rank {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .diamond: "Diamond"
        }
    }

    /// "Season 3 · 2026" — calendar quarters.
    public static func seasonLabel(quarter: Int, year: Int) -> String { "Season \(quarter) · \(year)" }
    /// "Ends Sep 30".
    public static func seasonEndsLabel(lastDay: Date) -> String {
        "Ends \(weekLabelFormatter.string(from: lastDay))"
    }
    /// Under the rank during the first week of a season.
    public static func rankPlacementLabel(daysLeft: Int) -> String {
        daysLeft <= 1 ? "Placement week. Ranked tomorrow." : "Placement week. Ranked in \(daysLeft) days."
    }
    /// "62% to Gold".
    public static func rankProgressLabel(percent: Int, next: SeasonsAndRanks.Rank) -> String {
        "\(percent)% to \(rankName(next))"
    }
    public static let rankTopLabel = "Top rank. Hold it through the season."
    /// "Based on your last 4 weeks against your own plan, not volume."
    public static let rankExplainer = "Based on the last 4 weeks against your own plan, not volume."
    public static func rankConsistencyAccessibility(rank: SeasonsAndRanks.Rank, percent: Int) -> String {
        "\(rankName(rank)) rank, \(percent)% consistency over 4 weeks"
    }

    public static let seasonBadgesTitle = "Season badges"
    public static let seasonBadgesEmpty = "Finish a season to keep its badge forever."
    public static let seasonBadgeInProgressTitle = "This season"
    /// Title for a `season_<yyyy>Q<q>_<rank>` badge key, e.g. "Gold · Q3 2026". `nil` for any other key.
    public static func seasonBadgeTitle(forKey key: String) -> String? {
        let parts = key.split(separator: "_")
        guard parts.count == 3, parts[0] == "season",
              let rank = SeasonsAndRanks.Rank(rawValue: String(parts[2])) else { return nil }
        let season = parts[1].split(separator: "Q")
        guard season.count == 2 else { return "\(rankName(rank)) season" }
        return "\(rankName(rank)) · Q\(season[1]) \(season[0])"
    }

    public static let monthlyChallengeSectionTitle = "Monthly challenge"
    /// Spec §5.9's named themes; the other nine months read "<Month> Lock-In".
    public static func monthlyChallengeTitle(themeKey: String, month: Int) -> String {
        switch themeKey {
        case "january_lock_in": return "January Lock-In"
        case "summer_shred_consistency": return "Summer Shred Consistency"
        case "no_skip_november": return "No-Skip November"
        default:
            let names = Calendar(identifier: .gregorian).monthSymbols
            let name = (1...12).contains(month) ? names[month - 1] : "Monthly"
            return "\(name) Lock-In"
        }
    }
    /// "9 of 12 days so far".
    public static func monthlyChallengeProgressLabel(active: Int, expected: Int) -> String {
        "\(active) of \(expected) \(expected == 1 ? "day" : "days") so far"
    }
    public static let monthlyChallengeComplete = "Challenge cleared. The badge is in your Trophy Case."
    public static let monthlyChallengeExplainer = "Show up on your planned days this month. Any verified goal counts."
    /// "Ends in 6 days".
    public static func monthlyChallengeEndsLabel(daysLeft: Int) -> String {
        daysLeft <= 1 ? "Last day" : "Ends in \(daysLeft) days"
    }

    // Gym Home Turf (spec §5.8)
    public static let gymBoardRowTitle = "Gym Home Turf"
    public static let gymBoardRowSubtitle = "Most consistent at your gym this month"
    public static let gymBoardScreenTitle = "Gym Home Turf"
    public static let gymBoardYourConsistencyTitle = "Your last 30 days"
    /// "18 of 30 days at the gym".
    public static func gymBoardConsistencyLabel(days: Int, total: Int) -> String {
        "\(days) of \(total) days at the gym"
    }
    /// Spec §5.8 verbatim shape: "You're #4 most consistent at this gym this month."
    public static func gymBoardYourRankLabel(rank: Int) -> String {
        "You're #\(rank) most consistent at this gym this month."
    }
    public static let gymBoardOfflineTitle = "The board needs the network"
    public static let gymBoardOfflineMessage =
        "Gym rankings compare you with other people at your gym, so they load from ZANO's servers. That isn't live yet. Your own consistency above is counted on this iPhone and is always up to date."
    public static let gymBoardErrorMessage = "Couldn't load the board. Your own numbers above are still current."
    public static let gymBoardNoGymTitle = "Save your gym first"
    public static let gymBoardNoGymMessage = "The board is for people who train at the same place. Save and confirm your gym to see it."
    public static let gymBoardEmptyMessage = "Nobody else at this gym has joined yet. You're first on the board."
    public static let gymBoardPrivacyTitle = "Show me on the board"
    public static let gymBoardPrivacyFooter =
        "Off by default. When on, people at your gym see a rank and your handle, or \"Anonymous\" if you leave it blank. Never your name, location, or workouts."
    public static let gymBoardHandlePlaceholder = "Handle (optional)"
    public static let gymBoardHandleSave = "Save handle"
    public static let gymBoardHandleInvalid = "Use 2 to 20 letters, numbers, - or _."
    public static let gymBoardAnonymous = "Anonymous"
    public static let gymBoardYouSuffix = "(you)"
    public static func gymBoardPercent(_ percent: Int) -> String { "\(percent)%" }
    /// "#4".
    public static func gymBoardRankLabel(_ rank: Int) -> String { "#\(rank)" }
    public static func gymBoardRowAccessibility(rank: Int, name: String, percent: Int) -> String {
        "Number \(rank), \(name), \(percent)% consistent"
    }
    public static let gymBoardPickerLabel = "Gym"
    public static let gymBoardUnnamedGym = "Your gym"

}
