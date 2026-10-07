// Core/Tests/CoreTests/WeeklyRankTimeSavedTests.swift
//
// Session 37: the weekly recap's rank movement and "time your apps stayed locked" summary.
//   - `SeasonsAndRanks.rankMovementDays` / `rankMovement(from:to:)` (pure) and
//     `weeklyRankMovement(weekStart:)` over an in-memory store (season boundary, first week)
//   - `WeeklyRecapBuilder.summarize` with Time Bank spend and shield attempts, the comparison with
//     last week, and decoding a summary stored before these fields existed
//   - `LockedOutAttemptTracker`'s per-day tally (week totals, re-renders, retention)
//   - week boundaries across both US daylight-saving changes
//   - `Copy.weeklyRecap`'s time-saved lines
//
// Pure tests use fixed calendars (GMT, America/New_York). The SwiftData round trip uses
// `Calendar.current` on purpose: `SeasonsAndRanks` computes rank with `Calendar.current`, so the
// seeded days are built with the same calendar and the test holds in any CI time zone.

import Foundation
import SwiftData
import Testing
@testable import Core

private let gmt: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
}()

private let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

private func day(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func freshDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "zano.tests.weeklyRank.\(UUID().uuidString)"))
}

// MARK: - Rank movement (pure)

@Suite("Weekly rank movement")
@MainActor
struct WeeklyRankMovementTests {

    private static let q3 = SeasonsAndRanks.Season(
        year: 2026, quarter: 3, startDate: day(gmt, 2026, 7, 1), endDate: day(gmt, 2026, 10, 1)
    )
    private static let q4 = SeasonsAndRanks.Season(
        year: 2026, quarter: 4, startDate: day(gmt, 2026, 10, 1), endDate: day(gmt, 2027, 1, 1)
    )

    private func status(_ rank: SeasonsAndRanks.Rank, _ season: SeasonsAndRanks.Season, placement: Bool = false) -> SeasonsAndRanks.RankStatus {
        SeasonsAndRanks.RankStatus(
            rank: rank,
            consistency: rank.minimumConsistency,
            weeklyConsistency: [],
            season: season,
            isPlacement: placement
        )
    }

    @Test func comparesLastSundayWithThisSunday() {
        // 2026-09-28 is a Monday.
        let days = SeasonsAndRanks.rankMovementDays(weekStart: day(gmt, 2026, 9, 28), calendar: gmt)
        #expect(days.previous == day(gmt, 2026, 9, 27))
        #expect(days.current == day(gmt, 2026, 10, 4))
    }

    @Test func movementIsTheSignedTierChange() {
        #expect(SeasonsAndRanks.rankMovement(from: status(.gold, Self.q3), to: status(.platinum, Self.q3)) == 1)
        #expect(SeasonsAndRanks.rankMovement(from: status(.bronze, Self.q3), to: status(.diamond, Self.q3)) == 4)
        #expect(SeasonsAndRanks.rankMovement(from: status(.platinum, Self.q3), to: status(.silver, Self.q3)) == -2)
        #expect(SeasonsAndRanks.rankMovement(from: status(.gold, Self.q3), to: status(.gold, Self.q3)) == 0)
    }

    @Test func aNewSeasonIsAResetNotADrop() {
        #expect(SeasonsAndRanks.rankMovement(from: status(.diamond, Self.q3), to: status(.bronze, Self.q4)) == nil)
        #expect(SeasonsAndRanks.rankMovement(from: status(.diamond, Self.q3), to: status(.bronze, Self.q4, placement: true)) == nil)
    }

    @Test func placementIsNeverCompared() {
        // Coming out of placement (forced Bronze) must not read as a climb, nor going in as a drop.
        #expect(SeasonsAndRanks.rankMovement(from: status(.bronze, Self.q4, placement: true), to: status(.gold, Self.q4)) == nil)
        #expect(SeasonsAndRanks.rankMovement(from: status(.gold, Self.q4), to: status(.bronze, Self.q4, placement: true)) == nil)
    }

    @Test func comparisonDaysAreCalendarDaysAcrossDaylightSaving() {
        // Spring forward: 2026-03-08 (Sunday) is 23 hours long in New York.
        let spring = SeasonsAndRanks.rankMovementDays(weekStart: day(newYork, 2026, 3, 9), calendar: newYork)
        #expect(spring.previous == day(newYork, 2026, 3, 8))
        #expect(spring.current == day(newYork, 2026, 3, 15))
        // Fall back: 2026-11-01 (Sunday) is 25 hours long; the week's Sunday is still midnight.
        let fall = SeasonsAndRanks.rankMovementDays(weekStart: day(newYork, 2026, 10, 26), calendar: newYork)
        #expect(fall.previous == day(newYork, 2026, 10, 25))
        #expect(fall.current == day(newYork, 2026, 11, 1))
        #expect(newYork.component(.hour, from: fall.current) == 0)
    }
}

