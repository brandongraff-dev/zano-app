# Session 13 — v3 slices + the §5 creative features that didn't fit an earlier session

- **Branch:** `main`
- **Spec sections:** §5.4 (Ghost Mode), §5.8 (gym leaderboard), §5.9 (seasons/ranks), §5.10
  (Bedtime Gate & Sunrise Alarm), §5.12 (Auto-Focus), §5.17 (Trophy Case & cosmetics), §5.18
  (Travel Mode), §5.21 (Apple Watch)
- **Status:** Scaffolded — Unverified. The background follow-up batch (11 build agents + 2 harden
  agents) has landed and its harden-pass fixes are committed (2026-09-22, commit `27edf3e`).

## Why this batch exists

After the core 8 clusters (Sessions 2–6, 9–11) finished, a gap-check against the full spec found
these named, spec'd features had no build agent assigned anywhere — not oversights so much as
genuinely separate slices, several explicitly v3 (§5.8, §5.9, §5.21 are all listed under the v3
roadmap in §4), but §5.10 (Bedtime Gate & Sunrise Alarm) is explicitly a **headline v2 feature**
("the most demoed mechanic in the whole app") that had been missed and needed to be caught up, not
deferred.

## Scope, by file (confirmed present on disk as of 2026-09-22, mid-batch)

- **Bedtime Gate & Sunrise Alarm (§5.10):** `Core/Sources/Core/Verification/SunriseAlarmManager.swift`,
  `BedtimeGateManager.swift`, `Core/Sources/Core/LiveActivity/BedtimeWindDownActivityAttributes.swift`,
  `Core/Sources/Core/Copy/SunriseAlarmCopy.swift`, `App/ZANO/Features/SunriseAlarm/*.swift`
  (setup + alarm-ringing UI). AlarmKit (iOS 26+) as primary path, chained local notifications as
  the 17–18 fallback, per §5.10's own guidance. All 4 dismiss variants (Tag/Steps/Focus/Squad), 1
  max snooze, and the 60-second escape hatch are in scope — "never trap the user" was called out as
  a hard requirement for this batch specifically.
- **Ghost Mode (§5.4):** `Core/Sources/Core/Retention/GhostMode.swift`,
  `Core/Sources/Core/UI/Components/GhostProgressBanner.swift`
- **Trophy Case & Cosmetics (§5.17):** `App/ZANO/Features/Trophy/TrophyCaseView.swift`,
  `CosmeticsShopView.swift`, `Core/Sources/Core/Retention/CosmeticsStore.swift`
- **Travel Mode (§5.18):** `Core/Sources/Core/Retention/TravelMode.swift`
- **Auto-Focus Integration (§5.12):** `Core/Sources/Core/LockEngine/AutoFocusIntegration.swift`,
  `Core/Sources/Core/Copy/AutoFocusSetupInstructions.swift`
- **Gym leaderboard (§5.8):** `Core/Sources/Core/Social/GymLeaderboard.swift`
- **Seasons/ranks (§5.9):** `Core/Sources/Core/Retention/SeasonsAndRanks.swift`
- **Watch app skeleton (§5.21):** a new `ZANOWatch` target appended to `project.yml` (additive
  only — verified by a dedicated harden agent that no existing target block was disturbed) +
  `Watch/ZANOWatch/*.swift`. Deliberately minimal, matching the Session-0 extension-placeholder
  spirit — this is the most speculative slice in the repo.
- **Real ML pipeline groundwork** — see `12-ml-service.md`, same batch.

## Known issues

- **Found and fixed post-hoc:** the Sunrise Alarm UI files (`AlarmRingingView`,
  `SunriseAlarmSetupView`, `BedtimeGateSetupView`) called a `Copy.alarmRinging`/`.sunriseAlarm`/
  `.bedtimeGate` umbrella namespace that didn't exist — the manager-side agent had been instructed
  to build a flat `SunriseAlarmCopy` enum instead, without visibility into the umbrella convention
  established elsewhere in the same wave. Resolved: `Core/Sources/Core/Copy/SunriseAlarmScreenCopy.swift`
  now provides the ~70 keys the UI actually calls, cross-checked against each file's own
  documented key list, delegating to `SunriseAlarmCopy` for safety-critical wording rather than
  duplicating it. This is the kind of seam the harden pass is meant to catch — worth treating as a
  reminder to spot-check cross-agent naming conventions specifically, not just per-file correctness.
- `project.yml`'s `ZANOWatch` target is explicitly flagged by its own author as not yet wired as
  ZANO's companion app (`embed`-ing a watch target is a different mechanism than the app-extension
  `embed: true` pattern used elsewhere in this file) — read the inline comment block in
  `project.yml` directly above the `ZANOWatch` target for the specific gaps left for a deliberate
  follow-up, not fixed in this pass because they'd touch a target this run wasn't scoped to.
- Sunrise Alarm's AlarmKit usage is the newest, least-training-certain API surface in the whole
  build — treat it as the single highest-priority thing to check first on a real Mac with iOS 26.
- Several of these views (`GhostProgressBanner`, Trophy Case) were built as self-contained
  components with integration into `TodayView`/`SettingsView` deliberately left as a follow-up
  rather than edited directly, to avoid colliding with those files while other agents might still
  have been settling them. **That integration wiring is real, undone work — track it.**

## Needs verification on

Everything here needs a Mac at minimum; Sunrise Alarm and Watch additionally need a real device
(and, for Watch, a paired Apple Watch) and are the least mature parts of the entire build.
