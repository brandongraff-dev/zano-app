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
//
// Launch-blocker fixes (docs/design/unfinished-audit-2026-10-02.md L3/L4/L5/L8):
//   - A running session is persisted in the App Group defaults (`FocusSessionStore`), so it
//     survives the app being killed or suspended. `restorePersistedSessions` (on every app
//     activation, and before any end/lookup) re-adopts it and ends it as verified when its planned
//     active time has already elapsed.
//   - The countdown ends the session by itself at zero (verified), so a session started from
//     Today, a widget, Siri or an NFC tag verifies without anyone calling `endSession`.
//   - Spec section 3 anti-cheat "Leaving the app pauses timer": `appDidEnterBackground` pauses
//     every session started in the app (`pausesWhenAppLeaves`), `appDidBecomeActive` resumes the
//     ones it paused. There is no grace period in the spec, so none here. Sessions started
//     outside the app (Siri, widget, NFC, Watch) run with shields on and don't pause: the person
//     was never in the app to leave it.
//   - `activeSession` is observable, so any screen can show a session it didn't start, and
//     `endActiveSession()` lets `EndFocusIntent` / `zano://focus/end` end it without an id.

import ActivityKit
import Foundation
import Observation
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

/// Runs the in-app focus-session timer (docs/spec.md section 3 Focus session row), drives its
/// `FocusActivityAttributes` Live Activity end-to-end (start, tick, pause/resume, end), and on end
/// verifies the session (elapsed active time >= planned minutes) and logs the result as a
/// `GoalEvent` (every complete/miss is a training row, not just successes).
///
/// `@MainActor @Observable`: it owns a tick loop and an ActivityKit `Activity` (main-actor
/// concerns), and `activeSession` is read live by SwiftUI. One instance per process; the running
/// session itself lives in the App Group defaults (`FocusSessionStore`) so the app's process can
/// pick it up again after a relaunch. Every intent that starts or ends one is a
/// `LiveActivityIntent`, so in practice only the app's process runs sessions.
@MainActor
@Observable
public final class FocusSessionVerifier {
    public static let shared = FocusSessionVerifier()

    /// One in-flight focus session: its persisted record plus the process-local handles.
    private struct RunningSession {
        var record: PersistedFocusSession
        /// `nil` when Live Activities are unavailable/denied: the timer and verification still work.
        var activity: Activity<FocusActivityAttributes>? = nil
        /// The per-second tick loop while running and unpaused.
        var tickTask: Task<Void, Never>? = nil
    }

    /// How long a finished Live Activity stays visible (showing its final state) before the system
    /// may dismiss it.
    private static let activityDismissalGracePeriod: TimeInterval = 5

