# Session 6 — Onboarding + paywall

- **Branch:** `main`
- **Spec sections:** §7 (onboarding flow, 14 screens), §21 (monetization/paywall)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Onboarding" cluster (3 build agents + 1 harden agent).

## Scope

All 14 onboarding screens per §7, the shared flow state driving them, and RevenueCat paywall
wiring.

## Files

- `App/ZANO/Features/Onboarding/Screen1Hook.swift` … `Screen14FirstWin.swift` (14 files)
- `App/ZANO/Features/Onboarding/OnboardingFlowState.swift`, `OnboardingContainerView.swift`
- `Core/Sources/Core/Monetization/RevenueCatManager.swift`, `PaywallViewModel.swift`
- `App/ZANO/Features/Onboarding/PaywallView.swift`

## Decisions

- `OnboardingFlowState` (`@Observable`, `currentScreen: Int` + one property per Q1–Q6 answer) was
  split across two build agents by screen range (1–8, 9–14) with one agent as sole owner of the
  state file, avoiding a two-writer collision on shared state.
- Paywall follows §21's rules exactly: free trial with pre-expiry reminder, annual highlighted,
  visible "Continue with limited free" path, benefit copy meant to echo the user's own onboarding
  answers rather than generic copy.
- `RevenueCatManager` wraps `import RevenueCat` behind the package not existing yet (per
  `docs/dependencies.md`) — real wiring happens once that SPM package is added on a Mac.

## Known issues

- Screens reference `Core/Sources/Core/UI` component names (Design System cluster) that were
  built concurrently — same reconciliation note as `05-design-system.md`.
- The permission-priming screen (12) only primes notifications per §7 — Location/Health requests
  are deferred to gym setup as the spec requires, not requested here.

## Needs verification on

Mac + device: full 14-screen flow navigability, hold-to-commit haptic, FamilyActivityPicker screen
(4) actually invoking the real picker, paywall rendering once RevenueCat is wired with a real API
key and offering.
