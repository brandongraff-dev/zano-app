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
