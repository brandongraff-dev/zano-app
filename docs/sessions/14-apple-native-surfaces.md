# Session 14 — Apple-native design redo (Session 5 follow-up, steps 1–3)

- **Branch:** `claude/sweet-mayer-a9hzwo`
- **Spec sections:** §15 (Design System & UI Direction), §16 (style direction)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-06
- **Last updated:** 2026-10-06

## Scope

The user felt the dark UI had an "AI-generated" look and asked for it to feel like Apple built it:
still playful, but professional and clean. They kept the lime accent, to be used more rarely. The
redo is split into three steps:

1. **Tokens + surfaces (this doc):** palette, cards, glows, default button, tints.
2. **Icons + symbol effects + materials:** see the second log entry below.
3. **Motion + haptics:** see the third log entry below.

## Definition of done (step 1)

- Neutrals match Apple's dark grouped palette everywhere (app, widgets, watch).
- No resting glow, outline or tinted wash on ordinary cards; accent appears only on earned moments.
- CI builds and the screenshot gallery shows the new look on every screen.

## Log

### 2026-10-06 — Step 1: tokens and surfaces

- **Files touched:**
  - Tokens: `Core/Sources/Core/UI/Theme.swift`, `Extensions/ZANOWidgets/Support/ZANOWidgetColor.swift`,
    `Watch/ZANOWatch/WatchTheme.swift`, `docs/spec.md` (§15)
  - Components: `ZanoSurface.swift`, `PrimaryButton.swift`, `IconBadge.swift`, `GoalRing.swift`,
    `TimeBankBar.swift`, `ShieldPreview.swift` (all in `Core/Sources/Core/UI/Components/`)
  - Screens: `App/ZANO/ContentView.swift`; `Features/Lock/LockStatusView.swift`;
    `Features/Progress/ProgressView.swift`; `Features/Settings/SettingsView.swift`;
    `Features/Trophy/{TrophyCaseView,CosmeticsShopView}.swift`;
    `Features/LockSetup/{LockSetupView,AlwaysAllowedWarningView}.swift`;
    `Features/Celebration/UnlockCelebrationView.swift`;
    `Features/SunriseAlarm/BedtimeGateSetupView.swift`; and in `Features/Onboarding/`:
    `OnboardingContainerView`, `PaywallView`, `Screen1Hook`, `Screen4AppSelection`,
    `Screen5PhoneTime`, `Screen8CoachVoice`, `Screen9WakeUp`, `Screen10PlanReveal`,
    `Screen11Commitment`, `Screen12PermissionPriming`, `Screen14FirstWin`.
- **What changed:**
  - Palette: background `#0A0A0B` → `#000000`, surface `#141416` → `#1C1C1E`, surface-2
    `#1C1C1F` → `#2C2C2E` (Apple `systemBackground` / `secondarySystemGroupedBackground` /
    `tertiarySystemGroupedBackground`, dark). The widget and watch mirrors were updated to match.
  - `zanoCard`: flat fill only. The 1px edge is drawn only under Increase Contrast. The outer glow
    is gone. The `tint` wash now draws only when `active` (earned card, or warning card).
  - `PrimaryButton`: new `.neutral` tint (white fill, black label) is now the **default**. `.accent`
    is explicit and used only on the unlock-celebration dismiss and first-win done CTAs. Removed the
    specular rim and the pressed glow (a flat capsule, like `.borderedProminent`).
  - `IconBadge`: neutral `surface2` disc with a hierarchical tinted glyph, instead of a
    tinted-wash disc.
  - Glows removed: backdrops on the onboarding hook, paywall, lock-setup empty state, shield preview,
    coach voice, permission priming, plan reveal, wake-up (red top glow), and the two pre-win
    first-win phases. Shadows removed from the Lock hero numeral, onboarding progress bar, wake-up
    bars, progress-calendar head/badges and the Time Bank bar. `GoalRing` glows only once complete.
    Glows that remain are all earned moments: Today/Lock backdrops when a balance is spendable or all
    goals are done, the hook halo after the padlock opens, commitment once committed, the first-win
    payoff, the wake-up reclaim, and earned trophies.
  - Tint: app root (`ContentView`) and the screens that set their own root tint (Settings, Trophy,
    Cosmetics, LockSetup) now use white, so the tab bar, toolbar buttons and sliders are neutral.
    The onboarding progress fill is white. The bedtime wind-down `Toggle` gets an explicit accent
    tint (white-on-white would hide the knob). The alarm toggle already had `warning`.
- **Decisions made and why:**
  - Apple's exact grouped hexes instead of a tuned near-black, so ZANO surfaces meet system sheets,
    alerts and the tab bar without a seam.
  - "Accent = earned" is enforced by defaults (button, tint, cards), not by convention, so new
    screens get the quiet look automatically.
  - The `AccentColor` asset stays lime: it drives system surfaces outside SwiftUI's `.tint` (for
    example alert buttons and the FamilyActivityPicker), where lime still reads as the brand.
- **Known issues / TODOs left behind:**
  - Contrast figures in `Theme.swift` doc comments were measured on the old neutrals (the header
    says so). Text ratios only improve on true black. The white-overlay neutrals (`hairline`,
    `track`) read slightly lighter on `#1C1C1E`. Re-measure if any visual feels off.
  - `accentWash` / `accentDim` were tuned against `#0A0A0B`. They still read correctly but may want
    a one-value retune once seen on device.
  - `landing/style.css` still uses the old neutrals. It is out of scope for the app; update it if
    the site should match.
  - `HeroGlow` / `OnboardingKit.Glow` are still general-purpose. Call sites now limit them to
    earned moments, by convention.
