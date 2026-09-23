# Composition audit — every screen under `App/ZANO/Features/**`

**Date:** 2026-09-23. **Status:** read-only design review. The only file this task wrote is this one.

**What "read" means here.** All 33 Swift files under `App/ZANO/Features/**` were read top to
bottom (Today, Lock, Fuel, Progress, Settings incl. its 4 private sub-screens/sheets, LockSetup x3,
Share x2, Trophy x2, SunriseAlarm x3, Celebration, Onboarding: container + `OnboardingFlowState` +
Screens 1-14 + `PaywallView`; the dead `Screen13Paywall` included), plus `Theme.swift` and the 13
Core/UI components those screens compose (`GoalRing`, `RingCluster`, `LockStatusCard`, `GoalRow`,
`PrimaryButton`, `StreakPill`, `TimeBankBar`, `RecapCard`, `GhostProgressBanner`, `ShieldPreview`,
`ShareCard`, `PaywallCard`, `OnboardingQuestion`). Not read: `CelebrationBurst`, `FounderSeriesCard`
(no screen uses it), `PreviewCatalog`. `ContentView.swift` / `ZANOApp.swift` were read for context only
and are owned by the concurrent wave.

**What this is not.** There is no Mac, Simulator or device in this environment. Nothing below was
rendered. Every "you would see" statement is arithmetic on the source (frame sizes, font sizes,
padding) against an assumed **iPhone 15/16, 393 x 852 pt, 16 pt screen gutters -> 361 pt content
width, default Dynamic Type**. Where a claim depends on Swift name lookup or on a system default I say
so. Pattern references in section 6 come from working knowledge of shipping apps, not from anything
fetched this session - verify visually before copying a number.

**Relationship to sibling docs.** `ui-stress-test-findings.md` and `apple-design-review.md` already
cover accessibility, Dynamic Type, reduced motion and animation. This document deliberately does not
repeat them. It answers a different question: *if I composed each screen in my head, does it have a
focal point, does it look designed, and does it look like one app?* Line numbers are as of this read
and will drift.

---

## 0. Verdict

The code is disciplined; the screens are not designed. Every colour, radius and spacing value comes
from `Theme`, every string is routed through `Copy` (with a handful of leaks), and the components are
well built. What is missing is **hierarchy and material**:

