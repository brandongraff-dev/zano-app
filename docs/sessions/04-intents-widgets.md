# Session 4 — App Intents catalog + widgets + Controls + Siri + NFC

- **Branch:** `main`
- **Spec sections:** §6 (widgets/Controls/Live Activities/NFC/Siri), §14 (App Intents catalog)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Intents & Widgets" cluster (3 build agents + 1 harden agent).

## Scope

The full §14 App Intents catalog, real interactive widgets (replacing the Session-0 placeholder),
iOS 18 Controls, all 3 Live Activity configurations, NFC tag reading/mapping, and Siri phrases.

## Files

- `Core/Sources/Core/Intents/*.swift` (13 intents + `IntentSupport.swift` + `ZanoShortcuts.swift`)
- `Extensions/ZANOWidgets/` — `ZANOWidgetsBundle.swift` (rewritten), `HomeWidget/`,
  `LockScreenWidget/`, `Controls/`, `LiveActivities/`, `Support/`
- `Core/Sources/Core/Verification/NFCReader.swift`, `NFCTagMapper.swift`,
  `NFCTagSetupInstructions.swift`

## Decisions

- Controls (iOS 18) are mixed directly into the same `WidgetBundle`'s `body`, gated
  `#available(iOSApplicationExtension 18.0, *)`, per Apple's documented pattern — no separate
  target/Info.plist entry. Flagged as the one mechanism in this cluster most worth a double-check
  on a real compiler.
- NFC tag → action dispatch reuses the exact App Intent types from this same cluster
  (`LogWaterIntent`, `LogProteinIntent`, `LogCreatineIntent`, `StartLockIntent`, `SunriseKeyIntent`)
  rather than a parallel dispatch mechanism.

## Known issues

- `AppShortcutsProvider` phrase wording follows §6 exactly ("Lock in with ZANO", "Log a shake",
  "Log water", "How am I doing today") — Siri's actual phrase-matching behavior can't be tested
  without a device.
- Widget timeline data reads the App Group only, per §11/§27 — no networking. Confirm on-device
  that timeline reloads actually fire after each intent call (§27: "interactive widgets can only
  run App Intents; no navigation, and updates need a timeline reload after the intent").

## Needs verification on

Real device: widget interactivity (buttons actually invoking intents without opening the app),
Control Center controls appearing and working, all 3 Live Activities rendering on Lock
Screen/Dynamic Island, NFC read of an actual `zano://tag/<uuid>` NDEF tag, Siri phrase recognition.
