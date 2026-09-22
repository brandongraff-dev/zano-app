// Core/Sources/Core/LiveActivity/BedtimeWindDownActivityAttributes.swift
//
// docs/spec.md §5.10 ★ Bedtime Gate & Sunrise Alarm — Bedtime Gate:
//   "Optional wind-down Live Activity: 'Bedtime lock in 10 min.'"
// docs/spec.md §6 (Widgets, Controls, Live Activities, NFC, Siri) groups this under the same
// "Live Activities (ActivityKit)" list as Focus Session / Gym Dwell / Earn Meter.
//
// Defines the `ActivityAttributes` contract for the Bedtime wind-down Live Activity, following
// the exact shape convention every other LiveActivity file in this directory already uses
// (`FocusActivityAttributes`, `GymDwellActivityAttributes`, `EarnMeterActivityAttributes`):
// fixed identity in the top-level struct, everything that changes tick-to-tick in `ContentState`.
// `BedtimeGateManager.swift` (Core/Sources/Core/Verification, same task/session as this file) is
// the sole owner of starting/updating/ending this Activity — see that file for the actual
// `Activity<BedtimeWindDownActivityAttributes>.request`/`.update`/`.end` call sites.
//
// `ActivityAttributes` refines `Codable & Hashable` on the whole type; every stored property below
// is a `String`/`Int`/`Bool`, so both conformances (and `Sendable`, where the current SDK expects
// it — see `GymDwellActivityAttributes`'s doc comment on the same open question) are trivially
// satisfied either via synthesis or because every field is itself `Sendable`.

import ActivityKit
import Foundation

/// Live Activity shown during the wind-down window leading up to the Bedtime Gate's auto-arm
/// (docs/spec.md §5.10: "Bedtime lock in 10 min"), and briefly after arming to confirm the lock is
/// now in effect ("phone becomes a clock").
public struct BedtimeWindDownActivityAttributes: ActivityAttributes {

    /// The part of the Live Activity that updates while wind-down is counting down.
    public struct ContentState: Codable, Hashable {
        /// Minutes remaining until the Bedtime Gate auto-arms, floored at 0. `BedtimeGateManager`
        /// pushes a fresh value roughly once a minute while counting down; once the lock actually
        /// arms this settles at `0` and ``isLocked`` flips to `true` instead of this ticking
        /// negative.
        public var minutesUntilBedtime: Int

        /// `true` once `BedtimeGateManager.autoArmBedtimeLock` has actually applied the shield for
        /// tonight — lets the widget swap from a countdown ("Bedtime lock in 10 min") to a settled
        /// "Locked for the night" state without a second Activity type.
        public var isLocked: Bool

        public init(minutesUntilBedtime: Int, isLocked: Bool) {
            self.minutesUntilBedtime = minutesUntilBedtime
            self.isLocked = isLocked
        }
    }

    /// The configured bedtime, pre-formatted (e.g. `"10:30 PM"`) at Activity start so the widget
    /// extension never needs its own `DateFormatter`/locale lookup just to render the headline —
    /// mirrors `GymDwellActivityAttributes.gymName`'s and `FocusActivityAttributes.goalTitle`'s
    /// same "hand the extension a ready-to-render string" convention (docs/spec.md §27: widget
    /// extensions must stay tiny and fast).
    public var bedtimeLabel: String

    public init(bedtimeLabel: String) {
        self.bedtimeLabel = bedtimeLabel
    }
}
