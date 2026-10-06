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

// MARK: - Spend control (buildout Wave 2F, 2026-09-25)

extension Copy.lockStatus {
    public static let spendSectionTitle = "Spend minutes"
    public static let spendSectionDetail = "Open your apps now. Goals still unlock them for good."
    /// A choice chip: `"15 min"`, or `"All 45 min"`.
    public static func spendChoice(minutes: Int, isAll: Bool) -> String {
        isAll ? "All \(minutes) min" : "\(minutes) min"
    }
    public static func spendChoiceSpoken(minutes: Int) -> String { "Spend \(minutes) minutes" }
    public static let spendExtendHint = "Spending more adds to the time."
    public static let spendNoEarnLock = "No Earn Mode lock is running."
}

// MARK: - Lock trust pass (2026-10-02): blocking line, Screen Time self-check, Time Bank borrow

extension Copy.lockStatus {
    /// What's blocked, counts only: `"12 apps"`, `"2 categories + 5 apps"`, `"1 website"`. Token
    /// contents are never shown. `nil` counts (couldn't read the selection) or all zero read as
    /// "your apps".
    public static func blockingWhat(apps: Int?, categories: Int?, websites: Int?) -> String {
        var parts: [String] = []
        if let categories, categories > 0 { parts.append(categories == 1 ? "1 category" : "\(categories) categories") }
        if let apps, apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if let websites, websites > 0 { parts.append(websites == 1 ? "1 website" : "\(websites) websites") }
        return parts.isEmpty ? "your apps" : parts.joined(separator: " + ")
    }

    /// The one honest line under the hero while a lock runs:
    /// `"Blocking 12 apps · ends when your goals are done"`, `"Blocking 5 apps · ends at 9:00 PM"`,
    /// or during a Time Bank window `"Apps open until 3:45 PM · locks again after"`.
    public static func blockingLine(_ summary: LockBlockingSummary) -> String {
        if let open = summary.openUntil {
            return "Apps open until \(open.formatted(date: .omitted, time: .shortened)) · locks again after"
        }
        let what = blockingWhat(apps: summary.appCount, categories: summary.categoryCount, websites: summary.webDomainCount)
        let ending: String
        switch summary.ending {
        case .whenGoalsDone: ending = "ends when your goals are done"
        case .at(let date): ending = "ends at \(date.formatted(date: .omitted, time: .shortened))"
        case .whenEnded: ending = "on until you end it"
        }
        return "Blocking \(what) · \(ending)"
    }

    // Visual direction v2 (2026-10-02): the blocking line as two facts instead of one middle-dot
    // sentence. `blockingLine` above stays (VoiceOver labels and tests use it).

    /// What the lock is doing: `"Blocking 12 apps"`, or `"Apps open until 3:45 PM"` during a window.
    public static func blockingHeadline(_ summary: LockBlockingSummary) -> String {
        if let open = summary.openUntil {
            return "Apps open until \(open.formatted(date: .omitted, time: .shortened))"
        }
        return "Blocking \(blockingWhat(apps: summary.appCount, categories: summary.categoryCount, websites: summary.webDomainCount))"
    }

    /// When it ends: `"Ends when your goals are done"`, `"Ends at 9:00 PM"`, `"On until you end it"`,
    /// or `"Locks again after"` during a window.
    public static func blockingEnding(_ summary: LockBlockingSummary) -> String {
        if summary.openUntil != nil { return "Locks again after" }
        switch summary.ending {
        case .whenGoalsDone: return "Ends when your goals are done"
        case .at(let date): return "Ends at \(date.formatted(date: .omitted, time: .shortened))"
        case .whenEnded: return "On until you end it"
        }
    }

    /// The (i) beside the borrow card's title, which now holds `borrowSectionDetail`.
    public static let borrowInfoLabel = "About borrowing"
    /// The (i) beside the spend card's title, which now holds `spendSectionDetail`.
    public static let spendInfoLabel = "About spending minutes"

    // Screen Time self-check (`LockHealthCheck`)
    public static let healthAccessOffTitle = "Screen Time access is off — ZANO can't block apps"
    public static let healthAccessOffDetail = "Your lock is still on in ZANO, but iOS isn't letting it block anything. Turn access back on to fix it."
    public static let healthShieldMissingTitle = "Your lock isn't blocking right now"
    public static let healthShieldMissingDetail = "The lock is running but no apps are shielded. Fix it to put the block back."
    public static let healthFixButton = "Fix it"
    public static let healthFixFailed = "Still off. Open Settings, then Screen Time, and allow ZANO."
    public static let healthFixed = "Fixed. ZANO is blocking again."

    // Time Bank borrow ("5 minutes now, from your Time Bank") — any lock mode
    public static let borrowSectionTitle = "Need a few minutes?"
    public static let borrowSectionDetail = "Borrow from your Time Bank. Your lock comes back on its own."
    /// The main action: `"Borrow 5 min from your Time Bank"`.
    public static func borrowButtonLabel(minutes: Int) -> String { "Borrow \(minutes) min from your Time Bank" }
    /// A chip: `"10 min"`.
    public static func borrowChip(minutes: Int) -> String { "\(minutes) min" }
    public static func borrowChipSpoken(minutes: Int) -> String { "Borrow \(minutes) minutes" }
    /// `"45 min in your bank"`.
    public static func borrowBalance(minutes: Int) -> String { "\(minutes) min in your bank" }
    /// Empty bank during an Earn Mode lock (goals add minutes there).
    public static let borrowEmptyEarn = "Your Time Bank is empty — finish a goal to earn minutes"
    /// Empty bank during a full lock: goals end the lock rather than adding minutes, so say that.
    public static let borrowEmptyFull = "Your Time Bank is empty — finish a goal to earn minutes"
    public static func borrowNotEnough(remaining: Int) -> String { "Only \(remaining) min in your bank." }
    public static let borrowNoLock = "No lock is running."
    public static let borrowFailed = "Couldn't open your apps. Try again."
    public static let borrowExtendHint = "Borrowing more adds to the time. Your lock comes back after."
}
