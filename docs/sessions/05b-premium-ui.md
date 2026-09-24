# Session 05b — Premium UI + UX pass

- **Branch:** `claude/sharp-euler-npwt08`
- **Spec sections:** §15 (design system, amended 2026-09-24), §16 P1/P3/P4/P5, §5.1, §5.15, §5.17, §7, §21
- **Plan:** `docs/design/premium-ui-plan.md`
- **Status:** Compiles + tested in CI (device verification open)
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

### 2026-09-24 — Round 1 CI + round 2 fixes

- **CI:** run 35945717141 (commit 53ce3fe) green on the first try: app build, Core tests, 38
  screenshots. DemoData log confirms 15 sessions / 14 ended / 14 earned in the store.
- **Round 2 (commit 4385ffe), from reviewing those screenshots:** the vault's filled lock watermark
  read as a grey placeholder block → thin outline emblem with a fade; hero gained a line naming what
  the lock waits on; water progress in liters (the ml line truncated); alarm escape dock made opaque
  with a fade (content bled through it, snooze looked clipped; pre-existing); remaining green
  chrome made neutral (lock-set default star/tint, Settings coach-voice selection, share CTAs).
- **Known issues left:** Settings/Fuel got system-level changes only; `ZANOUITests/Flow1PaywallFreePathUITests.swift`
  still targets the removed free path (pre-existing, UI tests are compile-only in CI); workout ring
  is green by spec (§15 ring colors) even though it's not an earned state.
- **Needs verification on:** real device — locked-app icons in the vault (FamilyControls tokens),
  haptics, motion at 120 Hz, shield/widgets.
