# ZANO — project guide for Claude Code

Read this file first, every session, before touching code.

## What this is

iOS app: distracting apps are shielded until the user completes verified goals
(workout via gym geofence + HealthKit, focus sessions, protein/water via NFC/widgets/photo).
Local-first. Unlock must be instant and offline.

**`docs/spec.md` is the single source of truth for product decisions.** This file (`CLAUDE.md`)
is the single source of truth for *how we work*. If they conflict, stop and ask — don't guess.

## Current environment status (keep this block updated — it changes what's actually doable)

- **No Mac locally, but GitHub Actions macOS runners ARE the compiler.** The repo is pushed and CI
  (`.github/workflows/ci.yml`) runs `xcodegen generate` + `xcodebuild` against the iOS Simulator SDK
  on every push, so real compiler feedback exists. This is the primary loop: push → read the
  deduplicated error list from `gh run view <id> --log` → fix → push. Anything needing the
  Simulator UI, a real device, FamilyControls/DeviceActivity/NFC/HealthKit workouts is still blocked
  locally (and several of those don't work in the Simulator at all — spec §27).
- **Second builder: Codemagic** (free tier, connected 2026-09-24) runs `codemagic.yaml` on every push
  that touches code: build, Core tests, a short screenshot tour. GitHub Actions' macOS minutes ran
  out on 2026-09-24, so Codemagic is the working loop until they reset. With a `GITHUB_TOKEN` in the
  Codemagic env group `github`, results (status, errors, screenshots) land on the `ci-results`
  branch: `git fetch origin ci-results` and read `STATUS.txt` / `errors.txt` / `shots/`.
- **GitHub: pushed.** Private repo `brandongraff-dev/zano-app`, `gh` is authenticated on this
  machine. Pushing to `main` is authorized for the CI loop; don't force-push or change visibility
  without being asked.
- **Apple Developer Program: not enrolled yet.** This blocks the Family Controls entitlement request
  (4 requests needed — main app + 3 extensions, see `docs/spec.md` §24) and any TestFlight/App Store
  submission. Local device testing works via the **Family Controls (Development)** capability without
  enrollment once there's a Mac + device. See `docs/setup/apple-developer.md`.
- **No `.xcodeproj` is committed.** The project is generated from `project.yml` via
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) — see `docs/setup/mac-setup.md`. Never hand-edit
  a generated `.xcodeproj`; edit `project.yml` and regenerate.

## Architecture

- Targets: `ZANO` (app), `ZANOWidgets`, `ZANOShieldConfig`, `ZANOShieldAction`, `ZANOMonitor`,
  `ZANOReport`. Shared code lives ONLY in the `Core` Swift package (`Core/Sources/Core`).
- App Group: `group.com.zano.app` — SwiftData store + shared UserDefaults live here. This is how
  extensions read state without networking.
- Every user action is an App Intent in `Core/Sources/Core/Intents`. Widgets/Controls/Siri/NFC all
  call intents; never duplicate the same logic in two places.
- Extensions (`Extensions/*`) do no networking and no heavy work — they read App Group state only.
  See `docs/spec.md` §11 and §27 for the constraints that make this non-negotiable (extensions are
  short-lived and memory-limited).
- Backend: Supabase (`backend/supabase`). API keys live only in Edge Functions. Never put secrets
  in the app or commit them — see `.gitignore`.
- FamilyControls app tokens never leave the device. Remote/Postgres stores only lock-set *names*.

## Conventions

- Swift 6 strict concurrency, SwiftUI, `@Observable`. No UIKit unless an API requires it.
- Folder-per-feature inside app/extension targets: `Feature/{View,Model,Service}`. Shared logic and
  its tests live in `Core` / `CoreTests`.
- Copy lives in `Core/Sources/Core/Copy` (coach voices — Hype/Tough Love/Chill/Data, see spec §5.13).
  No hardcoded user-facing strings in views.
