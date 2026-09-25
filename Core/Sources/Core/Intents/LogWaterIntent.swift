// Core/Sources/Core/Intents/LogWaterIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | LogWaterIntent | ml, source | Writes goal_event |
// docs/spec.md §3 (Goal Catalog: Water, Tier B — "NFC tap on bottle (+ bottle size), widget
// button"; anti-cheat: "Tap rate limit (no 8 taps in a minute)"). §6 NFC section: "Log Water
// 750ml" — this intent's `milliliters` default (750) matches that exactly. §6 Siri phrase:
// "Log water" (wired up in `ZanoShortcuts.swift`).
//
// Same "Tier B tap is its own verification" reasoning as `LogProteinIntent`: writes
// `GoalEvent(kind: .verify, verified: true)`.

import AppIntents
import Foundation
import SwiftData

public struct LogWaterIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Water"

    public static var description: IntentDescription {
        IntentDescription(
            "Logs water toward today's goal.",
            categoryName: "Log"
        )
    }

    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Milliliters", description: "Milliliters of water.", default: 750)
    public var milliliters: Int

    @Parameter(title: "Source", default: .manual)
    public var source: GoalLogSource

    public init() {}

    public init(milliliters: Int = 750, source: GoalLogSource = .manual) {
        self.milliliters = milliliters
        self.source = source
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$milliliters)ml of water")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let goal = try IntentSupport.activeGoal(ofType: .water, for: user.id, in: context) else {
            throw ZanoIntentError.goalNotFound
        }

        // Anti-cheat (spec §3 Water row: "Tap rate limit (no 8 taps in a minute)").
        let tapsInLastMinute = try IntentSupport.recentEventCount(for: goal.id, withinSeconds: 60, in: context)
        let isRateLimited = tapsInLastMinute >= 8

        let event = GoalEvent(
            kind: .verify,
            value: Double(milliliters),
            source: source.eventSource,
            verified: !isRateLimited,
            meta: isRateLimited ? .object(["notCounted": .string("too_fast")]) : .object([:]),
            user: user,
            goal: goal
        )
        context.insert(event)
        try context.save()
        await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goal.id)

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_log_water",
            properties: ["milliliters": milliliters, "source": source.rawValue, "counted": !isRateLimited]
        )

        if isRateLimited {
            // Transparent, not accusatory — spec §9.8: "Never accuse — just don't count, and show
            // 'not counted: too quick' transparently."
            return .result(dialog: "That's a lot of taps at once — this one wasn't counted.")
        }
        return .result(dialog: "Logged \(milliliters)ml of water.")
    }
}
