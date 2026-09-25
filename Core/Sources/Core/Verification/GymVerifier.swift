// Core/Sources/Core/Verification/GymVerifier.swift
//
// docs/spec.md §3 "Goal Catalog & Verification" — "Workout (gym)" row (Tier A):
//   How it's verified: "Geofence arrival at saved gym + minimum dwell (default 35 min) +
//   HealthKit workout OR elevated HR during dwell"
//   Anti-cheat: "Dwell time; HR/motion check; can't be in car (Core Motion automotive);
//   parking-lot detection via GPS accuracy radius"
// docs/spec.md §9.4 "Gym Auto-Detection" describes the companion clustering pipeline
// (GymAutoDetect.swift, same session/folder) that proposes the `Gym` row this verifier later
// tracks dwell against; its anti-cheat line ("dwell inside radius, Core Motion not automotive,
// optional HR") is the same signal set implemented here, just applied live instead of
// historically.
//
// SYSTEM CONTRACTS (orchestrator-fixed public shape):
//   final class GymVerifier {
//       static let shared = GymVerifier()
//       func beginDwellTracking(gymID: UUID) async
//       func currentDwellMinutes(gymID: UUID) async -> Int
//       func isVerified(gymID: UUID, requiredMinutes: Int) async -> Bool
//   }
// Implemented below with that exact outer shape (see "decisions" in this session's structured
// report for the one intentional addition, `currentContentState`, and why `requiredMinutes` grew
// a default value instead of losing its explicit-call compatibility).
//
// Concurrency: `GymVerifier` itself is a `final class` (per contract) with no mutable stored
// state — every mutable field (per-gym dwell sessions, the CLMonitor instance, its event-reading
// Task) lives on a private `actor`, `GymDwellState`, that this class forwards to. That makes
// `GymVerifier` trivially, non-`@unchecked` `Sendable` (its only stored property is a `let`
// reference to an actor, and actors are implicitly `Sendable`), while still giving the mutable
// dwell-tracking state a real transaction boundary. See the write-swift skill §3–4: "isolate it
// to an actor" is the standard fix for state shared across the app's various callers of
// `GymVerifier.shared`, and an actor's synchronous methods are where invariants must hold.

import Foundation
import CoreLocation
import CoreMotion
import HealthKit
import SwiftData
import os

/// Tunable constants for gym verification, named so other modules (Gym Setup UI, the Live
/// Activity, `AdaptiveGoalEngine`) can reference the same values the spec table documents
/// instead of repeating a magic number.
public enum GymVerificationDefaults {
    /// docs/spec.md §3: "minimum dwell (default 35 min)".
    public static let requiredDwellMinutes = 35
    /// Heart-rate threshold (BPM) used as the "elevated" HealthKit corroboration signal (spec
    /// §3: "elevated HR during dwell"; §9.4: "If HealthKit HR was elevated ... confidence up").
    /// Not sourced from the spec verbatim (it gives no number) — a reasonable resting-exceeding
    /// threshold for "this looks like exercise, not standing around", picked conservatively low
    /// so it under- rather than over-claims. Worth tuning once `goal_events` has real data
    /// (spec §9.9).
    public static let elevatedHeartRateBPM = 100.0
}

/// Verifies the Workout (gym) goal (docs/spec.md §3, Tier A) by combining three signals, in
/// order of how load-bearing each one is to `isVerified`'s result:
///
/// 1. **Geofence + dwell** (hard requirement) — a `CLMonitor` condition on the saved `Gym`'s
///    circular region, with a running dwell clock while the device stays inside it.
/// 2. **Anti-cheat** (hard requirement) — Core Motion's historical activity classification must
///    not show automotive travel during the dwell window (spec: "can't be in car").
/// 3. **HealthKit corroboration** (soft signal, never blocking) — elevated heart rate during the
///    dwell window raises confidence (mirrored onto `GymDwellActivityAttributes.ContentState`
///    and available to callers via `lastHealthKitCorroboration(gymID:)` for `GoalEvent.meta`),
///    but a user who has not granted HealthKit read access — or whose HealthKit data has none —
///    is never blocked by it. See `elevatedHeartRateDuringDwell`'s doc comment for exactly why
///    HealthKit read authorization makes "blocking on it" impossible to do honestly anyway.
///
/// `beginDwellTracking`/`currentDwellMinutes`/`isVerified` are the orchestrator's fixed public
/// shape; do not rename or retype them without updating every other module calling
/// `GymVerifier.shared` by name (LockEngine's goal-completion check, the Live Activity update
/// loop, `AdaptiveGoalEngine`'s `GoalEvent` sourcing, etc.).
public final class GymVerifier: Sendable {
    public static let shared = GymVerifier()

