// Core/Sources/Core/Retention/WeeklyRecapBuilder.swift
//
// Builds the weekly recap ON DEVICE (audit item N1 in docs/design/unfinished-audit-2026-10-02.md:
// the Sunday "your recap is ready" nudge linked to an always-empty recap, because spec §9.6's
// Sunday 6 PM job is a server job that doesn't exist yet). Spec §5.14 Weekly Report Card, §5.15
// Time Reclaimed, §9.6 Weekly Recap Writer.
//
// What it does: from Sunday 18:00 (or on the first foreground after it), it writes the `Recap` row
// for the week (Monday–Sunday) from local data only:
//   - goal rings: per goal, completed days ÷ expected days (a gym goal set to N workouts a week
//     expects N; a weekly goal expects 1; a daily goal expects every day it existed that week)
//   - goals completed / planned, best day, current streak
//   - "time reclaimed" = time locked in (lock sessions clipped to the week, overlaps counted once,
//     the same rule `MilestoneEngine` uses)
//   - a coach line in the user's voice from templates (`Copy.weeklyRecap`): one win, one suggestion
//   - rank movement over the week (`SeasonsAndRanks.weeklyRankMovement`, session 37)
// Extras the `Recap` model has no column for (earned days, completions per goal type, best streak,
// shield "Close app" taps, the comparison with last week) are kept as a `WeeklyRecapSummary` in the
// App Group (`summary(forWeekStart:)`), so Progress or a milestone can show them without a schema
// migration.
//
// "Screen time saved" (session 37) is an on-device estimate from ZANO's own data, NOT Apple Screen
// Time (usage numbers are only readable inside the DeviceActivityReport extension and never reach
// the app): time apps stayed locked = lock time minus Time Bank minutes spent opening them, plus how
// many times the user reached for a locked app (shield renders, `LockedOutAttemptTracker`'s per-day
// tally) and closed it (`ReclaimedOpens`). The attempt and close counts stay in the on-device
// summary; only the minutes go into the synced `RecapStats.timeReclaimedMinutes`, as before.
//
// A week with no data at all gets NO row, and `NudgeScheduler` skips that Sunday's nudge
// (`hasData(weekContaining:)`). Running it again is safe: the due week's row is recomputed and only
// saved when something changed.
//
// Hook: `NudgeScheduler.reschedule()` calls `buildIfDue()` first thing, so it already runs on every
// app foreground with no extra call site.

import Foundation
import SwiftData
import os

// MARK: - Summary

/// Everything the recap shows for one week, including what `RecapStats` has no field for.
public struct WeeklyRecapSummary: Codable, Sendable, Equatable {
    public struct Comparison: Codable, Sendable, Equatable {
        public var goalsCompletedDelta: Int
        public var earnedDaysDelta: Int
        public var lockedMinutesDelta: Int
        /// Change in `appsLockedMinutes`. Optional only so summaries stored before session 37
        /// still decode.
        public var appsLockedMinutesDelta: Int?
        /// Change in `lockedAppAttempts` (same decoding note).
        public var lockedAppAttemptsDelta: Int?
    }

    public var weekStart: Date
    public var earnedDays: Int
    public var lockedMinutes: Int
    public var goalsCompleted: Int
    public var goalsPlanned: Int
    /// `GoalType.rawValue` → completed days.
    public var completionsByType: [String: Int]
    /// `Goal.id.uuidString` → 0...1.
    public var rings: [String: Double]
    /// `Calendar` weekday with the most completions, if any.
    public var bestWeekday: Int?
    public var currentStreak: Int
    public var bestStreak: Int
    /// Shield "Close app" taps (`ReclaimedOpens`).
    public var reclaimedCloses: Int
    /// `nil` when last week had nothing to compare with.
    public var vsLastWeek: Comparison?

    // Added in session 37. Optional so summaries stored before it still decode.

