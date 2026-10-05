// Core/Sources/Core/Intents/StartFocusIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | StartFocusIntent | minutes | Starts timer + Live Activity, shields on |
// docs/spec.md §3 (Goal Catalog: "Focus session | A | In-app timer (25/50/90 min) with shields
// active; Live Activity shows countdown").
//
// Calls `FocusSessionVerifier.shared.startSession(goalID:plannedMinutes:)` with the exact
// signature from this task's system contracts. The "Live Activity" and "shields on" halves of
// this intent's effect are `FocusSessionVerifier`'s job, not duplicated here — CLAUDE.md: "never
// duplicate the same logic in two places." This file only resolves *which* goal the session
// verifies against (spec's param list is just `minutes`; the contract needs a `goalID` too) and
// hands off.

import AppIntents
import Foundation
import SwiftData

/// `LiveActivityIntent` (not plain `AppIntent`) so a run from the Home widget, Control Center, an
/// NFC tag or Siri executes in the app's process, like `StartLockIntent`: the session, its tick
/// loop and its persisted record live there, so it can end itself (verified) at zero and be
/// re-adopted after a relaunch. A session started in a widget's own process was never verified
/// (audit L4).
public struct StartFocusIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Start Focus Session"

    public static var description: IntentDescription {
        IntentDescription(
            "Starts a timed focus session with shields active.",
            categoryName: "Focus"
        )
    }

    public static let openAppWhenRun: Bool = false

    /// Matches the 25/50/90-minute presets from spec §3, defaulting to 25. Any positive value is
    /// accepted — the presets are a UI convenience (App-owned), not a hard constraint here.
    @Parameter(title: "Minutes", description: "How long to focus for.", default: 25)
    public var minutes: Int

    /// Which `Goal` (type `.focusSession`) this session verifies. Optional: when left unset, the
    /// user's active focus-session goal is resolved automatically
    /// (`IntentSupport.activeGoal(ofType:for:in:)`) — the common case for the "start a focus
    /// session" Siri phrasing, which doesn't name a goal. A widget offering more than one focus
    /// goal can pass this explicitly instead.
    @Parameter(title: "Focus Goal", description: "Which focus goal this session counts toward. Defaults to your active Focus goal.")
    public var focusGoal: GoalEntity?

    public init() {}

    public init(minutes: Int = 25, focusGoal: GoalEntity? = nil) {
        self.minutes = minutes
        self.focusGoal = focusGoal
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes)-minute focus session") {
            \.$focusGoal
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        let goalID: UUID
        if let focusGoal {
            goalID = focusGoal.id
        } else if let goal = try IntentSupport.activeGoal(ofType: .focusSession, for: user.id, in: context) {
            goalID = goal.id
        } else {
            throw ZanoIntentError.noFocusGoalConfigured
        }

        let clampedMinutes = max(1, minutes)
        // Started outside the app (Siri, widget, Control Center, NFC): the person isn't in the app
        // to leave it, so the session doesn't pause on app background.
        _ = try await FocusSessionVerifier.shared.startSession(
            goalID: goalID,
            plannedMinutes: clampedMinutes,
            pausesWhenAppLeaves: false
        )

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_start_focus",
            properties: ["minutes": clampedMinutes, "goal_id": goalID.uuidString]
        )

        return .result(dialog: "Focus started for \(clampedMinutes) minutes.")
    }
}
