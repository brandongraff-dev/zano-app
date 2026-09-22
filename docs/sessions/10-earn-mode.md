# Session 10 — Earn Mode (Time Bank)

- **Branch:** `main`
- **Spec sections:** §5.2 (Earn Rate / Time Bank), §5.11 (Dynamic Island earn meter)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Earn Mode" cluster (2 build agents + 1 harden agent).

## Scope

Time Bank deposit/spend/expiry engine, partial unlock tiers, and the earn-meter Live Activity.

## Files

- `Core/Sources/Core/LockEngine/TimeBankEngine.swift`, `PartialUnlockTiers.swift`
- `Core/Sources/Core/LiveActivity/EarnMeterActivityAttributes.swift`,
  `EarnMeterActivityManager.swift`

## Decisions

- Deposit values taken verbatim from §5.2: gym session = 90 min, focus block = 30 min, protein =
  30 min. Unused minutes expire at midnight — no hoarding, enforced by keying `time_bank` rows per
  calendar date rather than a rolling balance.
- `PartialUnlockTiers` computes which apps unlock from a `LockSet` + completed-goal-ID set,
  matching §2's example ("2 of 3 goals unlocks messaging, all 3 unlocks TikTok") as a general rule
  rather than a hardcoded case.

## Known issues

- `EarnMeterActivityManager` starts/updates/ends the Live Activity from `TimeBankEngine` state
  changes — confirm on a Mac that ActivityKit's update cadence (and its 8-hour Live Activity limit,
  §27) is respected for a full day's earn cycle, not just a single deposit.

## Needs verification on

Real device: Time Bank math across a full day (multiple deposits/spends), midnight expiry actually
firing, the Dynamic Island earn meter rendering and updating live.
