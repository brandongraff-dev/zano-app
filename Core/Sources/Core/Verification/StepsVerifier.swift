// Core/Sources/Core/Verification/StepsVerifier.swift
//
// docs/spec.md §3 "Goal Catalog & Verification" — "Steps" row (Tier A):
//   How it's verified: "HealthKit step count vs target"
//   Anti-cheat: "None needed"
// This is the simplest Tier A verifier in the catalog by design — spec explicitly says no
// anti-cheat layer is required (unlike Workout (gym)'s dwell/motion/HR stack in
// `GymVerifier.swift`), so this file is a single trusted signal: today's HealthKit step count
// compared against the goal's (adaptive) target.
//
// docs/spec.md §13 Data Model: mirrors `goals.target_value`/`goals.unit` (`GoalType.steps`,
// `Models/Goal.swift`) and writes rows into `goal_events` (`Models/GoalEvent.swift`) exactly the
// way every other Tier A verifier in this folder does.
//
// No fixed CONTRACTS block named `StepsVerifier` exists elsewhere in this codebase as of this
// file's authorship (checked: no other file references the type by name). The public shape below
// is this session's own design, deliberately mirroring `GymVerifier.swift`'s established
// two-piece shape (a stateless `Sendable` forwarding class + a private `actor` owning every
// mutable field and every HealthKit call) since that is the most directly analogous Tier A
// verifier already on disk, and `FocusSessionVerifier.swift`'s convention of writing its own
// `GoalEvent` rows rather than leaving that to a caller.
//
// Concurrency: `StepsVerifier` is a `final class: Sendable` with no mutable stored state of its
// own (only a `let` reference to the actor below), matching `GymVerifier`'s reasoning verbatim —
// see that file's header comment. The actual mutable state (per-goal `HKObserverQuery` handles,
// the shared `HKHealthStore`, and the one `ModelContext` this file reads/writes through) lives on
// `StepsObserverState`, a private `actor`.

import Foundation
import HealthKit
import SwiftData
import os

/// Errors `StepsVerifier` throws itself, as opposed to errors bubbled up from HealthKit/SwiftData.
public enum StepsVerifierError: Sendable, Equatable, LocalizedError {
    /// HealthKit is unavailable on this device (e.g. no Health app data store), or the
    /// `.stepCount` quantity type could not be constructed — the latter should never actually
    /// happen (`.stepCount` is one of HealthKit's oldest, always-present identifiers), but this
    /// mirrors `GymVerifier`'s own defensive `guard let heartRateType = ...` rather than
    /// force-unwrapping.
    case healthDataUnavailable

    /// The call site passed a `goalID` with no matching `Goal` row in the shared App Group store.
    case goalNotFound(UUID)

    /// The call site passed a `goalID` whose `Goal.type` is not `.steps` — this verifier only
    /// ever compares HealthKit step counts, so pointing it at e.g. a protein goal is a caller
    /// bug worth failing loudly on rather than silently querying steps for the wrong goal.
    case wrongGoalType(GoalType)

    /// The goal has no usable target: today's `DailyPlan.plannedValue` (via
    /// `AdaptiveGoalEngine.dailyPlan(for:on:)`) is `nil` *and* `Goal.targetValue` is `nil`. There
    /// is nothing to compare today's step count against.
    case missingTargetValue(UUID)

    public var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "HealthKit step data is unavailable on this device, or the app has not been granted read access to step count."
        case .goalNotFound(let goalID):
            "No Goal with id \(goalID) exists locally — cannot verify steps for it."
        case .wrongGoalType(let type):
            "StepsVerifier only verifies GoalType.steps goals (got \(type.rawValue))."
        case .missingTargetValue(let goalID):
            "Goal \(goalID) has no target step count (today's DailyPlan and Goal.targetValue are both nil) — nothing to verify against."
        }
    }
}

