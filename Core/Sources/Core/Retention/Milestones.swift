// Core/Sources/Core/Retention/Milestones.swift
//
// Shareable milestone moments (founder-approved growth feature, 2026-10-02): the moment a user
// earns something worth posting, the app offers a 9:16 card to share. Every milestone is computed
// from local data only (SwiftData in the App Group), and each one fires exactly once.
//
// Milestones:
//   - Streak: 7, 14, 30, 50, 100, 365 days (the `Streak` row's `current`, which `StreakEngine` owns).
//   - Hours locked in: 10, 25, 50, 100, 250, 500 hours, the union of every *ended* `LockSession`'s
//     start...end (overlaps counted once). This is time the apps were locked, NOT "screen time
//     saved": real screen time is only visible inside the Screen Time report extension.
//   - Earned unlocks: the 1st, 10th, 50th and 100th lock that ended `.earned`.
//   - Early bird: the first gym goal `.complete` event logged between 5:00 and 7:00 local time.
//   - Monthly story: on the first evaluation in a new month, "Your <Month>" for the previous month,
//     only if that month had at least 3 earned days (days with an earned unlock).
//
// Fire-once ledger: the ids of celebrated milestones live in the App Group defaults (same pattern
// as `VariableReward`'s ledger). Ladders collapse: someone who already has a 40-day streak when this
// ships sees one "30 days" moment, not 7, 14 and 30 in a row, because `markCelebrated` also marks
// every lower rung of the same ladder.
//
// SwiftData: no enum is compared inside a `#Predicate` (that crashed the app in CI). Sessions are
// fetched whole, goal events by date only, and kinds/types are filtered in Swift.

import Foundation
import SwiftData
import os

// MARK: - Values

/// The previous month's summary for the "Your <Month>" story.
public struct MonthlyStory: Codable, Sendable, Hashable {
    public let year: Int
    /// 1...12.
    public let month: Int
    /// Distinct days in the month with at least one earned unlock.
    public let earnedDays: Int
    /// Earned unlocks in the month.
    public let earnedUnlocks: Int
    /// Minutes apps were locked in the month (overlapping locks counted once, clipped to the month).
    public let lockedMinutes: Int
    /// The longest run of consecutive earned days inside the month.
    public let bestStreak: Int
    /// The goal completed most often in the month, `nil` when no completion names a goal.
    public let topGoalTitle: String?

    public init(year: Int, month: Int, earnedDays: Int, earnedUnlocks: Int, lockedMinutes: Int, bestStreak: Int, topGoalTitle: String?) {
        self.year = year
        self.month = month
        self.earnedDays = earnedDays
        self.earnedUnlocks = earnedUnlocks
        self.lockedMinutes = lockedMinutes
        self.bestStreak = bestStreak
        self.topGoalTitle = topGoalTitle
    }

    /// The month's standalone name in the user's locale ("September"). Locale data, not app copy.
    public func monthName(calendar: Calendar = .current) -> String {
        let symbols = calendar.standaloneMonthSymbols
        guard (1...symbols.count).contains(month) else { return "" }
        return symbols[month - 1]
    }

    /// Whole hours locked, rounded down (never rounds a share card up).
    public var lockedHours: Int { lockedMinutes / 60 }
}

/// One shareable milestone.
public enum Milestone: Sendable, Hashable, Identifiable {
    case streak(days: Int)
    case lockedHours(Int)
    case earnedUnlocks(Int)
    /// `checkInAt` is the qualifying gym completion's timestamp.
    case earlyBird(checkInAt: Date)
    case monthlyStory(MonthlyStory)

    /// Ladder families share an id prefix; `markCelebrated` marks the lower rungs too.
    public enum Family: Int, Sendable, Comparable, CaseIterable {
        // Raw value is presentation priority: a monthly story is time-sensitive, so it goes first.
        case monthlyStory = 0
        case streak
        case earnedUnlocks
        case lockedHours
        case earlyBird

