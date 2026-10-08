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

## Log

### 2026-10-06 — Spec 2.2: Family annual plan + free-trial rules (docs only)

- **Files touched:** `docs/spec.md` (§21, §7 screen 12, §16 P5, §28, version line),
  `Core/Sources/Core/Models/Subscription.swift` and `Core/Sources/Core/Monetization/RevenueCatManager.swift`
  (doc comments only: removed the stale Free-tier description, listed the family plan).
- **What changed:** hard paywall kept. Added a Family annual plan ($69.99/yr, test $59.99) as its own
  App Store product with Apple Family Sharing on, in the same subscription group as the individual
  plans. Trial rules: card on file through Apple's introductory offer (no in-app card collection),
  7-day trial on annual and family annual only, reminder 2 days before charge, day-5 "what your trial
  earned you" card.
- **Decisions made and why:** product owner chose the family plan + hard paywall (2026-10-06). Separate
  product because Apple doesn't let Family Sharing be turned off once enabled; one group so there's a single trial per
  Apple ID and individual↔family is an upgrade/downgrade. No-card reverse trial left as a later
  experiment only.
- **Known issues / TODOs left behind:** no code changes yet. The paywall still renders whatever
  packages the offering returns. A family package would currently compete with the individual
  annual for default selection (`PaywallViewModel.defaultSelection` picks the first `.annual`), has no
  copy or "up to 6 people" label, and the day-5 card and reminder notification aren't built.
  Needs a follow-up coding task (proposed, awaiting approval).
- **Needs verification on:** N/A (docs). App Store Connect + RevenueCat product setup once enrolled.

### 2026-10-06 — Family plan + trial reminder + day-5 card (code, superseded on merge)

First built on a branch cut from an older `main`. Its trial reminder (`TrialReminderScheduler`) and
day-5 card (`TrialValueCard`) duplicated `TrialReminder` and `TrialEarnedCard`, which `main` had
already shipped in session 5b, down to the same notification id. Both were dropped when the branch
was merged with `main` on 2026-10-08; see the next entry.

### 2026-10-08 — Merge with main; Family plan on main's paywall

- **Files touched:** `Core/Sources/Core/Monetization/RevenueCatManager.swift` (`SubscriptionPackage.isFamilyShareable`,
  mapped from `StoreProduct.isFamilyShareable`), `Core/Sources/Core/Monetization/PaywallViewModel.swift` (default
  selection skips Family, `displayOrder`), `Core/Sources/Core/Copy/PaywallCopy.swift` (`familyPlanTitle`,
  `familyPeopleLabel`), `App/ZANO/Features/Onboarding/PaywallView.swift` (tiles laid out by `displayOrder`, Family
  title and "Up to 6 people" detail, Family in the DEBUG demo offering for CI screenshots),
  `Core/Tests/CoreTests/FamilyPlanTests.swift` (new), `docs/spec.md` (§21, §7, §16, §28, version 2.2).
- **What changed:** main's paywall shows monthly and annual side by side; the Family plan now follows as a tile with
  its own trial pill. The individual annual stays the default even if the offering lists Family first. Trial
  reminders and the "What your trial earned you" card are main's existing `TrialReminder`/`TrialEarnedCard`,
  unchanged; §21 now describes them.
- **Decisions made and why:** on overlap, main's code wins: it uses the store's real trial end date and
  refreshes on every launch, which the branch's version didn't. Family detected by the product's Family Sharing
  flag rather than a package-ID naming convention.
- **Known issues / TODOs left behind:** App Store Connect needs a `zano_pro_family_annual`-style product with
  Family Sharing on, in the same subscription group, plus a RevenueCat package for it. The paywall still shows a
  trial pill to people who already used their trial (needs RevenueCat's eligibility check).
- **Needs verification on:** CI build + `FamilyPlanTests` + the paywall screenshot (three tiles); device sandbox
  purchase and Family Sharing once Apple enrollment and the products exist.
