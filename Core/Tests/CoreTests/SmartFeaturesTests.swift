// Core/Tests/CoreTests/SmartFeaturesTests.swift
//
// The background "smart" features (2026-10-02, research items 2, 3, 4, 10 and audit item N1):
//   - `ImplementationPlan` (if-then plan) and `LockSchedule.planAwareDefault`
//   - `SlipRisk` (hand-set logistic score)
//   - `NudgeTimingBandit` / `NudgeTimingLedger` / `BetaSampler` and the bandit-aware
//     `NudgeScheduler.plan(_:)` (seeded, so every draw is reproducible)
//   - `WeeklyRecapBuilder` (pure summary + a SwiftData round trip)
//   - `ReclaimedOpens` and the one sec-style `ShieldCopy`
// Fixed GMT Gregorian calendar throughout. 2026-09-28 is a Monday.

import Foundation
import SwiftData
import Testing
@testable import Core

private let gmt: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 9) -> Date {
    gmt.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func freshDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "zano.tests.smart.\(UUID().uuidString)"))
}

// MARK: - If-then plan

@Suite("ImplementationPlan + plan-aware lock schedule")
struct ImplementationPlanTests {

    @Test func defaultWorkoutDaysSpreadAcrossTheWeek() {
        #expect(ImplementationPlan.defaultWorkoutDays(perWeek: 1) == [2])
        #expect(ImplementationPlan.defaultWorkoutDays(perWeek: 3) == [2, 4, 6])
        #expect(ImplementationPlan.defaultWorkoutDays(perWeek: 5) == [2, 3, 4, 5, 6])
        #expect(ImplementationPlan.defaultWorkoutDays(perWeek: 7) == LockSchedule.allWeekdays)
        #expect(ImplementationPlan.defaultWorkoutDays(perWeek: 0) == [2])
        #expect(ImplementationPlan.defaultWorkoutDays(perWeek: 12) == LockSchedule.allWeekdays)
    }

    @Test func plannedDaysAndEarliestMinute() {
        let plan = ImplementationPlan(entries: [
            .init(goalType: .workoutGym, weekdays: [2, 4, 6], minuteOfDay: 18 * 60),
            .init(goalType: .focusSession, weekdays: LockSchedule.allWeekdays, minuteOfDay: 9 * 60),
        ])
        #expect(plan.isPlannedDay(date(28), calendar: gmt))
        #expect(plan.earliestMinute(on: date(28), calendar: gmt) == 9 * 60)
        #expect(plan.entries(on: date(29), calendar: gmt).map(\.goalType) == [.focusSession])
        #expect(plan.plannedWeekdays == LockSchedule.allWeekdays)
    }

    @Test func emptyDayEntriesAreDropped() {
        let plan = ImplementationPlan(entries: [.init(goalType: .workoutGym, weekdays: [], minuteOfDay: 600)])
        #expect(plan.entries.isEmpty)
    }

    @Test func persistsInDefaults() throws {
        let defaults = try freshDefaults()
        let plan = ImplementationPlan(
            entries: [.init(goalType: .workoutGym, weekdays: [2, 4], minuteOfDay: 1_080)],
            slipPatternRaw: "weekends",
            createdAt: date(28)
        )
        ImplementationPlan.save(plan, to: defaults)
        #expect(ImplementationPlan.load(from: defaults) == plan)
        ImplementationPlan.save(nil, to: defaults)
        #expect(ImplementationPlan.load(from: defaults) == nil)
    }

    @Test func noPlanIsTheMorningDefault() {
        let id = UUID()
        #expect(LockSchedule.planAwareDefault(lockSetID: id, plan: nil, mode: .full) == .morningDefault(lockSetID: id, mode: .full))
    }

    @Test func gymOnlyPlanLocksOnlyGymDays() {
        let id = UUID()
        let plan = ImplementationPlan(entries: [.init(goalType: .workoutGym, weekdays: [2, 4, 6], minuteOfDay: 18 * 60)])
        let schedule = LockSchedule.planAwareDefault(lockSetID: id, plan: plan, activeGoalTypes: [.workoutGym], mode: .full)
        #expect(schedule.weekdays == [2, 4, 6])
        #expect(schedule.startMinuteOfDay == 7 * 60)
        #expect(schedule.isUntilGoalsDone)
        #expect(schedule.isValid)
    }

