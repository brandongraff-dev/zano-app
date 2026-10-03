# Session 5c — Visual direction v2 ("after-hours arcade, frosted glass")

- **Branch:** working tree on `main` (not committed by this agent; the orchestrating session commits)
- **Spec sections:** §15 (design system, token table superseded by `docs/design/visual-direction-v2.md`), §16, §5.1, §8, §24 (emergency unlock always visible)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-02
- **Last updated:** 2026-10-02

## Scope

Founder feedback 2026-10-02: the UI "looks a bit AI"; make it fun and themed, remove elements that
don't fit, a cleaner glassmorphic bottom nav, glass components. This pass: the design system (Theme +
shared components), the tab bar and tab container (Squad hidden for v1), Today, Lock, and the copy for
removed captions. Fuel, Progress, Settings, onboarding, paywall, celebration and milestone cards only
inherit the new tokens/components here; their own layout passes are listed in the design doc §6.

## Definition of done

- Design direction written (`docs/design/visual-direction-v2.md`) before code.
- Tokens and components updated so every screen picks the look up through `Theme` / `zanoCard` /
  `zanoHero` / `zanoGlass` / `zanoAmbient` / `zanoBackdrop`.
- Tab bar: one glass capsule, five icon-only tabs, sliding selected pill with label; UI-test labels
  and the `zano.tabBar` container id intact.