// MARK: - Rank movement over a store

@Suite("Weekly rank movement — SwiftData")
@MainActor
struct WeeklyRankMovementStoreTests {

    private let calendar = Calendar.current

    private func noon(_ month: Int, _ dayOfMonth: Int) -> Date {
        day(calendar, 2026, month, dayOfMonth, 12)
    }

    /// A 3x-a-week user with verified completions on `days` (month, day).
    private func seededEngine(createdAt: Date, days: [(Int, Int)]) throws -> SeasonsAndRanks {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User(createdAt: createdAt)
        context.insert(user)
        let gym = Goal(type: .workoutGym, title: "Gym", cadence: "3x a week", verificationTier: .a, createdAt: createdAt, user: user)
        context.insert(gym)
        for (month, dayOfMonth) in days {
            context.insert(GoalEvent(ts: noon(month, dayOfMonth), kind: .complete, source: .geofence, verified: true, user: user, goal: gym))
        }
        try context.save()
        return SeasonsAndRanks(modelContainer: container)
    }

    @Test func aStrongerWeekMovesUpMidSeason() throws {
        // Week Mon 2026-08-24 – Sun 08-30, well inside Q3. Last Sunday's 4-week window holds one
        // full week (0.25 → Bronze); this Sunday's holds two (0.5 → Silver).
        let engine = try seededEngine(
            createdAt: noon(6, 1),
            days: [(8, 17), (8, 18), (8, 19), (8, 24), (8, 25), (8, 26)]
        )
        let weekStart = calendar.startOfDay(for: noon(8, 24))
        #expect(engine.weeklyRankMovement(weekStart: weekStart, calendar: calendar) == 1)
    }

    @Test func theWeekANewSeasonStartsHasNoMovement() throws {
        // Week Mon 2026-09-28 – Sun 10-04: last Sunday is Q3, this Sunday is Q4 (and in placement).
        let engine = try seededEngine(
            createdAt: noon(6, 1),
            days: [(9, 14), (9, 15), (9, 16), (9, 21), (9, 22), (9, 23), (9, 28), (9, 29), (9, 30)]
        )
        let weekStart = calendar.startOfDay(for: noon(9, 28))
        #expect(engine.weeklyRankMovement(weekStart: weekStart, calendar: calendar) == nil)
    }

    @Test func aFirstWeekHasNoMovement() throws {
        // The account started midweek: there was no rank "last Sunday" to move from.
        let engine = try seededEngine(createdAt: noon(8, 26), days: [(8, 26), (8, 27), (8, 28)])
        let weekStart = calendar.startOfDay(for: noon(8, 24))
        #expect(engine.weeklyRankMovement(weekStart: weekStart, calendar: calendar) == nil)
    }

    @Test func noUserMeansNoMovement() throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let engine = SeasonsAndRanks(modelContainer: container)
        #expect(engine.weeklyRankMovement(weekStart: calendar.startOfDay(for: noon(8, 24)), calendar: calendar) == nil)
    }
}

// MARK: - Time your apps stayed locked

@Suite("Weekly recap — time apps stayed locked")
@MainActor
struct WeeklyTimeSavedTests {

    private func week(
        start: Date,
        lockedHours: Double,
        spent: Int,
        attempts: Int,
        closes: Int
    ) -> RecapWeekInputs {
        RecapWeekInputs(
            weekStart: start,
            goals: [],
            lockIntervals: lockedHours > 0 ? [DateInterval(start: start.addingTimeInterval(9 * 3600), duration: lockedHours * 3600)] : [],
            earnedUnlockDates: [],
            reclaimedCloses: closes,
            timeBankSpentMinutes: spent,
            lockedAppAttempts: attempts
        )
    }

    @Test func timeBankSpendComesOffTheLockedTime() {
        let current = week(start: day(gmt, 2026, 9, 28), lockedHours: 3, spent: 25, attempts: 12, closes: 5)
        let summary = WeeklyRecapBuilder.summarize(current, previous: nil, currentStreak: 0, bestStreak: 0, rankMovement: 2, calendar: gmt)

        #expect(summary.lockedMinutes == 180)
        #expect(summary.appsLockedMinutes == 155)
        #expect(summary.lockedAppAttempts == 12)
        #expect(summary.reclaimedCloses == 5)
        #expect(summary.vsLastWeek == nil)

        let stats = WeeklyRecapBuilder.stats(for: summary, calendar: gmt)
        #expect(stats.timeReclaimedMinutes == 155)
        #expect(stats.rankMovement == 2)
    }

