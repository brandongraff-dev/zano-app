// Core/Sources/Core/Verification/HomeWorkoutVerifier.swift
//
// docs/spec.md §3 "Goal Catalog & Verification" — "Workout (home/outdoor)" row (Tier A):
//   How it's verified: "HealthKit workout logged (Apple Watch, Strava, Nike Run Club, etc.) OR
//   Core Motion active minutes"
//   Anti-cheat: "Min 20 min; HR if Watch present"
// Goal type: `GoalType.workoutHomeOutdoor` (Core/Sources/Core/Models/Goal.swift) — not
// `.workoutGym`, which `GymVerifier.swift` (same directory) already owns.
//
// Sibling of GymVerifier.swift for the *other* workout row. This verifier has **no geofence and no
// dwell session** — unlike a gym workout, a home/outdoor workout has no fixed saved location to
// arrive at and stay inside, so there is nothing here resembling `GymDwellState`'s per-gym
// `DwellSession` dictionary or its `CLMonitor` region-event loop. That machinery is deliberately not
// reused or duplicated from GymVerifier, because it doesn't apply to this row at all — only what
// genuinely is shared between the two verification stories is mirrored below (and each time, it says
// so instead of silently re-deriving it):
//   - the actor-isolates-the-SDK-state shape (write-swift skill §3: "isolate it to an actor"), used
//     here even though this file has no *mutable* state to protect the way gym dwell sessions are —
//     it's still the clean way to give `HKHealthStore`/`CMMotionActivityManager` (both predate Swift
//     6 and aren't SDK-audited `Sendable`) a home without `nonisolated(unsafe)` sprinkled everywhere.
//   - "elevated HR is opportunistic corroboration, never a gate" — same reasoning as
//     `GymVerifier.elevatedHeartRateDuringDwell`'s doc comment (HealthKit's `authorizationStatus(for:)`
//     only ever reports *write* status, never read status, so "denied" and "no data" are
//     indistinguishable from inside the app — treating a `nil` answer as failure would silently turn
//     a corroboration signal into an invisible, unfixable block. CLAUDE.md: "never trap the user.")
//   - Core Motion's automotive/low-confidence handling mirrors `MotionAntiCheat`'s and
//     `GymVerifier.isAutomotive`'s documented fail-open reasoning, not re-derived here.
//
// Every query here is stateless and re-evaluated fresh per call — there is no multi-step "arm
// tracking, then poll" lifecycle the way gym dwell needs one (dwell has to accumulate live; a
// completed HealthKit workout or a completed stretch of Core Motion activity is just... queried).
// That collapses what would otherwise be GymVerifier's four-method split
// (`beginDwellTracking`/`currentDwellMinutes`/`isVerified`/`lastHealthKitCorroboration`) into one
// `verify(in:requiredMinutes:)` call that returns everything a caller needs — evidence source,
// minutes, HR corroboration — in one `HomeWorkoutVerificationResult`, plus a thin `isVerified`
// convenience for callers that only want the bool.
//
// No public API for this file is fixed by an orchestrator SYSTEM CONTRACTS block — a repo-wide
// search for `HomeWorkoutVerifier` before writing this file found no other file referencing it yet
// — so this shape is this session's own design, chosen to fit how the verification story actually
// works rather than force-fit GymVerifier's shape where it doesn't apply. See this task's
// `knownIssues`/`decisions` output for the call these judgment calls (goalID-less API, single-workout
// vs. cross-workout duration, HR-corroboration blocking-vs-soft) actually made.
//
// Like GymVerifier (see its header), this file does not write `GoalEvent` rows itself — it answers
// "is this goal verified right now, and via what evidence," and leaves turning that into a
// `GoalEvent`/streak update to LockEngine's goal-completion integration point. That integration point
// is not yet built as of this session (`LockEngineManager.isGoalVerified` currently only reads
// already-written `GoalEvent` rows; nothing yet calls any verifier and writes the resulting event —
// the same gap GymVerifier's header already flags for the gym row).
//
// Update (buildout Wave 1D, 2026-09-25): the GoalEvent-writing gap above is now closed for the
// HealthKit-workout signal. `checkToday(goalID:)` writes one verified `.complete` (source
// `.healthKit`) when a single HealthKit workout today meets the goal's minutes, then calls
// `GoalCompletionCoordinator`. The Core Motion fallback still only answers `verify`; it never writes
// a completion on its own (a day of walking around would otherwise count as a workout).
//
// SDK surface used below (`HKSampleQuery` over `HKObjectType.workoutType()`, sorting by
// `HKSampleSortIdentifierEndDate`, `HKSourceRevision.productType` for Watch-vs-other-source
// detection, `CMMotionActivityManager` historical activity queries) was written from training
// knowledge, not confirmed against a live SDK or current Apple sample code (no Mac/Xcode in this
// environment — CLAUDE.md working rule 5). Flagged in this session's knownIssues for a real-SDK
// check on first build, same as GymVerifier already flags its own CLMonitor surface for the same
// reason.

