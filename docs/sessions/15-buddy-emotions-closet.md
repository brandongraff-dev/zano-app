# Session 15 — Buddy emotions + Buddy Closet

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.17 (Trophy Case & Cosmetics, new Buddy Closet and Buddy emotions paragraphs), §15 (design system), §24 (no restrictive goals)
- **Status:** Compiles + Core unit tests pass in CI (run 105, 2026-10-06). Device and Simulator behaviour still unverified (see "Needs verification on")
- **Started:** 2026-10-05
- **Last updated:** 2026-10-05

## Scope

Requested by the founder (2026-10-05): more emotions for the nine buddies (working out, drinking water, eating, and anything else that fits), and lots of shop items and customization for every buddy. This is the first slice of a larger list (monthly and year recaps, "Earned It" video, study/work goals, Health and Strava import, parent and teen mode), built characters-first as agreed.

## Log

### 2026-10-05 — Integration: bring the buddies into this branch

- **What changed:** merged `claude/sharp-euler-npwt08` (the app's buddy work: sprites, picker, gear, levels, Scroll Monster, watch app; 140 commits ahead of `main`) and `claude/gracious-johnson-tl2jf4` (landing page and newer buddy art) into this branch, then regenerated the sprites with `scripts/buddies/export_swift.py --sprites-only`. Neither source branch was changed.
- **Decisions:** conflicts in 4 views took the redesigned (sharp-euler) versions; main's rewritten hard-paywall UI tests were kept and the stale `Flow1PaywallFreePathUITests` removed; `docs/spec.md` palette took the newer 2026-09-24 colours and kept main's "locked is muted, not red" decision.
- **Known issues:** the UI tests (Flow2/3, ScenarioSupport) came from main and were written against the old onboarding; with the buddy step added they may need adjusting. CI will say.

### 2026-10-05 — Ten activity emotions for all nine buddies

- **Files touched:** `scripts/buddies/face.py`, `scripts/buddies/export_swift.py`, `scripts/buddies/preview.py` (new), `Core/Sources/Core/UI/Buddy/Buddy.swift`, `BuddySprites.swift` and `Watch/ZANOWatch/Generated/WatchBuddySprites.swift` (generated), `Core/Tests/CoreTests/BuddyTests.swift`
- **What changed:** new `BuddyPose` cases lifting, flexing, sipping, thirsty, eating, hungry, focused, yawning, proud, lovey (90 new sprites). `BuddyPose(goal:moment:)` maps a goal and a moment (needed / doing / done) to the right face. Props (barbell, bottle, drumstick, egg, target, star, zzz) are placed in free space by `face.place`, so one definition fits all nine shapes.
- **Decisions:** all positive; hunger and thirst never read as guilt; no face for restrictive goals. `lovey` exists but no screen uses it yet (squad nudges, spec §5.7).
- **Not wired yet:** the faces are available and mapped but no screen switches to them on a log event yet (Today, Fuel and the focus timer should call `BuddyPose(goal:moment:)`).
- **Needs verification on:** CI (compile + `BuddyTests`); a device for how the 48px props read at 32pt.

### 2026-10-05 — Buddy Closet

- **Files touched:** `scripts/buddies/style.py` (new), `preview_style.py` (new), `export_swift.py`; `Core/.../UI/Buddy/BuddyStyle.swift`, `BuddyStyleSprites.swift` (generated), `Buddy.swift`; `Core/.../Copy/BuddyStyleCopy.swift`, `TrophyCosmeticsCopy.swift`; `Core/.../Retention/CosmeticsStore.swift`; `App/ZANO/Features/Buddy/BuddyClosetView.swift` (new), `BuddyPickerView.swift`; `App/ZANO/Features/Trophy/CosmeticsShopView.swift`; `App/ZANO/ScreenshotGallery.swift`; `.github/workflows/ci.yml`; `Core/Tests/CoreTests/BuddyStyleTests.swift`
- **What changed:** 108 new cosmetics: 72 skins (8 colourways per buddy, applied as a four-colour table at draw time, so no extra sprites), 10 hats, 4 eyewear, 6 neckwear, 6 back items and 10 backdrops (258 generated sprites). Sold through the existing `CosmeticsStore` as a fifth category `.buddyStyle`; the closet screen (Settings > Buddy > Open the closet) previews, buys, wears and takes off. What a buddy wears is saved per buddy (`BuddyOutfit`) and `BuddySprite` draws it everywhere. The watch keeps its own, smaller sprite set (no closet items).
- **Decisions:** hats/eyewear/neckwear/back/backdrops are bought once and worn by any buddy; skins are per buddy. A bought item takes its slot from earned gear (`BuddyGear.slot`). Backdrops only show on big sprites (`showsBackdrop`). Prices are placeholders (skins 300-450, wearables 120-450, backdrops 250-300).
- **Known issues:**
  - Coin income is low for a catalog this size (boss drop 75, bonus drops 25-75). Either prices come down or a coin source is added; that is an economy decision for the founder.
  - Widgets, the shield and notification images draw the buddy through `Buddy.image(pose:gear:)` and do not wear the outfit yet.
  - `CosmeticsShopView` hides the new category chip; the closet is the only way to browse it.
  - Back items clip at the screen edge on the widest buddies (Zib, Moko).
- **Needs verification on:** CI (compile, `BuddyStyleTests`, the `buddy-closet` screenshot); a device for feel.

## Blockers

- No Mac or Simulator here: everything above compiles and runs only in CI.
