# Premium UI plan: making ZANO feel like a top-tier app

**Date:** 2026-09-24 · **Status:** Plan approved in direction; Phase 0 next. No Swift changed.

**Decisions (2026-09-24):** palette **option A** (keep dark, accent only for earned states; spec §15 amended). **Superseded later the same day:** the founder supplied the final logo (silver swoosh-star mark + thin geometric wordmark) and dropped acid green as not premium. The accent is now platinum `#E4E2DC`, goal rings are muted metals (see `docs/brand/brand-kit.md`). Phase 0 references: **Spotify** (content-first darkness, achromatic chrome, pill/circle geometry) and **Nike** (extreme condensed display-type contrast).
**Spec sections:** §15 (design system), §16 (UI exploration), §5.1 (Living Shield), §7 (onboarding),
§8 (retention psychology), §21 (paywall), §24 (safety), §27 (platform gotchas).
**Input:** the 25 CI screenshots from run 35935594714 (commit `aa04f093`), the 10 audits already in
`docs/design/`, and the nine skills vendored in `.claude/skills/` (see its README).

---

## 1. The bar: what "as good as Spotify or Airbnb" actually means

Those apps don't feel premium because of gradients. They share six traits, and each one is a
checkable requirement for every ZANO screen:

1. **One hero per screen.** Within about 3 seconds, you know what matters and what to do next.
2. **Content provides the color, not the UI.** Spotify's chrome is achromatic and album art brings
   the color. For ZANO, the content is your goals and the apps you've locked.
3. **Motion answers you.** Every tap, log and verification gets an immediate physical response
   (spring, haptic, number roll). Ambient decoration is rare.
4. **One unforgettable peak.** Duolingo's lesson-complete and Airbnb's booking-confirmed moments.
   ZANO's peak is **the unlock**, and today it isn't designed at all.
5. **Every state is designed.** Empty, loading, error, offline, first day and day 300 all look
   intentional. Nothing is ever a grey grid.
6. **One system, applied without exceptions.** The same radii, spacing, type ramp and press
   behavior everywhere, so the app feels built by one hand.

## 2. What's wrong today (from the screenshots)

- Every surface is the same dark card, so there's no depth hierarchy.
- The core idea, *your apps are locked*, is only shown as the text "2 goals left" over grey bars.
- There are large voids above the button on Today, Lock, Your Plan and First Win.
- Rings are flat and single-color, and an empty ring looks disabled.
- Acid green is used on chrome everywhere (tabs, buttons, icons), so it no longer means "earned."
- Default type plus tracked ALL-CAPS grey labels over every section.
- A flat black background that looks the same whether you're locked or unlocked.
- Empty states look broken (Progress "0m", grey heatmap), and the paywall dead-ends when there are
  no products.

## 3. The decision that needs you first: the palette

Spec §15 locks **near-black plus a single acid-green accent**. Anthropic's `frontend-design` skill
names exactly that combination as one of the five most common looks of AI-generated UI.
Decided 2026-09-24: **option A**.

| Option | What changes | Spec impact |
|---|---|---|
| **A. Keep it, make green earned (recommended)** | Chrome goes achromatic (white/grey tabs and buttons). Goal colors carry the content, Spotify-style. Acid green appears **only** when something is earned: completed rings, the unlock moment, the "Earned" state. Distinctiveness comes from light and atmosphere, not a new hue. | Small: amend §15 so the accent is not used on navigation/chrome. |
| B. Keep dark, change the accent | Pick a more ownable "earned" color (e.g. warm gold, trophy/rank energy). | Bigger: new §15 tokens, widgets, shield, app icon. |
| C. Keep everything as-is | Polish only. | None, but the result will read as "generic dark app". |

## 4. Design concept: "light is earned"

While you're locked, ZANO is dark, quiet and slightly cold, and your locked apps sit dimmed behind
a shield. Each completed goal adds its color and light to the screen. The unlock is the brightest
moment in the app. This one idea decides most visual questions (when to glow, when to use green,
how the background behaves) and it's literally what the product does.

