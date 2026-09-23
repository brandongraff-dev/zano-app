// Core/Sources/Core/Intents/QuickRepeatMealIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | QuickRepeatMealIntent | mealId | Logs remembered meal |
// docs/spec.md §5.19 Quick Repeats & Food Memory: "Meal photos build a personal library. 'Your
// usual chicken bowl (48g)?' appears as a one-tap suggestion." §3 (Goal Catalog: Protein, Tier B —
// "quick-repeat of recent meals" is one of its verification methods).
//
// A quick repeat creates a *new* `Meal` row for today (copying the referenced meal's `items`/
// `proteinG`, pre-confirmed since it's a repeat of something the user already reviewed once — spec
// §5.19's whole point is skipping the re-review step) and writes a matching `GoalEvent` against
// the Protein goal, exactly like `LogProteinIntent` does for a manual log — this is a Protein log,
// just pre-filled from memory instead of typed/tapped fresh.

import AppIntents
import Foundation
import SwiftData

public struct QuickRepeatMealIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Usual Meal"

    public static var description: IntentDescription {
        IntentDescription(
            "Logs a remembered meal again, without re-entering it.",
            categoryName: "Log"
        )
    }

    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Meal", description: "Which remembered meal to log again.")
    public var meal: MealEntity

    public init() {}

    public init(meal: MealEntity) {
        self.meal = meal
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal) again")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)
        let userID = user.id
        let mealID = meal.id

        var descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.id == mealID && $0.userID == userID }
        )
        descriptor.fetchLimit = 1
        guard let remembered = try context.fetch(descriptor).first else {
            throw ZanoIntentError.mealNotFound
        }

        let repeatedMeal = Meal(
            userID: user.id,
            ts: .now,
            photoPath: remembered.photoPath,
            items: remembered.items,
            proteinG: remembered.proteinG,
            confirmed: true
        )
        context.insert(repeatedMeal)

        if let proteinGrams = remembered.proteinG,
           let proteinGoal = try IntentSupport.activeGoal(ofType: .protein, for: user.id, in: context) {
            let event = GoalEvent(
                kind: .verify,
                value: proteinGrams,
                source: .manual,
                verified: true,
                meta: .object(["quickRepeatMealID": .string(remembered.id.uuidString)]),
                user: user,
                goal: proteinGoal
            )
            context.insert(event)
        }

        try context.save()

        // Instrumentation (spec §23: "Instrument from day one: ... every intent").
        Analytics.shared.capture(
            event: "intent_quick_repeat_meal",
            properties: ["meal_id": mealID.uuidString]
        )

        let label = remembered.items.first?.name ?? "Meal"
        return .result(dialog: "Logged \(label) again.")
    }
}
