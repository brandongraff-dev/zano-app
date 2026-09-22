// Core/Sources/Core/LockEngine/EmergencyUnlock.swift
//
// The 60-second hold + optional streak-penalty flow behind Emergency Unlock:
//   - spec §4: "Emergency unlock (60-second hold + streak penalty option)"
//   - spec §14 `EmergencyUnlockIntent`: "60-sec hold in app; records unlock_kind=emergency"
//   - spec §24 / CLAUDE.md: "Any lock/shield feature must always keep an emergency-unlock path.
//     Never trap the user."
//
// This file is a UI-agnostic `@Observable` state machine only — it imports neither SwiftUI nor
// UIKit. Whatever hold gesture drives it (a `PrimaryButton` "hold-to-commit" variant per spec
// §15's component list, or a custom `DragGesture`/`LongPressGesture`) lives in App/ZANO or the
// relevant extension, not here, per CLAUDE.md's "Shared code goes ONLY in Core" /
// "App-only UI in App/ZANO/Features" split. Likewise, none of the copy an app would show
// ("This will end your streak", "Hold to confirm you're really locked out") is hardcoded here —
// a view reads `phase`/`progress`/`appliesStreakPenalty` and looks its copy up in
// `Core/Sources/Core/Copy`, per CLAUDE.md's "no hardcoded UI strings" rule.
//
// Not part of this task's SYSTEM CONTRACTS list — this file's public shape is this session's own
// design, built to call `LockEngineManager.shared.emergencyUnlock(sessionID:)` and
// `StreakEngine.shared.recordMiss(on:)`/`useFreeze(on:)` exactly as CONTRACTS specifies those.

import Foundation
import Observation

/// Drives one Emergency Unlock attempt for a single `LockSession`. Create a fresh instance per
/// attempt (e.g. when the Emergency sheet/screen appears) rather than reusing one across
/// sessions.
@MainActor
@Observable
public final class EmergencyUnlock {

    /// Where this attempt is in its lifecycle. A view switches on this to decide what to render
    /// (idle hold button → filling progress ring → confirmation/celebration → error state).
    public enum Phase: Sendable, Equatable {
        /// Not currently being held. The starting state, and also where a released-early hold
        /// returns to so the user can simply try again — releasing early is never a penalty by
        /// itself (CLAUDE.md: never trap the user, but also never punish *attempting* to leave).
        case idle
        /// Finger down, progress advancing toward `EmergencyUnlock.holdDuration`.
        case holding
        /// The hold reached `holdDuration`; `LockEngineManager.emergencyUnlock` and (if
        /// `appliesStreakPenalty`) `StreakEngine.recordMiss` are in flight.
        case completing
        /// The lock has been ended with `unlockKind: .emergency`. Terminal.
        case unlocked
        /// `LockEngineManager.emergencyUnlock` threw. Terminal for this instance — a view should
        /// show `lastError` and offer to create a new `EmergencyUnlock` to retry, since this
        /// instance's internal hold timer has already finished.
        case failed
    }

    /// spec §4 / §14: the hold is always 60 seconds — this is not user- or server-configurable.
    public static let holdDuration: TimeInterval = 60

    /// How often `progress`/`secondsRemaining` are republished while holding. Fine-grained enough
    /// for a smooth progress ring (spec §15: "ring fills ease-out 600ms" motion language) without
    /// pushing an `@Observable` update on every display-link frame.
    private static let tickInterval: TimeInterval = 0.05

    /// The `LockSession` this attempt would end.
    public let sessionID: UUID

    public private(set) var phase: Phase = .idle

    /// `0...1` over `EmergencyUnlock.holdDuration`. `0` whenever `phase != .holding` and the hold
    /// hasn't just completed.
    public private(set) var progress: Double = 0

    /// Whole seconds left in the current hold, for a "59… 58… 57…" style label. Equal to
    /// `Int(holdDuration)` before the first hold starts.
    public private(set) var secondsRemaining: Int = Int(EmergencyUnlock.holdDuration)

