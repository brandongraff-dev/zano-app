// Core/Tests/CoreTests/GoalCompletionTests.swift
//
// Tests Core/Sources/Core/LockEngine/GoalCompletionCoordinator.swift and GoalDayProgress.swift
// (docs/spec.md §2 core loop, §5.2 Earn Mode, §5.5 Plan B half credit; Wave 0 of
// docs/design/buildout-plan.md).
//
// Every test builds its own in-memory store. The live lock engine is replaced by a stub that ends
// the `LockSession` row directly: the real `LockEngineManager.endLock` clears a
// `ManagedSettingsStore`, which a test bundle can't safely touch (same line LockEngineTests.swift
// draws). The Time Bank is the real `TimeBankEngine` on the same in-memory store. Dates are a fixed
// reference day, never `.now`.

import Foundation
import SwiftData
import Testing
@testable import Core

// MARK: - Harness

@MainActor
private final class CoordinatorSpy {
    var endedSessionIDs: [UUID] = []
    var earnedUnlockDates: [Date] = []
    var duelPoints = 0
}

@MainActor
private struct Harness {
    static let referenceDay = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)
    )!

    let container: ModelContainer
    let context: ModelContext
    let user: User
    let spy: CoordinatorSpy
    let timeBank: TimeBankEngine
    let coordinator: GoalCompletionCoordinator

    init(lockEngineAgrees: Bool = true) throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        try context.save()

        let spy = CoordinatorSpy()
        let timeBank = TimeBankEngine(modelContainer: container)
        let effects = GoalCompletionCoordinator.Effects(
            lockEngineAgreesUnlockIsEarned: { _ in lockEngineAgrees },
            endLockAsEarned: { sessionID in
                let endContext = ModelContext(container)
                var descriptor = FetchDescriptor<LockSession>(predicate: #Predicate { $0.id == sessionID })
                descriptor.fetchLimit = 1
                guard let session = try endContext.fetch(descriptor).first, session.isActive else {
                    throw LockEngineError.sessionAlreadyEnded(sessionID)
                }
                session.endedAt = Harness.referenceDay
                session.unlockKind = .earned
                try endContext.save()
                spy.endedSessionIDs.append(sessionID)
            },
            depositMinutes: { minutes, date in
                try await timeBank.deposit(minutes: minutes, for: date)
            },
            recordEarnedUnlock: { date in
                spy.earnedUnlockDates.append(date)
            },
            applyDuelPoint: { _, _ in
                spy.duelPoints += 1
            }
        )

        self.container = container
        self.context = context
        self.user = user
        self.spy = spy
        self.timeBank = timeBank
        self.coordinator = GoalCompletionCoordinator(modelContainer: container, effects: effects)
    }

    static func at(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: referenceDay)!
    }

    func addGoal(_ type: GoalType, target: Double?) throws -> Goal {
        let goal = Goal(type: type, title: type.rawValue, targetValue: target, verificationTier: .b, user: user)
        context.insert(goal)
        try context.save()
        return goal
    }

    func log(
        _ goal: Goal,
        amount: Double?,
        kind: GoalEventKind = .verify,
        verified: Bool = true,
        hour: Int = 9
    ) throws {
        context.insert(GoalEvent(
            ts: Self.at(hour: hour),
            kind: kind,
            value: amount,
            source: .manual,
            verified: verified,
            user: user,
            goal: goal
        ))
        try context.save()
    }

    func startLock(requiring goals: [Goal], mode: LockMode) throws -> UUID {
        let session = LockSession(
            userID: user.id,
            startedAt: Self.at(hour: 7),
            trigger: .manual,
            mode: mode,
            requiredGoalIDs: goals.map(\.id)
        )
        context.insert(session)
        try context.save()
        return session.id
    }

    func recorded(_ goal: Goal) async {
        await coordinator.goalEventRecorded(goalID: goal.id, at: Self.referenceDay)
    }

    /// Reads through a fresh context so it sees what the coordinator's own context saved.
    func completionCount(for goal: Goal) throws -> Int {
        let goalID = goal.id
        return try ModelContext(container).fetch(FetchDescriptor<GoalEvent>())
            .filter { $0.goal?.id == goalID && $0.kind == .complete }
            .count
    }

    func session(_ id: UUID) throws -> LockSession? {
        var descriptor = FetchDescriptor<LockSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try ModelContext(container).fetch(descriptor).first
    }

    func bankMinutes() async -> Int {
        await timeBank.remainingMinutes(for: Self.referenceDay)
    }
}

