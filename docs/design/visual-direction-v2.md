# Visual direction v2: "after-hours arcade, frosted glass"

**Date:** 2026-10-02 · **Status:** implemented for the design system, tab bar, Today and Lock (session 5c).
Fuel, Progress, Settings, onboarding, paywall, celebration and milestone cards pick it up through the
shared tokens and components; their own layout passes are listed at the end.
**Why:** the founder's feedback on the 2026-10-02 screenshots: "It's not exciting and looks a bit AI.
Make it fun, themed a little more, get rid of elements that don't fit, a much cleaner glassmorphic
bottom nav bar, use glassmorphic components."
**Spec:** §15 (design system), §16 (UI exploration), §5.1 (Living Shield), §8 (retention), §24 (safety).
The §15 token table (colors, radii, type) is superseded by this document; §15 needs a one-line pointer
here the next time someone edits the spec.

---

## 1. Why the old screens read as "generated"

| Tell | Where it showed |
| --- | --- |
| Near-black canvas (`#050506`) with one bright blue accent | every screen |
| Content chopped into identical dark cards, one radius everywhere | Today, Lock, Settings |
| Small grey captions under everything | "Blocking your apps · ends when…", "Gym session + Protein" |
| Meta strings joined with middle dots | "Locked · Social · since 7:00 AM", "Star 72% charged · time off your phone" |
| Tracked all-caps eyebrow labels | "SCREEN TIME TODAY" |
| Glow used as decoration | halos behind every hero |
| Dense stacks of equal-weight rows | goal list, settings |
| A busy tab bar: six labelled items | everywhere |
| Two hero numbers fighting | Today: "2h 23m" and "2" stacked |

## 2. The subject, and the idea

ZANO turns *earning your phone back* into a game you win every day. The people playing it are 17–27,
gym kids and self-improvers. The world it borrows from is the **after-hours arcade**: deep ink rooms
lit by coloured light, chunky score numerals, buttons that feel good to hit. The material is
**frosted glass**: glass is how the arcade light reaches the controls, so the colour you see through a
card is the colour of the room behind it.

One memorable thing per screen. On Today that is the star (the mascot). On Lock it is the vault rings.
Everything around it stays quiet.

## 3. Tokens

### Color

| Token | Hex | Role |
| --- | --- | --- |
| `background` (ink) | `#0B0E24` | The room. Indigo ink, not black: glass needs colour behind it. |
| `backgroundDeep` | `#06081A` | Bottom of the canvas gradient; where bars and the tab bar sit. |
| `surface` | `#161A3A` | Solid glass fallback (Reduce Transparency) and opaque sheets. |
| `surface2` | `#1F2450` | Nested solid wells, pressed states. |
| `text` | `#F4F3FF` | Warm white with a hint of violet. |
| `textSecondary` | `#D2D0EA` | Multi-line supporting copy (≈85%). |
| `muted` | `#A6A4C8` | Metadata (≈70%, not the old 45% grey). 7.6:1 on ink, 6.5:1 on a card. |
| `accent` (ZANO Blue) | `#3F7BFF` | Brand action colour: selection, primary CTA, earned. |
| `accentFill` | `#2A62E6` | Fill under a white label (5.3:1). |
| `aurora.blue` | `#3F7BFF` | Aurora blob 1. |
| `aurora.violet` | `#8F5BFF` | Aurora blob 2. |
| `ember` | `#FF8A3D` | Streak and fire moments only (streak flame, earned-day warmth). |
| `danger` | `#F0606E` | Emergency only. |
| `warning` | `#F5B54A` | Caution (never red). |

Goal rings are saturated and joyful now (each also carries a glyph; colour is never the only signal):
workout `#C8F04A` volt, protein `#FF9548` apricot, focus `#9B7BFF` violet, water `#3CC8FF` sky,
steps `#4BE38C` mint, creatine `#FF6FAE` pink, sunrise `#FFC94A` sun, sleep `#7C8CFF` periwinkle,
reading `#E9A86B` tan, meal prep `#34D6BE` teal, stretch `#D17BFF` orchid, cold/sauna `#8FE3FF` ice,
custom = `muted`.

### The canvas: aurora

