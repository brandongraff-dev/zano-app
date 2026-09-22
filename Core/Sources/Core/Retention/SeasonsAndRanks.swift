// Core/Sources/Core/Retention/SeasonsAndRanks.swift
//
// docs/spec.md §5.9 Seasons, Ranks, Monthly Challenges (quoted in full):
//   "- Ranks: Bronze → Silver → Gold → Platinum → Diamond based on 4-week consistency (not
//   volume, so a 3x/week person can hit Diamond).
//   - Seasons (quarterly) reset rank with a 'season badge' kept forever.
//   - Monthly challenges themed to fresh starts: 'January Lock-In,' 'Summer Shred Consistency,'
//   'No-Skip November.' Shareable challenge cards."
// docs/spec.md §8 Retention Psychology Rules, rule 9 ("No shame"): "Copy never says 'you
// failed.' Misses are 'slipped,' always followed by the next smallest step." — Bronze is a
// floor/default tier, never a punitive "below bronze" state; a quiet fresh start each season,
// never a callout. Rule 10 ("Loss aversion, ethically"): "Show what's at stake (streak, rank,
// Time Bank) before a lock, never as a threat after a miss." Rule 6 ("Fresh-start timing"):
// "Push challenges on Mondays, the 1st, after holidays..." — this file's monthly-challenge
// window boundaries (calendar-month-aligned) are exactly that fresh-start timing mechanism.
// docs/spec.md §5.17 Trophy Case & Cosmetics: "Badges for milestones..." — the season badge and
// monthly-challenge badge this file awards live in that same `badges` table (`Models/Badge.swift`),
// the same pattern `StreakEngine.swift`'s "Comeback" badge and `ComebackMode.swift`'s
// "comeback_challenge_*" badge already use.
// docs/spec.md §5.14 Weekly Report Card: "...streak, rank movement..." and
// `Models/Recap.swift`'s existing `rankMovement: Int?` field / `Copy.progress.
// rankMovementLabel(delta:)` / `RecapCard.rankLabel` (already wired in `ProgressView.swift`,
// `PreviewCatalog.swift`) are the pre-existing integration points a future Weekly Report Card
// session should read this file's `currentRank(asOf:)` through — not this task's file list to
// wire up (cross-module; see the TODO near `currentRank` below).
//
// Not part of any other file's SYSTEM CONTRACTS block (only `LockEngineManager`,
// `FocusSessionVerifier`, `GymVerifier`, `TimeBankEngine`, `StreakEngine`, `AdaptiveGoalEngine`,
// and the LiveActivity attribute structs have a fixed public shape other agents build against —
// see `StreakEngine.swift`'s/`AdaptiveGoalEngine.swift`'s own header comments) — this file's
// public API is this task's own design choice, kept deliberately small (CLAUDE.md: "don't add
// abstractions... beyond what the current session's scope requires").
//
// ARCHITECTURE DECISION (flagged prominently — read before extending this file): docs/spec.md
// §13 Data Model has no `seasons`/`ranks`/`monthly_challenges` table, and this task's scope is
// exactly one file (`Core/Sources/Core/Retention/SeasonsAndRanks.swift`) — it does not include
// adding a new SwiftData `@Model` (which would also require registering it in
// `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`'s `appGroupModelTypes` array, a
// different file this task does not own — an unregistered `@Model` type compiles fine but fails
// every fetch/insert at runtime, per that file's own doc comment) or a new backend migration
// (`backend/supabase/migrations`, also out of scope). So this file computes rank and challenge
// progress *live*, entirely derived from already-persisted `GoalEvent`/`Goal`/`User` rows, and
// persists only the two durable, forever-kept artifacts spec §5.9 actually asks for — the
// season badge and a monthly-challenge-complete badge — through the existing `Badge` model,
// exactly the way `StreakEngine`'s "Comeback" badge and `ComebackMode`'s challenge-complete
// badge already do. Nothing here is cached in `UserDefaults` either (unlike `StreakEngine`'s
// freeze-week anchor or `ComebackMode`'s challenge-start-date): every quantity below is either
// reconstructed from history on every call, or checked for idempotency via a deterministic
// `Badge.key` existence lookup — see `awardPastSeasonBadgeIfNeeded`/
// `awardMonthlyChallengeBadgeIfComplete` for why that's sufficient (no separate "have I already
// checked this season" marker needed). Flagged as this task's own architecture choice in
// `decisions`, not a rejection of `UserDefaults`-backed state on principle — it just isn't
// needed here.
//
// WHY THIS DOESN'T WRAP `StreakEngine.currentStreak()`: `Streak.current` (spec §5.6, §8 rule 3)
// requires an earned unlock on (almost) *every* calendar day to keep growing — it is, by
// construction, a daily-cadence, forgiveness-only-for-one-slip metric. Spec §5.9 is explicit
// that rank must NOT be volume-shaped this way ("not volume, so a 3x/week person can hit
// Diamond") — a genuine 3x/week-by-design user's raw day-streak would reset on most of their
// planned rest days under `StreakEngine`'s own semantics, which fails that exact example. So
// this file computes its own, separate "consistency" signal (see `expectedActiveDaysPerWeek`
// below) normalized to each user's own stated cadence instead of reusing `Streak.current`
// directly. This is the one real, load-bearing interpretation call in this file — flagged in
// `decisions`.

