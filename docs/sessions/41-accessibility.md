# Session 41 — Accessibility pass (VoiceOver, Dynamic Type, Reduce Motion)

- **Branch:** worktree branch based on `origin/claude/dazzling-hypatia-ed6q5d` at `42fdb5a` (sessions 33-40 merged, CI run 147 green)
- **Spec sections:** §15 (design system: motion rules, type, components), §24 (emergency access: "never trap users"; the emergency unlock keeps its deliberate friction)
- **Status:** Scaffolded — Unverified (written without a Swift toolchain; needs a CI compile, then a VoiceOver walk, a Dynamic Type check at AX1-AX5 and a Reduce Motion check on a device or the Simulator)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

`docs/launch/final-checklist.md` §C, "A final accessibility pass": VoiceOver labels on the new tiles and
cards, Dynamic Type at the largest sizes, Reduce Motion. Audited `App/ZANO/Features/**` (priority: Today,
Lock incl. `EmergencyUnlockControl`, Fuel, Progress incl. the weekly recap card, Settings incl. the Account
section and the Strava row, Onboarding, Paywall), `Core/Sources/Core/UI/Components` and
`Extensions/ZANOWidgets`. Changes are modifiers only (no view restructuring), mirroring patterns the repo
already uses (`.accessibilityHidden(true)` on decorative glyphs inside button labels and combined rows,
`.isHeader`, `.dynamicTypeSize(...DynamicTypeSize.accessibility1)`, `value: reduceMotion ? 0 : tick` on
symbol effects, `withAnimation(reduceMotion ? nil : ...)`).

## Definition of done

- Every interactive control on the main flows has a spoken label; decorative art is hidden; tiles and
  cards read as one element with label and value; selection states carry `.isSelected`.
- Main flows stay usable at the largest accessibility text size (no clipped buttons or labels).
- Looping or celebratory motion is off or reduced under Reduce Motion.
- The emergency unlock is operable with VoiceOver and still asks for the full deliberate wait.

## What the audit found first

The app was already in good shape: about 190 `.accessibilityElement`, 220 `.accessibilityHidden`, 160
`.accessibilityLabel` and 140 Reduce Motion checks before this session. Every looping animation (aurora,
mascot body language and sparks, living mark, celebration stage, sun character breathe, NFC ring, buddy idle
bob) already pauses or freezes under Reduce Motion; every buddy/Cal/sun sprite is decorative and hidden;
goal rings, the Time Bank bar, streak pill, recap stats, rank card, trophy shelf and Fuel meters already
speak one label + value. So this pass is a set of small gap fixes, not a rewrite.

## Log

### 2026-10-08 — Accessibility gap fixes

- **Files touched (all modified):**
  - `App/ZANO/Features/Today/TodayView.swift`
  - `App/ZANO/Features/Lock/EmergencyUnlockControl.swift`
  - `App/ZANO/Features/Fuel/Components/FuelMeterCards.swift`
  - `App/ZANO/Features/Progress/ProgressView.swift`
  - `App/ZANO/Features/Settings/SettingsView.swift`
  - `App/ZANO/Features/Settings/SettingsSupportViews.swift`
  - `App/ZANO/Features/Goals/View/GoalTypePickerSheet.swift`
  - `App/ZANO/Features/Onboarding/OnboardingContainerView.swift`
  - `App/ZANO/Features/Onboarding/OnboardingPlayKit.swift`
  - `App/ZANO/Features/Onboarding/Screen10PlanReveal.swift`
  - `App/ZANO/Features/Onboarding/PaywallView.swift`
  - `App/ZANO/ZanoTabBar.swift`
  - `Core/Sources/Core/UI/Components/PrimaryButton.swift`
  - `Core/Sources/Core/UI/Components/RecapCard.swift`
  - `Core/Sources/Core/Copy/WidgetCopy.swift`
  - `Extensions/ZANOWidgets/LiveActivities/ZANOFocusLiveActivity.swift`
  - `Extensions/ZANOWidgets/LiveActivities/ZANOGymDwellLiveActivity.swift`
- **What changed:**
  - VoiceOver (10):
    - Today bottom bar status row (`TodayStatusRow`): the SF Symbol is hidden; the row combines its
      children, so "Timer" / "Location" was read before the title.
    - Paywall plan tile: the radio glyph is hidden (the `.isSelected` trait already says it).
    - Settings > Health pause length rows: the checkmark is hidden (the row has `.isSelected`).
    - Settings choice tiles (coach voice, appearance): the icon is hidden so the button reads its title only.
    - Onboarding `OnboardingKit.DisplayTitle` (First Win, widget prompt, Plan reveal headlines) is a heading.
    - Plan reveal "building your plan" title is a heading.
    - Weekly recap card (`RecapCard`, Progress): the week label is a heading.
    - Focus Live Activity: the progress bar has a label ("Focus progress"; value spoken as a percentage).
      New copy `WidgetCopy.focusProgressAccessibilityLabel`.
    - Gym dwell Live Activity: both progress bars are hidden; the status line next to them already says
      the minutes in words.
    - Emergency unlock: `.updatesFrequently` while the countdown runs, so a focused VoiceOver user hears the
      seconds-left value refresh.
  - Dynamic Type (5):
    - `PrimaryButton` (every primary CTA): the title may wrap to two lines at accessibility sizes instead of
      truncating (the button already grows from `minHeight`). Same `lineLimit(isAccessibilitySize ? 2 : 1)`
      pattern as `GoalActionList`.
    - `RecapCard` stat unit line ("apps stayed locked"): `lineLimit(2)` instead of 1.
    - Settings choice tile titles (four tiles share an ~80pt row): capped at `accessibility1`.
    - Onboarding charge button (fixed 64pt capsule, one-line title): label capped at `accessibility1`.
    - Glass tab bar selected title: capped at `xxxLarge`; the bar already has the Large Content Viewer.
  - Reduce Motion (4):
    - Progress streak flame bounce, Fuel meter header bounce and Fuel camera/barcode sticker bounce now use
      `value: reduceMotion ? 0 : tick` (the pattern `ZanoSticker` and the tab bar use).
    - Goal target stepper in the add-goal sheet: `withAnimation(reduceMotion ? nil : springStandard)`.
