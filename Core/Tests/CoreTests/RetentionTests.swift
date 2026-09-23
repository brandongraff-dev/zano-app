// Core/Tests/CoreTests/RetentionTests.swift
//
// docs/spec.md §9.1 Adaptive Goal Engine (v1 rules):
//   "target completion rate 75–85%. If 7-day rate < 60% → lower the daily bar one step
//   (fewer minutes / fewer days / lower grams). If > 90% for 10 days → raise one step. Never
//   change more than one step per week."
// docs/spec.md §5.6 Never Miss Twice:
//   "A miss doesn't kill a streak. A second consecutive miss does. The app makes the 'comeback
//   day' feel special: bigger unlock celebration, 'Comeback' badge, shield copy that acknowledges
//   it."
//
// docs/sessions/09-retention.md flagged exactly these two rule sets under "Needs verification on":
//   "a real `swift test` exercising 28+ days of synthetic GoalEvent history through
//   AdaptiveGoalEngine/StreakEngine to confirm the step-change rules actually fire at the right
//   thresholds — worth writing as an early CoreTests addition," and under "Known issues": "No unit
//   tests were written for the difficulty-step math... a real test would catch an off-by-one before
//   it ships." This file is that early addition — nothing else.
//
// Scope is deliberately narrow, per this task's own brief: `AdaptiveGoalEngine.adjustDifficulty`/
// `dailyPlan`'s §9.1 thresholds, and `StreakEngine.recordMiss`/`recordEarnedUnlock`'s §5.6 Never
// Miss Twice behavior. `PlanB`, `ComebackMode`, `TravelMode`, `GhostMode`, `SeasonsAndRanks`, and
// `CosmeticsStore` were read for context (their header comments cross-reference `StreakEngine`/
// `AdaptiveGoalEngine` directly) but are NOT this file's concern — each is either out of this
// task's explicit brief or, like `ComebackMode`, deliberately independent of the two engines
// tested here (see `ComebackMode.swift`'s own header comment on why it doesn't call into
// `StreakEngine` to decide anything).
//
// Environment note (see this task's own `knownIssues`): this was written with no Mac/Swift
// toolchain available to actually run `swift test --package-path Core` (CLAUDE.md "Current
// environment status"). Every API used below is read directly from the real source files it
// exercises (`StreakEngine.swift`, `AdaptiveGoalEngine.swift`, and the `Models/` types), so this
// should compile and pass on the next Mac/CI run, but it has not been compiler-verified locally —
// flag any mismatch found there back into `docs/sessions/09-retention.md`.
//
// One assumption every test below shares: each test builds its own in-memory `ModelContainer`
// (never the real `.appGroup` singleton) and seeds `User`/`Goal`/`GoalEvent` rows through its own
// short-lived `ModelContext`, separate from the `ModelContext` the engine under test lazily creates
// internally over that *same* container. This relies on a second `ModelContext` over one
// `ModelContainer` seeing an earlier context's already-saved rows on its own next fetch —
// `ComebackMode.swift`'s header comment (this same directory) documents this exact pattern as safe
// ("there is no shared-object-identity requirement across contexts, only within one context's own
// fetched instances") and every engine here already exposes an `internal init(modelContainer:)`
// specifically so `CoreTests` can do this. Flagged here anyway since it's the one SwiftData
// behavior this whole file leans on that no Mac has confirmed yet.

import Foundation
import SwiftData
import Testing
@testable import Core

// MARK: - Shared fixtures

/// A fixed, deliberately DST-transition-safe anchor (mid-January — no timezone anywhere in the
/// world sits mid-DST-transition within a couple of weeks of this date, Northern *or* Southern
/// hemisphere). `AdaptiveGoalEngine.weeklyCappedDelta` compares raw `Date.timeIntervalSince`
/// seconds against a flat `7 * 24 * 60 * 60` constant, not calendar-day counts, so a test date
/// range that silently crosses a DST change could make the "8 days later" assertion below flaky
/// depending on which timezone `swift test` happens to run in. Anchoring here instead of at
/// `Date()`/`.now` keeps every test in this file deterministic regardless of when or where it runs.
private let retentionTestAnchor: Date = {
    let components = DateComponents(year: 2025, month: 1, day: 15, hour: 12)
    return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_736_942_400)
}()

/// `offset` calendar days from `base` (negative = earlier), normalized to local midnight the same
/// way every engine under test normalizes its own `date`/`ts` inputs (`Calendar.current.startOfDay`).
private func retentionTestDay(_ offset: Int, from base: Date = retentionTestAnchor) -> Date {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: base)
    return calendar.date(byAdding: .day, value: offset, to: start) ?? start
}