    private let state: GymDwellState

    /// Internal for tests — production code always uses `.shared`. Not part of the fixed
    /// contract shape; the no-argument path (`GymVerifier()` behind `.shared`) is.
    init(state: GymDwellState = GymDwellState()) {
        self.state = state
    }

    /// Arms dwell tracking for `gymID`: looks the gym up in the App Group SwiftData store,
    /// starts (or reuses) a `CLMonitor` condition on its saved geofence, and starts the dwell
    /// clock immediately. `GymVerifier` does not itself decide *when* someone is near their gym
    /// — the realistic caller is "a region-entry event just fired" or "the user opened the app
    /// and CLMonitor's cached state already shows the condition satisfied" — it only starts
    /// measuring once told to. Idempotent: calling this again while a session for `gymID` is
    /// already active (not yet exited) is a no-op, so a caller can call it eagerly without
    /// worrying about double-counting dwell time.
    ///
    /// A logged no-op (CONTRACTS gives this method no error channel) if `gymID` has no saved
    /// `Gym` row, or if that row's `confirmed` is `false` — `Gym.confirmed`'s own doc comment
    /// (`Core/Sources/Core/Models/Gym.swift`) states the invariant explicitly: "GymVerifier must
    /// only use confirmed gyms for real unlocks; an unconfirmed autoDetected row is a suggestion
    /// only." Enforced here rather than just assumed of callers, so an unconfirmed
    /// `GymAutoDetect` candidate id passed in by mistake can never start real dwell tracking.
    public func beginDwellTracking(gymID: UUID) async {
        await state.beginDwellTracking(gymID: gymID)
    }

    /// Minutes elapsed in the current (or most recently ended, if the device already stepped
    /// outside the geofence) dwell session for `gymID`. `0` if `beginDwellTracking` was never
    /// called for this gym, or if a prior session was superseded by a fresh region entry after
    /// fully exiting (see `GymDwellState.handleRegionEntered`).
    public func currentDwellMinutes(gymID: UUID) async -> Int {
        await state.currentDwellMinutes(gymID: gymID)
    }

    /// `true` once dwell time ≥ `requiredMinutes` (spec default 35,
    /// `GymVerificationDefaults.requiredDwellMinutes`) **and** Core Motion shows no
    /// medium-or-higher-confidence automotive activity during the dwell window. HealthKit
    /// elevated-HR corroboration is checked opportunistically (see the type doc comment) but
    /// never gates this result — dwell + anti-cheat alone satisfy Tier A's "auto-verify if
    /// possible... never a form" (spec §3).
    ///
    /// The first `true` for a dwell also writes the day's workout `.complete` `GoalEvent`
    /// (`source: .geofence`, HR corroboration in `meta`) and calls `GoalCompletionCoordinator`.
    /// The same check runs on its own when the geofence reports the user leaving the gym.
    ///
    /// `requiredMinutes` has no default in the orchestrator's CONTRACTS block; the default added
    /// here is purely additive (every explicit-argument call site still compiles and behaves
    /// identically) and just saves callers from repeating the spec's default at every call site.
    public func isVerified(
        gymID: UUID,
        requiredMinutes: Int = GymVerificationDefaults.requiredDwellMinutes
    ) async -> Bool {
        await state.isVerified(gymID: gymID, requiredMinutes: requiredMinutes)
    }