1. **Nothing is big.** `Theme.Typography` tops out at 44 pt (`numeralLarge`). Spec section 15 asks for
   "chunky bold numerals... big numerals for grams/minutes/streak". Across 33 screens `numeralLarge`
   is used in exactly five places and `numeralMedium` in three (plus `GoalRing`'s centre text). The
   protein number on the Fuel screen, the day count on the Wake-Up screen, the clock on the alarm, the
   "2h 10m unlocked" reward on the celebration: all are 13-44 pt. There is no focal number anywhere in
   the app.
2. **Nothing has depth.** Card surface (`#141416`) against background (`#0A0A0B`) is **1.076 : 1**
   (computed; iOS's own grouped-card-on-black is 1.23 : 1). None of the five tab screens draws a stroke
   of its own (the only one they can show is the conditional Always-Allowed banner in Settings). Across
   the whole repo (app + Core/UI) there is **one** gradient (`ShareCard`), **zero** shadows, **zero**
   glows, **one** material (`Today`'s bottom bar). Spec section 16's own style paragraph asks for
   "subtle inner glow on active elements, crisp 1px hairline dividers". The cards will read as faint
   grey slabs.
3. **Everything is the same weight.** Today = lock card, three equal rings, ghost card. Progress =
   four identical `surface` cards. Fuel = rings, then three `headline` + `GoalRow` stacks. Lock = two
   near-identical status cards before a goal ever appears. When every block is a radius-20 rounded rect
   with a 40 pt icon circle and a headline, the eye has no entry point.
4. **Three visual dialects.** (A) custom dark cards (Today, Lock, Fuel, Progress, Trophy, Share);
   (B) stock iOS `Form`/`List` (Settings + its 4 sub-screens, LockSetup, SunriseAlarm setup, Bedtime
   Gate, every sheet); (C) onboarding "poster" (centered icon + title + body + button). They do not
   feel like the same product, and there are **three different screen-title treatments** (Today's
   custom 22 pt in-scroll header; Lock/Sunrise/Bedtime's `.inline` nav title; Fuel/Progress/Settings/
   Trophy/Cosmetics/LockSetup's default `.navigationTitle`, i.e. the system large title unless a parent
   overrides it).
5. **Broken rendering, not just taste.** The Today hero ring row overflows every iPhone (offender 1),
   and seven "spinners" in the app are almost certainly the entire Progress screen (offender 2).

The good news: fixing five design-system gaps (section 3) plus rebuilding roughly ten screens'
composition gets the app from "tutorial-grade" to "designed". None of it needs new architecture.

**What already works and should be kept:** the token discipline itself; `GoalRow`'s status semantics;
`TrophyTile`'s earn moment; `AlarmRingingView`'s structure (escalating tint, always-present escape
hatch, four dismiss variants); onboarding option cards' selected state (accent stroke + `surface2`
fill); `AlwaysAllowedWarningView` (the one component that already has a stroke and reads as designed);
the hold-to-commit pattern; the fixed-frame `LockedOutMomentContent` copy model; `StreakHistoryGrid`
as an idea.

---

## 1. Rubric

For each screen I asked four questions:

| # | Question | Failing looks like |
|---|---|---|
| F | Is there **one focal point** (a number, a ring, a state) that wins in under a second? | Equal-weight cards; 44 pt max; a list of headlines |
| S | Is it **custom composition** in ZANO's dark/acid-green language, or default `List`/`Form`? | System grouped background, system fonts, system rows |
| D | Is **density** right? | Sparse = 22 pt title floating in void; dense = 5 stacked `GoalRow` sections |
| A | Does it feel like the **same app** as Today? | Different title treatment, background, control set |

---

## 2. The ten worst offenders (ranked by visibility x severity)

Each entry: where, what you would see, why it fails, fix direction. Sizes/tokens are proposals; any
new token needs a spec section 15 amendment first (see `Theme.swift` header). Section 3 defines the
shared pieces the fixes lean on (**S-1** hero numeral type, **S-2** card surface/elevation, **S-3**
GoalRing hero size + coloured track, **S-4** dark form scaffold, **S-5** button variants, **S-6**
`SelectableCard`, **S-7** `GoalRow` without a status glyph).

### 1. `TodayView` (+ `RingCluster`) — the hero screen has no hero, and its ring row doesn't fit

**Where:** `Today/TodayView.swift:88-103` (body), `:179-203` (lock card, rings),
`:224-230` (ring items), `:292-333` (CTA states), `:105-111` (bottom bar);
`Core/UI/Components/RingCluster.swift:97-106,164`; `GoalRing.swift:31-51,105,173`.

**What you would see.** A 22 pt "Today" + streak pill; a `LockStatusCard` (surface, 40 pt icon
circle, headline, caption); **three `.large` rings in a horizontal `ScrollView`**; a `GhostProgressBanner`
(surface, 40 pt icon circle, eyebrow, body, scoreboard); a bottom bar.

**Why it fails.**
- **The rings overflow.** `RingCluster(.row)` lays out `RingClusterCell`s of
  `max(148, 64) = 148` pt with 24 pt gaps: 3 x 148 + 2 x 24 = **492 pt** in a **361 pt** column. The
  Focus ring is ~2/3 off-screen behind a hidden-indicator horizontal scroll nested in a vertical scroll.
  Worse on 6.1" and smaller. The hero moment of the app is clipped.
- **No focal point.** Three equal rings, sandwiched between two visually identical cards (same
  surface, same radius, same 40 pt tinted-circle-plus-headline layout). The state that defines the
  screen - locked vs unlocked - is a list row, not a hero.
- **The numbers are missing.** Rings carry only an icon (`centerIcon`); the value (`72/150g`) is a
  13 pt muted caption under each. Spec section 15: "big numerals for grams/minutes/streak". Also
  `GoalRing.swift:173` picks `numeralMedium` (28 pt) for both `.medium` and `.large`, so even if a value
  went in the ring it wouldn't scale with it.
- **Empty rings vanish.** The unfilled track is `surface2` (`GoalRing.swift:105`) directly on
  `background`: **1.16 : 1**. A 0 % ring (every ring on a new day, and all three in the "not set"
  state) is a whisper; only the ~50 pt centre icon (`0.34 x 148`) remains.
- **The CTA is dead in 5 of 8 states.** `PrimaryAction` has 8 cases; `setupIncomplete`,
  `focusRunning`, `verifyingAtGym`, `waitingToUnlock` and `openFuel` all render a `PrimaryButton` with
  `isEnabled: false, action: {}` - a 50 %-opacity green slab. `openFuel` (`:330-331`) is titled "Open
  Fuel" and does nothing; for anyone whose remaining goals are protein/water (the common case) the only
  CTA on the main screen is inert. `beginLock` is a 2-second hold-to-commit for a routine daily action,
  which spends the pattern's specialness (it is the app's commitment/emergency gesture).
- **Minor:** the bottom bar is the app's only `Material` (`:110`), reading as a grey slab on a flat
  black screen; `NavigationStack` with no `.navigationTitle` leaves an empty nav-bar band above the
  custom header (add `.toolbar(.hidden, for: .navigationBar)`); hardcoded `"min banked"` (`:194`) and
  `"Done"/"Not yet"` (`:468`) bypass `Copy`.

**Fix direction.**
```
TUE - SEP 23                                   [ flame 14 ]   <- eyebrow (captionEmphasized, muted, uppercase) + title
Today
+--------------------------------------------------------+
| LOCKED                                                 |   state band: radius .large (28), surface,
| 2 goals to earn                                        |   danger@0.14 -> clear top-leading gradient,
| [icons] TikTok, Instagram, YouTube        > Lock       |   1 px stroke (S-2). "2" in numeralLarge.
+--------------------------------------------------------+
                    +---------+
                    |   72    |     hero ring = the goal the CTA acts on (GoalRing .hero, S-3)
                    |  g / 150|     value in numeralHero (S-1); icon + title beneath
                    +---------+
        ( 88 ring )              ( 88 ring )                   satellites: .medium, equal columns
        Workout  done            Focus 25/50
 ghost: "1 ahead of your best week" - single 44 pt line, no card
[ Start focus - 25 min ]        <- pinned; gradient fade (background@0 -> background), never disabled
```
- **Minimum fix if spec P1's "three equal rings" is kept:** three `.medium` (88 pt) rings in
  `HStack` with `.frame(maxWidth: .infinity)` cells = 3 x 88 + 2 x 24 = 312 pt: fits, no scroll. Move
  the value into the ring (`.text("72")`, unit/target as a caption line) and switch `RingCluster`'s
  `.row` to non-scrolling equal columns. Use `.hero` + two satellites only after amending P1.
- Track becomes `color.opacity(0.18)` (Apple Fitness convention; the app already uses `.opacity(0.16)`
  for icon-badge fills) so an empty ring is visible and colour-coded (S-3).
- Never render a dead CTA. `focusRunning` -> replace the button with a live countdown row +
  "End"; `verifyingAtGym` -> a status row ("At Equinox - 12 min"); `waitingToUnlock` -> hide the CTA,
  the state band turns accent and says "Unlocking"; `setupIncomplete` -> enabled "Finish setup".
  `openFuel` needs a tab switch, which needs `AppRouter` (owned by the concurrent wave): add an
  `onOpenFuel: () -> Void` parameter to `TodayView` now and let the ContentView owner inject it.
  `beginLock` should be `.standard`; keep `.holdToCommit` for emergency unlock and onboarding commit.
- Ghost banner: demote to a one-line inline row (icon + text + `numeralSmall` scoreboard). It is the
  third-most important thing on the screen, not a full card.
- Fix the bottom bar with a `LinearGradient` fade rather than `.ultraThinMaterial`.

**Touches:** `TodayView.swift`, `RingCluster.swift`, `GoalRing.swift`, `GhostProgressBanner.swift`,
`LockStatusCard.swift`, `Theme.swift`. **Blocked-by:** `AppRouter` only for the `openFuel` navigation.

---

### 2. Seven "spinners" are the Progress screen (name shadowing) — a rendering bug, not a taste issue

**Where** (bare `ProgressView()` in the `ZANO` module): `Fuel/FuelView.swift:1106`;
`SunriseAlarm/AlarmRingingView.swift:235,264`; `SunriseAlarm/SunriseAlarmSetupView.swift:319`;
`Onboarding/PaywallView.swift:222,319,351`.

**Why.** `Progress/ProgressView.swift:111` declares `struct ProgressView: View` at module scope. Swift
resolves unqualified names to the current module before imports, so `ProgressView()` in every other file
in the module means *the Progress tab*, not `SwiftUI.ProgressView`. It compiles (the type has a default
`init()`), which is exactly what `LockedOutMomentView.swift:468-477` and `WeeklyRecapShareView.swift:
312-318` warn about in comments - and both spell `SwiftUI.ProgressView()`. The seven sites above did not.
Confidence: high by Swift's shadowing rule and by two independent in-repo comments; **not
compiler-verified** here.

**What you would see.** Paywall while offerings load: an entire Progress scroll view inside the offerings
slot (`:222`). Paywall purchase in flight: a Progress scroll view stacked in the CTA `ZStack` (`:319`),
expanding the CTA area to the height of a screen. Alarm settings-loading and tag-scanning states: the
Progress tab inside the alarm card. Barcode "looking up" state: the Progress tab full-bleed in the sheet.

**Fix.** Qualify all seven as `SwiftUI.ProgressView(...)` now. Do **not** rename the screen type yet -
`ContentView` (concurrent wave) almost certainly references `ProgressView()` for the tab; rename to
`ProgressScreen` only after that wave lands. Consider one 3-line `ZanoSpinner` in Core/UI so nobody types
the bare name again (accent tint, small).

---

### 3. `FuelView` — a logging screen whose numbers are 13 pt and whose actions are 32 pt

**Where:** `Fuel/FuelView.swift:358-391` (rings + quick-add), `:393-420` (ring items), `:422-450`
(`quickAddRow`), `:459-484` (gap planner), `:601-619` (quick repeat), `:657-688` + `:952-997` (staples),
`:873-897` (`FuelQuickAddChip`), `:1165-1216` (barcode result/serving), `:1153,1199` (text fields).

**What you would see.** Two `.large` rings (2 x 148 + 24 = 320 pt) **left-aligned in a 361 pt column**
(the row is a `ScrollView(.horizontal)`; 41 pt of dead space on the right); `72/150g` and `1250/3000ml` in
13 pt muted captions under them; then two anonymous chip rows; then up to three more `headline`-titled
sections.

**Why it fails.**
- **`label:` is declared and never used.** `quickAddRow(label:...)` (`:422-425`) takes `"Protein"` /
  `"Water"` and never renders it. Two identical-looking chip rows sit under the rings and only the tint
  says which is which.
- **The best actions are hidden.** The protein row is `+15g +25g +40g [Log custom amount] [Scan barcode]`
  ~ 460 pt (estimate) in a 361 pt horizontal scroll with no indicator: barcode scan, the app's most differentiated
  logging path, is off-screen on first load.
- **Hit targets:** `FuelQuickAddChip` is 13 pt text + 8 pt vertical padding ~ **32 pt tall** (`:887-892`),
  the primary action of a screen used several times a day; staple delete is a 14 pt glyph in a 32 x 32
  frame (`:985-991`).
- **The result of an action is 13 pt.** Logging changes a ring and a caption. No `sensoryFeedback`
  anywhere in the file (spec: "haptics on every verified event").
- **Everything below is `GoalRow`.** Gap planner = 3 `GoalRow`s with a rank prefix leaking engine
  internals (`"#1 ·"`, `:505,507`) and a trailing empty circle (which reads "unchecked to-do", wrong for
  an *option*; S-7). Quick Repeat = a `GoalRow` whose *title is a question sentence* ("Your usual chicken
  bowl (48g)?") with the same empty circle and no visible "log" affordance. Staples = a list with a trash
  icon. Four sections, one look.
- **Sheets/results are stock.** `ManualAmountSheet` / `KitchenStapleAddSheet` are default `Form`s;
  barcode fields use `.textFieldStyle(.roundedBorder)` (a light system field in a dark sheet, `:1153,
  1199`); the scan result's hero is a 28 pt `numeralMedium` (`:1177`) centred in a void.

**Fix direction.**
```
Fuel
+-- Protein ---------------------------------------------+
| ( ring 88 )   72 / 150 g               <- numeralLarge  |   one card per macro (S-2), tint = ring colour
|               78 g to go                                |   ring keeps the icon; the number is beside it
| [ +15 ] [ +25 ] [ +40 ] [ ... ] [ scan ]  <- 44 pt tall|   chips live INSIDE the card they belong to;
+---------------------------------------------------------+   scan = 44 x 44 icon button, never scrolls away
+-- Water -----------------------------------------------+
| ( ring 88 )   1,250 / 3,000 ml                           |
| [ +250 ] [ +500 ] [ +750 ] [ ... ]                       |
+---------------------------------------------------------+
Suggested now   (gap >= 20 g)  ONE hero suggestion + "Log 20 g" button; the other two as text links
Quick repeat    Chicken bowl - 48 g                    [ Log ]      <- explicit button, no question sentence
Kitchen staples chips / 2-col tiles (name + grams); tap logs; long-press = delete
```
- Numbers go in `numeralLarge` (or `numeralHero` if S-1 lands), ring becomes a small companion.
- Chips: `minHeight: 44`, `numeralSmall` for the amount, tint at 0.14 stays. Add
  `.sensoryFeedback(.success, trigger: logTick)` + a brief ring/number bump.
- Drop the `#rank` prefix; show *one* recommended gap option (tier order already ranks it).
- `.textFieldStyle(.roundedBorder)` -> a `surface2` field with a stroke; barcode result: product name
  `title`, protein in `numeralHero`/ring colour, single full-width Log button, 3 lines total.
- `ManualAmountSheet`/`KitchenStapleAddSheet`: replace `Form` with the S-4 dark scaffold and a large
  numeric entry (`numeralLarge`, decimal pad, quick-step chips).

**Touches:** `FuelView.swift` only (+ S-2/S-7 components). No forbidden paths.

---

### 4. Onboarding 9 -> 10 -> 11: the emotional peak of the flow is a stat line, a list and an empty screen

**Where:** `Onboarding/Screen9WakeUp.swift:82-133,147-199`; `Screen10PlanReveal.swift:50-135`;
`Screen11Commitment.swift:40-84`; plus `Screen14FirstWin.swift:222-253,585-642`.

**Screen 9 — inverted hierarchy.** The pain number (`daysPerYear`, e.g. 76) is `numeralLarge` 44 pt in
`danger` (`:103`); the reward (`daysReclaimed`) is `numeralMedium` **28 pt** in accent (`:118-123`) - the
reason to continue is smaller than the fear. The 22 pt `title` headline already states the number ("At
5h/day, that's ~76 days a year on your phone.", `OnboardingCopy.swift:104-106`), the counter then shows it
again, and its 13 pt caption repeats "days a year on your phone" (`:108`) verbatim - the same fact three
times in one glance. Two counters are stacked with `Spacer`s instead of *staged*.
- **Fix:** one hero at a time. Beat 1 (0-0.9 s): `numeralHero` (>= 88 pt, S-1) `days` count-up in
  `danger`, caption "days a year on your phone" (`headline`, muted); shorten
  `Copy.onboarding.wakeUpHeadline` to the hours clause ("At 5h/day...") so the counter carries the number
  once. Beat 2: the red number scales to ~0.5 and moves up (`matchedGeometryEffect` or
  `offset`), an accent `numeralHero` "+30 days back" counts up in its place. Reduced motion: both numbers
  shown statically, stacked. Add `.hero` to `OnboardingAnimatedCount.Size`.

**Screen 10 — the "reveal" is a `GoalRow` dump.** Spec P4: "bespoke card: locked apps row with icons,
goals list, schedule, difficulty tag 'Starting easy on purpose', hold-to-commit". Actual: the shared
`LockStatusCard(isLocked: true)` (a red padlock, "Locked" - before anything is locked; `:55-59`), one
`GoalRow` per goal with `status: .pending` (an empty to-do circle on a plan; S-7, `:72`), a text-only
`scheduleCard` (`:115-135`), a caption, a full-width Continue (`:84`). No app icons, no difficulty tag,
no staging; 22 pt title.
- **Fix:** stage the reveal (header -> "Locks these apps" row with up to 6 real app icons via
  `Label(token)` [ManagedSettingsUI; unverified here] -> goal rows one at a time, each showing an *empty
  ring in its goal colour* + target, no status glyph -> schedule chip -> accent "Starting easy on purpose"
  tag). One composite card (S-2) rather than four siblings. Stagger via `.transition` +
  `Theme.Motion.springStandard` delays capped at ~5 items; reduced motion = one cross-fade.

**Screen 11 — a 22 pt title floating in a black void.** `Copy.onboarding.commitHeadline` (`title`), a
subtitle, a recap capsule, then a hold button at the bottom (`:40-84`). The one ritual moment in the app
has no ritual visual - spec P4 wants "a hold-to-commit button... with a progress outline".
- **Fix:** make the ring the button: a 200 pt `GoalRing.hero` (S-3), empty in accent-track, filling
  under the finger over 2 s (mirror the `AlarmRingingView` escape-hatch pattern), "Hold to commit" inside
  in `headline`; commitment sentence above in `display` (S-1), recap capsule below. On completion the
  ring closes with `springCelebration` + `.success` haptic. Keep the VoiceOver `accessibilityAction`.

**Screen 14 — a second, weaker celebration language.** `celebratingView` (`:222-253`) = 56 pt flame +
22 pt title + `StreakPill`, plus `OnboardingConfettiView` with a **five-colour** palette (`:598-604`)
that breaks "ONE accent only". Meanwhile `UnlockCelebrationView` already exists ("Earned.", accent burst,
Time Bank). **Fix:** present `UnlockCelebrationView` here (streak 1, no badge) and delete the bespoke
confetti; one celebration language for the whole product. `EmergencyHoldControl` (`:544-579`) is a 160 x
6 pt bar - a 60 s safety control at a size that is hard to find and hold; make it the same ring-hold as
the alarm's escape hatch, `.medium`.

**Touches:** `Screen9/10/11/14`, `UnlockCelebrationView`, `Theme.swift`, `GoalRing.swift`. All in
onboarding/Core-UI; no forbidden paths.

---

### 5. `PaywallView` (+ `PaywallCard`) — revenue screen, CTA below the fold, plan cards nearly identical

**Where:** `Onboarding/PaywallView.swift:112-125` (layout), `:158-163`, `:167-191`, `:195-214`,
`:247-262`, `:306-326`; `Core/UI/Components/PaywallCard.swift:59-110`. (`Screen13Paywall.swift` is dead
wiring - `OnboardingContainerView.swift:115` routes to `PaywallView` - delete or ignore.)

**What you would see.** A 30 pt headline; three benefit rows (32 pt accent icon circles + 15 pt body); a
"your plan" section; two plan cards; then trial note, CTA, Restore, "Continue free" - **all inside one
`ScrollView`**.

**Why it fails.**
- **The CTA isn't pinned.** Estimated content: 24 pad + 37 headline + 32 + 120 benefits + 32 + 112-192
  built plan + 32 + 154 cards + 32 + ~150 CTA block + 32 ~ **760-840 pt** vs ~**700 pt** visible under the
  onboarding header on a 852 pt phone. The purchase button is below the fold for everyone with an
  Earn-everything plan, and more so on smaller phones. Estimate, not measured.
- **"Your plan" is a to-do list.** `GoalRow(title:, icon: "target", status: .pending)` (`:210`): every
  goal gets the same generic `target` icon and an empty status circle (S-7). It also repeats Screen 10.
- **Annual vs monthly are the same object.** `PaywallCard` differs only by a 40 %-opacity stroke and a
  "BEST VALUE" pill (`:94-106`); both are 71 pt cards with the price in a 17 pt `numeralSmall`. Spec P5
  says the annual card is highlighted and monthly "smaller". The price - the thing being sold - is the
  same size as a caption plus 4 pt.
- **Off-token:** headline `.system(size: 30, ...)` (`:160`); benefit icons in accent for decoration
  (accent = earned/CTA, S-8). Loading/purchasing/restore states hit offender 2.

**Fix direction.**
- `PaywallView` body -> `ScrollView` for headline/benefits/plan, and `.safeAreaInset(edge: .bottom)` for
  **CTA + trial note + Restore + Continue free**, with a gradient fade above it. One tap from anywhere.
- Replace the "plan" `GoalRow`s with a compact chip row / three mini empty rings in goal colours (or drop
  it - Screen 10 already showed it).
- `PaywallCard` gets a `size`: annual = `.hero` (radius `.large`, 2 pt accent stroke, `accent@0.06` fill,
  price in `numeralMedium`, "$3.33/mo" as sub-hero, trial pill "7 days free"); monthly = `.compact` (radius
  `.small`, `numeralSmall`, no fill). Selected state = stroke weight, not a second glyph.
- Benefit icons in `text` on `surface2` circles (keep accent for the CTA and the selected plan).
- `display` type token for the headline (S-1).

**Touches:** `PaywallView.swift`, `PaywallCard.swift`, `Theme.swift`.

---

### 6. `ShareCard` + `WeeklyRecapShareView` + `LockedOutMomentView` — the export will be a near-empty black rectangle

**Where:** `Core/UI/Components/ShareCard.swift:78-131` (layout), `:133-145` (ring strip), `:161-172`
(`renderImage`); `Share/WeeklyRecapShareView.swift:154-224`; `Share/LockedOutMomentView.swift:301-381`,
`:512-525`.

**Why it fails.**
- **Export scale is wrong.** `renderImage` lays the card out at **1080 x 1920 *points*** with
  `scale = 1` (`:162-171`). All type is `Theme.Typography`: title 22 pt, stat line 17 pt, footer 13 pt;
  rings `.small` = 44 pt. On a 1080 pt canvas 22 pt is **2 % of the width**; a 44 pt ring is 4 %. The
  on-screen preview (320 pt wide) looks proportionate; the PNG the user actually posts does not - it is a
  black 9:16 with microscopic text and a big empty `Spacer` (`:115`). What you preview is not what you
  share.
- **No hero.** Spec P7 is "chunky numerals" - 7 rings, big stats. The card has no numeral above 22 pt.
  `LockedOutMomentView` passes `dayRings: []` (`:515`), so that card is *text only*: a title, a stat line
  and a highlight line on a gradient. A viral share card with no graphic and no brand mark beyond a 13 pt
  muted "ZANO".
- **Screen chrome:** the header has an `xmark.circle.fill` dismiss *and* the footer repeats a "Close"
  text button (`LockedOutMomentView:371-378,424-427`; `WeeklyRecapShareView:214-220,267-270`). The card
  is capped at `maxWidth: 320` on a 393 pt screen.
- **Unreachable:** neither screen is presented from anywhere (previews only). `RecapCard` in Progress has
  no Share action.

**Fix direction.**
- Design the card at **360 x 640 pt** and export with `scale = 3` (-> 1080 x 1920 px). Everything then
  scales with the export and the preview finally equals the PNG. (Keep the existing `.aspectRatio(9/16)`.)
- Recap layout at 360 x 640:
```
WEEK 38                                        ZANO  (accent dot + wordmark, headline weight)
        12 / 14              <- numeralHero, accent, 88 pt; radial accent@0.18 glow behind (S-2)
   goals completed
  --------------------------------
  M    T    W    T    F    S    S      <- 7 rings .small (44 pt -> 132 px at x3), accent, labels caption
  6h 40m reclaimed   |   Best day: Thursday      <- headline, then body muted
                                  zano.app
```
  Locked-out card: hero = `numeralHero` "4x" + "You tried to open TikTok 4 times in an hour", ring
  strip omitted, bottom third anchored with wordmark + `StreakPill`. Bottom-anchor the footer; no
  free-floating `Spacer` void.
- Screens: single dismiss (keep the header xmark), `ShareLink` CTA in `safeAreaInset(.bottom)`, preview
  card `frame(maxWidth: .infinity)` inside 32 pt gutters, secondary "Save image".
- Add the entry points: a Share button on `RecapCard`/Progress, and present `LockedOutMomentView` from
  whichever wave wires the tracker.

**Touches:** `ShareCard.swift`, both Share views, `RecapCard.swift`, `ProgressView.swift` (entry point).

---

### 7. `LockSetupView` (+ `AppPickerView`) — the most tutorial-grade screen, and unreachable

**Where:** `LockSetup/LockSetupView.swift:105-116` (List), `:212-259` (row + toggle), `:362-399`
(editor `Form`), `:200-210` (empty state); `AppPickerView.swift:46-60`. Only a `#Preview` references
`LockSetupView()` - nothing in the app navigates to it.

**Why it fails.**
- **Stock everything, and off-token.** A plain `List` with system background (pure black `#000`, not
  `#0A0A0B`) and rows in `.font(.body)`, `.foregroundStyle(.primary)`, `.font(.caption)`,
  `.foregroundStyle(.secondary)` (`:219-223`; `AppPickerView:53`) - the only Feature file that bypasses
  `Theme.Typography`/`Theme.Colors` outright, against `Theme.swift`'s own header.
- **A lock set is the product's core object and it has no identity.** Name, "3 apps, 1 category", a
  `Switch`. No app icons, no "default" badge, no state.
- **A toggle that lies.** The default switch ignores off (`:246-259`, `guard isOn else { return }`):
  the user flips it, it snaps back. That is a radio wearing a switch's clothes.
- **The picker is a `LabeledContent` row** - "Select apps ........ 3 apps" - the highest-stakes choice in
  setup rendered as a settings line. No preview of what will be shielded; `AlwaysAllowedWarningView`
  exists and is never used here.

**Fix direction.**
- Keep `List` (swipe-to-delete, a11y) but style it: `.listStyle(.plain)`, `.scrollContentBackground(.hidden)`,
  `Theme.Colors.background`, `.listRowBackground(Color.clear)`, `.listRowSeparator(.hidden)`, and make
  each row a card (S-2): leading overlapped icon stack of up to 4 real app icons (28 pt, `-8 pt` overlap)
  + `+N` chip; `headline` name; `caption` summary; trailing **"Default" pill** (accent outline) instead of
  a switch. "Make default" = context menu / editor button. Empty state = the same card language (an
  outlined dashed "Create your first lock set" tile), not `ContentUnavailableView`.
- Editor sheet: S-4 scaffold; "Choose apps" becomes a 2-row drop-zone card that shows selected icons
  after picking, with the Always-Allowed banner directly under it when relevant.
- Add a Settings row ("Lock sets") - `SettingsView` is in scope; nothing to coordinate.

**Touches:** `LockSetupView.swift`, `AppPickerView.swift`, `SettingsView.swift` (one row), S-4.

---

### 8. `AlarmRingingView` — the clock is 44 pt, and the escape hatch is as loud as the task

**Where:** `SunriseAlarm/AlarmRingingView.swift:133-154` (layout), `:181-211` (header), `:269-295`
(steps/focus rings), `:372-444` (escape hatch), `:235,264` (offender 2).

**Why it fails.**
- **The one thing you must read half-asleep is 44 pt.** `Text(now, format: .hour().minute())` in
  `numeralLarge` (`:193`); the file's own comment (`:188-191`) admits `Theme.Typography` has nothing
  bigger. An alarm's clock should be the largest element on the screen.
- **Two rings, one hierarchy.** On the Steps and Focus variants the dismiss task is a `.large` (148 pt)
  `GoalRing` (`:271,290`) and the escape hatch below is *also* a `.large` 148 pt ring, now `danger`-red
  (`:412-417`). Two equal rings stacked = no primary. The safety valve should be findable, not equal.
- **The safety-critical control is at the bottom of a scroll.** Content estimate: 56 pad + 114 header +
  32 + ~230 card + 32 + 21 snooze + 32 + ~360 escape-hatch block + 56 ~ **930 pt** vs 852 pt: the hatch
  is partly below the fold on a ringing alarm (estimate).

**Fix direction.**
```
   WAKE UP                          eyebrow (phase tint)
   6:32                             numeralHero, 96 pt, text colour (do not animate/pulse it)
+----------------------------------+
|   [ dismiss ring/step/tag task ] |   the card is the hero; ring stays .large
+----------------------------------+
        Snooze - 1 left
============= pinned bottom bar (safeAreaInset) =============
  Can't dismiss?   ( ring .small 44, danger, "60s" )   [ ] I'm not home
```
- Escape hatch: pinned, compact (`.small` ring, single row), always visible, never scrolls. Keep the
  hold mechanics and the `accessibilityAction` exactly as they are.
- Header: `numeralHero`; drop the `headline` under it to one caption line.
- Keep the tint pulse (already reduced-motion gated). Do not add motion to the clock.
- Fix offender 2 at `:235,264`.

**Touches:** `AlarmRingingView.swift`, `Theme.swift` (S-1).

---

### 9. `SunriseAlarmSetupView` + `BedtimeGateSetupView` — a flagship feature configured in stock forms, and Save says nothing

**Where:** `SunriseAlarm/SunriseAlarmSetupView.swift:155-169` (Form + toolbar), `:211-219` (wake time),
`:223-271` (variant rows), `:289-359` (tag section), `:429-443` (`save()`); `BedtimeGateSetupView.swift:
46-97,120-134`.

**Why it fails.**
- **The two numbers the feature is about are compact `DatePicker` rows.** Wake time (`:213-217`) and
  bedtime (`BedtimeGate:49-53`) are one-line pickers at body size. Spec section 5.10 is "Bedtime Gate &
  Sunrise Alarm" (a marquee, starred feature); the setup screens should *show a night*, not a form.
- **Stock `Form`, no `scrollContentBackground(.hidden)`** -> pure black `#000` system grouped bg with
  system row fills. Pushing from `SettingsView` (which hides it and paints `#0A0A0B`) changes background
  colour between screens.
- **Four dismiss methods = four identical rows.** Icon, title, description, checkmark (`:242-263`); the
  selected state is an accent tint + checkmark; unselected state is nearly identical. It is a radio list
  the height of a screen for what should be a 2 x 2 chooser.
- **Save is silent.** Both `save()` methods set `isSaving = false` and return - no dismiss, no
  confirmation, no haptic (`:429-443`, `BedtimeGate:120-134`), and toolbar-only. A user cannot tell
  whether it saved, and leaving without tapping discards edits with no warning.
- With the Tag method selected the form is five `Section`s (wake time, method, tag list, how-it-works /
  troubleshooting disclosure groups, technology tier) of mostly caption text; NFC step badges are accent
  for decoration.

**Fix direction.**
- One shared "Sleep" header (both screens are companions): two large time tiles side by side -
  `Bed 10:30 PM` and `Wake 6:30 AM`, `numeralLarge`/`numeralHero`, each opening a sheet with a `.wheel`
  picker - and a derived caption between them ("8 h sleep window"). Wake tile in
  `Ring.sunriseAlarm`, bed tile in `Ring.sleepOnTime` (existing tokens).
- Dismiss method -> 2 x 2 `SelectableCard` grid (S-6): 28 pt icon, title, one-line description; selected
  = accent stroke + `accent@0.08` fill; the chosen method's config (steps stepper / tag list / squad
  picker) expands beneath.
- Replace toolbar Save with **autosave** on change (debounced 400 ms) plus a small "Saved" status line
  with `.sensoryFeedback(.success)`; or a pinned `PrimaryButton("Save alarm")` that dismisses. Never
  silent.
- S-4 scaffold for everything below; NFC steps collapse into one "How tag setup works" card.
- Fix offender 2 at `SunriseAlarmSetupView.swift:319`.

**Touches:** both files, S-4/S-6.

---

### 10. `ProgressView` (+ `TrophyCaseView`) — four identical cards, and the emotional metric doesn't lead

**Where:** `Progress/ProgressView.swift:118-139` (stack), `:143-160` (time reclaimed), `:174-195` +
`:324-348` (streak + grid), `:219-254` (trophy), `:258-293` (recap), `:351-374` (`BadgeTile`), `:229`;
`Trophy/TrophyCaseView.swift:119-162,183-238,262-363`; `RecapCard.swift:76`.

**Why it fails.**
- **Four cards, one weight.** `timeReclaimedCard`, `streakSection`, `badgesSection` and the recap are all
  `surface`, radius 20, padding 16, `headline` title. "Time Reclaimed" (spec 5.15: the lifetime payoff)
  is a 44 pt numeral with a 13 pt muted eyebrow in a plain card - the same object as the Trophy Case.
- **The streak grid swings between invisible and shouting.** Earned days are solid `accent` squares
  (`:340-343`) - the brand's scarcest colour, painted in bulk once a streak exists - while unearned days
  are `surface2` squares on a `surface` card (**1.08 : 1**), so a new user's grid is essentially
  invisible and a 28-day streak is a wall of acid green. No weekday header, no "today" marker, no legend.
  The `StreakPill` above it repeats the number the grid already implies.
- **The Trophy section is either empty or a sub-set.** With no badges it is a body-text paragraph
  (`:238-240`); with some it shows *only earned* tiles, while `TrophyCaseView` shows all six with locked
  states. Two implementations (`BadgeTile` here vs `TrophyTile` there) of the same tile, already drifting.
- **`chevron.right`** (`:229`) does not mirror in RTL (already flagged in `ui-stress-test-findings.md`
  2.4 for `TrophyCaseView`; missed here).
- **Recap rings overflow.** `RecapCard` uses `RingCluster(.small, .row)`; each cell is 64 pt wide + 24
  pt gaps -> 5 goals = 416 pt in a 329 pt card interior; more than 4 scrolls sideways inside a card.
- **`TrophyCaseView` header card** stacks a progress headline, a subtitle, a coin pill *and* a nested
  full-width "Cosmetics Shop" link in one card (`:119-162`): three jobs, no lead.

**Fix direction.**
```
Progress
+----------------------------------------------------+
|  TIME RECLAIMED                       [ flame 14 ]  |   hero card: radius .large, accent@0.12 -> clear
|  41h 20m            <- numeralHero                  |   gradient, 1 px stroke (S-2); pill: "+3h 10m this week"
+----------------------------------------------------+
  Streak   M T W T F S S grid  (today = outlined, freeze = water tint, earned = accent@0.9, gaps 3)
  Trophy case  [6 tiles, locked ones dimmed - the SAME TrophyTile]        >
  This week    RecapCard (rings .grid)                          [ Share ]
```
- Hero first; the other three are `surface` at radius 20 and visibly quieter. Move `StreakPill` into the
  hero.
- Streak grid: weekday header row, `today` ring, cell radius 4, gaps 3, `accent` only for *earned*, glow
  only on the current-streak head. Remove the duplicate pill.
- Trophy section: render the six milestone tiles (extract `TrophyTile` into Core/UI or make it
  `internal`), so the section is never a paragraph. `chevron.forward`.
- `RecapCard`: `.grid` layout when > 4 rings.
- `TrophyCaseView`: lead with the tile grid; coin balance in the nav bar trailing item; the shop link
  becomes a single row at the bottom.

**Touches:** `ProgressView.swift`, `TrophyCaseView.swift`, `RecapCard.swift`, `RingCluster.swift`.

---

## 3. Systemic causes — fix these once and half the offenders shrink

Everything below lives in `Theme.swift` and `Core/UI/Components` (neither is on the concurrent wave's
forbidden list). Spec section 15 is authoritative for tokens; amend it first.

**S-1 Type ramp too flat.** Add `Theme.Typography.numeralHero()` (72-96 pt, `.heavy`, `.rounded`,
`.monospacedDigit`) and `display` (34 pt bold rounded; replaces ad hoc `.system(size: 34/30/...)` at
`Screen1Hook.swift:40`, `PaywallView.swift:160`). Users: Today ring value, Fuel numbers, Progress hero,
Alarm clock, Wake-Up counters, Share hero, Celebration reward. Because fixed `size:` fonts don't scale
with Dynamic Type (see `ui-stress-test-findings.md` 1.2), wrap hero numerals in `@ScaledMetric` +
`.minimumScaleFactor(0.5)` from day one. In `UnlockCelebrationView` the reward ("2h 10m unlocked") is
currently the *smallest* text on the screen: 13 pt `captionEmphasized` inside `TimeBankBar`'s label
(`UnlockCelebrationView.swift:177-184` -> `TimeBankBar.swift:54-62`) while "Earned." is 44 pt. Make the
reward the hero (`numeralHero`, "2h 10m") and "Earned." the headline above it.

**S-2 No elevation system.** Surface vs background = 1.076 : 1; `Theme.Colors.hairline` is `surface2@0.8`,
i.e. also ~1.08 : 1 - it cannot draw an edge on `surface`. Propose: `Theme.Colors.stroke`
(`Color.white.opacity(0.08)`, derived like `hairline` was) and one Core/UI modifier
`.zanoCard(radius:tint:active:)`: `surface` fill + 1 px `stroke` + optional `tint.opacity(0.14)`
top-leading gradient + (when `active`) a 24 pt-radius `tint.opacity(0.22)` glow. Reduce Transparency /
Reduce Motion: drop glow and gradient, keep stroke. Adopt in `LockStatusCard`, `GhostProgressBanner`,
`GoalRow`, `RecapCard`, `PaywallCard`, `TrophyCaseView`, `ProgressView`, `LockStatusView`. This is the
single change that makes the app look designed instead of flat.

**S-3 `GoalRing`.** (a) `Size.hero` (200 pt, 18 pt line) with a size-scaled centre: `.text` in
`numeralHero` for hero, `numeralLarge` for `.large`, `numeralMedium` for `.medium`, `numeralSmall` for
`.small` (currently only small vs "everything else", `GoalRing.swift:173`). (b) Track = `color.opacity(0.18)`
not `surface2` (`:105`) so empty rings are visible and colour-coded (`surface2` on `background` is
1.16 : 1). (c) Optional leading-edge dot/glow for the filled arc, off under Reduce Motion.

**S-4 Dark form scaffold.** One `ZanoFormStyle`/`.zanoForm()` for every `List`/`Form` (Settings + 4
sub-screens + all sheets): `.scrollContentBackground(.hidden)`, `Theme.Colors.background.ignoresSafeArea()`,
`.listRowBackground(Theme.Colors.surface)`, a `captionEmphasized` uppercase muted section header,
consistent `listRowInsets`, `.tint(Theme.Colors.accent)`. Also a `ZanoScreenHeader` (eyebrow + title +
optional trailing) so Today/Fuel/Progress/Settings stop using three title treatments. Missing today at:
`GymSetupDetailView` (`SettingsView.swift:562-621`), `NFCTagSetupDetailView` (`:865-946`), `AddGymSheet`
(`:720-772`), `MapTagSheet` (`:1082-1155`), `LockSetupView`, `SunriseAlarmSetupView`,
`BedtimeGateSetupView`, `ManualAmountSheet`, `KitchenStapleAddSheet`.

**S-5 Button variants.** `PrimaryButton` is the only button. Begin-lock, emergency-unlock, buy, share,
continue and "log 20 g" all get the same accent fill (and `.holdToCommit` paints acid-green - the "earned"
colour - while you *bail out* of a lock, `LockStatusView.swift:277-283`). Disabled = 50 % opacity, which
reads as a dead button (Today shows five). Six hand-rolled secondaries exist because none does
(`shareLabel`/`shareFailedLabel` x2, `FuelQuickAddChip`, plain text links). Add `tint`/`role`
(`.danger` for emergency), `Style.secondary` (stroke + `text`), `Style.chip` (44 pt min height), and give
disabled a clear "unavailable" treatment plus, where relevant, an explanatory caption.

**S-6 `SelectableCard`.** Screens 3, 7 and 8 are three copies of the same option-row code
(`Screen3MainGoal.swift:89-117`, `Screen7FallOff.swift:46-74`, `Screen8CoachVoice.swift:50-84`), and
Settings' coach-voice picker, Sunrise variant rows and Cosmetics category chips re-invent it. One Core/UI
`SelectableCard(icon:title:subtitle:isSelected:)` (accent stroke 2 pt + `accent@0.08` fill selected;
`stroke` unselected; optional leading SF Symbol; trailing radio dot). Give each option in Screens 3/7 a
leading symbol.

**S-7 `GoalRow` without a status glyph.** `GoalRow` always renders a trailing circle/dotted/check
(`GoalRow.swift:167-190`), so it means "checkbox" - correct on Lock/Today, wrong for a plan preview
(Screen 10, `PaywallView:210`), an *option* (Fuel gap planner), a *suggestion* (Quick Repeat). Add
`status: .none` / `trailing: .chevron`. Also the row is 56 pt without `progress` and ~68 pt with (ring
44 + padding) so adjacent rows in one list jump height.

**S-8 Accent discipline.** Spec: "ONE accent only... earned/unlock". `AccentColor` is also set to
`#B8FF3C` (`Assets.xcassets/AccentColor.colorset`), so every unstyled `Button`/`NavigationLink`/`Toggle`/
`DatePicker` in the app is acid green too. Decorative uses to demote: Paywall benefit icons
(`PaywallView:178-181`), Screen 1 lock (`:34-36`), Screen 4 apps icon (`:69-70`), Screen 12 bell
(`:35-37`), Cosmetics *buy* buttons (5 stacked full-width accent buttons, `CosmeticsShopView:326-331`),
Settings link rows (Manage subscription / Restore / Privacy), NFC step badges, Sunrise variant icon tint,
Fuel "+ Add" chip. Rule of thumb for the fix wave: accent = CTA fill, *earned/complete*, active ring,
selected stroke. Everything decorative -> `text` on `surface2`.

**Copy leaks noticed in passing** (not composition; fix waves should route through `Copy.<area>`):
`TodayView:194,468`, `LockStatusView:141,250,345` ("min banked", "min available", "Done", "Not yet"),
Fuel unit suffixes and `"g protein"` (`:367,384,402,414,974`).

---

## 4. Scorecard — every file under `Features/**`

F = focal point, S = custom vs stock, D = density, A = same app. Grade is composition only.
`unreachable` = no in-app presenter exists today.

| File | F | S | D | A | Grade | One-line verdict |
|---|---|---|---|---|---|---|
| `Today/TodayView` | none: 3 equal rings | custom | medium | reference | **D+** | Ring row overflows; CTA dead in 5/8 states; twin cards. Offender 1 |
| `Lock/LockStatusView` | none | custom | too many low-info cards | yes | **C-** | Opens with the same card you tapped; 3-line `timeContextCard`; hand-rolled goal rows drift from `GoalRow`; emergency in accent. See 5.1 |
| `Fuel/FuelView` | none | custom + stock sheets | dense below, flat above | mostly | **C-** | Offender 3 |
| `Progress/ProgressView` | weak | custom | ok | yes | **C** | Offender 10 |
| `Settings/SettingsView` (+4 sub-screens) | n/a | stock `List`/`Form` | sparse | no | **C-** | See 5.2 |
| `LockSetup/LockSetupView` | none | stock, off-token | sparse | no | **F** | Offender 7; unreachable |
| `LockSetup/AppPickerView` | none | stock | sparse | no | **D** | A `LabeledContent` row for the core choice |
| `LockSetup/AlwaysAllowedWarningView` | n/a | custom + stroke | good | yes | **B** | The template for how cards should look; use it |
| `Share/WeeklyRecapShareView` | card | custom | ok | yes | **C** | Duplicate dismiss; unreachable. Offender 6 |
| `Share/LockedOutMomentView` | card | custom | ok | yes | **C-** | Text-only card; unreachable. Offender 6 |
| `Core UI/ShareCard` (composed by both) | none | custom | empty middle | yes | **D** | 22 pt type on a 1080 pt canvas. Offender 6 |
| `Trophy/TrophyCaseView` | tiles | custom | ok | yes | **C+** | Good tile + earn moment; header card has 3 jobs |
| `Trophy/CosmeticsShopView` | none | custom | ok | partly | **D+** | See 5.3 |
| `SunriseAlarm/SunriseAlarmSetupView` | none | stock `Form` | long | no | **D** | Offender 9 |
| `SunriseAlarm/BedtimeGateSetupView` | none | stock `Form` | sparse | no | **D** | Offender 9 |
| `SunriseAlarm/AlarmRingingView` | clock (too small) | custom | dense, scrolls | yes | **C-** | Offender 8 |
| `Celebration/UnlockCelebrationView` | "Earned." 44 pt | custom | sparse | yes | **C+** | Right idea, timid scale, reward is 13 pt (S-1) |
| `Onboarding/OnboardingContainerView` | n/a | custom | ok | own dialect | **B-** | Clean scaffold; 4 pt progress bar; add reduce-motion gate on the screen transition |
| `Onboarding/Screen1Hook` | icon | custom | sparse | own | **C-** | See 5.4 |
| `Onboarding/Screen2SocialProof` | none | custom | sparse | own | **D+** | Three 17 pt lines, no attribution. See 5.4 |
| `Onboarding/Screen3MainGoal` | none | custom | ok | own | **C** | Option card copy #1 (S-6) |
| `Onboarding/Screen4AppSelection` | none | custom | sparse | own | **C-** | One row; no preview of chosen apps; `chevron.right` (`:76`) |
| `Onboarding/Screen5PhoneTime` | 44 pt value | custom | ok | own | **C** | Default slider; value should be hero (S-1) |
| `Onboarding/Screen6Workouts` | none | custom + default `Stepper` | ok | own | **C-** | System steppers in cards; 28 pt values |
| `Onboarding/Screen7FallOff` | none | custom | ok | own | **C** | Option card copy #2 |
| `Onboarding/Screen8CoachVoice` | quotes | custom | good | own | **C+** | Best of the three option screens (quote in italics); copy #3 |
| `Onboarding/Screen9WakeUp` | inverted | custom | sparse | own | **C-** | Offender 4 |
| `Onboarding/Screen10PlanReveal` | none | custom | list dump | own | **D+** | Offender 4 |
| `Onboarding/Screen11Commitment` | none | custom | sparse | own | **D** | Offender 4 |
| `Onboarding/Screen12PermissionPriming` | icon | custom | sparse | own | **C** | Generic; show a mock notification instead of a bell |
| `Onboarding/PaywallView` | headline | custom | long | own | **C-** | Offender 5 |
| `Onboarding/Screen14FirstWin` | ring (running) | custom | sparse | own | **C** | Second celebration language; 160 x 6 pt emergency bar. Offender 4 |
| `Onboarding/Screen13Paywall` | - | - | - | - | n/a | Dead code; not wired |
| `Onboarding/OnboardingFlowState` | - | - | - | - | n/a | Model, not a screen |

---

## 5. Next tier — specific, smaller

**5.1 `LockStatusView`** (`Lock/LockStatusView.swift:54-76,148-179,213-238,242-261,273-290`)
- It opens with the identical `LockStatusCard` you just tapped on Today. Replace with a Lock-specific
  hero: the *time bank* (Earn mode) or the *countdown to next lock* as a `numeralHero`, with the state
  band (S-2) as a slim header.
- `timeContextCard` = a full card for "Locked since 7:02 AM / Triggered manually / Next lock 10:30 PM" -
  three low-information lines. Make it a single `caption` row under the hero.
- `goalRow` (`:213-238`) hand-rolls what `GoalRow` does with different padding (`sm` vs `md`/`sm`
  horizontal). Use `GoalRow`; give required goals rings with value text (S-3).
- Time Bank: a 10 pt bar, a 17 pt "N min available" and a footnote. The bank is Earn Mode's hero - use a
  `numeralHero` minutes value over a taller (14 pt) bar.
- Emergency button: `.holdToCommit` in accent with a warning-triangle glyph. Emergency should read as
  danger (S-5) and sit visually apart, not as another green CTA.

**5.2 `SettingsView`** (`Settings/SettingsView.swift:158-191,195-224,355-389,544-946`)
- The first thing in Settings is four coach-voice radio rows (~4 x 60 pt) - a set-once preference gets
  top billing above everything, and the Pro upsell is buried mid-list as a row. Lead with a profile/plan
  card (plan tier, streak, "Upgrade" CTA); turn coach voice into a 2 x 2 `SelectableCard` grid of voice
  cards with their sample line (the delight moment onboarding already builds).
- `Label(...)` rows have bare symbols; use 28 pt rounded-square icon tiles tinted by the existing
  `Ring.*` colours so the list has rhythm and identity.
- `alwaysAllowedSection` correctly reuses the warning card - promote it to the top when it applies.
- Sub-screens are stock lists (S-4); NFC detail is three sections of caption text (explainer + steps +
  troubleshooting): lead with a big "Scan a tag" card, collapse the rest into "How it works". `AddGymSheet`
  is a name field, a `Stepper` and a "use current location" text button - show a `Map` snapshot with the
  radius circle after locating.

**5.3 `CosmeticsShopView`** (`Trophy/CosmeticsShopView.swift:195-213,267-334,380-419`)
- **It sells cosmetics without showing them.** "Ice Mint theme" is a 44 pt tile holding a `snowflake`
  glyph; "Glow Trail ring" is `circle.dotted`. Each item needs a live preview: theme = a 3-swatch strip /
  mini ring in that palette; ring style = a rendered `GoalRing` at 70 %; shield background = a
  thumbnail; voice pack = its sample quote.
- Five full-width cards, each with a full-width accent `PrimaryButton` = five acid-green slabs. Use a
  2-column grid of preview tiles, price as a small coin pill, and one quiet outlined "Equipped"
  state; only the *selected* tile shows an accent CTA.
- `VStack` root has `.background(Theme.Colors.background)` without `ignoresSafeArea` (`:100`) - the
  bottom safe area falls back to the system background.

**5.4 Onboarding 1-8, 12** 
- **1 Hook (`Screen1Hook.swift:27-54`):** spec says "Full-bleed". It is a 64 pt SF Symbol, a 34 pt
  headline and a button on flat black. Give it a hero: a large ring that closes (or a lock glyph) with an
  accent radial glow (S-2) behind it, headline at `display`+, and a slow single-run entrance (no loop;
  reduced motion = static).
- **2 Social proof (`Screen2SocialProof.swift:33-44`):** three 17 pt headline lines in a 140 pt `TabView`
  with dots. No names, stars, rating or count - it is social proof with no proof. Lead with a stat in
  `numeralLarge` ("12,000 locks earned this week" - once real), quote in `headline`, attribution line in
  `caption`.
- **3/7/8:** S-6.
- **4 App selection (`:65-91`):** after picking, show the chosen apps' real icons (max 6 + "+N") inside the
  row; `chevron.forward`.
- **5 Phone time (`:22-40`):** `numeralHero` value in accent; custom slider track; add the live
  "= N days a year" caption (already computed by `estimatedDaysPerYearOnPhone`) if the spec's "reveal on 9"
  allows.
- **6 Workouts (`:53-67`):** replace `Stepper` with large -/+ round buttons (44 pt) flanking a
  `numeralLarge` count.
- **12 Permission (`:31-38`):** replace the generic bell-in-a-circle with a rendered mock notification
  banner (app icon + a coach-voice line in the user's chosen voice).
- **Selection animations** in 2/3/5/7/8 (`.animation(Theme.Motion.springStandard, ...)`) have no
  `accessibilityReduceMotion` gate (the prior wave's rule); add it when these files are next touched.

**5.5 `UnlockCelebrationView`** (`Celebration/UnlockCelebrationView.swift:121-184`) - S-1 applied; add the
streak (+1) beat; give the burst an origin (ring closing to a check) instead of a 280 x 280 box behind
text.

**5.6 `ShieldPreview`** (Core UI; only used by `PreviewCatalog`) - the most-seen screen in the product
(every blocked-app attempt) is a 96 pt muted circle + 22 pt title. When the shield extension is wired,
add the goal ring / "1 goal left" state and a streak chip; `danger` badge stays. It is unrendered in-app
today, so this is design-spec only.

---

## 6. Reference patterns (working knowledge, not fetched — verify visually)

| ZANO screen | Look at | What to take |
|---|---|---|
| Today, rings | Apple Fitness (Activity summary) | Value numerals in the ring's own colour; ring track = the ring colour at ~20-30 %; leading-edge cap that glows; summary card first |
| Today, hero state | Whoop (Recovery ring), Oura (Readiness) | **One** giant number at centre; secondary metrics as smaller rows beneath; the rest of the screen is quiet |
| Lock / Alarm | Apple Clock alarm editor + Sleep schedule dial | Time as the largest thing on screen; wheel picker in a sheet; derived "sleep window" caption |
| Card depth (all) | Linear, Vercel dark UI, Apple Wallet | 1 px stroke at ~6-8 % white + a faint top-edge gradient; glow only on *active* elements |
| Share card | Strava activity stickers, Spotify Wrapped | Enormous single stat, tiny supporting detail, brand mark anchored bottom, designed at 360 x 640 then exported at 3x |
| Celebration | Duolingo streak screens, Apple Fitness award | One giant numeral + a single-colour burst; reward number bigger than the headline |
| Paywall | RevenueCat paywall templates, Robinhood Gold | Pinned CTA bar; selected plan larger; price is the hero of its card |
| Category peers | Opal, ScreenZen, one sec | Calm dark canvas, one action per state; shield = one message + one action |
| Onboarding | Finch, Duolingo, Cal AI | Staged reveals, mascot/hero visual per step, big single-choice cards with leading icons |

---

## 7. Suggested fix-wave decomposition (keeps file ownership disjoint)

Do **not** touch: `ZANOApp.swift`, `ContentView.swift`, `AppRouter.swift`, `LockEngineManager.swift`,
`LockSetManager.swift`, `project.yml`, `Assets.xcassets/**`, `ZANOUITests/**`, `Core/.../Watch/**`,
`Watch/ZANOWatch/**` (concurrent wave). Copy stays under `Copy.<area>`; keep every existing
`accessibilityReduceMotion` gate; new glow/gradient/stagger must be static or a plain fade under Reduce
Motion; new hero numerals use `@ScaledMetric` + `minimumScaleFactor`.

1. **Wave A - design system** (do first; everything else depends on it): `Theme.swift` (+ spec section
   15 amendment: `numeralHero`, `display`, `stroke`), `GoalRing` (`.hero`, scaled centre, coloured track),
   `PrimaryButton` variants, `.zanoCard`, `.zanoForm`, `ZanoScreenHeader`, `SelectableCard`, `GoalRow`
   `status: .none`, `PaywallCard` sizes. Plus the offender-2 spinner qualification (7 one-liners; no
   dependency, can ship immediately).
2. **Wave B - Today / Lock / Celebration:** offenders 1 and 5.1, 5.5. Needs an injected `onOpenFuel`
   closure for the `openFuel` state (ContentView owner wires it).
3. **Wave C - Fuel:** offender 3.
4. **Wave D - Progress / Trophy / Cosmetics / Share:** offenders 6 and 10, 5.3.
5. **Wave E - Settings / LockSetup / Sunrise / Bedtime:** offenders 7 and 9, 5.2 (+ a Settings row to
   reach `LockSetupView`).
6. **Wave F - Onboarding / Paywall / Alarm:** offenders 4, 5, 8, 5.4.

---

## 8. Not verified

- Nothing was rendered. Every size/overflow/fold claim is arithmetic on the source at 393 x 852 pt and
  default Dynamic Type; measure before trusting the ~700 pt (paywall) and ~930 pt (alarm) estimates.
- The `ProgressView` shadowing claim (offender 2) follows from Swift's module-before-import lookup and two
  in-repo comments, but has not been compiled.
- `Label(applicationToken)` (ManagedSettingsUI) for app icons, and any SF Symbol names proposed, are
  unchecked against the SDK.
- Contrast ratios (surface 1.076, surface2-on-background 1.16, iOS grouped 1.234, muted 6.07, accent 16.4,
  danger 5.81) were computed from the token hexes with the WCAG relative-luminance formula, not measured
  on a device (real displays, True Tone and OLED black crush change perceived contrast; low-contrast
  dark-on-darker cards tend to look *worse* on OLED, not better).
- Section 6 patterns are from memory of shipping apps; treat them as prompts for exploration, not
  specifications.
