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

        /// The UI tests find the emergency control by this exact text; it stays the control's
        /// spoken label for the whole hold.
        public static let emergencyUnlockTitle = "Hold to unlock in an emergency"
        /// Visible title while the 60-second hold runs: `"Keep holding · 42s"`.
        public static func emergencyUnlockHolding(secondsRemaining: Int) -> String {
            "Keep holding · \(secondsRemaining)s"
        }
        /// Visible title once the hold completed and the lock is being ended.
        public static let emergencyUnlockCompleting = "Ending the lock…"
        /// VoiceOver value while holding: `"42 seconds left"`.
        public static func emergencyUnlockSecondsLeftSpoken(_ seconds: Int) -> String {
            seconds == 1 ? "1 second left" : "\(seconds) seconds left"
        }
        /// VoiceOver hint. A sustained touch has no VoiceOver equivalent, so a double-tap starts the
        /// same 60-second countdown and a second double-tap stops it.
        public static let emergencyUnlockHint = "Hold for 60 seconds to end this lock. With VoiceOver, double-tap to start the countdown and double-tap again to stop it."
        /// Announced when the countdown starts or stops from VoiceOver.
        public static let emergencyUnlockCountdownStarted = "Emergency unlock in 60 seconds. Double-tap again to stop."
        public static let emergencyUnlockCountdownStopped = "Emergency unlock stopped. Your lock is still on."
        /// Announced once the lock has ended.
        public static let emergencyUnlockDone = "Lock ended. Your apps are open."
        /// The streak-penalty option (EmergencyUnlock.appliesStreakPenalty). On by default.
        public static let emergencyPenaltyToggle = "Count this as a slip on my streak"
        /// Footnote under the hold, matching the shield's "60-second hold" copy.
        public static func emergencyUnlockFootnote(appliesStreakPenalty: Bool) -> String {
            appliesStreakPenalty
                ? "Always available. Hold for 60 seconds to end this lock. It counts as a slip on your streak."
                : "Always available. Hold for 60 seconds to end this lock. Your streak stays as it is."
        }
        public static let emergencyUnlockFailed = "Couldn't end the lock. Hold again to retry."

        /// Shown above the paywall when a subscription lapsed while a lock is still on.
        public static let paywallLockStillOn = "A lock is still on. You can always end it here."

        /// The start-lock button's failure line.
        public static let lockStartFailed = "Couldn't start the lock. Try again."

        /// Under Lock's read-only goal list: goals are acted on from Today.
        public static let goToTodayTitle = "Go to Today to log these"

        /// The tab bar's Lock item while a lock is running (VoiceOver value).
        public static let tabLockRunningValue = "Lock running"

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

        public static let timeBankExpiryNote = "Unused minutes expire at midnight."

        // Time Bank spending (spec §5.2) — for the Lock tab's spend control.
        public static func spendButtonLabel(minutes: Int) -> String { "Spend \(minutes) min" }
        public static func spendUnlockedUntil(_ time: String) -> String { "Apps open until \(time)" }
        public static func spendNotEnough(remaining: Int) -> String {
            remaining == 0 ? "Your bank is empty. Do a goal to earn minutes." : "Only \(remaining) min in your bank."
        }
        public static let spendFullLockNote = "This is a full lock. Minutes can't open it."
        public static let spendFailed = "Couldn't open your apps. Try again."

        /// `"72/150g"`, `"25/50 min"`. Same shape as Today's ring value.
        public static func goalValue(current: Int, target: Int, unit: String) -> String {
            Copy.today.progressValue(current: current, target: target, unit: unit)
        }

        /// Goal status words, the same two Today uses.
        public static let goalDone = "Done"
        public static let goalNotYet = "Not yet"

        // MARK: - Idle state (empty-states pass 2026-09-24)
        //
        // The Lock tab with nothing running. The start button's title is deliberately not
        // `Copy.today.beginLockStandardTitle`: the UI tests find Today's begin-lock button by that
        // exact text. The hero's spoken label still leads with `unlockedHeadline`, which the tests
        // wait for after an emergency unlock.

        public static let idleHeadline = "No lock running"
        /// Under the headline when a lock could start right now.
        public static let idleReadyDetail = "Your apps are open. Lock in whenever you're ready."
        /// Under the headline when there's no default lock set or no active goal yet.
        public static let idleSetupDetail = "Pick your goals and the apps to lock on Today, then start your first lock."
        public static let idleStartLockTitle = "Start a lock now"
    }
}