    @Test func anUnplannedDailyGoalKeepsEveryDay() {
        let plan = ImplementationPlan(entries: [.init(goalType: .workoutGym, weekdays: [2, 4, 6], minuteOfDay: 18 * 60)])
        let schedule = LockSchedule.planAwareDefault(lockSetID: UUID(), plan: plan, activeGoalTypes: [.workoutGym, .protein], mode: .full)
        #expect(schedule.weekdays == LockSchedule.allWeekdays)
    }

    @Test func anEarlyPlanStartsTheLockBeforeIt() {
        let plan = ImplementationPlan(entries: [.init(goalType: .workoutGym, weekdays: [2, 4, 6], minuteOfDay: 6 * 60 + 10)])
        let schedule = LockSchedule.planAwareDefault(lockSetID: UUID(), plan: plan, mode: .full)
        // 6:10 − 60 min = 5:10, rounded down to a quarter hour.
        #expect(schedule.startMinuteOfDay == 5 * 60)
    }
}

@Suite("LockSchedule.seededDefault — reads the user's active goals")
@MainActor
struct SeededScheduleTests {
    @Test func narrowsToGymDaysOnlyWhenEveryDailyGoalIsPlanned() throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        context.insert(Goal(type: .workoutGym, title: "Gym", targetValue: 3, unit: "workouts", cadence: "daily", verificationTier: .a, user: user))
        try context.save()
        let plan = ImplementationPlan(entries: [.init(goalType: .workoutGym, weekdays: [2, 4, 6], minuteOfDay: 18 * 60)])
        let id = UUID()
        #expect(LockSchedule.seededDefault(lockSetID: id, plan: plan, modelContainer: container).weekdays == [2, 4, 6])

        context.insert(Goal(type: .protein, title: "Protein", targetValue: 120, unit: "g", cadence: "daily", verificationTier: .b, user: user))
        try context.save()
        #expect(LockSchedule.seededDefault(lockSetID: id, plan: plan, modelContainer: container).weekdays == LockSchedule.allWeekdays)
        #expect(LockSchedule.seededDefault(lockSetID: id, plan: nil, modelContainer: container).startMinuteOfDay == 7 * 60)
    }
}

// MARK: - Slip risk

@Suite("SlipRisk — hand-set logistic score")
struct SlipRiskTests {

    @Test func workedExamplesFromTheHeader() {
        let steady = SlipRisk.score(SlipRiskFeatures(weekday: 3, daysSinceLastEarned: 1, streak: 5, isPlannedDay: true))
        #expect(abs(steady - 0.081) < 0.005)
        #expect(steady < SlipRisk.streakNudgeThreshold)

        let rough = SlipRisk.score(SlipRiskFeatures(
            weekday: 3, daysSinceLastEarned: 2, streak: 0, yesterdayMissed: true, planBUsedRecently: true
        ))
        #expect(abs(rough - 0.537) < 0.005)
        #expect(SlipRisk.isHighRisk(score: rough))
    }

    @Test func featuresMoveTheScoreTheRightWay() {
        let base = SlipRiskFeatures(weekday: 4, daysSinceLastEarned: 1, streak: 2, isPlannedDay: nil)
        func with(_ change: (inout SlipRiskFeatures) -> Void) -> Double {
            var f = base
            change(&f)
            return SlipRisk.score(f)
        }
        let b = SlipRisk.score(base)
        // Evaluated into locals first: closures inside `#expect` aren't expanded reliably.
        let missed = with { $0.yesterdayMissed = true }
        let planB = with { $0.planBUsedRecently = true }
        let fourDays = with { $0.daysSinceLastEarned = 4 }
        let neverEarned = with { $0.daysSinceLastEarned = nil }
        let longStreak = with { $0.streak = 20 }
        let planned = with { $0.isPlannedDay = true }
        let unplanned = with { $0.isPlannedDay = false }
        let saturday = with { $0.weekday = 7 }
        let monday = with { $0.weekday = 2 }
        let saturdayWithPrior = with {
            $0.weekday = 7
            $0.slipPatternRaw = "weekends"
        }
        let weekdayWithWeekendPrior = with { $0.slipPatternRaw = "weekends" }
        let goodRun = with { $0.streak = 4 }
        let goodRunWithPrior = with {
            $0.streak = 4
            $0.slipPatternRaw = "afterGoodDays"
        }
        #expect(missed > b)
        #expect(planB > b)
        #expect(fourDays > b)
        #expect(neverEarned > b)
        #expect(longStreak < b)
        #expect(planned < b)
        #expect(unplanned > b)
        #expect(saturday > b)
        #expect(monday < b)
        // The onboarding prior only bites on the matching days.
        #expect(saturdayWithPrior > saturday)
        #expect(weekdayWithWeekendPrior == b)
        #expect(goodRunWithPrior > goodRun)
    }