// MARK: - Rolling logged amounts into one completion

@Suite("GoalCompletionCoordinator — logged amounts become one .complete")
@MainActor
struct GoalCompletionRollupTests {
    @Test("protein logs summing to the target create exactly one .complete")
    func proteinLogsReachingTargetCreateOneCompletion() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 150)

        try h.log(protein, amount: 50)
        await h.recorded(protein)
        try h.log(protein, amount: 50)
        await h.recorded(protein)
        #expect(try h.completionCount(for: protein) == 0)

        try h.log(protein, amount: 50)
        await h.recorded(protein)
        #expect(try h.completionCount(for: protein) == 1)
    }

    @Test("repeated calls after the target never add a second .complete or a second duel point")
    func repeatedCallsAreIdempotent() async throws {
        let h = try Harness()
        let water = try h.addGoal(.water, target: 1500)
        try h.log(water, amount: 1500)

        await h.recorded(water)
        await h.recorded(water)
        try h.log(water, amount: 750, hour: 10)
        await h.recorded(water)

        #expect(try h.completionCount(for: water) == 1)
        #expect(h.spy.duelPoints == 1)
    }

    @Test("unverified logs (a duplicate NFC tap) don't count toward the target")
    func unverifiedLogsDoNotCount() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 100)
        try h.log(protein, amount: 60)
        try h.log(protein, amount: 60, verified: false)

        await h.recorded(protein)

        #expect(try h.completionCount(for: protein) == 0)
    }

    @Test("today's DailyPlan target overrides the goal's own target")
    func dailyPlanOverridesGoalTarget() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 150)
        h.context.insert(DailyPlan(
            date: Calendar.current.startOfDay(for: Harness.referenceDay),
            plannedValue: 80,
            user: h.user,
            goal: protein
        ))
        try h.context.save()

        try h.log(protein, amount: 80)
        await h.recorded(protein)

        #expect(try h.completionCount(for: protein) == 1)
    }

    @Test("a verified .verify on a goal with no numeric target completes it")
    func binaryVerifyCompletes() async throws {
        let h = try Harness()
        let mealPrep = try h.addGoal(.mealPrep, target: nil)
        try h.log(mealPrep, amount: 4)

        await h.recorded(mealPrep)

        #expect(try h.completionCount(for: mealPrep) == 1)
    }

    @Test("a missed focus session's minutes never add to the logged amount")
    func missesDoNotAddToAmount() {
        let events = [
            GoalEvent(ts: Harness.at(hour: 9), kind: .miss, value: 40, source: .timer, verified: false),
            GoalEvent(ts: Harness.at(hour: 10), kind: .miss, value: 40, source: .timer, verified: true),
        ]
        let progress = GoalDayProgress(targetValue: 50, unit: "min", events: events)
        #expect(progress.loggedAmount == 0)
        #expect(!progress.isComplete)
    }
}

// MARK: - Earned unlock