## 5. How each skill is used

| Phase | Skill | What it contributes |
|---|---|---|
| Direction | `frontend-design` | Two-pass token plan (color, type, layout, principles), then critique against the brief before building. Flags generic defaults. |
| Direction | `ui-ux-pro-max` | `--design-system` run persisted to `design-system/zano/MASTER.md`, plus per-page overrides. Its first run already suggested condensed athletic type and "avoid: no gamification". |
| Direction | `make-mobile-design` | Real brand references from `awesome-design-md` (Spotify, Nike, PlayStation, Airbnb…), then `design-system.html` and iPhone-frame HTML mockups of every screen. |
| Mockups | `mobile-figma-designer` | The package structure: 00 system, 01 user flow, 02 screens, 03 edge states, 04 handoff notes. Done in HTML because no Figma is connected. |
| Mockups | `mobile-app-ui-design` | 8pt spacing, thumb-zone CTAs, 60/30/10 color, peak-end design of the unlock and first-win moments. |
| Critique | `ux-designer` | Accessibility (WCAG 2.2 AA, Dynamic Type, VoiceOver), onboarding, notifications, dark-pattern and ethics check (important for a lock app with a hard paywall). |
| Critique | `appstore-mvp-review` | Paywall placement (hard paywall), onboarding length, differentiation, review risk. Scored 1–10. |
| Build | `swiftui-from-figma` | Mockup to SwiftUI: reuse `Theme`/Core components, all states per screen, previews, no new dependencies. |
| Polish | `ios-icon-gen` | App icon and any custom glyphs as `.imageset` (runs in CI or on a Mac, since it needs `sips`). |

Where the skills disagree, this plan resolves it as follows:
- `ui-ux-pro-max` suggests Barlow Condensed, but `make-mobile-design` says iOS uses SF. **Use SF Pro
  with `.fontWidth(.condensed/.compressed)`** for big numerals and display. You get the athletic,
  condensed feel natively with no font license or bundle cost.
- `mobile-app-ui-design` says 4 sizes and 2 weights, but iOS HIG has an 11-step ramp. **Use the HIG
  ramp, but at most 4 sizes per screen.**
- `frontend-design` says no all-caps labels, and the app uses them everywhere. **Remove them.**
  Hierarchy comes from size and weight instead.

## 6. Phases

Each phase ends with a before/after gallery from the CI screenshot job (the same format as the
artifact you reviewed) and a stop for your approval.

### Phase 0: Direction (HTML only, about 1 session)
1. Generate and persist `design-system/zano/MASTER.md` (ui-ux-pro-max), reconciled with §15.
2. Ground the direction in the Spotify and Nike `DESIGN.md` references (make-mobile-design), and write the token plan (frontend-design pass 1).
3. Build **Today** in 3 directions as iPhone-frame HTML mockups, each honoring the concept above.
4. Self-critique each against the brief (frontend-design pass 2) and publish them side by side.
5. **You pick one.** It becomes `design-system.html` and the reference for everything after.

