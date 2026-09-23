// Core/Sources/Core/Intents/ZanoShortcuts.swift
//
// docs/spec.md §6 (Widgets, Controls, Live Activities, NFC, Siri):
//   "App Shortcuts with phrases: 'Lock in with ZANO', 'Log a shake', 'Log water',
//    'How am I doing today'. Expose parameters (grams, ml, minutes)."
//
// Every phrase below embeds `\(.applicationName)` — Apple requires this token somewhere in every
// `AppShortcut` phrase so Siri can disambiguate which app's shortcut it's invoking; it renders as
// "ZANO" (the app's display name) at runtime, not literal text this file has to hardcode. Each
// intent instance below is constructed with `source`/mode defaults appropriate to a *spoken*
// invocation (e.g. `source: .siri`) rather than the in-app/widget default — see each intent's own
// `@Parameter(default:)` for what a programmatic (widget/NFC) caller gets instead.
//
// Apple's documented limit is 10 `AppShortcut`s per provider; this file declares 4, matching
// spec §6's phrase list exactly. `EmergencyUnlockIntent` and `EndFocusIntent` are intentionally
// absent — see their own file headers for why.

import AppIntents

public struct ZanoShortcuts: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor { .lime }

    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartLockIntent(),
            phrases: [
                "Lock in with \(.applicationName)",
                "Start my lock in \(.applicationName)",
            ],
            shortTitle: "Lock In",
            systemImageName: "lock.fill"
        )

        AppShortcut(
            intent: LogProteinIntent(source: .siri),
            phrases: [
                "Log a shake with \(.applicationName)",
                "Log a shake in \(.applicationName)",
            ],
            shortTitle: "Log a Shake",
            systemImageName: "cup.and.saucer.fill"
        )

        AppShortcut(
            intent: LogWaterIntent(source: .siri),
            phrases: [
                "Log water with \(.applicationName)",
                "Log water in \(.applicationName)",
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )

        AppShortcut(
            intent: CheckStatusIntent(),
            phrases: [
                "How am I doing today in \(.applicationName)",
                "Check my status in \(.applicationName)",
            ],
            shortTitle: "Check Status",
            systemImageName: "chart.bar.fill"
        )
    }
}