/// A fresh, isolated in-memory `ModelContainer` — never the real `.appGroup` singleton, so no test
/// in this file shares state with another or with a real device's store. Mirrors the `inMemory:
/// true` path `ModelContainer+AppGroup.swift` documents existing expressly "for SwiftUI previews
/// and unit tests."
private func makeInMemoryContainer() throws -> ModelContainer {
    try ModelContainer.makeAppGroupContainer(inMemory: true)
}

// MARK: - AdaptiveGoalEngine — spec §9.1 v1 rules

@MainActor
@Suite("AdaptiveGoalEngine — spec §9.1 v1 rules")
struct AdaptiveGoalEngineThresholdTests {

    /// A goal detached from any `ModelContext` — `adjustDifficulty(for:last28Days:)` is documented
    /// as "a pure, deterministic function of its input... trivially unit-testable with hand-built
    /// GoalEvents," so no SwiftData container is needed for the tests that call it directly.
    private func makeGoal(target: Double = 150, unit: String = "g") -> Goal {
        Goal(
            type: .protein,
            title: "Protein",
            targetValue: target,
            unit: unit,
            verificationTier: .b,
            active: true,
            adaptive: true,
            user: User()
        )
    }

    private func makeEngine() throws -> AdaptiveGoalEngine {
        AdaptiveGoalEngine(modelContainer: try makeInMemoryContainer())
    }

    // MARK: 7-day / 10-day rate thresholds (parameterized boundary table)

    /// One boundary case for the §9.1 rate thresholds. `completedWithinTenDayWindow` marks which
    /// day-offsets (0 = most recent, i.e. `adjustDifficulty`'s own "asOf" reference day) inside the
    /// trailing 10-day window get a verified `.complete` event; every other offset in `0...9` gets
    /// a verified-but-not-completed `.log` marker instead, so "not completed" is an explicit row,
    /// matching what `fetchRecentEvents` actually hands this method in production.
    ///
    /// `paddingDaysAllCompleted` fills the REST of spec §9.1's full 28-day input (offsets `10...27`)
    /// either all-completed or all-missed — deliberately the case least favorable to the correct,
    /// narrow-window answer. If `adjustDifficulty` ever regressed to reading a wider window than the
    /// 7/10 days spec §9.1 actually specifies (an off-by-one on the window size, not just the
    /// threshold), these paddings are chosen so that mistake would flip the expected `expectedDelta`
    /// — exactly the class of bug docs/sessions/09-retention.md flagged this suite as worth catching
    /// before it ships.
    struct ThresholdScenario: Sendable, CustomStringConvertible {
        let name: String
        let completedWithinTenDayWindow: Set<Int>
        let paddingDaysAllCompleted: Bool
        let expectedDelta: Int
        var description: String { name }
    }

    private static let thresholdScenarios: [ThresholdScenario] = [
        ThresholdScenario(
            name: "7-day rate 4/7 ≈ 57.1% (just under 60%) lowers one step",
            completedWithinTenDayWindow: [0, 1, 2, 3],
            paddingDaysAllCompleted: true,
            expectedDelta: -1
        ),
        ThresholdScenario(
            name: "7-day rate 5/7 ≈ 71.4% (at/above 60%) does not lower",
            completedWithinTenDayWindow: [0, 1, 2, 3, 4],
            paddingDaysAllCompleted: false,
            expectedDelta: 0
        ),
        ThresholdScenario(
            name: "only the 7th day back (offset 6) is completed — the 7-day window is inclusive of exactly 7 days, not 6",
            completedWithinTenDayWindow: [6],
            paddingDaysAllCompleted: false,
            expectedDelta: -1
        ),
        ThresholdScenario(
            name: "10-day rate exactly 90% (9/10) does not raise — the boundary is strictly '> 90%'",
            completedWithinTenDayWindow: Set(0...8),
            paddingDaysAllCompleted: true,
            expectedDelta: 0
        ),
        ThresholdScenario(
            name: "10-day rate 100% (10/10) raises one step",
            completedWithinTenDayWindow: Set(0...9),
            paddingDaysAllCompleted: false,
            expectedDelta: 1
        ),
        ThresholdScenario(
            name: "steady-state ~75–85% band (7-day ≈85.7%, 10-day 80%): neither threshold fires",
            completedWithinTenDayWindow: [0, 1, 2, 3, 4, 5, 7, 8],
            paddingDaysAllCompleted: true,
            expectedDelta: 0
        ),
    ]