    /// Last HealthKit elevated-HR corroboration result recorded by `isVerified` for `gymID`:
    /// `nil` if `isVerified` hasn't run yet (or HealthKit had nothing to say — see
    /// `elevatedHeartRateDuringDwell`), `true`/`false` once it has. Exposed so a caller writing
    /// the resulting `GoalEvent` (LockEngine/Verification integration point — this file does not
    /// write `GoalEvent` rows itself, following `FocusSessionVerifier`'s equivalent boundary) can
    /// attach it to `GoalEvent.meta` without re-querying HealthKit.
    public func lastHealthKitCorroboration(gymID: UUID) async -> Bool? {
        await state.lastHealthKitCorroboration(gymID: gymID)
    }

    /// Convenience bundling `currentDwellMinutes`/`isVerified` into the exact `ContentState`
    /// shape `GymDwellActivityAttributes` (same Verification/LiveActivity ownership, this
    /// session) needs, so whichever module starts/updates the gym-dwell Live Activity
    /// (docs/spec.md §6: "Gym dwell: 'At the gym · 22 min · verified at 35'") doesn't have to
    /// duplicate the verified-comparison logic. Not part of the fixed CONTRACTS shape — an
    /// intentional, additive convenience since both files it bridges are owned by this session.
    public func currentContentState(
        gymID: UUID,
        requiredMinutes: Int = GymVerificationDefaults.requiredDwellMinutes
    ) async -> GymDwellActivityAttributes.ContentState {
        let elapsed = await currentDwellMinutes(gymID: gymID)
        let verified = await isVerified(gymID: gymID, requiredMinutes: requiredMinutes)
        return GymDwellActivityAttributes.ContentState(
            elapsedMinutes: elapsed,
            verifiedAtMinutes: requiredMinutes,
            isVerified: verified
        )
    }
}

// MARK: - GymDwellState (private actor: the real mutable state and I/O)

