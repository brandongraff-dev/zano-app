// FocusSessionVerifier.swift
// Core / Verification
//
// docs/spec.md §3 (Goal Catalog & Verification → "Focus session" row, Tier A):
//   "In-app timer (25/50/90 min) with shields active; Live Activity shows countdown."
//   Anti-cheat: "Leaving the app pauses timer; phone pickup count logged."
// docs/spec.md §6 (Widgets, Controls, Live Activities, NFC, Siri → "Live Activities (ActivityKit)"):
//   "Focus session: countdown, pause, end."
//
// Implements the exact public shape from this task's SYSTEM CONTRACTS block:
//
//   final class FocusSessionVerifier {
//       static let shared = FocusSessionVerifier()
//       func startSession(goalID: UUID, plannedMinutes: Int) async throws -> UUID
//       func endSession(sessionID: UUID) async throws -> Bool
//   }
//
// so `LockEngineManager` (owned by another agent this same batch, per that file's own contract)
// and any App Intent / UI call site can call `FocusSessionVerifier.shared.startSession(...)` /
// `.endSession(...)` today, before this file exists on disk from their point of view, and keep
// compiling once it lands.

import ActivityKit
import Foundation
import os
import SwiftData

/// The 25/50/90-minute in-app timer presets from docs/spec.md §3's Focus session row. This is a
/// convenience the UI layer (Session 5, docs/spec.md §15 — "Today"/focus screens) is expected to
/// enumerate for its preset buttons; `startSession(goalID:plannedMinutes:)` itself still takes a
/// plain `Int` (per CONTRACTS) rather than this enum, so a future custom-duration entry point
/// isn't blocked on changing this file's public shape.
public enum FocusSessionPreset: Int, CaseIterable, Sendable, Codable {
    case twentyFiveMinutes = 25
    case fiftyMinutes = 50
    case ninetyMinutes = 90

    /// Same value as the raw value, spelled out for call sites that read better as
    /// `preset.minutes` than `preset.rawValue`.
    public var minutes: Int { rawValue }
}

/// Errors `FocusSessionVerifier` throws itself, as opposed to errors bubbled up from SwiftData.
public enum FocusSessionVerifierError: Sendable, Equatable, LocalizedError {
    /// `startSession(plannedMinutes:)` was called with a value that can never be reached
    /// (`<= 0`). Not restricted to the 25/50/90 presets — see `FocusSessionPreset`'s doc comment
    /// — only rejected when the timer could never complete.
    case invalidPlannedMinutes(Int)

    /// `startSession` was called with a `goalID` that has no matching `Goal` row in the shared
    /// App Group store. Verification always needs a real goal to attach the resulting
    /// `GoalEvent` to (docs/spec.md §13), so this fails fast at session start rather than
    /// discovering it after the user has already run a 90-minute timer.
    case goalNotFound(UUID)

    /// `endSession`/`pauseSession`/`resumeSession` was called with a `sessionID` this verifier
    /// has no in-memory running session for — already ended, never started, or started in a
    /// different process (each app/extension process has its own `FocusSessionVerifier.shared`;
    /// see the type's doc comment).
    case sessionNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidPlannedMinutes(let minutes):
            "Focus session planned minutes must be greater than zero (got \(minutes))."
        case .goalNotFound(let goalID):
            "No Goal with id \(goalID) exists locally — cannot start a focus session for it."
        case .sessionNotFound(let sessionID):
            "No running focus session with id \(sessionID) (already ended, or never started in this process)."
        }
    }
}

/// Runs the in-app focus-session timer (docs/spec.md §3 Focus session row), drives its
/// `FocusActivityAttributes` Live Activity end-to-end (start → tick → pause/resume → end), and on
/// end verifies the session (elapsed active time >= planned minutes) and logs the result as a
/// `GoalEvent` (docs/spec.md §13; that table is "the training table for §9 ML systems" per its
/// own header comment — every complete/miss belongs there, not just successes).
///
/// `@MainActor`, not a plain `actor`: this type owns a `Timer`-like tick loop and an ActivityKit
/// `Activity` — both are UI-adjacent, foreground-only concerns (a focus session's Live Activity
/// only usefully ticks while the app is active; see the "leaving the app pauses timer" TODO hook
/// below), so confining all of its mutable state to the main actor is the simplest correct choice
/// per this session's `write-swift` guidance ("shared mutable state → actor, or `@MainActor`
/// class") while still matching this task's CONTRACTS declaration of `FocusSessionVerifier` as a
/// `final class` (a `@MainActor final class` *is* implicitly `Sendable`, so `static let shared`
/// and every `async` method below are callable from any isolation domain exactly the way
/// CONTRACTS' other call sites assume — they just hop to the main actor to do it, the same as any
/// other `@MainActor` singleton).
///
/// One `FocusSessionVerifier.shared` exists per process. The main app and every extension that
/// links Core get their own instance — this is fine for focus sessions specifically because only
/// the main app ever starts/ends one (the timer needs to be visibly running in-app); nothing here
/// assumes cross-process state the way `SharedDefaults`/`ModelContainer.appGroup` do.
@MainActor
public final class FocusSessionVerifier {
    public static let shared = FocusSessionVerifier()