    @Test("adjustDifficulty applies spec §9.1's 7-day/10-day rate thresholds", arguments: Self.thresholdScenarios)
    func ratesTriggerExpectedStepChange(_ scenario: ThresholdScenario) async throws {
        let goal = makeGoal()
        let referenceDay = retentionTestDay(0)

        var events: [GoalEvent] = []
        for offset in 0...9 {
            let kind: GoalEventKind = scenario.completedWithinTenDayWindow.contains(offset) ? .complete : .log
            events.append(GoalEvent(
                ts: retentionTestDay(-offset, from: referenceDay),
                kind: kind,
                source: .manual,
                verified: true,
                goal: goal
            ))
        }
        for offset in 10...27 {
            let kind: GoalEventKind = scenario.paddingDaysAllCompleted ? .complete : .log
            events.append(GoalEvent(
                ts: retentionTestDay(-offset, from: referenceDay),
                kind: kind,
                source: .manual,
                verified: true,
                goal: goal
            ))
        }

        let engine = try makeEngine()
        let delta = await engine.adjustDifficulty(for: goal, last28Days: events)
        #expect(delta == scenario.expectedDelta, "\(scenario.name)")
    }

    // MARK: Definitional edges the boundary table doesn't cover

    @Test("no history at all recommends no change")
    func emptyHistoryRecommendsNoChange() async throws {
        let goal = makeGoal()
        let engine = try makeEngine()
        let delta = await engine.adjustDifficulty(for: goal, last28Days: [])
        #expect(delta == 0)
    }

    @Test("an unverified 'complete' event does not count as a completion")
    func unverifiedCompleteEventsDoNotCount() async throws {
        let goal = makeGoal()
        let referenceDay = retentionTestDay(0)
        // Every day in the 10-day window has a `.complete` event, but none are verified — per
        // `adjustDifficulty`'s own doc comment, "Completed" means `verified == true` AND a
        // completing `kind`. If verification were ignored this would read as 100% (raise); reading
        // it correctly, nothing counts as completed at all, so the 7-day rate is 0% and lowers.
        let events = (0...9).map { offset in
            GoalEvent(
                ts: retentionTestDay(-offset, from: referenceDay),
                kind: .complete,
                source: .manual,
                verified: false,
                goal: goal
            )
        }
        let engine = try makeEngine()
        let delta = await engine.adjustDifficulty(for: goal, last28Days: events)
        #expect(delta == -1, "unverified events must not be counted as completions")
    }

    @Test("a verified Plan B completion counts as a real completion")
    func planBCompletionCounts() async throws {
        let goal = makeGoal()
        let referenceDay = retentionTestDay(0)
        // spec §5.5 / this file's own doc comment: "a Plan B completion still counts as genuine
        // engagement with the goal for this purpose."
        let events = (0...9).map { offset in
            GoalEvent(
                ts: retentionTestDay(-offset, from: referenceDay),
                kind: .planB,
                source: .manual,
                verified: true,
                goal: goal
            )
        }
        let engine = try makeEngine()
        let delta = await engine.adjustDifficulty(for: goal, last28Days: events)
        #expect(delta == 1, "a fully Plan-B'd 10-day window should still raise the bar")
    }

    @Test("verified log/verify/miss/freeze events do not count as completions")
    func nonCompletionKindsAreExcluded() async throws {
        let goal = makeGoal()
        let referenceDay = retentionTestDay(0)
        let nonCompletingKinds: [GoalEventKind] = [.log, .verify, .miss, .freeze]
        let events = (0...9).map { offset in
            GoalEvent(
                ts: retentionTestDay(-offset, from: referenceDay),
                kind: nonCompletingKinds[offset % nonCompletingKinds.count],
                source: .manual,
                verified: true,
                goal: goal
            )
        }
        let engine = try makeEngine()
        let delta = await engine.adjustDifficulty(for: goal, last28Days: events)
        #expect(delta == -1, "only .complete/.planB should ever count toward the completion rate")
    }

    @Test("events belonging to a different goal are ignored")
    func eventsForOtherGoalsAreIgnored() async throws {
        let goal = makeGoal()
        let otherGoal = makeGoal()
        let referenceDay = retentionTestDay(0)
        // A fully-completed 28-day history, but every event is tagged to `otherGoal`, not `goal`.
        let events = (0...27).map { offset in
            GoalEvent(
                ts: retentionTestDay(-offset, from: referenceDay),
                kind: .complete,
                source: .manual,
                verified: true,
                goal: otherGoal
            )
        }
        let engine = try makeEngine()
        let delta = await engine.adjustDifficulty(for: goal, last28Days: events)
        #expect(delta == 0, "another goal's history must not leak into this goal's recommendation")
    }

