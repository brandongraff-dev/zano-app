// Core/Sources/Core/LockEngine/GoalCompletionCoordinator.swift
//
// The step that turns "a goal was logged" into "apps unlock": docs/spec.md §2 (LOCK → DO THE GOAL
// → VERIFIED → UNLOCK + STREAK), §5.2 (Earn Mode deposits Time Bank minutes per verified goal),
// §5.5 (Plan B = half credit in Earn Mode), §5.7 (duel points per verified goal), §8 rule 11
// (streak starts at Day 1 on the first earned unlock). Wave 0 of docs/design/buildout-plan.md.
//
// Every intent/verifier that writes a `GoalEvent` calls `goalEventRecorded(goalID:)` right after
// saving it. The coordinator then:
//   1. Rolls the day's logged amount up into exactly one verified `.complete` event once the target
//      is reached (protein/water log `.verify` + amount; the engine only accepts completions).
//   2. Runs the per-completion rewards once per goal per day, tracked with a marker in the
//      completion event's `meta`: a duel point, and (Earn Mode lock only) Time Bank minutes.
//   3. If a lock is active and every required goal is verified, ends it as `.earned` through
//      `LockEngineManager`, then records the earned unlock with `StreakEngine`.
//
// Everything is idempotent: calling it twice, or from two processes, never adds a second
// completion, a second deposit, or a second unlock.
//
// The unlock celebration needs no extra hook: `LockEngineManager.endLock` sets
// `lastUnlockedSessionID`, which `App/ZANO/ContentView.swift` already observes and hands to
// `AppRouter.handleUnlock` (and Today presents its own when the lock drops).
//
// Emergency unlock is untouched: this file never ends a lock any other way than `.earned`, and
// never looks at a lock that has already ended.

import Foundation
import SwiftData
import os

/// Single entry point from "a `GoalEvent` was saved" to completion, rewards, and earned unlock.
///
/// `@MainActor` like `LockEngineManager`, `TimeBankEngine` and `StreakEngine`, which it drives, and
/// like the App Intents' `perform()` that call it. Callers off the main actor (the steps and gym
/// verifiers' actors) pass only a `UUID` across. Each call reads through a fresh `ModelContext`, so
/// it sees whatever the caller's own context just saved.
@MainActor
public final class GoalCompletionCoordinator {
    public static let shared = GoalCompletionCoordinator()

    /// The side effects the coordinator triggers, injectable for tests (the live lock engine
    /// touches ManagedSettings, which a test bundle can't).
    struct Effects {
        /// `LockEngineManager.evaluateUnlockEligibility` — the engine's own check, which also
        /// refreshes the shield's "goals left" mirror. Both checks must agree before ending a lock.
        var lockEngineAgreesUnlockIsEarned: @MainActor (UUID) async -> Bool
        var endLockAsEarned: @MainActor (UUID) async throws -> Void
        var depositMinutes: @MainActor (Int, Date) async throws -> Void
        var recordEarnedUnlock: @MainActor (Date) async -> Void
        var applyDuelPoint: @MainActor (UUID, Date) async -> Void
        /// `VariableReward.roll` — the 1-in-~6 surprise on an earned unlock (spec §8 rule 4).
        /// Defaulted to a no-op so existing test harnesses keep compiling; `.live` wires it.
        var rollVariableReward: @MainActor (UUID, Date) async -> Void = { _, _ in }

        static var live: Effects {
            Effects(
                lockEngineAgreesUnlockIsEarned: { sessionID in
                    await LockEngineManager.shared.evaluateUnlockEligibility(sessionID: sessionID)
                },
                endLockAsEarned: { sessionID in
                    try await LockEngineManager.shared.endLock(sessionID: sessionID, unlockKind: .earned)
                },
                depositMinutes: { minutes, date in
                    try await TimeBankEngine.shared.deposit(minutes: minutes, for: date)
                },
                recordEarnedUnlock: { date in
                    await StreakEngine.shared.recordEarnedUnlock(on: date)
                    // Advances a running comeback challenge (no-op when none is running).
                    await ComebackMode.shared.recordDayCompleted(on: date)
                },
                applyDuelPoint: { userID, date in
                    // Local-only: updates duel rows and queues an outbox sync. Swallows its own errors.
                    await DuelManager.shared.applyVerifiedGoalEvent(userID: userID, verifiedAt: date)
                },
                rollVariableReward: { sessionID, date in
                    // Deterministic per session and idempotent (ledger-backed); never throws.
                    _ = VariableReward.shared.roll(sessionID: sessionID, at: date)
                }
            )
        }
    }