`ZanoAuroraBackground` (Core/UI/Components/ZanoAurora.swift) replaces the flat fill behind every
`.zanoAmbient(_:)` and `.zanoBackdrop(...)` screen. Ink gradient (`background` → `backgroundDeep`) plus
three soft radial blobs: blue top-left, violet top-right, ember low-left (ember only lights up when
the day is earned). The blobs drift over 20–30 s periods at ~12 fps through a `TimelineView` that is
paused when the app is inactive, when the tab is hidden (`zanoAmbientIsLive`), and replaced by a still
frame under Reduce Motion. The bottom third stays dark so bars and the tab bar read cleanly. State
(`ZanoAmbientState`) sets the blob strengths: locked = cool and dim, progress = warming, earned =
brightest, with ember.

### Glass

One recipe, three elevations (`ZanoGlassLevel`):

| Level | Used for | Recipe |
| --- | --- | --- |
| `.card` | goal tiles, content cards (`zanoCard`) | white 9% → 4% frost sheen, tint wash, 1px specular stroke (white 35% top → 4% → 10% bottom), soft inner shade at the bottom edge |
| `.raised` | the one hero per screen (`zanoHero`) | white 12% → 5%, stronger stroke, drop shadow (black 35%, r 30, y 18), optional earned glow |
| `.chrome` | tab bar, chips over scrolling content, status capsules (`ZanoGlass`) | real `.ultraThinMaterial` + ink tint 35% + the specular stroke |

Content cards do **not** use a real blur: the aurora behind them is already soft, so a blur would cost
a render pass and look identical. Real material is only for chrome that content scrolls under.
Reduce Transparency: every level becomes a solid `surface` fill with the same stroke. Increase
Contrast: the stroke doubles.

### Radius (by hierarchy, not one value)

| Token | Value | For |
| --- | --- | --- |
| `small` | 16 | tiles inside cards, wells |
| `medium` | 24 | cards, goal tiles |
| `large` | 32 | sheets and large cards |
| `hero` | 36 | the one hero surface per screen |
| controls | `Capsule()` | buttons, chips, the tab bar |

Concentric: 24 holds 16 at an 8pt inset, 32 holds 24 at 8.

### Type

System families, used deliberately:

- **Scores** (`Typography.score(size:)`, `NumeralText`, `numeralHero`): SF Pro **Expanded**, black/heavy.
  Big, wide, game-score energy. Smaller counters (`numeralMedium/Small`) are SF Pro Rounded bold.
- **Voice** (`display`, `titleLarge`, `title`, `headline`): SF Pro **Rounded**, bold/semibold.
- **Body/caption**: SF Pro (default design).

Rules: sentence case, no tracked all-caps, no eyebrow labels above sections, no middle-dot meta
strings in new UI (a meta line becomes chips or two separate facts), fewer and larger words.

### Spacing, metrics, motion

Spacing keeps 4/8/12/16/24/32 and adds `xxl` 48. Tab bar: 64pt high capsule, 52pt items.

| Motion token | Value | For |
| --- | --- | --- |
| `springStandard` | 0.35 / 0.82 | state changes |
| `springPop` | 0.28 / 0.52 | goal completion pop, burst |
| `tabPill` | 0.42 / 0.78 | the tab bar's sliding pill |
| `idleBobPeriod` | 3.4 s | the star's idle bob |
| `auroraFrameInterval` | 1/12 s | aurora drift |

Every motion is gated on Reduce Motion (still frame / no scale), and the aurora pauses off-screen.

## 4. Components

- **Tab bar** (`App/ZANO/ZanoTabBar.swift`): one floating chrome-glass capsule, five icon-only tabs
  (Today, Lock, Fuel, Progress, Settings; Squad hidden for v1). The selected tab grows a liquid blue
  pill that slides between tabs (`matchedGeometryEffect`, `tabPill` spring) and reveals its label.
  Lock carries a small dot while a lock runs. Every button keeps `accessibilityLabel(title)` inside the
  `zano.tabBar` container, and offers the Large Content Viewer.
- **Star** (`ZanoLivingMark`): the mascot. Bigger on Today, a playful bob, a light sweep when charged,
  and a `ZanoChargeBurst` (ring shockwave + pop) when a goal completes.
- **Goal tiles** (`GoalActionList`): each goal is its own glass tile washed in its colour. Two per row
  (an odd last tile spans the row); one per row at accessibility text sizes. Ring + title + progress +
  the one action, full width at the bottom. A completed tile pops (scale + haptic) and glows in its colour.
- **Status capsule** (`ZanoStatusCapsule`): chrome glass, an SF Symbol instead of a dot when given one.
- **Streak pill**: chrome glass, ember flame, score numerals.
- **Info button** (`ZanoInfoButton`): the home for explanations removed from main screens (a popover).

## 5. Screens in this pass