    // MARK: "Never more than one step per week" (needs real persistence — `dailyPlan`, not the pure function)

    @Test("dailyPlan never changes an adaptive goal's difficulty step more than once per 7-day window")
    func dailyPlanCapsStepChangesToOncePerWeek() async throws {
        let container = try makeInMemoryContainer()
        let setupContext = ModelContext(container)

        let day0 = retentionTestDay(0)
        let calendar = Calendar.current
        let user = User()
        let goal = Goal(
            type: .protein,
            title: "Protein",
            targetValue: 150,
            unit: "g",
            verificationTier: .b,
            active: true,
            adaptive: true,
            // Well past the 3-day engineered-early-win window (spec §8 rule 1), so `dailyPlan`
            // actually runs the §9.1 rules engine instead of the flat early-win plan.
            createdAt: retentionTestDay(-40, from: day0),
            user: user
        )
        setupContext.insert(user)
        setupContext.insert(goal)

        // An unbroken run of 0%-completion history (verified `.log` markers only — no `.complete`/
        // `.planB` anywhere) spanning from before day0's own 28-day lookback through the day before
        // the final `day0 + 8` call below. Every 7-day and 10-day trailing window this test's three
        // `dailyPlan` calls ever look at sees a 0% rate — comfortably under §9.1's "<60%" bar, with
        // no risk of the ">90%" raise rule firing instead and confusing the assertions.
        for offset in -12...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: day0) ?? day0
            setupContext.insert(GoalEvent(ts: day, kind: .log, source: .manual, verified: true, user: user, goal: goal))
        }
        try setupContext.save()

        let engine = AdaptiveGoalEngine(modelContainer: container)

        let plan0 = await engine.dailyPlan(for: goal, on: day0)
        #expect(plan0.difficultyStep == -1, "a struggling goal's very first plan should take one step down")

        let day1 = calendar.date(byAdding: .day, value: 1, to: day0) ?? day0
        let plan1 = await engine.dailyPlan(for: goal, on: day1)
        #expect(
            plan1.difficultyStep == -1,
            "a second recommended change only 1 day after the first must be capped — spec §9.1 'never more than one step per week'"
        )

        let day8 = calendar.date(byAdding: .day, value: 8, to: day0) ?? day0
        let plan8 = await engine.dailyPlan(for: goal, on: day8)
        #expect(
            plan8.difficultyStep == -2,
            "once a full 7+ days have elapsed since the last change, a further one-step change is allowed again"
        )
    }
}

// MARK: - StreakEngine — spec §5.6 Never Miss Twice

@MainActor
@Suite("StreakEngine — spec §5.6 Never Miss Twice")
struct StreakEngineNeverMissTwiceTests {

    private func makeEngine() throws -> (engine: StreakEngine, container: ModelContainer, userID: UUID) {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        try context.save()
        return (StreakEngine(modelContainer: container), container, user.id)
    }

