// ShareCopy.swift
// Core / Copy
//
// `Copy.lockedOut`, `Copy.share` — every user-facing string `App/ZANO/Features/Share/
// {LockedOutMomentView,WeeklyRecapShareView}.swift` call, under the `Copy.<area>.<key>` umbrella
// this codebase actually uses (see `Copy.swift`'s header). This is a reconciliation, not new scope:
// both files' own "ASSUMED API" header comments already document this exact key list — including
// the note that `Copy.share.shareButtonTitle`/`.preparingShareTitle`/`.shareFailedRetryLabel`/
// `.footerWordmark` are deliberately shared between the two screens rather than duplicated, and that
// `Copy.progress.bestDayLabel(day:)`/`.unknownGoalLabel` (already declared in `ProgressCopy.swift`,
// this same sweep) are reused by `WeeklyRecapShareView.swift` rather than re-declared here. Repo-
// wide sweep (2026-09-22): both namespaces were referenced but never declared anywhere in
// `Core/Sources/Core/Copy`, which would have failed to compile.
//
// spec §5.16's literal button name is kept exactly as specified: "a 'Share this' option" ->
// `shareButtonTitle = "Share this"`.

import Foundation

// MARK: - Copy.lockedOut (LockedOutMomentView.swift)

extension Copy {
    public enum lockedOut {
        public static let screenTitle = "Locked out"

        /// The spec-literal line itself, e.g. "My phone won't let me open TikTok until I hit the
        /// gym." Both parameters are caller-resolved short phrases that already fall back to `nil`
        /// when unknown (a category-level shield has no single app name; several required goals
        /// have no single headline one) — mirrors `ShieldCopy.content(for:)`'s own
        /// `shieldedName ?? "This app"` inline fallback rather than a separate variant table.
        public static func headline(appName: String?, blockingGoalSummary: String?) -> String {
            let app = appName ?? "This app"
            guard let blockingGoalSummary else {
                return "My phone won't let me open \(app) right now."
            }
            return "My phone won't let me open \(app) until I \(blockingGoalSummary)."
        }

        public static func statLine(attemptCount: Int, windowMinutes: Int) -> String {
            "\(attemptCount) \(attemptCount == 1 ? "try" : "tries") in the last \(windowMinutes) minutes"
        }

        /// A share card is public, so it never prints a zero streak ("Streak 0"): with no streak it
        /// is just the goals clause. Streak reads "14-day streak", the same form as everywhere else.
        public static func highlightLine(goalsRemaining: Int, streak: Int) -> String {
            let goalsClause = goalsRemaining == 1 ? "1 goal left" : "\(goalsRemaining) goals left"
            guard streak > 0 else { return goalsClause }
            return "\(goalsClause) · \(streak)-day streak"
        }

        /// Was "Turns friction into content. Might as well share it." — that leaked the growth
        /// strategy (spec §5.16's rationale) onto the screen the user sees at their most frustrated.
        public static let acknowledgementLine = "Still locked. Share it and keep yourself honest."
        public static let dismissButtonTitle = "Not now"
    }
}

// MARK: - Copy.share (LockedOutMomentView.swift, WeeklyRecapShareView.swift)

extension Copy {
    public enum share {
        // Shared across every ShareCard export (LockedOutMomentView, WeeklyRecapShareView).
        public static let shareButtonTitle = "Share this"
        public static let preparingShareTitle = "Preparing…"
        public static let shareFailedRetryLabel = "Couldn't prepare the image. Try again."
        public static let footerWordmark = "ZANO"

        // WeeklyRecapShareView.swift only.
        public static let weeklyRecapScreenTitle = "Your week"

        public static func weeklyRecapTitle(weekNumber: Int, rankTierLabel: String?) -> String {
            guard let rankTierLabel else { return "Week \(weekNumber)" }
            return "Week \(weekNumber) · Rank \(rankTierLabel)"
        }

