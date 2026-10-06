# Session 24 — Buddy faces on Today goals, focus-lock question on Today

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.17 (buddy), §5.24 (focus lock)
- **Status:** Scaffolded — Unverified (not yet compiled in CI)
- **Started / Last updated:** 2026-10-06

## Log

### 2026-10-06

- **Files touched:** `App/ZANO/Features/Today/GoalActionList.swift` (new `goalType` on `GoalActionItem`; the tile's sticker becomes the buddy's face for goals that have one), `Today/TodayView.swift` (passes `goalType`, shows `FocusLockAskCard`), new `App/ZANO/Features/FocusLock/FocusLockAskCard.swift`, `docs/sessions/17-focus-lock.md`.
- **What changed:** the emotions from session 15 are now on screen. A workout tile shows the buddy lifting while it is running and flexing when done; water shows thirsty, sipping, then proud; protein and meal prep show hungry, eating, proud; focus and reading show focused; sunrise alarm and stretching show yawning. Goals without a face keep their icon sticker. A focus-lock question about an upcoming meeting now appears on Today with Yes / No.
- **Decisions:** moment is derived from what the tile already knows (done, live status, any progress, otherwise needed). No new state.
- **Known issues / not done:** the Fuel and Focus screens themselves still use their own art; no notification for focus-lock questions.
- **Needs verification on:** CI compile; Simulator look of the tiles (48 pt face where the sticker was).