    /// Whether completing this hold will also record a streak miss — spec §4's "streak penalty
    /// option". Defaults to `true`: an emergency unlock is a genuine miss of whatever this lock
    /// was gating, so the honest default carries that cost. A view can turn this off before the
    /// hold completes (`setAppliesStreakPenalty(false)`), or spend a freeze instead via
    /// `useStreakFreezeInstead()`, which does the same thing on success.
    public private(set) var appliesStreakPenalty: Bool

    /// Set if `completeHold` fails (`phase == .failed`). `nil` otherwise.
    public private(set) var lastError: Error?

    private var tickTask: Task<Void, Never>?

    public init(sessionID: UUID, appliesStreakPenalty: Bool = true) {
        self.sessionID = sessionID
        self.appliesStreakPenalty = appliesStreakPenalty
    }

    deinit {
        tickTask?.cancel()
    }

    // MARK: - Hold gesture

    /// Starts (or restarts, after a release/failure) the 60-second hold. Call from the hold
    /// control's "pressed down" event. Idempotent while already holding.
    public func beginHold() {
        guard phase == .idle || phase == .failed else { return }
        lastError = nil
        phase = .holding
        progress = 0
        secondsRemaining = Int(Self.holdDuration)

        tickTask?.cancel()
        let startedAt = Date.now
        tickTask = Task { [weak self] in
            await self?.runHold(startedAt: startedAt)
        }
    }

    /// Call when the hold gesture ends before reaching `holdDuration` (finger lifted). Resets
    /// progress back to zero and returns to `.idle` — never a penalty by itself, so the user can
    /// simply try again.
    public func cancelHold() {
        guard phase == .holding else { return }
        tickTask?.cancel()
        tickTask = nil
        progress = 0
        secondsRemaining = Int(Self.holdDuration)
        phase = .idle
    }

    /// Lets a view toggle the "streak penalty option" (spec §4) explicitly, e.g. a switch next to
    /// the hold button. No-op once the hold has finished (`.completing`/`.unlocked`/`.failed`) —
    /// the decision is locked in the instant `completeHold` reads it.
    public func setAppliesStreakPenalty(_ appliesPenalty: Bool) {
        guard phase == .idle || phase == .holding else { return }
        appliesStreakPenalty = appliesPenalty
    }

    /// Convenience for a "use a streak freeze instead" secondary action: spends one of the user's
    /// `StreakEngine` freezes (spec §8 Never Miss Twice / freezes) and, if one was available,
    /// turns `appliesStreakPenalty` off. Safe to call at any point before the hold completes.
    ///
    /// - Returns: `true` if a freeze was spent (penalty now off); `false` if none was available
    ///   (`appliesStreakPenalty` is left unchanged).
    @discardableResult
    public func useStreakFreezeInstead(on date: Date = .now) async -> Bool {
        guard phase == .idle || phase == .holding else { return false }
        guard await StreakEngine.shared.useFreeze(on: date) else { return false }
        appliesStreakPenalty = false
        return true
    }

    // MARK: - Private

    private func runHold(startedAt: Date) async {
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(startedAt)
            if elapsed >= Self.holdDuration {
                progress = 1
                secondsRemaining = 0
                await completeHold()
                return
            }
            progress = elapsed / Self.holdDuration
            secondsRemaining = max(0, Int((Self.holdDuration - elapsed).rounded(.up)))
            try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
        }
    }

    /// Ends the lock via `LockEngineManager.shared.emergencyUnlock(sessionID:)` and, if
    /// `appliesStreakPenalty` is still `true` at this instant, records the miss via
    /// `StreakEngine.shared.recordMiss(on:)` — exactly the call this task's CONTRACTS specifies
    /// for "if the penalty is chosen".
    private func completeHold() async {
        phase = .completing
        do {
            try await LockEngineManager.shared.emergencyUnlock(sessionID: sessionID)
            if appliesStreakPenalty {
                await StreakEngine.shared.recordMiss(on: .now)
            }
            phase = .unlocked
        } catch {
            lastError = error
            phase = .failed
        }
    }
}
