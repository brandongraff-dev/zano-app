# Session 36 — Buddy moods on Fuel and Focus; outfits on widgets and the shield

- **Branch:** `worktree-agent-a7e6ad4fbf237a8bd` (based on `origin/main` at `c586ea9`)
- **Spec sections:** §5.17 (Buddy Closet, Buddy emotions), §5.17a (page companions), §15 (design system), §24 (additive only, never shaming)
- **Status:** Scaffolded — Unverified (not compiled; no Mac here. CI compiles and runs `BuddyMomentsTests`. The shield and widgets need a device)
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

Follow-ups left open by sessions 15, 24 and 29:

1. `BuddyPose(goal:moment:)` was only used on Today's goal tiles (session 24). Use it on the Fuel tab (react to protein and water logs, goal completion, nothing logged yet) and in the focus flow (running, done, ended early), including the Focus Live Activity, through the session 29 page-companion pattern rather than a new buddy view. Respect Reduce Motion.
2. Widgets and the shield should draw the equipped Buddy Closet outfit, read from the App Group, with a missing value falling back to no outfit.
3. Core unit tests for any new pure mapping logic.

## Definition of done

- The Fuel tab's buddy and the focus buddies change face with what happens, never shaming, with no motion under Reduce Motion.
- Widgets, the Live Activity and the shield wear the outfit saved in the closet; an older install with no saved outfit draws the bare buddy.
- New mapping rules are covered by Core tests that pass in CI.

## Log

### 2026-10-07 — Fuel and focus faces, outfit check

- **Files touched:**
  - `Core/Sources/Core/UI/Buddy/BuddyMoments.swift` (new): `BuddyPose.Moment(logged:target:)`, `BuddyPose.fuelPage(protein:water:justLogged:)`, `BuddyPose.focus(isPaused:outcome:)`.
  - `Core/Sources/Core/LiveActivity/FocusActivityAttributes.swift`: optional `ContentState.outcome` and new `FocusOutcome` (`done` / `broken`).
  - `Core/Sources/Core/Verification/FocusSessionVerifier.swift`: the ended Activity's final content carries `outcome` (verified gives `done`, otherwise `broken`).
  - `Core/Sources/Core/UI/Buddy/Cal.swift`: `pageBuddy` now draws a private `PageBuddy` that pops once when its pose changes (the streak pill's pop), and only swaps faces under Reduce Motion.
  - `Core/Sources/Core/UI/Buddy/Buddy.swift`: `StoredBuddySprite` gives `BuddySprite` `.id(buddy)`.
  - `App/ZANO/Features/Fuel/FuelView.swift`: `justLogged` state (set by every log path: chips, custom amount, barcode, gap ideas, staples, quick repeat, meal photo), cleared 3 s after the log; `.pageBuddy(fuelBuddyPose)` replaces the fixed `.pageBuddy(.eating)`.
  - `App/ZANO/Features/Today/TodayView.swift`: `TodayStatusRow` takes an optional `buddyPose`; the "focus running" bar shows the buddy focused (resting while paused) instead of the timer icon.
  - `Extensions/ZANOWidgets/LiveActivities/ZANOFocusLiveActivity.swift`: `ZANOFocusBuddy` takes the content state and uses `BuddyPose.focus` (was `happy` / `idle`).
  - `Core/Tests/CoreTests/BuddyMomentsTests.swift` (new).
- **What changed:**
  - **Fuel:** the navigation-bar buddy eats or sips for 3 s after a protein or water log, looks proud if that log met the goal, is proud while every fuel goal on the plan is met, hungry before any protein is logged, then thirsty before any water, and eats otherwise (and with no fuel goals at all, as before).
  - **Focus:** focused while a block runs (Today's bottom bar and the Live Activity), resting while paused, proud on the ended Live Activity of a verified block, resting on one that ended early. The "done" moment in the app was already the break coach card (session 25), which shows the buddy.
  - **Outfits:** nothing needed changing. Checked in code: since session 15's 2026-10-06 update, outfits are saved per buddy in the App Group (`BuddyOutfit.storageKey(for:)` = `shared.buddyOutfit.<buddy>`, JSON) and `BuddySprite` reads them with `@AppStorage(store: SharedDefaults.store)`. Every widget spot (`ZANOWidgetBuddy` on the Home widgets, `StoredBuddySprite` on the Live Activity, `ZanoLivingMark` in the report) draws through `BuddySprite`, so they already wear it. The shield (`ShieldConfigurationExtension.buddyIcon`) calls `buddy.image(pose: .sleepy, gear:, outfit: BuddyOutfit.stored(for:))` without the backdrop, a 48 px composite drawn once into a 96 pt @3x renderer (about 330 KB while drawing, then released), with the star as the fallback. The closet calls `WidgetRefresh.reloadAll()` on every wear and take-off. A missing or unreadable outfit decodes to bare (`BuddyOutfit.stored`, covered by `BuddyStyleTests`).
- **Decisions made and why:**
  - A focus block that ends early gets the resting face (`idle`), not `sad` or `meh`: spec §5.17a says companions are never shaming.
  - Hungry comes before thirsty when both are untouched: protein is the Fuel tab's hero card.
  - The after-log face lasts 3 s so the change is noticed and then settles; it is cleared by a `.task(id: logTick)`, so a second log restarts the timer.
  - `outcome` is optional in `ContentState` so older encoded content still decodes (tested), and existing callers compile unchanged (default `nil`).
  - `.id(buddy)` on `StoredBuddySprite`: `BuddySprite`'s outfit `@AppStorage` gets its key in `init`; a new identity per buddy means a buddy swap reads the new buddy's outfit rather than possibly keeping the old key's storage. Defensive; not observed (no device).
  - The shield keeps its sleepy pose and the existing renderer: it already draws the outfit cheaply.
- **Known issues / TODOs left behind:**
  - The Live Activity's "Paused" label can still show on the ended Activity if the block ended while paused (unchanged behaviour).
  - The watch keeps its own sprite set: no outfits and no focus outcome face there.
  - No focus screen exists in the app outside onboarding's first win (which already uses `focused` / `yawning`); the focus faces in the app live on Today's bottom bar and goal tile.
- **Needs verification on:** CI (compile and `BuddyMomentsTests`); the Simulator for the Fuel buddy pop and Reduce Motion; a real device for the Live Activity's end state, the Home widgets and the shield wearing an outfit.

## Blockers

- No Mac or Simulator here: this compiles and runs only in CI. The shield needs the Family Controls capability on a real device.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status
- [x] No secrets committed (check `.gitignore` coverage if you added new config/env files)

### 2026-10-08 — CI

- Merged into `claude/dazzling-hypatia-ed6q5d` with sessions 33-40. GitHub Actions run 147 (head 49a2e4c): the app with every extension, the Watch app, the embedded Watch build and the Core unit tests all pass. Device checks above still open.
