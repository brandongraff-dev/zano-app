// Core/Sources/Core/LiveActivity/GymDwellActivityAttributes.swift
//
// docs/spec.md §6 "Widgets, Controls, Live Activities, NFC, Siri" — Live Activities:
//   "Gym dwell: 'At the gym · 22 min · verified at 35'"
//
// SYSTEM CONTRACTS (orchestrator-fixed public shape):
//   struct GymDwellActivityAttributes: ActivityAttributes {
//       struct ContentState: Codable, Hashable { var elapsedMinutes: Int; var verifiedAtMinutes: Int; var isVerified: Bool }
//       var gymName: String
//   }
// Implemented below with that exact shape, plus `public`/explicit-init boilerplate needed for a
// public Core type to be constructible from the App and Extensions targets that import it (Swift
// does not synthesize a public memberwise init for a public type — see e.g. `Gym.swift`,
// `GoalEvent.swift` in Core/Sources/Core/Models for the same pattern already used in this repo).
//
// Wave 1A: `GymDwellActivityManager` (same folder) now owns request/update/end, driven by
// `GymPresenceService`. The paragraph below predates that and is kept for history.
//
// This file only defines the attributes/content-state contract. The Live Activity's actual
// start/update call sites (`Activity<GymDwellActivityAttributes>.request(attributes:content:
// pushType:)` and `.update(...)`) belong wherever the dwell loop lives that decides *when* to
// push a new `ContentState` — `GymVerifier.currentContentState(gymID:requiredMinutes:)`
// (GymVerifier.swift, same session) already assembles the exact value to push; wiring that into
// an actual `Activity` request/update loop is a deliberate cross-module integration point left
// for whichever session builds ZANOWidgets' Live Activity UI / LockEngine's dwell-tracking
// trigger, since starting an `Activity` needs to run in a context that already knows the app's
// Live Activity / push entitlement setup (project.yml, another session's scope).
//
// Known-uncertain detail (see this session's knownIssues): whether `ActivityAttributes` itself
// requires `Sendable` conformance varies by SDK version. Not declared explicitly here to match
// the orchestrator's given shape exactly; if the live SDK requires it, Swift synthesizes it
// automatically since every stored property below (`String`, `Int`, `Bool`) is trivially
// `Sendable`.

import ActivityKit
import Foundation

/// Live Activity shown while a gym dwell session (`GymVerifier`, Verification/GymVerifier.swift)
/// is in progress — docs/spec.md §6's "At the gym · 22 min · verified at 35".
public struct GymDwellActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Minutes dwelt so far in the current geofence session. Mirrors
        /// `GymVerifier.currentDwellMinutes(gymID:)`.
        public var elapsedMinutes: Int

        /// The dwell threshold this session needs to hit to verify — normally
        /// `GymVerificationDefaults.requiredDwellMinutes` (35, GymVerifier.swift), surfaced here
        /// rather than hardcoded in the widget so a future per-gym override still renders
        /// correctly without a widget-side change.
        public var verifiedAtMinutes: Int

        /// Mirrors `GymVerifier.isVerified(gymID:requiredMinutes:)`'s latest result, so the
        /// widget can switch from a running "22 min" state to a verified/checkmark state without
        /// re-deriving the `elapsedMinutes >= verifiedAtMinutes` comparison (and without silently
        /// disagreeing with `GymVerifier`'s own anti-cheat result, which a naive comparison here
        /// would).
        public var isVerified: Bool

        /// When the running dwell started (`nil` once it ended or when unknown). Added in Wave 1A
        /// so the widget can render a self-updating `Text(enteredAt, style: .timer)`: the app
        /// can't push `elapsedMinutes` every minute while it's suspended in the background, so a
        /// minute count alone goes stale on the Lock Screen. Optional + defaulted, so older
        /// encoded states and existing call sites keep working.
        public var enteredAt: Date?

        public init(elapsedMinutes: Int, verifiedAtMinutes: Int, isVerified: Bool, enteredAt: Date? = nil) {
            self.elapsedMinutes = elapsedMinutes
            self.verifiedAtMinutes = verifiedAtMinutes
            self.isVerified = isVerified
            self.enteredAt = enteredAt
        }
    }

    /// Display name of the gym this session is at (`Gym.name`, Core/Sources/Core/Models/Gym.swift).
    /// If the user never named their saved gym, the caller starting this Activity is responsible
    /// for substituting a generic label — that copy decision belongs in Core/Sources/Core/Copy
    /// per CLAUDE.md's "no hardcoded user-facing strings" rule, not in this attributes file.
    public var gymName: String

    /// The `Gym.id` this Activity tracks, so a relaunched app can re-adopt the right running
    /// Activity (`GymDwellActivityManager`). Optional + defaulted for source compatibility.
    public var gymID: UUID?

    public init(gymName: String, gymID: UUID? = nil) {
        self.gymName = gymName
        self.gymID = gymID
    }
}