    /// `meta` key marking the completion event whose rewards (duel point, Earn Mode minutes) were
    /// already paid out. Local bookkeeping only.
    static let processedMetaKey = "completionProcessed"
    /// `meta` key marking a `.complete` this coordinator inserted from the day's logged amount.
    public static let rollupMetaKey = "rollup"

    private let modelContainer: ModelContainer
    private let effects: Effects
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GoalCompletionCoordinator")

    init(modelContainer: ModelContainer = .appGroup, effects: Effects = .live) {
        self.modelContainer = modelContainer
        self.effects = effects
    }

    // MARK: - Entry point

    /// Call right after saving any `GoalEvent` for `goalID`. Never throws: a failure here is logged
    /// and must never fail the log the user just made.
    public func goalEventRecorded(goalID: UUID, at now: Date = .now) async {
        let context = ModelContext(modelContainer)
        guard let goal = fetchGoal(id: goalID, in: context) else { return }
        let activeLock = fetchActiveLock(in: context)

        // Reconcile the logged goal plus every goal the active lock needs, so a goal whose logs
        // landed before this coordinator ran (or in another process) still counts.
        var goals = [goal]
        for requiredID in activeLock?.requiredGoalIDs ?? [] where requiredID != goalID {
            if let required = fetchGoal(id: requiredID, in: context) { goals.append(required) }
        }

        // No `await` between these fetches and the save: two calls can't interleave here, so the
        // rollup and the processed marker are written at most once.
        let newCompletions = goals.compactMap { reconcile($0, in: context, now: now) }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                logger.error("Could not save goal completion for \(goalID.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                return
            }
        }

        let isEarnMode = activeLock?.mode == .earn
        for completion in newCompletions {
            await payRewards(for: completion, earnMode: isEarnMode, at: now)
        }

        guard let activeLock else { return }
        let sessionID = activeLock.id
        let allRequiredVerified = areAllRequiredGoalsVerified(activeLock, in: context)
        let engineAgrees = await effects.lockEngineAgreesUnlockIsEarned(sessionID)
        guard allRequiredVerified, engineAgrees else { return }

