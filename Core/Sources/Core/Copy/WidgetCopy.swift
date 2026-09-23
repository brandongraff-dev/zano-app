// WidgetCopy.swift
// Core / Copy
//
// User-facing copy for Extensions/ZANOWidgets (Home Screen widget, Lock Screen widget, iOS 18
// Controls, and the 3 Live Activities) — moved here from Extensions/ZANOWidgets/Support/
// ZANOWidgetCopy.swift, which this file replaces, per CLAUDE.md: "User-facing copy lives in
// Core/Sources/Core/Copy - no hardcoded UI strings elsewhere." The widget extension previously
// carried this copy locally with a header comment explicitly flagging it as known debt, on the
// grounds that `Core/Sources/Core/Copy` didn't exist yet when that file was written; it exists
// now (see `CoachVoice.swift`, `ShieldCopy.swift`, same directory), so the copy moves here.
//
// Not yet coach-voice-aware (docs/spec.md §5.13: Hype/Tough Love/Chill/Data) — widget/Control/
// Live-Activity chrome is tight on space and, per docs/spec.md §27, extensions must stay tiny and
// fast, so this is deliberately the same flat, single-voice copy the original file shipped, just
// relocated. A future pass that wants these voice-aware can route them through `CoachVoiceTone`
// (`CoachVoice.swift`, this directory) without any widget-side call site changing shape.

import Foundation

public enum WidgetCopy {
    // MARK: - Home Screen widget

    public static let appName = "ZANO"
    public static let startLockButton = "Start lock"
    public static let logProteinButton = "+25g"
    public static let logWaterButton = "+500ml"
    public static let startFocusButton = "Start focus"
    public static let todaysPlanTitle = "Today's plan"
    public static let timeBankTitle = "Time Bank"
    public static let noActiveLock = "Unlocked"

    public static func lockedStatus(lockSetName: String?) -> String {
        guard let lockSetName, !lockSetName.isEmpty else { return "Locked" }
        return "\(lockSetName) locked"
    }

    public static func goalsRemaining(_ count: Int) -> String {
        count == 1 ? "1 goal left" : "\(count) goals left"
    }

    /// "14-day streak" in words. This is also the VoiceOver label for the widget's numeral-plus-
    /// flame streak pill, so it can't be the emoji alone ("14🔥" read as "14 fire"), and it puts
    /// no flame on Data or Tough Love users who didn't choose one.
    public static func streak(_ count: Int) -> String { "\(count)-day streak" }

    public static func nextLock(_ date: Date?) -> String {
        guard let date else { return "No lock scheduled" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Next lock \(formatter.string(from: date))"
    }

    /// Time Bank balance still to spend, so "left" — not "unlocked", which reads as time already
    /// used (and dilutes the core lock/unlock verb). The celebration screen keeps the spec-verbatim
    /// "2h 10m unlocked" (`Copy.celebration.timeBankUnlockedLabel`), where it fits.
    public static func minutesRemaining(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 min left" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m left" }
        if hours > 0 { return "\(hours)h left" }
        return "\(mins) min left"
    }

    // MARK: - Lock Screen widget

    public static let lockScreenConfigTitle = "ZANO Stat"
    public static let lockScreenConfigDescription = "Choose which stat this Lock Screen widget shows."
    public static let metricProtein = "Protein"
    public static let metricWater = "Water"
    public static let metricStreak = "Streak"

    public static func inlineStatus(isLocked: Bool, goalsRemaining: Int) -> String {
        guard isLocked else { return "Unlocked" }
        return goalsRemaining > 0 ? "Locked · \(Self.goalsRemaining(goalsRemaining))" : "Locked"
    }

    // MARK: - Controls (iOS 18+)

    public static let controlLockToggleTitle = "Lock"
    public static let controlLockToggleDescription = "Turn your ZANO lock on or off."
    public static let controlLockedLabel = "Locked"
    public static let controlUnlockedLabel = "Unlocked"

    public static let controlLogWaterTitle = "Log water"
    public static let controlLogWaterDescription = "Log 500ml of water."
    public static let controlLogShakeTitle = "Log shake"
    public static let controlLogShakeDescription = "Log 25g of protein."
    public static let controlStartFocusTitle = "Start focus"
    public static let controlStartFocusDescription = "Start a 25-minute focus session."
    public static let controlLogCreatineTitle = "Log creatine"
    public static let controlLogCreatineDescription = "Log today's creatine dose."

    public static let controlNoDefaultLockSetMessage =
        "Add a lock set in ZANO before locking from Control Center."

    // MARK: - Live Activities

    public static let focusPausedLabel = "Paused"
    public static let focusEndButton = "End"
    public static let focusLiveActivityDisplay = "ZANO Focus"

    public static let gymVerifiedLabel = "Verified"
    public static let gymLiveActivityDisplay = "ZANO Gym"

    public static func gymDwellStatus(elapsedMinutes: Int, verifiedAtMinutes: Int) -> String {
        "At the gym · \(elapsedMinutes) min · verified at \(verifiedAtMinutes)"
    }

    public static let earnMeterLiveActivityDisplay = "ZANO Earn Meter"
    public static let viewTodayLink = "View Today"

    public static func earnMeterGoalsRemaining(_ count: Int) -> String {
        count == 0 ? "All goals done" : Self.goalsRemaining(count)
    }
}
