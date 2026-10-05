# Session 20 — Workout auto-unlock and Year in Review

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.1, §5.21, §24
- **Status:** Scaffolded — Unverified
- **Started / Last updated:** 2026-10-05

## Log

### 2026-10-05

- **Files touched:** new `Verification/HealthWorkoutObserver.swift`, `App/ZANO/Features/Share/YearInReviewView.swift`; edited `Milestones.swift`, `MilestoneCopy.swift`, `MilestoneCardView.swift`, `MilestonePresenter.swift`, `MilestoneTests.swift`
- **What changed:** An HKObserverQuery with background delivery runs the Health goal checks when a workout lands (so a workout from Strava or any Health-writing app unlocks apps). Year in Review appears Dec 1 to Jan 7 for people with 14+ earned days. Monthly recap already existed.
- **Known issues / not done:** Strava direct link is not built (needs API keys and backend OAuth); works only via Apple Health.
- **Needs verification on:** Device for background delivery; CI for compile and tests

## Blockers

- No Mac or device here; CI is the compiler.