**Today** reads in three seconds: the header (wordmark + streak), the star with one charge chip, the
big score ("2" / "goals to unlock"), the goal segments, one glass status capsule ("Social", lock icon,
chevron into Lock), then the goal tiles, then at most one suggestion.
Removed: the date beside the wordmark; the "2h 23m / SCREEN TIME TODAY / Star 72% charged · …" stack
under the star (now one chip, and the total lives in the Screen time section); the goal-names caption
under the number (the tiles say it); the "since 7:00 AM" meta in the capsule (Lock shows it); the
"Blocking your apps · ends when…" line (Lock shows it as two facts). All of it is still in the hero's
VoiceOver label, which still starts with "Locked ·" for the UI tests.

**Lock**: one hero, the vault (glass `hero` surface, lock medallion + set name, "since 7:00 AM" chip,
score + concentric rings, locked-app icons). The separate star above it is gone (Today owns the star).
Then two facts ("Blocking 12 apps", "Ends when your goals are done") as glass tiles, the goal tiles,
borrow, and the trigger/next-lock line. The borrow card's explanatory sentence moved into an info
popover. Emergency unlock is unchanged and pinned at the bottom in every locked state.

## 6. Next pass (adopt, don't re-invent)

- **Fuel / Progress / Settings**: drop section eyebrows and all-caps; use `title` (rounded) for section
  heads; replace middle-dot meta lines with chips; let the hero number use `Typography.score(size:)`.
- **Onboarding**: `.zanoBackdrop` already gets the aurora. Swap condensed-heavy headlines for the rounded
  `display`; one big visual per step.
- **Paywall**: plan cards as `zanoHero`/`zanoCard` glass; the selected plan gets the accent stroke and pill.
- **Celebration / milestone cards**: ember belongs here; use `ZanoChargeBurst` and `springPop`; move
  `Typography.numeral(size:)` call sites to `score(size:)` once each layout is checked on an SE
  (expanded is ~35% wider than the compressed face they use today).
- `numeral(size:)` deliberately keeps its old compressed face so unverified screens don't overflow;
  retire it screen by screen.

## 7. Pass 2: moments and setup screens (2026-10-03, "make it more playful")

Feature-local, no Core/UI changes. Unverified on a device or simulator (parse-checked only).

- **Unlock celebration**: the star leaps while it charges, bursts at the apex (jackpot rays in the goal
  palette, sun marquee bulbs, shockwave) and bounces back; confetti in the goal palette; "Apps unlocked"
  glass chip; "Earned." is a tilted stamp (score face, double sun rim) that slams down with a heavy
  haptic; the Time Bank rolls up in 12 steps with selection ticks; verification is two chips; the
  surprise is a pink prize ticket ("Bonus round!"). Reduce Motion: resting frame, one success haptic.
- **Share posters**: collectibles. `PosterHue` per poster (streak ember, hours violet, unlocks volt,
  early bird sun, month sky, recap sky, locked-out pink); arcade-room background (hue blobs, sunburst,
  halftone, fixed sprinkles); eyebrow as a tilted sticker pill; hero on a die-cut sticker (white rim,
  hard offset shadow, tilt). Still 1080x1920 via `ImageRenderer`, static `ZanoMark`, no materials.
  The one-accent rule for share cards is retired for posters.
- **Sunrise alarm**: a striped retro sun rises behind the score-face clock; the tag prompt is a sun
  sticker in breathing ripple rings; compact layout under 700pt container height; escape hatch label
  shortened to "Emergency off" (still pinned, same hold + VoiceOver action).
- **Gym**: dwell is a 10-segment charge meter in volt (`GymChargeMeter`); saved gyms are glass map cards
  (`GymMapPreview`); empty states use the pin sticker.
- **NFC**: "Your collection" is a two-column grid of tag stickers in action colours; the tap scene's tag is
  a die-cut sticker, waves cycle goal colours, success pops confetti.