import Foundation
import SwiftData
import os

/// docs/spec.md §5.9's three mechanics — Ranks, Seasons, Monthly Challenges — computed live from
/// existing `Goal`/`GoalEvent`/`User` history, with only the two durable artifacts spec §5.9
/// actually calls out (the permanent season badge, a monthly-challenge-complete badge) persisted,
/// via the existing `Badge` model. See this file's header comment for the full architecture
/// rationale.
///
/// `@MainActor`, matching every other engine in this codebase (`StreakEngine`, `ComebackMode`,
/// `AdaptiveGoalEngine`, `LockEngineManager`, `FocusSessionVerifier`) for the same reason each of
/// those documents at their own declaration: a plain `final class` singleton needs either
/// `Sendable` conformance (unrealistic for a type owning a `ModelContext`) or global-actor
/// isolation under Swift 6 strict concurrency, and every realistic call site (SwiftUI views, App
/// Intents, a future Weekly Report Card integration) is already `@MainActor` or happy to `await`
/// a hop onto it. A `@MainActor final class` is implicitly `Sendable`.
@MainActor
public final class SeasonsAndRanks {
    public static let shared = SeasonsAndRanks()

    // MARK: - Ranks (spec §5.9 bullet 1)

    /// Bronze → Diamond, in ascending order. `String` raw values (not `Int`) so they read cleanly
    /// inside a `Badge.key` (e.g. `"season_2026Q3_gold"`) without a lookup table — matching
    /// `Badge.key`'s own doc comment: "a stable, non-user-facing identifier; the display copy for
    /// each key lives in `Core/Sources/Core/Copy`." This type is that same kind of stable
    /// identifier, not display text — a future UI layer maps `Rank` to an icon/label/color itself.
    public enum Rank: String, Codable, CaseIterable, Sendable, Comparable {
        case bronze, silver, gold, platinum, diamond

        /// Declaration order above *is* rank order (bronze lowest, diamond highest) — this just
        /// makes that ordering usable with `<`/`>`/`sorted()` instead of every call site having to
        /// know that fact independently.
        private var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