- Today and Lock redesigned; behaviour, hooks, accessibility labels ("Locked ·" prefix, "Hold to
  unlock in an emergency", tab titles) unchanged; emergency unlock visible in every locked state.
- CI build green and the screenshot tour reviewed (not done by this agent: no iOS SDK here).

## Log

### 2026-10-02 — v2 design system, tab bar, Today, Lock

- **Files touched:**
  - `docs/design/visual-direction-v2.md` (new)
  - `Core/Sources/Core/UI/Theme.swift` (palette, glass tokens, radii incl. `hero`, `Spacing.xxl`,
    tab-bar metrics, `Typography.score`/`label`, rounded headings, rounded small numerals, v2 motion)
  - `Core/Sources/Core/UI/Components/ZanoAurora.swift` (new: aurora canvas + `zanoAmbientIsLive`)
  - `Core/Sources/Core/UI/Components/HeroGlow.swift` (`zanoBackdrop`/`zanoAmbient` draw the aurora)
  - `Core/Sources/Core/UI/Components/ZanoSurface.swift` (cards are frost glass; `zanoHero` raised glass)
  - `Core/Sources/Core/UI/Components/ZanoGlass.swift` (chrome glass; `ZanoStatusCapsule` glyph option;
    new `ZanoGlassChip`, `ZanoInfoButton`)
  - `Core/Sources/Core/UI/Components/ZanoLivingMark.swift` (bob + lean; `ScreenTimeChargeView` chips;
    `zanoChargeBurst`)
  - `Core/Sources/Core/UI/Components/{NumeralText,PrimaryButton,StreakPill,StickyActionBar,GoalRing}.swift`
  - `Core/Sources/Core/Copy/TodayCopy.swift`, `Core/Sources/Core/Copy/LockStatusCopy.swift` (additive)
  - `App/ZANO/ZanoTabBar.swift`, `App/ZANO/ContentView.swift`
  - `App/ZANO/Features/Today/{TodayView,GoalActionList,LockVaultCard,FinishSetupCard}.swift`,
    `App/ZANO/Features/Today/Suggestions/SuggestionCard.swift`
  - `App/ZANO/Features/Lock/LockStatusView.swift`
- **What changed:** see the design doc §3–§5.
- **Decisions made and why:**
  - Content cards are frost without a real blur (the aurora is already soft; a material would cost a
    render pass per card and look the same). Real material only on chrome (tab bar, capsules).
  - `Typography.numeral(size:)` keeps its compressed face: ~20 unverified call sites (alarm clock,
    recap pages, share posters) would overflow with the wider score face. New code uses `score(size:)`.
  - Squad hidden by removing it from the bar and the container; `selection == .squad` (deep link,
    first-invite nudge) is steered to Today in `MainTabView` so nothing lands on a blank screen.
  - `Copy.lockStatus.blockingLine` (asserted by `LockTrustTests`) is unchanged and still the spoken
    label; the screen shows the new `blockingHeadline` / `blockingEnding` facts.
- **Known issues / TODOs left behind:**
  - Widgets keep their mirrored palette (`Extensions/ZANOWidgets/Support/ZANOWidgetColor.swift`): not
    updated to v2.
  - `UITests` comment in `ZANOUIScenarioSupport.swift` still lists a Squad tab (`squadTab` constant is
    unused by any test).
  - Navigation large titles (Lock, Fuel, …) are still the system face, not rounded.
- **Needs verification on:** CI build (Swift 6 type checking of `keyframeAnimator` closures, the
  tab bar layout on iPhone SE), screenshot tour, real device (aurora cost, Reduce Transparency /
  Reduce Motion / Increase Contrast paths).

## 2026-10-03 — Pass 2 (playful) and pass 3 (restraint)

- **Pass 2, playful** (founder: "make it more playful"): star mascot moods (sleepy/idle/perky/charged,
  jump on goal, spin on tap), `ZanoSticker`, `RollingNumber`, `zanoGoalTile`, squishy press, bouncy
  tab icons, rounded nav titles; Today compact stage (goals above the fold); Lock padlock character;
  Fuel game meters; Progress arcade (week pills, sticker streak grid, rank medal, trophy shelf);
  onboarding guide star, power cells, charging hold; playful paywall; sticker Settings; arcade unlock
  celebration; collectible share posters; sunrise ringing screen; gym charging meter; NFC sticker
  collection; trophy cabinet; v2 widget palette.
- **Pass 3, restraint** (founder: "don't overdo it, gradients everywhere aren't too much; icons are
  good"): aurora ~55% intensity and slower; flat goal tints instead of gradient washes; one hero glow
  per screen; no gradient text; solid buttons/meters/paths; posters at most two decorative layers;
  idle motion only on the star (and the alarm). Rules in docs/design/visual-direction-v2.md §9.
- **Fixes from screenshots:** paywall prices never truncate/wrap; locked-out poster headline clears
  the lock sticker; Today shows goals right after the hero; star not clipped; screen-time total kept
  under the star. EmergencyUnlock takes an injectable clock so hold tests don't depend on wall time.
- **Status:** Scaffolded — Unverified until the CI build + screenshot tour for this commit is green;
  all device-only behaviour still unverified.

## 2026-10-03 — Light mode

- **What changed:** every `Theme` colour token is now a light/dark pair (`ZanoTone`, `Theme.Tones`);
  the ~90 `.preferredColorScheme(.dark)` calls in App/ and Core UI are gone (previews keep theirs);
  Settings > Appearance (System / Light / Dark, default System) in App Group defaults, applied at the
  root in `ZANOApp`; nav bar titles use the dynamic `text` colour; chrome glass follows the scheme;
  light cards get a soft shadow; star graphite and logo metal adapt; Home widget + Screen Time report
  honour an explicit choice; CI screenshots gain a light pass (`-ZANOAppearance light`,
  `shots/light-<name>.png`). Palette and kept-dark surfaces: docs/design/visual-direction-v2.md §10.
- **Files:** `Core/Sources/Core/UI/Theme.swift`, `Core/Sources/Core/UI/ZanoAppearance.swift` (new),
  `Core/Sources/Core/Copy/SettingsCopy.swift`, `Core/Sources/Core/UI/Components/{ZanoGlass,
  ZanoSurface,ZanoLivingMark,ScreenTimeSummaryView,ShieldPreview}.swift`,
  `Core/Sources/Core/Retention/CosmeticsStore.swift` (comment), `App/ZANO/ZANOApp.swift`,
  `App/ZANO/ContentView.swift`, `App/ZANO/ScreenshotGallery.swift`,
  `App/ZANO/Features/Settings/SettingsView.swift` (Appearance row only), ~45 feature screens (forced
  dark removed; a few white-overlay tracks moved to `text.opacity`), `Extensions/ZANOShieldConfig/
  ShieldConfigurationExtension.swift`, `Extensions/ZANOReport/ZANOReportExtension.swift` (comment),
  `Extensions/ZANOWidgets/{HomeWidget/ZANOHomeWidget,Support/ZANOWidgetColor,
  Support/ZANOWidgetComponents}.swift`, `.github/workflows/ci.yml`, `scripts/ci/screenshots.sh`.
- **Decisions:** the shield stays dark (static cross-process value; dynamic colours unverified there);
  alarm, unlock celebration and share posters/moments stay dark on purpose; light goal colours are
  ≥4.5:1 so `onFill` labels on them still pass; main CI tour stays dark (screenshot runs default to
  dark unless `-ZANOAppearance light`).
- **Status:** Scaffolded — Unverified. Parse-checked only (`swiftc -frontend -parse`); needs the CI
  build and a look at the light screenshots, then a device for widgets, the report extension and
  the shield.

## 2026-10-03 — Buddies (the star is replaced by 9 pickable pixel-art buddies)

- **What changed:** the founder replaced the ZANO star mascot with nine pixel-art buddies (Stash
  default). Earlier commit: the `Buddy` model, generated sprite data, `BuddySprite`, colours, copy and
  the Stash app icon. This task: a "Pick your buddy" screen (onboarding step 2, new; Settings > Buddy
  row), the buddy drawn wherever the star was the character (Today hero incl. the `ZANOReport`
  extension's view, Lock idle hero, unlock celebration, onboarding hook/guide/meter/plan/first
  win/paywall, milestone poster + moment, recap intro, Home Screen widgets), pose from the day's
  mood, hero glow tinted with the buddy's colour, `-ZANOBuddy <rawValue>` screenshot argument, CI
  shots `buddy-picker`, `onboarding-8`, `buddy-brick-today`, `light-buddy-picker`, Core tests.
  Design notes: docs/design/visual-direction-v2.md §11.
- **Files:** new `App/ZANO/Features/Buddy/BuddyPickerView.swift`, `Core/Tests/CoreTests/BuddyTests.swift`;
  Core: `UI/Buddy/Buddy.swift` (pose raw value + `heroStorageKey`), `UI/Theme.swift`
  (`BuddyColors.onSignature`), `UI/Components/{ZanoLivingMark,ZanoMascot,ScreenTimeSummaryView}.swift`,
  `Copy/{BuddyCopy,ScreenTimeCopy,TodayCopy}.swift`; App: `ScreenshotGallery.swift`,
  `Features/Today/TodayView.swift`, `Features/Lock/LockStatusView.swift`,
  `Features/Celebration/UnlockStarStage.swift`, `Features/Settings/SettingsView.swift`,
  `Features/Onboarding/{OnboardingFlowState,OnboardingContainerView,OnboardingPlayKit,Screen1Hook,
  Screen10PlanReveal,Screen14FirstWin,PaywallView}.swift` (+ step-number comments in Screen3MainGoal,
  Screen4AppSelection, ScreenYourWhy), `Features/Share/{MilestoneCardView,MilestoneMomentView,
  RecapStoryPages}.swift`; Extensions: `ZANOReport/ZANOReportExtension.swift` (comment),
  `ZANOWidgets/{Support/ZANOWidgetComponents,HomeWidget/ZANOHomeWidget,
  LockScreenWidget/ZANOLockScreenWidget}.swift`; UI tests: `ZANOUITests/{ZANOUIScenarioSupport,
  Flow1PaywallFreePathUITests,Flow2OnboardingCompletionUITests}.swift` (buddy step); CI:
  `.github/workflows/ci.yml`, `scripts/ci/screenshots.sh`; docs: `docs/spec.md` §7 (one line),
  `docs/design/visual-direction-v2.md` §11.
- **Decisions:**
  - Onboarding is 8 steps: buddy right after the hook. Every later step number moved up by one, so
    `-ZANOScreen onboarding-N` ids shifted (the CI SE pass list was remapped to the same screens) and
    the UI tests tap "Team up with" on step 2.
  - The picker stores on every tap (like Settings > Appearance) and reloads widgets; "Team up"
    only advances (onboarding) or pops (Settings).
  - Today's hero on a device is drawn by the report extension, which can't see goals, so Today writes
    the pose to the App Group (`BuddyPose.heroStorageKey`) and `ScreenTimeChargeView` reads it (and
    the buddy) with `@AppStorage`; in-app callers pass the pose directly. The charge the star used to
    show as a fill is now only the "72%" sticker (which now carries the spoken charge); the screen-time
    total sticker stays under the hero.
  - The star stays where it is a brand mark, not the character (see design §11), including the
    Lock Screen accessory widgets and accented/vibrant Home widgets, where full-colour pixel art can't
    render legibly. `ZanoLivingMark` stays (Settings' Pro badge, previews).
  - Copy that named the star on Today/Screen time now names the buddy or the charge
    (`Copy.buddy.heroSpoken/heroHint`; `chargeHint`, `chargeSpoken`, `accessDetail`); the unused
    `Copy.today.mascotSpoken/mascotHint` were removed. Shield and widget copy about "the star
    charging" is unchanged (out of scope; flagged).
  - The picker's button label is a fixed dark ink (`Theme.BuddyColors.onSignature`) because every
    signature colour is mid-to-bright; the kind line uses `textSecondary` in light mode.
- **Known issues / unverified:** parse-checked only (`swiftc -frontend -parse` on every touched Swift
  file); needs the CI build, Core tests and a look at `shots/buddy-picker.png`, `onboarding-2.png`,
  `buddy-brick-today.png`, `light-buddy-picker.png`. Device-only: the report extension reflecting a
  pose/buddy change written by the app (cross-process `@AppStorage` refresh), widget rendering modes,
  haptics. Shield copy and the Lock Screen widget glyph still speak of the star.
- **Status:** Scaffolded — Unverified.

### Buddies: first screenshot review fixes (2026-10-03)

CI run 37147073060 (commit 7de3476) was green end to end (build, Core tests incl. BuddyTests, UI-test
compile, screenshot tour). Reviewing the shots found four issues, fixed here:

- **Picker: name drawn over the sprite.** The glow (1.8x the sprite) was a ZStack child, so it grew
  the stage and pushed the bottom-aligned sprite down onto the name. The glow is now a background.
- **Picker: last row (Tank, Volt, Howl) hidden under "Team up".** The hero is now compact and side by
  side (96pt sprite left; name, kind and world chip right), tiles 88pt min, so all nine fit above the
  button on a 6.1" phone (still a ScrollView for SE).
- **Today: buddy leaning ~12° and the 72% sticker over its belly.** The mascot motion's lean/sway/wiggle
  were star-era rotations; rotated pixel art goes jagged. Moods now use bob, breath and squash only
  (the tap spin stays, it is brief). The charge sticker sits beside the screen-time total under the
  buddy instead of on it.
- **`light-buddy-picker` came out as the launch screen.** Timing: the light pass now waits 7s per shot.

Files: `App/ZANO/Features/Buddy/BuddyPickerView.swift`, `Core/Sources/Core/UI/Components/ZanoMascot.swift`,
`Core/Sources/Core/UI/Components/ZanoLivingMark.swift`, `.github/workflows/ci.yml`.

### Buddies: faces follow the charge (2026-10-03)

Founder ask: "make them have different expressions depending on how charged they are". Three new
faces for all nine buddies (generated, `scripts/buddies/chars.py` → `BuddySprites.swift`, now 6 poses
each): `tired` (heavy lids, panting, sweat drop), `meh` (half-lidded, flat mouth), `grin` (big toothy
smile). `BuddyPose(charge:)`: <20% tired, <45% meh, <70% idle, <90% grin, else happy.
`BuddyPose.hero(charge:mood:)`: a finished day (all goals done) always beams; otherwise the charge
decides. `ScreenTimeChargeView` (Today's hero, in-app and in the `ZANOReport` extension) uses it
whenever there is a charge; before Screen Time access the day's mood alone decides (sleepy/idle/happy,
as before). Motion (hop, breathing) still follows the goal mood. Widgets have no screen-time charge and
keep the goal-mood faces. Volt's resting face became a closed smile so his toothy grin means something.
Tests: `faceFollowsTheCharge`, `heroBeamsWhenTheDayIsDoneWhateverTheCharge` in BuddyTests.
Unverified until CI/device: the faces in the running app (demo charge is 72%, so screenshots show the grin).
