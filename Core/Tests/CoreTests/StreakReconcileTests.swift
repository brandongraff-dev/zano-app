// StreakReconcileTests.swift
//
// `StreakEngine.reconcileMissedDays(asOf:)` — the end-of-day catch-up that records real misses so
// Never Miss Twice (spec §5.6) arms without waiting for an emergency unlock. Health-paused days
// never count (spec §24).
//
// Dates sit in mid-June 2023, away from any DST change and from the other suites' anchors, because
// `HealthPause` history is global App Group state and the paused-day test writes to it.

import Foundation
import SwiftData
import Testing
@testable import Core

private let reconcileAnchor: Date = {
    let components = DateComponents(year: 2023, month: 6, day: 14, hour: 12)
    return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_686_744_000)
}()

/// `offset` days after the anchor, at noon (so "asOf" is always mid-day).
private func reconcileDay(_ offset: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: reconcileAnchor) ?? reconcileAnchor
}

@MainActor
@Suite("StreakEngine — reconcileMissedDays", .serialized)
struct StreakReconcileTests {

    private func makeEngine() throws -> (engine: StreakEngine, container: ModelContainer) {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(User())
        try context.save()
        let defaults = UserDefaults(suiteName: "StreakReconcileTests.\(UUID().uuidString)") ?? .standard
        return (StreakEngine(modelContainer: container, reconcileDefaults: defaults), container)
    }

    private func missCount(in container: ModelContainer) throws -> Int {
        try ModelContext(container).fetch(FetchDescriptor<GoalEvent>())
            .filter { $0.kind == .miss && $0.goal == nil }
            .count
    }

    private func armed(in container: ModelContainer) throws -> Bool {
        try ModelContext(container).fetch(FetchDescriptor<Streak>()).first?.neverMissTwiceArmed ?? false
    }

    /// Earns days 0...2 (streak 3), then runs the first sweep on day 3, which only stamps day 2.
    private func earnThreeDaysAndStamp(_ engine: StreakEngine) async {
        await engine.recordEarnedUnlock(on: reconcileDay(0))
        await engine.recordEarnedUnlock(on: reconcileDay(1))
        await engine.recordEarnedUnlock(on: reconcileDay(2))
        await engine.reconcileMissedDays(asOf: reconcileDay(3))
    }

    @Test("the first run only stamps yesterday and records no misses")
    func firstRunStampsOnly() async throws {
        let (engine, container) = try makeEngine()
        await engine.recordEarnedUnlock(on: reconcileDay(0))

        await engine.reconcileMissedDays(asOf: reconcileDay(5))

        #expect(try missCount(in: container) == 0)
        #expect(try armed(in: container) == false)
        #expect(await engine.currentStreak() == 1)
    }

    @Test("an unearned yesterday arms Never Miss Twice, and repeat calls change nothing")
    func idempotentAndArms() async throws {
        let (engine, container) = try makeEngine()
        await earnThreeDaysAndStamp(engine)

        await engine.reconcileMissedDays(asOf: reconcileDay(4))
        await engine.reconcileMissedDays(asOf: reconcileDay(4))
        await engine.reconcileMissedDays(asOf: reconcileDay(4).addingTimeInterval(3600))

        #expect(try missCount(in: container) == 1)
        #expect(try armed(in: container))
        #expect(await engine.currentStreak() == 3, "one miss never breaks the streak")

        // The comeback earn continues the streak instead of resetting it.
        await engine.recordEarnedUnlock(on: reconcileDay(4))
        #expect(await engine.currentStreak() == 4)
    }

    @Test("an earned yesterday is not a miss")
    func earnedDayIsNotAMiss() async throws {
        let (engine, container) = try makeEngine()
        await earnThreeDaysAndStamp(engine)
        await engine.recordEarnedUnlock(on: reconcileDay(3))

        await engine.reconcileMissedDays(asOf: reconcileDay(4))

        #expect(try missCount(in: container) == 0)
        #expect(await engine.currentStreak() == 4)
    }

    @Test("two unearned days in one sweep break the streak")
    func twoMissedDaysBreakStreak() async throws {
        let (engine, container) = try makeEngine()
        await earnThreeDaysAndStamp(engine)

        await engine.reconcileMissedDays(asOf: reconcileDay(5))

        #expect(try missCount(in: container) == 2)
        #expect(await engine.currentStreak() == 0)
    }

    @Test("health-paused days are skipped")
    func skipsPausedDays() async throws {
        let previous = SharedDefaults.healthPauseHistory
        defer { SharedDefaults.healthPauseHistory = previous }

        let (engine, container) = try makeEngine()
        await earnThreeDaysAndStamp(engine)

        let calendar = Calendar.current
        let pauseStart = calendar.startOfDay(for: reconcileDay(3))
        let pauseEnd = calendar.startOfDay(for: reconcileDay(5))
        SharedDefaults.healthPauseHistory = previous + [HealthPause.Interval(start: pauseStart, end: pauseEnd)]

        await engine.reconcileMissedDays(asOf: reconcileDay(5))

        #expect(try missCount(in: container) == 0)
        #expect(try armed(in: container) == false)
        #expect(await engine.currentStreak() == 3)
    }

    @Test("a long absence only looks back reconcileLookBackDays days")
    func lookBackIsCapped() async throws {
        let (engine, container) = try makeEngine()
        await engine.recordEarnedUnlock(on: reconcileDay(0))
        await engine.reconcileMissedDays(asOf: reconcileDay(1)) // stamps day 0

        await engine.reconcileMissedDays(asOf: reconcileDay(40))

        #expect(try missCount(in: container) == StreakEngine.reconcileLookBackDays)
        #expect(await engine.currentStreak() == 0)
    }
}

// MARK: - LockedOutAttemptTracker (spec §5.16: "3+ times in an hour")

@Suite("LockedOutAttemptTracker — attempts in the last hour")
struct LockedOutAttemptTrackerTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LockedOutAttemptTrackerTests.\(UUID().uuidString)") ?? .standard
    }

    @Test("counts attempts in the trailing hour and keeps the last app name")
    func countsTrailingHour() {
        let defaults = makeDefaults()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        LockedOutAttemptTracker.recordAttempt(appName: "Old", at: start, defaults: defaults)
        LockedOutAttemptTracker.recordAttempt(appName: "TikTok", at: start.addingTimeInterval(3000), defaults: defaults)
        LockedOutAttemptTracker.recordAttempt(appName: nil, at: start.addingTimeInterval(3300), defaults: defaults)
        LockedOutAttemptTracker.recordAttempt(appName: "TikTok", at: start.addingTimeInterval(3700), defaults: defaults)

        let now = start.addingTimeInterval(3700)
        #expect(LockedOutAttemptTracker.attemptsInLastHour(asOf: now, defaults: defaults) == 3)
        #expect(LockedOutAttemptTracker.lastAttemptAppName(asOf: now, defaults: defaults) == "TikTok")
        #expect(LockedOutAttemptTracker.lastAttemptAppName(asOf: now.addingTimeInterval(7200), defaults: defaults) == nil)
    }

    @Test("repeat renders a few seconds apart count as one attempt")
    func dedupesRepeatRenders() {
        let defaults = makeDefaults()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        LockedOutAttemptTracker.recordAttempt(appName: "A", at: start, defaults: defaults)
        LockedOutAttemptTracker.recordAttempt(appName: "A", at: start.addingTimeInterval(2), defaults: defaults)
        #expect(LockedOutAttemptTracker.attemptsInLastHour(asOf: start.addingTimeInterval(3), defaults: defaults) == 1)
    }
}