        do {
            try await effects.endLockAsEarned(sessionID)
        } catch {
            // Most likely another call (or process) ended it first. Nothing to celebrate twice.
            logger.notice("Earned unlock skipped for \(sessionID.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        await effects.recordEarnedUnlock(now)
        // Only reached once per lock: `endLockAsEarned` throws for a lock that already ended.
        await effects.rollVariableReward(sessionID, now)
        logger.notice("Lock \(sessionID.uuidString, privacy: .public) ended as earned.")
    }

    // MARK: - Per-goal reconcile

    private struct NewCompletion {
        let goalID: UUID
        let goalType: GoalType
        let userID: UUID?
        let isPlanB: Bool
    }

    /// Inserts the day's `.complete` if the logged amount reached the target, and marks today's
    /// completion as processed. Returns a value only the first time a completion is processed.
    private func reconcile(_ goal: Goal, in context: ModelContext, now: Date) -> NewCompletion? {
        let events = todaysEvents(goalID: goal.id, in: context, now: now)

        var completion = events
            .filter { GoalDayProgress.isVerifiedCompletion($0) && $0.kind != .freeze }
            .min { $0.ts < $1.ts }

        if !events.contains(where: GoalDayProgress.isVerifiedCompletion) {
            let plannedValue = todaysPlannedValue(goalID: goal.id, in: context, now: now)
            let progress = GoalDayProgress(goal: goal, todaysEvents: events, plannedValue: plannedValue)
            guard progress.isComplete else { return nil }

            var meta: [String: JSONValue] = [
                Self.rollupMetaKey: .bool(true),
                "loggedAmount": .number(progress.loggedAmount),
            ]
            if let target = plannedValue ?? goal.targetValue { meta["target"] = .number(target) }
            let latestSource = events.filter(\.verified).max { $0.ts < $1.ts }?.source ?? .manual
            // `value: nil` so the amount isn't counted twice by `GoalDayProgress`.
            let rollup = GoalEvent(
                ts: now,
                kind: .complete,
                value: nil,
                source: latestSource,
                verified: true,
                meta: .object(meta),
                user: goal.user,
                goal: goal
            )
            context.insert(rollup)
            completion = rollup
        }

        guard let completion, !Self.isProcessed(completion) else { return nil }
        Self.markProcessed(completion)
        return NewCompletion(
            goalID: goal.id,
            goalType: goal.type,
            userID: goal.user?.id ?? completion.user?.id,
            isPlanB: completion.kind == .planB
        )
    }

    private func payRewards(for completion: NewCompletion, earnMode: Bool, at now: Date) async {
        // A durable per-goal-per-day ledger, outside the event row: Today's undo can delete a
        // rollup `.complete` (and its processed marker), and a later log would otherwise pay the
        // duel point and Time Bank minutes a second time.
        guard RewardLedger.claim(goalID: completion.goalID, on: now) else { return }
        if let userID = completion.userID {
            await effects.applyDuelPoint(userID, now)
        }
        guard earnMode, let fullMinutes = TimeBankEarnRates.minutes(for: completion.goalType) else { return }
        let minutes = completion.isPlanB ? PlanB.earnModeMinutes(forFullMinutes: fullMinutes) : fullMinutes
        guard minutes > 0 else { return }
        do {
            try await effects.depositMinutes(minutes, now)
        } catch {
            logger.error("Time Bank deposit failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Lock eligibility

    /// Same rule as `LockEngineManager.evaluateUnlockEligibility`: every required goal has a
    /// verified completion since the start of the day the lock began; an empty list never earns.
    private func areAllRequiredGoalsVerified(_ session: LockSession, in context: ModelContext) -> Bool {
        guard session.isActive, !session.requiredGoalIDs.isEmpty else { return false }
        let startOfDay = Calendar.current.startOfDay(for: session.startedAt)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= startOfDay }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        let verifiedGoalIDs = Set(events.filter(GoalDayProgress.isVerifiedCompletion).compactMap { $0.goal?.id })
        return session.requiredGoalIDs.allSatisfy { verifiedGoalIDs.contains($0) }
    }

    // MARK: - Meta marker

    private static func isProcessed(_ event: GoalEvent) -> Bool {
        guard case .object(let fields) = event.meta else { return false }
        return fields[processedMetaKey] == .bool(true)
    }

    private static func markProcessed(_ event: GoalEvent) {
        var fields: [String: JSONValue] = [:]
        if case .object(let existing) = event.meta { fields = existing }
        fields[processedMetaKey] = .bool(true)
        event.meta = .object(fields)
    }

    // MARK: - SwiftData
    //
    // Only `Bool`/`Date`/`UUID` comparisons go inside `#Predicate`; the goal relationship and enum
    // comparisons are filtered in Swift, the same split `LockEngineManager.isGoalVerified` uses.

    private func fetchGoal(id: UUID, in context: ModelContext) -> Goal? {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchActiveLock(in context: ModelContext) -> LockSession? {
        let descriptor = FetchDescriptor<LockSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first { $0.isActive }
    }

    private func todaysEvents(goalID: UUID, in context: ModelContext, now: Date) -> [GoalEvent] {
        let (start, end) = dayBounds(for: now)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= start && $0.ts < end }
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.goal?.id == goalID }
    }

    private func todaysPlannedValue(goalID: UUID, in context: ModelContext, now: Date) -> Double? {
        let (start, end) = dayBounds(for: now)
        let descriptor = FetchDescriptor<DailyPlan>(
            predicate: #Predicate<DailyPlan> { $0.date >= start && $0.date < end }
        )
        return ((try? context.fetch(descriptor)) ?? []).first { $0.goal?.id == goalID }?.plannedValue
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}


/// Remembers which goal-days have already paid rewards, in the App Group defaults so the app,
/// widgets and intents share it. Keys older than a week are pruned on each claim.
enum RewardLedger {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let key = "zano.rewardLedger.v1"

    /// `true` the first time for this goal and calendar day, `false` after.
    @MainActor
    static func claim(goalID: UUID, on date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        let entry = "\(goalID.uuidString)|\(Int(day.timeIntervalSince1970))"
        var ledger = defaults.stringArray(forKey: key) ?? []
        guard !ledger.contains(entry) else { return false }
        let cutoff = day.addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        ledger = ledger.filter { item in
            guard let stamp = item.split(separator: "|").last, let t = Double(stamp) else { return false }
            return t >= cutoff
        }
        ledger.append(entry)
        defaults.set(ledger, forKey: key)
        return true
    }
}
