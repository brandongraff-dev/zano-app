# Session 14 — Apple-native surfaces (Session 5 design redo, step 1 of 3)

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
2. Icons + symbol effects (`GoalRing`, `GoalRow`, `StreakPill`, `LockStatusCard`, `TimeBankBar`,
   Today/Lock/Fuel), not started.
3. Motion + haptics (spring tokens, zoom navigation transitions, scroll transitions, the unlock
   sequence, Reduce Motion coverage), not started.

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