        public static func < (lhs: Family, rhs: Family) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The rungs of a ladder family, ascending. Empty for one-off families.
        public var ladder: [Int] {
            switch self {
            case .streak: MilestoneEngine.streakThresholds
            case .lockedHours: MilestoneEngine.lockedHourThresholds
            case .earnedUnlocks: MilestoneEngine.earnedUnlockThresholds
            case .earlyBird, .monthlyStory: []
            }
        }

        var idPrefix: String {
            switch self {
            case .streak: "streak"
            case .lockedHours: "hours"
            case .earnedUnlocks: "unlocks"
            case .earlyBird: "early-bird"
            case .monthlyStory: "month"
            }
        }

        func ladderID(_ threshold: Int) -> String { "\(idPrefix)-\(threshold)" }
    }

    public var family: Family {
        switch self {
        case .streak: .streak
        case .lockedHours: .lockedHours
        case .earnedUnlocks: .earnedUnlocks
        case .earlyBird: .earlyBird
        case .monthlyStory: .monthlyStory
        }
    }

    /// The ladder rung, or `nil` for one-off milestones.
    public var threshold: Int? {
        switch self {
        case .streak(let days): days
        case .lockedHours(let hours): hours
        case .earnedUnlocks(let count): count
        case .earlyBird, .monthlyStory: nil
        }
    }

    /// Stable ledger id: "streak-30", "hours-100", "unlocks-1", "early-bird", "month-2026-09".
    public var id: String {
        switch self {
        case .earlyBird:
            return Family.earlyBird.idPrefix
        case .monthlyStory(let story):
            let month = story.month < 10 ? "0\(story.month)" : "\(story.month)"
            return "\(Family.monthlyStory.idPrefix)-\(story.year)-\(month)"
        default:
            return family.ladderID(threshold ?? 0)
        }
    }
}

/// Everything the pure evaluation reads, as plain values (so tests need no store).
public struct MilestoneSnapshot: Sendable, Equatable {
    public struct GoalCompletion: Sendable, Equatable {
        public let date: Date
        public let goalTitle: String?
        public init(date: Date, goalTitle: String?) {
            self.date = date
            self.goalTitle = goalTitle
        }
    }

    public var currentStreak: Int
    /// start...end of every ended lock session.
    public var lockIntervals: [DateInterval]
    /// `endedAt` of every session that ended `.earned`.
    public var earnedUnlockDates: [Date]
    /// Timestamps of gym goal `.complete` events.
    public var gymCompletionDates: [Date]
    /// Every goal `.complete` event (for the monthly story's top goal).
    public var goalCompletions: [GoalCompletion]

    public init(
        currentStreak: Int = 0,
        lockIntervals: [DateInterval] = [],
        earnedUnlockDates: [Date] = [],
        gymCompletionDates: [Date] = [],
        goalCompletions: [GoalCompletion] = []
    ) {
        self.currentStreak = currentStreak
        self.lockIntervals = lockIntervals
        self.earnedUnlockDates = earnedUnlockDates
        self.gymCompletionDates = gymCompletionDates
        self.goalCompletions = goalCompletions
    }
}

// MARK: - Engine

@MainActor
public final class MilestoneEngine {
    public static let shared = MilestoneEngine()

    public nonisolated static let streakThresholds = [7, 14, 30, 50, 100, 365]
    public nonisolated static let lockedHourThresholds = [10, 25, 50, 100, 250, 500]
    public nonisolated static let earnedUnlockThresholds = [1, 10, 50, 100]
    /// A month needs this many earned days for a "Your <Month>" story.
    public nonisolated static let monthlyStoryMinimumEarnedDays = 3
    /// Early bird window, local hours: 5:00 up to (not including) 7:00.
    public nonisolated static let earlyBirdHours = 5..<7

    static let ledgerKey = "zano.milestones.celebrated.v1"

