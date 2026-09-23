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
        public static let timeBankFootnote = "Unused minutes expire at midnight."
        public static let lockedSincePrefix = "Locked since"
        /// No trailing colon: `lockedSincePrefix` and `WidgetCopy.nextLock` have none, and the time
        /// follows in its own `Text`.
        public static let nextLockPrefix = "Next lock"
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

        public static let emergencyUnlockTitle = "Hold to unlock in an emergency"
        /// Deliberately makes no promise about the streak: the two emergency paths disagree on
        /// whether a penalty applies (`EmergencyUnlock.appliesStreakPenalty` defaults to `true`;
        /// `LockStatusView` calls `LockEngineManager.emergencyUnlock` directly), so "no streak
        /// penalty" was an unverified guarantee. State the exact rule here once it is settled
        /// (docs/design/writing-findings.md §5.1 and §9.3).
        public static let emergencyUnlockFootnote = "Always available."

        // MARK: - Design pass 2026-09-23 (moved here from `LockStatusView.swift`'s `extension Copy.lockStatus`)
        //
        // `LockStatusView` was redesigned around a Lock-specific hero number and briefly carried these
        // in an `extension Copy.lockStatus` at the bottom of the view file (App target), because this
        // file was outside that task's edit list. They are user-facing copy, so they live here
        // (CLAUDE.md: `Core/Sources/Core/Copy`); values and call-site shapes are unchanged.

        public static let heroEyebrowLocked = "Locked"
        public static let heroEyebrowUnlocking = "Unlocking"
        public static let heroAllDone = "All goals done"
        public static let heroNextLock = "Next lock"

        /// `"Next lock · Wednesday"` — the label over the next-lock time when it isn't today.
        public static func heroNextLockOn(day: String) -> String { "Next lock · \(day)" }

        /// The hero line for the open-goal count ("2 goals left"). Same words as Today's hero.
        public static func heroGoalsLeftLine(count: Int) -> String { Copy.today.heroGoalsLeftLine(count: count) }

        /// The hero line for the Time Bank ("45 min available"): the number leads, the words trail.
        public static func heroBankLine(minutes: Int) -> String { "\(minutes) min available" }

        /// The Lock screen's Time Bank footnote. `timeBankFootnote` above carries the same words (its
        /// old text cited "spec §5.2" and was cleaned up in the copy pass); this is the key the screen
        /// calls, kept so no call site changes.
        public static let timeBankExpiryNote = "Unused minutes expire at midnight."

        /// `"72/150g"`, `"25/50 min"`. Same shape as Today's ring value.
        public static func goalValue(current: Int, target: Int, unit: String) -> String {
            Copy.today.progressValue(current: current, target: target, unit: unit)
        }

        public static let goalDone = "Done"
        public static let goalNotYet = "Not yet"

        /// Spoken status for a goal row (the row's own glyph carries no words).
        public static let goalStatusComplete = "Complete"
        public static let goalStatusInProgress = "In progress"
        public static let goalStatusPending = "Not started"
    }
}
