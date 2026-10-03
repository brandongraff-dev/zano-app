// OnboardingShortFlowCopy.swift
// Core / Copy
//
// Strings the 7-step onboarding (founder decision 2026-10-02: first real win within ~3 minutes)
// needed that no existing key covered, plus the Today "Finish setup" items that took over the setup
// topics onboarding no longer asks about (coach voice, Sunrise alarm, squads). Kept in their own
// file so the merge added wording without rewording anything: every existing `Copy.onboarding` key
// keeps its text. Same voice as `OnboardingCopy.swift`: plain, calm, sentence case, no urgency.

import Foundation

extension Copy.onboarding {

    // MARK: - Step 1: Hook (the proof strip that used to be its own screen)

    /// Small label over the three product claims under the hook headline.
    public static let hookProofEyebrow = "How it works"

    // MARK: - Step 3: Your why (phone time + when it slips + the math, one step)

    public static let yourWhyTitle = "What's your phone costing you?"
    public static let yourWhySubtitle = "Be honest. No judgment here."
    /// Above the optional "when does it slip" chips.
    public static let yourWhySlipLabel = "When does your routine usually slip? (optional)"

    /// The reclaim line under the cost: "Earn 2h a day back: 30 days a year back."
    public static func yourWhyReclaimLine(hoursLabel: String, days: Int) -> String {
        "Earn \(hoursLabel) a day back: \(days) days a year back."
    }

    // MARK: - Step 4: Apps (when Screen Time access was refused)

    /// Lets someone who refused Screen Time access keep going; the first win then runs without a
    /// lock, and Today's first-day checklist offers to pick apps again.
    public static let q2ContinueWithoutLockButton = "Continue without locking"

    // MARK: - Step 5: Plan + commit

    /// Under the plan card, above the hold-to-commit button.
    public static let planCommitHint = "Hold for 2 seconds. This is you, deciding."
    /// Shown on the plan card's apps row when no apps were picked (Screen Time access refused).
    public static let planNoAppsLine = "Pick apps to lock anytime from Today."

    // MARK: - Step 7: First win

    /// The intro subtitle when there is nothing to lock (no Screen Time access or no apps): the
    /// timer still runs and still earns Day 1.
    public static let firstWinSubtitleNoLock = "2-minute focus to earn Day 1."
    /// The one-line notification priming that used to be its own screen. Starting the session asks
    /// for notification permission once, right after this line.
    public static let firstWinNotificationLine = "We'll only nudge when it matters."
    /// Accessibility value of the charging star during the session.
    public static func firstWinStarAccessibilityValue(percent: Int) -> String {
        "\(percent)% charged"
    }
    /// Spoken label for the big countdown.
    public static func firstWinCountdownAccessibilityLabel(minutes: Int, seconds: Int) -> String {
        let minutePart = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondPart = seconds == 1 ? "1 second" : "\(seconds) seconds"
        return "\(minutePart) \(secondPart) left"
    }

    // MARK: - Today "Finish setup" items moved out of onboarding

    public static let finishSetupVoiceTitle = "Pick your coach voice"
    public static let finishSetupVoiceDetail = "Hype, Tough Love, Chill or Data. You're on Hype."
    public static let finishSetupSunriseTitle = "Set your Sunrise alarm"
    public static let finishSetupSunriseDetail = "Wake up, tap to prove it, start the day locked in."
    public static let finishSetupSquadTitle = "Start a squad"
    public static let finishSetupSquadDetail = "See each other's rings. Nudge each other."
    /// The coach voice sheet's title and its close button.
    public static let finishSetupVoiceSheetTitle = "Pick your coach voice"
    public static let finishSetupVoiceSheetSubtitle = "How should ZANO talk to you?"
}
