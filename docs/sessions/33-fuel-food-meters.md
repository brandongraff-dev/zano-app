# Session 33 — Fuel: protein bar meter, pop badges, water bottle

- **Branch:** `claude/focused-keller-41j9sk`
- **Spec sections:** §15 (design system / Fuel screen), §5.19–§5.20 (rows restyled only, no behaviour change)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

The founder asked (with a screenshot of the protein card) for the progress bar to look like food
instead of a plain bar, for the header icon to pop, and for the same kind of treatment on the rest
of the Fuel page. Visual only: no data, intent or copy changes.

## Log

### 2026-10-08 — Protein bar, pop badges, water bottle

- **Files touched:** `App/ZANO/Features/Fuel/Components/FuelGameMeters.swift`,
  `App/ZANO/Features/Fuel/Components/FuelMeterCards.swift`, `App/ZANO/Features/Fuel/FuelView.swift`,
  `App/ZANO/ScreenshotGallery.swift`
- **What changed:**
  - `FuelSegmentMeter` replaced by `FuelProteinBar`: a candy wrapper in the protein hue (crimped
    ends, ten dashed ghost squares) that fills with moulded chocolate chunks. The leading edge has a
    bite taken out of it (`FuelBiteMask`, animatable), and three crumbs fly off the bite on each log.
    At 100% the bite goes away and the bar glows.
  - `FuelPopBadge`: a glossy, tilted tile in the goal colour with a white glyph, white sticker rim,
    coloured glow and a sparkle. Used in both meter headers (bounces on a log, charge burst on
    completion) and, smaller and without the sparkle, on the Quick Repeat banner, Top-ups rows,
    staple rows and the empty-staples row. Card titles are now heavy rounded type.
  - Water tank: a bottle cap on top and three bubbles that ride with the level.
  - Screenshot gallery: a `fuel-bottom` screen (Fuel scrolled to the end) and a `light-` prefix on
    any `-ZANOScreen` name to render light mode, so focused CI runs can shoot light screens.
- **Decisions made and why:** chocolate colours are fixed food browns (not theme tokens) so the bar
  reads as chocolate in both schemes; the wrapper carries the protein hue. This reverses part of the
  "Pass 3 (restraint)" flat look for this screen only, at the founder's request. All motion is still
  a reply to a log and is off under Reduce Motion.
- **Known issues / TODOs left behind:** none known.
- **CI:** focused run 149 green (compile); `tab-fuel`, `fuel-bottom` and their `light-` versions read.
- **Needs verification on:** crumbs/bounce motion feel on a device.

### 2026-10-09 — Still current

Sessions 34–35 extended this style to Today and Lock and were reverted at the founder's request;
Fuel keeps the protein bar, pop badges and water bottle from this session, unchanged.