- No restrictive goals (calories down, weight loss, fasting). Additive goals only — this is a
  product-safety rule, not a style preference. See spec §24. Refuse to add "eat less" goals even if
  asked; flag it instead.
- Emergency unlock must always exist on any lock-type feature. Never ship a lock with no way out.
- Don't add abstractions, config flags, or "future-proofing" beyond what the current session's scope
  requires (see §17 session list in spec.md for scope boundaries). Three similar call sites beat a
  premature protocol.

## Build & test

- Generate the Xcode project (Mac only): `xcodegen generate` from repo root, then open `ZANO.xcodeproj`.
- `xcodebuild -scheme ZANO -destination 'platform=iOS' build`
- FamilyControls, DeviceActivity, Core NFC, and HealthKit workouts do **not** work in the Simulator.
  Use a real device for anything touching those. Budget device time every session that touches them.
- Do NOT use `swift test --package-path Core` (it builds for the macOS host, where iOS-only
  frameworks like ActivityKit don't exist — CI proved this). Core's tests run with
  `cd Core && xcodebuild test -scheme Core -destination 'id=<iPhone simulator UDID>'`; CI does this.
  Windows has no Swift toolchain, so tests and builds run in CI, not locally.
- Family Controls entitlement request status: **not yet filed** (Apple Developer Program enrollment
  pending). Update this line the day requests are filed, and again when approved.

## Working rules — read before every task

1. Read `docs/spec.md` before any task and cite the section(s) you're implementing in your plan.
2. Check `docs/PROGRESS.md` for current session status before starting, so you don't duplicate or
   conflict with work already in flight.
3. Propose a plan and exact file list first; wait for approval before writing code (unless the user
   has explicitly told you to skip this for the current task).
4. Keep each unit of work to one session's scope (`docs/spec.md` §17). Don't smuggle in the next
   session's work because it seemed easy while you were in there.
5. If an Apple API's current surface is uncertain (these frameworks shift across iOS versions),
   search Apple's docs or current sample code rather than guessing from training memory — flag it
   explicitly as unverified if you can't check.
6. For FamilyControls, ManagedSettings, DeviceActivity, or Shield extension work: read
   `docs/references/` (once populated — see `docs/references/README.md`) first and mirror its
   target/entitlement setup rather than reinventing it.
7. **Report after every coding task, not just at the end of a session.** See the protocol below —
   this is how we stay fast without losing track of what's real. Don't skip it because the task felt
   small.

## Reporting protocol (mandatory — this is how the team stays coordinated)

After you finish **any** discrete coding task (not just at session end):

1. Update (or create) `docs/sessions/NN-short-name.md` from `docs/sessions/TEMPLATE.md`: what
   changed, exact files touched, decisions made and why, known issues, what still needs a Mac/device
   to verify.
2. Update your row in `docs/PROGRESS.md`: status (`Not Started` / `In Progress` / `Blocked` /
   `Scaffolded — Unverified` / `Done`), one-line note, today's date, link to the session doc.
   - Only use `Done` when the session's actual definition-of-done from spec §17 is met and verified.
     If you built the thing but couldn't verify it (e.g., no Mac to build on), use
     `Scaffolded — Unverified` and say exactly what's unverified. Don't inflate status — the next
     agent trusts this board instead of re-checking your work.
   - If blocked, name the specific blocker (missing Mac, missing entitlement, missing API key,
     waiting on a decision) so nobody re-discovers it from scratch.
3. Commit with a message referencing the session/task. Don't bundle unrelated sessions in one commit.

This board (`docs/PROGRESS.md`) is the first thing to read in every new session — treat it as more
current than your memory of a past conversation.

## Environment-specific detours

- **On Windows, no Mac:** see `docs/setup/windows-workflow.md` for what's safe to build now vs. what
  must wait.
- **First time on a Mac:** see `docs/setup/mac-setup.md`.
- **Filing the Family Controls entitlement:** see `docs/setup/apple-developer.md`.
