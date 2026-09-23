// StretchVerifier.swift
// Core / Verification
//
// docs/spec.md §3 (Goal Catalog & Verification → "Stretch / mobility" row, Tier B):
//   How it's verified: "Guided 5-min timer with device flat on floor (accelerometer check)"
//   Anti-cheat: "Device orientation"
//
// Pattern: mirrors FocusSessionVerifier.swift's timer shape (start/end, elapsed-time
// verification against a planned duration, GoalEvent logging via the same `.timer` source) —
// both goals are "run an in-app timer, verify elapsed time" Tier A/B goals. Deliberately
// different in three ways:
//   - Fixed 5-minute duration (`StretchVerifier.sessionMinutes`), not a user-selectable preset —
//     spec says "Guided 5-min timer", not a duration picker the way Focus session's 25/50/90 is.
//   - No pause/resume and no Live Activity. docs/spec.md §6's Live Activities list enumerates
//     "Focus session", "Gym dwell", and an "earn meter" only (also §4's tech table: "Live
//     Activities | ActivityKit | Focus/gym/earn meter") — Stretch/mobility isn't among them, and
//     a 5-minute guided routine (a screen actively showing stretch instructions) doesn't need to
//     survive backgrounding the way a 25-90 min focus block does.
//   - Its own anti-cheat gate is the device-flat accelerometer check
//     (`MotionAntiCheat.isDeviceFlat`, extended onto that shared file rather than forking a
//     second motion utility — see that method's own doc comment), sampled periodically through
//     the session, instead of Focus's "leaving the app pauses timer" / phone-pickup-count signal.
//
// Uses `GoalType.stretchMobility` (Core/Sources/Core/Models/Goal.swift) — the existing case, not
// a new one. No SYSTEM CONTRACTS block named this type's shape for this task, so its public API
// is designed fresh here, following FocusSessionVerifier's/GymVerifier's own established
// conventions in this same directory rather than inventing a new one.

import Foundation
import os
import SwiftData

/// Errors `StretchVerifier` throws itself, as opposed to errors bubbled up from SwiftData.
/// Mirrors `FocusSessionVerifierError`'s two structural cases; there's no
/// `invalidPlannedMinutes` equivalent here because the stretch session's duration is fixed
/// (`StretchVerifier.sessionMinutes`), not caller-supplied.
public enum StretchVerifierError: Sendable, Equatable, LocalizedError {
    /// `startSession` was called with a `goalID` that has no matching `Goal` row in the shared
    /// App Group store. Verification always needs a real goal to attach the resulting
    /// `GoalEvent` to (docs/spec.md §13), so this fails fast at session start.
    case goalNotFound(UUID)

    /// `endSession`/`liveState` was called with a `sessionID` this verifier has no in-memory
    /// running session for — already ended, never started, or started in a different process
    /// (each app/extension process has its own `StretchVerifier.shared`; see the type's doc
    /// comment).
    case sessionNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .goalNotFound(let goalID):
            "No Goal with id \(goalID) exists locally — cannot start a stretch session for it."
        case .sessionNotFound(let sessionID):
            "No running stretch session with id \(sessionID) (already ended, or never started in this process)."
        }
    }
}

/// A point-in-time snapshot of a running stretch session, for a guided-timer UI to poll without
/// reaching into this verifier's private state. Not part of any fixed cross-module contract —
/// this type and `StretchVerifier.liveState(sessionID:)` are both owned by this file, added as a
/// convenience the same way `GymVerifier.currentContentState` is for its own callers.
public struct StretchSessionState: Sendable, Equatable {
    /// Seconds left in the fixed 5-minute countdown, clamped to `0` once elapsed.
    public let secondsRemaining: Int
    /// The most recent device-flat sample taken during this session, or `nil` before the first
    /// tick has run. Not itself the anti-cheat verdict — a single non-flat sample (adjusting into
    /// position) doesn't fail the session; see `flatRatio`.
    public let isCurrentlyFlat: Bool?
    /// Fraction (0...1) of ticks so far where the device was flat. `endSession` gates
    /// verification on this being at least `StretchVerifier.requiredFlatRatio` by the time the
    /// session ends. `1.0` before the first tick (nothing to fail yet) — fail-open, matching
    /// `MotionAntiCheat`'s own convention.
    public let flatRatio: Double
}