    /// The session a screen should show, or `nil` when none is running. Updated on every start,
    /// pause, resume, end and restore (not every tick: derive the countdown from `endsAt`).
    public private(set) var activeSession: ActiveFocusSession?

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let store: FocusSessionStore
    private let onVerified: @MainActor (UUID) async -> Void
    @ObservationIgnored private var runningSessions: [UUID: RunningSession] = [:]
    /// Outcomes of sessions this process already ended, so a second `endSession` for the same id
    /// (the countdown ended it at zero, then the onboarding screen's own timer asks too) returns
    /// the real result instead of throwing.
    @ObservationIgnored private var endedResults: [UUID: Bool] = [:]
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "FocusSessionVerifier")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container and its own defaults suite; every real call site uses `.shared`.
    init(
        modelContainer: ModelContainer = .appGroup,
        store: FocusSessionStore = FocusSessionStore(),
        onVerified: @escaping @MainActor (UUID) async -> Void = { goalID in
            await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
        }
    ) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        self.store = store
        self.onVerified = onVerified
    }

    // MARK: - Start

    /// Starts a new focus session for `goalID`: opens the Live Activity and begins the countdown.
    ///
    /// - Parameters:
    ///   - goalID: The `Goal.id` this session counts toward. Must exist in the shared store.
    ///   - plannedMinutes: The timer length (any positive value; 25/50/90 are the UI presets).
    ///   - isPlanB: `true` when Today's Plan B card started this shortened session (spec 5.5): a
    ///     verified Plan B session logs `.planB` instead of `.complete`.
    ///   - pausesWhenAppLeaves: `true` (the default) for a session the person runs in the app:
    ///     leaving the app pauses it (spec section 3 anti-cheat). `false` for sessions started
    ///     outside the app (`StartFocusIntent` from Siri, a widget or an NFC tag; the Watch).
    /// - Returns: A new session id.
    public func startSession(
        goalID: UUID,
        plannedMinutes: Int,
        isPlanB: Bool = false,
        pausesWhenAppLeaves: Bool = true
    ) async throws -> UUID {
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
        let record = PersistedFocusSession(
            id: sessionID,
            goalID: goalID,
            plannedMinutes: plannedMinutes,
            startedAt: .now,
            isPlanB: isPlanB,
            pausesWhenAppLeaves: pausesWhenAppLeaves,
            activityID: activity?.id
        )
        runningSessions[sessionID] = RunningSession(record: record, activity: activity)
        persist()
        startTicking(for: sessionID)

        logger.notice("Started focus session \(sessionID.uuidString, privacy: .public) for goal \(goalID.uuidString, privacy: .public), \(plannedMinutes, privacy: .public) min planned.")
        return sessionID
    }

    // MARK: - Pause / resume

    /// Pauses a running session's clock and freezes its Live Activity countdown. A no-op if the
    /// session is unknown or already paused.
    public func pauseSession(sessionID: UUID) async {
        guard markPaused(sessionID: sessionID, at: .now, automatically: false),
              let session = runningSessions[sessionID] else { return }
        await updateActivity(for: session, asOf: .now, isPaused: true)
    }

    /// Resumes a paused session: the pause is excluded from verification and the countdown. A
    /// no-op if the session is unknown or not paused.
    public func resumeSession(sessionID: UUID) async {
        guard markResumed(sessionID: sessionID, at: .now) else { return }
        startTicking(for: sessionID)
    }

    // MARK: - App lifecycle (spec section 3: "Leaving the app pauses timer")

    /// The app went to the background: pause every in-app session (`pausesWhenAppLeaves`) and
    /// count the leave. Synchronous so the pause is persisted before iOS suspends the process;
    /// the Live Activity update follows on its own task.
    public func appDidEnterBackground(now: Date = .now) {
        var paused: [RunningSession] = []
        for (id, session) in runningSessions where session.record.pausesWhenAppLeaves && session.record.pausedAt == nil {
            runningSessions[id]?.record.appLeaveCount += 1
            if markPaused(sessionID: id, at: now, automatically: true), let updated = runningSessions[id] {
                paused.append(updated)
            }
        }
        guard !paused.isEmpty else { return }
        // `Activity` isn't `Sendable`; these values never leave the main actor.
        nonisolated(unsafe) let toUpdate = paused
        Task { [weak self] in
            for session in toUpdate { await self?.updateActivity(for: session, asOf: now, isPaused: true) }
        }
    }

    /// The app is active again (and on launch): re-adopt any persisted session, verify the ones
    /// whose time already elapsed, and resume the sessions leaving the app paused.
    public func appDidBecomeActive(now: Date = .now) async {
        await restorePersistedSessions(now: now)
        for (id, session) in runningSessions where session.record.autoPaused {
            if markResumed(sessionID: id, at: now) { startTicking(for: id) }
        }
    }

    /// Re-adopts sessions persisted by an earlier run of this process (killed, crashed, or a
    /// session another launch started). One whose planned active time already elapsed is ended
    /// as verified right away; the rest keep running (or stay paused). Idempotent and cheap.
    public func restorePersistedSessions(now: Date = .now) async {
        let records = store.load().filter { runningSessions[$0.id] == nil && endedResults[$0.id] == nil }
        guard !records.isEmpty else { return }
        for record in records {
            let activity = record.activityID.flatMap { id in
                Activity<FocusActivityAttributes>.activities.first { $0.id == id }
            }
            runningSessions[record.id] = RunningSession(record: record, activity: activity)
        }
        publishActiveSession()
        for record in records {
            if record.elapsedActiveSeconds(asOf: now) >= TimeInterval(record.plannedMinutes * 60) {
                _ = try? await endSession(sessionID: record.id, at: now)
            } else if record.pausedAt == nil {
                startTicking(for: record.id)
            }
        }
    }

    // MARK: - End

    /// Ends a running focus session: stops the tick loop, ends the Live Activity, verifies
    /// (elapsed active time >= planned, see `isVerified`), and logs a `GoalEvent` (`.complete` /
    /// `.planB` if verified, `.miss` otherwise).
    ///
    /// Ending a session this process already ended returns that session's result again.
    ///
    /// - Returns: `true` if the session verified.
    /// - Throws: `FocusSessionVerifierError.sessionNotFound`, or a SwiftData save error.
    public func endSession(sessionID: UUID) async throws -> Bool {
        try await endSession(sessionID: sessionID, at: .now)
    }

    /// Ends whichever session is running (the most recently started one), for callers that don't
    /// hold an id: `EndFocusIntent`, the Live Activity's `zano://focus/end` link.
    ///
    /// - Returns: whether it verified, or `nil` when no session was running.
    @discardableResult
    public func endActiveSession(now: Date = .now) async throws -> Bool? {
        await restorePersistedSessions(now: now)
        guard let id = latestSessionID() else { return nil }
        return try await endSession(sessionID: id, at: now)
    }

    /// The running session's id after re-adopting any persisted one, or `nil`.
    public func activeSessionID(now: Date = .now) async -> UUID? {
        await restorePersistedSessions(now: now)
        return latestSessionID()
    }

    private func endSession(sessionID: UUID, at now: Date) async throws -> Bool {
        if runningSessions[sessionID] == nil, endedResults[sessionID] == nil {
            await restorePersistedSessions(now: now)
        }
        if let previous = endedResults[sessionID] { return previous }
        guard var session = runningSessions[sessionID] else {
            throw FocusSessionVerifierError.sessionNotFound(sessionID)
        }
        // Removed (memory and App Group) before the first `await`, so a second caller can never
        // end — and log — the same session twice.
        runningSessions.removeValue(forKey: sessionID)
        session.tickTask?.cancel()
        session.tickTask = nil

        let record = session.record
        let elapsedSeconds = record.elapsedActiveSeconds(asOf: now)
        let plannedSeconds = TimeInterval(record.plannedMinutes * 60)
        let verified = Self.isVerified(
            elapsedSeconds: elapsedSeconds,
            plannedSeconds: plannedSeconds,
            appLeaveCount: record.appLeaveCount
        )
        endedResults[sessionID] = verified
        persist()

        await endActivity(for: session, elapsedSeconds: elapsedSeconds, asOf: now)
        try logOutcome(record: record, elapsedSeconds: elapsedSeconds, verified: verified, at: now)
        if verified { await onVerified(record.goalID) }

        logger.notice("Ended focus session \(sessionID.uuidString, privacy: .public): elapsed \(Int(elapsedSeconds), privacy: .public)s / planned \(Int(plannedSeconds), privacy: .public)s, verified=\(verified, privacy: .public).")
        return verified
    }

    /// "Delete all my data": stops every running session without logging anything (the rows are
    /// being deleted anyway) and forgets the persisted record. The Live Activities are ended by
    /// `DeviceDataReset`.
    public func resetAll() {
        for session in runningSessions.values { session.tickTask?.cancel() }
        runningSessions = [:]
        endedResults = [:]
        persist()
    }

    /// Pure verification rule: the session's active time reached the plan. A few seconds of slack
    /// per time the person left the app, because a screen's own countdown keeps running in the
    /// seconds iOS gives a backgrounded app while this clock is already paused (the onboarding
    /// first-win screen ends its session from its own countdown). Capped at 30 seconds.
    nonisolated static func isVerified(elapsedSeconds: TimeInterval, plannedSeconds: TimeInterval, appLeaveCount: Int) -> Bool {
        let slack = min(30, 2 + 5 * TimeInterval(max(0, appLeaveCount)))
        return elapsedSeconds + slack >= plannedSeconds
    }

    // MARK: - State changes (synchronous, persisted)

    @discardableResult
    private func markPaused(sessionID: UUID, at now: Date, automatically: Bool) -> Bool {
        guard var session = runningSessions[sessionID], session.record.pausedAt == nil else { return false }
        session.record.pausedAt = now
        session.record.autoPaused = automatically
        session.tickTask?.cancel()
        session.tickTask = nil
        runningSessions[sessionID] = session
        persist()
        return true
    }

    @discardableResult
    private func markResumed(sessionID: UUID, at now: Date) -> Bool {
        guard var session = runningSessions[sessionID], let pausedAt = session.record.pausedAt else { return false }
        session.record.accumulatedPauseDuration += max(0, now.timeIntervalSince(pausedAt))
        session.record.pausedAt = nil
        session.record.autoPaused = false
        runningSessions[sessionID] = session
        persist()
        return true
    }

    private func latestSessionID() -> UUID? {
        runningSessions.values.max { $0.record.startedAt < $1.record.startedAt }?.record.id
    }

    /// Writes every running session to the App Group and republishes `activeSession`.
    private func persist() {
        store.save(runningSessions.values.map(\.record))
        publishActiveSession()
    }

    private func publishActiveSession() {
        let latest = runningSessions.values.max { $0.record.startedAt < $1.record.startedAt }?.record
        let snapshot = latest.map { ActiveFocusSession(record: $0, asOf: .now) }
        if snapshot != activeSession { activeSession = snapshot }
    }

    // MARK: - Tick loop

    /// Spawns (or replaces) the per-second countdown for `sessionID`. Synchronous on purpose: the
    /// task is stored before its body can run, so `tick` always sees it.
    private func startTicking(for sessionID: UUID) {
        runningSessions[sessionID]?.tickTask?.cancel()
        let task = Task { [weak self] in
            while let self, !Task.isCancelled {
                let keepGoing = await self.tick(sessionID: sessionID)
                guard keepGoing,
                      let current = self.runningSessions[sessionID],
                      current.record.pausedAt == nil,
                      current.tickTask != nil
                else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
        runningSessions[sessionID]?.tickTask = task
    }

    /// One countdown step, recomputed from real elapsed active time. At zero the session ends
    /// itself as verified (audit L3/L4: nobody else has to call `endSession`). Returns whether the
    /// loop should keep going.
    private func tick(sessionID: UUID) async -> Bool {
        guard let session = runningSessions[sessionID], session.record.pausedAt == nil else { return false }
        let now = Date.now
        if session.record.elapsedActiveSeconds(asOf: now) >= TimeInterval(session.record.plannedMinutes * 60) {
            runningSessions[sessionID]?.tickTask = nil
            _ = try? await endSession(sessionID: sessionID, at: now)
            return false
        }
        await updateActivity(for: session, asOf: now, isPaused: false)
        return true
    }

    // MARK: - Live Activity

    /// Starts the Focus Session Live Activity. Never throws outward: a denied/unavailable Live
    /// Activity degrades to "timer runs, no Live Activity".
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

        let plannedSeconds = TimeInterval(session.record.plannedMinutes * 60)
        let remaining = remainingSeconds(elapsedSeconds: session.record.elapsedActiveSeconds(asOf: now), plannedSeconds: plannedSeconds)

        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(secondsRemaining: remaining, isPaused: isPaused),
            staleDate: nil
        )
        await activity.update(content)
    }

    /// Ends `session`'s Live Activity (if any) showing its final countdown value.
    private func endActivity(for session: RunningSession, elapsedSeconds: TimeInterval, asOf now: Date) async {
        guard let liveActivity = session.activity else { return }
        nonisolated(unsafe) let activity = liveActivity

        let plannedSeconds = TimeInterval(session.record.plannedMinutes * 60)
        let remaining = remainingSeconds(elapsedSeconds: elapsedSeconds, plannedSeconds: plannedSeconds)

        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(secondsRemaining: remaining, isPaused: session.record.pausedAt != nil),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .after(now.addingTimeInterval(Self.activityDismissalGracePeriod)))
    }

    private func remainingSeconds(elapsedSeconds: TimeInterval, plannedSeconds: TimeInterval) -> Int {
        max(0, Int((plannedSeconds - elapsedSeconds).rounded(.up)))
    }

    // MARK: - Plan B (spec 5.5)

    /// `.planB` for a session the Plan B card started, or for any session shorter than today's
    /// full target on a day the user switched this goal to Plan B. Otherwise `.complete`.
    private func completionKind(for record: PersistedFocusSession, elapsedMinutes: Double, at now: Date) -> GoalEventKind {
        if record.isPlanB { return .planB }
        guard PlanB.isAccepted(goalID: record.goalID, on: now) else { return .complete }
        guard let fullTarget = fullTarget(goalID: record.goalID, on: now) else { return .complete }
        return elapsedMinutes < fullTarget ? .planB : .complete
    }

    private func fullTarget(goalID: UUID, on date: Date) -> Double? {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DailyPlan>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let planned = (try? context.fetch(descriptor))?.first { $0.goal?.id == goalID }?.plannedValue
        return planned ?? (try? fetchGoal(id: goalID, in: context))?.targetValue
    }

    // MARK: - Persistence

    private func fetchGoal(id: UUID, in context: ModelContext? = nil) throws -> Goal? {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try (context ?? modelContext).fetch(descriptor).first
    }

    /// Logs the session's outcome as a `GoalEvent`, attached to its goal when it still exists.
    private func logOutcome(record: PersistedFocusSession, elapsedSeconds: TimeInterval, verified: Bool, at now: Date) throws {
        // A fresh context per write: a long-lived context can hold a stale `Goal` whose `events`
        // list predates rows other contexts added since, and saving through it detaches them.
        let context = ModelContext(modelContainer)
        let goal = try? fetchGoal(id: record.goalID, in: context)
        let kind: GoalEventKind = verified ? completionKind(for: record, elapsedMinutes: elapsedSeconds / 60, at: now) : .miss

        var meta: [String: JSONValue] = [
            "plannedMinutes": .number(Double(record.plannedMinutes)),
            "elapsedSeconds": .number(elapsedSeconds),
            "pausedSeconds": .number(record.accumulatedPauseDuration),
            // Spec section 3 anti-cheat: "phone pickup count logged" — times the person left the app.
            "appLeaves": .number(Double(record.appLeaveCount)),
        ]
        if kind == .planB { meta[PlanB.planBMetaKey] = .bool(true) }

        let event = GoalEvent(
            ts: now,
            kind: kind,
            value: elapsedSeconds / 60,
            source: .timer,
            verified: verified,
            meta: .object(meta),
            user: goal?.user,
            goal: goal
        )
        context.insert(event)
        try context.save()
    }
}