@Suite("GoalCompletionCoordinator — earned unlock")
@MainActor
struct GoalCompletionUnlockTests {
    @Test("a lock with 2 required goals ends as earned only after both complete, exactly once")
    func twoRequiredGoalsEndLockOnlyWhenBothDone() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 100)
        let creatine = try h.addGoal(.creatine, target: nil)
        let lockID = try h.startLock(requiring: [protein, creatine], mode: .full)

        try h.log(protein, amount: 60)
        await h.recorded(protein)
        #expect(h.spy.endedSessionIDs.isEmpty)

        try h.log(creatine, amount: 1, kind: .complete)
        await h.recorded(creatine)
        #expect(h.spy.endedSessionIDs.isEmpty)
        #expect(try h.session(lockID)?.isActive == true)

        try h.log(protein, amount: 40, hour: 10)
        await h.recorded(protein)
        #expect(h.spy.endedSessionIDs == [lockID])
        #expect(try h.session(lockID)?.unlockKind == .earned)
        #expect(h.spy.earnedUnlockDates.count == 1)

        await h.recorded(protein)
        await h.recorded(creatine)
        #expect(h.spy.endedSessionIDs == [lockID])
        #expect(h.spy.earnedUnlockDates.count == 1)
    }

    @Test("a required goal whose logs landed before the lock is still rolled up")
    func earlierLogsForRequiredGoalsCount() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 100)
        let creatine = try h.addGoal(.creatine, target: nil)
        try h.log(protein, amount: 100, hour: 8)
        let lockID = try h.startLock(requiring: [protein, creatine], mode: .full)

        try h.log(creatine, amount: 1, kind: .complete)
        await h.recorded(creatine)

        #expect(try h.completionCount(for: protein) == 1)
        #expect(h.spy.endedSessionIDs == [lockID])
    }

    @Test("the lock stays on when the lock engine's own check disagrees")
    func lockEngineMustAgree() async throws {
        let h = try Harness(lockEngineAgrees: false)
        let protein = try h.addGoal(.protein, target: 100)
        let lockID = try h.startLock(requiring: [protein], mode: .full)

        try h.log(protein, amount: 100)
        await h.recorded(protein)

        #expect(h.spy.endedSessionIDs.isEmpty)
        #expect(try h.session(lockID)?.isActive == true)
    }

    @Test("an emergency unlock is never re-ended or turned into an earned unlock")
    func emergencyUnlockIsUnaffected() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 100)
        let lockID = try h.startLock(requiring: [protein], mode: .full)
        // What LockEngineManager.emergencyUnlock leaves behind: the row ended as `.emergency`.
        let context = ModelContext(h.container)
        var descriptor = FetchDescriptor<LockSession>(predicate: #Predicate { $0.id == lockID })
        descriptor.fetchLimit = 1
        let row = try #require(try context.fetch(descriptor).first)
        row.endedAt = Harness.at(hour: 8)
        row.unlockKind = .emergency
        try context.save()

        try h.log(protein, amount: 100)
        await h.recorded(protein)

        #expect(h.spy.endedSessionIDs.isEmpty)
        #expect(h.spy.earnedUnlockDates.isEmpty)
        #expect(try h.session(lockID)?.unlockKind == .emergency)
        #expect(try h.completionCount(for: protein) == 1)
    }
}

// MARK: - Earn Mode (spec §5.2)

@Suite("GoalCompletionCoordinator — Earn Mode Time Bank deposits")
@MainActor
struct GoalCompletionEarnModeTests {
    @Test("each newly completed goal deposits its earn-rate minutes once, then the lock ends as earned")
    func earnModeDepositsOncePerGoal() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 100)
        let focus = try h.addGoal(.focusSession, target: 25)
        let lockID = try h.startLock(requiring: [protein, focus], mode: .earn)

        try h.log(protein, amount: 100)
        await h.recorded(protein)
        await h.recorded(protein)
        #expect(await h.bankMinutes() == TimeBankEarnRates.proteinMinutes)
        #expect(h.spy.endedSessionIDs.isEmpty)

        try h.log(focus, amount: 25, kind: .complete, hour: 10)
        await h.recorded(focus)
        #expect(await h.bankMinutes() == TimeBankEarnRates.proteinMinutes + TimeBankEarnRates.focusBlockMinutes)
        #expect(h.spy.endedSessionIDs == [lockID])
    }

    @Test("a Plan B completion deposits half credit")
    func planBDepositsHalfCredit() async throws {
        let h = try Harness()
        let gym = try h.addGoal(.workoutGym, target: nil)
        _ = try h.startLock(requiring: [gym], mode: .earn)

        try h.log(gym, amount: nil, kind: .planB)
        await h.recorded(gym)

        #expect(await h.bankMinutes() == PlanB.earnModeMinutes(forFullMinutes: TimeBankEarnRates.gymSessionMinutes))
    }

    @Test("a full-mode lock deposits nothing")
    func fullModeDepositsNothing() async throws {
        let h = try Harness()
        let protein = try h.addGoal(.protein, target: 100)
        _ = try h.startLock(requiring: [protein], mode: .full)

        try h.log(protein, amount: 100)
        await h.recorded(protein)

        #expect(await h.bankMinutes() == 0)
    }
}
