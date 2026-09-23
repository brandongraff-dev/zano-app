// Core/Sources/Core/Intents/LogCreatineIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | LogCreatineIntent | — | 1/day |
// docs/spec.md §3 (Goal Catalog: Creatine / supplement, Tier B — "NFC tap on tub, or widget
// button"; anti-cheat: "1 per day").
//
// No dictated Siri phrase (spec §6 lists only four phrases and creatine isn't one of them) — this
// intent is reached via an NFC tag tap or a widget/Control button, both of which construct the
// intent programmatically and can set `source` explicitly; the `@Parameter` default (`.manual`)
// only matters for an in-app "log manually" button.
//
// The "1/day" cap is enforced here (`IntentSupport.hasVerifiedEventToday`) rather than left to a
// later aggregation step, since — unlike protein/water, which accumulate toward a gram/ml target
// across multiple taps — creatine is a single daily yes/no per spec's own anti-cheat column.

import AppIntents
import Foundation
import SwiftData

public struct LogCreatineIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Creatine"

    public static var description: IntentDescription {
        IntentDescription(
            "Logs today's creatine or supplement dose.",
            categoryName: "Log"
        )
    }

    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Source", default: .manual)
    public var source: GoalLogSource

    public init() {}

    public init(source: GoalLogSource = .manual) {
        self.source = source
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        guard let goal = try IntentSupport.activeGoal(ofType: .creatine, for: user.id, in: context) else {
            throw ZanoIntentError.goalNotFound
        }

        if try IntentSupport.hasVerifiedEventToday(for: goal.id, in: context) {
            // No shame, no error — spec §8 rule 9: "Copy never says 'you failed.'" Already done
            // today is a fine, boring outcome, not a problem to surface as a failure.
            // Instrumentation (spec §23: "Instrument from day one: ... every intent").
            Analytics.shared.capture(
                event: "intent_log_creatine",
                properties: ["source": source.rawValue, "counted": false]
            )
            return .result(dialog: "Already logged today.")
        }

        let event = GoalEvent(
            kind: .complete,
            value: 1,
            source: source.eventSource,
            verified: true,
            user: user,
            goal: goal
        )
        context.insert(event)
        try context.save()

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_log_creatine",
            properties: ["source": source.rawValue, "counted": true]
        )

        return .result(dialog: "Creatine logged.")
    }
}
