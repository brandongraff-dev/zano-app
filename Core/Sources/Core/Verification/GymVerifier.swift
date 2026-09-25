// Core/Sources/Core/Verification/GymVerifier.swift
//
// docs/spec.md §3 "Goal Catalog & Verification" — "Workout (gym)" row (Tier A):
//   How it's verified: "Geofence arrival at saved gym + minimum dwell (default 35 min) +
//   HealthKit workout OR elevated HR during dwell"
//   Anti-cheat: "Dwell time; HR/motion check; can't be in car (Core Motion automotive);
//   parking-lot detection via GPS accuracy radius"
// docs/spec.md §24 "Location": When In Use first, Always only at gym setup with a clear
// explanation, and a manual check-in fallback — `recordManualCheckIn(gymID:)` below is that
// fallback's single write path (Tier C, `source: .manual`, flagged `tier: "C"` in `meta`).
//
// SYSTEM CONTRACTS (orchestrator-fixed public shape, unchanged):
//   final class GymVerifier {
//       static let shared = GymVerifier()
//       func beginDwellTracking(gymID: UUID) async
//       func currentDwellMinutes(gymID: UUID) async -> Int
//       func isVerified(gymID: UUID, requiredMinutes: Int) async -> Bool
//   }
//
// Wave 1A additions (all additive):
//   * `syncMonitoredGyms()` — one `CLMonitor` condition per *confirmed* gym, re-created at every
//     launch by `GymPresenceService.start()`. A `CLMonitor` must be re-opened (same name) and its
//     `events` consumed right after launch, or a background relaunch for a region event delivers
//     nothing.
//   * Region entry now starts dwell on its own (it always did inside `handleRegionEntered`, but
//     nothing armed the monitor until someone tapped "verify at gym").
//   * `startCheckIn(gymID:)` — the honest version of "start": it only starts the clock when the
//     geofence says the phone is inside. `beginDwellTracking` now forwards to it, so a tap at home
//     no longer counts home time as gym time.
//   * `presenceEvents()` — entered / exited / verified, for the presence service (Live Activity,
//     notifications, the check-in screen).
//   * Sessions persist to the App Group defaults, so a process that iOS killed mid-workout and
//     relaunched for the exit event still knows when the user arrived.
//   * The silent `requestAlwaysAuthorization()` is gone: the Gym Setup UI asks, after a primer.
//
// Concurrency: `GymVerifier` is a `final class` with one `let` (an actor), so it is `Sendable`
// without `@unchecked`; every mutable field lives on `GymDwellState`.

import Foundation
import CoreLocation
import CoreMotion
import HealthKit
import SwiftData
import os

/// Tunable constants for gym verification, shared by Gym Setup, the Live Activity and
/// `AdaptiveGoalEngine` so the spec's numbers live in one place.
public enum GymVerificationDefaults {
    /// docs/spec.md §3: "minimum dwell (default 35 min)".
    public static let requiredDwellMinutes = 35
    /// Heart-rate threshold (BPM) for the "elevated HR during dwell" corroboration signal. The
    /// spec gives no number; conservatively low so it under- rather than over-claims.
    public static let elevatedHeartRateBPM = 100.0
    /// Geofence radius bounds the setup UI offers (the old Settings slider's range).
    public static let minimumRadiusMeters = 50
    public static let maximumRadiusMeters = 500
    public static let defaultRadiusMeters = 150
}

// MARK: - Public value types

/// What the geofence currently says about one gym.
public enum GymRegionState: Sendable, Equatable {
    case inside
    case outside
    /// Not monitored yet, or Core Location has no answer (no fix, no permission).
    case unknown
}

/// A change the presence layer reacts to.
public enum GymPresenceEvent: Sendable, Equatable {
    /// A dwell clock started (region entry, or a check-in started while inside).
    case entered(gymID: UUID)
    /// The phone left the geofence. `dwellMinutes` is the finished session's length.
    case exited(gymID: UUID, dwellMinutes: Int)
    /// The dwell passed its target and anti-cheat, and the day's workout completion was written.
    case verified(gymID: UUID, dwellMinutes: Int)
}

