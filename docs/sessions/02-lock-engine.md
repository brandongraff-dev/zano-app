# Session 2 — Lock Engine

- **Branch:** `main`
- **Spec sections:** §2 (core loop), §5.1 (Living Shield), §6, §11, §24, §27
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Lock Engine" cluster (3 build agents + 1 harden agent), first of 8
  feature clusters piped after the Foundation phase completed.

## Scope

FamilyActivityPicker-based lock-set management, ManagedSettings shield apply/remove, DeviceActivity
schedules, real Living Shield content in both shield extensions, and emergency unlock.

## Files

- `Core/Sources/Core/LockEngine/LockEngineManager.swift`, `LockSetManager.swift`,
  `EmergencyUnlock.swift`
- `Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift`,
  `Extensions/ZANOShieldAction/ShieldActionExtension.swift` — replaced the Session-0 placeholders
- `Core/Sources/Core/Copy/CoachVoice.swift`, `ShieldCopy.swift` — coach-voice copy tables (4 voices
  × state: mid-lock / near-completion / after-a-miss), created here since no other cluster owned
  Copy yet
- `App/ZANO/Features/LockSetup/LockSetupView.swift`, `AppPickerView.swift`

## Decisions

- Shield extensions read `SharedDefaults` only (streak, goals remaining, coach voice, earned-
  minutes mirror) — never open `ModelContainer` directly, staying inside a shield extension's tight
  memory/time budget per §11/§27.
- `ShieldActionExtension`'s primary ("Show my goals") and secondary ("Emergency") buttons both post
  a local notification with a `deepLink` in `userInfo`, since shields can't open the app directly
  (§27's documented workaround). The actual emergency-unlock grant happens nowhere in the
  extension — only `LockEngineManager.emergencyUnlock(sessionID:)` inside the app can end a lock,
  keeping "never trap the user" enforceable in exactly one place.
- Shield's one call-to-action color reuses the §15 accent token (`#B8FF3C`) rather than a second ad
  hoc color.

## Known issues

- `recentMiss` in `ShieldCopy.ShieldContext` is left at its default (`false`) — the
  `SharedDefaults` mirror of `Streak.neverMissTwiceArmed` that would drive the real after-a-miss
  shield copy doesn't exist yet (Retention cluster owns `StreakEngine`; wiring that mirror is a
  small follow-up, not done in this cluster).
- The Controls-mixed-into-`WidgetBundle` mechanism referenced by later widget work, and the
  `ManagedSettingsUI` extension-point identifiers in `project.yml`, remain flagged unverified from
  Session 0 — nothing here changes that.

## Needs verification on

Real device (FamilyControls/ManagedSettings/DeviceActivity do not work in Simulator, §27): picking
apps, applying a shield, confirming the custom shield content renders, confirming the notification-
deep-link path actually opens the app to the right screen.