### Phase 1: Full mockup set (HTML, about 1–2 sessions)
Every screen in the chosen direction, grouped like the Figma package:
- **Main tabs:** Today, Lock, Fuel, Progress, Settings.
- **Onboarding:** all 14 screens plus the plan reveal (§16 P4), hold-to-commit.
- **Peak moments:** unlock celebration (§16 P3), first win, streak milestones, Locked-Out moment.
- **Paywall:** hard paywall (decision 2026-09-23), loading, product selected, purchase in
  progress, restore, **retry/offline** (fixes today's dead end).
- **Shield** (§5.1 Living Shield), widgets (S/M/L, lock screen), Live Activity/Dynamic Island.
- **Edge states:** empty day 1, no gym set, permission denied, offline, error, Dynamic Type XXL.
- **Handoff notes:** interactions, component mapping, motion specs.

Then run the critique passes: `ux-designer` (accessibility, ethics) and `appstore-mvp-review`
(scorecard). Fix what they find in the mockups before any Swift.

### Phase 2: Foundation in SwiftUI (1 session)
`Core/Sources/Core/UI/Theme.swift` v2 and the components it feeds:
- **Depth, 3 levels:** ambient background, frosted hero surface, recessed wells. This replaces the
  single card style in `ZanoSurface`.
- **State-driven ambient light:** background tone follows lock progress. `MeshGradient` is iOS 18+
  and the target is iOS 17, so it gets a `LinearGradient`/`RadialGradient` fallback.
- **Type:** SF condensed/compressed numerals, monospaced digits, no all-caps eyebrows.
- **Color roles:** achromatic chrome and earned-only accent (per the palette decision).
- **Motion tokens:** springs for response and ring fill, numeric-text transitions, haptic map, all
  respecting Reduce Motion.
- **Components v2:** `GoalRing` (gradient stroke, glowing end cap, tick track, complete state),
  `LockStatusCard` becomes a vault card (dimmed app icons behind a shield, per-goal segmented
  progress), `PrimaryButton` (press physics, hold-to-commit), `StreakPill`, `TimeBankBar`,
  a new next-action card, badge art.

### Phase 3: Screens (2–3 sessions, in this order)
1. Today → 2. Unlock celebration → 3. Your Plan and Paywall → 4. Progress (and Trophy Case) →
5. Lock → 6. Fuel → 7. Remaining onboarding → 8. Settings, Sunrise Alarm, Bedtime Gate, Shop.

Each screen ships with loading/empty/error states and previews, and all copy goes through
`Core/Sources/Core/Copy` (no hardcoded strings).

### Phase 4: Motion, haptics and the peak (1 session)
The unlock sequence (≤1.2s per §15): shield cracks, rings converge, green light floods, number rolls,
haptic crescendo. Built natively (Canvas + TimelineView + KeyframeAnimator, per
`docs/design/animation-library-decision.md`; no Lottie). Plus ring fills on appear, rolling
numbers, press states and the locked-state slow pulse.

### Phase 5: Assets and review (1 session)
- App icon and badge art (`ios-icon-gen`), share cards (§5.14).
- Fix demo seed data so screenshots show a real 15-day history, not empty grids.
- Final `appstore-mvp-review` and `ux-designer` audits on the built app screenshots.

## 7. Quality gate for every screen

- [ ] One hero, understood in 3 seconds. Primary action in the thumb zone.
- [ ] No void larger than one section gap. No filler either.
- [ ] Green appears only for earned states (if option A).
- [ ] At most 4 type sizes. No all-caps eyebrows. Numerals use the display style.
- [ ] Spacing only from the 4/8 scale. Radii concentric.
- [ ] Every tap has press feedback plus a haptic where it's a verified event.
- [ ] Loading, empty, error and offline states designed and previewed.
- [ ] WCAG AA contrast, 44pt targets, VoiceOver labels, Dynamic Type up to AX sizes, Reduce Motion.
- [ ] Emergency unlock visible on every lock-type screen (CLAUDE.md, §24).
- [ ] Additive goals only; no "eat less" framing (§24).
- [ ] No internal references (e.g. "spec §5.10") in user-facing text.

## 8. What can't be verified here

- Real locked-app icons (FamilyControls tokens) render only on a device; CI screenshots will use
  placeholder icons.
- Haptics, 120Hz motion feel, the shield extension, widgets on a real Home Screen, Dynamic Island.
- Those need the Mac + device from `docs/PROGRESS.md`. Everything else is checked via CI screenshots.

## 9. Tracking

A new row, "5b · Premium UI pass", goes on `docs/PROGRESS.md` when Phase 0 starts, with a session doc
per phase (`docs/sessions/05b-*.md`). This keeps it separate from Session 5's original scaffolding.