    /// Ranks moved over the week (positive = up); `nil` when there's no honest comparison
    /// (new season, placement, first week; see `SeasonsAndRanks.rankMovement(from:to:)`).
    public var rankMovement: Int?
    /// Time Bank minutes spent opening locked apps this week (they were unlocked for that long).
    public var timeBankSpentMinutes: Int?
    /// Times a shield showed for a locked app this week ("reached for a locked app").
    public var lockedAppAttempts: Int?

    /// "Time your apps stayed locked": lock time minus the Time Bank minutes spent opening them.
    /// An estimate from ZANO's own locks, not Apple Screen Time.
    public var appsLockedMinutes: Int {
        max(0, lockedMinutes - (timeBankSpentMinutes ?? 0))
    }

    public var hasData: Bool {
        earnedDays > 0 || goalsCompleted > 0 || lockedMinutes > 0 || reclaimedCloses > 0 || (lockedAppAttempts ?? 0) > 0
    }
}

// MARK: - Pure inputs

/// One goal as the summary needs it.
public struct RecapGoalInput: Sendable, Equatable {
    public var id: UUID
    public var type: GoalType
    public var title: String
    /// How many completed days fill this goal's ring this week.
    public var expectedDays: Int
    /// Start-of-day dates this goal was complete on, within the week.
    public var completedDays: Set<Date>

    public init(id: UUID, type: GoalType, title: String, expectedDays: Int, completedDays: Set<Date>) {
        self.id = id
        self.type = type
        self.title = title
        self.expectedDays = expectedDays
        self.completedDays = completedDays
    }
}

/// One week's raw material, as plain values.
public struct RecapWeekInputs: Sendable, Equatable {
    public var weekStart: Date
    public var goals: [RecapGoalInput]
    /// Lock sessions already clipped to the week.
    public var lockIntervals: [DateInterval]
    public var earnedUnlockDates: [Date]
    public var reclaimedCloses: Int
    /// Time Bank minutes spent this week (`TimeBank.spentMin` summed over the week's days).
    public var timeBankSpentMinutes: Int
    /// Shield renders for locked apps this week (`LockedOutAttemptTracker.attempts`).
    public var lockedAppAttempts: Int

    public init(
        weekStart: Date,
        goals: [RecapGoalInput],
        lockIntervals: [DateInterval],
        earnedUnlockDates: [Date],
        reclaimedCloses: Int,
        timeBankSpentMinutes: Int = 0,
        lockedAppAttempts: Int = 0
    ) {
        self.weekStart = weekStart
        self.goals = goals
        self.lockIntervals = lockIntervals
        self.earnedUnlockDates = earnedUnlockDates
        self.reclaimedCloses = reclaimedCloses
        self.timeBankSpentMinutes = timeBankSpentMinutes
        self.lockedAppAttempts = lockedAppAttempts
    }
}

// MARK: - Builder

@MainActor
public final class WeeklyRecapBuilder {
    public static let shared = WeeklyRecapBuilder()

    /// Sunday 18:00 (spec §9.6), an hour before the recap nudge.
    nonisolated static let buildHour = 18
    nonisolated static let summaryKeyPrefix = "zano.weeklyRecap.summary."
    nonisolated static let keptSummaries = 8