/// A read-only copy of one dwell session.
public struct GymDwellSnapshot: Sendable, Equatable {
    public let gymID: UUID
    public let enteredAt: Date
    public let exitedAt: Date?
    public let dwellMinutes: Int
    public let heartRateCorroborated: Bool?
    /// `true` once this session verified and logged the workout.
    public let isVerified: Bool

    public var isActive: Bool { exitedAt == nil }
}

/// Result of `startCheckIn(gymID:)`.
public enum GymCheckInStartResult: Sendable, Equatable {
    /// Inside the geofence: the dwell clock is running now.
    case started
    /// A dwell for this gym was already running.
    case alreadyRunning
    /// The geofence says the phone isn't at the gym (or can't tell yet). The monitor is armed, so
    /// the clock starts on its own the moment the phone arrives.
    case notAtGym
    /// No saved, confirmed gym with that id.
    case unavailable
}

/// Result of `recordManualCheckIn(gymID:)` (spec §24's manual fallback, Tier C).
public enum GymManualCheckInResult: Sendable, Equatable {
    case recorded
    /// The one manual check-in allowed per day was already used.
    case alreadyUsedToday
    /// Today's gym workout is already complete (verified or manual) — nothing to add.
    case alreadyCompletedToday
    /// No active gym goal to log against.
    case noGymGoal
    case failed
}

// MARK: - GymVerifier

/// Verifies the Workout (gym) goal (docs/spec.md §3, Tier A):
///
/// 1. **Geofence + dwell** (hard requirement) — a `CLMonitor` condition per confirmed `Gym`, with
///    a running dwell clock while the phone stays inside it.
/// 2. **Anti-cheat** (hard requirement) — no medium-or-higher-confidence automotive activity
///    during the dwell window (spec: "can't be in car").
/// 3. **HealthKit corroboration** (soft signal, never blocking) — elevated heart rate raises
///    confidence and is recorded in `GoalEvent.meta`; missing HealthKit access never blocks.
public final class GymVerifier: Sendable {
    public static let shared = GymVerifier()

    private let state: GymDwellState

    /// Internal for tests — production code always uses `.shared`.
    init(state: GymDwellState = GymDwellState()) {
        self.state = state
    }

    // MARK: Contract surface

    /// Arms the geofence for `gymID` and starts the dwell clock if the phone is inside it. Kept
    /// for existing callers; identical to `startCheckIn(gymID:)` minus the result. Idempotent.
    /// Only confirmed gyms are ever tracked (`Gym.confirmed`'s contract).
    public func beginDwellTracking(gymID: UUID) async {
        _ = await state.startCheckIn(gymID: gymID)
    }

    /// Minutes in the current (or most recently ended) dwell session for `gymID`; `0` if none.
    public func currentDwellMinutes(gymID: UUID) async -> Int {
        await state.currentDwellMinutes(gymID: gymID)
    }

    /// `true` once dwell ≥ `requiredMinutes` **and** Core Motion shows no automotive travel during
    /// the window. The first `true` for a dwell writes the day's `.complete` `GoalEvent`
    /// (`source: .geofence`) and calls `GoalCompletionCoordinator`. The same check runs on its own
    /// when the geofence reports the user leaving.
    public func isVerified(
        gymID: UUID,
        requiredMinutes: Int = GymVerificationDefaults.requiredDwellMinutes
    ) async -> Bool {
        await state.isVerified(gymID: gymID, requiredMinutes: requiredMinutes)
    }

    /// Last HealthKit elevated-HR result for `gymID`'s session: `nil` until HealthKit had samples
    /// to judge (or if it never will — denied read access looks like "no data").
    public func lastHealthKitCorroboration(gymID: UUID) async -> Bool? {
        await state.lastHealthKitCorroboration(gymID: gymID)
    }

    /// `currentDwellMinutes`/`isVerified` bundled into the Live Activity's `ContentState`.
    public func currentContentState(
        gymID: UUID,
        requiredMinutes: Int = GymVerificationDefaults.requiredDwellMinutes
    ) async -> GymDwellActivityAttributes.ContentState {
        let verified = await isVerified(gymID: gymID, requiredMinutes: requiredMinutes)
        let snapshot = await dwellSnapshot(gymID: gymID)
        return GymDwellActivityAttributes.ContentState(
            elapsedMinutes: snapshot?.dwellMinutes ?? 0,
            verifiedAtMinutes: requiredMinutes,
            isVerified: verified,
            enteredAt: snapshot?.isActive == true ? snapshot?.enteredAt : nil
        )
    }