    /// One in-flight focus session's mutable state. Kept as a private value type (not a class) so
    /// mutating one field is an ordinary struct mutation through the `runningSessions` dictionary
    /// rather than a second layer of reference-type bookkeeping on top of the dictionary itself.
    private struct RunningSession {
        let id: UUID
        let goalID: UUID
        let plannedMinutes: Int
        let startedAt: Date

        /// `nil` while running; set to the moment `pauseSession` was called while paused.
        var pausedAt: Date? = nil
        /// Total time spent paused across every past pause/resume cycle in this session, not
        /// counting a pause currently in progress (that's `pausedAt`'s job — see
        /// `elapsedActiveSeconds(asOf:)`).
        var accumulatedPauseDuration: TimeInterval = 0

        /// `nil` when Live Activities are unavailable/denied (`requestLiveActivity` logs and
        /// degrades gracefully) — the timer and verification still work without one.
        var activity: Activity<FocusActivityAttributes>? = nil

        /// The unstructured per-second tick loop while this session is running and unpaused.
        /// `nil` while paused or once the countdown has reached zero (`tick` cancels its own
        /// loop at that point; `endSession`/`pauseSession` cancel it explicitly otherwise).
        var tickTask: Task<Void, Never>? = nil

        /// Wall-clock time actually spent running (i.e. excluding every pause), as of `now`.
        /// This — not raw `now.timeIntervalSince(startedAt)` — is what verification and the
        /// countdown are both measured against, so pausing (docs/spec.md §3: "Leaving the app
        /// pauses timer") genuinely stops the clock rather than just freezing the display.
        func elapsedActiveSeconds(asOf now: Date) -> TimeInterval {
            let inProgressPause = pausedAt.map { now.timeIntervalSince($0) } ?? 0
            return max(0, now.timeIntervalSince(startedAt) - accumulatedPauseDuration - inProgressPause)
        }
    }

    /// How long a finished Live Activity stays visible (showing its final "complete"/"missed"
    /// state) before the system is allowed to dismiss it, so the user actually sees the outcome
    /// instead of it vanishing the instant `endSession` returns.
    private static let activityDismissalGracePeriod: TimeInterval = 5