- **Needs verification on:** CI build + screenshot gallery (workflow_dispatch on this branch), then
  real device (OLED true black, tint inheritance into sheets).

### 2026-10-06 — Step 2: icons, symbol effects, materials

- **Files touched:** `Core/Sources/Core/UI/Theme.swift` (new `Theme.Symbols`),
  `Core/Sources/Core/UI/Components/{ZanoSurface,GoalRing,GoalRow,StreakPill,LockStatusCard,TimeBankBar,StickyActionBar}.swift`,
  `App/ZANO/Features/Today/TodayView.swift`, `App/ZANO/Features/Fuel/FuelView.swift`,
  `App/ZANO/Features/Progress/ProgressView.swift`, `App/ZANO/Features/Trophy/TrophyCaseView.swift`,
  `App/ZANO/Features/Onboarding/{PaywallView,Screen2SocialProof,Screen3MainGoal,Screen14FirstWin}.swift`.
- **What changed:**
  - `Theme.Symbols.goal(_:)` is now the one goal-type → SF Symbol map. It replaces six hand-copied
    switches that had already drifted. New glyphs: gym = `figure.strengthtraining.traditional`,
    focus = `brain.head.profile`, sleep = `bed.double.fill`, meal prep = `frying.pan.fill`, cold
    shower/sauna = `shower.fill` (it used to share `snowflake` with the frozen streak), custom =
    `sparkles`.
  - Symbol reactions, all Reduce-Motion gated: a ring's center glyph bounces once when the ring
    closes (`GoalRing`), the row checkmark bounces once on completion (`GoalRow`), and the Time
    Bank hourglass pulses only while the balance is low. The streak flame uses SF multicolor
    (orange/yellow) instead of the lime. Hierarchical rendering on ring glyphs.
  - `LockStatusCard` locked padlock is `textSecondary`, not red (spec §15: locked reads calm).
  - Materials: new `zanoGlass(in:)` (Liquid Glass on iOS 26, `.ultraThinMaterial` before) for
    floating chrome; Today's bottom status capsule ("focus running" etc.) uses it.
    `StickyActionBar` is now a progressive blur (material masked by a fade, plus a light darkening
    gradient). New `zanoSheetBackground()`: the system glass sheet on iOS 26, `.regularMaterial`
    before. Applied to Fuel's two half-height sheets, whose opaque black fill was removed.
  - Numerals were already SF Pro Rounded (`Theme.Typography.numeral*`); no change needed.
- **Decisions made and why:** content cards stay opaque, and glass is only for the floating layer,
  per Apple's own rule for Liquid Glass. The timer-style status row is white, not lime (a running
  timer is not earned).
- **Known issues:** `glassEffect` and `brain.head.profile` / `frying.pan.fill` rendering are
  unverified until CI screenshots and a device. Sheet tint/material inheritance through
  `NavigationStack` is unverified on iOS 17/18.
- **Needs verification on:** CI build + screenshots, then device.

### 2026-10-06 — Step 3: motion

- **Files touched:** `Core/Sources/Core/UI/Components/ZanoMotion.swift` (new),
  `Core/Sources/Core/UI/Theme.swift`, `Core/Sources/Core/UI/Components/TimeBankBar.swift`,
  `App/ZANO/Features/Today/TodayView.swift`, `App/ZANO/Features/Progress/ProgressView.swift`,
  `App/ZANO/Features/Trophy/TrophyCaseView.swift`,
  `App/ZANO/Features/Onboarding/{OnboardingContainerView,Screen1Hook}.swift`, `docs/spec.md` (§15).
- **What changed:**
  - `Theme.Motion.ringFill` is a spring (`response 0.7, damping 0.78`) instead of a 600ms
    ease-out, so rings and bars close with a small physical settle, like Activity's. The
    Time Bank and onboarding bars clip to their track so the overshoot never pokes out.
  - Zoom navigation (iOS 18+, a normal push on 17): Today's hero card → Lock screen, Progress's
    Trophy Case link → Trophy Case, Trophy Case's shop row → Cosmetics shop. Implemented as
    `zanoZoomSource(id:in:)` / `zanoZoomDestination(id:in:)`.
  - `zanoScrollSettle()`: top-level cards ease to 96% scale / 65% opacity as they leave the scroll
    edge (off under Reduce Motion). Applied to Today and Progress top-level sections.
- **Already in place, verified by reading (no change):** the unlock celebration's full choreography
  (seal → open padlock, ring close, particle burst, count-up, success haptic, all within 1.2s,
  Reduce Motion-aware), success haptics on Fuel logs, goal completion, hold-to-commit and lock
  transitions.
- **Known issues:** the zoom transitions and scroll settle can only be judged on a device or
  Simulator (the CI screenshots are static). Screen1Hook's unlock beat still waits a fixed 0.6s,
  while the spring reaches visually full at about 0.6–0.7s and settles a little later.
- **Needs verification on:** CI build, then Simulator/device for feel.

### 2026-10-06 — CI round 1 fix

- CI run 37482486400 failed with two errors, both on `glassEffect` in `ZanoSurface.swift`. CI's
  Xcode predates the iOS 26 SDK. The call is now behind `#if compiler(>=6.2)`, so CI builds always
  use `.ultraThinMaterial`; Liquid Glass compiles only under Xcode 26. Core failing to compile means
  App-target errors (if any) surface on the next run.
