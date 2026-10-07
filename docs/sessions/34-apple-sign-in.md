# Session 34 — Sign in with Apple + Supabase auth, backend features switched on by keys

- **Branch:** `worktree-agent-a3f9316c856a6b511` (based on `origin/main` at `c586ea9`)
- **Spec sections:** §11 (Architecture: "Auth (Sign in with Apple)"), §13 (data model, `users` row per
  auth user), §5.7 (Squads), §5.23 (Family Link), §5.31 (Household), §9.5 (Meal Vision), §24 (App Review)
- **Status:** Scaffolded — Unverified (awaiting CI; nothing here has run against a live Supabase project or
  on a device)
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

Finish the auth half of Session 7 (`07-backend.md`: "Anonymous → Sign in with Apple account linking... is
not built") and `docs/launch/supabase-setup.md` step 9: once the founder adds a Supabase URL + anon key to
the build, every backend-dependent feature that has a server side works with no further code change. With no
keys the app behaves exactly as before (App Review 2.1: nothing visible that doesn't work).

## Definition of done

- With no keys: no Account section, no Household / Family Link / Squad, no Supabase network calls.
- With keys: Settings > Account offers Sign in with Apple; signed in, Household and Family Link appear,
  meal-photo estimates work, sync pushes/pulls; sign out and delete account work; tokens refresh.
- Verified on a device against a live project (open: see "Needs verification").

## Log

### 2026-10-07 — Auth module, wiring, Settings > Account, delete-account function, build keys

- **Files touched:**
  - New `Core/Sources/Core/Auth/BackendAvailability.swift` (`BackendAvailability` + `@MainActor @Observable AccountStatus`)
  - New `Core/Sources/Core/Auth/AppleSignInNonce.swift`
  - New `Core/Sources/Core/Auth/SupabaseAuthClient.swift` (`SupabaseSession`, `SupabaseAuthError`, GoTrue REST client)
  - New `Core/Sources/Core/Auth/SupabaseSessionStore.swift` (`SupabaseSessionStoring`, `KeychainSessionStore`)
  - New `Core/Sources/Core/Auth/SupabaseAuthSession.swift` (actor; the real `SupabaseAuthTokenProviding`)
  - New `Core/Sources/Core/Auth/BackendConnections.swift` (`connect()`, `syncIfSignedIn()`)
  - New `Core/Sources/Core/Social/SquadAvailability.swift`
  - New `Core/Sources/Core/Copy/AccountCopy.swift` (`Copy.account`)
  - New `Core/Tests/CoreTests/AuthTests.swift` (23 tests)
  - New `backend/supabase/functions/delete-account/index.ts`
  - Modified `Core/Sources/Core/Sync/SupabaseSyncBackend.swift` (protocol gains `hasSupabaseSession()` with a default)
  - Modified `Core/Sources/Core/Verification/MealVisionClient.swift` (`isConfigured` is now `get async` and
    needs a session; `MealVisionConfiguration.make(rawURL:rawKey:)` pure parser, accepts a bare host)
  - Modified `Core/Sources/Core/Household/{HouseholdClient,HouseholdModels}.swift`,
    `Core/Sources/Core/Family/{FamilyLinkClient,FamilyModels}.swift` (`isConfigured` async + session-aware;
    `isLive` computed)
  - Modified `App/ZANO/ZANOApp.swift` (connect after `SyncEngine.configure`; sync on launch and on every
    `.active`), `App/ZANO/Features/Settings/SettingsView.swift` (Account section, Squad row),
    `App/ZANO/ContentView.swift` (comment only)
  - Modified `project.yml` (Sign in with Apple entitlement; `SUPABASE_URL` / `SUPABASE_ANON_KEY` Info.plist
    keys + empty build settings), `codemagic.yaml`, `.github/workflows/ci.yml`, `fastlane/Fastfile`
    (pass `REVENUECAT_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` to xcodebuild from env)
  - Docs: `docs/launch/supabase-setup.md` (steps 9-10 rewritten, checks added),
    `docs/launch/final-checklist.md` (C and D), `docs/launch/app-privacy-labels.md` (§5 item 2 update),
    `backend/supabase/functions/README.md`
- **What changed:**
  - Sign in with Apple → `POST {SUPABASE_URL}/auth/v1/token?grant_type=id_token` with
    `{provider: "apple", id_token, nonce: <raw>}` (Apple gets the SHA-256 hex of the nonce). Request fields
    and the response shape (`access_token`, `refresh_token`, `expires_in`, `expires_at`, `user`) and the
    `apikey` header were checked against supabase/auth's `openapi.yaml` on 2026-10-07. Not run live.
  - Session JSON in one Keychain item (`AfterFirstUnlockThisDeviceOnly`, app-only, no access group: the
    extensions never do networking). Refresh with `grant_type=refresh_token` when under 60 s remain;
    concurrent callers share one refresh (Supabase rotates refresh tokens). A refused refresh clears the
    session (signed out) and throws `.sessionExpired`.
  - Sign out: best-effort `POST /auth/v1/logout`, always clears locally. Delete account: calls the new
    `delete-account` Edge Function (service-role key server-side only), which removes the caller's meal
    photos and Family Link proof photos from Storage and then the auth user; every row cascades
    (`0001_init.sql`: `users.id → auth.users on delete cascade`, everything else → `users`). The app keeps
    the session if the server didn't confirm, so the person can retry.
  - `BackendConnections.connect()` hands `SupabaseAuthSession.shared` to `SyncEngine` (as
    `SupabaseSyncBackend`), `MealVisionClient`, `HouseholdClient`, `FamilyLinkClient`. Each client's
    `isConfigured` now also needs a session, so a signed-out person gets the existing offline/manual path.
  - Nothing called `SyncEngine.flush()` before. `syncIfSignedIn()` now pushes the outbox and pulls on launch
    and on every return to the app, only when keys exist and someone is signed in. Errors are logged.
- **Decisions made and why:**
  - **Squad is a Settings row, not a sixth tab,** because the floating glass tab bar is designed for five.
    And it **stays hidden even when signed in**: no `SquadDirectory` / `SquadRingSource` implementation and
    no server endpoint exist (the `sync` function refuses squad rows on purpose), so invite codes from other
    phones could never resolve. `SquadAvailability.hasServerSupport = false` holds it back; flip it in the
    session that builds those pieces. Showing it on sign-in alone would be a 2.1 problem.
  - **Referral stays hidden** for the same reason: `ReferralBackend` has no server implementation (no Edge
    Function / RPC to redeem a code and credit both freezes). Not invented here (out of scope).
  - `AccountStatus` is `@MainActor @Observable`, and `HouseholdAvailability.isLive` /
    `FamilyLinkAvailability.isLive` became `@MainActor static var`s reading it, so Settings updates the
    moment someone signs in or out. Their only callers are SwiftUI views.
  - `SupabaseAuthTokenProviding` gained `hasSupabaseSession()` with a default (`true`) so test doubles and
    any other conformer keep compiling.
  - Account section is hidden entirely without keys (`BackendAvailability.isConfigured`), and the Account
    section's copy says an account is optional (locks and unlocking never need it).
  - Build keys go on the xcodebuild command line in every builder (coordinator item): project.yml's
    target-level `REVENUECAT_API_KEY: ""` overrides env vars, so a key set only in Codemagic's environment
    was silently ignored before. `MealVisionConfiguration.make` accepts a bare host so an `.xcconfig` (where
    `//` starts a comment) also works. PostHog/Sentry have no Info.plist key yet, so they aren't passed.
  - Codemagic: no new env group listed (a missing group can fail the build); keys go in the existing
    `github` group.
- **Known issues / TODOs left behind:**
  - Anonymous-first auth (spec §11 "anonymous → linked") is not built; there is only Sign in with Apple.
    Data before sign-in stays on the device and syncs through the outbox after sign-in.
  - The local `User` row id and the Supabase `auth.uid()` are different UUIDs; the sync function sets
    `user_id` from the token server-side, so this is fine for push, but a future pull/merge must map them.
  - "Delete all my data" (local wipe) does not sign out, and "Delete account" does not wipe local data (its
    confirmation says so; the local wipe's copy doesn't mention the account). Decide whether the local
    wipe should also sign out.
  - Squad, Referral, gym leaderboard and meal-prep vision backends remain unbuilt (see decisions).
- **Needs verification on:** CI (compile + `AuthTests`), then a live Supabase project + real device.

## Needs a live Supabase project / device (nothing below has been observed)

- The exact id_token request (`provider`, `id_token`, `nonce`) succeeds for a native Apple token, with the
  Apple provider's Client IDs set to `com.zano.app`.
- Response timestamps (`expires_at`) and the refresh rotation behave as parsed; the token refreshes after an
  hour away.
- `POST /auth/v1/logout` returns 2xx with the user token.
- `delete-account`: `storage.list/remove` on `meal-photos/<uid>`, the embedded filter on
  `family_proofs → family_tasks.link_id`, `auth.admin.deleteUser`, and the cascade over every table.
- `SignInWithAppleButton` + `com.apple.developer.applesignin` with a real provisioning profile.
- The Keychain write in an unsigned Simulator build may fail (`errSecMissingEntitlement`); then the session
  lasts only for that launch. Logged, not fatal. Real signed builds are expected to work.
- The xcodebuild command-line value `SUPABASE_URL=https://…` reaching Info.plist intact (expected; the
  bare-host form is the fallback).

## Unsure it compiles (no toolchain here)

- `Core/Sources/Core/Auth/SupabaseSessionStore.swift`: the `kSec*` CFString constants under Swift 6 strict
  concurrency (standard pattern, believed fine).
- `Core/Sources/Core/Verification/MealVisionClient.swift`, `HouseholdClient.swift`, `FamilyLinkClient.swift`:
  `public var isConfigured: Bool { get async { … } }` on an actor (effectful read-only property).
- `App/ZANO/Features/Settings/SettingsView.swift` `SettingsAccountSection`: `SignInWithAppleButton`'s
  `onRequest` closure writing `@State` (main-actor closure inference).
- `Core/Tests/CoreTests/AuthTests.swift`: `NSLock.withLock` in the in-memory store.

## Blockers

- No Supabase project, Apple Developer enrollment (for the Sign in with Apple capability on the App ID), or
  device. See `docs/launch/supabase-setup.md` steps 9-10.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (coordinator)
- [x] No secrets committed (keys are empty in project.yml and come from CI environments)