    @Test func daysSinceEarnedIsCapped() {
        let a = SlipRisk.score(SlipRiskFeatures(weekday: 4, daysSinceLastEarned: 7))
        let b = SlipRisk.score(SlipRiskFeatures(weekday: 4, daysSinceLastEarned: 300))
        #expect(a == b)
    }

    @Test func scoreIsAProbability() {
        let worst = SlipRisk.score(SlipRiskFeatures(
            weekday: 7, daysSinceLastEarned: 30, streak: 0, isPlannedDay: false,
            yesterdayMissed: true, planBUsedRecently: true, slipPatternRaw: "weekends"
        ))
        let best = SlipRisk.score(SlipRiskFeatures(weekday: 2, daysSinceLastEarned: 0, streak: 400, isPlannedDay: true))
        #expect(worst < 1 && worst > 0.9)
        #expect(best > 0 && best < 0.05)
    }
}

// MARK: - Bandit

@Suite("NudgeTimingBandit — Thompson sampling, seeded")
struct NudgeTimingBanditTests {

    @Test func seededGeneratorIsReproducible() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
    }

    @Test func betaSamplesHaveTheRightMean() {
        var rng = SeededGenerator(seed: 7)
        let draws = (0..<4_000).map { _ in BetaSampler.sample(alpha: 2, beta: 5, using: &rng) }
        let mean = draws.reduce(0, +) / Double(draws.count)
        #expect(abs(mean - 2.0 / 7.0) < 0.02)
        #expect(draws.allSatisfy { $0 > 0 && $0 < 1 })
        // Shapes below 1 go through the boost path.
        let small = (0..<2_000).map { _ in BetaSampler.sample(alpha: 0.5, beta: 0.5, using: &rng) }
        #expect(abs(small.reduce(0, +) / Double(small.count) - 0.5) < 0.03)
    }

    @Test func priorsFavourTheDefaultAndThePlan() {
        #expect(NudgeTimingBandit.prior(kind: .streakAtRisk, armID: "t1200") == BetaArm(alpha: 2, beta: 1))
        #expect(NudgeTimingBandit.prior(kind: .streakAtRisk, armID: "t1080") == BetaArm(alpha: 1, beta: 1))
        #expect(NudgeTimingBandit.prior(kind: .streakAtRisk, armID: "plan") == BetaArm(alpha: 3, beta: 1))
    }

    @Test func recordAddsRewardsAndForgets() {
        var bandit = NudgeTimingBandit()
        bandit.record(kind: .proteinLastMile, armID: "t1020", acted: true)
        #expect(bandit.posterior(kind: .proteinLastMile, armID: "t1020") == BetaArm(alpha: 2, beta: 1))
        bandit.record(kind: .proteinLastMile, armID: "t1020", acted: false)
        let after = bandit.posterior(kind: .proteinLastMile, armID: "t1020")
        #expect(abs(after.alpha - (1 + 0.97)) < 1e-9)
        #expect(abs(after.beta - 2) < 1e-9)
        // Other arms untouched.
        #expect(bandit.posterior(kind: .proteinLastMile, armID: "t1170") == BetaArm(alpha: 1, beta: 1))
    }

    @Test func choiceIsDeterministicPerSeed() {
        let bandit = NudgeTimingBandit()
        let arms: [NudgeTimeArm] = [.fixed(minutes: 1_200), .fixed(minutes: 1_080), .fixed(minutes: 1_140)]
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)
        #expect(bandit.choose(kind: .streakAtRisk, among: arms, using: &a) == bandit.choose(kind: .streakAtRisk, among: arms, using: &b))
        var c = SeededGenerator(seed: 1)
        #expect(bandit.choose(kind: .streakAtRisk, among: [], using: &c) == nil)
    }

    @Test func learnsTheArmThatWorks() {
        var bandit = NudgeTimingBandit()
        for _ in 0..<20 {
            bandit.record(kind: .streakAtRisk, armID: "t1140", acted: true)
            bandit.record(kind: .streakAtRisk, armID: "t1200", acted: false)
            bandit.record(kind: .streakAtRisk, armID: "t1080", acted: false)
        }
        let arms: [NudgeTimeArm] = [.fixed(minutes: 1_200), .fixed(minutes: 1_080), .fixed(minutes: 1_140)]
        var wins = 0
        for seed in 1...200 {
            var rng = SeededGenerator(seed: UInt64(seed))
            if bandit.choose(kind: .streakAtRisk, among: arms, using: &rng) == .fixed(minutes: 1_140) { wins += 1 }
        }
        #expect(wins > 180)
    }

    @Test func ledgerTracksFiredScoredAndCancelled() {
        var ledger = NudgeTimingLedger()
        let fired = UUID(), pending = UUID()
        ledger.record(nudgeID: fired, kind: .morningPlan, armID: "t480", fireDate: date(28, 8))
        ledger.record(nudgeID: pending, kind: .streakAtRisk, armID: "t1200", fireDate: date(28, 20))
        let now = date(28, 12)

        #expect(ledger.firedKinds(on: now, now: now, calendar: gmt) == [.morningPlan])
        ledger.cancel([fired, pending], notFiredBy: now)
        #expect(ledger.entries[fired.uuidString] != nil)
        #expect(ledger.entries[pending.uuidString] == nil)

        #expect(ledger.markScored(fired)?.armID == "t480")
        #expect(ledger.markScored(fired) == nil)
        // Still counts as fired today after scoring.
        #expect(ledger.firedKinds(on: now, now: now, calendar: gmt) == [.morningPlan])

        ledger.prune(now: date(1, 12, month: 10), calendar: gmt)
        #expect(ledger.entries.isEmpty)
    }
}

