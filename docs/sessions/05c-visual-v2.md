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

### Buddies v4: cuter, distinct, eight obvious faces (2026-10-03)

Founder feedback on v3: "needs more variations and more obvious, the animals need to be cuter, they
seem copy and paste and boring". Redrawn from scratch (`scripts/buddies/`: `engine.py`, `face.py`,
`buddies.py`; the old `eng.py`/`chars.py` are gone):

- **48x48** (was 32): room for big eyes and readable faces. `BuddyPixels.size = 48`; any multiple of
  16pt draws evenly on 3x screens.
- **Distinct silhouettes**, not one template: Stash pear body + giant ringed tail and a phone; Zib a
  single mochi blob with long ears, star antenna and a blue bow; Lox slim with a bushy tail and a
  padlock locket; Pip an egg-shaped owl with gold ring eyes and pink gill fronds; Moko peeking from
  its egg with a shell cap; Brick wide and stocky (flexes when ecstatic); Tank chunky rhino in a Z
  jersey; Volt a torpedo shark with a bolt fin and teeth; Howl a wolf in a hoodie with cheek tufts.
  Each has its own eye shape/size/iris.
- **Eight faces** (`BuddyPose`): drained (> < eyes, tears, rain cloud, washed-out colours, ears down,
  arms hanging), sad (worried brows, tear, frown), meh (heavy lids, flat mouth, sweat drop), content
  (`idle`), happy, excited (sparkle eyes, big grin, one arm waving), ecstatic (^ ^ eyes, biggest grin,
  arms up, hearts), sleepy (closed eyes, snot bubble). Body language changes with the face.
- Charge → face: <15% drained, <30% sad, <45% meh, <60% content, <75% happy, <90% excited, else
  ecstatic; all goals done is always ecstatic. Mood → face: sleepy / content / happy (some done) /
  ecstatic (all done). Celebrations and milestone posters use ecstatic.
- App icon regenerated (Stash, happy, 48px).

## 2026-10-03 — Buddy everywhere

Founder: "more places to incorporate the app logo everywhere". The user's buddy now shows in:

- **Shield** (`Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift`): `icon` is the stored
  buddy (`Buddy.stored`, one App Group defaults read) in the `.sleepy` pose, the 48px sprite drawn 6x
  with `interpolationQuality = .none` into a 96pt @3x `UIGraphicsImageRenderer` (288px, ~330 KB while
  drawing). Falls back to the `ShieldMark` star if the sprite can't be built. Title, subtitle, both
  buttons and their labels (incl. the emergency path via "Use Time Bank") are unchanged.
  `ShieldPreview` (Core) matches: the 96pt grey glyph disc is now the sleepy buddy; the lock disc and
  the caption stay (`ShieldPreviewGlyph.systemImage` is no longer drawn).
- **Focus Live Activity** (`Extensions/ZANOWidgets/LiveActivities/ZANOFocusLiveActivity.swift`):
  buddy on the Lock Screen banner (48pt), the expanded island's leading region (32pt, next to the
  goal title) and as the compact leading glyph (16pt, replacing the timer symbol). Happy while
  running, content (`.idle`) while paused. Minimal keeps the timer symbol.
- **Notification images** (`Core/Sources/Core/UI/Buddy/BuddyNotificationImage.swift`, new): a 144px
  PNG (3x nearest-neighbour via CoreGraphics + ImageIO, no UIKit) cached once per buddy+pose under
  Caches/BuddyNotificationImages, copied to a fresh temp file per attachment because
  `UNNotificationAttachment` MOVES the file into the system store when the request is added. Any
  failure returns `nil` (no image); scheduling is never blocked. Wired into `NudgeScheduler` (happy;
  streak-at-risk sad), `TrialReminder` (content, through a new optional `buddyPose:` parameter on
  `NotificationPermission.scheduleOneShot`), `OnboardingDripScheduler` (happy) and
  `BedtimeGateManager` wind-down (sleepy). It lives in Core, not the app target as first suggested,
  because every local notification is scheduled from Core.