/// Runs the guided 5-minute stretch/mobility timer (docs/spec.md §3 Stretch/mobility row), and on
/// end verifies the session against two independent gates: elapsed time >= the planned 5 minutes,
/// **and** the device stayed flat for at least `requiredFlatRatio` of the sampled ticks. Logs the
/// result as a `GoalEvent` (docs/spec.md §13) either way — a miss is as real a training row as a
/// completion, matching `FocusSessionVerifier.logOutcome`'s own doc comment on this point.
///
/// `@MainActor`, not a plain `actor`: same reasoning as `FocusSessionVerifier` — this type owns
/// an unstructured `Task`-based tick loop for a foreground, UI-adjacent guided routine (the
/// stretch screen is expected to be actively showing instructions/countdown while this runs), so
/// confining its mutable state to the main actor is the simplest correct choice per this
/// session's `write-swift` guidance ("shared mutable state → actor, or `@MainActor` class") while
/// keeping `StretchVerifier` itself trivially `Sendable` (`@MainActor final class` is implicitly
/// `Sendable`) for any-isolation call sites — they just hop to the main actor to call it, same as
/// any other `@MainActor` singleton.
///
/// One `StretchVerifier.shared` exists per process, same caveat as `FocusSessionVerifier.shared`:
/// fine here because only the main app ever starts/ends a guided stretch session (it needs to be
/// visibly running in-app).
@MainActor
public final class StretchVerifier {
    public static let shared = StretchVerifier()

    /// docs/spec.md §3: "Guided 5-min timer". Fixed, not a caller-chosen preset — see this file's
    /// header comment for why that's a deliberate difference from `FocusSessionPreset`.
    public static let sessionMinutes = 5

    /// Minimum fraction of sampled ticks the device must have been flat for `endSession` to count
    /// the anti-cheat gate as passed. Spec §3 says only "device flat on floor" with no numeric
    /// tolerance for brief real-world movement (getting into/out of position between stretches,
    /// adjusting a mat) — `0.7` is this file's own assumption, not sourced from spec.md. Flagged
    /// in knownIssues; tune with real usage data or an explicit product decision rather than
    /// treating it as settled.
    public static let requiredFlatRatio = 0.7

    /// How often the tick loop samples `MotionAntiCheat.isDeviceFlat`. 15 seconds gives 20
    /// samples across the full 5-minute session — frequent enough to catch a phone actually
    /// picked up and used mid-session, infrequent enough not to keep CoreMotion's accelerometer
    /// spun up continuously (`AccelerometerFlatnessState` only starts/stops it for ~250ms per
    /// sample — see `MotionAntiCheat.swift`).
    private static let sampleInterval: TimeInterval = 15

    /// One in-flight stretch session's mutable state. Private value type, same rationale as
    /// `FocusSessionVerifier.RunningSession`: kept as a struct so mutating one field is an
    /// ordinary struct mutation through the `runningSessions` dictionary rather than a second
    /// layer of reference-type bookkeeping on top of the dictionary itself.
    private struct RunningSession {
        let id: UUID
        let goalID: UUID
        let startedAt: Date

        /// `nil` while paused or once the countdown has reached zero (`tick` cancels its own
        /// loop at that point); `endSession` cancels it explicitly otherwise. No pause/resume
        /// here (unlike `FocusSessionVerifier`) — see this file's header comment.
        var tickTask: Task<Void, Never>?

        /// Most recent `MotionAntiCheat.isDeviceFlat` sample, surfaced via `liveState`.
        var lastFlatSample: Bool?
        var flatSampleCount: Int = 0
        var totalSampleCount: Int = 0

        /// Fail-open before any samples exist (mirrors `MotionAntiCheat`'s own convention):
        /// nothing has failed yet, so there's nothing to gate on.
        var flatRatio: Double {
            totalSampleCount == 0 ? 1.0 : Double(flatSampleCount) / Double(totalSampleCount)
        }

