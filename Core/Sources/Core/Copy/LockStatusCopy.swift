// LockStatusCopy.swift
// Core / Copy
//
// `Copy.lockStatus` — every user-facing string `App/ZANO/Features/Lock/LockStatusView.swift` calls,
// under the `Copy.<area>.<key>` umbrella this codebase actually uses (see `Copy.swift`'s header).
//
// Repo-wide Copy sweep (2026-09-22): `LockStatusView.swift` previously defined its own `private enum
// Copy` nested inside the view, pointing at its own header comment's "see TodayView.swift's header
// for why copy is a private enum here" rationale — see `TodayCopy.swift` (this same sweep) for why
// that's exactly the "flat standalone enum" mistake this sweep exists to catch, even though it
// compiled (a nested type shadows the module-level `Core.Copy` inside its own scope, so it wasn't a
// build break). Every string value below is copied verbatim from that file's removed private enum,
// so this is a pure move, not a rewrite. `LockTrigger` is `Core.LockEngineManager`'s real type
// (`Core/Sources/Core/LockEngine/LockEngineManager.swift`), imported implicitly since this file is
// itself inside the `Core` module.

import Foundation

extension Copy {
    public enum lockStatus {
        public static let screenTitle = "Lock"
        public static let unlockedHeadline = "Unlocked"
        public static let lockedHeadlineSingular = "Locked · 1 goal left"
        public static func lockedHeadlinePlural(_ count: Int) -> String { "Locked · \(count) goals left" }

        public static let requiredGoalsHeading = "Required to unlock"
        public static let timeBankHeading = "Time Bank"
        public static let timeBankFootnote = "Unused minutes expire at midnight — spec §5.2, no hoarding."
        public static let lockedSincePrefix = "Locked since"
        public static let nextLockPrefix = "Next lock:"
        public static let noScheduleLine = "No lock scheduled right now."

        public static func triggerLine(_ trigger: LockTrigger?) -> String {
            switch trigger {
            case .nfc: "Started by NFC tap"
            case .schedule: "Started by your schedule"
            case .manual: "Started manually"
            case .auto: "Started automatically"
            case nil: ""
            }
        }

        public static let emergencyUnlockTitle = "Hold to emergency unlock"
        public static let emergencyUnlockFootnote = "Always available. No streak penalty, no judgment."
    }
}