import CoreMotion
import Foundation
import HealthKit
import SwiftData
import os

/// Tunable constants for home/outdoor workout verification, named so other modules (workout goal
/// setup UI, `AdaptiveGoalEngine`) can reference the same values this file's spec citation
/// documents instead of repeating a magic number — mirrors `GymVerificationDefaults`' role for the
/// gym row.
public enum HomeWorkoutVerificationDefaults {
    /// docs/spec.md §3 "Workout (home/outdoor)" anti-cheat column: "Min 20 min".
    public static let requiredMinutes = 20

    /// Heart-rate threshold (BPM) used as the "elevated" corroboration signal when a qualifying
    /// workout was Watch-sourced (spec: "HR if Watch present"). Deliberately the same value
    /// `GymVerifier` uses for its own elevated-HR check (`GymVerificationDefaults
    /// .elevatedHeartRateBPM`) rather than a second, possibly-drifting magic number — both rows are
    /// answering the same underlying question ("does this look like real exertion?").
    public static let elevatedHeartRateBPM = GymVerificationDefaults.elevatedHeartRateBPM
}

/// Errors `HomeWorkoutVerifier.checkToday(goalID:)` throws itself.
public enum HomeWorkoutVerifierError: Error, Sendable, Equatable {
    case goalNotFound(UUID)
    case wrongGoalType(GoalType)
}

/// Which signal a `HomeWorkoutVerificationResult` was actually verified from.
///
/// Deliberately **not** a 1:1 mirror of `GoalEventSource`
/// (`Core/Sources/Core/Models/GoalEvent.swift`) — that enum's raw values are a closed Postgres check
/// constraint (`'nfc' | 'widget' | 'photo' | 'barcode' | 'geofence' | 'healthkit' | 'timer' |
/// 'manual' | 'siri'`) this file has no scope to extend, and it has no case that cleanly means "Core
/// Motion activity classification, not a HealthKit workout sample." Whichever future
/// `GoalEvent`-writing integration point (see this file's header) maps `.coreMotionActiveMinutes`
/// onto a `GoalEventSource` will need to either pick the closest existing fit (most likely
/// `.healthKit`, since it's still device-sensor-derived rather than a user action like an NFC tap)
/// or add a dedicated source value in a schema migration — a decision for whoever owns
/// `backend/supabase/migrations`, not this file. Flagged in knownIssues rather than decided here.
public enum HomeWorkoutVerificationSource: Sendable, Equatable {
    /// A qualifying `HKWorkout` sample was found (Apple Watch, Strava, Nike Run Club, or any other
    /// app that writes workouts to HealthKit — spec's "etc." is intentionally open, not an
    /// allowlist of source apps).
    case healthKitWorkout
    /// No qualifying HealthKit workout existed, but Core Motion's activity classification showed
    /// enough sustained walking/running/cycling time in the window.
    case coreMotionActiveMinutes
}