    private let modelContainer: ModelContainer
    private lazy var modelContext = ModelContext(modelContainer)
    private var runningSessions: [UUID: RunningSession] = [:]
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "FocusSessionVerifier")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Start

    /// Starts a new focus session for `goalID`: opens the `FocusActivityAttributes` Live Activity
    /// (docs/spec.md §6) and begins the per-second countdown immediately.
    ///
    /// - Parameters:
    ///   - goalID: The `Goal.id` this session counts toward. Must already exist in the shared
    ///     store — see `FocusSessionVerifierError.goalNotFound`.
    ///   - plannedMinutes: The timer length. The UI layer is expected to pass one of
    ///     `FocusSessionPreset`'s 25/50/90 values (docs/spec.md §3), but any positive value is
    ///     accepted here — see `FocusSessionPreset`'s doc comment for why this stays an `Int`.
    /// - Returns: A new session id. Pass it to `endSession`/`pauseSession`/`resumeSession`.
    /// - Throws: `FocusSessionVerifierError.invalidPlannedMinutes` or `.goalNotFound`, or a
    ///   SwiftData fetch error.
    public func startSession(goalID: UUID, plannedMinutes: Int) async throws -> UUID {
        guard plannedMinutes > 0 else {
            throw FocusSessionVerifierError.invalidPlannedMinutes(plannedMinutes)
        }
        guard let goal = try fetchGoal(id: goalID) else {
            throw FocusSessionVerifierError.goalNotFound(goalID)
        }

        let sessionID = UUID()
        let activity = requestLiveActivity(
            goalTitle: goal.title,
            plannedMinutes: plannedMinutes,
            secondsRemaining: plannedMinutes * 60
        )

        runningSessions[sessionID] = RunningSession(
            id: sessionID,
            goalID: goalID,
            plannedMinutes: plannedMinutes,
            startedAt: .now,
            activity: activity
        )
        startTicking(for: sessionID)

        logger.notice("Started focus session \(sessionID.uuidString, privacy: .public) for goal \(goalID.uuidString, privacy: .public), \(plannedMinutes, privacy: .public) min planned.")
        return sessionID
    }

    // MARK: - Pause / resume
    //
    // Mechanics live here; *deciding when to call these* is the UI layer's job.
    //
    // TODO(cross-module integration — UI layer, `App/ZANO/Features`, docs/spec.md §3 Focus
    // session row "Leaving the app pauses timer"; not this session's scope, see
    // `FocusActivityAttributes.ContentState.isPaused`'s doc comment): observe `scenePhase` (or
    // `UIApplication.willResignActiveNotification`/`didBecomeActiveNotification`) around the
    // focus-session screen and call `pauseSession`/`resumeSession` accordingly. Everything below
    // this point is real, working pause/resume — nothing about it is a stub.

    /// Pauses a running session's clock and freezes its Live Activity countdown. A no-op if the
    /// session is unknown or already paused.
    public func pauseSession(sessionID: UUID) async {
        guard var session = runningSessions[sessionID], session.pausedAt == nil else { return }

        let now = Date.now
        session.pausedAt = now
        session.tickTask?.cancel()
        session.tickTask = nil
        runningSessions[sessionID] = session

        await updateActivity(for: session, asOf: now, isPaused: true)
    }

    /// Resumes a paused session: folds the pause's duration into `accumulatedPauseDuration` (so
    /// it's excluded from verification and the countdown) and restarts the tick loop. A no-op if
    /// the session is unknown or not currently paused.
    public func resumeSession(sessionID: UUID) async {
        guard var session = runningSessions[sessionID], let pausedAt = session.pausedAt else { return }

        session.accumulatedPauseDuration += Date.now.timeIntervalSince(pausedAt)
        session.pausedAt = nil
        runningSessions[sessionID] = session

        startTicking(for: sessionID)
    }

    // MARK: - End

    /// Ends a running focus session: stops the tick loop, ends the Live Activity, verifies
    /// (elapsed active time >= `plannedMinutes`), and logs a `GoalEvent` (`.complete` if
    /// verified, `.miss` otherwise — both are meaningful training rows, not just successes; see
    /// `GoalEvent.swift`'s header comment).
    ///
    /// - Returns: `true` if the session verified (elapsed active seconds >= planned).
    /// - Throws: `FocusSessionVerifierError.sessionNotFound`, or a SwiftData save error.
    public func endSession(sessionID: UUID) async throws -> Bool {
        guard var session = runningSessions[sessionID] else {
            throw FocusSessionVerifierError.sessionNotFound(sessionID)
        }
        runningSessions.removeValue(forKey: sessionID)

        session.tickTask?.cancel()
        session.tickTask = nil

        let now = Date.now
        let elapsedSeconds = session.elapsedActiveSeconds(asOf: now)
        let plannedSeconds = TimeInterval(session.plannedMinutes * 60)
        let verified = elapsedSeconds >= plannedSeconds

        await endActivity(for: session, elapsedSeconds: elapsedSeconds, asOf: now)
        try logOutcome(session: session, elapsedSeconds: elapsedSeconds, verified: verified, at: now)

        logger.notice("Ended focus session \(sessionID.uuidString, privacy: .public): elapsed \(Int(elapsedSeconds), privacy: .public)s / planned \(Int(plannedSeconds), privacy: .public)s, verified=\(verified, privacy: .public).")
        return verified
    }

    // MARK: - Tick loop

    /// Spawns (or replaces) the unstructured per-second countdown for `sessionID`. Unstructured,
    /// not `async let`/a task group, because its lifetime (up to 90 minutes, per docs/spec.md §3)
    /// doesn't fit a lexical scope — see this session's `write-swift` guidance on `Task { }`.
    /// Synchronous on purpose: the assignment to `runningSessions[sessionID]?.tickTask` below must
    /// happen before the spawned task's body gets a chance to run (no `await` sits between the
    /// two on this main-actor call stack), so there's no race with `tick(sessionID:)` reading it.
    private func startTicking(for sessionID: UUID) {
        let task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick(sessionID: sessionID)

                // Stop looping once `tick` cancelled itself (countdown hit zero) or the session
                // was paused/ended by someone else while we were suspended below.
                guard let current = self.runningSessions[sessionID],
                      current.pausedAt == nil,
                      current.tickTask != nil
                else { return }

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return // Cancelled mid-sleep.
                }
            }
        }
        runningSessions[sessionID]?.tickTask = task
    }

    /// One countdown step: recompute `secondsRemaining` from actual elapsed active time (not a
    /// simple decrement — this makes the countdown self-correcting against any inexact timer
    /// firing) and push it to the Live Activity. Cancels its own session's tick task once the
    /// countdown reaches zero; the session otherwise stays "running" (Tier A auto-verification
    /// still needs an explicit `endSession` call — e.g. from `EndFocusIntent`, docs/spec.md §14 —
    /// the same way it would if the user finishes early or over-runs).
    private func tick(sessionID: UUID) async {
        guard let session = runningSessions[sessionID], session.pausedAt == nil else { return }

        let now = Date.now
        await updateActivity(for: session, asOf: now, isPaused: false)

        if session.elapsedActiveSeconds(asOf: now) >= TimeInterval(session.plannedMinutes * 60) {
            runningSessions[sessionID]?.tickTask?.cancel()
            runningSessions[sessionID]?.tickTask = nil
        }
    }

    // MARK: - Live Activity

    /// Starts the Focus Session Live Activity. Never throws outward: a denied/unavailable Live
    /// Activity (user disabled them in Settings, `ActivityAuthorizationError`, etc.) degrades to
    /// "timer runs, no Live Activity" rather than failing the whole session — the countdown and
    /// verification are the part of docs/spec.md §3 that must always work.
    private func requestLiveActivity(
        goalTitle: String,
        plannedMinutes: Int,
        secondsRemaining: Int
    ) -> Activity<FocusActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities disabled; running focus session without one.")
            return nil
        }

        let attributes = FocusActivityAttributes(goalTitle: goalTitle, plannedMinutes: plannedMinutes)
        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(secondsRemaining: secondsRemaining, isPaused: false),
            staleDate: nil
        )

        do {
            return try Activity<FocusActivityAttributes>.request(attributes: attributes, content: content)
        } catch {
            logger.error("Failed to start Focus Session Live Activity: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Pushes the current countdown/pause state to `session`'s Live Activity, if it has one.
    private func updateActivity(for session: RunningSession, asOf now: Date, isPaused: Bool) async {
        guard let liveActivity = session.activity else { return }
        nonisolated(unsafe) let activity = liveActivity

        let plannedSeconds = TimeInterval(session.plannedMinutes * 60)
        let remaining = remainingSeconds(elapsedSeconds: session.elapsedActiveSeconds(asOf: now), plannedSeconds: plannedSeconds)

        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(secondsRemaining: remaining, isPaused: isPaused),
            staleDate: nil
        )
        await activity.update(content)
    }

    /// Ends `session`'s Live Activity (if any) showing its final countdown value, with a short
    /// grace period before the system may dismiss it (`activityDismissalGracePeriod`).
    private func endActivity(for session: RunningSession, elapsedSeconds: TimeInterval, asOf now: Date) async {
        guard let liveActivity = session.activity else { return }
        nonisolated(unsafe) let activity = liveActivity

        let plannedSeconds = TimeInterval(session.plannedMinutes * 60)
        let remaining = remainingSeconds(elapsedSeconds: elapsedSeconds, plannedSeconds: plannedSeconds)

        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(secondsRemaining: remaining, isPaused: session.pausedAt != nil),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .after(now.addingTimeInterval(Self.activityDismissalGracePeriod)))
    }

    private func remainingSeconds(elapsedSeconds: TimeInterval, plannedSeconds: TimeInterval) -> Int {
        max(0, Int((plannedSeconds - elapsedSeconds).rounded(.up)))
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
    /// rather than throwing.
    private func logOutcome(session: RunningSession, elapsedSeconds: TimeInterval, verified: Bool, at now: Date) throws {
        let goal = try? fetchGoal(id: session.goalID)

        let event = GoalEvent(
            ts: now,
            kind: verified ? .complete : .miss,
            value: elapsedSeconds / 60,
            source: .timer,
            verified: verified,
            meta: .object([
                "plannedMinutes": .number(Double(session.plannedMinutes)),
                "elapsedSeconds": .number(elapsedSeconds),
                "pausedSeconds": .number(session.accumulatedPauseDuration),
            ]),
            user: goal?.user,
            goal: goal
        )
        modelContext.insert(event)
        try modelContext.save()
    }
}
