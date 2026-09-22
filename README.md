# ZANO

Distracting apps stay locked until you earn them back. Native iOS (Swift/SwiftUI). See
[`docs/spec.md`](docs/spec.md) for the full product spec — it's the single source of truth.

## Start here

1. **`CLAUDE.md`** — how we work: architecture rules, conventions, and the mandatory reporting
   protocol every coding session follows.
2. **`docs/PROGRESS.md`** — live status board. Read before starting anything.
3. **`docs/spec.md`** — the full product/build spec (§17 has the session plan; §18/§19 have
   Claude Code prompt templates, also copied ready-to-use into `docs/prompts/`).

## Current state (2026-09-22)

This repo is freshly scaffolded (Session 0, see
[`docs/sessions/00-repo-and-stack-setup.md`](docs/sessions/00-repo-and-stack-setup.md)) from a
Windows machine with no Mac available yet. That means:

- The Xcode project is **not** committed — it's generated from [`project.yml`](project.yml) via
  [XcodeGen](https://github.com/yonaskolb/XcodeGen). Nobody has run `xcodegen generate` or opened
  it in Xcode yet, so treat the app/extension targets as unverified until a Mac session does that
  (see [`docs/setup/mac-setup.md`](docs/setup/mac-setup.md)).
- The Supabase backend schema (`backend/supabase/migrations/0001_init.sql`) is real, working SQL —
  this part *is* runnable on Windows via the Supabase CLI + Docker.
- Apple Developer Program enrollment is pending — see
  [`docs/setup/apple-developer.md`](docs/setup/apple-developer.md) for what that blocks and what it
  doesn't.

Full picture: [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Repo layout

```
App/ZANO/              Main app target source
Extensions/             ZANOWidgets, ZANOShieldConfig, ZANOShieldAction, ZANOMonitor, ZANOReport
Core/                   Shared Swift package (Models, Store, Intents, Verification, LockEngine,
                         Sync, UI — see Core/Sources/Core/Core.swift for the map)
backend/supabase/       Postgres schema, RLS, Edge Functions
project.yml             XcodeGen config — generates the .xcodeproj, don't hand-edit the project
docs/spec.md            Product & build spec (source of truth)
docs/PROGRESS.md        Live status board — read first
docs/sessions/          One report per build session, updated after every coding task
docs/prompts/           Ready-to-paste Claude Code prompts for each session type
docs/setup/             Environment setup: Mac, Windows-without-a-Mac, Apple Developer
docs/references/        Gitignored — reference repos cloned locally, see docs/references/README.md
```

## Working with Claude Code on this repo

Every session should read `CLAUDE.md` and the relevant `docs/spec.md` sections first, check
`docs/PROGRESS.md` for current status, and — after every coding task, not just at the end — update
its `docs/sessions/NN-*.md` file and `docs/PROGRESS.md` row. This is not optional; it's how the
project stays coherent across many sessions/agents moving fast in parallel. See `CLAUDE.md`
"Reporting protocol" for the exact rules, and `docs/prompts/generic-session.md` for a ready-to-use
kickoff prompt.
