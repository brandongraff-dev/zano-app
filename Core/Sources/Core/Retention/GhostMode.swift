// Core/Sources/Core/Retention/GhostMode.swift
//
// docs/spec.md §5.4 ★ Ghost Mode:
//   "Race your past self. The app shows a 'ghost' of your best week: 'Ghost You had already
//   trained twice by Tuesday.' Zero social pressure, pure self-competition. Very effective for
//   people who don't want friends in the app."
// docs/spec.md §8 Retention Psychology Rules, rule 9 ("No shame"): "Copy never says 'you failed.'
// Misses are 'slipped,' always followed by the next smallest step." Applied here too: falling
// behind your own ghost is framed as a fact to react to, never a failure — see `headline(...)`
// below, and there is deliberately no "you lost" state, only degrees of ahead/tied/behind.
// docs/spec.md §13 Data Model: `goal_events (..., kind: ... | complete | ...)` — this file reads
// that same table `StreakEngine`/`ComebackMode`/`AdaptiveGoalEngine` (this same directory) already
// read from, purely as a read-only historical query. It writes nothing.
//
// Not part of this task's SYSTEM CONTRACTS list (only `LockEngineManager`, `FocusSessionVerifier`,
// `GymVerifier`, `TimeBankEngine`, `StreakEngine`, `AdaptiveGoalEngine`, and the LiveActivity
// attribute structs have a fixed public shape other agents build against) — this file's public API
// is this task's own design choice, per this task's brief: "expose something like
// `func ghostComparison(for date: Date) async -> GhostComparison`."
//
// Copy discipline (CLAUDE.md: "User-facing copy lives in Core/Sources/Core/Copy... no hardcoded
// user-facing strings in views"): `GhostComparison.headline` below IS a composed, user-facing
// sentence, and this file is `Retention/`, not `Copy/`. That's a deliberate, scope-constrained
// choice, not an oversight — this task owns exactly two files (this one and
// `UI/Components/GhostProgressBanner.swift`), not a new `Copy/GhostCopy.swift`, and CLAUDE.md's own
// "don't add abstractions... beyond what the current session's scope requires" cuts against
// creating one just to hold a single sentence. Every raw field the sentence is built from
// (`ghostCompletedCount`, `currentCompletedCount`, `dayLabel`, `dayOfWeekOffset`, ...) is also
// exposed on `GhostComparison`, so a future session can move `headline`'s composition into a real
// Copy file (with `CoachVoice`-varied phrasing, spec §5.13, matching `ShieldCopy`'s pattern) without
// this file's callers losing any information — flagged again in this task's `knownIssues`.

import Foundation
import SwiftData
import os

/// Computes a "race your past self" comparison for Ghost Mode (docs/spec.md §5.4): finds the
/// user's best historical week (by total completed-goal count) and reports what that "ghost" had
/// accomplished by the same point in the week that `date` is at right now.
///
/// `@MainActor`, matching every other engine in this codebase (`StreakEngine`, `ComebackMode`,
/// `AdaptiveGoalEngine`, `LockEngineManager`) for the same reason each documents at its own
/// declaration: a plain `final class` singleton needs either `Sendable` conformance (unrealistic
/// for a type owning a `ModelContext`) or global-actor isolation under Swift 6 strict concurrency,
/// and every realistic call site (a SwiftUI view's `.task`, an App Intent) is already `@MainActor`
/// or happy to `await` a hop onto it.
@MainActor
public final class GhostMode {
    public static let shared = GhostMode()

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GhostMode")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container (mirrors `StreakEngine`/`ComebackMode`'s own convention); every real
    /// call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public shape

    /// One "today vs. Ghost You" comparison, at the day-of-week point `date` falls on.
    public struct GhostComparison: Sendable, Equatable {
        /// Start-of-day for the date this comparison was computed for.
        public let date: Date
        /// Start of `date`'s own calendar week (`Calendar.current.dateInterval(of: .weekOfYear:)`).
        public let weekStart: Date
        /// 1-indexed position of `date` within its own week — `1` on the week's first day, up to
        /// `7`. Both this week's and the ghost week's completed-goal counts below are summed over
        /// exactly this many days from each week's own start, so "by \(dayLabel)" means the same
        /// relative point in both weeks regardless of which absolute dates they fall on.
        public let dayOfWeekOffset: Int
        /// Full weekday name for `date` (e.g. `"Tuesday"`) — the "...by Tuesday" in spec §5.4's
        /// example line.
        public let dayLabel: String
        /// `false` until there is at least one fully-elapsed historical week (a week that ended
        /// before `weekStart`) containing at least one completed goal. A brand-new user, or one
        /// still in their first-ever week, has no ghost yet — this is the only "empty" state;
        /// there is no error state (see `ghostComparison(for:)`'s doc comment).
        public let hasGhostWeek: Bool
        /// Start of the best historical week found (highest total completed-goal count across the
        /// whole week; ties favor the more recent week). `nil` when `hasGhostWeek` is `false`.
        public let ghostWeekStart: Date?
        /// Completed-goal count in the ghost week, summed over its first `dayOfWeekOffset` days.
        /// `0` when `hasGhostWeek` is `false`.
        public let ghostCompletedCount: Int
        /// Completed-goal count so far *this* week, summed over the same first `dayOfWeekOffset`
        /// days (i.e. through and including `date`).
        public let currentCompletedCount: Int
        /// A single ready-to-render sentence in spec §5.4's voice, e.g. "Ghost You had already
        /// completed 2 goals by Tuesday." See this file's header comment for why this composition
        /// lives here rather than `Core/Sources/Core/Copy`, and why every field above is exposed
        /// directly too (so a future caller/Copy file can build its own phrasing instead).
        public let headline: String

