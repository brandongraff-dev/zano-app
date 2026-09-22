// Core/Sources/Core/LiveActivity/EarnMeterActivityAttributes.swift
//
// docs/spec.md §5.11 "Dynamic Island Earn Meter":
//   "During a lock, the Dynamic Island / Live Activity shows the Time Bank, goals remaining, and
//   next scheduled lock. During gym dwell: elapsed time at the gym and 'verified in 12 min.'"
//   (the gym-dwell half of that section is `GymDwellActivityAttributes`, same folder, another
//   session — this file is the *lock* half: the Earn Mode Time Bank meter.)
// docs/spec.md §6 "Widgets, Controls, Live Activities, NFC, Siri" → Live Activities:
//   "Active lock (Earn Mode): Time Bank draining bar."
//
// SYSTEM CONTRACTS (orchestrator-fixed public shape):
//   struct EarnMeterActivityAttributes: ActivityAttributes {
//       struct ContentState: Codable, Hashable { var earnedMinutesRemaining: Int; var goalsRemaining: Int; var nextLockTime: Date? }
//       var lockSetName: String
//   }
// Implemented below with that exact shape, plus `public`/explicit-init boilerplate needed for a
// public Core type to be constructible from the App and Extensions targets that import it (Swift
// does not synthesize a public memberwise init for a public type — see e.g. `Gym.swift`,
// `GoalEvent.swift` in Core/Sources/Core/Models, and this folder's own `GymDwellActivityAttributes`
// for the same pattern already used in this repo).
//
// `Extensions/ZANOWidgets/LiveActivities/ZANOEarnMeterLiveActivity.swift` (a different target,
// already on disk as of this task) renders this exact shape: `context.attributes.lockSetName` for
// the headline, and `context.state.earnedMinutesRemaining` / `.goalsRemaining` / `.nextLockTime`
// for the draining bar, goals-remaining line, and next-lock countdown. Nothing here may drift from
// what that file already reads.
//
// `ActivityAttributes` (ActivityKit) refines `Codable & Hashable` on the *whole* type, not just
// `ContentState` — every stored property below is a `String`/`Int`/`Date?`, so both conformances
// are synthesized automatically for this type and for `ContentState`, matching this folder's other
// two attributes files.

import ActivityKit
import Foundation

/// Fixed (non-changing for the lifetime of one Live Activity) attributes for the Earn Meter: which
/// `LockSet` is currently active. Everything that changes as the Time Bank drains or refills while
/// the lock is in effect — remaining minutes, goals still owed, the next scheduled lock — lives in
/// ``ContentState`` instead, per ActivityKit's attributes/content-state split.
public struct EarnMeterActivityAttributes: ActivityAttributes {

    /// The part of the Live Activity that updates while an Earn Mode lock is running. ActivityKit
    /// content updates replace this wholesale (they are not incremental/patched), so every field
    /// the widget needs to redraw the meter must be present here.
    public struct ContentState: Codable, Hashable {
        /// Minutes still available to spend right now — mirrors
        /// `TimeBankEngine.remainingMinutes(for:)` (`Core/Sources/Core/LockEngine/
        /// TimeBankEngine.swift`) for whatever calendar day the lock's Time Bank ledger is keyed
        /// to. This is the number the draining bar (spec §6: "Time Bank draining bar") renders.
        public var earnedMinutesRemaining: Int

        /// How many of the active `LockSession.requiredGoalIDs` are still unmet — mirrors
        /// `LockEngineManager`'s `SharedDefaults.goalsRemainingForActiveLock`
        /// (`Core/Sources/Core/Store/SharedDefaults.swift`), so the widget doesn't need its own
        /// SwiftData fetch just to render "2 goals left" (docs/spec.md §27: extensions must stay
        /// tiny and fast).
        public var goalsRemaining: Int

        /// When the lock is next scheduled to re-arm (a `DeviceActivity` schedule or the Bedtime
        /// Gate, spec §5.10) — mirrors `SharedDefaults.nextScheduledLockAt`. `nil` when nothing is
        /// scheduled (e.g. a purely manual/NFC-triggered lock with no recurring schedule).
        public var nextLockTime: Date?

        public init(earnedMinutesRemaining: Int, goalsRemaining: Int, nextLockTime: Date?) {
            self.earnedMinutesRemaining = earnedMinutesRemaining
            self.goalsRemaining = goalsRemaining
            self.nextLockTime = nextLockTime
        }
    }

    /// Display name of the `LockSet` (`Core/Sources/Core/Models/LockSet.swift`, `.name`) this
    /// Earn Mode lock is shielding, copied in at Activity start so the Live Activity/Dynamic
    /// Island never needs a SwiftData fetch just to render its headline (docs/spec.md §27).
    public var lockSetName: String

    public init(lockSetName: String) {
        self.lockSetName = lockSetName
    }
}