    // MARK: Presence (Wave 1A)

    /// Re-opens the gym `CLMonitor` and makes its conditions match the saved, confirmed gyms
    /// (adds new ones, re-adds moved/resized ones, removes deleted/unconfirmed ones), then starts
    /// consuming its events. Call at launch and after any gym is saved, edited or deleted.
    /// Never asks for location permission — the Gym Setup UI does that after its primer.
    public func syncMonitoredGyms() async {
        await state.syncMonitoredGyms()
    }

    /// Starts the dwell clock if the geofence says the phone is at `gymID`; otherwise arms the
    /// monitor so arrival starts it. See `GymCheckInStartResult`.
    @discardableResult
    public func startCheckIn(gymID: UUID) async -> GymCheckInStartResult {
        await state.startCheckIn(gymID: gymID)
    }

    /// The geofence's current answer for `gymID`.
    public func regionState(gymID: UUID) async -> GymRegionState {
        await state.regionState(gymID: gymID)
    }

    /// The current (or most recent, today) dwell session for `gymID`, if any.
    public func dwellSnapshot(gymID: UUID) async -> GymDwellSnapshot? {
        await state.snapshot(gymID: gymID)
    }

    /// A fresh stream of presence events. Single consumer: calling this again finishes the
    /// previous stream. `GymPresenceService` is the consumer in the app.
    public func presenceEvents() async -> AsyncStream<GymPresenceEvent> {
        await state.makePresenceStream()
    }

    /// Re-checks HealthKit for elevated heart rate during `gymID`'s running session (for the
    /// check-in screen's HR chip). Returns the stored result; `nil` when HealthKit can't say.
    @discardableResult
    public func refreshHeartRateCorroboration(gymID: UUID) async -> Bool? {
        await state.refreshHeartRateCorroboration(gymID: gymID)
    }

    /// The gym goal's dwell target in minutes (its `targetValue`), else spec §3's 35.
    public func requiredDwellMinutes() async -> Int {
        await state.requiredDwellMinutes()
    }

    // MARK: Manual fallback (spec §24)

    /// Writes an honest Tier C gym completion: a verified `.complete` `GoalEvent` with
    /// `source: .manual` and `meta: {"tier": "C"}`, then calls `GoalCompletionCoordinator`.
    /// Limited to one per day, and refused when today's gym goal is already complete.
    public func recordManualCheckIn(gymID: UUID?) async -> GymManualCheckInResult {
        await state.recordManualCheckIn(gymID: gymID)
    }
}

// MARK: - GymDwellState