// MARK: - Public snapshot

/// What a screen needs to show a running focus session it may not have started (Today, the Lock
/// tab): which goal, how long, and when it ends. `endsAt` is `nil` while paused.
public struct ActiveFocusSession: Sendable, Equatable {
    public let id: UUID
    public let goalID: UUID
    public let plannedMinutes: Int
    public let startedAt: Date
    public let isPaused: Bool
    /// Wall-clock time the countdown reaches zero if it isn't paused again; `nil` while paused.
    public let endsAt: Date?
    /// Remaining seconds at the time of the snapshot (frozen while paused).
    public let secondsRemainingAtSnapshot: Int

    init(record: PersistedFocusSession, asOf now: Date) {
        let remaining = max(0, TimeInterval(record.plannedMinutes * 60) - record.elapsedActiveSeconds(asOf: now))
        self.id = record.id
        self.goalID = record.goalID
        self.plannedMinutes = record.plannedMinutes
        self.startedAt = record.startedAt
        self.isPaused = record.pausedAt != nil
        self.endsAt = record.pausedAt == nil ? now.addingTimeInterval(remaining) : nil
        self.secondsRemainingAtSnapshot = Int(remaining.rounded(.up))
    }
}

// MARK: - Persistence (App Group)

/// A running focus session as stored in the App Group defaults (device-local, never synced).
struct PersistedFocusSession: Codable, Sendable, Equatable {
    var id: UUID
    var goalID: UUID
    var plannedMinutes: Int
    var startedAt: Date
    var isPlanB: Bool
    var pausesWhenAppLeaves: Bool
    /// `ActivityKit` `Activity.id`, to re-attach the Live Activity after a relaunch.
    var activityID: String?
    /// Set while paused.
    var pausedAt: Date? = nil
    /// `true` when leaving the app (not the person) paused it, so returning resumes it.
    var autoPaused: Bool = false
    /// Every finished pause, excluded from the active time.
    var accumulatedPauseDuration: TimeInterval = 0
    /// Times the person left the app during the session (spec section 3: "phone pickup count logged").
    var appLeaveCount: Int = 0

    /// Wall-clock time actually spent running (every pause excluded), as of `now`.
    func elapsedActiveSeconds(asOf now: Date) -> TimeInterval {
        let inProgressPause = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - accumulatedPauseDuration - inProgressPause)
    }
}

/// The App Group key holding running focus sessions. `@unchecked Sendable`: `UserDefaults` is
/// thread-safe, the same reasoning as `LockEngineSharedState`'s `nonisolated(unsafe)` defaults.
struct FocusSessionStore: @unchecked Sendable {
    static let key = "core.focusSession.running.v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.defaults = defaults
    }

    func load() -> [PersistedFocusSession] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PersistedFocusSession].self, from: data)) ?? []
    }

    func save(_ sessions: [PersistedFocusSession]) {
        guard !sessions.isEmpty, let data = try? JSONEncoder().encode(sessions) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    /// "Delete all my data": forget any running session.
    static func clearAll() {
        FocusSessionStore().save([])
    }
}
