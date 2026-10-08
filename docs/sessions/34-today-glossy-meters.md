# Session 34 — Today: glossy style and goal-shaped meters

- **Branch:** `claude/focused-keller-41j9sk` (stacked on session 33)
- **Spec sections:** §15 (design system, Today), §5.17 (buddy faces kept on tiles)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

After the Fuel pass (session 33) the founder chose: keep that style app-wide, **glossy** (not flat or
pixel-art), **start with Today**, and **a meter that looks like the goal for every goal**. Approved
plan: shared badge + meters in Core, Today tiles/hero/XP bar, a review screen for all meters. Lock's
"Required to unlock" tiles share Today's `GoalTile`, so they change too (approved). Visual only: no
data, intent or copy changes.

## Log

### 2026-10-08 — Shared badge, 13 goal meters, Today

- **Files touched:**
  - new: `Core/Sources/Core/UI/Components/ZanoPopBadge.swift`,
    `Core/Sources/Core/UI/Components/GoalMeters/{ZanoGoalMeter,FoodMeters,BodyMeters,TimeMeters}.swift`
  - modified: `App/ZANO/Features/Today/{GoalActionList,LockVaultCard,TodayView}.swift`,
    `App/ZANO/Features/Buddy/BuddyToast.swift`, `App/ZANO/Features/Fuel/{FuelView,Components/FuelMeterCards,Components/FuelGameMeters}.swift`,
    `App/ZANO/ScreenshotGallery.swift`, `docs/design/visual-direction-v2.md`
- **What changed:**
  - `ZanoPopBadge` (from Fuel's badge) and `ZanoProteinBar` (from Fuel's protein bar) now live in Core;
    Fuel uses them unchanged.
  - `ZanoGoalMeter(goal:progress:)`: workout barbell (plate pairs load from the middle out), steps
    footprints, stretch resistance band, cold/sauna thermometer, protein bar, water glasses, creatine
    scoops, meal-prep containers, focus battery, sunrise sun-over-horizon, sleep moon phases, reading
    book spines, custom stars. Springs to new levels, pops once at 100%, glows when full; Reduce
    Motion off.
  - Today goal tiles: the meter under the numbers; glossy badge for goals without a buddy face;
    glossy action capsules (lit top, white rim, soft glow).
  - Today hero: the thin segment bar under "goals to unlock" is now one small glossy tile per goal,
    filling from the bottom (glyph stays whole: colour over empty, white over fill), full badge
    with sparkle when done. Glossy level chip and XP bar under the buddy.
  - `goal-meters` gallery screen: every meter at 0 / 45% / 100%.
  - Design doc §12 "Pass 4: glossy" records the direction and where to stay calm.
- **Decisions made and why:** the 72% / screen-time chips were left as they are: they already have
  gloss (`ZanoSticker`) and are drawn by the Screen Time report extension on device too. Buddy faces
  stay on tiles (they are the app's character). First CI pass showed a crowded barbell, unreadable
  footprints, odd scoops and a half-hidden fork glyph in the hero tile; all reworked in a second
  commit.
- **Known issues / TODOs left behind:** Lock's hero, Progress and Settings still in the older look
  (next sessions).
- **Needs verification on:** CI screenshots of the second pass; motion feel on a device.