/// Owns every mutable piece of gym-verification state: dwell sessions (persisted), the
/// `CLMonitor` and its event task, the presence stream, and the Motion/HealthKit calls. State is
/// mutated in synchronous methods; only framework calls are `async`.
actor GymDwellState {
    private var sessions: [UUID: DwellSession]

    /// Lazily re-opened with the same name on first use; `CLMonitor` reloads its saved conditions
    /// from disk (WWDC23 "Meet Core Location Monitor").
    private var monitor: CLMonitor?
    private var eventTask: Task<Void, Never>?
    private var presenceContinuation: AsyncStream<GymPresenceEvent>.Continuation?

    private let motionActivityManager = CMMotionActivityManager()
    private let healthStore = HKHealthStore()

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GymVerifier")

    private static let monitorName = "com.zano.app.gymMonitor"
    private static let sessionsDefaultsKey = "zano.gym.dwellSessions.v1"

    init() {
        sessions = Self.loadPersistedSessions()
    }

    // MARK: Check-in

    func startCheckIn(gymID: UUID) async -> GymCheckInStartResult {
        if let existing = sessions[gymID], existing.isActive {
            return .alreadyRunning
        }
        guard let gym = fetchGym(id: gymID), gym.confirmed else {
            logger.notice("startCheckIn called for a missing or unconfirmed gym \(gymID.uuidString, privacy: .public).")
            return .unavailable
        }
        let geometry = GymGeometry(gym)
        await arm(geometry)
        guard await regionState(gymID: gymID) == .inside else {
            return .notAtGym
        }
        // Re-check after the suspension: the event loop may have started it meanwhile.
        if let existing = sessions[gymID], existing.isActive {
            return .alreadyRunning
        }
        startSession(gymID: gymID)
        return .started
    }

    func currentDwellMinutes(gymID: UUID) -> Int {
        sessions[gymID]?.dwellMinutes(asOf: .now) ?? 0
    }

    func snapshot(gymID: UUID) -> GymDwellSnapshot? {
        guard let session = sessions[gymID] else { return nil }
        return GymDwellSnapshot(
            gymID: gymID,
            enteredAt: session.enteredAt,
            exitedAt: session.exitedAt,
            dwellMinutes: session.dwellMinutes(asOf: .now),
            heartRateCorroborated: session.healthKitCorroborated,
            isVerified: session.completionLogged
        )
    }

    func isVerified(gymID: UUID, requiredMinutes: Int) async -> Bool {
        guard let session = sessions[gymID] else { return false }
        if session.completionLogged { return true }

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

        // Opportunistic corroboration only — never gates the result above.
        if let elevated = await elevatedHeartRateDuringDwell(window) {
            sessions[gymID]?.healthKitCorroborated = elevated
            persistSessions()
        }

        await recordCompletionIfNeeded(gymID: gymID, dwellMinutes: dwellMinutes)
        return true
    }

    func lastHealthKitCorroboration(gymID: UUID) -> Bool? {
        sessions[gymID]?.healthKitCorroborated
    }

    func refreshHeartRateCorroboration(gymID: UUID) async -> Bool? {
        guard let session = sessions[gymID] else { return nil }
        let window = DateInterval(start: session.enteredAt, end: session.exitedAt ?? .now)
        guard window.duration > 0 else { return session.healthKitCorroborated }
        if let elevated = await elevatedHeartRateDuringDwell(window) {
            // Only ever upgrade: once HR was elevated this session, a later quiet sample doesn't
            // un-corroborate it.
            let merged = (sessions[gymID]?.healthKitCorroborated == true) || elevated
            sessions[gymID]?.healthKitCorroborated = merged
            persistSessions()
        }
        return sessions[gymID]?.healthKitCorroborated
    }

    // MARK: Presence stream

    func makePresenceStream() -> AsyncStream<GymPresenceEvent> {
        presenceContinuation?.finish()
        let (stream, continuation) = AsyncStream<GymPresenceEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        presenceContinuation = continuation
        return stream
    }

    private func emit(_ event: GymPresenceEvent) {
        presenceContinuation?.yield(event)
    }

    // MARK: Geofencing (CLMonitor)

    /// `CLMonitor` surface used here — `init(_:)`, `add(_:identifier:assuming:)`,
    /// `remove(_:)`, `identifiers`, `record(for:)`, `events`, `CircularGeographicCondition` and
    /// the `CLMonitor.Event.State` cases — is iOS 17.0+. Unverified against a device.
    func syncMonitoredGyms() async {
        let wanted = fetchConfirmedGymGeometries()
        let clMonitor = await currentMonitor()
        let wantedIDs = Set(wanted.map(\.identifier))

        for identifier in await clMonitor.identifiers where !wantedIDs.contains(identifier) {
            await clMonitor.remove(identifier)
            if let gymID = UUID(uuidString: identifier) {
                sessions[gymID] = nil
            }
        }
        persistSessions()

        for geometry in wanted {
            await arm(geometry, using: clMonitor)
        }
        ensureEventLoopRunning()
    }

    func regionState(gymID: UUID) async -> GymRegionState {
        guard let monitor else { return .unknown }
        guard let record = await monitor.record(for: gymID.uuidString) else { return .unknown }
        switch record.lastEvent.state {
        case .satisfied: return .inside
        case .unsatisfied: return .outside
        default: return .unknown
        }
    }

    private func arm(_ geometry: GymGeometry) async {
        let clMonitor = await currentMonitor()
        await arm(geometry, using: clMonitor)
        ensureEventLoopRunning()
    }

    /// Adds the condition unless an identical one is already monitored. Re-adding an unchanged
    /// condition would reset its state to the assumed `.unsatisfied`, which could briefly read as
    /// "left the gym" mid-workout — so unchanged conditions are left alone.
    private func arm(_ geometry: GymGeometry, using clMonitor: CLMonitor) async {
        if let record = await clMonitor.record(for: geometry.identifier),
           let existing = record.condition as? CLMonitor.CircularGeographicCondition,
           geometry.matches(existing) {
            return
        }
        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: geometry.latitude, longitude: geometry.longitude),
            radius: CLLocationDistance(geometry.radiusMeters)
        )
        await clMonitor.add(condition, identifier: geometry.identifier, assuming: .unsatisfied)
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
                    // Verify before emitting the exit, so a dwell that met its target reports
                    // `.verified` first and the presence layer never shows "left early" for it.
                    let wasActive = sessions[gymID]?.isActive == true
                    handleRegionExited(gymID: gymID)
                    _ = await isVerified(gymID: gymID, requiredMinutes: requiredDwellMinutes())
                    if wasActive {
                        emit(.exited(gymID: gymID, dwellMinutes: currentDwellMinutes(gymID: gymID)))
                    }
                case .unknown, .unmonitored:
                    // Transient states (right after `add`, no fix, region cap). Not an exit — a
                    // state flap must not truncate a real dwell.
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
        eventTask = nil
    }

    private func handleRegionEntered(gymID: UUID) {
        if let existing = sessions[gymID], existing.isActive { return }
        // Never tracked, or the previous session already exited: a fresh window, so "drive past,
        // leave, come back" can't be stitched into one long dwell.
        startSession(gymID: gymID)
    }

    private func handleRegionExited(gymID: UUID) {
        guard sessions[gymID]?.isActive == true else { return }
        sessions[gymID]?.exitedAt = .now
        persistSessions()
    }

    private func startSession(gymID: UUID) {
        sessions[gymID] = DwellSession(gymID: gymID, enteredAt: .now)
        persistSessions()
        emit(.entered(gymID: gymID))
    }

    // MARK: SwiftData reads

    private func fetchGym(id: UUID) -> Gym? {
        let context = ModelContext(ModelContainer.appGroup)
        let descriptor = FetchDescriptor<Gym>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchConfirmedGymGeometries() -> [GymGeometry] {
        let context = ModelContext(ModelContainer.appGroup)
        let gyms = (try? context.fetch(FetchDescriptor<Gym>(predicate: #Predicate { $0.confirmed }))) ?? []
        return gyms.map(GymGeometry.init)
    }

    // MARK: Completion (spec §3 gym row → GoalEvent, then GoalCompletionCoordinator)

    /// Writes the day's `.complete` (`source: .geofence`) the first time this dwell verifies, then
    /// hands off to `GoalCompletionCoordinator`. The flag is set before any `await` so a second
    /// concurrent `isVerified` can't log twice.
    private func recordCompletionIfNeeded(gymID: UUID, dwellMinutes: Int) async {
        guard let session = sessions[gymID], !session.completionLogged else { return }
        sessions[gymID]?.completionLogged = true
        persistSessions()
        guard let goalID = writeCompletion(
            gymID: gymID,
            dwellMinutes: dwellMinutes,
            heartRateCorroborated: session.healthKitCorroborated
        ) else { return }
        emit(.verified(gymID: gymID, dwellMinutes: dwellMinutes))
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
        if todaysEvents(for: goalID, in: context).contains(where: { $0.verified && $0.kind == .complete }) {
            return goalID
        }

        var meta: [String: JSONValue] = [
            "gymID": .string(gymID.uuidString),
            "dwellMinutes": .number(Double(dwellMinutes)),
            "tier": .string(VerificationTier.a.rawValue),
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

    func recordManualCheckIn(gymID: UUID?) async -> GymManualCheckInResult {
        let (result, goalID) = writeManualCheckIn(gymID: gymID)
        if result == .recorded, let goalID {
            await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
        }
        return result
    }

    private func writeManualCheckIn(gymID: UUID?) -> (GymManualCheckInResult, UUID?) {
        let context = ModelContext(ModelContainer.appGroup)
        guard let goal = activeGymGoal(in: context) else { return (.noGymGoal, nil) }
        let goalID = goal.id
        let todays = todaysEvents(for: goalID, in: context)
        if todays.contains(where: { $0.source == .manual && $0.kind == .complete }) {
            return (.alreadyUsedToday, goalID)
        }
        if todays.contains(where: { $0.verified && $0.kind == .complete }) {
            return (.alreadyCompletedToday, goalID)
        }

        var meta: [String: JSONValue] = ["tier": .string(VerificationTier.c.rawValue)]
        if let gymID {
            meta["gymID"] = .string(gymID.uuidString)
        }
        let event = GoalEvent(
            kind: .complete,
            source: .manual,
            verified: true,
            meta: .object(meta),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save manual gym check-in: \(String(describing: error), privacy: .public)")
            return (.failed, goalID)
        }
        return (.recorded, goalID)
    }

    /// Today's events for `goalID`. Goal matching is done in Swift, not `#Predicate` (this
    /// codebase's usual SwiftData conservatism about relationship key paths).
    private func todaysEvents(for goalID: UUID, in context: ModelContext) -> [GoalEvent] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let events = (try? context.fetch(FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= startOfDay }
        ))) ?? []
        return events.filter { $0.goal?.id == goalID }
    }

    /// The gym goal's dwell target (`targetValue`, minutes), else spec §3's default 35.
    func requiredDwellMinutes() -> Int {
        let context = ModelContext(ModelContainer.appGroup)
        guard let minutes = activeGymGoal(in: context)?.targetValue, minutes > 0 else {
            return GymVerificationDefaults.requiredDwellMinutes
        }
        return Int(minutes)
    }

    /// The newest active `.workoutGym` goal. Enum comparison in Swift, not `#Predicate`.
    private func activeGymGoal(in context: ModelContext) -> Goal? {
        let goals = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.active }))) ?? []
        return goals
            .filter { $0.type == .workoutGym }
            .max { $0.createdAt < $1.createdAt }
    }

    // MARK: Persistence (App Group defaults)

    private func persistSessions() {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return }
        let stored = Array(sessions.values)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.sessionsDefaultsKey)
        }
    }

    /// Today's sessions only — yesterday's dwell never carries into today.
    private static func loadPersistedSessions() -> [UUID: DwellSession] {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier),
              let data = defaults.data(forKey: sessionsDefaultsKey),
              let stored = try? JSONDecoder().decode([DwellSession].self, from: data)
        else { return [:] }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        var result: [UUID: DwellSession] = [:]
        for session in stored where session.enteredAt >= startOfDay {
            result[session.gymID] = session
        }
        return result
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


