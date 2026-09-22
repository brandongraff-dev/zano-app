// Core/Sources/Core/LiveActivity/EarnMeterActivityManager.swift
//
// docs/spec.md §5.11 "Dynamic Island Earn Meter":
//   "During a lock, the Dynamic Island / Live Activity shows the Time Bank, goals remaining, and
//   next scheduled lock."
// docs/spec.md §6 "Widgets, Controls, Live Activities, NFC, Siri" → Live Activities:
//   "Active lock (Earn Mode): Time Bank draining bar."
//
// Starts, updates, and ends the `EarnMeterActivityAttributes` Live Activity
// (`EarnMeterActivityAttributes.swift`, same folder/session) from `TimeBankEngine`'s state, per
// this task's instructions: "an EarnMeterActivityManager that starts/updates/ends the Live
// Activity from TimeBankEngine state changes (call TimeBankEngine.shared per CONTRACTS)."
//
// `TimeBankEngine` (Core/Sources/Core/LockEngine/TimeBankEngine.swift) is owned by another agent
// in this same batch and is called here exactly per its frozen SYSTEM CONTRACTS shape:
//
//   final class TimeBankEngine {
//       static let shared = TimeBankEngine()
//       func deposit(minutes: Int, for date: Date) async throws
//       func spend(minutes: Int, for date: Date) async throws -> Bool
//       func remainingMinutes(for date: Date) async -> Int
//   }
//
// That contract exposes no observation/delegate hook of its own (no Combine publisher, no
// `AsyncSequence` of balance changes) — deposits/spends are plain `async throws` calls. So this
// file is deliberately the *single place* Earn Mode balance changes and Live Activity updates are
// kept in lockstep: ``deposit(minutes:for:)`` and ``spend(minutes:for:)`` below wrap the matching
// `TimeBankEngine` call with a Live Activity refresh in the same async step, and
// ``refreshFromTimeBank(goalsRemaining:nextLockTime:on:)`` is the explicit hook for a caller that
// changed the balance some other way (or just wants to re-pull `goalsRemaining`/`nextLockTime`
// after a goal verified) to push a fresh `ContentState` without re-depositing/re-spending anything.
//
// TODO(cross-module integration — LockEngine, `Core/Sources/Core/LockEngine/LockEngineManager.swift`,
// owned by another agent this batch, not this file's scope): `LockEngineManager.startLock` /
// `.endLock` are the natural call sites to start this Live Activity when an `.earn`-mode lock
// begins and end it when that lock ends (earned, emergency, schedule end, or manual — the Earn
// Meter should disappear the moment the lock it describes is no longer active, matching
// `FocusSessionVerifier`'s Live-Activity-tracks-the-session-exactly convention). Wiring that call
// is left for whichever session integrates the two, since this file cannot edit
// `LockEngineManager.swift`. Everything below this point — start, update, end, and the
// deposit/spend passthrough — is real, working code, not a stub.

import ActivityKit
import Foundation
import os

/// Starts, refreshes, and ends the single Earn Meter Live Activity for the current process.
///
/// `@MainActor`, matching `FocusSessionVerifier`'s reasoning exactly: this type owns an ActivityKit
/// `Activity` (a UI-adjacent, foreground-relevant concern — Apple's own sample code always drives
/// `Activity.request`/`.update`/`.end` from the main actor), and confining its one mutable stored
/// property to the main actor is the simplest correct choice under Swift 6 strict concurrency while
/// still matching this task's CONTRACTS declaration of `EarnMeterActivityManager` as an (implicitly
/// `Sendable`) singleton callable from any isolation domain — callers just hop to the main actor to
/// do it, like every other `async` API on this singleton already does.
///
/// One Earn Meter Activity exists at a time per process, matching `LockEngineManager`'s
/// single-active-lock model (`SharedDefaults.activeLockSessionID` is a single optional id, not a
/// set) — there is only ever one currently-shielding `LockSession` to meter.
@MainActor
public final class EarnMeterActivityManager {
    public static let shared = EarnMeterActivityManager()

