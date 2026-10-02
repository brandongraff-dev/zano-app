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
