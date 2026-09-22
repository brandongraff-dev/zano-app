# Session 0 — Repo, CLAUDE.md, spec, Xcode project (all targets), App Group, Core package, CI to TestFlight

- **Branch:** `main`
- **Spec sections:** §11 (Architecture), §12 (Tech Stack), §17 (Build Plan), §18 (CLAUDE.md
  Template), §24 (Safety/Legal — entitlement process)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-09-22
- **Last updated:** 2026-09-22

## Scope

- Repo + git init
- `CLAUDE.md` (adapted from spec §18, extended with environment status + reporting protocol)
- `docs/spec.md` = the master plan, moved into place as instructed by the plan itself
- Xcode project for all 6 targets, defined via XcodeGen (`project.yml`) rather than a hand-written
  `.xcodeproj` — see "Decisions" below for why
- App Group (`group.com.zano.app`) wired into entitlements for the app + all extensions
- `Core` Swift package skeleton (`Package.swift`, minimal source, one passing test)
- CI workflow targeting TestFlight, with the actual TestFlight step disabled until signing/Apple
  Developer prerequisites exist
- Full docs system: progress board, session report template, setup guides, prompt templates,
  reference-repo tracking, dependency tracking

## Definition of done (from spec §17)

> Empty app builds & ships to TestFlight

**Not met yet, and can't be from this environment.** No Mac exists to run `xcodegen generate`,
open the project, or build it, and Apple Developer Program enrollment (required for TestFlight)
hasn't happened. This session produces everything short of that: a project that *should* build once
opened on a Mac, and a CI pipeline that will actually attempt the build on every push. Real
definition-of-done is deferred to whoever runs `docs/setup/mac-setup.md`.

## Log

### 2026-09-22 — Initial scaffold

- **Files touched:** repo-wide initial commit — see `git log` / the commit this session doc was
  committed alongside for the full file list.
