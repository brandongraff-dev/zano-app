# Session 9 — Streak logic + adaptive engine v1

- **Branch:** `main`
- **Spec sections:** §5.5 (Plan B), §5.6 (Never Miss Twice), §8 (retention psychology rules),
  §9.1 (adaptive engine v1 rules)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Retention" cluster (2 build agents + 1 harden agent). Extended by the
  follow-up batch with Ghost Mode, Trophy Case/Cosmetics, Travel Mode, and Seasons/Ranks — see
  `13-v3-slices.md`.

## Scope

Streak engine (freezes, Never Miss Twice, comeback handling) and the rules-based adaptive
difficulty engine + Plan B day logic.

## Files

- `Core/Sources/Core/Retention/StreakEngine.swift`, `ComebackMode.swift`
- `Core/Sources/Core/Retention/AdaptiveGoalEngine.swift`, `PlanB.swift`

## Decisions

- `AdaptiveGoalEngine` implements §9.1's v1 rules exactly: 7-day completion rate <60% → lower one
  difficulty step; >90% for 10 days → raise one step; never more than one step change per week.
  No bandit/ML — that's explicitly v2 (§9.1 itself defers it).
- `PlanB` takes a plain `isHighRisk: Bool` rather than calling the ML risk service directly — the
  real slip-prediction signal is Session 12 scope and doesn't exist yet; keeping the interface
  boundary explicit here means Session 12 landing later doesn't require touching this file.
- Streak freezes: 1/week free, 3/week paid, per §4/§21.

## Known issues

- `StreakEngine`'s `recordMiss`/`recordEarnedUnlock` need to be called from the actual unlock-
  eligibility path (Lock Engine cluster) and the emergency-unlock penalty option — confirm those
  call sites exist and pass the right dates once compiled.
- No unit tests were written for the difficulty-step math (§9.1's exact thresholds are simple
  enough to hand-verify by reading the code, but a real test would catch an off-by-one before it
  ships).

## Needs verification on

Mac: a real `swift test` exercising 28+ days of synthetic `GoalEvent` history through
`AdaptiveGoalEngine`/`StreakEngine` to confirm the step-change rules actually fire at the right
thresholds — worth writing as an early CoreTests addition.
