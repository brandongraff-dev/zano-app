// Core/Sources/Core/Intents/OpenTodayIntent.swift
//
// docs/spec.md §14 App Intents Catalog:
//   | OpenTodayIntent | — | Deep link |
// docs/spec.md §15 (Screens: "Today, Lock, Fuel, Progress, Squad, Settings...") — the Today screen
// is the app's home tab.
//
// Scope note: this intent guarantees the app foregrounds (`openAppWhenRun = true`); landing on
// the Today tab specifically (as opposed to whatever tab was last visible) is App-side navigation
// state owned by `App/ZANO`, not this task's scope. `App/ZANO`'s root view is the right place to
// read "was the app just opened via `OpenTodayIntent`" (e.g. via `NSUserActivity`/scene state) and
// select the Today tab — a genuine cross-module integration point, not guessed here.

import AppIntents

public struct OpenTodayIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Today"

    public static var description: IntentDescription {
        IntentDescription(
            "Opens ZANO to your Today screen.",
            categoryName: "Navigation"
        )
    }

    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}
