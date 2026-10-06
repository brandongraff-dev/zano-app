// OnboardingGuideCopy.swift
// Core / Copy
//
// The star's lines (visual pass 2, 2026-10-03, founder: "make it more playful"). In onboarding the
// living star is a guide character: it says one short line in a speech bubble and reacts to each
// answer. Rules for these lines: short, a little funny, never shaming, never a promise the product
// can't keep. The star talks in first person ("I'll build the rest"); everything else on the screen
// stays plain.
//
// `MainGoal` is an App-target type Core can't see, so the reaction takes its raw value (the same
// narrow pattern `planScheduleFallOffNote(patternLabel:)` uses). An unknown value falls back to a
// line that needs no answer.

import Foundation

extension Copy.onboarding {

    // MARK: - Step 1: Hook (the loop, as three stickers)

    /// One beat of the game loop shown under the hook headline: a short title and one line.
    public struct LoopBeat: Sendable, Equatable {
        public let title: String
        public let detail: String
    }

    /// Lock it, earn it, get it back. Replaces the three-sentence "How it works" card.
    public static let hookLoop: [LoopBeat] = [
        LoopBeat(title: "Lock it", detail: "Time-wasters go dark."),
        LoopBeat(title: "Earn it", detail: "Gym, focus, protein. Verified."),
        LoopBeat(title: "Get it back", detail: "Apps open the second you're done."),
    ]

    /// Spoken once for the whole loop row.
    public static let hookLoopSpoken = "How it works: lock your apps, earn them with verified goals, get them back the second you're done."

    // MARK: - Step 2: Main goal (character select)

    public static let guideMainGoalPrompt = "Pick your main quest. I'll build the rest."

    /// The star's reaction to the picked main goal. `rawValue` is `MainGoal.rawValue`.
    public static func guideMainGoalReaction(rawValue: String) -> String {
        switch rawValue {
        case "gymConsistency": "Gym era. Love that for you."
        case "protein": "Protein on lock. Your muscles say thanks."
        case "stopDoomscrolling": "Thumbs off the feed. We've got this."
        case "lockInWorkSchool": "Locked in. No side quests."
        case "allOfIt": "Full send. We'll start easy, though."
        default: "Good pick. Let's build it."
        }
    }

    // MARK: - Step 3: Your why (the counter)

    /// Under the big days counter: "if you earn 2h a day back".
    public static func yourWhyReclaimChip(days: Int) -> String {
        "+\(days) days back a year"
    }

    public static func yourWhyReclaimCondition(hoursLabel: String) -> String {
        "if you earn \(hoursLabel) a day back"
    }

    /// The hours chip above the counter: "5h a day".
    public static func yourWhyHoursChip(_ hoursLabel: String) -> String {
        "\(hoursLabel) a day"
    }

    /// The slip chips' heading, without the "(optional)" tail: the chips say it by being skippable.
    public static let yourWhySlipTitle = "When does it usually slip?"
    public static let yourWhySlipOptional = "Optional"

    // MARK: - Step 4: Apps

    public static let guideAppsPrompt = "Pick your villains. I'll guard the door."
    public static let guideAppsPicked = "Locked and loaded."

    // MARK: - Step 5: Plan

    public static let guidePlanLine = "Built from your answers. Starting easy on purpose."
    /// Shown inside the charge button while it is being held.
    public static let commitCharging = "Charging…"
}