/// Everything a caller needs to both know a home/outdoor workout is verified and, if it wants to,
/// log the evidence (e.g. onto a future `GoalEvent.meta`) without re-querying HealthKit/Core Motion.
public struct HomeWorkoutVerificationResult: Sendable, Equatable {
    public let verified: Bool
    /// `nil` iff `verified` is `false` and neither signal found anything qualifying.
    public let source: HomeWorkoutVerificationSource?
    /// Minutes of evidence found for `source` (workout duration, or summed active-classification
    /// time), rounded down to whole minutes. `0` when `verified` is `false`.
    public let minutes: Int
    /// Elevated-HR corroboration for a Watch-sourced `.healthKitWorkout` result only (spec: "HR if
    /// Watch present" — an iPhone-only workout has no continuous HR sensor to check). `nil` when
    /// not applicable (no qualifying workout, the workout wasn't Watch-sourced, or HealthKit had no
    /// HR samples to judge — see `HomeWorkoutQueryState.heartRateCorroboration`'s doc comment for
    /// why `nil` must never be read as `false`). Exactly like `GymVerifier
    /// .lastHealthKitCorroboration`, this **never gates `verified`** — it's opportunistic
    /// corroboration only, never a reason a real workout fails to unlock anything.
    public let heartRateCorroboration: Bool?

    public static let notVerified = HomeWorkoutVerificationResult(
        verified: false, source: nil, minutes: 0, heartRateCorroboration: nil
    )
}

/// Verifies the Workout (home/outdoor) goal (docs/spec.md §3, Tier A) by checking two independent
/// signals, either one sufficient on its own:
///
/// 1. **HealthKit workout** — any single `HKWorkout` sample (however it got into HealthKit: Apple
///    Watch, Strava, Nike Run Club, Apple's own Workout app, etc.) with a duration ≥
///    `requiredMinutes` (spec default 20), inside the caller's window. Checked first; a real logged
///    workout is strictly better evidence than a motion-classification inference, so a qualifying
///    hit here short-circuits without also burning a Core Motion query.
/// 2. **Core Motion active minutes** — the fallback for a workout nobody logged anywhere: Core
///    Motion's own activity classification shows ≥ `requiredMinutes` of cumulative
///    walking/running/cycling time (excluding automotive and stationary) inside the window. This is
///    the *only* signal a phone-only user with no workout-logging app can ever produce, so spec's
///    "OR" is load-bearing — it is a first-class path here, not an afterthought.
///
/// Elevated heart rate during a Watch-sourced workout (spec: "HR if Watch present") is checked and
/// returned as corroboration but never blocks `verified` — see `HomeWorkoutVerificationResult
/// .heartRateCorroboration`'s doc comment.
///
/// `Sendable` `final class` with zero mutable state of its own; the SDK objects it drives
/// (`HKHealthStore`, `CMMotionActivityManager`) live on a private actor, `HomeWorkoutQueryState` —
/// see this file's header for why an actor is used here even without a dwell-style mutable session
/// to protect.
public final class HomeWorkoutVerifier: Sendable {
    public static let shared = HomeWorkoutVerifier()

    private let state: HomeWorkoutQueryState

    /// Internal for tests — production code always uses `.shared`.
    init(state: HomeWorkoutQueryState = HomeWorkoutQueryState()) {
        self.state = state
    }

    /// `true` iff `verify(in:requiredMinutes:)` found a qualifying signal. Convenience for call
    /// sites (LockEngine's future goal-completion check, Today screen polling) that only need the
    /// bool — use `verify` directly when the evidence (`source`/`minutes`/HR corroboration) is also
    /// needed, e.g. to attach to a `GoalEvent`.
    public func isVerified(
        in window: DateInterval? = nil,
        requiredMinutes: Int = HomeWorkoutVerificationDefaults.requiredMinutes
    ) async -> Bool {
        await verify(in: window, requiredMinutes: requiredMinutes).verified
    }

