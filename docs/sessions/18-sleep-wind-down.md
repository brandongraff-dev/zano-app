# Session 18 — Sleep wind-down and sleep insights

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.25, §5.10, §24
- **Status:** Scaffolded — Unverified
- **Started / Last updated:** 2026-10-05

## Log

### 2026-10-05

- **Files touched:** new `Core/Sources/Core/Sleep/*` (models, insights engine, store, HealthKit reader, manager), `Copy/SleepCopy.swift`, `App/ZANO/Features/Sleep/{SleepCheckInCard,SleepInsightsView}.swift`, `SleepTests.swift`; edited `BedtimeGateManager`, `TodayView`, `SettingsView`, `project.yml` (Health usage text)
- **What changed:** A morning check-in and a calm on-device insights engine (10 rated nights, 4 per side, 0.5 delta; suggests a bedtime at most 30 minutes earlier; goes quiet during a rough stretch). No server ML.
- **Known issues / not done:** Insights need ~10 rated nights before they speak. Sleep reads from HealthKit only.
- **Needs verification on:** CI compile and tests; HealthKit sleep read on a device

## Blockers

- No Mac or device here; CI is the compiler.