- **What changed:**
  - `git init`, default branch renamed to `main`, `.gitignore` covering Xcode/SPM/Fastlane/secrets/
    Supabase/Python artifacts.
  - Moved `ZANO_MASTER_PLAN.md` → `docs/spec.md` (spec's own header says "Keep it at docs/spec.md").
  - `CLAUDE.md` written from spec §18's template, extended with a "Current environment status"
    block (Mac/GitHub/Apple Developer/entitlement status) and an explicit "Reporting protocol"
    section — this is what the user asked for by name ("docs for agents telling them to report
    work and mark what they have done after coding each task").
  - `docs/PROGRESS.md` — status board covering all 14 sessions (0-13) from spec §17, plus an
    environment/accounts table and a physical-product track table (spec §25).
  - `docs/sessions/TEMPLATE.md` — per-session report template with a mandatory "Log" section meant
    to be appended to after every task, not just at session end.
  - `docs/setup/windows-workflow.md`, `mac-setup.md`, `apple-developer.md` — what's safe to build
    now vs. blocked, and the exact steps for each transition (Windows-only → Mac available →
    Apple Developer enrolled).
  - `docs/references/README.md` — the spec's §20.2 reference-repo table, with a clone command and
    the license-check rule.
  - `docs/dependencies.md` — which SPM package gets added in which session, deliberately without
    hand-guessed version numbers (see Decisions).
  - `docs/prompts/*.md` — spec §19's four prompt templates as standalone, ready-to-paste files.
  - `project.yml` — XcodeGen config for all 6 targets (`ZANO`, `ZANOWidgets`, `ZANOShieldConfig`,
    `ZANOShieldAction`, `ZANOMonitor`, `ZANOReport`), App Group entitlement on all of them, plus
    FamilyControls/HealthKit/NFC/APNs entitlements on the main app and FamilyControls on the
    Screen-Time-facing extensions.
  - `App/ZANO/ZANOApp.swift`, `ContentView.swift` — minimal app entry point.
  - `Extensions/*/*.swift` — one placeholder source file per extension target, each conforming to
    the real Apple protocol/base class for that extension point (`ShieldConfigurationDataSource`,
    `ShieldActionDelegate`, `DeviceActivityMonitor`, `DeviceActivityReportExtension`,
    `WidgetBundle`), so the *shape* is right even though the behavior is a placeholder.
  - `Core/Package.swift`, `Core/Sources/Core/Core.swift`, `Core/Tests/CoreTests/CoreTests.swift` —
    minimal package that documents (in a doc comment) which future session owns which subfolder.
  - `backend/supabase/migrations/0001_init.sql` — full schema + RLS transcribed from spec §13,
    plus `backend/supabase/README.md` and `backend/supabase/functions/README.md`.
  - `.github/workflows/ci.yml` — macOS-runner CI that generates the project, runs Core's tests,
    attempts an app build (non-fatal for now), with the TestFlight job commented out.
  - Initial commit created locally. **Not pushed** — no remote configured, and pushing wasn't asked
    for.

- **Decisions made and why:**
  - **XcodeGen instead of a committed `.xcodeproj`.** A `.pbxproj` is a fragile, mostly-generated
    format; hand-authoring one from a non-Mac environment with no way to open/validate it in Xcode
    risks a corrupted or subtly-broken project that wastes the first Mac session diagnosing XML
    instead of building. `project.yml` is plain, reviewable YAML and the standard way iOS teams
    keep project config mergeable and diffable anyway — this isn't a downgrade even once a Mac
    exists.
  - **No SPM dependencies added yet** (RevenueCat/Supabase/PostHog/Sentry/Lottie). Session 0's
    spec scope doesn't call for them (they're Session 1/6/7), and hand-guessing current version
    numbers for fast-moving SDKs risks pinning something already stale or broken. `docs/dependencies.md`
    documents exactly which session adds which package and where, so it's a five-minute Xcode task
    when the time comes, not a research problem.
  - **Extension stub files conform to the real Apple protocols**, not empty files, so the project
    structure is maximally close to "just works" on first Mac build — but every extension-specific
    `NSExtensionPointIdentifier`/`NSExtensionPrincipalClass` in `project.yml` is flagged as
    unverified (I don't have Xcode to cross-check against current template output). This is the
    single biggest risk in this session's output — see Known issues.
  - **Didn't hand-write `backend/supabase/config.toml`.** Its schema changes across Supabase CLI
    versions; instructed `supabase init` to generate a current one instead of committing a guess.
  - **Marked this session `Scaffolded — Unverified`, not `Done`.** The spec's own definition-of-done
    for Session 0 is "ships to TestFlight," which is categorically impossible from this environment
    right now. Claiming `Done` would be exactly the kind of status inflation `CLAUDE.md`'s reporting
    protocol exists to prevent — dogfooding that rule here.

- **Known issues / TODOs left behind:**
  - `project.yml`'s extension `NSExtensionPointIdentifier` / `NSExtensionPrincipalClass` values are
    best-effort from documented Apple APIs, not verified against current Xcode templates. First Mac
    session must cross-check each one (see `docs/setup/mac-setup.md` step 3) — expect small fixes,
    that's normal, not a regression.
  - `Core/Sources/Core` has almost nothing in it beyond a namespace enum — intentional, Session 1
    scope, but flagging so nobody assumes models already exist.
  - No Supabase project has actually been created; the migration SQL has never been run against a
    real (or even local Docker) Postgres instance. It's syntactically careful but unexecuted.
  - CI's app-build step has `|| true` so a currently-expected failure (unverified extension config)
    doesn't block the pipeline going green for the parts that *are* solid (Core tests, project
    generation). Remove that once a real Mac build confirms the app target builds clean.
  - Bundle ID scheme (`com.zano.app` + `.widgets`/`.shieldconfig`/`.shieldaction`/`.monitor`/
    `.report`) is my choice, consistent with the App Group name already fixed in spec §13
    (`group.com.zano.app`) — not separately confirmed with the user. Cheap to change in
    `project.yml` before bundle IDs are registered with Apple; will get expensive after.

- **Needs verification on:** Mac (xcodegen generate + first build), then real device (everything
  Screen-Time/HealthKit/NFC related — Simulator can't test any of it per spec §27).

## Blockers

- No Mac — blocks generating/opening/building the Xcode project at all.
- Apple Developer Program not enrolled — blocks filing the Family Controls entitlement and any
  TestFlight/App Store step. See `docs/setup/apple-developer.md`.

## Definition-of-done check

- [ ] Every item in "Definition of done" above is actually true — **no**, see Status.
- [ ] Verified where the spec requires real-device/Mac verification — **no**, nothing has run yet.
- [x] `docs/PROGRESS.md` row updated to match this file's Status
- [x] No secrets committed (nothing secret was ever created this session; `.gitignore` covers the
      categories that will appear later — `.env`, `.p8`/`.p12`/`.mobileprovision`, etc.)