/// Owns every mutable, shared piece of gym-verification state: per-gym dwell sessions, the
/// lazily-created `CLMonitor` and its event-consuming background `Task`, and the Core
/// Location/Motion/HealthKit calls needed to evaluate them. Dictionary mutations happen in
/// synchronous methods (the actor's transaction boundary — write-swift skill §3: "mutate actor
/// state in synchronous methods"); only the calls out to Apple frameworks are `async`, and each
/// one's result is written back in one more synchronous hop rather than left half-applied across
/// a suspension point.
actor GymDwellState {
    private var sessions: [UUID: DwellSession] = [:]

    /// Lazily created on first `beginDwellTracking` call. `CLMonitor` (iOS 17+) is Apple's
    /// async/await-native replacement for delegate-based `CLLocationManager` region monitoring
    /// (WWDC23 "Meet Core Location Monitor") — a natural fit for an actor-owned event loop, since
    /// its `events` sequence can be iterated with `for try await` directly against `self`.
    private var monitor: CLMonitor?

    /// One geofence-event-consuming `Task` for the process's lifetime of this actor (not one per
    /// gym — a single `CLMonitor` instance holds every condition; spec §27 notes region
    /// monitoring supports ~20 regions per app and "one gym per user is fine", but the loop below
    /// keys off `event.identifier` so a second saved gym needs no changes here).
    private var eventTask: Task<Void, Never>?

    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()
    private let healthStore = HKHealthStore()

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GymVerifier")

    /// Stable name CLMonitor persists its condition state under across launches (WWDC23: a
    /// `CLMonitor` reloads its saved conditions from disk when re-created with the same name).
    private static let monitorName = "com.zano.app.gymMonitor"

    // MARK: Public-facing operations (called by GymVerifier)

    func beginDwellTracking(gymID: UUID) async {
        if let existing = sessions[gymID], existing.isActive {
            return
        }
        guard let gym = fetchGym(id: gymID) else {
            logger.error(
                "beginDwellTracking(gymID:) called for a gym id with no saved Gym row: \(gymID.uuidString, privacy: .public)."
            )
            return
        }
        // Gym.confirmed's contract (Core/Sources/Core/Models/Gym.swift): only confirmed gyms may
        // be dwell-tracked/verified — an unconfirmed, autoDetected row is a suggestion only.
        guard gym.confirmed else {
            logger.notice(
                "beginDwellTracking(gymID:) called for an unconfirmed Gym (\(gymID.uuidString, privacy: .public)); ignoring per Gym.confirmed's contract."
            )
            return
        }
        sessions[gymID] = DwellSession(gymID: gymID, enteredAt: .now)
        await armGeofence(for: gym)
    }

    func currentDwellMinutes(gymID: UUID) -> Int {
        sessions[gymID]?.dwellMinutes(asOf: .now) ?? 0
    }

    func isVerified(gymID: UUID, requiredMinutes: Int) async -> Bool {
        guard let session = sessions[gymID] else { return false }

        let dwellMinutes = session.dwellMinutes(asOf: .now)
        guard dwellMinutes >= requiredMinutes else { return false }

        let window = DateInterval(start: session.enteredAt, end: session.exitedAt ?? .now)
        guard window.duration > 0 else { return false }

        if await isAutomotive(during: window) {
            logger.notice(
                "Gym dwell for \(gymID.uuidString, privacy: .public) failed anti-cheat: automotive activity detected during dwell window."
            )
            return false
        }

        // Opportunistic corroboration only — never gates the result above. See
        // `elevatedHeartRateDuringDwell`'s doc comment for why `nil` must not count as "false".
        if let elevated = await elevatedHeartRateDuringDwell(window) {
            sessions[gymID]?.healthKitCorroborated = elevated
        }

        await recordCompletionIfNeeded(gymID: gymID, dwellMinutes: dwellMinutes)
        return true
    }

    func lastHealthKitCorroboration(gymID: UUID) -> Bool? {
        sessions[gymID]?.healthKitCorroborated
    }

    // MARK: Geofencing (CLMonitor)

    /// `CLMonitor`'s exact surface below (`CLMonitor.CircularGeographicCondition`, the
    /// `.satisfied`/`.unsatisfied`/`.unknown`/`.unmonitored` `CLMonitor.State` cases, and
    /// `add(_:identifier:assuming:)`) was confirmed against third-party write-ups of Apple's
    /// WWDC23 "Meet Core Location Monitor" session while writing this file (no Mac/Xcode in this
    /// environment to check the live SDK directly — CLAUDE.md working rule 5). Believed correct;
    /// flagged in this session's `knownIssues` for a real-SDK check on first build regardless.
    private func armGeofence(for gym: Gym) async {
        requestLocationAuthorizationIfNeeded()

        let clMonitor = await currentMonitor()
        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: gym.lat, longitude: gym.lng),
            radius: CLLocationDistance(gym.radiusMeters)
        )
        await clMonitor.add(condition, identifier: gym.id.uuidString, assuming: .unsatisfied)
        ensureEventLoopRunning()
    }

    private func currentMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor(Self.monitorName)
        monitor = created
        return created
    }

    private func ensureEventLoopRunning() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            await self?.consumeMonitorEvents()
        }
    }

    private func consumeMonitorEvents() async {
        guard let monitor else { return }
        do {
            for try await event in await monitor.events {
                guard let gymID = UUID(uuidString: event.identifier) else { continue }
                switch event.state {
                case .satisfied:
                    handleRegionEntered(gymID: gymID)
                case .unsatisfied:
                    handleRegionExited(gymID: gymID)
                    // Completion must not depend on a screen polling `isVerified`: leaving the gym
                    // after the required dwell verifies (and logs) the workout on its own.
                    _ = await isVerified(gymID: gymID, requiredMinutes: requiredDwellMinutes())
                case .unknown, .unmonitored:
                    // Transient/undetermined states (e.g. right after `add`, before Core
                    // Location has a fix, or the 20-region cap was hit). Deliberately not
                    // treated as an exit — doing so could truncate a real dwell session on a
                    // momentary state flap.
                    logger.debug(
                        "Gym \(gymID.uuidString, privacy: .public) geofence condition state: \(String(describing: event.state), privacy: .public)"
                    )
                @unknown default:
                    break
                }
            }
        } catch {
            logger.error("CLMonitor event stream ended with an error: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleRegionEntered(gymID: UUID) {
        guard let existing = sessions[gymID], existing.isActive else {
            // Either never tracked, or a previous session had already exited — start a fresh
            // dwell window rather than resuming the old one, so "drive past, leave, come back"
            // can't be stitched into one long dwell.
            sessions[gymID] = DwellSession(gymID: gymID, enteredAt: .now)
            return
        }
        // Already actively dwelling; nothing to do.
    }

    private func handleRegionExited(gymID: UUID) {
        guard sessions[gymID]?.exitedAt == nil else { return }
        sessions[gymID]?.exitedAt = .now
    }

    /// Gym Setup (App/Features/GymSetup, another session) is expected to have already prompted
    /// for `.authorizedAlways` when the user first saves a gym — background region monitoring
    /// across app restarts needs Always, not When-In-Use, to reliably wake the app. This is a
    /// safety-net request (a no-op once authorization is already determined) so a `CLMonitor`
    /// condition added here isn't silently useless with zero record of why.
    ///
    /// A newer alternative worth evaluating once a device is available: `CLServiceSession` /
    /// `CLBackgroundActivitySession` (iOS 17+) can grant background location work under
    /// `.whenInUse` for some scenarios without the full Always prompt. Left unimplemented here —
    /// the exact interaction between those session types and `CLMonitor`'s background wake
    /// reliability for a fully-backgrounded region entry is not something this session could
    /// verify without a device; see knownIssues.
    private func requestLocationAuthorizationIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if status != .authorizedAlways {
            logger.notice(
                "Gym geofencing armed without .authorizedAlways (status: \(String(describing: status), privacy: .public)); background dwell detection will be unreliable until Gym Setup obtains Always authorization."
            )
        }
    }

    private func fetchGym(id: UUID) -> Gym? {
        let context = ModelContext(ModelContainer.appGroup)
        let descriptor = FetchDescriptor<Gym>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: Completion (spec §3 gym row → GoalEvent, then GoalCompletionCoordinator)

    /// Writes the day's workout `.complete` (`source: .geofence`) the first time this dwell
    /// verifies, then hands off to `GoalCompletionCoordinator` (unlock, streak, Time Bank). The
    /// flag is set before any `await` so a second concurrent `isVerified` can't log twice.
    private func recordCompletionIfNeeded(gymID: UUID, dwellMinutes: Int) async {
        guard let session = sessions[gymID], !session.completionLogged else { return }
        sessions[gymID]?.completionLogged = true
        guard let goalID = writeCompletion(
            gymID: gymID,
            dwellMinutes: dwellMinutes,
            heartRateCorroborated: session.healthKitCorroborated
        ) else { return }
        await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
    }

    /// Returns the gym goal's id when a completion exists for today (written now or earlier), or
    /// `nil` if there's no active gym goal or the save failed.
    private func writeCompletion(gymID: UUID, dwellMinutes: Int, heartRateCorroborated: Bool?) -> UUID? {
        let context = ModelContext(ModelContainer.appGroup)
        guard let goal = activeGymGoal(in: context) else {
            logger.notice("Gym dwell verified but no active gym goal exists; nothing to log.")
            return nil
        }
        let goalID = goal.id
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let todays = (try? context.fetch(FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= startOfDay }
        ))) ?? []
        if todays.contains(where: { $0.goal?.id == goalID && $0.kind == .complete }) {
            return goalID
        }

        var meta: [String: JSONValue] = [
            "gymID": .string(gymID.uuidString),
            "dwellMinutes": .number(Double(dwellMinutes)),
        ]
        if let heartRateCorroborated {
            meta["heartRateCorroborated"] = .bool(heartRateCorroborated)
        }
        let event = GoalEvent(
            kind: .complete,
            value: Double(dwellMinutes),
            source: .geofence,
            verified: true,
            meta: .object(meta),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save gym workout GoalEvent: \(String(describing: error), privacy: .public)")
            return nil
        }
        return goalID
    }

    /// The gym goal's dwell target (`targetValue`, minutes), else spec §3's default 35 — the same
    /// fallback Today uses when it polls `isVerified`.
    private func requiredDwellMinutes() -> Int {
        let context = ModelContext(ModelContainer.appGroup)
        guard let minutes = activeGymGoal(in: context)?.targetValue, minutes > 0 else {
            return GymVerificationDefaults.requiredDwellMinutes
        }
        return Int(minutes)
    }

    /// The newest active `.workoutGym` goal. The enum comparison is done in Swift, not
    /// `#Predicate` (this codebase's usual SwiftData conservatism).
    private func activeGymGoal(in context: ModelContext) -> Goal? {
        let goals = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.active }))) ?? []
        return goals
            .filter { $0.type == .workoutGym }
            .max { $0.createdAt < $1.createdAt }
    }

    // MARK: Anti-cheat — Core Motion automotive check

    /// `true` if Core Motion's historical activity classification shows automotive travel with
    /// at least `.medium` confidence anywhere in `window` (spec §3 anti-cheat: "can't be in car
    /// (Core Motion automotive)"). `.low`-confidence automotive samples are noise (e.g. briefly
    /// stopped at a light half a block from the gym) and are deliberately not enough to fail
    /// anti-cheat on their own. Requires the "Motion & Fitness" usage description
    /// (`NSMotionUsageDescription`) in the app target's Info.plist — a project.yml/App-target
    /// concern, not this file's.
    private func isAutomotive(during window: DateInterval) async -> Bool {
        guard CMMotionActivityManager.isActivityAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            motionActivityManager.queryActivityStarting(from: window.start, to: window.end, to: .main) { activities, error in
                guard let activities, error == nil else {
                    continuation.resume(returning: false)
                    return
                }
                let automotive = activities.contains { $0.automotive && $0.confidence != .low }
                continuation.resume(returning: automotive)
            }
        }
    }

    // MARK: Optional corroboration — HealthKit elevated heart rate

    /// Returns `true`/`false` when HealthKit actually had heart-rate samples to judge, `nil` when
    /// it cannot answer — HealthKit unavailable on this device, or (the common case) the app was
    /// never granted read access. HealthKit deliberately does not let an app distinguish "read
    /// access denied" from "never asked": `HKHealthStore.authorizationStatus(for:)` only reports
    /// *write*/share status, never read status, and a denied-read query simply returns zero
    /// samples — indistinguishable from "no data exists". Treating that as `nil` (rather than
    /// `false`) is what keeps this a corroborating signal instead of quietly becoming a phantom
    /// reason `isVerified` could fail for reasons the user could never see or fix — CLAUDE.md:
    /// "never a form", and by the same spirit, never an invisible gate either.
    private func elevatedHeartRateDuringDwell(_ window: DateInterval) async -> Bool? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil, let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let elevated = quantitySamples.contains {
                    $0.quantity.doubleValue(for: bpmUnit) >= GymVerificationDefaults.elevatedHeartRateBPM
                }
                continuation.resume(returning: elevated)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - DwellSession

/// One in-progress or just-finished dwell window for a gym. Plain value type held inside
/// `GymDwellState`'s dictionary — never shared outside the actor.
private struct DwellSession {
    let gymID: UUID
    let enteredAt: Date
    var exitedAt: Date?
    /// Last opportunistic HealthKit corroboration result for this session, read back via
    /// `GymVerifier.lastHealthKitCorroboration(gymID:)`.
    var healthKitCorroborated: Bool?

    /// Set once this dwell's workout `.complete` was written, so it's logged at most once.
    var completionLogged = false

    var isActive: Bool { exitedAt == nil }

    func dwellMinutes(asOf now: Date) -> Int {
        let end = exitedAt ?? now
        return max(0, Int(end.timeIntervalSince(enteredAt) / 60))
    }
}
