// Core/Sources/Core/Intents/CheckStatusIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | CheckStatusIntent | — | Returns spoken/summary status for Siri |
// docs/spec.md §6 Siri phrase: "How am I doing today" (wired up in `ZanoShortcuts.swift`).
//
// Calls `StreakEngine.shared.currentStreak()` and `TimeBankEngine.shared.remainingMinutes(for:)`
// with the exact signatures from this task's system contracts, plus a direct read of today's
// `GoalEvent`s for the "goals done today" count. Reads `SharedDefaults.goalsRemainingForActiveLock`
// for the active-lock summary rather than recomputing it — that value is owned and kept current
// by `LockEngineManager` (see `Core/Sources/Core/Store/SharedDefaults.swift`'s own doc comment:
// "Treat SharedDefaults as read-mostly from everywhere except the one engine that owns each key"),
// so this intent only ever reads it, never writes it.
//
// The dialog text here is plain and factual on purpose, not styled to a coach voice (Hype / Tough
// Love / Chill / Data, spec §5.13) — that styling is `Core/Sources/Core/Copy`'s job once it
// exists, and this task must not invent that module's API. Restyling this dialog through
// `Copy` once it's built is a genuine follow-up integration point, not guessed here.

import AppIntents
import Foundation
import SwiftData

public struct CheckStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Status"

    public static var description: IntentDescription {
        IntentDescription(
            "Reports your streak, today's goals, and banked minutes.",
            categoryName: "Status"
        )
    }

    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)

        let streak = await StreakEngine.shared.currentStreak()
        let bankedMinutes = await TimeBankEngine.shared.remainingMinutes(for: .now)

        let activeGoalIDs = try IntentSupport.activeGoalIDs(for: user.id, in: context)
        let goalsDoneToday = try goalsCompletedToday(goalIDs: activeGoalIDs, in: context)
        let totalGoals = activeGoalIDs.count

        var parts: [String] = []

        if streak > 0 {
            parts.append("\(streak)-day streak")
        } else {
            parts.append("No streak yet — today's a good day to start one")
        }

        if totalGoals > 0 {
            parts.append("\(goalsDoneToday) of \(totalGoals) goals done today")
        }

        if SharedDefaults.activeLockSessionID != nil {
            let remaining = SharedDefaults.goalsRemainingForActiveLock
            parts.append(remaining > 0 ? "\(remaining) left to unlock" : "everything's unlocked")
        }

        if bankedMinutes > 0 {
            parts.append("\(bankedMinutes) minutes banked")
        }

        // Instrumentation (spec §23: "Instrument from day one: ... every intent"). No
        // `@Parameter`s on this intent, so no key-parameter properties to attach.
        Analytics.shared.capture(event: "intent_check_status")

        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: ". ") + "."))
    }

    private func goalsCompletedToday(goalIDs: [UUID], in context: ModelContext) throws -> Int {
        guard !goalIDs.isEmpty else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        // Filtered by date/verified in the predicate, then narrowed to `goalIDs` in plain Swift —
        // keeping the `#Predicate` itself to simple stored-property comparisons rather than a
        // captured-array `.contains` over an optional relationship, which this offline session
        // can't check translates cleanly (see this task's `knownIssues`).
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate { event in event.verified && event.ts >= startOfDay }
        )
        let events = try context.fetch(descriptor)
        let goalIDSet = Set(goalIDs)
        let distinctGoalIDs = Set(events.compactMap { $0.goal?.id }).intersection(goalIDSet)
        return distinctGoalIDs.count
    }
}