    @Test func spendingMoreThanWasLockedNeverGoesNegative() {
        #expect(WeeklyRecapBuilder.appsLockedMinutes(lockedMinutes: 30, spentMinutes: 45) == 0)
        #expect(WeeklyRecapBuilder.appsLockedMinutes(lockedMinutes: 30, spentMinutes: -5) == 30)
    }

    @Test func comparesWithLastWeek() {
        let current = week(start: day(gmt, 2026, 9, 28), lockedHours: 3, spent: 20, attempts: 8, closes: 2)
        let previous = week(start: day(gmt, 2026, 9, 21), lockedHours: 2, spent: 0, attempts: 14, closes: 1)
        let summary = WeeklyRecapBuilder.summarize(current, previous: previous, currentStreak: 0, bestStreak: 0, calendar: gmt)

        #expect(summary.vsLastWeek?.lockedMinutesDelta == 60)
        #expect(summary.vsLastWeek?.appsLockedMinutesDelta == 40)
        #expect(summary.vsLastWeek?.lockedAppAttemptsDelta == -6)
        #expect(summary.rankMovement == nil)
    }

    @Test func emptyWeeksHaveNoDataAndNoComparison() {
        let empty = week(start: day(gmt, 2026, 9, 28), lockedHours: 0, spent: 0, attempts: 0, closes: 0)
        let emptyBefore = week(start: day(gmt, 2026, 9, 21), lockedHours: 0, spent: 0, attempts: 0, closes: 0)
        let summary = WeeklyRecapBuilder.summarize(empty, previous: emptyBefore, currentStreak: 0, bestStreak: 0, calendar: gmt)
        #expect(!summary.hasData)
        #expect(summary.vsLastWeek == nil)
        #expect(summary.appsLockedMinutes == 0)

        // Reaching for a locked app is something that happened, even with no lock time logged.
        let attemptsOnly = week(start: day(gmt, 2026, 9, 28), lockedHours: 0, spent: 0, attempts: 3, closes: 0)
        #expect(WeeklyRecapBuilder.summarize(attemptsOnly, previous: nil, currentStreak: 0, bestStreak: 0, calendar: gmt).hasData)
    }

    @Test func summariesStoredBeforeSession37StillDecode() throws {
        let json = """
        {"weekStart":0,"earnedDays":1,"lockedMinutes":30,"goalsCompleted":2,"goalsPlanned":3,
         "completionsByType":{},"rings":{},"currentStreak":1,"bestStreak":1,"reclaimedCloses":0,
         "vsLastWeek":{"goalsCompletedDelta":1,"earnedDaysDelta":0,"lockedMinutesDelta":5}}
        """
        let summary = try JSONDecoder().decode(WeeklyRecapSummary.self, from: Data(json.utf8))
        #expect(summary.rankMovement == nil)
        #expect(summary.lockedAppAttempts == nil)
        #expect(summary.appsLockedMinutes == 30)
        #expect(summary.vsLastWeek?.appsLockedMinutesDelta == nil)
    }

    @Test func weekBoundariesHoldAcrossDaylightSaving() {
        // Spring forward inside the week: Mon 03-02 to Mon 03-09 is 167 hours, still one week.
        let springStart = WeeklyRecapBuilder.weekStart(containing: day(newYork, 2026, 3, 8, 20), calendar: newYork)
        #expect(springStart == day(newYork, 2026, 3, 2))
        let springEnd = newYork.date(byAdding: .day, value: 7, to: springStart)!
        #expect(springEnd == day(newYork, 2026, 3, 9))
        #expect(springEnd.timeIntervalSince(springStart) == 167 * 3600)

        // Fall back on the week's Sunday: due at 18:00 local that Sunday, for that same week.
        #expect(WeeklyRecapBuilder.dueWeekStart(now: day(newYork, 2026, 11, 1, 17, 59), calendar: newYork) == day(newYork, 2026, 10, 19))
        #expect(WeeklyRecapBuilder.dueWeekStart(now: day(newYork, 2026, 11, 1, 18), calendar: newYork) == day(newYork, 2026, 10, 26))
    }
}

// MARK: - Locked-app attempts per day

@Suite("LockedOutAttemptTracker — per-day tally")
struct LockedOutDailyTallyTests {

