// Core/Sources/Core/Intents/LogCustomGoalIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | LogCustomGoalIntent | goalId | Tier C with friction |
// docs/spec.md §3 (Goal Catalog: Custom goal, Tier C — "One tap after user-set friction (hold
// button, short reflection prompt)"; "Honesty" anti-cheat). Also covers the Cold shower / sauna
// row, which is the same Tier C shape ("One tap + optional photo").
//
// Scope split (same reasoning as `EmergencyUnlockIntent`): the "user-set friction" (a hold, a
// short reflection prompt) is a SwiftUI interaction owned by an App/ZANO/Features view. That view
// runs the friction step and only calls this intent once it's satisfied — this intent's job is
// just to record the resulting completion. Tier C is honesty-based by design (spec §3
// "Verification philosophy": "the point is friction and accountability, not surveillance"), so a
// call here is trusted and written as `verified: true` unconditionally.

import AppIntents
import Foundation
import SwiftData

public struct LogCustomGoalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Goal"

    public static var description: IntentDescription {
        IntentDescription(
            "Logs a custom goal as done for today.",
            categoryName: "Log"
        )
    }

    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Goal", description: "Which custom goal to log.")
    public var goal: GoalEntity

    public init() {}

    /// Where the log came from (not a user-facing parameter). NFC tags pass `.nfc`.
    public var logSource: GoalLogSource = .manual

    public init(goal: GoalEntity) {
        self.goal = goal
    }

    public init(goal: GoalEntity, source: GoalLogSource) {
        self.goal = goal
        self.logSource = source
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$goal) as done")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let matchedGoal = try IntentSupport.goal(withID: goal.id, for: user.id, in: context) else {
            throw ZanoIntentError.goalNotFound
        }

        let event = GoalEvent(
            kind: .complete,
            value: nil,
            source: logSource,
            verified: true,
            user: user,
            goal: matchedGoal
        )
        context.insert(event)
        try context.save()
        await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: matchedGoal.id)

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_log_custom_goal",
            properties: ["goal_id": matchedGoal.id.uuidString]
        )

        return .result(dialog: "\(matchedGoal.title) logged.")
    }
}