        /// Wall-clock time since `startedAt`. No pause to subtract (unlike
        /// `FocusSessionVerifier.RunningSession.elapsedActiveSeconds`) — a fixed 5-minute guided
        /// routine has no "leaving the app" pause concept per this file's header comment.
        func elapsedSeconds(asOf now: Date) -> TimeInterval {
            max(0, now.timeIntervalSince(startedAt))
        }
    }

    private let modelContainer: ModelContainer
    private lazy var modelContext = ModelContext(modelContainer)
    private var runningSessions: [UUID: RunningSession] = [:]
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "StretchVerifier")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Start

    /// Starts a new guided stretch session for `goalID`: begins the fixed 5-minute countdown and
    /// the periodic device-flat sampling immediately.
    ///
    /// - Parameter goalID: The `Goal.id` this session counts toward. Expected to be a
    ///   `.stretchMobility` goal, though — like `FocusSessionVerifier.startSession` — this method
    ///   doesn't itself enforce that; the caller owns picking the right goal. Must already exist
    ///   in the shared store — see `StretchVerifierError.goalNotFound`.
    /// - Returns: A new session id. Pass it to `endSession`/`liveState`.
    /// - Throws: `StretchVerifierError.goalNotFound`, or a SwiftData fetch error.
    public func startSession(goalID: UUID) async throws -> UUID {
        guard let goal = try fetchGoal(id: goalID) else {
            throw StretchVerifierError.goalNotFound(goalID)
        }
        if goal.type != .stretchMobility {
            // Non-blocking: FocusSessionVerifier/GymVerifier don't gate on `goal.type` either —
            // the caller owns picking the right goal id, and refusing here would be exactly the
            // kind of surprise failure CLAUDE.md's "never trap the user" rule warns against. Just
            // a signal for debugging a caller that wired the wrong goal id to this verifier.
            logger.notice("startSession(goalID:) called for a Goal whose type is \(String(describing: goal.type), privacy: .public), not .stretchMobility; proceeding anyway.")
        }

        let sessionID = UUID()
        runningSessions[sessionID] = RunningSession(id: sessionID, goalID: goalID, startedAt: .now)
        startTicking(for: sessionID)

        logger.notice("Started stretch session \(sessionID.uuidString, privacy: .public) for goal \(goalID.uuidString, privacy: .public).")
        return sessionID
    }

    // MARK: - Live state

    /// A snapshot of `sessionID`'s current countdown/flatness state, for a guided-timer UI to
    /// poll (e.g. on a `TimelineView`/periodic-refresh tick) rather than reaching into this
    /// verifier's private state. `nil` if `sessionID` isn't a currently-running session (already
    /// ended, or never started in this process) — deliberately not throwing, since a UI polling
    /// loop racing session end is an expected, non-exceptional case (unlike `endSession` being
    /// called twice, which is a real caller bug `StretchVerifierError.sessionNotFound` should
    /// surface).
    public func liveState(sessionID: UUID) -> StretchSessionState? {
        guard let session = runningSessions[sessionID] else { return nil }
        let plannedSeconds = TimeInterval(Self.sessionMinutes * 60)
        let remaining = max(0, Int((plannedSeconds - session.elapsedSeconds(asOf: .now)).rounded(.up)))
        return StretchSessionState(
            secondsRemaining: remaining,
            isCurrentlyFlat: session.lastFlatSample,
            flatRatio: session.flatRatio
        )
    }

    // MARK: - End

    /// Ends a running stretch session: stops the tick loop, verifies (elapsed time >= 5 minutes
    /// **and** flat ratio >= `requiredFlatRatio`), and logs a `GoalEvent` (`.complete` if
    /// verified, `.miss` otherwise — both are meaningful training rows, not just successes; see
    /// `GoalEvent.swift`'s header comment).
    ///
    /// - Returns: `true` if the session verified.
    /// - Throws: `StretchVerifierError.sessionNotFound`, or a SwiftData save error.
    public func endSession(sessionID: UUID) async throws -> Bool {
        guard var session = runningSessions[sessionID] else {
            throw StretchVerifierError.sessionNotFound(sessionID)
        }
        runningSessions.removeValue(forKey: sessionID)

        session.tickTask?.cancel()
        session.tickTask = nil

        let now = Date.now
        let elapsedSeconds = session.elapsedSeconds(asOf: now)
        let plannedSeconds = TimeInterval(Self.sessionMinutes * 60)
        let flatRatio = session.flatRatio
        let verified = elapsedSeconds >= plannedSeconds && flatRatio >= Self.requiredFlatRatio

        try logOutcome(session: session, elapsedSeconds: elapsedSeconds, flatRatio: flatRatio, verified: verified, at: now)

        logger.notice("Ended stretch session \(sessionID.uuidString, privacy: .public): elapsed \(Int(elapsedSeconds), privacy: .public)s / planned \(Int(plannedSeconds), privacy: .public)s, flatRatio=\(flatRatio, privacy: .public), verified=\(verified, privacy: .public).")
        return verified
    }

    // MARK: - Tick loop

    /// Spawns (or replaces) the unstructured per-`sampleInterval` loop for `sessionID`: samples
    /// `MotionAntiCheat.isDeviceFlat` and folds it into the running tally. Unstructured, not
    /// `async let`/a task group, for the same reason as `FocusSessionVerifier.startTicking` — a
    /// 5-minute lifetime doesn't fit a lexical scope. Synchronous on purpose: the assignment to
    /// `runningSessions[sessionID]?.tickTask` below happens before the spawned task's body gets a
    /// chance to run (no `await` sits between the two on this main-actor call stack), so there's
    /// no race with `tick(sessionID:)` reading it.
    private func startTicking(for sessionID: UUID) {
        let task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick(sessionID: sessionID)

                // Stop looping once the session was ended by someone else while we were
                // suspended below (mirrors FocusSessionVerifier.startTicking's own guard).
                guard let current = self.runningSessions[sessionID], current.tickTask != nil else { return }

                do {
                    try await Task.sleep(for: .seconds(Self.sampleInterval))
                } catch {
                    return // Cancelled mid-sleep.
                }
            }
        }
        runningSessions[sessionID]?.tickTask = task
    }

    /// One sampling step: reads `MotionAntiCheat.isDeviceFlat` and folds it into the running
    /// session's flat-ratio tally. Does not itself decide pass/fail — that's `endSession`'s job,
    /// once the full ratio across the whole session is known.
    private func tick(sessionID: UUID) async {
        guard runningSessions[sessionID] != nil else { return }
        let isFlat = await MotionAntiCheat.shared.isDeviceFlat()

        // Re-check after the `await` above: the session may have ended while this call was
        // in flight (`endSession` removes it from `runningSessions` synchronously).
        guard var session = runningSessions[sessionID] else { return }
        session.lastFlatSample = isFlat
        session.totalSampleCount += 1
        if isFlat { session.flatSampleCount += 1 }
        runningSessions[sessionID] = session
    }

    // MARK: - Persistence

    private func fetchGoal(id: UUID) throws -> Goal? {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Logs the session's outcome as a `GoalEvent` (docs/spec.md §13). Attaches it to the
    /// session's `Goal` (and that goal's `user`) when the goal can still be found — a goal
    /// deleted mid-session is an edge case, not a reason to silently drop a completed/missed
    /// session's record, so this still logs with `goal: nil, user: nil` if that lookup fails
    /// rather than throwing (same shape as `FocusSessionVerifier.logOutcome`).
    private func logOutcome(
        session: RunningSession,
        elapsedSeconds: TimeInterval,
        flatRatio: Double,
        verified: Bool,
        at now: Date
    ) throws {
        let goal = try? fetchGoal(id: session.goalID)

        let event = GoalEvent(
            ts: now,
            kind: verified ? .complete : .miss,
            value: elapsedSeconds / 60,
            source: .timer,
            verified: verified,
            meta: .object([
                "plannedMinutes": .number(Double(Self.sessionMinutes)),
                "elapsedSeconds": .number(elapsedSeconds),
                "flatRatio": .number(flatRatio),
                "flatSampleCount": .number(Double(session.flatSampleCount)),
                "totalSampleCount": .number(Double(session.totalSampleCount)),
            ]),
            user: goal?.user,
            goal: goal
        )
        modelContext.insert(event)
        try modelContext.save()
    }
}
