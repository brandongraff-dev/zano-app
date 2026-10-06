# Session 25 — Focus break coach

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.29, §5.28 (templates), §24
- **Status:** Scaffolded — Unverified (not yet compiled in CI)
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06

- **Files touched:** new `Core/Sources/Core/Focus/BreakCoach.swift`, `Copy/BreakCoachCopy.swift`, `Core/Tests/CoreTests/BreakCoachTests.swift`, `App/ZANO/Features/Today/BreakCoachCard.swift`; edited `TodayView.swift`, `docs/spec.md`.
- **What changed:** a pure `BreakCoach.suggestion` turns today's verified focus blocks into a break length and one activity; a Today card shows it for 15 minutes after a block ends and while no block is running.
- **Decisions:** reads the existing outcome events (focus goal, timer source, verified, not a miss) instead of adding storage; "Done" is remembered per block in `@AppStorage`; no notification or break timer (the nudge only suggests).
- **Known issues / not done:** no push at the end of a break; blocks started outside the app still count because they log the same event.
- **Needs verification on:** CI compile and `BreakCoachTests`; Simulator look.