    @Test func countsAttemptsByLocalDay() throws {
        let defaults = try freshDefaults()
        let monday = day(gmt, 2026, 9, 28)
        // The previous Sunday, last week. (Recorded in time order, as the shield does.)
        LockedOutAttemptTracker.recordAttempt(appName: "C", at: monday.addingTimeInterval(-3600), defaults: defaults, calendar: gmt)
        LockedOutAttemptTracker.recordAttempt(appName: "A", at: monday.addingTimeInterval(9 * 3600), defaults: defaults, calendar: gmt)
        // A re-render 5 seconds later is the same attempt.
        LockedOutAttemptTracker.recordAttempt(appName: "A", at: monday.addingTimeInterval(9 * 3600 + 5), defaults: defaults, calendar: gmt)
        LockedOutAttemptTracker.recordAttempt(appName: "B", at: monday.addingTimeInterval(30 * 3600), defaults: defaults, calendar: gmt)

        let nextMonday = gmt.date(byAdding: .day, value: 7, to: monday)!
        #expect(LockedOutAttemptTracker.attempts(from: monday, to: nextMonday, calendar: gmt, defaults: defaults) == 2)
        let lastMonday = gmt.date(byAdding: .day, value: -7, to: monday)!
        #expect(LockedOutAttemptTracker.attempts(from: lastMonday, to: monday, calendar: gmt, defaults: defaults) == 1)
        // The hour window is unchanged.
        #expect(LockedOutAttemptTracker.attemptsInLastHour(asOf: monday.addingTimeInterval(9 * 3600 + 60), defaults: defaults) == 1)
    }

    @Test func aLateAttemptOnTheLongFallBackSundayStaysInItsWeek() throws {
        let defaults = try freshDefaults()
        LockedOutAttemptTracker.recordAttempt(appName: nil, at: day(newYork, 2026, 11, 1, 23, 30), defaults: defaults, calendar: newYork)
        let weekStart = day(newYork, 2026, 10, 26)
        let nextWeek = day(newYork, 2026, 11, 2)
        #expect(LockedOutAttemptTracker.attempts(from: weekStart, to: nextWeek, calendar: newYork, defaults: defaults) == 1)
        #expect(LockedOutAttemptTracker.attempts(from: nextWeek, to: day(newYork, 2026, 11, 9), calendar: newYork, defaults: defaults) == 0)
    }

    @Test func keepsOnlyRecentDays() throws {
        let defaults = try freshDefaults()
        let first = day(gmt, 2026, 9, 1, 12)
        for offset in 0..<20 {
            LockedOutAttemptTracker.recordAttempt(appName: nil, at: gmt.date(byAdding: .day, value: offset, to: first)!, defaults: defaults, calendar: gmt)
        }
        let end = gmt.date(byAdding: .day, value: 21, to: first)!
        #expect(LockedOutAttemptTracker.attempts(from: first, to: end, calendar: gmt, defaults: defaults) == LockedOutAttemptTracker.dayRetention)
    }

    @Test func noTallyReadsAsZero() throws {
        let defaults = try freshDefaults()
        #expect(LockedOutAttemptTracker.attempts(from: day(gmt, 2026, 9, 28), to: day(gmt, 2026, 10, 5), calendar: gmt, defaults: defaults) == 0)
    }
}

// MARK: - Copy

@Suite("Copy.weeklyRecap — time apps stayed locked")
struct WeeklyTimeSavedCopyTests {

    @Test func comparisonReadsAsAFact() {
        #expect(Copy.weeklyRecap.appsLockedVsLastWeek(deltaMinutes: 70) == "+1h 10m vs last week")
        #expect(Copy.weeklyRecap.appsLockedVsLastWeek(deltaMinutes: -40) == "40m less than last week")
        #expect(Copy.weeklyRecap.appsLockedVsLastWeek(deltaMinutes: 0) == "Same as last week")
    }

    @Test func reachedLines() {
        #expect(Copy.weeklyRecap.reachedLine(attempts: 12, closes: 5) == "Reached for a locked app 12 times, closed it 5")
        #expect(Copy.weeklyRecap.reachedLine(attempts: 1, closes: 0) == "Reached for a locked app 1 time")
        #expect(Copy.weeklyRecap.reachedLine(attempts: 0, closes: 2) == "Closed a locked app 2 times")
        #expect(Copy.weeklyRecap.reachedLine(attempts: 0, closes: 0) == nil)
        #expect(Copy.weeklyRecap.reachedPill(attempts: 0, closes: 0) == nil)
        #expect(Copy.weeklyRecap.timeSavedNotes(appsLockedDeltaMinutes: nil, attempts: 0, closes: 0).isEmpty)
        #expect(Copy.weeklyRecap.timeSavedNotes(appsLockedDeltaMinutes: 5, attempts: 3, closes: 0).count == 2)
    }

    @Test func neverPassesItselfOffAsScreenTime() {
        let labels = [
            Copy.weeklyRecap.appsLockedTitle,
            Copy.weeklyRecap.appsLockedCaption,
            Copy.weeklyRecap.appsLockedLabel(duration: "1h"),
        ]
        for label in labels {
            #expect(!label.lowercased().contains("screen time"))
        }
        #expect(Copy.weeklyRecap.screenTimeFootnote.contains("not Apple Screen Time"))
    }
}