        public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.sortOrder < rhs.sortOrder }
    }

    /// The full result of a rank computation for one point in time — everything a UI layer needs
    /// to render a rank pill/progress view without recomputing anything itself.
    public struct RankStatus: Sendable, Equatable {
        public let rank: Rank
        /// The 4-week consistency score (`0...1`) `rank` was derived from — see
        /// `weeklyConsistency` for the per-week breakdown that produced it.
        public let consistency: Double
        /// Up to 4 entries, oldest → newest, each this user's own-cadence-normalized "did I show
        /// up" fraction for that trailing 7-day bucket (see `expectedActiveDaysPerWeek`). Fewer
        /// than 4 entries only early in a season, once the season-start clamp (see
        /// `weeklyConsistencyBuckets`) leaves less than a full 28 days of in-season history to
        /// bucket.
        public let weeklyConsistency: [Double]
        public let season: Season
        /// `true` during the first `minimumSeasonDaysForRankedStatus` days of a season, when there
        /// isn't yet enough in-season data to rank meaningfully — `rank` is forced to `.bronze`
        /// during this window regardless of `consistency` (see `computeRankStatus`), so a single
        /// lucky day 1 can't vault someone to Diamond. A UI layer can use this flag to show
        /// "ranked in N days" copy instead of a bare Bronze pill, without this file needing to own
        /// that copy itself.
        public let isPlacement: Bool
    }

    /// "not volume, so a 3x/week person can hit Diamond" (spec §5.9) — the per-user normalizer
    /// that makes that literally true. `Goal.cadence` is free text (`Models/Goal.swift`'s own doc
    /// comment: "not a fixed enum in the migration"), so this is a best-effort parse, not a
    /// guaranteed-exact read of every possible phrasing. Takes the *maximum* parsed weekly count
    /// across the user's active goals — rank tracks keeping up with the user's most demanding
    /// stated commitment, not their easiest one. Falls back to spec §5.9's own worked example
    /// (`3`) when no active goal has a parseable cadence, rather than defaulting to `7`: a `7`
    /// default would make Diamond unreachable for exactly the population spec calls out by name
    /// whenever cadence text is missing/unparseable, which would contradict the spec line this
    /// constant exists to satisfy. Flagged as this task's own interpretation in `decisions` — spec
    /// does not pin an exact parsing rule or fallback number.
    static let fallbackWeeklyCadence = 3

    /// See `fallbackWeeklyCadence`'s doc comment. `internal`, not `private`, only so `CoreTests`
    /// can exercise the parser directly.
    static func parsedWeeklyCadence(from cadence: String?) -> Int? {
        guard let cadence else { return nil }
        let text = cadence.lowercased()

        if text.contains("daily") || text.contains("everyday") || text.contains("every day") { return 7 }
        if text.contains("weekday") { return 5 }
        if text.contains("weekend") { return 2 }
        guard text.contains("week") else { return nil }

        var digits = ""
        for character in text {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        if let parsed = Int(digits), parsed > 0 { return min(7, parsed) }
        if text.contains("weekly") { return 1 }
        return nil
    }

    static func expectedActiveDaysPerWeek(for goals: [Goal]) -> Int {
        let parsed = goals.filter(\.active).compactMap { parsedWeeklyCadence(from: $0.cadence) }
        return parsed.max() ?? fallbackWeeklyCadence
    }

    /// How many trailing calendar days' history this task reads as "4-week consistency" (spec
    /// §5.9's own phrase). Not calendar-week-aligned (no Mon-Sun grouping) — a rolling 28 days
    /// ending on the day being ranked, split into 4 consecutive 7-day buckets — so a user who
    /// joined mid-week never gets a short first bucket purely from calendar alignment; the only
    /// thing that shortens a bucket is the season-start clamp (`weeklyConsistencyBuckets`).
    private static let windowDays = 28
    private static let bucketDays = 7

    /// Below this many elapsed days *in the current season*, `RankStatus.rank` is forced to
    /// `.bronze` regardless of `consistency` (`RankStatus.isPlacement` reports this). Spec §5.9
    /// doesn't specify a placement period; this task adds one so a single strong opening day can't
    /// compute a misleadingly high rank from almost no data — flagged in `decisions` as this
    /// task's own choice, not exact spec text.
    private static let minimumSeasonDaysForRankedStatus = 7

    // Rank thresholds against the `0...1` consistency score. Spec §5.9 doesn't pin exact cutoffs;
    // these are this task's own calibration, flagged in `decisions`: hitting *your own* stated
    // cadence roughly 9-in-10 in-season weeks running is a real stretch (Diamond), roughly
    // 3-in-10 is "you're doing something, just not consistently" (the Bronze/Silver line).
    // Deliberately never a "worse than Bronze" tier below this — spec §8 rule 9 ("No shame").
    private static let diamondThreshold: Double = 0.90
    private static let platinumThreshold: Double = 0.75
    private static let goldThreshold: Double = 0.55
    private static let silverThreshold: Double = 0.30

    private static func rank(forConsistency consistency: Double) -> Rank {
        switch consistency {
        case diamondThreshold...: return .diamond
        case platinumThreshold...: return .platinum
        case goldThreshold...: return .gold
        case silverThreshold...: return .silver
        default: return .bronze
        }
    }

    /// The signed-in user's current rank, as of `date` (defaults to now), within `date`'s season
    /// (`currentSeason(asOf:)`) — see `RankStatus`/this file's header comment for exactly what
    /// "consistency" means and why it isn't `Streak.current`. Never throws: no local `User` row
    /// (or any other read failure) degrades to a placement-period Bronze `RankStatus` rather than
    /// propagating an error, matching every other read-only method in this codebase's engines.
    ///
    /// TODO(cross-module, Weekly Report Card session, spec §5.14; not this task's file list):
    /// `Recap.rankMovement` / `Copy.progress.rankMovementLabel(delta:)` / `RecapCard.rankLabel`
    /// already exist and are wired into `ProgressView.swift`, but nothing yet calls this method to
    /// populate them — that integration (comparing this week's `currentRank(asOf:)` against last
    /// week's) belongs to whichever session builds the Recap-generation job, not this file.
    public func currentRank(asOf date: Date = .now) async -> RankStatus {
        let season = currentSeason(asOf: date)
        guard let user = try? fetchCurrentUser() else {
            return RankStatus(rank: .bronze, consistency: 0, weeklyConsistency: [], season: season, isPlacement: true)
        }
        let goals = fetchActiveGoals(userID: user.id)
        return computeRankStatus(userID: user.id, goals: goals, asOf: date, season: season)
    }

    private func computeRankStatus(userID: UUID, goals: [Goal], asOf date: Date, season: Season) -> RankStatus {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let seasonStart = calendar.startOfDay(for: season.startDate)
        let daysIntoSeason = (calendar.dateComponents([.day], from: seasonStart, to: day).day ?? 0) + 1

        let buckets = weeklyConsistencyBuckets(userID: userID, goals: goals, asOf: day, seasonStart: seasonStart)
        let consistency = buckets.isEmpty ? 0 : buckets.reduce(0, +) / Double(buckets.count)
        let isPlacement = daysIntoSeason < Self.minimumSeasonDaysForRankedStatus
        let rank: Rank = isPlacement ? .bronze : Self.rank(forConsistency: consistency)

        return RankStatus(
            rank: rank,
            consistency: consistency,
            weeklyConsistency: buckets,
            season: season,
            isPlacement: isPlacement
        )
    }

    /// Up to 4 consistency fractions (oldest → newest), one per trailing 7-day bucket ending on
    /// `day`, each bucket clamped so it never reaches before `seasonStart` — this clamp is the
    /// entire mechanism by which "seasons reset rank" (spec §5.9): the first bucket of a brand-new
    /// season simply has nowhere earlier to look, so consistency starts from a clean slate every
    /// quarter without this file needing to persist or clear any separate "current rank" state.
    /// Stops early (fewer than 4 buckets) once a candidate bucket's clamped start would equal or
    /// pass `seasonStart` on a prior iteration.
    private func weeklyConsistencyBuckets(userID: UUID, goals: [Goal], asOf day: Date, seasonStart: Date) -> [Double] {
        let calendar = Calendar.current
        let expected = max(1, Self.expectedActiveDaysPerWeek(for: goals))

        var buckets: [Double] = []
        var bucketEnd = day
        for _ in 0..<(Self.windowDays / Self.bucketDays) {
            guard bucketEnd >= seasonStart else { break }
            let unclamped = calendar.date(byAdding: .day, value: -(Self.bucketDays - 1), to: bucketEnd) ?? bucketEnd
            let bucketStart = max(unclamped, seasonStart)

            let activeDays = countActiveDays(userID: userID, from: bucketStart, throughInclusive: bucketEnd)
            buckets.append(min(1.0, Double(activeDays) / Double(expected)))

            guard let previousEnd = calendar.date(byAdding: .day, value: -Self.bucketDays, to: bucketEnd) else { break }
            bucketEnd = previousEnd
        }
        return buckets.reversed()
    }

    /// Distinct calendar days in `[from, throughInclusive]` with at least one qualifying
    /// `GoalEvent` — "qualifying" mirrors `AdaptiveGoalEngine.adjustDifficulty`'s own "completed"
    /// definition (`verified == true` and `kind` of `.complete` or `.planB`) plus `.freeze`: a
    /// streak-freeze day is still a day the user's consistency was protected/covered, not a gap
    /// (spec §8 rule 3, "a streak should feel protective, not fragile" — this file reads that
    /// same forgiveness principle into rank consistency, not just the daily streak). `.freeze`
    /// events don't carry `verified == true` as a *meaningful* filter the way `.complete`/`.planB`
    /// do (`StreakEngine.insertFreezeEvent` always writes `verified: true`), so this doesn't
    /// re-check it for that case — only that the kind is `.freeze` at all.
    private func countActiveDays(userID: UUID, from start: Date, throughInclusive end: Date) -> Int {
        let calendar = Calendar.current
        let startOfRange = calendar.startOfDay(for: start)
        guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) else {
            return 0
        }

        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= startOfRange && $0.ts < exclusiveEnd }
        )
        guard let events = try? context.fetch(descriptor) else { return 0 }

        let qualifying = events.filter { event in
            guard event.user?.id == userID else { return false }
            switch event.kind {
            case .complete, .planB: return event.verified
            case .freeze: return true
            case .log, .verify, .miss: return false
            }
        }
        let days = Set(qualifying.map { calendar.startOfDay(for: $0.ts) })
        return days.count
    }

    // MARK: - Seasons (spec §5.9 bullet 2)

    /// One calendar quarter (Jan–Mar, Apr–Jun, Jul–Sep, Oct–Dec). Spec §5.9 says "quarterly"
    /// without pinning an alignment (calendar quarters vs. e.g. anniversary-of-signup quarters) —
    /// calendar quarters is this task's read, since it's the unambiguous default and matches
    /// spec §8 rule 6's "fresh-start timing" framing (the 1st of a quarter is exactly that kind of
    /// fresh-start moment, alongside "the 1st" of any month already called out there).
    public struct Season: Sendable, Equatable, Hashable {
        public let year: Int
        /// `1...4`.
        public let quarter: Int
        /// Local midnight on the season's first day, inclusive.
        public let startDate: Date
        /// Local midnight on the day after the season's last day — exclusive upper bound.
        public let endDate: Date

        /// Stable, non-user-facing identifier for this season (e.g. `"2026Q3"`) — used as part of
        /// the permanent season badge's `Badge.key`, the same "stable identifier, display text
        /// lives in Copy" convention `Badge.key` itself documents.
        public var id: String { "\(year)Q\(quarter)" }
    }

    public func currentSeason(asOf date: Date = .now) -> Season {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let quarter = (month - 1) / 3 + 1
        let startMonth = (quarter - 1) * 3 + 1

        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start
        return Season(year: year, quarter: quarter, startDate: start, endDate: end)
    }

    private func previousSeason(before season: Season) -> Season {
        let calendar = Calendar.current
        let shiftedStart = calendar.date(byAdding: .month, value: -3, to: season.startDate) ?? season.startDate
        return currentSeason(asOf: shiftedStart)
    }

    /// Banks the permanent "season badge" (spec §5.9: "Seasons (quarterly) reset rank with a
    /// 'season badge' kept forever") for whichever season most recently *fully* ended before
    /// `date`, if it hasn't been banked yet and the signed-in user actually existed for at least
    /// part of it. Idempotent and self-contained: rather than persisting "which season did I last
    /// check" anywhere (see this file's header architecture note), this simply recomputes the
    /// previous season's rank and checks whether a `Badge` with that exact deterministic key
    /// (`"season_<season.id>_<rank.rawValue>"`) already exists — safe to call as often as a caller
    /// likes (app foreground, a daily refresh job, ...).
    ///
    /// - Returns: `true` only when a *new* badge was just inserted this call (useful for a caller
    ///   that wants to show a "Season complete — you finished Gold" celebration); `false` whenever
    ///   there's nothing new to bank (already banked, no signed-in user, or the previous season
    ///   predates the user's own account).
    ///
    /// TODO(cross-module; not this task's file list): nothing in the codebase calls this yet — a
    /// daily background refresh or app-foreground hook should, the same way `ComebackMode.swift`'s
    /// header flags its own `recordDayCompleted` as needing a real call site.
    @discardableResult
    public func awardPastSeasonBadgeIfNeeded(asOf date: Date = .now) async -> Bool {
        guard let user = try? fetchCurrentUser() else { return false }

        let season = currentSeason(asOf: date)
        let previous = previousSeason(before: season)
        guard user.createdAt < previous.endDate else { return false }

        let calendar = Calendar.current
        let lastDayOfPreviousSeason = calendar.date(byAdding: .day, value: -1, to: previous.endDate) ?? previous.startDate
        // Uses the user's *currently* active goals to derive `expectedActiveDaysPerWeek`, not
        // whatever goals were active back when `previous` was the live season — `Goal` has no
        // "was active as of date X" history to reconstruct that from (a goal that's since been
        // deleted/deactivated leaves no trace here). A goal added/removed since `previous` ended
        // can therefore skew the banked rank slightly. Flagged in `knownIssues` — acceptable for
        // v1 since this only affects the one-time badge text, not the always-live `currentRank`.
        let goals = fetchActiveGoals(userID: user.id)
        let status = computeRankStatus(userID: user.id, goals: goals, asOf: lastDayOfPreviousSeason, season: previous)

        let key = "season_\(previous.id)_\(status.rank.rawValue)"
        return awardBadgeIfNeeded(key: key, userID: user.id, earnedAt: previous.endDate)
    }

    // MARK: - Monthly themed challenges (spec §5.9 bullet 3)

    /// One calendar month's themed challenge. `themeKey` is a stable, non-user-facing identifier
    /// (same `Badge.key` convention) — the actual display title/art belongs to
    /// `Core/Sources/Core/Copy`, out of scope for this file.
    public struct MonthlyChallenge: Sendable, Equatable {
        /// `"yyyy-MM"`, e.g. `"2026-01"`.
        public let key: String
        public let themeKey: String
        public let year: Int
        /// `1...12`.
        public let month: Int
        /// Local midnight on the 1st of the month.
        public let startDate: Date
        /// Local midnight on the 1st of the next month — exclusive upper bound.
        public let endDate: Date
    }

    public func currentMonthlyChallenge(asOf date: Date = .now) -> MonthlyChallenge {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start

        return MonthlyChallenge(
            key: String(format: "%04d-%02d", year, month),
            themeKey: Self.themeKey(forMonth: month),
            year: year,
            month: month,
            startDate: start,
            endDate: end
        )
    }

    /// Spec §5.9 names exactly 3 example challenges out of 12 months: "January Lock-In," "Summer
    /// Shred Consistency," "No-Skip November." January and November map directly. "Summer" isn't
    /// pinned to one month — this task places it at July (Northern-hemisphere midsummer, matching
    /// spec §1's target audience with no stated hemisphere qualifier), flagged as a placement
    /// choice, not spec text, in `decisions`. The remaining 9 months have no spec-given theme at
    /// all; this returns a deterministic placeholder key (`"monthly_lock_in_<month>"`) for them
    /// purely so this function is total — the real creative names/art for those 9 are a future
    /// marketing/Copy-layer decision, explicitly flagged as a gap in `knownIssues`, not something
    /// this task invents on spec's behalf.
    private static func themeKey(forMonth month: Int) -> String {
        switch month {
        case 1: return "january_lock_in"
        case 7: return "summer_shred_consistency"
        case 11: return "no_skip_november"
        default: return "monthly_lock_in_\(month)"
        }
    }

    /// How much of `expectedActiveDaysPerWeek`'s daily-equivalent rate counts as "completed" this
    /// month. Spec §5.9 doesn't define pass/fail for a monthly challenge beyond it being
    /// "shareable" — this task reads "themed to fresh starts" as still needing *some* bar to clear
    /// (otherwise "shareable challenge card" has nothing to celebrate), and picks 80% of the
    /// user's own cadence, prorated to however much of the month has elapsed, as a deliberately
    /// slightly-forgiving bar (below the Gold rank threshold) so a monthly challenge stays easier
    /// to clear than a full season's rank climb. Flagged as this task's own number in `decisions`.
    private static let monthlyCompletionFraction = 0.8

    public struct MonthlyChallengeProgress: Sendable, Equatable {
        public let challenge: MonthlyChallenge
        /// Distinct qualifying-active calendar days so far this month (see `countActiveDays`).
        public let activeDays: Int
        /// The prorated-to-date target `activeDays` is measured against.
        public let expectedDays: Int
        /// `activeDays / expectedDays`, capped at `1.0`.
        public let progress: Double
        public let isComplete: Bool
    }

    /// `date`'s in-progress monthly challenge status. Never throws: no signed-in user degrades to
    /// a zeroed, incomplete `MonthlyChallengeProgress` rather than propagating an error.
    public func monthlyChallengeProgress(asOf date: Date = .now) async -> MonthlyChallengeProgress {
        let challenge = currentMonthlyChallenge(asOf: date)
        guard let user = try? fetchCurrentUser() else {
            return MonthlyChallengeProgress(challenge: challenge, activeDays: 0, expectedDays: 0, progress: 0, isComplete: false)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: challenge.endDate) ?? today
        let elapsedThrough = min(today, lastDayOfMonth)
        let daysElapsed = max(1, (calendar.dateComponents([.day], from: challenge.startDate, to: elapsedThrough).day ?? 0) + 1)

        let goals = fetchActiveGoals(userID: user.id)
        let dailyExpectedRate = Double(Self.expectedActiveDaysPerWeek(for: goals)) / 7.0
        let expectedDays = max(1, Int((Double(daysElapsed) * dailyExpectedRate * Self.monthlyCompletionFraction).rounded(.up)))
        let activeDays = countActiveDays(userID: user.id, from: challenge.startDate, throughInclusive: elapsedThrough)
        let progress = min(1.0, Double(activeDays) / Double(expectedDays))

        return MonthlyChallengeProgress(
            challenge: challenge,
            activeDays: activeDays,
            expectedDays: expectedDays,
            progress: progress,
            isComplete: progress >= 1.0
        )
    }

    /// Awards this month's completion badge (`"monthly_challenge_<yyyy-MM>"`) if
    /// `monthlyChallengeProgress(asOf:)` reports `isComplete`, idempotently (a `Badge.key`
    /// existence check, same pattern as `awardPastSeasonBadgeIfNeeded`). Spec §5.9's "Shareable
    /// challenge cards" is a UI/`ShareCard` concern (`Core/Sources/Core/UI/Components/
    /// ShareCard.swift`) this file deliberately does not touch — this only produces the durable
    /// signal (the badge) a future share-card flow can key off of.
    ///
    /// - Returns: `true` only when a *new* badge was just inserted this call.
    ///
    /// TODO(cross-module; not this task's file list): nothing calls this yet — same integration
    /// gap as `awardPastSeasonBadgeIfNeeded` above (a daily refresh/app-foreground hook should call
    /// both together).
    @discardableResult
    public func awardMonthlyChallengeBadgeIfComplete(asOf date: Date = .now) async -> Bool {
        let progress = await monthlyChallengeProgress(asOf: date)
        guard progress.isComplete, let user = try? fetchCurrentUser() else { return false }

        let key = "monthly_challenge_\(progress.challenge.key)"
        return awardBadgeIfNeeded(key: key, userID: user.id, earnedAt: date)
    }

    // MARK: - Badge awarding (spec §5.17 Trophy Case; same pattern as StreakEngine/ComebackMode)

    /// Inserts a `Badge(userID, key, earnedAt)` if none with that exact `(userID, key)` pair
    /// exists yet, matching `Badge.swift`'s own doc comment ("whichever engine awards badges...
    /// must check for an existing `(userID, key)` row before inserting"). Saves immediately
    /// (unlike `StreakEngine.awardBadgeIfNeeded`, which relies on its caller's later save) since
    /// every call site in this file is a standalone entry point with no surrounding save of its
    /// own — matching `ComebackMode.awardChallengeCompleteBadge`'s self-contained convention.
    ///
    /// - Returns: `true` if a new badge was just inserted and saved; `false` if one already
    ///   existed, or the save failed (logged either way).
    @discardableResult
    private func awardBadgeIfNeeded(key: String, userID: UUID, earnedAt: Date) -> Bool {
        var descriptor = FetchDescriptor<Badge>(
            predicate: #Predicate<Badge> { $0.userID == userID && $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return false }

        context.insert(Badge(userID: userID, key: key, earnedAt: earnedAt))
        do {
            try context.save()
            return true
        } catch {
            logger.error(
                "awardBadgeIfNeeded: failed to persist badge \(key, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    // MARK: - SwiftData

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "SeasonsAndRanks")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container (mirrors `StreakEngine`/`ComebackMode`/`AdaptiveGoalEngine`'s own
    /// convention); every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    private func fetchActiveGoals(userID: UUID) -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active == true })
        guard let goals = try? context.fetch(descriptor) else { return [] }
        return goals.filter { $0.user?.id == userID }
    }

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `StreakEngine.fetchCurrentUser()`/`ComebackMode.fetchCurrentUser()` use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw SeasonsAndRanksError.noSignedInUser
        }
        return user
    }
}

/// Thrown only by this file's private `fetchCurrentUser()`. Every public method above swallows it
/// via `try?` and degrades to a sensible default (never throws outward) — matching every other
/// read-only method in this codebase's engines.
enum SeasonsAndRanksError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