    private let modelContainer: ModelContainer
    private let calendar: Calendar
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "WeeklyRecapBuilder")

    init(modelContainer: ModelContainer = .appGroup, calendar: Calendar = .current, defaults: UserDefaults = SharedDefaults.store) {
        self.modelContainer = modelContainer
        self.calendar = calendar
        self.defaults = defaults
    }

    // MARK: Public

    /// Creates or refreshes the recap for the most recent week whose Sunday 18:00 has passed.
    /// Returns the week's summary when a row exists for it afterwards (`nil` for a week with no
    /// data, or when there's no local user yet).
    @discardableResult
    public func buildIfDue(now: Date = .now, voiceOverride: CoachVoice? = nil) -> WeeklyRecapSummary? {
        let weekStart = Self.dueWeekStart(now: now, calendar: calendar)
        let readContext = ModelContext(modelContainer)
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        guard let user = try? readContext.fetch(userDescriptor).first else { return nil }
        let userID = user.id
        let voice = voiceOverride ?? user.coachVoice

        guard let current = inputs(weekStart: weekStart, userID: userID, now: now, context: readContext) else { return nil }
        let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let previous = inputs(weekStart: previousStart, userID: userID, now: now, context: readContext)
        let streak = streakValues(userID: userID, context: readContext)
        let rankMovement = SeasonsAndRanks(modelContainer: modelContainer).weeklyRankMovement(weekStart: weekStart, calendar: calendar)

        let summary = Self.summarize(
            current,
            previous: previous,
            currentStreak: streak.current,
            bestStreak: streak.best,
            rankMovement: rankMovement,
            calendar: calendar
        )
        guard summary.hasData else { return nil }
        storeSummary(summary)

        let plannedTypes = Set(ImplementationPlan.load(from: defaults)?.entries.map(\.goalType) ?? [])
        let text = Self.coachLine(for: summary, goals: current.goals, voice: voice, plannedGoalTypes: plannedTypes, calendar: calendar)
        let stats = Self.stats(for: summary, calendar: calendar)
        writeRecap(userID: userID, weekStart: weekStart, stats: stats, text: text)
        return summary
    }

    /// Whether the week containing `date` has any data so far. `NudgeScheduler` skips the Sunday
    /// recap nudge when it doesn't.
    public func hasData(weekContaining date: Date, now: Date = .now) -> Bool {
        let weekStart = Self.weekStart(containing: date, calendar: calendar)
        let context = ModelContext(modelContainer)
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        guard let userID = (try? context.fetch(userDescriptor))?.first?.id,
              let week = inputs(weekStart: weekStart, userID: userID, now: now, context: context) else { return false }
        return Self.summarize(week, previous: nil, currentStreak: 0, bestStreak: 0, calendar: calendar).hasData
    }

    /// The stored summary for the week starting `weekStart` (extras the `Recap` row can't hold).
    public func summary(forWeekStart weekStart: Date) -> WeeklyRecapSummary? {
        let key = Self.summaryKeyPrefix + ReclaimedOpens.dayKey(weekStart, calendar: calendar)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeeklyRecapSummary.self, from: data)
    }

    // MARK: Week math (pure)

    /// Monday 00:00 of `date`'s week.
    public nonisolated static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        return mondayFirst.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The week the recap is due for: this week from Sunday 18:00, otherwise last week.
    public nonisolated static func dueWeekStart(now: Date, calendar: Calendar) -> Date {
        let thisWeek = weekStart(containing: now, calendar: calendar)
        if let sunday = calendar.date(byAdding: .day, value: 6, to: thisWeek),
           let buildTime = calendar.date(bySettingHour: buildHour, minute: 0, second: 0, of: sunday),
           now >= buildTime {
            return thisWeek
        }
        return calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
    }

    // MARK: Summary (pure)

    public nonisolated static func summarize(
        _ week: RecapWeekInputs,
        previous: RecapWeekInputs?,
        currentStreak: Int,
        bestStreak: Int,
        rankMovement: Int? = nil,
        calendar: Calendar
    ) -> WeeklyRecapSummary {
        let completed = week.goals.reduce(0) { $0 + $1.completedDays.count }
        let planned = week.goals.reduce(0) { $0 + max($1.expectedDays, $1.completedDays.count) }

        var byType: [String: Int] = [:]
        var rings: [String: Double] = [:]
        var byWeekday: [Int: Int] = [:]
        for goal in week.goals {
            byType[goal.type.rawValue, default: 0] += goal.completedDays.count
            let expected = max(1, goal.expectedDays)
            rings[goal.id.uuidString] = min(1, Double(goal.completedDays.count) / Double(expected))
            for day in goal.completedDays {
                byWeekday[calendar.component(.weekday, from: day), default: 0] += 1
            }
        }
        // Most completions wins; ties go to the earlier day of the week (Monday first).
        let bestWeekday = byWeekday.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : mondayIndex(lhs.key) > mondayIndex(rhs.key)
        }?.key

        let earnedDays = Set(week.earnedUnlockDates.map { calendar.startOfDay(for: $0) }).count
        let lockedMinutes = Int(MilestoneEngine.lockedSeconds(week.lockIntervals) / 60)

        let appsLocked = appsLockedMinutes(lockedMinutes: lockedMinutes, spentMinutes: week.timeBankSpentMinutes)

        var comparison: WeeklyRecapSummary.Comparison?
        if let previous {
            let previousCompleted = previous.goals.reduce(0) { $0 + $1.completedDays.count }
            let previousEarned = Set(previous.earnedUnlockDates.map { calendar.startOfDay(for: $0) }).count
            let previousLocked = Int(MilestoneEngine.lockedSeconds(previous.lockIntervals) / 60)
            let previousAppsLocked = appsLockedMinutes(lockedMinutes: previousLocked, spentMinutes: previous.timeBankSpentMinutes)
            if previousCompleted > 0 || previousEarned > 0 || previousLocked > 0 || previous.lockedAppAttempts > 0 {
                comparison = .init(
                    goalsCompletedDelta: completed - previousCompleted,
                    earnedDaysDelta: earnedDays - previousEarned,
                    lockedMinutesDelta: lockedMinutes - previousLocked,
                    appsLockedMinutesDelta: appsLocked - previousAppsLocked,
                    lockedAppAttemptsDelta: week.lockedAppAttempts - previous.lockedAppAttempts
                )
            }
        }

        return WeeklyRecapSummary(
            weekStart: week.weekStart,
            earnedDays: earnedDays,
            lockedMinutes: lockedMinutes,
            goalsCompleted: completed,
            goalsPlanned: planned,
            completionsByType: byType,
            rings: rings,
            bestWeekday: bestWeekday,
            currentStreak: currentStreak,
            bestStreak: max(bestStreak, MilestoneEngine.longestRun(of: week.earnedUnlockDates, calendar: calendar)),
            reclaimedCloses: week.reclaimedCloses,
            vsLastWeek: comparison,
            rankMovement: rankMovement,
            timeBankSpentMinutes: week.timeBankSpentMinutes,
            lockedAppAttempts: week.lockedAppAttempts
        )
    }

    /// Lock time minus Time Bank minutes spent (spending opens the locked apps for that long, so
    /// that time wasn't locked). Never negative.
    nonisolated static func appsLockedMinutes(lockedMinutes: Int, spentMinutes: Int) -> Int {
        max(0, lockedMinutes - max(0, spentMinutes))
    }

    private nonisolated static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    /// The coach line: one win, one suggestion (spec §9.6), from templates.
    public nonisolated static func coachLine(
        for summary: WeeklyRecapSummary,
        goals: [RecapGoalInput],
        voice: CoachVoice,
        plannedGoalTypes: Set<GoalType>,
        calendar: Calendar
    ) -> String {
        let win: Copy.weeklyRecap.Win
        if let delta = summary.vsLastWeek?.goalsCompletedDelta, delta > 0 {
            win = .improved(by: delta)
        } else if summary.earnedDays > 0 {
            win = .earnedDays(summary.earnedDays)
        } else if summary.lockedMinutes >= 30 {
            win = .lockedMinutes(summary.lockedMinutes)
        } else if summary.goalsCompleted > 0 {
            win = .goalsCompleted(summary.goalsCompleted)
        } else {
            win = .closes(summary.reclaimedCloses)
        }

        let bestDayName = summary.bestWeekday.map { calendar.weekdaySymbols[($0 - 1) % 7] }
        let open = goals
            .filter { (summary.rings[$0.id.uuidString] ?? 0) < 1 }
            .min { (summary.rings[$0.id.uuidString] ?? 0) < (summary.rings[$1.id.uuidString] ?? 0) }
        let suggestion: Copy.weeklyRecap.Suggestion
        if let open, timedGoalTypes.contains(open.type), !plannedGoalTypes.contains(open.type) {
            suggestion = .planGoal(title: open.title)
        } else if open != nil, let bestDayName {
            suggestion = .repeatBestDay(bestDayName)
        } else if open == nil, !goals.isEmpty {
            suggestion = .keepPlan
        } else if let bestDayName {
            suggestion = .repeatBestDay(bestDayName)
        } else {
            suggestion = .keepPlan
        }
        return Copy.weeklyRecap.coachLine(voice: voice, win: win, suggestion: suggestion)
    }

    /// Goals done at a time of day, where "give it a set time" is good advice (protein or water
    /// are logged through the day, so they get the best-day suggestion instead).
    nonisolated static let timedGoalTypes: Set<GoalType> = [.workoutGym, .workoutHomeOutdoor, .focusSession, .reading, .stretchMobility]

    /// Maps the summary onto the synced `RecapStats` shape.
    public nonisolated static func stats(for summary: WeeklyRecapSummary, calendar: Calendar) -> RecapStats {
        RecapStats(
            goalCompletionRings: summary.rings,
            bestDay: summary.bestWeekday.map { calendar.weekdaySymbols[($0 - 1) % 7] },
            // Net of Time Bank spend: the apps were open for those minutes, so they weren't reclaimed.
            timeReclaimedMinutes: summary.appsLockedMinutes,
            streak: summary.currentStreak,
            rankMovement: summary.rankMovement,
            goalsCompleted: summary.goalsCompleted,
            goalsPlanned: summary.goalsPlanned
        )
    }

    // MARK: Reading SwiftData

    /// The week's inputs. Predicates compare dates only; enums and relationships are checked in
    /// Swift (SwiftData predicate limits).
    private func inputs(weekStart: Date, userID: UUID, now: Date, context: ModelContext) -> RecapWeekInputs? {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        let week = DateInterval(start: weekStart, end: weekEnd)

        let goals = ((try? context.fetch(FetchDescriptor<Goal>())) ?? []).filter { $0.user?.id == userID }
        let events = ((try? context.fetch(FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= weekStart && $0.ts < weekEnd }
        ))) ?? []).filter { $0.user?.id == userID || $0.user == nil }
        let plans = (try? context.fetch(FetchDescriptor<DailyPlan>(
            predicate: #Predicate<DailyPlan> { $0.date >= weekStart && $0.date < weekEnd }
        ))) ?? []

        var goalInputs: [RecapGoalInput] = []
        for goal in goals {
            let goalEvents = events.filter { $0.goal?.id == goal.id }
            let goalPlans = plans.filter { $0.goal?.id == goal.id }
            let createdDay = calendar.startOfDay(for: goal.createdAt)
            guard createdDay < weekEnd, goal.active || !goalEvents.isEmpty else { continue }

            var completedDays: Set<Date> = []
            var availableDays = 0
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
                      let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                guard day >= createdDay else { continue }
                availableDays += 1
                let dayEvents = goalEvents.filter { $0.ts >= day && $0.ts < next }
                guard !dayEvents.isEmpty else { continue }
                let planned = goalPlans.first { $0.date >= day && $0.date < next }?.plannedValue
                if GoalDayProgress(goal: goal, todaysEvents: dayEvents, plannedValue: planned).isComplete {
                    completedDays.insert(day)
                }
            }
            goalInputs.append(RecapGoalInput(
                id: goal.id,
                type: goal.type,
                title: goal.title,
                expectedDays: Self.expectedDays(for: goal, availableDays: availableDays),
                completedDays: completedDays
            ))
        }

        // Lock sessions: whole table, filtered in Swift (unlockKind is an enum).
        let sessions = (try? context.fetch(FetchDescriptor<LockSession>())) ?? []
        var intervals: [DateInterval] = []
        var earned: [Date] = []
        for session in sessions where session.userID == userID {
            let end = min(session.endedAt ?? now, now)
            guard end > session.startedAt,
                  let clipped = DateInterval(start: session.startedAt, end: end).intersection(with: week) else { continue }
            intervals.append(clipped)
            if session.unlockKind == .earned, let endedAt = session.endedAt, week.contains(endedAt) {
                earned.append(endedAt)
            }
        }

        // Time Bank rows are one per local day, dated at local midnight (`TimeBankEngine`).
        let banks = (try? context.fetch(FetchDescriptor<TimeBank>(
            predicate: #Predicate<TimeBank> { $0.userID == userID && $0.date >= weekStart && $0.date < weekEnd }
        ))) ?? []
        let spent = banks.reduce(0) { $0 + max(0, $1.spentMin) }

        let closes = ReclaimedOpens.count(from: weekStart, to: weekEnd, calendar: calendar, defaults: defaults)
        let attempts = LockedOutAttemptTracker.attempts(from: weekStart, to: weekEnd, calendar: calendar, defaults: defaults)
        return RecapWeekInputs(
            weekStart: weekStart,
            goals: goalInputs,
            lockIntervals: intervals,
            earnedUnlockDates: earned,
            reclaimedCloses: closes,
            timeBankSpentMinutes: spent,
            lockedAppAttempts: attempts
        )
    }

    /// A gym goal set to "N workouts" a week expects N days; a weekly goal 1; a daily goal every
    /// day it existed that week.
    nonisolated static func expectedDays(for goal: Goal, availableDays: Int) -> Int {
        if goal.cadence?.lowercased().contains("week") == true { return min(1, availableDays) }
        if goal.type == .workoutGym || goal.type == .workoutHomeOutdoor,
           goal.unit?.lowercased().contains("workout") == true,
           let perWeek = goal.targetValue, perWeek >= 1 {
            return min(Int(perWeek.rounded()), availableDays)
        }
        return availableDays
    }

    private func streakValues(userID: UUID, context: ModelContext) -> (current: Int, best: Int) {
        var descriptor = FetchDescriptor<Streak>(predicate: #Predicate<Streak> { $0.userID == userID })
        descriptor.fetchLimit = 1
        guard let streak = (try? context.fetch(descriptor))?.first else {
            return (SharedDefaults.currentStreak, SharedDefaults.bestStreak)
        }
        return (streak.current, streak.best)
    }

    // MARK: Writing

    /// Upserts the week's `Recap` in a fresh context; saves only when something changed.
    private func writeRecap(userID: UUID, weekStart: Date, stats: RecapStats, text: String) {
        let context = ModelContext(modelContainer)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: weekStart) ?? weekStart.addingTimeInterval(86_400)
        var descriptor = FetchDescriptor<Recap>(
            predicate: #Predicate<Recap> { $0.userID == userID && $0.weekStart >= weekStart && $0.weekStart < nextDay }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try context.fetch(descriptor).first {
                guard existing.stats != stats || existing.text != text else { return }
                existing.stats = stats
                existing.text = text
            } else {
                context.insert(Recap(userID: userID, weekStart: weekStart, text: text, stats: stats))
            }
            try context.save()
            logger.notice("Weekly recap written for week starting \(weekStart.timeIntervalSince1970, privacy: .public).")
        } catch {
            logger.error("Could not write the weekly recap: \(String(describing: error), privacy: .public)")
        }
    }

    private func storeSummary(_ summary: WeeklyRecapSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        let key = Self.summaryKeyPrefix + ReclaimedOpens.dayKey(summary.weekStart, calendar: calendar)
        let isNewWeek = defaults.data(forKey: key) == nil
        defaults.set(data, forKey: key)
        // Keep the newest few (only worth checking when a new week was added).
        guard isNewWeek else { return }
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Self.summaryKeyPrefix) }.sorted()
        for key in keys.dropLast(Self.keptSummaries) { defaults.removeObject(forKey: key) }
    }
}