/// Verifies the Steps goal (docs/spec.md §3, Tier A) by comparing today's HealthKit cumulative
/// step count against the goal's effective daily target, and logs a `.complete` `GoalEvent`
/// (docs/spec.md §13) the moment the target is met.
///
/// Two ways to trigger a check:
/// 1. **On demand** — `checkToday(goalID:)`, e.g. from a "refresh" pull, the Today screen
///    appearing, or an App Intent.
/// 2. **In the background** — `startObserving(goalID:)` arms an `HKObserverQuery` (with
///    background delivery enabled) that re-runs `checkToday` every time HealthKit sees new step
///    samples, so the shield can unlock without the user having to reopen the app first
///    (CLAUDE.md: "Unlock must be instant and offline").
///
/// Unlike `GymVerifier` (which documents that it deliberately does *not* write `GoalEvent` rows
/// itself, leaving that to a caller), this file follows `FocusSessionVerifier`'s convention and
/// writes its own `.complete` row directly — there is no meaningful intermediate state for a
/// step count the way there is for a gym dwell session, so there is nothing for a caller to add.
///
/// **Never writes `.miss`.** A single check that hasn't hit the target yet does not mean the day
/// is over — steps accumulate all day, so "not yet at target" and "missed today's goal" are not
/// the same thing at 2pm. Per-day miss reconciliation is `StreakEngine`'s job
/// (`StreakEngine.recordMiss(on:)`, called by whatever end-of-day job owns that sweep across every
/// goal type — out of this file's scope, same as it is out of every other Tier A verifier's scope
/// in this folder); this file only ever asserts "the target was met," never "it wasn't, forever."
public final class StepsVerifier: Sendable {
    public static let shared = StepsVerifier()

    private let state: StepsObserverState

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container — mirrors `GymVerifier`'s/`FocusSessionVerifier`'s own convention;
    /// every real call site uses `.shared`.
    init(state: StepsObserverState = StepsObserverState()) {
        self.state = state
    }

    /// Requests HealthKit read access to step count. Call this once, from wherever the user turns
    /// on a Steps goal (Goal setup / onboarding — not owned by this file), before relying on
    /// `checkToday`/`startObserving` to return real data.
    ///
    /// HealthKit fundamentally cannot report back whether *read* access was granted or denied
    /// (only *share/write* status is queryable — see `GymVerifier.elevatedHeartRateDuringDwell`'s
    /// doc comment for the same Apple limitation) — this call only surfaces failures to even
    /// *present* the permission sheet (e.g. HealthKit unavailable on this device). A user who
    /// denies read access will simply see `checkToday` never verify; the app-wide emergency
    /// unlock (CLAUDE.md: "Emergency unlock must always exist on any lock-type feature") is what
    /// keeps that from ever being a trap, exactly as it is for every other Tier A goal in this
    /// folder that leans on HealthKit.
    public func requestAuthorization() async throws {
        try await state.requestAuthorization()
    }

    /// `true` while the app has never shown the HealthKit sheet for step count. HealthKit can't
    /// report whether *read* access was granted (see `requestAuthorization`), only whether the
    /// request still needs showing, so this is the best "is Health connected" signal there is.
    /// Today shows "Connect Apple Health" on a steps row while this is `true`.
    public func needsAuthorizationRequest() async -> Bool {
        await state.needsAuthorizationRequest()
    }

    /// Runs one check: today's HealthKit step count vs. the goal's effective target. If met and
    /// not already logged complete today, writes a `.complete` `GoalEvent` and returns `true`.
    /// If already logged complete today, returns `true` without writing a duplicate row
    /// (idempotent — safe to call repeatedly from a UI refresh or a background observer).
    ///
    /// - Throws: `StepsVerifierError.goalNotFound`, `.wrongGoalType`, `.missingTargetValue`, or a
    ///   `StepsVerifierError.healthDataUnavailable` / HealthKit query error.
    @discardableResult
    public func checkToday(goalID: UUID) async throws -> Bool {
        try await state.checkToday(goalID: goalID)
    }

    /// Today's raw HealthKit step count for `goalID`'s device, with no comparison against the
    /// target — a read-only convenience for a progress ring / widget, mirroring
    /// `GymVerifier.currentDwellMinutes(gymID:)`'s equivalent role for gym dwell.
    public func currentStepCount(goalID: UUID) async throws -> Double {
        try await state.currentStepCount(goalID: goalID)
    }