        /// `currentCompletedCount - ghostCompletedCount`. Positive means ahead of Ghost You.
        public var delta: Int { currentCompletedCount - ghostCompletedCount }
        public var isAheadOfGhost: Bool { hasGhostWeek && delta > 0 }
        public var isTiedWithGhost: Bool { hasGhostWeek && delta == 0 }
        public var isBehindGhost: Bool { hasGhostWeek && delta < 0 }
    }

    /// Computes today's Ghost Mode comparison (spec §5.4).
    ///
    /// "Best historical week" only ever considers weeks that ended before `date`'s own current
    /// week started — an in-progress week can't be its own ghost (that would just be comparing the
    /// user to themselves right now, not to a past self), and a week is only a fair "best" once
    /// it's fully elapsed. Ties (two historical weeks with an equal, highest completed-goal count)
    /// resolve to the more recent one — an arbitrary but deterministic and stable tie-break
    /// (flagged in this task's `decisions`; spec §5.4 doesn't say either way).
    ///
    /// Only `GoalEventKind.complete` events count toward "completed-goal count," not `.planB` or
    /// `.freeze` — spec §5.5 frames Plan B as "half credit," and folding that weighting into a
    /// ghost comparison felt like scope creep for a first pass here (this task's own choice,
    /// flagged in `decisions`; a future session could weight `.planB` at 0.5 if that reads better
    /// in practice).
    ///
    /// Never throws and never produces an error state: a missing local `User` row, an unresolvable
    /// calendar week, or simply no qualifying historical week are all just "no ghost yet"
    /// (`hasGhostWeek == false`) — spec §5.4's "zero social pressure" extends to zero failure
    /// state here too; this is a motivational surface, never a blocking one.
    public func ghostComparison(for date: Date = .now) async -> GhostComparison {
        let today = calendar.startOfDay(for: date)
        let label = Self.dayLabel(for: today)

        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today) else {
            logger.error("ghostComparison: could not resolve the current calendar week.")
            return Self.emptyComparison(date: today, weekStart: today, offset: 1, dayLabel: label)
        }
        let offset = dayOffset(of: today, in: currentWeek)

        guard let user = try? fetchCurrentUser() else {
            return Self.emptyComparison(date: today, weekStart: currentWeek.start, offset: offset, dayLabel: label)
        }

        guard let currentCutoff = calendar.date(byAdding: .day, value: offset, to: currentWeek.start) else {
            return Self.emptyComparison(date: today, weekStart: currentWeek.start, offset: offset, dayLabel: label)
        }
        let currentCount = completedGoalCount(userID: user.id, from: currentWeek.start, to: currentCutoff)

        guard let ghostWeekStart = bestHistoricalWeekStart(userID: user.id, before: currentWeek.start),
              let ghostCutoff = calendar.date(byAdding: .day, value: offset, to: ghostWeekStart)
        else {
            return Self.emptyComparison(
                date: today, weekStart: currentWeek.start, offset: offset, dayLabel: label,
                currentCompletedCount: currentCount
            )
        }
        let ghostCount = completedGoalCount(userID: user.id, from: ghostWeekStart, to: ghostCutoff)

