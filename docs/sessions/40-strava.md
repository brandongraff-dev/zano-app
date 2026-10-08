# Session 40 — Direct Strava link

- **Branch:** `worktree-agent-abd8b49ec97a1c151` (worktree; based on `origin/main` at `c586ea9`)
- **Spec sections:** §3 (Workout home/outdoor: "HealthKit workout logged (Apple Watch, Strava, ...)", "Min 20 min; HR if Watch present"), §5.1 (the shield reflects goal state; unchanged, it reads the same completions), §9.4 / §9.8 (anti-cheat: "never accuse, just don't count, show 'not counted' transparently"), §24 (health data stays on device; keys only in Edge Functions), §27 (HealthKit background delivery can be late: verify on next open)
- **Status:** Scaffolded — Unverified (needs a Supabase project, sign-in wired, a Strava API app, and a CI compile)
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

Before this, workouts only arrived through Apple Health (session 20's observer). This adds a direct Strava
connection as a second verified source for the home/outdoor workout goal (and the travel-mode gym goal,
which goes through the same check):

1. Backend: `strava-oauth` (connect, status, disconnect) and `strava-activities` (recent activities,
   refreshing tokens server-side), a migration for the token table with RLS, and an optional
   `strava-webhook` for deauthorization.
2. App: Settings > Strava (hidden unless the backend is configured and someone is signed in), connect via
   `ASWebAuthenticationSession` (SwiftUI `WebAuthenticationSession`) on the existing `zano://` scheme.
3. Verification: Strava activities feed the same `HomeWorkoutVerifier.checkToday` path Health workouts use,
   deduped against Health by start time + duration overlap.
4. Copy in `Core/Sources/Core/Copy/StravaCopy.swift`; Core tests for mapping and dedupe.
5. Setup steps in `docs/launch/supabase-setup.md` ("Strava").

## Definition of done

- A person who connected Strava and records a 20+ minute activity there (not typed in by hand) gets the
  workout goal completed on next foreground / Health wake, with no Health involvement.
- The same workout in Health and Strava completes the goal once and is counted once in progress.
- Tokens never reach the phone; disconnect revokes at Strava and deletes them.
- Nothing Strava-related is visible while the backend isn't configured.

## Log

### 2026-10-07 — Strava link: backend, client, verification, Settings, tests, docs

- **Files touched:**
  - new `backend/supabase/migrations/0008_strava.sql`
  - new `backend/supabase/functions/_shared/strava.ts`, `strava-oauth/index.ts`, `strava-activities/index.ts`, `strava-webhook/index.ts`
  - modified `backend/supabase/functions/README.md`
  - new `Core/Sources/Core/Strava/StravaModels.swift`, `StravaClient.swift`, `StravaActivityStore.swift`, `StravaActivitySync.swift`
  - new `Core/Sources/Core/Verification/WorkoutDedupe.swift`
  - modified `Core/Sources/Core/Verification/HomeWorkoutVerifier.swift`, `HealthGoalChecks.swift`, `Core/Sources/Core/Models/GoalEvent.swift`
  - new `Core/Sources/Core/Copy/StravaCopy.swift`
  - new `Core/Tests/CoreTests/StravaTests.swift` (27 tests)
  - new `App/ZANO/Features/Strava/StravaConnectView.swift`
  - modified `App/ZANO/Features/Settings/SettingsView.swift`, `App/ZANO/Features/Today/TodayView.swift`
  - modified `docs/launch/supabase-setup.md`
- **What changed:**
  - **Backend.** `strava_links` (user_id, athlete_id unique, access/refresh token, expiry, scope) and
    `strava_oauth_states` (CSRF `state`, 10-minute life), both RLS-on with no policies and privileges revoked
    from `anon`/`authenticated`: only the service role inside the functions can read them. `goal_events.source`
    gains `'strava'`. `strava-oauth`: `start` mints a state and returns the Strava mobile authorize URL;
    `exchange` claims the state once, swaps the code with `STRAVA_CLIENT_SECRET`, checks the granted scope,
    moves the athlete off any other ZANO account (one athlete, one account) and upserts; `status`;
    `disconnect` revokes at `/oauth/revoke` (best effort) and deletes. `strava-activities` refreshes the
    token when it expires within 5 minutes (storing the rotated refresh token), lists
    `/athlete/activities?after=` (clamped to 8 days, up to 2 pages of 100) and returns only id, sport type,
    start, elapsed/moving seconds, `manual`, heart-rate presence and max. Nothing about activities is stored.
    A refused refresh or a 401 deletes the link and returns 410. `strava-webhook` validates the
    subscription and deletes tokens on a deauthorization event; activity events are acknowledged and ignored.
    All three follow `family-proof-open`'s auth pattern (user-scoped client, `auth.getUser()`).
  - **Client.** `StravaClient` (actor, like `HouseholdClient`) calls the functions with the user's Supabase
    token and the anon key from `MealVisionConfiguration`. `StravaActivityStore` caches yesterday's and
    today's activities in `UserDefaults.standard` (main app only). `StravaActivitySync.refreshIfDue()`
    fetches at most once per 15 minutes from the start of yesterday.
  - **Verification (no duplicated logic).** `HealthGoalChecks.run()` (launch, every foreground, every
    HealthKit workout wake-up) now calls `StravaActivitySync.refreshIfDue()` first and runs the workout
    checks when Health was asked *or* Strava is linked. `HomeWorkoutQueryState.checkToday` keeps its single
    event-writing path: evidence is a qualifying Health workout first, else a qualifying Strava workout from
    `WorkoutDedupe.qualifyingStravaWorkout(health:strava:requiredMinutes:)`; the event is written with source
    `.strava` and `meta.stravaActivityID`. `longestWorkoutMinutesToday()` (Today's ring) uses the deduped
    merge too. Today stops showing "Connect Apple Health" for a Strava-linked person.
  - **Dedupe.** Two workouts are the same when their overlap is at least half the shorter one's span
    (zero-length spans: starts within 2 minutes). Health wins a tie; a Strava copy of a Health workout is
    dropped even if Health's copy was too short (one workout, one vote).
  - **Anti-cheat.** Strava `manual: true` activities never count (Tier A goal; spec §9.8 "just don't count"),
    and the Strava screen says so plainly ("1 workout typed in by hand on Strava wasn't counted"). Moving
    time (not elapsed) is what has to reach 20 minutes. Heart-rate corroboration uses Strava's max heart rate
    against the same 100 bpm threshold as Health and, like Health's, never gates.
  - **Settings.** A "Strava" row (after Planner) appears only when `StravaClient.shared.isAvailable()`; it
    opens `StravaConnectView` (connect, check now, disconnect with confirmation, "Powered by Strava").
    "Delete all my data" disconnects Strava (best effort) and clears the cache keys.
- **Decisions made and why:**
  - **The auth seam:** `public protocol StravaBackendSessionProviding: SupabaseAuthTokenProviding { func isBackendConfigured() async -> Bool }`
    in `StravaModels.swift`, wired with `StravaClient.shared.configure(session:)`. It reuses the existing
    `SupabaseAuthTokenProviding.supabaseAccessToken()` for the token and adds the one thing the UI needs:
    "is a project configured and is someone signed in", answered without network. `StravaClient.isAvailable()`
    additionally requires `SUPABASE_URL`/`SUPABASE_ANON_KEY` in Info.plist (`MealVisionConfiguration`). Today
    nothing conforms, so the row is hidden and every Strava path is inert. **Coordinator:** make the auth
    session type from the Sign in with Apple session conform and call `configure(session:)` at launch next to
    the other clients.
  - **Scope `activity:read_all`, not `activity:read`:** `activity:read` hides activities set to "Only You",
    and many people keep workouts private. Either grant is accepted by the server. Change `STRAVA_SCOPE` in
    `_shared/strava.ts` if least-privilege matters more than private workouts.
  - **The authorize URL is built server-side**, so the app needs no Strava client ID either, and `state` is
    stored server-side and claimed once.
  - **New `GoalEventSource.strava`** rather than reusing `.healthKit`: the training table (`goal_events`,
    spec §9.9) should say where a completion came from. The 0008 migration widens the check constraint.
  - **No background refresh task:** a `BGAppRefreshTask` needs the `fetch` background mode, which
    `project.yml` deliberately doesn't declare. Strava is fetched on the same occasions Health workouts are
    checked (launch, foreground, HealthKit workout wake-ups). The webhook doesn't push to the phone (no APNs).
  - **No Strava app hand-off:** Strava's docs suggest opening `strava://oauth/mobile/authorize` when the
    Strava app is installed. Skipped to avoid `LSApplicationQueriesSchemes` and a second callback path; the
    web sheet works for everyone. Easy to add later.
- **Known issues / TODOs left behind:**
  - **FOUNDER TO-DO (Strava brand guidelines):** replace the drawn "Connect with Strava" capsule and the
    "Powered by Strava" text in `StravaConnectView.swift` with Strava's official button and logo assets
    (developers.strava.com/guidelines). Required before the row is shown to anyone.
  - **FOUNDER TO-DO:** create the Strava API app (Authorization Callback Domain `zano.app`), set
    `STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET`, and request a capacity increase before launch (new Strava
    apps allow one athlete). Steps: `docs/launch/supabase-setup.md`, "Strava".
  - Privacy policy / App Store privacy answers don't mention Strava yet; update before enabling.
  - Migration number 0008 may collide with a parallel session's migration; renumber one at merge.
  - Tokens are plain text in `strava_links` (RLS + revoked grants). Supabase Vault would be stronger.
  - Health workouts typed in by hand (`HKMetadataKeyWasUserEntered`) still count through the existing
    Health path; only Strava's `manual` flag is checked here. Out of scope; worth a follow-up for parity.
  - The Strava row's "Connected" value refreshes on Settings appear, not live.
- **Unverified API details (flag for first real run):**
  - Redirect `zano://zano.app/strava` with callback domain `zano.app`: Strava's docs say the redirect must be
    "within the callback domain" and show a custom-scheme example, but don't spell out how the host is matched
    for custom schemes (`_shared/strava.ts`, `STRAVA_REDIRECT_URI`).
  - Whether the token response always includes `scope` (the app forwards the redirect's `scope` as a fallback).
  - `per_page` maximum (100 used, believed max 200) and the rate-limit status code (429 assumed).
  - The deauthorization webhook event's `aspect_type` (matched on `object_type: athlete` + `updates.authorized == "false"`).
  - SwiftUI `WebAuthenticationSession.authenticate(using:callbackURLScheme:)` signature and that a user
    cancel throws `ASWebAuthenticationSessionError.canceledLogin` (`StravaConnectView.swift`).
  - supabase-js v2 calls (`delete().select().maybeSingle()`, `upsert`) written from memory; the functions
    type-check against a stub only (`tsc --strict` with `any` clients).
- **Needs verification on:** CI (compile + `StravaTests`), a live Supabase project with the functions
  deployed, a real Strava account (connect, record, disconnect, deauthorize on strava.com), and a device
  (Health + Strava dedupe with a Watch run that also uploads to Strava).

## Blockers

- No Supabase project, no sign-in (parallel session), no Strava API app, no Mac (CI is the compiler).

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (coordinator owns the board for this session)
- [x] No secrets committed (all Strava values are Supabase function secrets; nothing in the app or repo)

### 2026-10-08 — CI

- Merged into `claude/dazzling-hypatia-ed6q5d` with sessions 33-40. GitHub Actions run 147 (head 49a2e4c): the app with every extension, the Watch app, the embedded Watch build and the Core unit tests all pass. Device checks above still open.
