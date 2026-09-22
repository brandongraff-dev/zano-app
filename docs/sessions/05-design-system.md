# Session 5 — Design system + screens

- **Branch:** `main`
- **Spec sections:** §15 (design system), §16 (mockup descriptions used as screen references)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, "Design System" cluster (3 build agents + 1 harden agent).

## Scope

`Theme.swift` with §15's exact tokens, every component in §15's component list, and the Today,
Lock, Fuel, Progress, and Settings screens built from them.

## Files

- `Core/Sources/Core/UI/Theme.swift`
- `Core/Sources/Core/UI/Components/*.swift` (GoalRing, RingCluster, LockStatusCard, StreakPill,
  TimeBankBar, PrimaryButton, ShieldPreview, GoalRow, RecapCard, ShareCard)
- `Core/Sources/Core/UI/PreviewCatalog.swift`
- `App/ZANO/Features/Today/TodayView.swift`, `Lock/LockStatusView.swift`,
  `Fuel/FuelView.swift`, `Progress/ProgressView.swift`, `Settings/SettingsView.swift`

## Decisions

- Token values taken verbatim from §15 (background `#0A0A0B`, accent `#B8FF3C` as the one accent,
  radii 12/20/28, spacing 4/8/12/16/24/32, per-goal ring colors).
- `PrimaryButton` includes the hold-to-commit variant (2s press + haptics) needed by onboarding's
  commitment screen, built here since it's a Theme component, not onboarding-specific.
- `ShareCard` renders via `ImageRenderer` to produce the 9:16 exportable format multiple other
  features (Weekly Recap, Locked-Out moment) depend on.
- Screens that reference not-yet-built sibling features (e.g. Today referencing lock-session
  state) call the CONTRACTS-level API shapes rather than waiting — see other session docs for
  where those land.

## Known issues

- The two other clusters that build screens referencing these components (Onboarding, Share
  cards) ran concurrently with this one in the pipeline — some prop/initializer names may need
  reconciling on first Mac build even though this cluster's harden pass cross-checked what it could
  see at the time.
- `PreviewCatalog.swift` exists precisely so a Mac session's first real feedback loop is fast:
  open it, see every component in light/dark immediately.

## Needs verification on

Mac (SwiftUI preview is enough for most of this, no device required): every component's actual
render, dark/light mode correctness, that `PreviewCatalog` compiles and shows everything.