        return GhostComparison(
            date: today,
            weekStart: currentWeek.start,
            dayOfWeekOffset: offset,
            dayLabel: label,
            hasGhostWeek: true,
            ghostWeekStart: ghostWeekStart,
            ghostCompletedCount: ghostCount,
            currentCompletedCount: currentCount,
            headline: Self.headline(dayLabel: label, ghostCount: ghostCount, currentCount: currentCount, hasGhostWeek: true)
        )
    }

    // MARK: - Week / day math

    /// 1-indexed offset of `day` within `week` (`1`...`7`). Clamped defensively — `day` is always
    /// `today`'s start-of-day and `week` is always `today`'s own `dateInterval(of: .weekOfYear:)`
    /// at every call site, so this should never actually need the clamp, but a stray off-by-one
    /// from a DST boundary should degrade to "somewhere in the week," never an out-of-range index
    /// a caller might use to subscript something.
    private func dayOffset(of day: Date, in week: DateInterval) -> Int {
        let value = calendar.dateComponents([.day], from: week.start, to: day).day ?? 0
        return min(7, max(1, value + 1))
    }

    /// The start of the best-performing fully-elapsed week strictly before `currentWeekStart`, by
    /// total `.complete` `GoalEvent` count for `userID` — or `nil` if there's no such week yet.
    ///
    /// Fetches with a `Date`-only `#Predicate` (`ts < currentWeekStart`) and filters `kind`/`user`
    /// in plain Swift afterward — the same conservative choice `StreakEngine.hasStreakMissEvent`/
    /// `ComebackMode.fetchDailyPlan` document at their own declarations: this task has no Mac/Swift
    /// toolchain to compile-verify `#Predicate`'s handling of a custom `Codable` enum (`kind`) or
    /// optional-relationship chaining (`user?.id`) on this SDK version.
    ///
    /// Performance note (flagged in `knownIssues`): this fetches every `GoalEvent` dated before the
    /// current week with no lower bound, so it scans a long-time user's *entire* history every call
    /// site. Fine for a local on-device SwiftData store at the data volumes one user's own goal log
    /// produces, but if this ever shows up as a real hitch on-device, the fix is either a bounded
    /// lookback window (e.g. the last 52 weeks) or a small persisted "best week so far" cache
    /// invalidated on new completions — neither is done here since there's no way to measure actual
    /// on-device timing without a Mac/device.
    private func bestHistoricalWeekStart(userID: UUID, before currentWeekStart: Date) -> Date? {
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts < currentWeekStart }
        )
        guard let events = try? context.fetch(descriptor), !events.isEmpty else { return nil }

        var countsByWeekStart: [Date: Int] = [:]
        for event in events {
            guard event.kind == .complete,
                  event.user?.id == userID,
                  let weekStart = calendar.dateInterval(of: .weekOfYear, for: event.ts)?.start
            else { continue }
            countsByWeekStart[weekStart, default: 0] += 1
        }
        guard !countsByWeekStart.isEmpty else { return nil }

        // Sort ascending by (count, weekStart) so `.last` is the highest count, most-recent-on-tie
        // week — a deterministic tie-break (see `ghostComparison(for:)`'s doc comment).
        return countsByWeekStart
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
            }
            .last?.key
    }

    /// Count of `.complete` `GoalEvent`s for `userID` with `ts` in `[start, end)`. Same `Date`-only
    /// `#Predicate` + plain-Swift-filter convention as `bestHistoricalWeekStart` above, mirroring
    /// `StreakEngine.eventExists`'s own `ts >= day && ts < nextDay` shape.
    private func completedGoalCount(userID: UUID, from start: Date, to end: Date) -> Int {
        guard end > start else { return 0 }
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= start && $0.ts < end }
        )
        guard let events = try? context.fetch(descriptor) else { return 0 }
        return events.filter { $0.kind == .complete && $0.user?.id == userID }.count
    }

    // MARK: - Headline composition (see file header for why this lives here, not Copy/)

    private static let noGhostHeadline =
        "Keep logging — Ghost Mode kicks in once you've completed a full week to race."

    private static func headline(dayLabel: String, ghostCount: Int, currentCount: Int, hasGhostWeek: Bool) -> String {
        guard hasGhostWeek else { return noGhostHeadline }

        if currentCount > ghostCount {
            return "You're ahead of Ghost You — \(goalCountPhrase(currentCount)) by \(dayLabel), "
                + "Ghost You had \(goalCountPhrase(ghostCount))."
        }
        if currentCount == ghostCount {
            guard ghostCount > 0 else {
                return "Ghost You hadn't gotten started by \(dayLabel) either — you're even so far."
            }
            return "Neck and neck with Ghost You — \(goalCountPhrase(currentCount)) each by \(dayLabel)."
        }
        return "Ghost You had already completed \(goalCountPhrase(ghostCount)) by \(dayLabel)."
    }

    private static func goalCountPhrase(_ count: Int) -> String {
        "\(count) \(count == 1 ? "goal" : "goals")"
    }

    private static func emptyComparison(
        date: Date, weekStart: Date, offset: Int, dayLabel: String, currentCompletedCount: Int = 0
    ) -> GhostComparison {
        GhostComparison(
            date: date,
            weekStart: weekStart,
            dayOfWeekOffset: offset,
            dayLabel: dayLabel,
            hasGhostWeek: false,
            ghostWeekStart: nil,
            ghostCompletedCount: 0,
            currentCompletedCount: currentCompletedCount,
            headline: noGhostHeadline
        )
    }

    // MARK: - Day label

    /// Fixed `en_US_POSIX`/Gregorian, independent of the device's actual locale/calendar — every
    /// other piece of English copy in this codebase (`ShieldCopy`, `CoachVoiceTone`) is likewise
    /// unlocalized today, so a weekday name should render the same stable English word ("Tuesday")
    /// regardless of device region settings rather than silently localizing ahead of the rest of
    /// the app's copy.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        formatter.timeZone = .current
        return formatter
    }()

    private static func dayLabel(for date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    // MARK: - SwiftData

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `StreakEngine`/`ComebackMode`/`LockEngineManager` each use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw GhostModeError.noSignedInUser
        }
        return user
    }
}

/// Thrown only by this file's private `fetchCurrentUser()`. `ghostComparison(for:)` swallows it via
/// `try?` (never throws outward — see that method's doc comment on why this is always a "no ghost
/// yet" state, never an error state).
enum GhostModeError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