    /// Runs both verification signals against `window` (defaults to the local calendar day
    /// containing `.now`, matching how a daily Tier A goal is actually evaluated — see
    /// `LockEngineManager.isGoalVerified`'s own `Calendar.current.startOfDay(for:)` day-boundary
    /// convention, mirrored here rather than reinvented) and returns the full result.
    ///
    /// - Parameters:
    ///   - window: The interval to look for a qualifying workout/activity in. `nil` means "today so
    ///     far." Passing an explicit interval (e.g. a full past day) is how a caller would run a
    ///     retroactive check, though the primary use is the live "did today's goal happen yet?"
    ///     check with the default.
    ///   - requiredMinutes: Spec default 20 (`HomeWorkoutVerificationDefaults.requiredMinutes`). A
    ///     caller with a `Goal.targetValue` override should pass that instead — this file has no
    ///     SwiftData access of its own (unlike `GymVerifier`, this verifier has no saved per-goal
    ///     row of its own to fetch; there is nothing here to look a `Goal` up *for* beyond the
    ///     minutes threshold, which the caller already has from its own `Goal` fetch).
    public func verify(
        in window: DateInterval? = nil,
        requiredMinutes: Int = HomeWorkoutVerificationDefaults.requiredMinutes
    ) async -> HomeWorkoutVerificationResult {
        let resolvedWindow = window ?? Self.defaultWindow()
        guard resolvedWindow.duration > 0 else { return .notVerified }

        if let workoutResult = await state.verifyViaHealthKitWorkout(
            window: resolvedWindow, requiredMinutes: requiredMinutes
        ) {
            return workoutResult
        }
        return await state.verifyViaCoreMotionActiveMinutes(
            window: resolvedWindow, requiredMinutes: requiredMinutes
        )
    }

    // MARK: - Goal completion (Today, foreground checks)

    /// `true` while the app has never asked for HealthKit workout read access (HealthKit can't say
    /// whether read access was *granted*, only whether the request sheet still needs showing).
    /// Today shows "Connect Apple Health" while this is `true`.
    public func needsAuthorizationRequest() async -> Bool {
        await state.needsAuthorizationRequest()
    }

    /// The longest single HealthKit workout today, in whole minutes (`0` with no workouts or no
    /// read access). For the row's live progress ring.
    public func longestWorkoutMinutesToday() async -> Int {
        await state.longestWorkoutMinutes(in: Self.defaultWindow())
    }

    /// The minutes one workout must reach for `goalID`: today's planned value (else the goal's
    /// target), never below spec §3's 20-minute floor.
    public func requiredMinutes(forGoalID goalID: UUID) async -> Int {
        let target = await AdaptiveGoalEngine.shared.effectiveTarget(forGoalID: goalID, on: .now)
        return Self.requiredMinutes(target: target)
    }

    static func requiredMinutes(target: Double?) -> Int {
        max(HomeWorkoutVerificationDefaults.requiredMinutes, Int((target ?? 0).rounded()))
    }

    /// Checks today's HealthKit workouts for `goalID` (a `.workoutHomeOutdoor` goal). When one
    /// workout reaches the required minutes and no verified completion exists yet today, writes a
    /// verified `.complete` `GoalEvent` (`source: .healthKit`, the workout's minutes as `value`),
    /// then calls `GoalCompletionCoordinator`. Idempotent: returns `true` without writing when
    /// today is already complete.
    @discardableResult
    public func checkToday(goalID: UUID) async throws -> Bool {
        let required = await requiredMinutes(forGoalID: goalID)
        let wrote = try await state.checkToday(goalID: goalID, requiredMinutes: required, window: Self.defaultWindow())
        if wrote == .wroteCompletion {
            await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
        }
        return wrote != .notYet
    }