// MARK: - Bandit-aware planning

@Suite("NudgeScheduler.plan — plan reminder, slip gate, bandit")
struct SmartNudgePlanTests {

    private func inputs(
        now: Date = date(28, 7),
        streak: Int = 5,
        openGoals: Int = 2,
        slipRisk: Double? = nil,
        planned: [Date: Int] = [:],
        bandit: NudgeTimingBandit? = nil,
        seed: UInt64 = 1,
        fired: Set<NudgeKind> = [],
        recapHasData: Bool = true
    ) -> NudgeScheduleInputs {
        NudgeScheduleInputs(
            now: now,
            calendar: gmt,
            dailyGoalCount: 2,
            streak: streak,
            openGoalsToday: openGoals,
            slipRisk: slipRisk,
            plannedMinutesByDay: planned,
            bandit: bandit,
            banditSeed: seed,
            firedKindsToday: fired,
            recapWeekHasData: recapHasData
        )
    }

    @Test func lowRiskDropsTheStreakNudge() {
        let low = NudgeScheduler.plan(inputs(slipRisk: 0.1))
        #expect(!low.contains { $0.kind == .streakAtRisk })
        let risky = NudgeScheduler.plan(inputs(slipRisk: 0.45))
        #expect(risky.first { $0.kind == .streakAtRisk }?.fireDate == date(28, 20))
    }

    @Test func eveningPlanGetsAReminder45MinutesBefore() {
        // 6 PM gym plan, no streak yet: the reminder still goes out, as the evening nudge.
        let planned = NudgeScheduler.plan(inputs(streak: 0, slipRisk: 0.05, planned: [date(28, 0): 18 * 60]))
        let reminder = planned.first { $0.kind == .streakAtRisk }
        #expect(reminder?.fireDate == date(28, 17, 15))
        #expect(reminder?.isPlanReminder == true)
    }