- **Empty states:** goals editor (64pt idle above the title), Progress's no-recap-yet card (48pt
  sleepy, replacing the calendar badge), unlock tiers empty card (48pt idle, replacing the stairs
  sticker), Squad's alone card (48pt idle, replacing the invite badge).
- **NFC:** tag-tap toast (32pt; happy, sad on a failed tap) and the write flow's success state (64pt
  excited under the title).
- **Settings footer:** 48pt idle buddy above the wordmark, tagline and version.
- **Launch screen:** `LaunchLogo` is now Stash (happy, 96pt, whole-pixel 2x/4x/6x) above the ZANO
  wordmark (pearl, 120pt wide, alpha from `docs/brand/zano-wordmark-1200.png`), generated by the new
  launch block at the end of `scripts/buddies/export_swift.py`. Static by nature, so it is always the
  default buddy. `UILaunchScreen` in project.yml unchanged.
- `StoredBuddySprite(pose:, size:)` (Buddy.swift): `BuddySprite` for the App Group's stored buddy,
  used by all of the above that are SwiftUI.

Skipped: a Fuel empty-day state (Fuel has no empty state, the meters show zero) and an NFC "no tags
yet" state (the tags section is simply hidden; the screen has its own hero). The ShieldAction
extension's hand-off notification has no image (extension, kept minimal).

Files: `Core/Sources/Core/UI/Buddy/{Buddy,BuddyNotificationImage}.swift`,
`Core/Sources/Core/UI/Components/ShieldPreview.swift`, `Core/Sources/Core/Store/NotificationPermission.swift`,
`Core/Sources/Core/Monetization/TrialReminder.swift`, `Core/Sources/Core/Social/{NudgeScheduler,OnboardingDripScheduler}.swift`,
`Core/Sources/Core/Verification/BedtimeGateManager.swift`, `Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift`,
`Extensions/ZANOWidgets/LiveActivities/ZANOFocusLiveActivity.swift`, `App/ZANO/Features/{Settings/GoalsEditorView,Settings/SettingsView,Progress/ProgressView,LockSetup/TierEditorView,Squad/SquadHomeView,NFC/TagTapToast,NFC/WriteTagFlow}.swift`,
`App/ZANO/Assets.xcassets/LaunchLogo.imageset/*.png`, `scripts/buddies/export_swift.py`.

Unverified (parse-checked only): everything until CI compiles it. Needs a device: the shield icon
(size/crop the system gives a 96pt icon, crispness), the Live Activity and Dynamic Island regions
(16pt compact fit, 32pt expanded), notification images (attachment thumbnail and expanded view), the
launch screen. `UIGraphicsImageRenderer` in the shield extension under Swift 6 isolation is assumed
nonisolated (true in the iOS 18 SDK as far as known).


### Buddy growth: levels and earned gear (2026-10-03)

Founder: "yes, start on buddy growth and accessories". Kept small on purpose (no shop, no coins:
earned only, which keeps it clear of the purchasable cosmetics in `CosmeticsStore`).

- **Level** from lifetime earned unlocks (`BuddyProgress.levelThresholds`: 0, 1, 3, 7, 15, 30, 50,
  75, 100, 150, 200, 300 → Lv 1–12).
- **Gear** (`BuddyGear`): party hat (first earned unlock), shades (7-day best streak), beanie (14),
  crown (30). Pixel overlays per buddy (`scripts/buddies/gear.py`, anchors per head; Moko's head
  drops in the slumped faces so it has a second variant), generated into BuddySprites.swift as
  `Buddy.gearPixels(_:slumped:)`. `Buddy.image(pose:gear:)` composes face + gear into one bitmap.
- **Worn item** in the App Group (`shared.buddyGear`): `BuddySprite` wears it by default
  (`gear:` overrides), so Today, widgets, posters and the shield all show it.