- **Trophy case**: glass cabinet; earned badges are coloured foil stickers (`TrophyBadgeDisc(badgeKey:)`,
  opt-in, so Progress's strip is unchanged) on glass stands; shop row hidden (v1 founder decision).

## 8. Pass 2: playful (design system, Today, Lock, tab bar, widgets; 2026-10-03)

**Why:** the founder, on the pass-1 screenshots: "Do the second pass, make it MORE PLAYFUL." Pass 1 got
the room right (ink, aurora, glass) but the room was empty: one quiet star, grey-ish tiles, a hero
that ate the whole first screen so the goals started below the fold. Pass 2 keeps the room and moves
a cast in. Unverified on a device or simulator (parse-checked only; CI is the compiler).

### The idea

The arcade has a **mascot**, **stickers** and **coins**. The star is a character who reacts to your
day; every goal's colour is a real presence (tiles that fill up like a glass of juice); wins throw
confetti in the goal colours; numbers roll like a score counter; everything you can tap squishes.
Still one orchestrated moment per screen: on Today, a completed goal makes its tile pop and the star
jump; nothing else moves on its own except the star's idle body language and the aurora.

### Playful tokens (Theme)

| Token | Value | For |
| --- | --- | --- |
| `Motion.springPop` | 0.34 / 0.46 (was 0.28 / 0.52) | earned beats: rounder, bigger overshoot |
| `Motion.springSquish` | 0.30 / 0.45 | the bounce back after any press (`PressableStyle`) |
| `Motion.numberRoll` | 0.45 / 0.72 | `RollingNumber`, rolling counters |
| `Motion.tabPill` | 0.40 / 0.68 (was 0.42 / 0.78) | squishier tab pill |
| `Motion.mascotJumpDuration` / `mascotSpinDuration` / `mascotHopPeriod` / `mascotWigglePeriod` | 0.9 / 0.7 / 1.6 / 3.2 s | the star's beats |
| `Colors.confetti` | blue, volt, apricot, pink, sky, sun | what a win throws (`CelebrationBurst` default) |
| `Colors.stickerHighlight` / `stickerShade` / `stickerRim` | white 32% / black 18% / white 85% | the vinyl look |
| `Metrics.stickerSmall/Regular/Large` | 26 / 34 / 48 | sticker heights |
| `Metrics.goalTileMinHeight` | 156 | an actionable goal tile |

### Components (Core/UI; adopt these, don't re-invent)

- **`ZanoSticker(_ text: String? = nil, systemImage:, color:, style: .filled | .tinted, size: .small |
  .regular | .large, tilt: Double = 0, bounceTrigger: Int = 0)`**: chunky chip on thick "vinyl": fill,
  top highlight, bottom inner shade, coloured drop light. `.filled` = solid colour with an ink label
  (`onFill`, AA on every goal colour); `.tinted` = the colour's wash on glass, `text` label. Icon-only
  stickers are decoration (hidden from VoiceOver, white die-cut rim) and may tilt; **`tilt` is ignored
  when there is text** (never rotate words). Symbols render `.hierarchical` and bounce on
  `bounceTrigger`.
- **`ZanoSparkleShape(pinch:)`**: the four-point arcade sparkle. Sparks, bursts, confetti.
- **`RollingNumber(_ value: Int, size: 34, face: .rounded | .score, color:)`**: a bare count that rolls
  (`.numericText(value:)`, `numberRoll`), Dynamic Type clamped at 1.35x. Strings with units stay
  `NumeralText` (which also rolls).
- **`.zanoGoalTile(color:progress:isDone:radius:)`**: the goal-coloured glass tile: tinted from the top
  (22%, 34% done), a liquid fill rising to `progress` with a bright surface line, a rim lit in the
  colour, a static glow when done. Text on it stays `text`/`textSecondary`.
- **`PressableStyle`** (same API): a squish (x gives a quarter less than `scale`, y a quarter more) and a
  springy release on `springSquish`. `.pressable(scale: 0.95)` for tiles, `0.92` for chips.
- **The mascot**: `ZanoMascotMood` (`.sleepy`, `.idle`, `.perky`, `.charged`; derive it with
  `ZanoMascotMood(done:total:isLocked:)`) and **`.zanoMascot(mood:jump:spin:sparkColors:size:showsGlow:)`**
  around any star view. Sleepy droops 12°, breathes, sits low and dim with two bubbles; perky hops with
  squash-and-stretch and orbits a spark per done goal colour; charged glows, hops faster and wiggles.
  `jump` (bump on a goal completion) crouches, leaps, stretches and lands; `spin` (bump on a tap) winds up
  and turns once. It is a modifier because Today's star on a device is drawn by the `ZANOReport`
  extension, which knows nothing about goals; the body language wraps it from the app. 
  `ZanoLivingMark(charge:height:accessibilityValue:mood:)` (new defaulted `mood`) also dims a sleepy star
  and brightens a charged one when drawn in-process. No faces.
- **`.zanoChargeBurst(trigger:color:sparks: Bool = true)`**: the ring pop now throws eight spinning
  sparkles (half the colour, half white).
- **`CelebrationBurst`**: defaults to `Theme.Colors.confetti` and adds sparkle particles. Pass
  `[Theme.Colors.accent]` for the old single-hue burst.
- **Aurora warmth**: `.zanoAuroraWarmth(_ 0...1)` outside `.zanoAmbient`/`.zanoBackdrop`, and
  `ZanoAuroraWarmth.forStreak(days:)` (square-root curve, full at 30 days): ember rises up to +0.16 and
  violet cools. `StreakPill` warms with the same curve (an ember wash) and its flame renders hierarchical.
- **`ScreenTimeChargeView`**: default height 96 (the compact hero's star; the report extension uses the
  default). The charge is a small sticker stuck on the star's corner ("72%", filled blue from 35%).
- **Navigation titles**: SF Pro Rounded heavy (large) and bold (inline), Dynamic-Type scaled, set once
  in `ZANOApp.configureNavigationBarTitles()`.
- **Coach voice**: `CoachVoiceTone.mascotLines(_:mood:)` (three short lines per voice and mood, what the
  star "says" when poked; sleepy lines always point at the next step, never shame) and
  `Copy.today.mascotSpoken(_:)` / `mascotHint`.

### Screens

- **Today**: the hero is a compact stage, about 190pt: the star (mascot, 96pt, its charge sticker) on the
  left, the score on the right ("2" / "goals to unlock", segments, the lock capsule, Earn Mode's banked
  minutes as a sticker). Stacked at accessibility sizes. The score is the button into Lock (VoiceOver
  label still starts with "Locked ·"); the star is its own control: tap to spin, a speech bubble with a
  coach line for ~2.4 s (announced to VoiceOver), light haptic. A completed goal: its tile pops and
  flips its sticker to a filled check with a burst in its colour, and the star jumps with a burst. The
  first row of goal tiles is visible on a 6.1" phone even with a suggestion card. Goal tiles: the whole
  tile is the button when it has an action (squish), chunky capsule affordance (quick-logs in the goal's
  colour with an ink label, starts in blue), the goal glyph as a tilted sticker that bounces on every
  log, a rolling progress line, liquid colour fill. Read-only tiles (Lock) are compact. Placement of
  `FinishTrialBanner`, `TrialEarnedCard`, `FinishSetupCard`, the health card and the suggestion slot is
  unchanged. The aurora warms with the streak.
- **Lock**: the vault rings light up per goal (full colour, stronger glow, a sparkle at 12 o'clock) around
  a padlock character that droops while nothing is done, sits up once something is, wobbles each time a
  goal lands and pops open (bouncing, blue) when earned. Medallion is a sticker; the number rolls. The
  blocking facts lead with tilted stickers. Borrow: the amounts are minute "coins" (hourglass, chunky,
  filled blue when picked, squish), the balance is a sticker. **"Hold to unlock in an emergency" is
  unchanged and pinned in every locked state.** The idle star sways.
- **Tab bar**: same glass capsule; the glyph you pick bounces (`symbolEffect(.bounce.up)`, keyed per tab
  so only that one jumps); squishier pill spring and press.
- **Widgets**: `ZANOWidgetColor` now points at the v2 tokens (ink, ZANO Blue, ember, volt/apricot/
  violet/sky goal colours) instead of the old near-black/bronze mirror; the background is a still
  aurora (ink gradient, blue behind the star, violet in the far corner); the streak flame is ember.
  StandBy unchanged (the system strips the background; `.widgetAccentable` marks what stays lit).

### Accessibility

Every motion is gated on Reduce Motion: the mascot keeps a still pose (sleepy tilt/dimness, glow,
parked sparks), no hop/wiggle/jump/spin; stickers don't bounce; presses dim without squishing; numbers
swap without rolling. Reduce Transparency: tiles and stickers become solid; the mascot's glow is off on
Today. Colour is never the only signal (tiles keep glyph + words; rings sit beside the number). Words
are never rotated.

### Unverified

Device/simulator rendering of all of the above. Specifically: transforms applied around the
`DeviceActivityReport` remote view (scale/rotation/opacity on the extension-hosted star) are expected to
work but are unverified; `symbolEffect(.bounce.up, options: .speed(_:))`, `hourglass.circle.fill` and
`sparkles` symbol names are from memory of the iOS 17 SDK.

## 9. Pass 3: restraint (2026-10-03)

**Why:** the founder, on the pass-2 screenshots: "I like the playful feel, just make sure it doesn't
overdo it and the gradients everywhere aren't too much — but the new icons and stuff are good and fun."
Pass 3 keeps every playful *object* (icons, `ZanoSticker`, goal-colour badges, the star mascot, chunky
score numerals, rolling numbers, the glass tab bar, the celebration) and takes the paint down.

### Rules (apply to anything new)

1. **Calm ink canvas.** The aurora stays on but runs at ~55% of its pass-2 light levels, drifts half
   as far (±2.5%) and ~1.7x slower (40–50 s orbits); streak warmth adds at most +0.07 ember (was
   0.16). The onboarding backdrop and the widget background were halved to match. Most of any screen
   should read as plain ink.
2. **Flat tints, not washes.** A tinted surface is ONE colour at low opacity: `zanoCard(tint:)` 8%
   (12% active), `zanoGoalTile` 14% (18% done). No multi-stop or corner-fading washes on cards, tiles,
   chips or meters.
3. **Flat progress.** Progress fills are one solid colour: tile fill (10%, no "juice" surface line),
   goal rings and vault rings (no angular sweep), Fuel bar (no gloss strip), water tank (solid water,
   flat rim), Progress week pills (one accent colour for every earned day, no candy palette, no
   shine), onboarding power cells (one accent), the paywall trial path (one solid accent line).
4. **Rims only where they mean something.** Neutral glass keeps its specular edge. A thin *solid*
   coloured rim marks done/selected/earned (done goal tile, active `zanoCard`, earned trophy stand).
5. **One glow per screen, and it is the hero's.** Only `zanoHero(active:)` and the star (mascot glow,
   `StarBloom`, Lock's idle halo, First Win halo) glow. Removed: done-tile glow, active-card glow, ring
   glows, Fuel bar/tank glows, streak-pill flame glow, Progress flame/pill/sticker/rank/shelf glows,
   power-cell glows, paywall path/node glows, tab-bar pill glow, gym battery segment + numeral glows,
   Today's score-numeral glow, vault lock/segment glows, live-dot glows.
6. **No gradient text.** Every text fill is one solid colour (Your Why's days numeral is solid ember;
   the metallic text on recap story, referral code and the "Earned." stamp is now `text`).
7. **Solid buttons.** `PrimaryButton` filled = flat `tint.fillColor` with a flat hairline rim (no
   sheen, no gradient rim). The onboarding charge button sweeps solid `accentFill` with a solid
   `accent` rim (no blue→violet, no violet glow). Tab-bar pill, Today chunky capsules, Lock borrow
   coins, Fuel chips, the share button: solid.
8. **Gradients are allowed only for:** glass material (frost fill, specular `glassEdge`/`edgeGradient`,
   inner shade), the star's metal and light (`metallic`, graphite, charge mask, light sweep), the
   aurora / `HeroGlow` / onboarding ambient lights, functional scrims (sticky action bar, map fade,
   camera vignette, alarm dock fade), cosmetics previews (they depict the product), the unlock
   celebration, the alarm ringing screen, and share posters/story pages.
9. **Posters stay bold, two decorative layers max.** `PosterRoom` = ink + one hue blob + the sunburst.
   The partner blob, halftone field and confetti sprinkles were removed.
10. **Motion:** the only always-on idle motion is the star (and the alarm ringing screen). Removed:
    the live-status `symbolEffect(.pulse)` (Today status row, tile live dot), the gym battery's blinking
    next segment, the NFC tag scene's idle phone bob and idle wave loop (the waves move only during an
    active scan). **One burst per win:** a goal completing on Today bursts the hero star only; the
    tile pops and flips its sticker but no longer throws its own burst.

All accessibility labels, UI-test labels and behaviour are unchanged; Reduce Motion / Reduce
Transparency paths are as in pass 2. Unverified until the next CI screenshot tour.

## 10. Light mode (2026-10-03)

**Why:** the founder: "A light mode for the app would be nice." The app was dark-only (fixed tokens,
`.preferredColorScheme(.dark)` on ~90 screens). It now follows the system appearance, with a
Settings > Appearance override (System / Light / Dark, default System).

### How it works

- Every colour token is a light/dark pair (`ZanoTone` in `Theme.Tones`); `Theme.Colors.<name>` is the
  dynamic `Color` built from it (a `UIColor` dynamic provider, no asset catalog). Token names and call
  sites are unchanged, so every screen adapts. Tokens stay `static let`s on non-actor enums (safe in
  widgets).
- The choice lives in the App Group defaults (`ZanoAppearance.storageKey`), is applied once at the app
  root (`ZANOApp`: `.preferredColorScheme` plus the window's `overrideUserInterfaceStyle`, so sheets
  follow and "System" really releases), and by `.zanoAppAppearance()` in the Home widget and the Screen
  Time report views (extensions the root can't reach).

### Light palette

| Token | Light | Dark (unchanged) | Note |
| --- | --- | --- | --- |
| `background` | `#F5F6FB` | `#0B0E24` | cool soft white, faint lavender (not cream, not pure white) |
| `backgroundDeep` | `#E8EAF4` | `#06081A` | |
| `surface` / `surfaceHero` | `#FFFFFF` | `#161A3A` / `#1D2248` | |
| `surface2` | `#ECEEF6` | `#1F2450` | |
| `text` | `#13142B` | `#F4F3FF` | 16.7:1 |
| `textSecondary` | `#3B3D5E` | `#D2D0EA` | 9.7:1 |
| `muted` | `#5C5E7E` | `#A6A4C8` | 5.8:1 |
| `accent` | `#2A62E6` | `#3F7BFF` | same brand blue a step deeper: 4.9:1, still usable as text |
| `accentFill` | `#2A62E6` | `#2A62E6` | white label 5.3:1 |
| `accentWash` / `accentDim` | `#DFE7FF` / `#A9BFF5` | `#15255E` / `#24408C` | |
| `ember` | `#B34A06` | `#FF8A3D` | 5.0:1 |
| `danger` / `warning` | `#C42F3F` / `#9A5F00` | `#F0606E` / `#F5B54A` | 5.1 / 4.9:1 |
| `hairline` / `hairlineStrong` / `track` | ink 10% / 18% / 10% | white 12% / 20% / 16% | |
| glass card fill | white 86% → 66% + soft indigo shadow (`glassShadow`, 10%, r14 y6) | white 9% → 4% | |
| glass rim (`glassEdge`) | white top highlight over an ink 7–12% hairline | white 35% → 4% → 12% | |
| chrome tint (tab bar) | white 45% over the light material | ink 35% over the dark material | |
| `shadow` | `#2A2D5C` 18% | black 55% | |
| aurora blue / violet / ember | `#5B8CFF` / `#A57BFF` / `#FF9A55` | `#3F7BFF` / `#8F5BFF` / ember | same low opacities: faint pastel tints |
| `metallic` (logo metal) | steel `#8C91A6` → `#666B80` → `#44485C` | pearl → silver | the silver star vanished on white |
| star graphite (`markGraphite*`) | ink 16% → 8%, edge ink 30% | white 11% → 3.5% | |

Goal colours in light are deeper twins of the same hues, each ≥4.5:1 on the light canvas (so they
work as text, as graphics, and as fills under an `onFill` label, which is the light canvas colour in
light mode): workout `#4F7300`, protein `#B8520A`, focus `#6A48E0`, water `#00749E`, steps `#0E7A43`,
creatine `#C22F72`, sunrise `#946600`, sleep `#4652D8`, reading `#9A5A22`, meal prep `#00776A`, stretch
`#9A3FD0`, cold/sauna `#0F6E8C`. Confetti uses the same tokens. Stickers (white die-cut rim, vinyl
highlight) are physical objects and look the same in both. The §9 restraint rules apply unchanged.

### Deliberately dark in both appearances

- **Alarm ringing** (`AlarmRingingView`): it rings in a dark bedroom.
- **Unlock celebration** (`UnlockCelebrationView`): the star's light sweep and burst are additive
  light on ink and wash out on white.
- **Share posters and moments** (`SharePoster` render, `ShareCard`, milestone moments, monthly story,
  locked-out moment, weekly recap story): posters are rendered dark for social feeds, and the moment
  shows the poster it shares.
- **The shield** (`ZANOShieldConfig`) and the in-app `ShieldPreview` of it: `ShieldConfiguration` is a
  static value drawn by the system in another process; its colours are the dark tones resolved
  explicitly. A dark block screen works over any app in either appearance.

### Unverified

Dynamic `UIColor`-backed `Color`s resolving against `.environment(\.colorScheme, …)` inside
`ImageRenderer` and in the widget's container background; `preferredColorScheme(.dark)` on a
full-screen cover not leaking to the window; the report extension honouring an explicit choice;
everything until the CI light pass (`shots/light-*.png`) has been looked at.

## 11. Buddies (2026-10-03)

**Why:** the founder replaced the ZANO star as the app's character with nine pixel-art buddies the
user picks from. All nine ship; **Stash** (the raccoon, also the app icon) is the default.

- **Model:** `Buddy` (Core/UI/Buddy): stash, zib, lox, pip, moko (cozy crew) and brick, tank, volt,
  howl (hype crew). Each has three poses (`BuddyPose`: idle, sleepy, happy) as generated 32x32 pixel
  data (`BuddySprites.swift`, from `scripts/buddies`; never edit by hand) and a colour trio in
  `Theme.BuddyColors`. `BuddySprite(buddy, pose:, size:)` draws it with nearest-neighbour scaling;
  it is decorative (callers label the element). Copy: `Copy.buddy`.
- **Storage:** `Buddy.storageKey` in the App Group defaults, read with
  `@AppStorage(Buddy.storageKey, store: SharedDefaults.store)` in the app, the widgets and the Screen
  Time report. Today also writes the hero's pose (`BuddyPose.heroStorageKey`) because the report
  extension that draws the hero on a device knows nothing about goals.
- **Picker** (`App/ZANO/Features/Buddy/BuddyPickerView.swift`): onboarding step 2 and Settings >
  Buddy. A raised glass stage (`zanoHero`) with the buddy at 128pt over a radial glow in its colour
  and an elliptical floor shadow; name in display rounded heavy; kind in the buddy colour (dark) or
  `textSecondary` (light, where lime/sun text would not read); the world as a solid chip in the buddy
  colour; a 3x3 grid of glass tiles (64pt sprite + name), selected = 2pt rim in the buddy colour over
  an 18% flat tint; a solid "Team up with <name>" capsule in the buddy colour with a fixed dark ink
  label (`Theme.BuddyColors.onSignature`). Tapping a tile stores it, hops the hero (not under Reduce
  Motion) and ticks a light haptic.
- **Pose mapping** (`BuddyPose(ZanoMascotMood)`): locked with nothing done = sleepy; everything done
  and every celebration = happy; otherwise idle. The `.zanoMascot(...)` motion layer (sway, hop,
  jump, spin, sparks) wraps the sprite exactly as it wrapped the star.
- **Per-buddy theme:** only the hero glow behind the buddy takes its colour (Today's mascot glow via
  `zanoMascot(glowColor:)`, the unlock celebration's bloom, the picker's stage). The app accent stays
  ZANO Blue.
- **Where the buddy replaced the star:** Today's hero (screen-time sticker and total kept under it)
  and the no-access card, the Lock tab's idle hero, the unlock celebration stage, the onboarding hook,
  guide, header meter, plan build beat, first win (intro ring, running, celebration) and paywall hero,
  the milestone poster sticker and moment, the recap story intro, and the Home Screen widgets
  (full-colour rendering).
- **Where the star stays (brand, not character):** the wordmark and the mark beside it on posters, the
  Lock Screen accessory widgets and accented/vibrant Home widgets (pixel art collapses into a tinted
  block there), NFC tag/card artwork (the printed maker's mark), the "first earned unlock" trophy glyph,
  Settings' Pro plan badge, the recap's faint star texture, and the app's previews. (The shield moved
  to the buddy on 2026-10-03, below; the star is only its fallback.)
- **Crispness:** sprites are sized at 32/64/96/128/160pt where it fits (the small Home widget with a
  Start button uses 48pt).
- **Buddy everywhere (2026-10-03):** the shield icon (stored buddy, sleepy, drawn 6x into 96pt @3x;
  `ShieldPreview` matches), the focus Live Activity (Lock Screen 48pt, expanded island 32pt, compact
  leading 16pt; happy, content while paused), local notification images (`BuddyNotificationImage`,
  144px PNG: nudges happy, streak at risk sad, trial reminder content, wind-down sleepy), empty states
  (goals editor 64pt, Progress recap 48pt sleepy, unlock tiers, squad alone card), the NFC tap toast
  (32pt, happy / sad on failure) and tag-written state (64pt excited), Settings' sign-off above the
  wordmark (48pt), and the launch screen (Stash above the wordmark, generated by
  `scripts/buddies/export_swift.py`; static, so always the default buddy). `StoredBuddySprite(pose:,
  size:)` is the one-liner for "the user's buddy" in these spots.

### Unverified

Everything until CI builds it and the tour (`buddy-picker`, `onboarding-2`, `buddy-brick-today`,
`light-buddy-picker`) has been looked at; the report extension picking up a buddy/pose change made in
the app (cross-process `@AppStorage` on App Group defaults); widget rendering modes on a device.