    @Test func morningPlanGetsAMorningReminder() {
        let planned = NudgeScheduler.plan(inputs(now: date(28, 5), streak: 0, planned: [date(28, 0): 7 * 60]))
        let reminder = planned.first { $0.kind == .morningPlan }
        #expect(reminder?.fireDate == date(28, 6, 15))
        #expect(reminder?.armID == "plan")
    }

    @Test func aKindThatFiredTodayIsNotPlannedAgain() {
        let planned = NudgeScheduler.plan(inputs(fired: [.streakAtRisk, .morningPlan]))
        #expect(!planned.contains { $0.kind == .streakAtRisk })
        // The morning plan rolls to tomorrow instead.
        #expect(planned.first { $0.kind == .morningPlan }.map { gmt.component(.day, from: $0.fireDate) } == 29)
    }

    @Test func emptyWeekSkipsTheRecapNudge() {
        #expect(!NudgeScheduler.plan(inputs(recapHasData: false)).contains { $0.kind == .weeklyRecap })
        #expect(NudgeScheduler.plan(inputs(recapHasData: true)).contains { $0.kind == .weeklyRecap })
    }

    @Test func banditPicksOneOfTheArmsAndIsStableForTheDay() {
        let bandit = NudgeTimingBandit()
        let first = NudgeScheduler.plan(inputs(bandit: bandit, seed: 12_345))
        let again = NudgeScheduler.plan(inputs(now: date(28, 7, 30), bandit: bandit, seed: 12_345))
        let streakTimes = Set(NudgeScheduler.fixedArms(for: .streakAtRisk).compactMap { gmt.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: date(28)) })
        let streak = first.first { $0.kind == .streakAtRisk }
        #expect(streak.map { streakTimes.contains($0.fireDate) } == true)
        #expect(streak?.fireDate == again.first { $0.kind == .streakAtRisk }?.fireDate)
        #expect(first.filter { $0.kind == .streakAtRisk }.count == 1)
    }

    @Test func banditFollowsALearnedArm() {
        var bandit = NudgeTimingBandit()
        for _ in 0..<30 {
            bandit.record(kind: .streakAtRisk, armID: "t1080", acted: true)
            bandit.record(kind: .streakAtRisk, armID: "t1200", acted: false)
            bandit.record(kind: .streakAtRisk, armID: "t1140", acted: false)
        }
        var atSix = 0
        for seed in 1...50 {
            let planned = NudgeScheduler.plan(inputs(bandit: bandit, seed: UInt64(seed)))
            if planned.first(where: { $0.kind == .streakAtRisk })?.fireDate == date(28, 18) { atSix += 1 }
        }
        #expect(atSix > 45)
    }

    @Test func banditStillRespectsTheCap() {
        let planned = NudgeScheduler.plan(inputs(now: date(27, 7), bandit: NudgeTimingBandit(), seed: 3))
        let byDay = Dictionary(grouping: planned) { gmt.startOfDay(for: $0.fireDate) }
        #expect(byDay.values.allSatisfy { $0.count <= NudgeSender.dailyCap })
    }
}

// MARK: - Weekly recap

@Suite("WeeklyRecapBuilder")
@MainActor
struct WeeklyRecapBuilderTests {

    @Test func weeksStartOnMondayAndAreDueSundayAt18() {
        #expect(WeeklyRecapBuilder.weekStart(containing: date(30, 15), calendar: gmt) == date(28, 0))
        #expect(WeeklyRecapBuilder.weekStart(containing: date(4, 23, month: 10), calendar: gmt) == date(28, 0))
        #expect(WeeklyRecapBuilder.dueWeekStart(now: date(4, 17, 59, month: 10), calendar: gmt) == date(21, 0))
        #expect(WeeklyRecapBuilder.dueWeekStart(now: date(4, 18, month: 10), calendar: gmt) == date(28, 0))
        #expect(WeeklyRecapBuilder.dueWeekStart(now: date(6, 9, month: 10), calendar: gmt) == date(28, 0))
    }

    private func goal(_ type: GoalType, _ title: String, expected: Int, days: [Int]) -> RecapGoalInput {
        RecapGoalInput(id: UUID(), type: type, title: title, expectedDays: expected, completedDays: Set(days.map { date($0, 0) }))
    }