// MARK: - Value types

/// A gym's geofence as plain `Sendable` values, read out of SwiftData inside the actor.
private struct GymGeometry: Sendable {
    let identifier: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int

    init(_ gym: Gym) {
        identifier = gym.id.uuidString
        latitude = gym.lat
        longitude = gym.lng
        radiusMeters = gym.radiusMeters
    }

    /// Same place and size, within float noise (a ~1 m tolerance).
    func matches(_ condition: CLMonitor.CircularGeographicCondition) -> Bool {
        abs(condition.center.latitude - latitude) < 0.00001
            && abs(condition.center.longitude - longitude) < 0.00001
            && abs(condition.radius - CLLocationDistance(radiusMeters)) < 1
    }
}

/// One in-progress or just-finished dwell window for a gym. Codable so it survives a relaunch.
private struct DwellSession: Codable {
    let gymID: UUID
    let enteredAt: Date
    var exitedAt: Date?
    var healthKitCorroborated: Bool?
    /// Set once this dwell's workout `.complete` was written, so it's logged at most once.
    var completionLogged = false

    init(gymID: UUID, enteredAt: Date) {
        self.gymID = gymID
        self.enteredAt = enteredAt
    }

    var isActive: Bool { exitedAt == nil }

    func dwellMinutes(asOf now: Date) -> Int {
        let end = exitedAt ?? now
        return max(0, Int(end.timeIntervalSince(enteredAt) / 60))
    }
}
