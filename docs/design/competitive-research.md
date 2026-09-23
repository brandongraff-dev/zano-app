# Competitive UI/UX research for ZANO

**Date:** 2026-09-23. **Status:** Research only. No Swift file was edited to produce this document.
**Scope:** habit and discipline apps (Streaks, Opal, Brick/Foqos, one sec, ScreenZen), dark-mode
fitness apps (Fitbod, WHOOP, Strava), streak/celebration craft (Duolingo), and AI meal-photo apps
(Cal AI, MyFitnessPal's 2026 redesign). Filtered against `docs/spec.md` §15/§16 and the real
`Theme.swift` / Core UI components as they exist on disk today.

Read section 0 first. Sections 1 to 3 are the evidence and the reasoning. Section 6 lists what this
pass could not establish and what to verify on a Mac.

---

## 0. Executive summary

**The spec's direction (§15/§16) is right. The code as written does not yet execute it.** Every
best-in-class app in this genre wins on the same three things: one dominant number per screen, a
dark surface where cards are actually visible, and celebration reserved for moments that are rare.
ZANO's tokens are disciplined, but reading the real files (not rendering them, see limits below)
shows five structural problems that would make the first launch look flat and generic:

1. **Today's ring row overflows every iPhone.** Three `.large` rings need 500pt of width; the
   usable width is 343 to 408pt. The third ring is cut off behind a horizontal scroll (arithmetic in 2.3).
2. **The most important number in the app is the smallest text on the screen.** Protein grams
   ("72/150g") is 13pt muted caption under an icon-only ring. Competitors put the number inside
   the ring or make it the hero.
3. **There is no typographic hero anywhere.** The largest style in `Theme.Typography` is
   `numeralLarge()` at 44pt, and Today's biggest text is a 22pt title. Competitors use roughly
   72pt for the primary metric (WHOOP) and a giant number in the streak moment (Duolingo).
4. **Cards, dividers and ring tracks are effectively invisible.** `surface` on `background` is
   1.08:1 and `hairline` on `surface` is 1.06:1 (computed, section 3.11). "Crisp 1px hairline
   dividers" from the style paragraph cannot be crisp at that contrast.
5. **The shield is the app's most-seen screen and Apple gives no layout control over it.** It is a
   fixed icon, title, subtitle, and two buttons. Layout research is irrelevant for it; copy
   hierarchy, the icon image, colors and blur are the only levers (section 3.3).

### Ranked punch list

| # | Change | Why (evidence) | Where | Effort | Needs spec decision |
|---|---|---|---|---|---|
| 1 | Fit the three Today rings to width (equal columns, about 104 to 110pt on 375 to 393pt phones) and put the number inside the ring | 3.1, 2.3 arithmetic; WHOOP three dials across, Cal AI number in ring | `GoalRing`, `RingCluster`, `TodayView`, `FuelView` | M | No |
| 2 | Add a display numeral tier (about 72pt) and use it for streak moments, "Earned.", the time bank, protein hero, wake-up counter | 3.1, 3.2, 3.4; WHOOP about 72pt hero | `Theme.Typography`, then screens | S | Yes (amend §15 type line) |
| 3 | Make surfaces legible: derive `hairline` and ring track from `text` opacity (0.10 to 0.14); optional top-lit 1px stroke on cards | 3.11 contrast table | `Theme.Colors`, `GoalRing`, `LockStatusCard` | S | Soft (§15 says tokens are a "starting point") |
| 4 | Shield copy and icon hierarchy: title six words or fewer, numbers in subtitle, primary button = the goal path, rendered progress icon | 3.3; one sec RCT, Opal 7s countdown | `Extensions/ZANOShieldConfig`, `Copy.shield` | S | Product owner (button A/B) |
| 5 | Remove the full-width `.ultraThinMaterial` bottom bar on Today; make the primary action an inline hero below the rings | 3.12; iOS 26 floating tab bar | `TodayView` | S | No |
| 6 | Tier celebrations: routine unlock stays at or under 1.2s; add a distinct milestone tier at 7/30/100/365 with a week row and share card | 3.2, 3.4; Duolingo | `UnlockCelebrationView`, new `WeekStreakRow` | M | Yes (§8 rule 4 and Theme 1.2s cap) |
| 7 | Rebuild Screen13Paywall hierarchy: plan recap, three benefits, selection-matched CTA, dated trial timeline, keep the free path | 3.6 | `Screen13Paywall`, reuse `PaywallView` pieces | M | No (free path already in §21) |
| 8 | Onboarding: live consequence on the phone-time slider; a 2 to 3s "building your plan" beat; test notification priming after the paywall | 3.5 | `Screen5PhoneTime`, `Screen10PlanReveal`, order in container | M | Order change needs approval |
| 9 | Fuel photo result card: protein-first hero, source photo, "estimated" chip, portion stepper, collapsible ingredients | 3.7 | `FuelView` photo flow | M | No |
| 10 | Share: add a transparent stats-sticker export beside the 9:16 card | 3.8; Strava stickers | `ShareCard`, `WeeklyRecapShareView` | M | No |
| 11 | Color semantics: fewer hues per screen; locked state desaturated rather than red on routine surfaces | 3.11; WHOOP and Duolingo | `Theme.Colors.Ring` usage, `LockStatusCard` | S | Yes (§15 danger = locked) |
| 12 | Empty state: unconfigured ring becomes a dashed outline with a plus and one CTA | 3.10 | `TodayView.ringItem`, `GoalRing` | S | No |

---

## 1. Method, limits and confidence

**What was done:** roughly 70 web searches and page fetches across teardown sites (ScreensDesign, Mobbin,
Page Flows, 60fps.design, App Fuel), company blogs, peer-reviewed research, vendor paywall data,
and press coverage. Then the real ZANO source files were read and the numbers below were computed
from them.

**Hard limits, stated plainly:**

- `WebFetch` returns a model-written summary of a page, not the page. It cannot read images.
  Almost no source publishes pixel measurements of competitor screens, so "how many points is
  Duolingo's streak number" is mostly **not knowable from text**. Where a number exists it is
  cited; where it does not, this document says "not published" rather than guessing.
- Mobbin, PNAS, Apple HIG pages, several Medium posts and Indie Hackers returned 403/410 or empty
  bodies. Facts that came only from a search-result summary (not a page I read) are marked **(search
  summary)**.
- Nothing about ZANO was rendered. Findings about ZANO's own screens come from reading Swift
  source plus arithmetic. They are predictions about layout, not observations.

**Confidence tags** used on every claim:

- **[P]** primary: peer-reviewed paper, the company's own post, Apple documentation.
- **[T]** independent teardown or journalism (ScreensDesign, MacStories, 60fps.design, etc.).
- **[V]** vendor or aggregator blog. Useful, possibly promotional, numbers unverified.
- **[C]** third-party reconstruction (someone else's CSS re-creation or clone spec). Low confidence.
- **[D]** derived by me from ZANO source or arithmetic. Checkable, but not observed on a device.

---

## 2. The ZANO filter

### 2.1 What the spec already gets right (research agrees)

| Spec decision | Research support |
|---|---|
| Near-black, not pure black, base (`#0A0A0B`) | Dark-mode fitness roundups converge on near-black bases [V]. WHOOP is "nearly all black" with color reserved for data [V]. |
| ONE accent, semantic ring colors | WHOOP: "no arbitrary accent colors", three-hue vocabulary learned once [V]. |
| Never Miss Twice, freezes, Plan B | Duolingo freezes: 4% more likely to return a week later, 5% less likely to lose the streak (cited in UX Magazine [V]); freezes granted at milestones "phrased as a refill, not a reward" [V]. |
| Max 2 proactive pushes per day (§8 rule 7) | Duolingo hard-caps save notifications at two per day [V, Digia]. |
| Never sell streak restores (§21) | Duolingo's "Earn Back" restores by completing lessons in a window, not by paying [V]. |
| 14-screen onboarding | Opal about 11 to 12 [T], Fitbod 14 [T], Duolingo 7 (mobile) to about 12 [V], Cal AI 32 [T]. Fourteen is mid-pack. |
| Free path on the paywall | Strava and Cal AI both use the "soft commitment" pattern: trial CTA, "cancel anytime", timeline [V, Superwall]. |
| Hold-to-commit friction | one sec's finding is that friction plus a real choice works (3.3). |

### 2.2 Constraints that reject popular competitor patterns

These are things the research surfaced that ZANO must **not** copy:

- **Calorie-budget dashboards** (Cal AI's "860 of 2,200 kcal", MyFitnessPal's "goal minus food plus
  exercise equals remaining"). ZANO goals are additive only (CLAUDE.md, spec §1/§24). The Fuel
  ring must count **up** toward protein grams ("72 / 150 g"), never present a "remaining budget".
- **"Now or never" discount screens with countdown timers** (Superwall pattern 5: Captions, Finch,
  YAZIO [V]) and the post-close "one-time gift" offer. Conflicts with §21 "no dark patterns" and §8.9 "no shame".
- **Confirmshaming and escalating guilt** (Duolingo's "unhinged"/"desperate" mascot states [V]).
  ZANO's copy rule is "slipped", then the next smallest step. Borrow the *mechanics* (state
  changes through the day), not the tone.
- **Custom shield layouts.** The real shield is `ShieldConfiguration` (3.3).
- **Hard paywall.** RevenueCat's 2026 data (search summary) reports hard paywalls converting about
  5x freemium (10.7% vs 2.1%) with near-identical one-year retention. That is a product-owner
  decision against §21's free tier, not a design finding. Flagged, not recommended.
- **A mascot.** Duolingo (Duo), Opal (the rock/gem), one sec (the flower) all have one. ZANO does
  not, and §5.13's coach voice is text. If the app needs a character, the padlock glyph plus the
  acid-green ring is the asset to develop. Do not bolt on an illustration.

### 2.3 What is actually on disk (verified by reading source; **[D]**, not rendered)

| Fact | Source |
|---|---|
| Today renders `RingCluster(items:, ringSize: .large, layout: .row)`. `.large` is 148pt diameter, 14pt stroke. `.row` is a horizontal `ScrollView`. Cells are 148pt wide, spaced `Theme.Spacing.lg` (24), plus 4pt padding each side. **Total = 3 x 148 + 2 x 24 + 8 = 500pt.** Usable width inside Today's `.padding(Theme.Spacing.md)` is 343 (375pt phones), 361 (393), 370 (402), 398 (430), 408 (440). Every current iPhone scrolls; the third ring is clipped. Fuel repeats the same call. | `TodayView.swift:201-203`, `GoalRing.swift:36-50`, `RingCluster.swift:98-105,164`, `FuelView.swift:360` |
| Ring centers are an SF Symbol icon (about 50pt at 148pt). The numbers live below the ring: title 13pt semibold `text`, value 13pt regular `muted`. | `TodayView.swift:218-220`, `RingCluster.swift:153-162` |
| Ring track is `surface2`, drawn directly on `background` (no card behind the rings on Today). | `GoalRing.swift:105`, `TodayView.swift:201` |
| An unconfigured goal renders progress 0 in `muted`, so you see only the `surface2` track plus a "Not set" caption. | `TodayView.swift:224-227` |
| Type hierarchy on Today: 22pt title, 17pt streak numeral, 17pt lock-card headline, 13pt ring labels. Largest text is 22pt. The 44pt `numeralLarge()` is not used on Today. | `Theme.swift:151-171`, `TodayView.swift:163-175`, `LockStatusCard.swift:81` |
| Bottom action: `PrimaryButton` inside `.safeAreaInset(edge: .bottom)` on an `.ultraThinMaterial` bar. | `TodayView.swift:105-111` |
| `hairline` = `surface2` at 0.8 opacity. | `Theme.swift:54` |
| Onboarding step 13 (`Screen13Paywall`) is: headline, plan cards, trial caption, CTA, "continue free", disclaimer. No benefit rows, no plan recap, no trial timeline, no restore button in that file. The spec-P5 layout (three benefit rows, "your plan", restore) exists separately in `PaywallView`. Two paywalls with diverging structure. | `Screen13Paywall.swift:58-102`, `PaywallView.swift:116,167-171` |
| Unlock celebration: 280pt burst frame, headline "Earned." in `numeralLarge()` (44pt). | `UnlockCelebrationView.swift:126-127,163-164` |
| Deployment target is iOS 17.0. | `project.yml:19` |

---

## 3. Findings by surface

Format: **Evidence** (with tags), **Implication** for ZANO, **Do this** (using real token names;
anything marked PROPOSED does not exist in `Theme` yet and needs a §15 note first).

### 3.1 Today: hierarchy, negative space, ring composition

**Evidence**

- WHOOP's overview shows three numbers only (Recovery, Strain, Sleep) and nothing else above the
  fold; trends and raw graphs are two deliberate taps away, "each tile is a doorway, not a
  destination" [V, 925 Studios]. The Recovery score renders at "roughly 72pt equivalent, readable
  from arm's length" with supporting text kept small [V]. WHOOP's redesigned home screen puts "three
  separate dials" across the top, each with its own deep-dive page [search summary of WHOOP's own
  "All-New WHOOP Home Screen" post, which returned 403 when fetched].
- Opal's redesigned home: three numbers at top (screen time, Focus Score %, pickups), then one
  hourly bar chart (green/red segments, scrubbable), then a scrolling breakdown. The stated reason
  for the redesign was that the old design "was too complex and hard to read" [P, Opal blog].
- Streaks: the whole product is up to six circles with an icon in each, completion by long press,
  a ring around the icon showing progress; extra detail lives on the "back" of the card [T, MacStories; Apple App Store story, P].
  Apple's editorial calls habits "a big button" [P].
- Cal AI home: a calorie ring with the number, three macro bars, two small tiles, a week strip,
  the day's meals; secondary metrics (fiber, sodium) sit behind a horizontal swipe [T, ScreensDesign].
  Cal AI is described as "dark-first, generous spacing, typography tuned for quick scanning" [search summary].
- MyFitnessPal's April 2026 "Today" redesign is the cautionary tale. Users reported more taps to
  log, the diary "buried behind a View All button", per-meal macros harder to find, and a diary
  "converted to a list of gigantic, space-consuming cards" [T, PiunikaWeb]. A search summary of
  MWM attributes a rating fall from 3.24 to 1.54 stars to the release; I could not fetch that page
  (HTTP 410), so treat the exact figure as unverified. The company said the change is "here to stay" [T].

**Implication.** The pattern is: one dominant element, one or two supporting tiers, detail one tap
away, and list rows stay compact. Big cards are for the hero only. MFP shows what happens when
every row gets hero treatment. ZANO's Today has the right number of elements (title and streak,
state card, rings, primary action, ghost banner). Its problem is scale and weight: everything is
17 to 22pt on similar surfaces, so nothing dominates, and the key number is 13pt grey.

**Do this**

1. **Number inside the ring.** Change the `GoalRing` center from icon-only to the value that
   matters: "72" in `Theme.Typography.numeralMedium()` (28pt) with the unit ("g", "min") as a
   `caption` line beneath the number. Move the icon to the label row beside the title. On a
   104pt ring the inner diameter is about 84pt and a three-digit 28pt rounded numeral is about 50pt
   wide, so it fits. This mirrors WHOOP and Cal AI and fixes "smallest text = most important number".
2. **Fit three rings to the width.** For exactly three items, lay out three equal columns with
   diameter `(availableWidth - 2 x gap) / 3`. At 16pt gaps that is 103.7pt (375), 109.7pt (393),
   122pt (430). Stroke scales to about 0.1 x diameter (existing ratios: 9/88 and 14/148), so
   10 to 11pt. Add a fit-to-width size rather than another fixed case in `GoalRing.Size`, or use
   `ViewThatFits`. Keep `.row` scrolling only for four or more items.
3. **Give Today one typographic hero.** Candidate: the state line ("2 goals left" or "Unlocked") as
   display type (PROPOSED `numeralHero()`, about 56 to 72pt, `.rounded`, bold, monospaced digits),
   replacing the 17pt headline as the loudest thing on screen. Keep the 22pt title small and the
   streak in chrome. Target a hero-to-supporting ratio of at least 3:1 (WHOOP 72pt against about
   13pt captions). Today's current ratio is 22:13, about 1.7:1, which reads flat.
4. **Above-the-fold budget: five elements, three type sizes.** Chrome (title, streak), hero state,
   rings, primary action, and nothing else visible at first paint. The ghost banner is already
   below. Do not add a sixth.
5. **Do not put full-size cards on list rows.** `GoalRow` should stay a compact row (about 56 to
   64pt). This is the MFP lesson.

### 3.2 Streak: size, placement, states, milestones

**Evidence**

- **Placement.** The sources I could read say only that Duolingo's streak sits in a "prominent
  position with a fire icon" [V, Apptitude]; the small flame-plus-number in the top bar is
  widely observed but I could not confirm its size from text. The number becomes the hero in the
  post-lesson streak screen and the share card [T].
  ZANO's `StreakPill` (13pt symbol, 17pt `numeralSmall()` in a `surface2` capsule) is correctly
  chrome-scale. The gap is the missing hero moment.
- **The streak moment, in order** (Duolingo 2-day and 126-day animations, [T, 60fps.design]):
  (1) desaturated grey flame with the old number, (2) flame scales up and bursts into orange and
  yellow with square particle sparks while the number scales down and is replaced by the new number
  (a vertical ticker roll), (3) the "day streak" label slides up, (4) a week row slides up and
  populates with checkmarks with a line drawing across completed days, (5) a warning/notice line,
  (6) a single prominent button slides up last. Five elements plus one button. The number, not the
  label, is the hero. Exact point sizes and durations are **not published**.
- **Week row.** Completed days are checkmarks; freeze-saved days are blue snowflakes; a "Perfect
  Streak" week collapses seven icons into one continuous bar [V, Deconstructor of Fun]. A
  "yellow halo wraps the flame" at Perfect Streak milestones [V].
- **Milestones only.** Full-screen custom animations are reserved for 7, 30, 100 and 365; other days get
  the counter tick-up [V]. Duolingo's own post confirms the phoenix redesign ("treat milestones
  like power-ups") but publishes **no** retention number. The often-quoted "+1.7% day-7
  retention" appears only in Deconstructor of Fun [V]. Treat it as unverified.
- **Share card.** Milestone share cards reportedly drove a "5 to 10x increase in organic sharing
  and over 6 million daily streak shares" [V, Deconstructor of Fun; unverified]. The share sheet is
  a bottom sheet with a spring, the backdrop dims, and a grid of destinations [T, 60fps.design].
- **States.** Active flame is orange; broken is grey [V]. Freeze states are blue snowflakes.
  Duolingo's home-screen widget shifts the mascot's expression through the day and, when the
  streak is at risk, may deep-link into the repair flow (search summary of a Medium widget analysis, [V]).
- **Copy tone.** "You've completed 47 of the last 50 days" beats "You broke your streak" [V, UX
  Magazine], which is exactly §8.9. Avoid "Are you really going to give up now?"
- **Third-party CSS reconstruction [C]** (blakecrosley.com, not Duolingo's own): idle flame 2s
  ease-in-out at plus/minus 2 degrees and 1.05x scale; at-risk flame 0.8s cycle, up to 1.1x. Use
  only as a starting range for the "at risk" idea, never as a spec.

**Implication.** ZANO's chrome pill is right. What is missing is (a) a display-scale number for
the moment it matters, (b) the week row as a reusable component, and (c) a two-tier celebration
model so 7/30/100 feel rare. ZANO already uses the water hue for the frozen state
(`StreakPill.swift:56`), which matches Duolingo's blue snowflake.

**Do this**

1. Add PROPOSED `Theme.Typography.numeralHero()` (about 72pt) and use it for the streak number on
   the milestone screen and Progress header. Keep `numeralLarge()` (44pt) for secondary big values.
2. Build a `WeekStreakRow` in Core/UI: seven day marks; completed = accent check, freeze-saved =
   `Theme.Colors.Ring.water` snowflake, today = ring outline, future = muted. A perfect week
   collapses to a single accent bar. It also serves `RecapCard`.
3. Two-tier celebration. Routine earned unlock stays within `Theme.Motion.unlockCelebrationMaxDuration`
   (1.2s). Milestone days (7/30/100/365) present a second, dismissible screen (number tick, week
   row, share button) that the user leaves with an explicit Continue. This exceeds the 1.2s cap
   only because it is user-paced, not an auto-playing sequence, so it needs an explicit spec note.
4. At-risk state (Never Miss Twice territory, spec §5.6): tint the flame/ring with
   `Theme.Colors.warning`, not `danger`, and deep-link the widget to the Plan B action. Do not add
   mascot-style "desperation".
5. Under Reduce Motion the milestone screen fades and shows the final state; keep the existing
   `@Environment(\.accessibilityReduceMotion)` gating pattern (`reduceMotion ? nil : ...`).

### 3.3 Shield: the highest-frequency screen, with the least layout freedom

**Hard constraint first.** The real shield is `ShieldConfiguration` (ManagedSettingsUI). Its
customizable surface is `backgroundBlurStyle`, `backgroundColor`, `icon` (a `UIImage`), `title`,
`subtitle`, `primaryButtonLabel` (plus button background color) and `secondaryButtonLabel`, with
label colors via `ShieldConfiguration.Label` [P, Apple docs and developer forums, search summary].
Custom SwiftUI is not allowed. Layout is system-fixed: icon, title, subtitle, primary button,
secondary button. So the in-app `ShieldPreview` is a *preview* of the real thing; it can be richer
than the real shield, but the real one is what fires 50+ times a day (spec §2).

**Evidence on what changes behavior**

- **one sec (peer-reviewed, 280 participants, 6 weeks)** [P]: the intervention is a 10-second
  delay with a full-screen breathing/moving effect, feedback on the number of opening attempts in
  the last 24 hours, and an option to dismiss. Result: 57% fewer openings after six weeks; users
  closed the app again in 36% of attempts; attempts themselves fell 37% versus week one. The paper
  reports that offering the option to dismiss had the strongest effect, the time delay contributed
  secondarily, and **"the message before consumption is not effective."** (This last line is from
  the PMC full text as summarized by the fetch tool; re-read the paper before quoting it externally.)
  The founder expected a 12% reduction [T, RevenueCat].
- **Opal** [T]: opening a blocked app triggers a 7-second countdown before you can unlock or pause;
  a splash shows how many unlocks remain today. Three strictness tiers: Normal, Timeout, Deep
  Focus (cannot be bypassed) [T, Productivity Stack].
- **ScreenZen** (search summary, [V]): configurable 5 to 30 second delay that progressively lengthens as the
  same app is opened more often; tracks daily opens.
- **Brick and Foqos**: the mechanic is a physical NFC tap, not a screen. The research found no
  detailed design writeup of their blocked-state UI (**not established**).

**Implication.** The evidence says the *choice architecture* (a visible way out, a small cost to
continue, a count of how often you tried) does the work, and persuasive text does not. ZANO's
Living Shield (§5.1) is text-led. That copy still matters for tone and identity, but it should not
carry the whole burden, and the extension cannot animate or lay out anything anyway. ZANO's unlock
is goal-gated rather than time-gated, so the shield's real job is to make the fastest path to the
goal obvious in one glance, and to make leaving painless.

**Do this**

1. **Copy hierarchy.** Title: six words or fewer, action-first ("Workout first, then TikTok").
   Subtitle carries the numbers ("1 goal left. Streak 14."). Do not stack a sentence of coaching
   into the title. Coach-voice variants (§5.13) live in the subtitle.
2. **Icon as information.** The `icon` slot accepts any `UIImage`. Render a small ring-progress
   glyph ("2/3") with `UIGraphicsImageRenderer` from App Group state, in `Theme.Colors.accent` on
   transparent. This is the one place the shield can show a chart. Keep it light: extensions are
   memory-limited (spec §11/§27); pre-render a handful of states rather than drawing arbitrary ones.
3. **Colors.** `backgroundColor` = `Theme.Colors.background`; a dark blur style so it reads as one
   surface with the app; primary button = `Theme.Colors.accent` with dark label (contrast of
   `background` on `accent` is 16.4:1, computed); secondary label in `muted`.
4. **Button roles (product-owner A/B).** Only two buttons exist. Today: primary "Show my goals",
   secondary "Emergency". one sec's result suggests testing a primary that is a clear *leave*
   action against the "goals" primary via the coach-voice bandit (§9). Do not remove Emergency
   (CLAUDE.md safety rule).
5. **Locked-Out card (§5.16).** one sec proves the value of showing attempt counts. Reuse the
   same on-device count ("4th time this hour") on the in-app Locked-Out card and as a subtitle
   variant on the shield.

### 3.4 Unlock celebration ("Earned.")

**Evidence:** Duolingo's staging (3.2) is: state swap from grey to color, number change, label,
supporting row, then button. Fitbod ends a workout with confetti and a summary, and the second
paywall appears *after* that summary framed around 90-day predictions [T, ScreensDesign]. Opal
unlocks a rendered 3D gem as a first-purchase reward [T]. On Apple's Activity rings an overlapping
ring means the goal was exceeded (Apple Community thread summaries; not a design source).

**Implication.** ZANO's spec (§15/§16 P3) and Theme already cap at 1.2s with `springCelebration`.
The structure is right; the scale is timid. "Earned." at 44pt in a 280pt burst frame is smaller
than the Duolingo streak number relative to its screen.

**Do this**

- Timeline inside 1.2s: 0 to 0.15s locked glyph (muted) swaps to accent; 0.1 to 0.7s ring fill
  with `Theme.Motion.ringFill` (0.6s) and the time-bank numeral ticks up with
  `.contentTransition(.numericText())`; the burst stays under 0.6s; the primary button is
  enabled from t=0.4s and never waits for the animation to finish.
- Make the time-bank value ("2h 10m") the hero in PROPOSED `numeralHero()`; "Earned." becomes the
  eyebrow above it at `numeralMedium()`. The number is the reward; the word is the label.
- Keep the 1-in-6 surprise (§8.4) as a badge chip after the number settles. Duolingo's rarity
  principle (milestones only) is why ZANO's routine unlock should stay quiet and the surprise tier
  should stay genuinely rare.
- Haptic: one `.success` on the state swap (the existing `sensoryFeedback` pattern), no second buzz.

### 3.5 Onboarding: pacing and the reveal

**Evidence**

- **One job per screen, no feature tours** [T, ScreensDesign on Duolingo]. "Level questions need a
  visible consequence." Delayed account creation: Duolingo defers signup until after the first
  lesson and frames it "Save your progress" [V, Gummble]. Time to first win reported at about 90 seconds [V].
- **Cal AI:** 32 screens; every input triggers an animation (a bar moves, a graph shifts, a number
  updates) so each answer has a visible consequence [T, tasu/ScreensDesign via search summary].
  Numbers shown: weight-loss-speed selector "offers instant timeline feedback" [T].
- **Opal:** about 11 to 12 screens [T]; one question per screen (name, new user, goal, age,
  description, daily screen time), then a personalized "Focus Report" quantifying lifetime phone
  time; copy is personalized ("[Name], Opal will get you back 5 years of your life") [T, Retention.Blog]; a
  playful tap-to-break-the-rock interaction and a fist-bump commitment animation [T]. The paywall
  follows the report, not the questions.
- **Duolingo "building your course"**: a roughly three-second theatrical loading beat with
  scrolling personalization text [V, Gummble; "manufactured anticipation"].
- **Fitbod:** 14 onboarding steps; strength-gain projections shown before signup; the first paywall
  appears after the first workout is generated but before it is started; the second after the
  summary [T]. The value is created and felt before payment is asked.

**Implication.** ZANO's 14 screens are fine. What the leaders add is (a) a visible consequence on
each input, (b) a theatrical "building it for you" beat before the reveal, and (c) the payment
ask directly after the peak. ZANO's current order puts Commitment (11), Permission priming (12),
Paywall (13). The permission screen sits between the peak and the ask.

**Do this**

1. **Live consequence on Q3 (`Screen5PhoneTime`).** As the slider moves, show "days per year on
   your phone" updating beside it in `numeralMedium()` with `.contentTransition(.numericText())`.
   Screen 9's reveal then lands as confirmation rather than first news. Uses the existing
   `OnboardingAnimatedCount` logic; motion gated by Reduce Motion.
2. **Wake-up moment (`Screen9WakeUp`).** Promote the two counters from `numeralLarge()` (44pt) to
   PROPOSED `numeralHero()`; this is the app's "Focus Report" and its single most shareable
   fact. Keep `danger` for the "days lost" number and `accent` for "days reclaimed".
3. **Plan reveal (`Screen10PlanReveal`).** Insert a 2 to 3s "building your plan" beat that
   *lists the user's own answers* as it resolves (the apps they picked, their goal, when they
   fall off). This is real personalization here, so it is honest, unlike Duolingo's mostly
   pre-built course.
4. **Test moving notification priming after the paywall** (Fitbod/Duolingo both ask right after a
   value moment). Requires a §7 order change, so it is a proposal, not a directive. Keep priming
   before step 14's first win so the first Live Activity can fire.
5. **Progress indicator:** confirm the container shows one (Duolingo does; Cal AI's bar moves per
   input). Not verified in this pass.

### 3.6 Paywall hierarchy

**Evidence**

- Scannable order: headline, value, price, CTA [V, ScreensDesign 2026]. Adapty's ordering:
  media, headline and 3 to 5 benefits, plans, social proof, CTA, legal links [V]. Runna "leads with the
  personalized training plan" and repeats user context before pricing; Hevy uses a Free/Pro table
  to make limits visible; BoldVoice's trial timeline shows the charge date and confirms a reminder
  is scheduled [T, ScreensDesign].
- **Trial timeline** is now an "Apple-endorsed" pattern [V]: Today / Day 5 reminder / Day 7 charge,
  with calendar dates rather than "Day 7" because "a date reduces ambiguity" [V, Adapty/ScreensDesign].
  Cal AI's "No Payment Due Now" with a promised reminder is the reference [V].
- **CTA label must match the action** ("Start seven-day free trial", not "Continue") [V]. Price must
  match App Store Connect exactly; full price, billing period and trial terms per plan; Privacy
  and Terms links; a reachable Restore Purchases; unclear trial terms or price prominence are the
  common rejection causes [V, Adapty]. Verify against the current App Review Guidelines text
  before shipping; I did not fetch Apple's page.
- Plan count: 2 products beat 1 by 61% and 3 beat 2 by 44% in Adapty's data [V, vendor-reported];
  annual is the highlighted default with visible savings [V, Superwall "anchor and decoy"].
- Fitbod's second paywall is framed around a 90-day projection [T].

**Implication.** ZANO's `Screen13Paywall` is a plan picker with a CTA. It lacks the two things
the leaders lead with: the user's own plan and a dated timeline. `PaywallView` already has three
benefit rows, a plan section, and Restore, so the pieces exist but are split across two files.

**Do this (top to bottom, one scroll, CTA pinned)**

1. Headline "Earn your phone back" (existing `Copy.onboarding.paywallHeadline`).
2. **"Your plan" recap card** (locked apps row, goals, schedule): the object they just built in
   step 10, reused compactly. Spec §21: "show the plan they built".
3. Three benefit rows with icons (existing `Copy.paywall.benefit*`), action verbs.
4. Plan cards: annual pre-selected with a savings badge, monthly beneath. Treat lifetime as the
   §21 "test only" option and keep it collapsed unless the test is on.
5. **CTA label bound to the selection** ("Start my 7-day free trial" for annual+trial).
6. **Dated timeline**: Today (full access), a reminder date two days before, and the charge date,
   with real dates from `Date`. It backs up the §7.13 "we'll remind you 2 days before" promise.
7. "Continue with limited free" stays visible (not tiny grey), then legal links, then Restore.
8. Do not add a post-close countdown or "special gift" screen (2.2).

### 3.7 Fuel: meal-photo flow

**Evidence**

- Cal AI: one photo returns the breakdown (calories, macros, health score, chat box); scan-food,
  barcode and label modes coexist on the camera surface; the edit screen shows the source image
  beside serving controls with a "Fix Issue" action; ingredients can be reviewed and adjusted
  before the diary accepts them [T, ScreensDesign; V for the screenshot-site details].
- ScreensDesign's calorie-tracker roundup: label status as **detected, estimated or entered** rather than giving every number equal
  authority; expose the source photo during review; correct "at the level where the mistake
  occurred" (portion wrong: keep ingredients; one ingredient missing: no full rescan) [T].
- MFP's failure (3.1) is partly a logging-friction failure: more taps, buried diary.

**Implication.** ZANO's photo flow is a Tier B verification (§3), so the estimate needs to feel
trustworthy *and* be one tap to accept. The competitors' calorie ring is the wrong hero (2.2), but
their review-card structure is exactly right.

**Do this**

- Result card: photo thumbnail top-left, **protein grams as the hero numeral** ("48 g",
  `numeralLarge()` or hero), an "Estimated" chip in `muted`, one accent button "Add 48 g". Below:
  a portion segmented control (half, 1x, 1.5x) as the fastest correction, then a collapsed
  "Ingredients" list for the slower correction. Two taps to log in the common case.
- Fuel's ring must read "72 / 150 g" and only fill upward; never a "remaining" figure.
- Keep quick-repeat chips (§5.19) above the camera entry: fastest path is no photo at all.
- Low confidence: ask one conversational question ("Chicken or tofu?") instead of showing a
  precise-looking wrong number [V, search summary of AI food-logging guides].

### 3.8 Progress, recap and share

**Evidence**

- **Strava Stats Stickers**: transparent-background stat overlays (route included) that the user
  places, resizes and rotates over their own photo inside Instagram Stories, with several
  layouts to scroll through [P, Strava community post, search summary]. Third-party tools exist
  because people want this format.
- Duolingo's milestone share card and spring bottom share sheet [T].
- WHOOP App Store screenshots lead with the dials and single color-coded numbers on dark, with
  restrained data colors "so the data reads as serious" [V, AppScreenMagic].
- Opal's home puts three numbers over one scrubbable hourly chart (3.1).

**Implication.** ZANO's `ShareCard` is an opaque 9:16 card. That suits Stories as a full-bleed
post, but the format Gen Z actually posts on top of gym-mirror photos is the transparent sticker.
The Time Reclaimed counter (§5.15) is ZANO's Opal "Focus Report": the number people screenshot.

**Do this**

- Add a transparent-PNG stats sticker export next to the 9:16 card: big numerals in `text`, one
  `accent` value, wordmark small. Same data as `RecapCard`.
- Recap top line: three numbers (as in spec P7: workouts, protein, time reclaimed) at
  `numeralMedium()` to hero, daily rings below, best day as a caption. Do not add a fourth stat.
- Time Reclaimed on Progress: hero numeral, then a scrubbable hourly/daily bar (Opal pattern) as
  the drill-down, not more rings.
- Already noted in `ui-stress-test-findings.md` §3.5: cap `title` and `statLine` line counts so
  long strings cannot clip the fixed 1080 x 1920 export.

### 3.9 Widgets and notifications

**Evidence:** Streaks' widgets are an App Icon ring widget, a Dots widget (fills dots or outlines
with color to show progress) and a Tasks widget (up to four tasks), all with theme and
gradient/flat backgrounds [T, MacStories]. Duolingo's widget changes state through the day and
deep-links to repair when at risk (3.2). Duolingo uses two notification types: routine (around the
user's habit window) and save (imminent loss only, capped at two per day) [V, Digia]; a "Streak
Wager" commitment test reportedly lifted day-7 retention 14% [V, single source; unverified].

**Do this:** ZANO's widget streak uses the literal fire emoji rather than the tinted SF Symbol the
in-app pill uses (`ui-stress-test-findings.md` §4.4). Match the pill. Give the small widget one
number and one action (Streaks-style), and an at-risk tint in `warning`. Notifications: keep the
two-a-day cap; separate "routine" from "save" in the scheduler. The Wager idea (commit to
protecting the streak) is compatible with §8.10 loss aversion if framed as opt-in.

### 3.10 Empty states

**Evidence:** first-run is the most sensitive empty state. Good ones give context, a next step and
a visual [V, Setproduct/Mobbin glossary]. Some habit apps seed sample data so heatmaps and streaks
are never blank [V]. Streaks' answer is structural: an empty slot is just an "add" circle in the
same grid [T].

**Implication.** ZANO §8.2 says never show an empty checklist. Today's unconfigured state (2.3) is a
`surface2` track at 1.16:1 against `background` plus a muted "Not set" caption. That reads as a
rendering bug, not an invitation.

**Do this:** unconfigured ring = dashed outline in `muted` at ring size with a plus glyph in the
center, title as usual, tapping it opens goal setup; only one such ring gets an accent tint (the
recommended first goal). Day 1 streak is set at the first win (§8.11 endowed progress). Trophy Case
already handles the zero state well (per stress-test findings §5); copy that approach for Progress.

### 3.11 Dark-surface craft: contrast, elevation, color meaning

Computed from `Theme.Colors` (WCAG relative luminance; **[D]**):

| Pair | Ratio |
|---|---|
| `surface` (#141416) vs `background` (#0A0A0B) | **1.08:1** |
| `surface2` (#1C1C1F) vs `surface` | **1.08:1** |
| `surface2` vs `background` (current ring track on Today) | **1.16:1** |
| `hairline` (surface2 at 0.8) vs `surface` | **1.06:1** |
| `text` on `background` | 18.2:1 |
| `muted` on `background` / `surface` / `surface2` | 6.1 / 5.6 / 5.2:1 |
| `accent` on `background` | 16.4:1 (so dark text on an accent button is 16.4:1) |
| `danger` on `background` | 5.8:1 |
| `Ring.focus` (#5E5CE6) on `background` / `surface` / `surface2` | **3.9 / 3.6 / 3.4:1** |
| Other ring hues on `background` | 5.4 to 14.0:1 |

Candidate strokes over `surface`: `text` at 0.08 = 1.22:1, 0.10 = 1.29:1, 0.12 = 1.38:1, 0.16 = 1.57:1.
Candidate ring tracks: `color` at 0.22 over `background` gives 1.76:1 (workout), 1.37 (protein),
1.39 (water) and only 1.21 for indigo `focus`.

**Evidence.** The strongest dark fitness dashboards use a near-black (not pure black) base [V];
WHOOP's dark canvas "makes colored elements feel like the primary content" [V]; a third-party WHOOP
blueprint describes "glow-as-elevation" and tabular numerals [C, low confidence]. Your own style
paragraph (§16) already asks for "subtle inner glow on active elements" and "crisp 1px hairline
dividers".

**Implication.** Luminance steps of 8 levels do not survive real viewing conditions (sunlight, low
brightness, OLED off-axis). At about 1.08:1, cards read as one flat plane, which is the "flat,
tutorial-grade" look this pass exists to fix. The `focus` indigo passes the 3:1 graphics threshold
but fails 4.5:1 for text, so never use `Ring.focus` as a text color.

**Do this**

1. Redefine `Theme.Colors.hairline` as `text.opacity(0.10)` to `0.12` (derived from an existing
   token, in the same way the current hairline was derived), used as a 1px `strokeBorder` on cards
   (`LockStatusCard`, `RecapCard`, plan cards). This yields about 1.3 to 1.4:1, which is enough for a
   thin line to read as an edge without turning cards into boxes.
2. Ring track: `Theme.Colors.text.opacity(0.12)` (1.48:1 over `background`) for all rings, or the
   ring's own color at about 0.30 with per-ring tuning on device. Do not use `surface2` for tracks
   on `background`.
3. Elevation by highlight, not shadow: a top-lit 1px inner stroke (a `LinearGradient` from
   `text.opacity(0.14)` to clear) on the hero card, plus `accent` glow only on *active* elements
   (the fill end-cap of a ring, the primary button pressed state). Matches §16's "subtle inner glow".
4. **Fewer hues per screen.** WHOOP uses three semantic colors app-wide [V]. ZANO defines 13 ring
   hues (`Theme.Colors.Ring`). Rule: Today and Fuel may use their per-goal hue (three, at most
   four). Dense views (Recap, Progress grid with five or more rings) switch to a single scheme:
   completed = `accent`, incomplete = `text` at low opacity. This keeps §15's "ONE accent".
5. **Locked is not an error.** Duolingo goes grey to vibrant on success; red is for loss. ZANO
   colors "locked" with `danger` (§15). On routine surfaces (LockStatusCard, Today) consider a
   desaturated `muted` padlock and reserve `danger` for Emergency, the alarm and true failure.
   Spec §8.10 says stakes are shown "before a lock, never as a threat". This is an opinion needing
   a design-owner call, not a bug.

### 3.12 iOS 26 platform context (verify on a Mac)

Deployment target is iOS 17.0, but the current SDK is iOS 26 (today is 2026-09-23). Built against
the iOS 26 SDK, system chrome adopts Liquid Glass automatically: the tab bar becomes a floating
pill inset from the edges, can minimize on scroll (`tabBarMinimizeBehavior`), and content beneath
fades but is not blurred; glass belongs to the navigation layer, not the content layer [T, LearnUI
and Donny Wals]. `tabViewBottomAccessory` shows on every tab, so it is wrong for a Today-only
action [T, Donny Wals]. "A large button above the tab bar obscuring content isn't very iOS 26-like" [T].

**Implication.** Today's full-width `PrimaryButton` on an `.ultraThinMaterial` bar
(`TodayView.swift:105-111`) stacks a second translucent panel above a floating glass tab bar.

**Do this:** make the primary action an inline hero at the bottom of the scroll content (a
`Theme.Radius.large` card with the accent button inside), with `.padding(.bottom)` clearing the
floating tab bar. Keep `.preferredColorScheme(.dark)` and the fixed `Theme` colors; do not tint
system chrome except the selected tab with `accent`. Confirm the tab bar and nav bar legibility over
`background` in the iOS 26 Simulator. `ContentView` and the tab bar are owned by another workflow
this run, so record and hand off rather than edit.

---

## 4. App-by-app cheat sheet

| App | Steal | Avoid | Confidence |
|---|---|---|---|
| **Streaks** | Grid of up to six large circles; long-press to complete; ring as progress; detail on the card's back; widgets with one number | Its customization sprawl (78 themes, 600 icons) is not ZANO's job | T/P |
| **Opal** | Quiz to "Focus Report" to paywall; three numbers plus one scrubbable chart on home; 7s countdown; unlocks-left splash; gem rewards; commitment micro-interaction | Lifetime at $399 as a default anchor; tooltips instead of a real first-run | T/P |
| **Brick / Foqos** | The physical tap as the whole ritual (matches §25 hardware) | No transferable screen design found | T |
| **one sec** | Attempt-count feedback; a clear way to dismiss; delay as friction; proof that message copy alone underperforms | Long delays on the goal-gated shield (ZANO's friction is the goal itself) | P |
| **ScreenZen** | Progressive delay based on repeat opens | Free-form intervention menu | V |
| **Fitbod** | Paywall after value is created; 90-day projection framing; body-map recovery visual; FAB "Start"; contextual tooltips only when relevant | 14+ steps of detailed input before value | T |
| **WHOOP** | Three numbers, tiers on separate screens, semantic color, dark canvas making color the content, big hero metric | All-caps DIN styling (keep SF Rounded numerals for ZANO's tone) | V/C |
| **Strava** | Stats stickers; stats overlaid on map instead of a toggle; contextual tooltips after first activity | Aggressive early paywall with a 30-day trial | T/P |
| **Duolingo** | Grey-to-color state swap; number as hero; week row; milestone-only drama; earned (not bought) restoration; two-push cap | Guilt-toned mascot escalation; unverified retention numbers | P/T/V |
| **Cal AI** | Source photo beside estimate; detected/estimated/entered labels; per-input animation in onboarding; "No Payment Due Now" | Calorie-remaining hero; 32-screen onboarding | T/V |
| **MyFitnessPal (2026)** | Nothing structural | Giant cards on list rows, buried diary, extra taps: ratings collapsed | T (rating figure unverified) |

---

## 5. Anti-patterns to keep out of ZANO

1. Hero-scale cards for repeating list rows (MFP).
2. Any core action reachable only by more taps than before a redesign (MFP; §8.8 effort asymmetry).
3. Color used decoratively; 13 ring hues on one dense screen.
4. Big numbers in muted grey below an icon-only ring.
5. Hairlines and tracks at about 1.1:1 contrast on near-black.
6. A shield that leans on long persuasive copy (one sec: the message alone is not effective).
7. Countdown-timer discount screens and post-close "gifts" (§21).
8. Full-width glass bars stacked over the iOS 26 tab bar.
9. Celebrating every action equally, so nothing feels earned.

---

## 6. Open questions and Mac verification checklist

**Not established by this research**

- Real point sizes for Duolingo's streak number versus its label, and Opal/Strava/Fitbod type scales.
  Needs actual screenshots. Sources to open and measure: ScreensDesign showcases (Opal, one sec, Cal AI,
  Fitbod, Strava, Duolingo), Mobbin's Opal onboarding flow and Duolingo streak screen, Page Flows for Opal, and
  60fps.design's Duolingo shots.
- How Brick and Foqos present their blocked state.
- Whether the "message is not effective" one sec finding holds for a goal-gated shield (the study
  was time-gated). Treat as a hypothesis to test with ZANO's own bandit.
- The exact MFP rating drop (search-summary figure, page not fetched).
- Apple's current wording on paywall price prominence (guideline text not fetched).

**Verify on a Mac once available** (every item is currently a prediction)

1. Today at 375, 393 and 430pt widths: confirm the ring row currently scrolls and the third ring is
   clipped; confirm the fixed version shows all three.
2. Cards, ring tracks and hairlines legible at normal and 50% brightness, and outdoors (or with the
   Simulator's high-brightness screenshot approach).
3. Type hierarchy: one clear hero per screen at default and at AX3 Dynamic Type (fixed sizes do not
   scale today, see `ui-stress-test-findings.md` §1.2; any new hero numeral must use a
   scaling-capable definition).
4. Shield extension rendering on a real device (Simulator cannot host FamilyControls): icon
   rendering memory, blur style choice, button contrast.
5. iOS 26: tab bar overlap with the bottom action; scroll-edge fade over `background`.
6. Celebration timeline stays at or under 1.2s and the button is tappable before it ends; Reduce
   Motion path shows the final state with no springs.
7. Both paywalls: same structure, price matches App Store Connect, dated timeline correct in a
   non-US locale.

---

## 7. Sources

Confidence tag in brackets. "(search summary)" means the fact came from a search result snippet
and the page itself was not read.

**Screen-time and discipline**
- one sec, PNAS/PMC full text: https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409/ [P]
  (PNAS original returned 403: https://www.pnas.org/doi/10.1073/pnas.2213114120)
- one sec, "Friction will change your behavior": https://one-sec.app/blog/friction-will-change-your-behavior/ [P]
- RevenueCat on one sec: https://www.revenuecat.com/blog/growth/frederik-riedel-expected-12-his-app-cut-screen-time-by-57/ [T]
- Opal review (7s countdown, tiers): https://productivitystack.substack.com/p/opal-review [T]
- Opal home screen redesign: https://opalapp.com/blog/introducing-the-new-opal-home-screen-track-your-screen-time-and-improve-your-focus [P]
- Opal teardown: https://screensdesign.com/showcase/opal-screen-time-control [T]
- Opal chat-style onboarding: https://www.retention.blog/p/chat-based-onboarding [T]
- Opal onboarding (11 screens): https://theappfuel.com/examples/opal_onboarding [T]
- ScreenZen delay design (search summary): https://unhookd.app/blog/screenzen-worth-it-review [V]
- Streaks review: https://www.macstories.net/reviews/streaks-6-brings-habit-tracking-to-your-home-screen-with-extensively-customizable-widgets/ [T]
- Streaks, Apple editorial: https://apps.apple.com/us/story/id1272004658 [P]
- Brick overview: https://trailandkale.com/brick-app-blocker-review/ [T]; Foqos: https://www.foqos.app/ [P]
- Apple `ShieldConfiguration`: https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration and forum
  https://developer.apple.com/forums/thread/738620 [P, search summary]

**Streaks and celebration (Duolingo)**
- Duolingo, streak milestone design: https://blog.duolingo.com/streak-milestone-design-animation [P]
- Deconstructor of Fun, streaks: https://duolingo.deconstructoroffun.com/mechanics/streaks [V]
- 60fps.design, 126-day and 2-day streak animations:
  https://60fps.design/shots/duolingo-126-day-streak-animation ,
  https://60fps.design/shots/duolingo-2-day-streak-animation ,
  https://60fps.design/shots/duolingo-streak-card-and-share-sheet [T]
- Reminder architecture: https://www.digia.tech/post/duolingo-habit-forming-reminders-retention-architecture/ [V]
- Streak psychology: https://uxmag.com/articles/the-psychology-of-hot-streak-game-design-how-to-keep-players-coming-back-every-day-without-shame [V]
- Onboarding: https://gummble.com/blog/duolingo-onboarding-flow-analysis [V],
  https://screensdesign.com/articles/duolingo-onboarding-design/ [T]
- CSS-level reconstruction: https://blakecrosley.com/guides/design/duolingo [C]
- Widget mood/deep-link (search summary): https://medium.com/@Jager-yoo/the-best-example-of-leveraging-ios-widget-potential-duolingo-f677115ad3f6 [V]

**Dark-mode fitness**
- WHOOP design breakdown: https://www.925studios.co/blog/whoop-design-breakdown [V]
- WHOOP App Store screenshots: https://appscreenmagic.com/top-screenshots/whoop [V]
- WHOOP blueprint: https://www.spectr.to/gallery/whoop [C]
- Fitbod teardown: https://screensdesign.com/showcase/fitbod-gym-fitness-planner [T]
- Fitbod critique (FAB "Start", search summary; page returned 403): https://medium.com/product-x-management/app-critique-fitbod-b78db0b8e61e [V]
- Strava teardown (search summary): https://screensdesign.com/showcase/strava-run-bike-hike [T]
- Strava map/data overlay change (search summary): https://the5krunner.com/2025/07/16/strava-app-redesign/ [T]
- Strava stats stickers (search summary): https://communityhub.strava.com/what-s-new-10/use-strava-stats-stickers-on-ig-stories-ios-android-9344 [P]
- Strava dark mode announcement (no design detail): https://stories.strava.com/articles/athlete-intelligence-new-heatmaps-dark-mode-and-more-the-major-announcements [P]

**AI meal logging**
- Cal AI teardown: https://screensdesign.com/showcase/cal-ai-calorie-tracker [T]
- Calorie tracker design roundup: https://screensdesign.com/articles/calorie-tracker-app-design/ [T]
- Cal AI screens (fan site): https://calaicalorietracker.com/cal-ai-screenshots/ [V]
- MyFitnessPal redesign complaints: https://piunikaweb.com/2026/04/24/myfitnesspal-new-update-complaints/ [T];
  rating figure (search summary; page returned 410): https://mwm.ai/articles/myfitnesspal-v26-16-0-replaces-diary-with-new-ui-sparking-rating-drop-in-april-2026 [V]

**Paywalls, onboarding, empty states**
- Adapty, high-performing paywall 2026: https://adapty.io/blog/high-performing-paywall-2026/ [V]
- Adapty, iOS paywall and review rules: https://adapty.io/blog/how-to-design-ios-paywall/ [V]
- Superwall, five paywall patterns: https://superwall.com/blog/5-paywall-patterns-used-by-million-dollar-apps [V]
- ScreensDesign, 2026 paywalls: https://screensdesign.com/articles/mobile-app-paywall-design-examples-2026/ [T]
- Qonversion: https://qonversion.io/blog/paywall-design-uiux-examples [V]
- RevenueCat, State of Subscription Apps 2026 (search summary): https://www.revenuecat.com/state-of-subscription-apps-2026-business/ [V]
- Setproduct, empty states: https://www.setproduct.com/blog/empty-state-ui-design [V]

**iOS 26**
- https://www.learnui.design/blog/ios-design-guidelines-templates.html [T]
- https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/ [T]

**Internal (read for this pass)**
- `docs/spec.md` §1 to §3, §5, §7, §8, §15, §16, §21; `CLAUDE.md`;
  `Core/Sources/Core/UI/Theme.swift`; `GoalRing`, `RingCluster`, `LockStatusCard`, `StreakPill`,
  `PrimaryButton`, `ShieldPreview`; `TodayView`, `Screen9WakeUp`, `Screen13Paywall`, `PaywallView`,
  `UnlockCelebrationView`, `FuelView` (structure); `docs/design/ui-stress-test-findings.md`,
  `docs/design/apple-design-review.md` (not re-derived here).