    private func badgeKeys(userID: UUID, in container: ModelContainer) throws -> [String] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<Badge>())
            .filter { $0.userID == userID }
            .map(\.key)
    }

    @Test("a single miss preserves the streak — spec §5.6: 'a miss doesn't kill a streak'")
    func oneMissSurvives() async throws {
        let (engine, _, _) = try makeEngine()
        let day0 = retentionTestDay(0)
        let calendar = Calendar.current

        await engine.recordEarnedUnlock(on: day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 1, to: day0) ?? day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 2, to: day0) ?? day0)
        let beforeMiss = await engine.currentStreak()
        #expect(beforeMiss == 3)

        await engine.recordMiss(on: calendar.date(byAdding: .day, value: 3, to: day0) ?? day0)
        let afterMiss = await engine.currentStreak()
        #expect(afterMiss == 3, "a lone miss must not break the streak")
    }

    @Test("earning again after one forgiven miss continues the streak and awards the Comeback badge")
    func forgivenMissComebackContinuesStreakAndAwardsBadge() async throws {
        let (engine, container, userID) = try makeEngine()
        let day0 = retentionTestDay(0)
        let calendar = Calendar.current

        await engine.recordEarnedUnlock(on: day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 1, to: day0) ?? day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 2, to: day0) ?? day0)
        // streak == 3 as of day0+2

        let missDay = calendar.date(byAdding: .day, value: 3, to: day0) ?? day0
        await engine.recordMiss(on: missDay) // one miss — forgiven, arms Never Miss Twice

        let comebackDay = calendar.date(byAdding: .day, value: 4, to: day0) ?? day0
        await engine.recordEarnedUnlock(on: comebackDay)

        let streak = await engine.currentStreak()
        #expect(streak == 4, "the forgiven miss must not reset the streak — it should simply continue")

        let keys = try badgeKeys(userID: userID, in: container)
        #expect(keys.contains { $0.hasPrefix("comeback_") }, "spec §5.6: the comeback day awards a Comeback badge")
    }

    @Test("two consecutive misses break the streak — spec §5.6: 'a second consecutive miss does'")
    func twoConsecutiveMissesBreakStreak() async throws {
        let (engine, _, _) = try makeEngine()
        let day0 = retentionTestDay(0)
        let calendar = Calendar.current

        await engine.recordEarnedUnlock(on: day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 1, to: day0) ?? day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 2, to: day0) ?? day0)
        #expect(await engine.currentStreak() == 3)

        await engine.recordMiss(on: calendar.date(byAdding: .day, value: 3, to: day0) ?? day0) // 1st miss — forgiven
        #expect(await engine.currentStreak() == 3)

        await engine.recordMiss(on: calendar.date(byAdding: .day, value: 4, to: day0) ?? day0) // 2nd CONSECUTIVE miss
        let finalStreak = await engine.currentStreak()
        #expect(finalStreak == 0, "a second consecutive miss must break the streak")
    }

    @Test("a duplicate recordMiss call for the same day is idempotent, not a second miss")
    func duplicateMissSameDayIsIdempotent() async throws {
        let (engine, _, _) = try makeEngine()
        let day0 = retentionTestDay(0)
        let calendar = Calendar.current

        await engine.recordEarnedUnlock(on: day0)
        #expect(await engine.currentStreak() == 1)

        let missDay = calendar.date(byAdding: .day, value: 1, to: day0) ?? day0
        await engine.recordMiss(on: missDay)
        await engine.recordMiss(on: missDay) // e.g. a retried nightly slip-prediction job, spec §9.2
        #expect(await engine.currentStreak() == 1, "a duplicate miss for the SAME day must not double-count as two misses")

        // the single, deduplicated miss should still be forgiven by the next earn:
        let comebackDay = calendar.date(byAdding: .day, value: 2, to: day0) ?? day0
        await engine.recordEarnedUnlock(on: comebackDay)
        #expect(await engine.currentStreak() == 2)
    }

    @Test("a miss with no active streak leaves the streak at zero without crashing")
    func missWithNoActiveStreakStaysZero() async throws {
        let (engine, _, _) = try makeEngine()
        await engine.recordMiss(on: retentionTestDay(0))
        #expect(await engine.currentStreak() == 0)
    }

    @Test("an unforgiven gap (no recordMiss call at all) resets the streak to Day 1, not a forgiven comeback")
    func unforgivenGapResetsToDayOne() async throws {
        let (engine, _, _) = try makeEngine()
        let day0 = retentionTestDay(0)
        let calendar = Calendar.current

        await engine.recordEarnedUnlock(on: day0)
        await engine.recordEarnedUnlock(on: calendar.date(byAdding: .day, value: 1, to: day0) ?? day0)
        #expect(await engine.currentStreak() == 2)

        // A multi-day gap with NO recordMiss call ever made — nothing armed Never Miss Twice, so
        // this is an ordinary unforgiven gap, not the §5.6 mechanic this suite is otherwise about.
        let laterDay = calendar.date(byAdding: .day, value: 6, to: day0) ?? day0
        await engine.recordEarnedUnlock(on: laterDay)
        #expect(await engine.currentStreak() == 1, "an unforgiven gap restarts the streak at Day 1 (endowed progress), never Day 0")
    }

    @Test("recordEarnedUnlock twice on the same calendar day is idempotent")
    func sameDayRepeatEarnIsIdempotent() async throws {
        let (engine, _, _) = try makeEngine()
        let day0 = retentionTestDay(0)
        await engine.recordEarnedUnlock(on: day0)
        await engine.recordEarnedUnlock(on: day0) // e.g. two lock sets both unlocked the same day
        #expect(await engine.currentStreak() == 1)
    }

    @Test("currentStreak is 0 when no local User row exists yet")
    func currentStreakWithNoUserIsZero() async throws {
        let container = try makeInMemoryContainer()
        let engine = StreakEngine(modelContainer: container) // no User inserted
        #expect(await engine.currentStreak() == 0)
    }
}