    /// Arms background observation for `goalID`: registers an `HKObserverQuery` for step count
    /// (with background delivery enabled) that re-runs `checkToday(goalID:)` on every new sample
    /// HealthKit reports, and runs one `checkToday` immediately so a goal that was already met
    /// before this was called (e.g. app relaunch mid-afternoon, well past the target) gets logged
    /// right away rather than waiting on the next step HealthKit happens to record.
    ///
    /// Idempotent: calling this again for a `goalID` that's already being observed is a no-op.
    ///
    /// - Throws: `StepsVerifierError.healthDataUnavailable` if HealthKit itself can't be queried
    ///   on this device. Background-delivery enablement failing is logged, not thrown — the
    ///   observer query itself (foreground/background wake while the process is alive) still
    ///   works without it; see `StepsObserverState.startObserving`'s doc comment.
    public func startObserving(goalID: UUID) async throws {
        try await state.startObserving(goalID: goalID)
    }

    /// Tears down background observation for `goalID`. A no-op if it was never started (or
    /// already stopped).
    public func stopObserving(goalID: UUID) async {
        await state.stopObserving(goalID: goalID)
    }
}

// MARK: - StepsObserverState (private actor: the real mutable state and I/O)

/// Owns every mutable, shared piece of steps-verification state: per-goal `HKObserverQuery`
/// handles, the shared `HKHealthStore`, and the one `ModelContext` this file reads `Goal`/writes
/// `GoalEvent` through. A plain `actor` (not `@MainActor`) — same reasoning `GymVerifier`'s
/// `GymDwellState` documents: `HKObserverQuery` update handlers fire on an arbitrary HealthKit
/// background queue, not in response to user interaction, so there is no reason to funnel this
/// work through the main actor the way `LockEngineManager`/`StreakEngine`/`AdaptiveGoalEngine` do
/// for their UI-adjacent, `ModelContext`-owning singletons.
actor StepsObserverState {
    private let healthStore = HKHealthStore()
    private let modelContainer: ModelContainer

    /// One shared `ModelContext` for every fetch/insert/save this actor does, so a `Goal` fetched
    /// here and a `GoalEvent` inserted here always live in the same context — inserting a model
    /// that references an object fetched from a *different* `ModelContext` is a SwiftData
    /// programmer error (cross-context relationship), not something a per-call fresh context
    /// (the way `GymDwellState.fetchGym` does it for its read-only lookups) would catch safely
    /// here, since this file both reads `Goal` and writes `GoalEvent` in the same operation.
    private lazy var context = ModelContext(modelContainer)

    /// One `HKObserverQuery` per goal currently being observed, keyed by `Goal.id`.
    private var observerQueries: [UUID: HKObserverQuery] = [:]

    /// Set once `enableBackgroundDelivery` has been requested for step count, so a second
    /// `startObserving` call for a different goal doesn't re-request it — background delivery is
    /// per-type, not per-goal (HealthKit has exactly one step-count background delivery setting
    /// for this app, shared across every Steps goal, of which spec §3 implies there is normally
    /// just one active at a time anyway).
    private var backgroundDeliveryRequested = false

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "StepsVerifier")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `StepsVerifier.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Authorization

    /// Classic completion-handler `HKHealthStore.requestAuthorization(toShare:read:completion:)`
    /// wrapped in a continuation, not the newer `async throws` overload — matching
    /// `GymVerifier`/`GymAutoDetect`'s existing pattern in this same folder of only reaching for
    /// HealthKit's original, longest-stable API surface, since this session has no Mac/Xcode to
    /// compile-verify a newer overload's exact availability (CLAUDE.md working rule 5). This
    /// specific initializer has existed since HealthKit's introduction (iOS 8) and is believed
    /// solid; flagged in knownIssues only for the general "no compiler to check" caveat every
    /// HealthKit call in this task shares.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw StepsVerifierError.healthDataUnavailable
        }
        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw StepsVerifierError.healthDataUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: [stepCountType]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Classic `getRequestStatusForAuthorization(toShare:read:completion:)` (iOS 12+), wrapped in
    /// a continuation like every other HealthKit call here. Only `.shouldRequest` means "never
    /// asked"; `.unnecessary`, `.unknown` or an error read as "already asked" so the row can't nag
    /// forever on an odd answer.
    func needsAuthorizationRequest() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [stepCountType]) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }

    // MARK: - On-demand check

    func checkToday(goalID: UUID) async throws -> Bool {
        guard let goal = fetchGoal(id: goalID) else {
            throw StepsVerifierError.goalNotFound(goalID)
        }
        guard goal.type == .steps else {
            throw StepsVerifierError.wrongGoalType(goal.type)
        }

        // Cheap SwiftData check first — skip the HealthKit round-trip entirely if today's
        // completion was already logged (idempotency; mirrors
        // `LockEngineManager.isGoalVerified(goalID:coveringDayOf:)`'s own dedupe check).
        if hasCompletedToday(goalID: goalID) {
            return true
        }

        guard let target = await effectiveTarget(for: goal), target > 0 else {
            throw StepsVerifierError.missingTargetValue(goalID)
        }

        let startOfDay = Calendar.current.startOfDay(for: .now)
        let stepCount = try await queryStepCount(from: startOfDay, to: .now)

        guard stepCount >= target else {
            return false
        }

        logCompletion(goal: goal, stepCount: stepCount, target: target)
        await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
        return true
    }

    func currentStepCount(goalID: UUID) async throws -> Double {
        guard fetchGoal(id: goalID) != nil else {
            throw StepsVerifierError.goalNotFound(goalID)
        }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return try await queryStepCount(from: startOfDay, to: .now)
    }

    // MARK: - Background observation

    /// `HKObserverQuery`'s classic initializer (present since iOS 4) rather than any newer
    /// convenience form — same "only the longest-stable HealthKit surface" reasoning as
    /// `requestAuthorization` above. The update handler runs on an arbitrary HealthKit-owned
    /// queue, not this actor, so it hops back in with `Task { await self... }`; it calls
    /// `completionHandler()` immediately after handing off to that task (not after the task
    /// finishes) — the completion handler only needs to signal "this batch was received," per
    /// Apple's documented contract, so HealthKit can keep delivering further updates rather than
    /// throttling this app for appearing unresponsive.
    func startObserving(goalID: UUID) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw StepsVerifierError.healthDataUnavailable
        }
        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw StepsVerifierError.healthDataUnavailable
        }
        guard observerQueries[goalID] == nil else { return }

        let query = HKObserverQuery(sampleType: stepCountType, predicate: nil) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard let self else { return }
            if let error {
                Task { await self.logObserverError(error, goalID: goalID) }
                return
            }
            Task {
                _ = try? await self.checkToday(goalID: goalID)
            }
        }

        healthStore.execute(query)
        observerQueries[goalID] = query

        await enableBackgroundDeliveryIfNeeded(for: stepCountType)

        // Covers the case where the target was already met before observation started (e.g. the
        // app relaunches at 3pm and the user already hit 10,000 steps at noon) — without this,
        // that goal would stay unverified until the next fresh step sample happens to arrive.
        _ = try? await checkToday(goalID: goalID)
    }

    func stopObserving(goalID: UUID) {
        guard let query = observerQueries.removeValue(forKey: goalID) else { return }
        healthStore.stop(query)
    }

    /// Classic completion-handler `enableBackgroundDelivery(for:frequency:withCompletion:)`,
    /// wrapped rather than the newer `async throws` overload — same reasoning as every other
    /// HealthKit call in this file. Failure here is logged, not thrown: the `HKObserverQuery`
    /// registered in `startObserving` above still fires while this process is alive even without
    /// background delivery, so degrading to "foreground-only observation" rather than failing
    /// `startObserving` outright matches this folder's general stance (e.g.
    /// `FocusSessionVerifier.requestLiveActivity`) of never letting an optional enhancement take
    /// down the feature it's enhancing.
    private func enableBackgroundDeliveryIfNeeded(for stepCountType: HKQuantityType) async {
        guard !backgroundDeliveryRequested else { return }
        backgroundDeliveryRequested = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.enableBackgroundDelivery(for: stepCountType, frequency: .immediate) { [logger] success, error in
                if !success {
                    logger.error(
                        "enableBackgroundDelivery(for: stepCount) failed: \(String(describing: error), privacy: .public)"
                    )
                }
                continuation.resume()
            }
        }
    }

    private func logObserverError(_ error: Error, goalID: UUID) {
        logger.error(
            "Steps HKObserverQuery for goal \(goalID.uuidString, privacy: .public) reported an error: \(String(describing: error), privacy: .public)"
        )
    }

    // MARK: - HealthKit query

    /// Classic `HKStatisticsQuery` (`.cumulativeSum`) wrapped in a continuation — the same
    /// completion-handler-based approach `GymVerifier.elevatedHeartRateDuringDwell` uses for its
    /// own HealthKit query, rather than the newer `HKStatisticsQueryDescriptor` async API (its
    /// exact initializer shape is less certain without a compiler to check against — flagged in
    /// knownIssues).
    private func queryStepCount(from start: Date, to end: Date) async throws -> Double {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw StepsVerifierError.healthDataUnavailable
        }
        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw StepsVerifierError.healthDataUnavailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let count = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: count)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Target resolution

    /// Today's effective target: `AdaptiveGoalEngine.dailyPlan(for:on:)`'s `plannedValue` if set,
    /// falling back to the goal's raw `targetValue` — the exact same `plan.plannedValue ??
    /// goal.targetValue` fallback `PlanB.swift` uses (docs/spec.md §9's adaptive engine is the
    /// single source of truth for "today's actual bar," not a second notion computed here).
    ///
    /// `AdaptiveGoalEngine` is `@MainActor` (see its own declaration's doc comment), so this hops
    /// there and back; only `plan.plannedValue` (a plain `Double?`) crosses back out — the
    /// `DailyPlan` object itself, which lives in `AdaptiveGoalEngine`'s own `ModelContext`, is
    /// never touched again after that, so no cross-context relationship is ever established. The
    /// `Goal` passed in, however, does cross the same boundary `AdaptiveGoalEngine`'s own header
    /// comment already flags as an open, unresolved-in-this-codebase wrinkle (`@Model` classes are
    /// not `Sendable`) — carried here unchanged, not newly introduced by this file; see
    /// knownIssues.
    private func effectiveTarget(for goal: Goal) async -> Double? {
        // Only a UUID goes in and a plain Double? comes out — no @Model crosses the actor boundary.
        let goalID = goal.id
        let fallback = goal.targetValue
        return await AdaptiveGoalEngine.shared.effectiveTarget(forGoalID: goalID, on: .now) ?? fallback
    }

    // MARK: - SwiftData

    private func fetchGoal(id: UUID) -> Goal? {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Whether a `.complete` `GoalEvent` already exists for `goalID` today. Fetches by the
    /// cheap, `#Predicate`-safe fields only (`verified`, `ts`) and filters the relationship
    /// (`goal?.id`) and the `kind` enum comparison in plain Swift afterwards — the same
    /// conservative split `LockEngineManager.isGoalVerified(goalID:coveringDayOf:)` and
    /// `AdaptiveGoalEngine.fetchPriorDailyPlans` both document: no Mac/Swift toolchain here to
    /// compile-verify how `#Predicate` handles optional-relationship chaining or custom `Codable`
    /// enum equality on this SDK version, so only unambiguous `Bool`/`Date` comparisons go inside
    /// the macro.
    private func hasCompletedToday(goalID: UUID) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= startOfDay }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains { $0.goal?.id == goalID && $0.kind == .complete }
    }

    /// Logs today's step-count completion as a `GoalEvent` (docs/spec.md §13 — "every log,
    /// verification, completion... gets a row"). `value` is the raw step count, matching
    /// `Goal.unit` for a Steps goal (`"steps"`, per spec §13's example units).
    private func logCompletion(goal: Goal, stepCount: Double, target: Double) {
        let event = GoalEvent(
            ts: .now,
            kind: .complete,
            value: stepCount,
            source: .healthKit,
            verified: true,
            meta: .object([
                "target": .number(target),
                "stepCount": .number(stepCount),
            ]),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        do {
            try context.save()
            logger.notice(
                "Steps goal \(goal.id.uuidString, privacy: .public) verified: \(Int(stepCount), privacy: .public) / \(Int(target), privacy: .public) steps."
            )
        } catch {
            logger.error(
                "Failed to save Steps GoalEvent for goal \(goal.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