    /// The local calendar day containing `now`, from midnight through `now` — today's "so far"
    /// window. A plain, non-actor-isolated helper (touches no SDK state), unlike everything else in
    /// this file.
    private static func defaultWindow(calendar: Calendar = .current, now: Date = .now) -> DateInterval {
        DateInterval(start: calendar.startOfDay(for: now), end: now)
    }
}

// MARK: - HomeWorkoutQueryState (private actor: SDK state + the actual queries)

/// Owns the two non-Sendable-audited SDK objects this verifier drives (`HKHealthStore`,
/// `CMMotionActivityManager`) and the queries that use them. No dictionaries of per-goal state to
/// protect the way `GymDwellState` has — see this file's header for why an actor is still the right
/// shape.
actor HomeWorkoutQueryState {
    private let healthStore = HKHealthStore()
    private let motionActivityManager = CMMotionActivityManager()
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "HomeWorkoutVerifier")
    private let modelContainer: ModelContainer
    /// One context for the goal fetch and the event insert (same reason as `StepsObserverState`).
    private lazy var context = ModelContext(modelContainer)

    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    enum CheckOutcome: Sendable, Equatable {
        case notYet
        case alreadyComplete
        case wroteCompletion
    }

    // MARK: Goal completion

    func checkToday(goalID: UUID, requiredMinutes: Int, window: DateInterval) async throws -> CheckOutcome {
        guard let goal = fetchGoal(id: goalID) else { throw HomeWorkoutVerifierError.goalNotFound(goalID) }
        guard goal.type == .workoutHomeOutdoor else { throw HomeWorkoutVerifierError.wrongGoalType(goal.type) }
        if hasVerifiedCompletion(goalID: goalID, since: window.start) { return .alreadyComplete }

        guard let result = await verifyViaHealthKitWorkout(window: window, requiredMinutes: requiredMinutes),
              result.verified, result.source == .healthKitWorkout
        else { return .notYet }

        // Re-check after the HealthKit await: another call may have written it meanwhile.
        if hasVerifiedCompletion(goalID: goalID, since: window.start) { return .alreadyComplete }

        var meta: [String: JSONValue] = [
            "workoutMinutes": .number(Double(result.minutes)),
            "requiredMinutes": .number(Double(requiredMinutes)),
        ]
        if let hr = result.heartRateCorroboration { meta["heartRateCorroborated"] = .bool(hr) }
        let event = GoalEvent(
            kind: .complete,
            value: Double(result.minutes),
            source: .healthKit,
            verified: true,
            meta: .object(meta),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        try context.save()
        logger.notice("Home/outdoor workout goal \(goalID.uuidString, privacy: .public) completed: \(result.minutes, privacy: .public) min.")
        return .wroteCompletion
    }

    private func fetchGoal(id: UUID) -> Goal? {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Only `Bool`/`Date` inside `#Predicate`; the relationship and kind are filtered in Swift
    /// (the split `StepsObserverState.hasCompletedToday` documents).
    private func hasVerifiedCompletion(goalID: UUID, since start: Date) -> Bool {
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= start }
        )
        guard let events = try? context.fetch(descriptor) else { return false }
        return events.contains { $0.goal?.id == goalID && GoalDayProgress.isVerifiedCompletion($0) }
    }

    // MARK: Authorization status

    /// Classic `getRequestStatusForAuthorization(toShare:read:completion:)` (iOS 12+), wrapped.
    /// `.shouldRequest` means the sheet was never shown for workouts; anything else (including an
    /// error) reads as "already asked", so the row never nags forever on an odd answer.
    func needsAuthorizationRequest() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let workoutType = HKObjectType.workoutType()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [workoutType]) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }

    // MARK: Live progress

    func longestWorkoutMinutes(in window: DateInterval) async -> Int {
        let workouts = await fetchWorkouts(in: window)
        let longest = workouts.map(\.duration).max() ?? 0
        return Int(longest / 60)
    }

    private func fetchWorkouts(in window: DateInterval) async -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable(), window.duration > 0 else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start, end: window.end, options: .strictStartDate
        )
        let sortByEndDateDescending = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortByEndDateDescending]
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout], error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    // MARK: HealthKit workout signal

    /// Returns a `.healthKitWorkout` result if a single qualifying `HKWorkout` exists in `window`;
    /// `nil` — not `.notVerified` — if HealthKit is unavailable, read access was never granted, or
    /// nothing in `window` reached `requiredMinutes`, so `HomeWorkoutVerifier.verify` knows to fall
    /// through to the Core Motion signal rather than reporting "not verified" prematurely.
    ///
    /// Requires a single workout sample to meet `requiredMinutes` on its own — several shorter
    /// workouts that sum to the threshold do not combine. Spec's "Min 20 min" reads most naturally
    /// as "the logged workout is at least 20 minutes," matching how a real HealthKit workout entry
    /// is one continuous recorded session; not spec-explicit, flagged as a judgment call in
    /// knownIssues.
    func verifyViaHealthKitWorkout(
        window: DateInterval, requiredMinutes: Int
    ) async -> HomeWorkoutVerificationResult? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let workouts = await fetchWorkouts(in: window)

        let requiredSeconds = TimeInterval(requiredMinutes * 60)
        guard let qualifying = workouts.first(where: { $0.duration >= requiredSeconds }) else {
            return nil
        }

        let minutes = Int(qualifying.duration / 60)
        let corroboration = await heartRateCorroboration(for: qualifying)
        logger.notice(
            "Home/outdoor workout verified via HealthKit: \(minutes, privacy: .public) min."
        )
        return HomeWorkoutVerificationResult(
            verified: true,
            source: .healthKitWorkout,
            minutes: minutes,
            heartRateCorroboration: corroboration
        )
    }

    /// `true` iff `workout`'s `sourceRevision.productType` names an Apple Watch model. Apple's
    /// device-model identifiers for Watch hardware all start with `"Watch"` (e.g. `"Watch6,1"`), the
    /// same shape `"iPhone14,5"`/`"iPad13,2"` etc. use for other Apple hardware —
    /// `HKSourceRevision.productType` is documented to report exactly this identifier for the
    /// device that recorded the sample. `false` (not `nil`) when `productType` itself is `nil` —
    /// some sources (older third-party apps, the Simulator) never populate it, and "unknown" should
    /// not be treated as "is a Watch" for a check that gates whether an HR query is even attempted.
    private func isWatchSourced(_ workout: HKWorkout) -> Bool {
        workout.sourceRevision.productType?.hasPrefix("Watch") ?? false
    }

    /// Elevated-HR corroboration for a qualifying workout, only attempted when `isWatchSourced`
    /// (spec: "HR if Watch present"). Returns `nil` — not `false` — whenever the signal can't
    /// honestly be answered: not Watch-sourced, no HR quantity type, or (the common case) HealthKit
    /// read access was never granted. `HKHealthStore.authorizationStatus(for:)` only ever reports
    /// *write*/share status, never read status, and a denied-read query simply returns zero
    /// samples — indistinguishable from "no HR data exists." Treating that as `nil` rather than
    /// `false` is what keeps this a corroborating signal instead of a phantom reason `verified`
    /// could quietly fail for — see `GymVerifier.elevatedHeartRateDuringDwell`'s doc comment, which
    /// this mirrors exactly (same underlying HealthKit ambiguity, same fail-open answer).
    private func heartRateCorroboration(for workout: HKWorkout) async -> Bool? {
        guard isWatchSourced(workout) else { return nil }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate, options: .strictStartDate
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard let quantitySamples = samples as? [HKQuantitySample], error == nil, !quantitySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let elevated = quantitySamples.contains {
                    $0.quantity.doubleValue(for: bpmUnit) >= HomeWorkoutVerificationDefaults.elevatedHeartRateBPM
                }
                continuation.resume(returning: elevated)
            }
            healthStore.execute(query)
        }
    }

    // MARK: Core Motion active-minutes signal (fallback)

    /// Returns a `.coreMotionActiveMinutes` result once cumulative walking/running/cycling time in
    /// `window` reaches `requiredMinutes`, else `.notVerified`.
    ///
    /// Runs its own direct `CMMotionActivityManager` query rather than reusing
    /// `MotionAntiCheat.shared.recentActivities(lookback:)`: that method's window is always
    /// `[now - lookback, now]`, which is right for its own short-lookback anti-cheat use (gym
    /// arrival, "was the last few minutes automotive?") but wrong here, where `window` can be an
    /// arbitrary interval — including one that doesn't end at `now` at all, e.g. a caller checking a
    /// past day. Availability/authorization/error handling below otherwise fails open exactly like
    /// `MotionAntiCheat`'s and `GymVerifier.isAutomotive`'s documented reasoning (not re-derived
    /// here): a missing signal must never block a real unlock (CLAUDE.md: "never trap the user").
    func verifyViaCoreMotionActiveMinutes(
        window: DateInterval, requiredMinutes: Int
    ) async -> HomeWorkoutVerificationResult {
        guard CMMotionActivityManager.isActivityAvailable() else { return .notVerified }

        let activities: [CMMotionActivity] = await withCheckedContinuation { continuation in
            motionActivityManager.queryActivityStarting(from: window.start, to: window.end, to: .main) { activities, error in
                guard let activities, error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                nonisolated(unsafe) let unsafeActivities = activities
                continuation.resume(returning: unsafeActivities)
            }
        }
        guard !activities.isEmpty else { return .notVerified }

        let activeSeconds = Self.cumulativeActiveSeconds(activities: activities, windowEnd: window.end)
        let requiredSeconds = TimeInterval(requiredMinutes * 60)
        guard activeSeconds >= requiredSeconds else { return .notVerified }

        let minutes = Int(activeSeconds / 60)
        logger.notice("Home/outdoor workout verified via Core Motion active minutes: \(minutes, privacy: .public) min.")
        return HomeWorkoutVerificationResult(
            verified: true,
            source: .coreMotionActiveMinutes,
            minutes: minutes,
            heartRateCorroboration: nil // Not applicable — no HealthKit workout to attach HR to.
        )
    }

    /// Sums the duration each consecutive, non-low-confidence "active" sample (see `isActive`)
    /// stays in effect, from its own `startDate` up to whichever comes first: the next sample's
    /// `startDate`, or `windowEnd`. `CMMotionActivityManager` reports one sample per *classification
    /// change*, not a fixed cadence — there is no per-sample "duration" field on `CMMotionActivity`
    /// itself, so a segment's length is only knowable from where the next one starts.
    private static func cumulativeActiveSeconds(activities: [CMMotionActivity], windowEnd: Date) -> TimeInterval {
        let sorted = activities.sorted { $0.startDate < $1.startDate }
        var total: TimeInterval = 0
        for (index, activity) in sorted.enumerated() {
            guard activity.confidence != .low, isActive(activity) else { continue }
            let segmentEnd = index + 1 < sorted.count ? sorted[index + 1].startDate : windowEnd
            total += max(0, segmentEnd.timeIntervalSince(activity.startDate))
        }
        return total
    }

    /// "Active" for this goal's purposes: walking, running, or cycling. Deliberately excludes
    /// `stationary`/`automotive`/`unknown` — the spec anti-cheat framing ("Core Motion active
    /// minutes" as the counterpart to a real logged workout) is about movement, not just "the phone
    /// wasn't sitting still," and automotive time is the one thing every other verifier in this
    /// codebase treats as an explicit anti-cheat signal (`MotionAntiCheat.isLikelyAutomotive`,
    /// `GymVerifier.isAutomotive`) — never something that should count toward a workout.
    private static func isActive(_ activity: CMMotionActivity) -> Bool {
        (activity.walking || activity.running || activity.cycling) && !activity.automotive
    }
}