- **Decisions made and why:**
  - **Emergency unlock left as is (no new action added).** It already has a VoiceOver path: double-tap
    starts the same 60-second countdown in `EmergencyUnlock` (Core) and a second double-tap stops it, with
    announcements for started / stopped / done / failed, a label, a hint and a seconds-left value. The wait
    is the friction, so VoiceOver users get the same deliberate step as touch users. Adding an
    `.accessibilityAction(named:)` that skipped the wait would weaken it, so nothing was added beyond
    `.updatesFrequently`.
  - New copy went into the existing `WidgetCopy` (the Live Activities' copy area), not a new `Copy.a11y`
    area: every feature already keeps its own spoken strings next to its visible ones.
  - Caps (`dynamicTypeSize(...)`) only on fixed-size chrome (tab bar, 64pt charge capsule, 4-up tiles);
    body text and CTAs grow instead.
- **Known issues / TODOs left behind:** see "Findings not changed" below.
- **Needs verification on:** CI compile first; then Simulator (Accessibility Inspector + VoiceOver, Dynamic
  Type AX1-AX5, Reduce Motion) and a device for the Live Activities and the emergency unlock with VoiceOver.

## Findings not changed (and why)

1. **Widgets and Live Activities use fixed `.font(.system(size:))`** throughout
   (`Extensions/ZANOWidgets/HomeWidget/ZANOHomeWidget.swift`, `TimeBankWidget/ZANOTimeBankWidget.swift`,
   `Support/ZANOWidgetComponents.swift`, the focus banner's 34pt countdown). The system widgets scale a
   little with Dynamic Type; ours don't. Switching them to text styles risks overflowing the small and
   accessory families, which can only be judged by looking at them. Needs a widget-gallery pass in the
   Simulator at large sizes.
2. **Share posters, the Earned It clip and recap story pages** (`Share/SharePoster.swift`,
   `Share/EarnedItClip.swift`, `Share/RecapStoryPages.swift`) use fixed sizes on purpose: they render a
   fixed 9:16 image (`.dynamicTypeSize(.large)` pins them). Not changed.
3. **Paywall price** (`PaywallView.swift`, plan tile) is a fixed 24pt with `minimumScaleFactor(0.55)`; it is
   designed to never truncate in a two-tile row. It does not grow with Dynamic Type. A `@ScaledMetric` with
   a cap would be nicer; left alone because the paywall is review-sensitive and needs a visual check.
4. **Icon glyphs inside fixed frames** (`.font(.system(size:))` on SF Symbols inside a fixed circle: Progress
   streak flame, stretch timer result, gym check-in seal, vault padlock, goal ring centres) stay fixed; the
   words beside them scale. Intentional.
5. **Focus Live Activity paused countdown** is `String(format: "%02d:%02d")`; VoiceOver may read "12:30" as a
   clock time. A spoken "12 minutes 30 seconds" label needs new copy and a check on device.
6. **Strava screen** (`Strava/StravaConnectView.swift`): an error message appears below the button but is
   not announced. Posting an announcement is a behaviour change, not a modifier; left for the Strava
   follow-up together with the official Strava button artwork.
7. **Symbol effects** (`.symbolEffect(.bounce)`): Apple may already tone these down under Reduce Motion
   (unverified); the repo gates them explicitly anyway, and the four ungated ones are now gated. The
   `Screen4AppSelection` "+" slot bounce is already gated at its trigger (`plusBounce` only grows when
   Reduce Motion is off).
8. **Today ghost row** reads the comparison headline but not the two bare scores; the headline already says
   who is ahead. Not changed.

## Unsure to compile (check on the first CI run)

- `App/ZANO/Features/Lock/EmergencyUnlockControl.swift`: the second `.accessibilityAddTraits(phase == .holding ? .updatesFrequently : [])`
  (same ternary shape as the repo's `isSelected ? .isSelected : []`).
- `Core/Sources/Core/UI/Components/PrimaryButton.swift`: new `@Environment(\.dynamicTypeSize)` and
  `.lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)` (same as `GoalActionList.swift:278`).

## Definition-of-done check

- [ ] VoiceOver walk of Today, Lock (incl. emergency unlock start/stop/complete), Fuel, Progress, Settings,
      Onboarding, Paywall on a device or the Simulator
- [ ] Dynamic Type AX1-AX5 on the same screens (CI screenshot tour could add an AX5 pass)
- [ ] Reduce Motion on: no looping motion on Today, Lock, onboarding, celebration
- [ ] `docs/PROGRESS.md` row (not edited by this session, by request)
- [x] No secrets committed
