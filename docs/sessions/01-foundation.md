# Session 1 — Data models (SwiftData), Store, outbox Sync skeleton, PostHog/Sentry

- **Branch:** `main` (see PROGRESS.md branch note — no per-session branches this batch)
- **Spec sections:** §13 (Data Model — frozen shape)
- **Status:** Scaffolded — Unverified
- **Built:** 2026-09-22, via the "Foundation" phase of a background multi-agent workflow (12 build
  agents + 2 harden agents), run before any downstream session so every later cluster could read
  real model files instead of guessing.

## Scope

All 19 SwiftData `@Model` types mirroring `backend/supabase/migrations/0001_init.sql` field-for-
field (Session 0's frozen §13 schema), the App Group `ModelContainer` + `SharedDefaults` wrapper,
an outbox `Sync` skeleton, and PostHog/Sentry wrapper wiring into `App/ZANO/ZANOApp.swift`.

## Files

- `Core/Sources/Core/Models/*.swift` (19 files) — User, Goal, DailyPlan, GoalEvent, LockSet,
  LockSession, TimeBank, Streak, Gym, Meal, Squad, SquadMember, Duel, Badge, Coin, Recap, Nudge,
  RiskScore, Subscription. Real `@Relationship(deleteRule:inverse:)` object graphs, not duplicate
  scalar FK fields. Enums (`GoalType` 14 cases, `VerificationTier`, `GoalEventKind/Source`,
  `CoachVoice`, `PlanTier`, `DailyPlanSource`) use raw values matching the Postgres check
  constraints exactly.
- `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`, `SharedDefaults.swift`
- `Core/Sources/Core/Sync/OutboxEvent.swift`, `SyncEngine.swift`
- `Core/Sources/Core/Analytics/Analytics.swift`, `CrashReporting.swift`
- `App/ZANO/ZANOApp.swift` — PostHog/Sentry setup calls, guarded `#if canImport` since neither SPM
  package is added to `project.yml` yet (see `docs/dependencies.md`)

## Decisions

- `goal_events.meta jsonb` stored as raw `Data` on the model (`metaData`) with a computed
  `JSONValue` accessor, not a recursive Codable enum as the direct SwiftData attribute — judged
  safer without a compiler to verify SwiftData's attribute-typing rules against an open-ended enum.
- `users.referred_by` is a plain `UUID?`, not a `@Relationship` — the referrer's row won't
  generally exist in this device's local (single-user) store.
- Composite uniqueness on `daily_plans(user_id, goal_id, date)` is **not** locally enforced (needs
  iOS 18's `#Unique` macro; `Core/Package.swift` targets iOS 17) — documented inline; whichever
  code writes `DailyPlan` rows must query-before-insert to avoid duplicates.

## Known issues

- **Nothing has been compiled.** No Mac/Swift toolchain exists in this environment — every file
  here is a careful first draft against real, training-known SwiftData/Foundation APIs, unverified
  by an actual `swift build`.
- Flagged mid-build: `@Model` classes are not `Sendable`, and several planned service classes take
  them as `async` function parameters. Resolved organically downstream — 38 files across
  LockEngine/Retention/Social/Intents/Monetization converged on `@MainActor` for their shared
  singleton managers, the standard fix for this pattern. Worth a deliberate second look on a Mac,
  but not an open problem as far as static review can tell.
- PostHog/Sentry calls are real API usage but genuinely inert until those SPM packages are added
  (Session-0 decision, tracked in `docs/dependencies.md`) and real API keys exist.

## Needs verification on

Mac: `swift build --package-path Core` (in particular the `@Relationship` pairs resolving without
macro ambiguity, and a `ModelContainer` including all 19 types actually initializing/persisting).
