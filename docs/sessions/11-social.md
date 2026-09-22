# Session 11 — Squads, duels, nudges, referral, share cards, Locked-Out moment

- **Branch:** `main`
- **Spec sections:** §5.7 (squads & duels), §5.8 (gym home turf — see note), §5.16 (Locked-Out
  moment), §9.3 (nudge optimizer, client-side cap)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Social" cluster (3 build agents + 1 harden agent) — the last of the 8
  clusters to finish, since its files were still landing when this was first checked mid-run.

## Files

- `Core/Sources/Core/Social/SquadManager.swift`, `DuelManager.swift`, `NudgeSender.swift`,
  `ReferralManager.swift`
- `App/ZANO/Features/Share/LockedOutMomentView.swift`, `WeeklyRecapShareView.swift`

## Decisions

- `NudgeSender` enforces the 2/day cap (§8 rule 7) client-side before any backend call, and
  records `delivered`/`acted_within_3h` for the future nudge-optimizer bandit (§9.3, Session 12+).
- `ReferralManager` grants a streak freeze to both sides on a successful referral, per §4 v2.
- `LockedOutMomentView` implements its own 3-attempts-in-an-hour counter (§5.16) rather than
  depending on the Screen Time Report extension, consistent with §27 ("Time Reclaimed is computed
  from lock durations instead" — same reasoning applies to counting shield impressions).
- `GymLeaderboard.swift` (§5.8) was **not** built in this cluster — it landed in the follow-up
  batch instead, once this cluster's other Social files existed to avoid a same-directory
  collision. See `13-v3-slices.md`.

## Known issues

- `SquadManager`'s "one member's freeze protects everyone once/week" rule and `DuelManager`'s
  point-tally-per-verified-goal both depend on `StreakEngine`/`GoalEvent` call sites this cluster
  didn't directly wire — confirm the integration once compiled.
- Both share views depend on `Core/Sources/Core/UI/Components/ShareCard.swift` (Design System
  cluster, built concurrently) — same reconciliation note as other UI-referencing sessions.

## Needs verification on

Two real accounts/devices: squad creation/join via invite code, nudge send/receive, duel point
tally over a real 7-day window, both share cards actually rendering a 9:16 image.