    @Test func summaryCountsRingsBestDayAndComparison() {
        let gym = goal(.workoutGym, "Gym", expected: 3, days: [28, 30])
        var protein = goal(.protein, "Protein", expected: 7, days: [])
        protein.completedDays = [date(28, 0), date(29, 0), date(30, 0), date(1, 0, month: 10)]
        let week = RecapWeekInputs(
            weekStart: date(28, 0),
            goals: [gym, protein],
            lockIntervals: [DateInterval(start: date(28, 7), duration: 3_600), DateInterval(start: date(28, 7, 30), duration: 3_600)],
            earnedUnlockDates: [date(28, 9), date(30, 19), date(30, 21)],
            reclaimedCloses: 4
        )
        let lastWeek = RecapWeekInputs(weekStart: date(21, 0), goals: [goal(.protein, "Protein", expected: 7, days: [21, 22])], lockIntervals: [], earnedUnlockDates: [], reclaimedCloses: 0)
        let summary = WeeklyRecapBuilder.summarize(week, previous: lastWeek, currentStreak: 3, bestStreak: 5, calendar: gmt)

        #expect(summary.goalsCompleted == 6)
        #expect(summary.goalsPlanned == 10)
        #expect(summary.earnedDays == 2)
        #expect(summary.lockedMinutes == 90)
        let gymRing = summary.rings[gym.id.uuidString] ?? -1
        #expect(abs(gymRing - 2.0 / 3.0) < 1e-9)
        #expect(summary.completionsByType == ["workout_gym": 2, "protein": 4])
        // Mon 28 and Wed 30 tie on 2 completions; Monday wins the tie.
        #expect(summary.bestWeekday == 2)
        #expect(summary.vsLastWeek?.goalsCompletedDelta == 4)
        #expect(summary.bestStreak == 5)
        #expect(summary.hasData)

        let stats = WeeklyRecapBuilder.stats(for: summary, calendar: gmt)
        #expect(stats.goalsCompleted == 6)
        #expect(stats.timeReclaimedMinutes == 90)
        #expect(stats.bestDay == gmt.weekdaySymbols[1])
    }

    @Test func anEmptyWeekHasNoData() {
        let empty = RecapWeekInputs(weekStart: date(28, 0), goals: [goal(.protein, "Protein", expected: 7, days: [])], lockIntervals: [], earnedUnlockDates: [], reclaimedCloses: 0)
        #expect(!WeeklyRecapBuilder.summarize(empty, previous: nil, currentStreak: 0, bestStreak: 0, calendar: gmt).hasData)
    }

    @Test func coachLinesAreShortAndCleanInEveryVoice() {
        let gym = goal(.workoutGym, "Gym", expected: 3, days: [28])
        let week = RecapWeekInputs(weekStart: date(28, 0), goals: [gym], lockIntervals: [], earnedUnlockDates: [date(28, 9)], reclaimedCloses: 0)
        let summary = WeeklyRecapBuilder.summarize(week, previous: nil, currentStreak: 1, bestStreak: 1, calendar: gmt)
        for voice in CoachVoice.allCases {
            let unplanned = WeeklyRecapBuilder.coachLine(for: summary, goals: [gym], voice: voice, plannedGoalTypes: [], calendar: gmt)
            let planned = WeeklyRecapBuilder.coachLine(for: summary, goals: [gym], voice: voice, plannedGoalTypes: [.workoutGym], calendar: gmt)
            for line in [unplanned, planned] {
                #expect(line.split(separator: " ").count <= 60)
                #expect(!line.contains("§"))
                #expect(!line.lowercased().contains("miss"))
            }
            #expect(unplanned.contains("Gym"))
            #expect(planned.contains(gmt.weekdaySymbols[1]))
        }
    }

    @Test func buildsTheRecapRowFromLocalData() throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let defaults = try freshDefaults()
        let context = ModelContext(container)
        let user = User(coachVoice: .data)
        context.insert(user)
        let creatine = Goal(type: .creatine, title: "Creatine", cadence: "daily", verificationTier: .b, createdAt: date(20), user: user)
        context.insert(creatine)
        for day in [28, 29, 30] {
            context.insert(GoalEvent(ts: date(day, 9), kind: .complete, source: .nfc, verified: true, user: user, goal: creatine))
        }
        context.insert(LockSession(userID: user.id, startedAt: date(29, 7), endedAt: date(29, 9), mode: .full, unlockKind: .earned))
        try context.save()