    private var activity: Activity<EarnMeterActivityAttributes>?
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "EarnMeterActivityManager")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance; every
    /// real call site uses `.shared`.
    init() {}

    /// `true` while this process has a running Earn Meter Activity.
    public var isActive: Bool { activity != nil }

    // MARK: - Start

    /// Starts the Earn Meter Live Activity for a newly-begun `.earn`-mode lock (docs/spec.md §5.2,
    /// §5.11). Reads the opening `ContentState` from `TimeBankEngine.shared.remainingMinutes(for:)`
    /// plus, unless overridden, `SharedDefaults.goalsRemainingForActiveLock` /
    /// `.nextScheduledLockAt` — the same App Group mirror `LockEngineManager` already maintains
    /// (`Core/Sources/Core/Store/SharedDefaults.swift`), so a caller mid-`startLock` doesn't have
    /// to re-derive `goalsRemaining` itself just to open this Activity.
    ///
    /// If a previous Earn Meter Activity is still tracked (e.g. a caller starts a new earn-mode
    /// lock without having ended the last one's Activity), it's ended first — this file's Activity
    /// is a singleton per the type doc comment, and an orphaned stale Activity showing the wrong
    /// lock set would be worse than replacing it.
    ///
    /// Never throws: a denied/unavailable Live Activity (user disabled them in Settings,
    /// `ActivityAuthorizationError`, etc.) degrades to "Time Bank still tracked, no Dynamic Island
    /// meter" rather than failing the lock itself — the lock/shield is the part of spec §2 that
    /// must always work.
    ///
    /// - Parameters:
    ///   - lockSetName: `LockSet.name` (Core/Sources/Core/Models/LockSet.swift) for the lock this
    ///     meter describes.
    ///   - goalsRemaining: Overrides the initial `ContentState.goalsRemaining`. Defaults to
    ///     `SharedDefaults.goalsRemainingForActiveLock`.
    ///   - nextLockTime: Overrides the initial `ContentState.nextLockTime`. Defaults to
    ///     `SharedDefaults.nextScheduledLockAt`.
    ///   - date: Which day's Time Bank ledger to read the opening balance from. Defaults to `.now`;
    ///     callers should not need to pass this outside of tests.
    /// - Returns: the started `Activity`, or `nil` if Live Activities are unavailable/denied.
    @discardableResult
    public func startActivity(
        lockSetName: String,
        goalsRemaining: Int? = nil,
        nextLockTime: Date? = nil,
        on date: Date = .now
    ) async -> Activity<EarnMeterActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities disabled; running earn-mode lock without a Dynamic Island earn meter.")
            return nil
        }

        if activity != nil {
            logger.notice("startActivity called with an Earn Meter Activity already running; ending the stale one first.")
            await endActivity()
        }

        let remaining = await TimeBankEngine.shared.remainingMinutes(for: date)
        let state = EarnMeterActivityAttributes.ContentState(
            earnedMinutesRemaining: remaining,
            goalsRemaining: goalsRemaining ?? SharedDefaults.goalsRemainingForActiveLock,
            nextLockTime: nextLockTime ?? SharedDefaults.nextScheduledLockAt
        )
        let attributes = EarnMeterActivityAttributes(lockSetName: lockSetName)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            let started = try Activity<EarnMeterActivityAttributes>.request(attributes: attributes, content: content)
            activity = started
            logger.notice("Started Earn Meter Live Activity for lock set \(lockSetName, privacy: .public): \(remaining, privacy: .public) min remaining.")
            return started
        } catch {
            logger.error("Failed to start Earn Meter Live Activity: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Update

    /// Re-pulls the Earn Meter's `ContentState` and pushes it, if an Activity is currently running.
    /// A no-op (not an error) when no Activity is active — every state-changing call in this file
    /// funnels through this method, and there being nothing to update is an ordinary outcome (e.g.
    /// a goal verifies after the user has already emergency-unlocked and this process just hasn't
    /// been told to end the Activity yet).
    ///
    /// This is the explicit "TimeBankEngine state changed, reflect it" hook for callers that moved
    /// the balance some other way than this file's own `deposit`/`spend` wrappers below (both of
    /// which already call this), or that only need to refresh `goalsRemaining`/`nextLockTime`
    /// (e.g. a goal just verified, changing `SharedDefaults.goalsRemainingForActiveLock`, with no
    /// Time Bank deposit involved for a `.full`-mode lock's earn-meter-adjacent display).
    ///
    /// - Parameters:
    ///   - goalsRemaining: Overrides `ContentState.goalsRemaining` for this push. Defaults to
    ///     `SharedDefaults.goalsRemainingForActiveLock`.
    ///   - nextLockTime: Overrides `ContentState.nextLockTime` for this push. Double-optional so
    ///     `nil` (the default) means "read `SharedDefaults.nextScheduledLockAt`" while `.some(nil)`
    ///     means "explicitly clear it" — a caller that knows the next lock time just became
    ///     unscheduled needs to be able to say so without this method quietly re-reading a stale
    ///     `SharedDefaults` value instead.
    ///   - date: Which day's Time Bank ledger to read the current balance from. Defaults to `.now`.
    public func refreshFromTimeBank(
        goalsRemaining: Int? = nil,
        nextLockTime: Date?? = nil,
        on date: Date = .now
    ) async {
        guard activity != nil else { return }

        let remaining = await TimeBankEngine.shared.remainingMinutes(for: date)
        let resolvedNextLockTime = nextLockTime ?? SharedDefaults.nextScheduledLockAt
        let state = EarnMeterActivityAttributes.ContentState(
            earnedMinutesRemaining: remaining,
            goalsRemaining: goalsRemaining ?? SharedDefaults.goalsRemainingForActiveLock,
            nextLockTime: resolvedNextLockTime
        )
        await activity?.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Deposits earned minutes via `TimeBankEngine.shared.deposit(minutes:for:)` (spec §5.2: a
    /// verified goal deposits minutes into today's Time Bank), then refreshes the Earn Meter
    /// Activity in the same call so the draining bar never lags a goal completion. The natural
    /// call site is wherever a `GoalEvent` for an `.earn`-mode lock's required goal is logged as
    /// verified — see the cross-module TODO at the top of this file.
    ///
    /// - Throws: whatever `TimeBankEngine.deposit(minutes:for:)` throws. The deposit itself always
    ///   completes (or throws) before this method returns; the Activity refresh that follows a
    ///   successful deposit is best-effort (see `refreshFromTimeBank`'s no-Activity no-op) and
    ///   never itself throws.
    public func deposit(minutes: Int, for date: Date = .now) async throws {
        try await TimeBankEngine.shared.deposit(minutes: minutes, for: date)
        await refreshFromTimeBank(on: date)
    }

    /// Spends minutes via `TimeBankEngine.shared.spend(minutes:for:)` (spec §5.2: unlocking a
    /// shielded app spends Time Bank minutes), then refreshes the Earn Meter Activity so the
    /// draining bar reflects the new balance immediately.
    ///
    /// - Returns: `TimeBankEngine.spend`'s own result — `true` if the spend was applied (enough
    ///   balance existed), `false` if it was rejected for insufficient balance. The Activity is
    ///   refreshed either way: even a rejected spend is worth re-pulling the authoritative balance
    ///   for, in case this process's view of it had drifted.
    /// - Throws: whatever `TimeBankEngine.spend(minutes:for:)` throws.
    @discardableResult
    public func spend(minutes: Int, for date: Date = .now) async throws -> Bool {
        let succeeded = try await TimeBankEngine.shared.spend(minutes: minutes, for: date)
        await refreshFromTimeBank(on: date)
        return succeeded
    }

    // MARK: - End

    /// Ends the running Earn Meter Activity, if any — called once the `.earn`-mode lock it
    /// describes is no longer active (earned unlock, emergency unlock, schedule end, or manual
    /// end; see the cross-module TODO at the top of this file for where that call belongs).
    ///
    /// Pushes one last `ContentState` read fresh from `TimeBankEngine`/`SharedDefaults` (rather
    /// than reusing whatever was last pushed) so the Activity's final on-screen state — which the
    /// system may keep visible for a few seconds after this call, per `dismissalPolicy` — reflects
    /// the true balance at the moment the lock ended, not a possibly-stale prior update.
    ///
    /// - Parameter dismissalPolicy: Defaults to `.immediate` — unlike a focus session's countdown
    ///   (`FocusSessionVerifier.activityDismissalGracePeriod`), there's no "watch it finish"
    ///   moment for an earn meter: the lock it describes has already ended by the time this is
    ///   called (or was emergency-unlocked, in which case lingering the meter on screen serves no
    ///   purpose). A caller with a product reason to show the final state briefly can pass
    ///   `.after(_:)` instead.
    public func endActivity(dismissalPolicy: ActivityUIDismissalPolicy = .immediate, on date: Date = .now) async {
        guard let activity else { return }
        self.activity = nil

        let remaining = await TimeBankEngine.shared.remainingMinutes(for: date)
        let finalState = EarnMeterActivityAttributes.ContentState(
            earnedMinutesRemaining: remaining,
            goalsRemaining: SharedDefaults.goalsRemainingForActiveLock,
            nextLockTime: SharedDefaults.nextScheduledLockAt
        )
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: dismissalPolicy)
        logger.notice("Ended Earn Meter Live Activity.")
    }
}
