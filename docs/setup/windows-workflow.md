# Working on ZANO from Windows (no Mac yet)

The app is native Swift/SwiftUI (`docs/spec.md` §12 — deliberately not React Native/Flutter/Expo),
so Xcode is non-negotiable for actually building, running, or testing it, and Xcode is macOS-only.
This doc is the honest map of what that does and doesn't block.

## Safe to do right now, no Mac needed

- **Docs, spec changes, session reports, PROGRESS.md** — all plain text.
- **`project.yml` (XcodeGen config)** — plain YAML, edit freely. Can't run `xcodegen generate` or
  open the result without a Mac, but the config itself is fully reviewable as text.
- **Core Swift Package *source*** (`Core/Sources/Core/**`) — you can write, restructure, and
  review Swift source for anything that's pure logic with no UIKit/SwiftUI/Apple-framework calls
  (e.g. streak math, adaptive-difficulty rules, JSON shapes, pure functions). You cannot compile or
  run it without a Swift toolchain, so treat it as unverified until it's built on a Mac or in CI.
  Don't write SwiftUI views, WidgetKit, HealthKit, CoreNFC, FamilyControls, or anything
  Apple-framework-specific this way with confidence — verify API surfaces against docs, and expect
  first-build fixes.
- **Supabase backend** (`backend/supabase/**`) — SQL migrations, RLS policies, Edge Function
  TypeScript, `config.toml` are all plain text/SQL/TS. You need the `supabase` CLI (+ Docker) to
  actually run these locally, which *does* work on Windows — this is one of the few parts of the
  stack you can fully exercise without a Mac.
- **CI config** (`.github/workflows/*.yml`) — plain YAML, runs on GitHub's macOS runners regardless
  of what you're developing on.
- **ML service** (v3, Python/FastAPI) — plain Python, fully runnable on Windows when that session
  starts.

## Blocked until there's a Mac (and usually a physical iPhone too)

- Generating the actual `.xcodeproj` from `project.yml` and opening it.
- Compiling anything (`xcodebuild`, `swift build` for a target using SwiftUI/UIKit).
- FamilyControls, ManagedSettings, DeviceActivity, HealthKit workouts, Core NFC, Core Motion,
  ActivityKit Live Activities, Controls — **none of these work in the iOS Simulator either**
  (spec §27), so even a Mac alone isn't enough for full verification; most of this app needs a real
  device.
- Filing/testing the Family Controls entitlement.
- TestFlight/App Store submission.

## What this means for pace

Don't block the whole team on the Mac. Sessions 0 (partially), 1 (Supabase/PostHog/Sentry account
wiring), 7 (backend schema/RLS/Edge Functions), and most of 12 (ML service) can make real, verified
progress from Windows right now. Sessions 2–6, 9–11, 13 involve Apple-framework code that can be
*written* here but must be marked `Scaffolded — Unverified` in `docs/PROGRESS.md` until it's built
and run on a Mac + device — don't mark them `Done`.

When a Mac becomes available, start with `docs/setup/mac-setup.md`.
