// Core/Sources/Core/Intents/LogWorkoutMinutesIntent.swift
//
// Session 42. docs/spec.md §3 (both workout rows accept minutes logged by hand as Tier C) and §14
// (every user action is an App Intent). Logs workout minutes by hand toward today's home/outdoor or
// gym workout goal, with no location, Health or Strava needed. Today's "Log minutes" sheet, the gym
// check-in screen and Siri all run this; the write itself is `HomeWorkoutVerifier.logManualMinutes`,
// so there is one write path.
//
// The friction (spec §3 Tier C: "honesty + friction") is the hold-to-confirm on the in-app sheet. Siri
// asks for the minutes and confirms by voice.

import AppIntents
import Foundation
import SwiftData

/// `LiveActivityIntent` like `LogWaterIntent`: the log may complete the last goal of a lock, and
/// ending that lock touches the shield, which only the app process can do.
public struct LogWorkoutMinutesIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Log Workout Minutes"

    public static var description: IntentDescription {
        IntentDescription(
            "Logs workout minutes by hand toward today's workout goal. No gym or location needed.",
            categoryName: "Log"
        )
    }

    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Minutes", description: "Minutes you worked out.", default: 30)
    public var minutes: Int

    @Parameter(title: "Source", default: .manual)
    public var source: GoalLogSource

    /// The workout goal to log against (Today and the gym screen pass theirs). `nil`: the home/outdoor
    /// workout goal, else the gym goal. Not a Siri parameter.
    public var goalID: UUID?

    public init() {}

    public init(minutes: Int = 30, source: GoalLogSource = .manual, goalID: UUID? = nil) {
        self.minutes = minutes
        self.source = source
        self.goalID = goalID
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$minutes) workout minutes")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        let goal: Goal?
        if let goalID {
            goal = try IntentSupport.goal(withID: goalID, for: user.id, in: context)
        } else {
            goal = try IntentSupport.activeGoal(ofType: .workoutHomeOutdoor, for: user.id, in: context)
                ?? IntentSupport.activeGoal(ofType: .workoutGym, for: user.id, in: context)
        }
        guard let goal, goal.type == .workoutHomeOutdoor || goal.type == .workoutGym else {
            throw ZanoIntentError.goalNotFound
        }
        let resolvedGoalID = goal.id
        let logged = ManualWorkoutMinutes.clamped(minutes)

        let result = try await HomeWorkoutVerifier.shared.logManualMinutes(
            goalID: resolvedGoalID,
            minutes: logged,
            source: source.eventSource
        )

        Analytics.shared.capture(
            event: "intent_log_workout_minutes",
            properties: ["minutes": logged, "source": source.rawValue, "completed": result.isCompleted]
        )

        let message = Copy.workoutMinutes.intentDialog(minutes: logged, result: result)
        return .result(dialog: "\(message)")
    }
}

extension ManualWorkoutLogResult {
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}