        public static func weeklyRecapStatLine(goalsCompleted: Int, goalsPlanned: Int, timeReclaimedLabel: String) -> String {
            "\(goalsCompleted) of \(goalsPlanned) goals · \(timeReclaimedLabel)"
        }

        public static let dismissButtonTitle = "Close"

        // MARK: Weekly recap story (WeeklyRecapShareView.swift, RecapStoryPages.swift)
        //
        // The recap is a swipeable story: one idea per page, one big number per page. Every string
        // here is additive and shame-free: a light week gets an encouraging line, never a zero hero.

        /// "Sep 14 – Sep 20". Both dates are caller-formatted.
        public static func storyDateRange(start: String, end: String) -> String {
            "\(start) – \(end)"
        }

        // Page 1: intro.
        public static let storyIntroHeadline = "This was your week."
        public static let storyIntroSubline = "Seven days of earning your screen time back."
        public static let storyTapHint = "Tap to continue"

        // Page 2: time reclaimed. The eyebrow reuses `Copy.progress.timeReclaimedTitle`.
        /// Unit under the giant numeral: hours (to one decimal) once there is at least one, minutes
        /// before that. 60-62 minutes displays as "1", hence singular.
        public static func storyTimeUnit(minutes: Int) -> String {
            if minutes >= 60 { return minutes < 63 ? "hour" : "hours" }
            return minutes == 1 ? "minute" : "minutes"
        }
        public static let storyTimeCaption = "Locked away from the apps that eat your day, while you did the work."
        public static let storyTimeEmptyHeadline = "Your locks are warming up."
        public static let storyTimeEmptyCaption = "Set a lock next week and watch this number grow."

        // Page 3: goals earned and streak.
        public static let storyGoalsEyebrow = "Goals earned"
        public static func storyGoalsCaption(planned: Int) -> String {
            planned > 0 ? "of \(planned) planned" : "this week"
        }
        public static let storyGoalsEmptyHeadline = "Next week starts fresh."
        public static let storyGoalsEmptyCaption = "Pick one goal and earn your first unlock."
        public static func storyStreakLine(days: Int) -> String { "\(days)-day streak" }
        /// "Up 2 ranks": the same words Progress uses (`Copy.progress.rankMovementLabel`), so rank
        /// movement reads one way everywhere.
        public static func storyRankUpLine(ranks: Int) -> String {
            Copy.progress.rankMovementLabel(delta: ranks)
        }

        // Page 4: best day and the goal that pushed back hardest.
        public static let storyDaysEyebrow = "Highs and lows"
        public static let storyBestDayTitle = "Best day"
        public static let storyBestDayCaption = "Your strongest day of the week."
        public static let storyToughestTitle = "Toughest goal"
        public static func storyToughestCaption(goal: String, percent: Int) -> String {
            "\(goal) landed \(percent)% of the week. That's next week's win."
        }

        // Page 5: the rings.
        public static let storyRingsEyebrow = "Your rings"
        public static func storyRingsHeadline(closed: Int, total: Int) -> String {
            "\(closed) of \(total) closed"
        }
        public static func storyPercent(_ percent: Int) -> String { "\(percent)%" }

        // Page 6: the share card.
        public static let storyShareEyebrow = "Share your week"
        public static let storyShareHeadline = "Ready to post."

        /// The story's pause/play control (beside Close). Auto-advance is also off entirely for
        /// VoiceOver, Switch Control, Reduce Motion and accessibility text sizes.
        public static let storyPauseLabel = "Pause"
        public static let storyPlayLabel = "Play"
        /// VoiceOver hint on the story, which is one adjustable element.
        public static let storyPageAccessibilityHint = "Swipe up or down to change page"

        /// VoiceOver value for the story, e.g. "Page 2 of 6".
        public static func storyPageAccessibilityValue(page: Int, total: Int) -> String {
            "Page \(page) of \(total)"
        }
    }
}
