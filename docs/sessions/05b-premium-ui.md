# Session 05b — Premium UI + UX pass

- **Branch:** `claude/sharp-euler-npwt08`
- **Spec sections:** §15 (design system, amended 2026-09-24), §16 P1/P3/P4/P5, §5.1, §5.15, §5.17, §7, §21
- **Plan:** `docs/design/premium-ui-plan.md`
- **Status:** In Progress
- **Started:** 2026-09-24
- **Last updated:** 2026-09-24

## Scope

A visual and UX redo of Session 5's screens so ZANO feels like a top-tier app, driven by the
design skills vendored in `.claude/skills/` (see its README). The user skipped the HTML-mockup phase
and asked for the Swift directly, verified through CI screenshots.

Decisions (2026-09-24): palette option A (keep near-black + acid green; green only for earned
states, chrome achromatic); references Spotify (content-first darkness) and Nike (condensed type).

## Definition of done

- Every main tab, onboarding screen and the paywall renders in the new system in CI screenshots.
- Flow fixes decided in the spec are in code: hard paywall (no free path), notification priming
  after the paywall.
- Build green, Core tests green.
- Device-only surfaces (real locked-app icons in the vault, haptics, shield, widgets) listed as
  unverified.

## Log

### 2026-09-24 — Round 1: design system, Today, Lock, Progress, Trophy, onboarding, paywall

- **Files touched:** `Core/Sources/Core/UI/Theme.swift`, `Components/{PrimaryButton,SelectableCard,
  ZanoSurface,HeroGlow,GoalRing,NumeralText,PaywallCard,OnboardingQuestion}.swift`,
  `Copy/{Today,Progress,Paywall,OnboardingReveal,OnboardingPaywallFirstWin,TrophyCosmetics}Copy.swift`,
  `App/ZANO/{ZANOApp,ContentView,ScreenshotGallery}.swift`, `Features/Today/{TodayView,LockVaultCard (new),
  GoalActionList (new)}.swift`, `Features/Lock/LockStatusView.swift`, `Features/Progress/ProgressView.swift`,
  `Features/Trophy/*`, `Features/SunriseAlarm/*`, `Features/Onboarding/*`, `Features/Fuel/FuelView.swift`,
  `Features/Celebration/UnlockCelebrationView.swift`.
- **What changed:**
  - Design system: achromatic chrome (`Colors.interactive`), `PrimaryButton` defaults to a white
    capsule (`.accent` only for earned moments), white selection, tab bar and onboarding progress
    white. Numerals and display type are SF Pro condensed/compressed (heavy, 88pt hero). Eyebrows are
    sentence case (no tracked all caps). New depth levels: `zanoAmbient` (state-driven screen light:
    cool when locked, warming with progress, accent when earned), `zanoHero` (elevated gradient
    surface with a real shadow). Rings: gradient sweep with a lit leading cap. Large navigation
    titles use the same condensed heavy face (UIKit appearance proxy, the only way to set it).
  - Today: the vault hero (`LockVaultCard`) shows the lock as one huge number, the locked apps
    dimmed behind a lock (device only), and a segment per required goal that fills in the goal's
    color. Goals are rows with an in-place action (`GoalActionList`): +25g protein / +250ml water log
    through the App Intents, focus and gym check-in start from their row. Grouped as "To unlock" /
    "Also today". The bottom bar only carries what a row can't (start today's lock, setup, live
    status). Removed the "Log the rest on Fuel" detour.
  - Lock: same vault and rows (read-only), large title, ambient light.
  - Progress / Trophy / Sunrise (helper agent): see the agent summary in the round-1 commit.
  - Onboarding / paywall (helper agent): hard paywall, priming after paywall, visual pass.
- **Decisions made and why:** see `docs/design/premium-ui-plan.md` §3–§5.
- **Known issues / TODOs left behind:** Settings and Fuel only got the system-level changes.
- **Needs verification on:** CI build + screenshots (pending), real device for locked-app icons,
  haptics, 120Hz motion.