        let builder = WeeklyRecapBuilder(modelContainer: container, calendar: gmt, defaults: defaults)
        // Saturday: not due for this week yet, and last week was empty → no row.
        #expect(builder.buildIfDue(now: date(3, 12, month: 10)) == nil)
        #expect(builder.hasData(weekContaining: date(4, 19, month: 10), now: date(3, 12, month: 10)))

        let summary = try #require(builder.buildIfDue(now: date(4, 18, 30, month: 10)))
        #expect(summary.goalsCompleted == 3)
        #expect(summary.earnedDays == 1)
        #expect(summary.lockedMinutes == 120)

        let recaps = try ModelContext(container).fetch(FetchDescriptor<Recap>())
        #expect(recaps.count == 1)
        #expect(recaps.first?.stats.goalsCompleted == 3)
        #expect(recaps.first?.text?.isEmpty == false)
        #expect(builder.summary(forWeekStart: date(28, 0))?.goalsCompleted == 3)

        // Running again updates in place rather than adding a second row.
        builder.buildIfDue(now: date(4, 20, month: 10))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Recap>()).count == 1)
    }
}

// MARK: - Reclaimed opens + shield copy

@Suite("ReclaimedOpens + one sec-style shield copy")
struct ReclaimedShieldTests {

    @Test func countsClosesPerDayAndWeek() throws {
        let defaults = try freshDefaults()
        ReclaimedOpens.recordClose(at: date(28, 10), calendar: gmt, defaults: defaults)
        ReclaimedOpens.recordClose(at: date(28, 22), calendar: gmt, defaults: defaults)
        ReclaimedOpens.recordClose(at: date(30, 8), calendar: gmt, defaults: defaults)
        ReclaimedOpens.recordClose(at: date(10, 8), calendar: gmt, defaults: defaults)
        #expect(ReclaimedOpens.count(from: date(28, 0), to: date(29, 0), calendar: gmt, defaults: defaults) == 2)
        #expect(ReclaimedOpens.countThisWeek(now: date(30, 23), calendar: gmt, defaults: defaults) == 3)
    }

    private func context(reclaimed: Int = 0) -> ShieldCopy.ShieldContext {
        ShieldCopy.ShieldContext(
            voice: .chill, shieldedName: "TikTok", currentStreak: 2, goalsRemaining: 2,
            mode: .full, earnedMinutesRemainingToday: 0, earnedMinutesMirrorIsForToday: false,
            reclaimedThisWeek: reclaimed
        )
    }

    @Test func coachLineRotatesPerViewAndKeepsTheGoalsLeftTitle() {
        let lines = Set((0..<4).map { ShieldCopy.content(for: context(), rotation: $0).subtitle })
        #expect(lines.count == 4)
        #expect(ShieldCopy.content(for: context(), rotation: 9).title.contains("2 goals"))
    }

    @Test func reclaimedLineJoinsTheRotationFromThreeCloses() {
        let few = (0..<5).map { ShieldCopy.content(for: context(reclaimed: 2), rotation: $0).subtitle }
        let many = (0..<5).map { ShieldCopy.content(for: context(reclaimed: 6), rotation: $0).subtitle }
        #expect(!few.contains { $0.contains("6") })
        #expect(many.contains { $0.contains("6 closes") })
    }

    @Test func timeBankButtonLandsOnTheLockTabAndNamesTheWayOut() {
        #expect(ShieldCopy.Buttons.closeApp == "Close app")
        #expect(ShieldCopy.Buttons.useTimeBank == "Time Bank or emergency")
        for voice in CoachVoice.allCases {
            let note = ShieldCopy.timeBankNotification(voice: voice, mode: .earn, earnedMinutes: 12)
            #expect(note.deepLink == ShieldCopy.DeepLink.emergency)
            #expect(note.body.contains("Emergency unlock"))
            #expect(note.title.contains("12"))
        }
    }
}
