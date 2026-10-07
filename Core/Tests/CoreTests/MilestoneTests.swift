// Core/Tests/CoreTests/MilestoneTests.swift
//
// Tests Core/Sources/Core/Retention/Milestones.swift: thresholds, the fire-once ledger (including
// ladder collapse), the monthly story's 3-earned-day threshold, the early bird window, and that no
// milestone exists for zero data.

import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor
struct MilestoneTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 2 Oct 2026, so "last month" is September 2026.
    private static let now = date(2026, 10, 2, 9)

    private func makeSubject() throws -> (MilestoneEngine, ModelContainer, User) {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        try context.save()
        let suite = "zano.tests.milestones.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (MilestoneEngine(modelContainer: container, defaults: defaults, calendar: Self.calendar), container, user)
    }

    private func setStreak(_ current: Int, userID: UUID, in container: ModelContainer) throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<Streak>(predicate: #Predicate<Streak> { $0.userID == userID }))
        if let streak = existing.first {
            streak.current = current
        } else {
            context.insert(Streak(userID: userID, current: current, best: current))
        }
        try context.save()
    }

    private func insertEarnedSession(userID: UUID, endedAt: Date, hours: Double = 1, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(LockSession(
            userID: userID,
            startedAt: endedAt.addingTimeInterval(-hours * 3600),
            endedAt: endedAt,
            mode: .earn,
            unlockKind: .earned
        ))
        try context.save()
    }

    // MARK: Pure thresholds

    @Test func streakThresholds() {
        func ids(_ streak: Int) -> [String] {
            MilestoneEngine.reached(in: MilestoneSnapshot(currentStreak: streak), now: Self.now, calendar: Self.calendar).map(\.id)
        }
        #expect(ids(0).isEmpty)
        #expect(ids(6).isEmpty)
        #expect(ids(7) == ["streak-7"])
        #expect(ids(29) == ["streak-7", "streak-14"])
        #expect(ids(365) == ["streak-7", "streak-14", "streak-30", "streak-50", "streak-100", "streak-365"])
    }

    @Test func lockedHourThresholds() {
        let start = Self.date(2026, 9, 1, 0)
        func reached(hours: Double) -> [String] {
            let snapshot = MilestoneSnapshot(lockIntervals: [DateInterval(start: start, duration: hours * 3600)])
            return MilestoneEngine.reached(in: snapshot, now: Self.now, calendar: Self.calendar).map(\.id)
                .filter { $0.hasPrefix("hours-") }
        }
        #expect(reached(hours: 9.99).isEmpty)
        #expect(reached(hours: 10) == ["hours-10"])
        #expect(reached(hours: 120) == ["hours-10", "hours-25", "hours-50", "hours-100"])
    }

    @Test func overlappingLocksCountOnce() {
        let start = Self.date(2026, 9, 1, 8)
        let intervals = [
            DateInterval(start: start, duration: 3600),
            DateInterval(start: start.addingTimeInterval(1800), duration: 3600),
            DateInterval(start: start.addingTimeInterval(7200), duration: 600),
        ]
        #expect(MilestoneEngine.lockedSeconds(intervals) == 5400 + 600)
    }

    @Test func earnedUnlockThresholds() {
        func ids(_ count: Int) -> [String] {
            let dates = (0..<count).map { Self.date(2026, 1, 1).addingTimeInterval(Double($0) * 60) }
            return MilestoneEngine.reached(in: MilestoneSnapshot(earnedUnlockDates: dates), now: Self.now, calendar: Self.calendar)
                .map(\.id).filter { $0.hasPrefix("unlocks-") }
        }
        #expect(ids(0).isEmpty)
        #expect(ids(1) == ["unlocks-1"])
        #expect(ids(9) == ["unlocks-1"])
        #expect(ids(10) == ["unlocks-1", "unlocks-10"])
    }

    @Test func earlyBirdWindow() {
        #expect(MilestoneEngine.isEarlyBird(Self.date(2026, 9, 3, 5, 0), calendar: Self.calendar))
        #expect(MilestoneEngine.isEarlyBird(Self.date(2026, 9, 3, 6, 59), calendar: Self.calendar))
        #expect(!MilestoneEngine.isEarlyBird(Self.date(2026, 9, 3, 7, 0), calendar: Self.calendar))
        #expect(!MilestoneEngine.isEarlyBird(Self.date(2026, 9, 3, 4, 59), calendar: Self.calendar))
    }

    @Test func longestRunCountsConsecutiveDays() {
        let days = [1, 2, 3, 5, 6, 6, 9].map { Self.date(2026, 9, $0) }
        #expect(MilestoneEngine.longestRun(of: days, calendar: Self.calendar) == 3)
        #expect(MilestoneEngine.longestRun(of: [], calendar: Self.calendar) == 0)
    }

    @Test func noMilestoneForZeroData() throws {
        #expect(MilestoneEngine.reached(in: MilestoneSnapshot(), now: Self.now, calendar: Self.calendar).isEmpty)
        let (engine, _, _) = try makeSubject()
        #expect(engine.evaluate(now: Self.now).isEmpty)
    }

    // MARK: Fire once

    @Test func milestoneFiresOnce() throws {
        let (engine, container, user) = try makeSubject()
        try setStreak(8, userID: user.id, in: container)

        let first = engine.evaluate(now: Self.now)
        #expect(first == [.streak(days: 7)])
        // Evaluating again without celebrating keeps it pending.
        #expect(engine.evaluate(now: Self.now) == first)

        engine.markCelebrated(.streak(days: 7))
        #expect(engine.evaluate(now: Self.now).isEmpty)

        try setStreak(14, userID: user.id, in: container)
        #expect(engine.evaluate(now: Self.now) == [.streak(days: 14)])
    }

    @Test func ladderCollapsesToHighestRung() throws {
        let (engine, container, user) = try makeSubject()
        try setStreak(40, userID: user.id, in: container)

        #expect(engine.evaluate(now: Self.now) == [.streak(days: 30)])
        engine.markCelebrated(.streak(days: 30))
        #expect(engine.loadLedger().isSuperset(of: ["streak-7", "streak-14", "streak-30"]))
        #expect(engine.evaluate(now: Self.now).isEmpty)

        // A streak that breaks and rebuilds never re-fires a celebrated rung.
        try setStreak(7, userID: user.id, in: container)
        #expect(engine.evaluate(now: Self.now).isEmpty)
    }

    @Test func newlyReachedIgnoresRungsBelowACelebratedOne() {
        let reached: [Milestone] = [.lockedHours(10), .lockedHours(25)]
        #expect(MilestoneEngine.newlyReached(reached, celebrated: ["hours-50"]).isEmpty)
        #expect(MilestoneEngine.newlyReached(reached, celebrated: []) == [.lockedHours(25)])
    }

    // MARK: Year in review

    private static func earnedDays(_ month: Int, count: Int, year: Int = 2026) -> [Date] {
        (1...count).map { date(year, month, $0, 8) }
    }

    @Test func yearInReviewOnlyShowsInDecemberAndTheFirstWeekOfJanuary() throws {
        let snapshot = MilestoneSnapshot(earnedUnlockDates: Self.earnedDays(3, count: 20))
        func review(_ now: Date) -> YearInReview? {
            MilestoneEngine.yearInReview(now: now, snapshot: snapshot, calendar: Self.calendar)
        }
        #expect(review(Self.date(2026, 10, 2)) == nil)
        #expect(review(Self.date(2026, 11, 30)) == nil)
        #expect(review(Self.date(2026, 12, 1))?.year == 2026)
        #expect(review(Self.date(2026, 12, 31))?.year == 2026)
        #expect(review(Self.date(2027, 1, 7))?.year == 2026)
        #expect(review(Self.date(2027, 1, 8)) == nil)
    }

    @Test func yearInReviewNeedsFourteenEarnedDays() {
        let december = Self.date(2026, 12, 5)
        let thirteen = MilestoneSnapshot(earnedUnlockDates: Self.earnedDays(3, count: 13))
        let fourteen = MilestoneSnapshot(earnedUnlockDates: Self.earnedDays(3, count: 14))
        #expect(MilestoneEngine.yearInReview(now: december, snapshot: thirteen, calendar: Self.calendar) == nil)
        #expect(MilestoneEngine.yearInReview(now: december, snapshot: fourteen, calendar: Self.calendar)?.earnedDays == 14)
    }

    @Test func yearInReviewFindsTheBestMonthTopGoalAndClipsToTheYear() throws {
        let snapshot = MilestoneSnapshot(
            lockIntervals: [DateInterval(start: Self.date(2025, 12, 31, 22), end: Self.date(2026, 1, 1, 2))],
            earnedUnlockDates: Self.earnedDays(3, count: 10) + Self.earnedDays(4, count: 5) + [Self.date(2025, 12, 30, 8)],
            goalCompletions: [
                .init(date: Self.date(2026, 3, 1), goalTitle: "Water"),
                .init(date: Self.date(2026, 3, 2), goalTitle: "Gym session"),
                .init(date: Self.date(2026, 4, 2), goalTitle: "Gym session"),
                .init(date: Self.date(2025, 12, 30), goalTitle: "Water"),
                .init(date: Self.date(2025, 12, 31), goalTitle: "Water"),
            ]
        )
        let review = try #require(MilestoneEngine.yearInReview(now: Self.date(2026, 12, 10), snapshot: snapshot, calendar: Self.calendar))
        #expect(review.earnedDays == 15, "last year's December unlock is not in 2026")
        #expect(review.bestMonth == 3)
        #expect(review.bestMonthDays == 10)
        #expect(review.bestStreak == 10)
        #expect(review.lockedMinutes == 120, "only the 2 hours inside 2026 count")
        #expect(review.topGoalTitle == "Gym session", "last year's completions don't count")
    }

    @Test func yearInReviewComesFirstAndHasItsOwnLedgerId() {
        let review = YearInReview(year: 2026, earnedDays: 20, earnedUnlocks: 20, lockedMinutes: 600, bestStreak: 5,
                                  topGoalTitle: nil, bestMonth: 3, bestMonthDays: 10)
        let story = MonthlyStory(year: 2026, month: 11, earnedDays: 9, earnedUnlocks: 9, lockedMinutes: 60, bestStreak: 4, topGoalTitle: nil)
        #expect(Milestone.yearInReview(review).id == "year-2026")
        let ordered = MilestoneEngine.newlyReached([.streak(days: 7), .monthlyStory(story), .yearInReview(review)], celebrated: [])
        #expect(ordered.first == .yearInReview(review))
        #expect(MilestoneEngine.newlyReached([.yearInReview(review)], celebrated: ["year-2026"]).isEmpty, "shown once")
    }

    // MARK: Monthly story

    @Test func monthlyStoryNeedsThreeEarnedDays() throws {
        let twoDays = MilestoneSnapshot(earnedUnlockDates: [Self.date(2026, 9, 1), Self.date(2026, 9, 2), Self.date(2026, 9, 2, 18)])
        #expect(MilestoneEngine.monthlyStory(now: Self.now, snapshot: twoDays, calendar: Self.calendar) == nil)

        let threeDays = MilestoneSnapshot(
            lockIntervals: [DateInterval(start: Self.date(2026, 8, 31, 22), end: Self.date(2026, 9, 1, 2))],
            earnedUnlockDates: [Self.date(2026, 9, 1), Self.date(2026, 9, 2), Self.date(2026, 9, 10)],
            goalCompletions: [
                .init(date: Self.date(2026, 9, 1), goalTitle: "Water"),
                .init(date: Self.date(2026, 9, 2), goalTitle: "Gym session"),
                .init(date: Self.date(2026, 9, 3), goalTitle: "Gym session"),
                .init(date: Self.date(2026, 10, 1), goalTitle: "Water"),
                .init(date: Self.date(2026, 10, 1, 13), goalTitle: "Water"),
            ]
        )
        let story = try #require(MilestoneEngine.monthlyStory(now: Self.now, snapshot: threeDays, calendar: Self.calendar))
        #expect(story.year == 2026)
        #expect(story.month == 9)
        #expect(story.earnedDays == 3)
        #expect(story.bestStreak == 2)
        // Clipped to September: 22:00 Aug 31 to 02:00 Sep 1 counts 2 hours.
        #expect(story.lockedMinutes == 120)
        // October's completions don't count toward September's top goal.
        #expect(story.topGoalTitle == "Gym session")
    }

    @Test func monthlyStoryFromStoreFiresOncePerMonth() throws {
        let (engine, container, user) = try makeSubject()
        for day in [3, 4, 5] {
            try insertEarnedSession(userID: user.id, endedAt: Self.date(2026, 9, day, 8), in: container)
        }

        let pending = engine.evaluate(now: Self.now)
        let story = try #require(pending.first)
        #expect(story.id == "month-2026-09")
        // 3 earned unlocks also reached the 1st-earned-unlock rung; the story is presented first.
        #expect(pending.map(\.id) == ["month-2026-09", "unlocks-1"])

        engine.markCelebrated(story)
        #expect(engine.evaluate(now: Self.now).map(\.id) == ["unlocks-1"])
        // Next month, September's story doesn't come back (October had no earned days).
        engine.markCelebrated(.earnedUnlocks(1))
        #expect(engine.evaluate(now: Self.date(2026, 11, 1, 9)).isEmpty)
    }

    // MARK: Early bird (store)

    @Test func earlyBirdNeedsAGymCompletionBeforeSeven() throws {
        let (engine, container, subjectUser) = try makeSubject()
        let context = ModelContext(container)
        // The user row must belong to this context: relating rows to an object from another
        // context isn't reliable in SwiftData.
        let userID = subjectUser.id
        let user = try #require(try context.fetch(FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == userID })).first)
        let gym = Goal(type: .workoutGym, title: "Gym session", verificationTier: .a, user: user)
        let water = Goal(type: .water, title: "Water", verificationTier: .b, user: user)
        context.insert(gym)
        context.insert(water)
        // Not early enough, wrong kind, wrong goal: none qualify.
        context.insert(GoalEvent(ts: Self.date(2026, 9, 3, 7, 5), kind: .complete, source: .geofence, verified: true, user: user, goal: gym))
        context.insert(GoalEvent(ts: Self.date(2026, 9, 4, 6, 0), kind: .verify, source: .geofence, verified: true, user: user, goal: gym))
        context.insert(GoalEvent(ts: Self.date(2026, 9, 5, 6, 0), kind: .complete, source: .widget, verified: true, user: user, goal: water))
        try context.save()
        #expect(engine.evaluate(now: Self.now).isEmpty)

        let checkIn = Self.date(2026, 9, 6, 6, 12)
        context.insert(GoalEvent(ts: checkIn, kind: .complete, source: .geofence, verified: true, user: user, goal: gym))
        try context.save()
        #expect(engine.evaluate(now: Self.now) == [.earlyBird(checkInAt: checkIn)])

        engine.markCelebrated(.earlyBird(checkInAt: checkIn))
        #expect(engine.evaluate(now: Self.now).isEmpty)
    }
}
