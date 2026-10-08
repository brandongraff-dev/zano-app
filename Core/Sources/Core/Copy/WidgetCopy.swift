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

    // MARK: - Charged star (Home + Lock Screen)
    //
    // Widgets can't read Screen Time numbers (only the DeviceActivityReport extension can), so the
    // star's charge is goal progress, and this copy says "goals", never "screen time".

    public static let widgetDescription = "Your goals charge the star. Finish them to unlock."
    public static let allGoalsDone = "All goals done"

    /// "Locked · Social" — the status line above the medium/large widget's big number.
    public static func lockStatusLine(lockSetName: String?) -> String {
        guard let lockSetName, !lockSetName.isEmpty else { return "Locked" }
        return "Locked · \(lockSetName)"
    }

    /// The unit under the big "2" on the medium/large widget.
    public static func goalsLeftUnit(_ count: Int) -> String {
        count == 1 ? "goal left" : "goals left"
    }

    /// "2 goals to unlock" — the rectangular Lock Screen headline.
    public static func goalsToUnlock(_ count: Int) -> String {
        count == 1 ? "1 goal to unlock" : "\(count) goals to unlock"
    }

    /// "1 of 3 goals" — progress when no lock is running.
    public static func goalsDone(_ done: Int, of total: Int) -> String {
        "\(done) of \(total) goals"
    }

    /// VoiceOver label for the charged star.
    public static func chargeAccessibility(done: Int, total: Int) -> String {
        total == 0 ? "No goals yet" : "\(done) of \(total) goals done"
    }

    // MARK: - Time Bank widget (session 35, spec §5.2)
    //
    // "You've earned 20 min" at a glance. The balance is today's minutes still to spend; they
    // expire at midnight, so nothing here says "saved" or "total".

    public static let timeBankWidgetDescription = "The minutes you've earned today, ready to spend."
    public static let timeBankSpendButton = "Spend"
    public static let timeBankEarnMoreButton = "Earn more"
    public static let timeBankOpenButton = "Open ZANO"
    public static let timeBankAllEarned = "All goals banked today"
    public static let timeBankEmptyHint = "Finish a goal to earn minutes"
    /// The unit inside the circular Lock Screen gauge.
    public static let timeBankMinutesUnit = "min"

    /// The words beside the big number: "min earned" until something is spent, then "min left".
    public static func timeBankUnit(spentMinutes: Int) -> String {
        spentMinutes > 0 ? "min left" : "min earned"
    }

    /// "Earned 60 · spent 25", or just "Earned 60" before anything is spent.
    public static func timeBankEarnedSpent(earned: Int, spent: Int) -> String {
        spent > 0 ? "Earned \(earned) · spent \(spent)" : "Earned \(earned)"
    }

    /// "Gym +90 min": the next goal that adds minutes.
    public static func timeBankNextEarn(title: String, minutes: Int) -> String {
        "\(title) +\(minutes) min"
    }

    /// "Time Bank · 35 min" — the rectangular Lock Screen headline.
    public static func timeBankHeadline(balance: Int) -> String {
        "\(timeBankTitle) · \(balance) min"
    }

    /// "35 min earned" / "35 min left" — the inline Lock Screen line.
    public static func timeBankInline(balance: Int, spent: Int) -> String {
        "\(balance) \(timeBankUnit(spentMinutes: spent))"
    }

    /// VoiceOver for the balance: "20 minutes earned", or "35 minutes left, 60 earned and 25 spent
    /// today", or "No minutes earned yet".
    public static func timeBankAccessibility(balance: Int, earned: Int, spent: Int) -> String {
        if earned == 0 && balance == 0 { return "No minutes earned yet" }
        if spent == 0 { return "\(minutesWord(balance)) earned" }
        return "\(minutesWord(balance)) left, \(earned) earned and \(spent) spent today"
    }

    private static func minutesWord(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    // MARK: - Lock Screen widget

    public static let lockScreenConfigTitle = "ZANO Stat"
    public static let metricGoals = "Goals"
    public static let lockScreenConfigDescription = "Choose which stat this Lock Screen widget shows."
    public static let metricProtein = "Protein"
    public static let metricWater = "Water"
    public static let metricStreak = "Streak"

    /// "Gym + Protein" — the goals still standing between the user and an unlock, for the
    /// rectangular Lock Screen widget. Two names, then "+1" for the rest, so it fits one line.
    public static func remainingGoalNames(_ titles: [String]) -> String? {
        let names = titles.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(2).joined(separator: " + ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }

    /// "Unlocked · 14-day streak" — the unlocked rectangular headline caption.
    public static func unlockedWithStreak(_ streak: Int) -> String {
        streak > 0 ? "\(noActiveLock) · \(Self.streak(streak))" : noActiveLock
    }

    public static func inlineStatus(isLocked: Bool, goalsRemaining: Int) -> String {
        guard isLocked else { return "Unlocked" }
        return goalsRemaining > 0 ? "Locked · \(Self.goalsRemaining(goalsRemaining))" : "Locked"
    }

    // MARK: - Controls (iOS 18+)

    // The lock control only ever STARTS a lock. While a lock runs, tapping it opens ZANO, where
    // the goals and the emergency unlock live; Control Center can never end a lock by itself.
    public static let controlLockTitle = "Start lock"
    public static let controlLockDescription = "Start your ZANO lock. While locked, opens ZANO."
    public static let controlLockedLabel = "Locked"

    /// The locked control's label: "2 goals left", or "Locked" once nothing is left.
    public static func controlLockedStatus(goalsRemaining: Int) -> String {
        goalsRemaining > 0 ? Self.goalsRemaining(goalsRemaining) : controlLockedLabel
    }

    public static let controlLogWaterTitle = "Log water"
    public static let controlLogWaterDescription = "Log 500ml of water."
    public static let controlLogShakeTitle = "Log shake"
    public static let controlLogShakeDescription = "Log 25g of protein."
    public static let controlStartFocusTitle = "Start focus"
    public static let controlStartFocusDescription = "Start a 25-minute focus session."
    public static let controlLogCreatineTitle = "Log creatine"
    public static let controlLogCreatineDescription = "Log today's creatine dose."


    // MARK: - Live Activities

    public static let focusPausedLabel = "Paused"
    public static let focusEndButton = "End"
    public static let focusLiveActivityDisplay = "ZANO Focus"
    /// VoiceOver label for the focus block's progress bar on the Lock Screen banner; the system
    /// speaks the value as a percentage (session 41).
    public static let focusProgressAccessibilityLabel = "Focus progress"

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
