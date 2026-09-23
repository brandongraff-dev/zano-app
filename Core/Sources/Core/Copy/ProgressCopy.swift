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

        public static let streakSectionTitle = "Streak"
        public static func streakBestLabel(best: Int) -> String { "Best: \(best) \(best == 1 ? "day" : "days")" }
        public static func streakFreezesLabel(freezesLeft: Int) -> String {
            "\(freezesLeft) freeze\(freezesLeft == 1 ? "" : "s") left"
        }

        public static let badgesSectionTitle = "Trophy Case"
        public static let badgesEmptyMessage = "Complete goals to start earning badges."

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