    private let modelContainer: ModelContainer
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "MilestoneEngine")

    /// `internal` so `CoreTests` can pass an in-memory container, a throwaway defaults suite and a
    /// fixed calendar.
    init(modelContainer: ModelContainer = .appGroup, defaults: UserDefaults? = nil, calendar: Calendar = .current) {
        self.modelContainer = modelContainer
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        self.calendar = calendar
    }

    // MARK: Public API

    /// Milestones newly reached and not yet celebrated, highest rung per ladder, in presentation
    /// priority order (monthly story, streak, earned unlocks, hours, early bird). Read-only: call
    /// `markCelebrated(_:)` once one is actually shown.
    public func evaluate(now: Date = .now) -> [Milestone] {
        let celebrated = loadLedger()
        let snapshot = makeSnapshot(now: now, includeAllGoalEvents: !celebrated.contains(Milestone.Family.earlyBird.idPrefix))
        let reached = Self.reached(in: snapshot, now: now, calendar: calendar)
        return Self.newlyReached(reached, celebrated: celebrated)
    }

    /// Records `milestone` (and every lower rung of its ladder) as celebrated, so it never fires again.
    public func markCelebrated(_ milestone: Milestone) {
        var ledger = loadLedger()
        ledger.formUnion(Self.ledgerIDs(markingCelebrated: milestone))
        saveLedger(ledger)
    }

    // MARK: Pure computation

    /// Every milestone `snapshot` has reached as of `now`, celebrated or not (the monthly story only
    /// for the month before `now`).
    public nonisolated static func reached(in snapshot: MilestoneSnapshot, now: Date, calendar: Calendar) -> [Milestone] {
        var result: [Milestone] = []

        result += streakThresholds.filter { snapshot.currentStreak >= $0 }.map { Milestone.streak(days: $0) }

        let hours = Int(lockedSeconds(snapshot.lockIntervals) / 3600)
        result += lockedHourThresholds.filter { hours >= $0 }.map { Milestone.lockedHours($0) }

        let unlocks = snapshot.earnedUnlockDates.count
        result += earnedUnlockThresholds.filter { unlocks >= $0 }.map { Milestone.earnedUnlocks($0) }

        if let first = snapshot.gymCompletionDates.filter({ isEarlyBird($0, calendar: calendar) && $0 <= now }).min() {
            result.append(.earlyBird(checkInAt: first))
        }

        if let story = monthlyStory(now: now, snapshot: snapshot, calendar: calendar) {
            result.append(.monthlyStory(story))
        }
        return result
    }

    /// Filters `reached` down to what should still be celebrated: not in the ledger, above any
    /// celebrated rung of its ladder, and only the highest such rung per ladder. Sorted by
    /// presentation priority.
    public nonisolated static func newlyReached(_ reached: [Milestone], celebrated: Set<String>) -> [Milestone] {
        var best: [Milestone.Family: Milestone] = [:]
        for milestone in reached where !celebrated.contains(milestone.id) {
            let family = milestone.family
            if let threshold = milestone.threshold {
                let highestCelebrated = family.ladder.filter { celebrated.contains(family.ladderID($0)) }.max() ?? 0
                guard threshold > highestCelebrated else { continue }
                if let current = best[family]?.threshold, current >= threshold { continue }
            }
            best[family] = milestone
        }
        return best.values.sorted { $0.family < $1.family }
    }

    /// The ledger ids `markCelebrated` writes: the milestone's own id plus every lower rung.
    public nonisolated static func ledgerIDs(markingCelebrated milestone: Milestone) -> Set<String> {
        var ids: Set<String> = [milestone.id]
        if let threshold = milestone.threshold {
            let family = milestone.family
            for rung in family.ladder where rung <= threshold {
                ids.insert(family.ladderID(rung))
            }
        }
        return ids
    }

    /// Total seconds covered by `intervals`, overlaps counted once.
    public nonisolated static func lockedSeconds(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?
        for interval in sorted {
            if let start = currentStart, let end = currentEnd {
                if interval.start <= end {
                    currentEnd = max(end, interval.end)
                    continue
                }
                total += end.timeIntervalSince(start)
            }
            currentStart = interval.start
            currentEnd = interval.end
        }
        if let start = currentStart, let end = currentEnd {
            total += end.timeIntervalSince(start)
        }
        return total
    }

    /// A gym check-in between 5:00 and 7:00 local time.
    public nonisolated static func isEarlyBird(_ date: Date, calendar: Calendar) -> Bool {
        earlyBirdHours.contains(calendar.component(.hour, from: date))
    }

    /// Longest run of consecutive calendar days in `days` (any time of day; duplicates ignored).
    public nonisolated static func longestRun(of days: [Date], calendar: Calendar) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in sorted {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// The story for the month before `now`'s month, or `nil` if it had fewer than
    /// `monthlyStoryMinimumEarnedDays` earned days.
    public nonisolated static func monthlyStory(now: Date, snapshot: MilestoneSnapshot, calendar: Calendar) -> MonthlyStory? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let previousStart = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
              let month = calendar.dateInterval(of: .month, for: previousStart) else { return nil }
        func inMonth(_ date: Date) -> Bool { date >= month.start && date < month.end }

        let earned = snapshot.earnedUnlockDates.filter(inMonth)
        let earnedDays = Set(earned.map { calendar.startOfDay(for: $0) })
        guard earnedDays.count >= monthlyStoryMinimumEarnedDays else { return nil }

        let clipped = snapshot.lockIntervals.compactMap { $0.intersection(with: month) }
        let lockedMinutes = Int(lockedSeconds(clipped) / 60)

        var counts: [String: Int] = [:]
        for completion in snapshot.goalCompletions where inMonth(completion.date) {
            guard let title = completion.goalTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
            counts[title, default: 0] += 1
        }
        // Most completions wins; ties go alphabetically so the result is stable.
        let topGoal = counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key

        let components = calendar.dateComponents([.year, .month], from: month.start)
        return MonthlyStory(
            year: components.year ?? 0,
            month: components.month ?? 0,
            earnedDays: earnedDays.count,
            earnedUnlocks: earned.count,
            lockedMinutes: lockedMinutes,
            bestStreak: longestRun(of: earned, calendar: calendar),
            topGoalTitle: topGoal
        )
    }

    // MARK: Snapshot (SwiftData)

    /// Reads local state into plain values. Predicates compare dates and ids only.
    func makeSnapshot(now: Date, includeAllGoalEvents: Bool) -> MilestoneSnapshot {
        let context = ModelContext(modelContainer)
        var snapshot = MilestoneSnapshot()

        // Streak: the current user's row.
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        if let userID = (try? context.fetch(userDescriptor))?.first?.id {
            var streakDescriptor = FetchDescriptor<Streak>(predicate: #Predicate<Streak> { $0.userID == userID })
            streakDescriptor.fetchLimit = 1
            snapshot.currentStreak = (try? context.fetch(streakDescriptor))?.first?.current ?? 0
        }

        // Lock sessions: whole table, filtered in Swift (unlockKind is an enum).
        let sessions = (try? context.fetch(FetchDescriptor<LockSession>())) ?? []
        for session in sessions {
            guard let end = session.endedAt, end > session.startedAt, end <= now.addingTimeInterval(60) else { continue }
            snapshot.lockIntervals.append(DateInterval(start: session.startedAt, end: end))
            if session.unlockKind == .earned {
                snapshot.earnedUnlockDates.append(end)
            }
        }

        // Goal events: by date only. All of history while Early bird is still unclaimed, otherwise
        // just from the previous month's start (all the monthly story needs).
        let lowerBound: Date
        if includeAllGoalEvents {
            lowerBound = .distantPast
        } else if let thisMonth = calendar.dateInterval(of: .month, for: now),
                  let previous = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) {
            lowerBound = previous
        } else {
            lowerBound = .distantPast
        }
        let events = (try? context.fetch(FetchDescriptor<GoalEvent>(predicate: #Predicate<GoalEvent> { $0.ts >= lowerBound }))) ?? []
        for event in events where event.kind == .complete {
            let goal = event.goal
            snapshot.goalCompletions.append(.init(date: event.ts, goalTitle: goal?.title))
            if goal?.type == .workoutGym {
                snapshot.gymCompletionDates.append(event.ts)
            }
        }
        return snapshot
    }

    // MARK: Ledger

    func loadLedger() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.ledgerKey) ?? [])
    }

    private func saveLedger(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: Self.ledgerKey)
        logger.debug("Milestone ledger now holds \(ids.count, privacy: .public) ids.")
    }
}