- **First unlock of each item puts it on once** (`BuddyProgress.adoptNewGear`, fire-once ledger
  `shared.buddyGearSeen`), run from Today when the completed-goal count changes. Taking it off sticks.
- **Settings > Buddy** shows a growth card under the grid: Lv chip + bar + "N more earned unlocks to
  Lv X", and four gear tiles (the buddy wearing each; tap to wear/take off; locked ones show the
  requirement). Not in onboarding (nothing earned yet).
- CI: new `buddy-gear` screenshot (demo progress Lv 4, hat + shades unlocked). Tests:
  `levelFollowsEarnedUnlocks`, `gearUnlocksFromPlay`, `newGearIsPutOnOnce`, `everyBuddyHasEveryGearOverlay`.
- **Reward beat:** when `adoptNewGear` puts something on, Today shows `BuddyGearToast` above its
  action bar for 6s: the buddy (ecstatic, wearing it) and "Stash put on the shades! 7-day streak."

### Founder polish pass (2026-10-04)

- **Settings > ZANO Pro card:** the title wrapped to "ZANO / Pro" because the streak pill sat beside the
  whole block. The pill now sits at the trailing end of the title row; the title is one line.
- **Buddy growth card:** it sat alone under the 3x3 grid with empty space below it. It now sits right
  under your buddy in Settings > Buddy and has a "next reward" row (the buddy trying on the next item,
  "9 of 14 streak days", a mini bar). `BuddyProgress.nextGear` / `nextGearProgress` + test. The
  duplicate `buddy-gear` screenshot was dropped (`buddy-picker` now shows the card).

### Gamification: XP on Today, weekly boss, perfect days, more gear (2026-10-04)

Founder: "build 1, 2, 3 and 4".

1. **XP and level on Today.** `BuddyProgress` is now XP-based: 10 XP per completed goal, 30 per earned
   unlock (`levelThresholds` 0, 30, 80, 160, 280, 450, 680, 1000, 1400, 1900, 2500, 3200 → Lv 1–12; about a
   week of steady days reaches Lv 5, a month Lv 10). Today shows `BuddyLevelStrip` ("Lv 5" + thin bar)
   under the buddy; a level-up toasts once (`shared.buddyLevelSeen`). Settings > Buddy shows "N XP to
   Lv X" and how XP is earned.
2. **Weekly boss: the Scroll Monster** (`Core/Retention/ScrollMonster.swift`). HP = a target of locked
   minutes (10% above last week's damage, 300–2400, 600 the first week); damage = locked minutes this
   week (overlaps once) + 20 per completed goal. States healthy / hurt (≤50% HP) / defeated; three colour
   variants by week number. Pixel art in `scripts/buddies/monster.py` → `ScrollMonster.pixels`. Beaten →
   +75 coins once per week (fire-once ledger `shared.scrollMonsterBeaten`, claim-then-pay like
   VariableReward), paid from Today with a toast. Progress gets a "This week's boss" section (monster,
   HP bar, days left, loot) right under Time reclaimed. Losing costs nothing.
3. **Perfect days** (`Core/Retention/PerfectDay.swift`): all of today's goals done → recorded once
   (`shared.perfectDays`), the buddy jumps and spins, and Today toasts "Perfect day! 3 in a row." The run
   (ending today or yesterday) and total show under the boss on Progress.
4. **More gear:** cape (Lv 5) and jetpack (Lv 10), drawn *behind* the buddy (`gearUnderPixels`, a new
   layer under the face), and a floating diamond (reached Diamond rank; remembered across seasons via
   `shared.buddyReachedDiamond`, recorded from Today). Seven items now, two rows on Settings > Buddy.

Today's gear toast became `BuddyToast` (gear / level up / perfect day / monster beaten), queued and shown
one at a time for 5 s. Tests: BuddyTests (XP levels, new gear rules, diamond memory, layers) and new
GamificationTests (boss damage/target/states/days left/art, perfect-day runs).
Unverified until CI: everything above. Device-only: nothing new beyond the existing list.
