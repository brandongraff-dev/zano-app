# Supabase setup (hosted project, step by step)

Written 2026-10-06 from the repo (`backend/supabase/`). Dashboard menu names move; where a step names a
screen, search the Supabase docs if it has changed. Nothing here has been run against a live project.

## Do you need this to submit version 1.0? No.

ZANO is local-first. Everything that gates a lock (goals, shield, timers, emergency unlock) works with no
server. Supabase powers extras: cloud backup/sync, photo meal estimates (`meal-vision`), the weekly recap
text, the risk check, the RevenueCat webhook, Household and Family Link.

**Sign in with Apple is built (session 34, 2026-10-07)** but untested against a live project. The switch is
the build itself: with no `SUPABASE_URL` / `SUPABASE_ANON_KEY` in the build, the app has no Account section,
no Household, no Family Link and makes no Supabase calls, exactly as before. Add the two keys (step 10) and
Settings gains an Account section; once someone signs in, Household and Family Link appear for them, meal
photo estimates start working, and sync pushes on every app open. Squads stay hidden either way: their
server side (invite lookup, squadmates' rings) is not built (`SquadAvailability.hasServerSupport`).

Recommended: submit 1.0 without the keys (nothing else to hide), then do the steps below and ship 1.1 with
them once you have tested sign-in on a device.

If you would rather ship it in 1.0, do all ten steps below and then re-check the privacy policy, the
App Store privacy answers and each `PrivacyInfo.xcprivacy` (`docs/launch/README.md`, "keep these four
things in agreement").

## Steps

1. **Create the project.** supabase.com > New project. Pick the region closest to most users (write it
   into the privacy policy's `[SUPABASE REGION]`). Use a strong database password and store it in a
   password manager. Free plan is fine to start; Family Link proofs and meal photos are small.

2. **Install the CLI and link.** On any computer with Node or Homebrew (a Mac is not needed):
   `supabase login`, then from `backend/`: `supabase link --project-ref <ref>` (the ref is in the project
   URL). The repo has no `config.toml`; if the CLI asks, run `supabase init` first and keep the folders.

3. **Apply the database.** `supabase db push` applies `migrations/0001` to `0007` (schema, RLS, auth/storage,
   waitlist, ML feature job, staples, Family Link, Household). Then open Table Editor and confirm RLS shows as enabled
   on every table. 0006 also creates the private `family-proofs` bucket; confirm it is **private** in Storage.

4. **Turn on the extensions** (Database > Extensions): `pg_cron` and `pg_net`. They are needed for the
   scheduled jobs in steps 7 and 8.

5. **Set the function secrets** (Edge Functions > Secrets, or `supabase secrets set NAME=value`). Never put
   these in the app or the repo.

   | Secret | Used by | Where it comes from |
   |---|---|---|
   | `ZANO_LLM_API_KEY`, `ZANO_LLM_API_URL`, `ZANO_LLM_API_VERSION`, `ZANO_LLM_MODEL` | meal-vision, meal-prep-plan, weekly-recap | your LLM provider account (a vision-capable model for meal photos) |
   | `REVENUECAT_WEBHOOK_SECRET` | revenuecat-webhook | any long random string; paste the same value into RevenueCat's webhook "Authorization header" |
   | `FAMILY_CLEANUP_SECRET` | family-proof-cleanup | any long random string (also used in step 7) |
   | `ML_SERVICE_URL`, `ML_SERVICE_API_KEY` | risk-check | only if you host `ml-service/` (see its README); otherwise skip risk-check |
   | `ZANO_WEEKLY_RECAP_BATCH_LIMIT`, `ZANO_RISK_CHECK_*` | optional tuning | defaults are fine |

   `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided to functions
   automatically. The **service role key is a master key: never put it in the app.**

6. **Deploy the functions.** From `backend/`:
   `supabase functions deploy sync meal-vision meal-prep-plan family-proof-open`
   and, because these three authenticate with their own secret instead of a user token:
   `supabase functions deploy revenuecat-webhook family-proof-cleanup weekly-recap --no-verify-jwt`
   (`risk-check` too, if used). Check each one answers: a call with no credentials should return 401, not 500.

7. **Schedule the proof cleanup** (view-once photos must actually be deleted). In the SQL editor, run the
   commented block at the bottom of `0006_family_link.sql` with your project URL and `FAMILY_CLEANUP_SECRET`
   filled in (every 5 minutes). Afterwards check `cron.job_run_details` shows successful runs. Without this,
   unopened photos would sit past the 24-hour promise.

8. **Schedule the weekly recap** (optional): the SQL example is in the header of
   `functions/weekly-recap/index.ts`. Skip it if you are not shipping recaps from the server.

9. **Turn on Sign in with Apple** (the app code exists since session 34: `Core/Sources/Core/Auth/`).
   - Apple Developer portal: on the App ID `com.zano.app`, tick **Sign in with Apple** and regenerate the
     provisioning profiles. project.yml already adds the `com.apple.developer.applesignin` entitlement.
   - Supabase: Authentication > Sign In / Providers > **Apple**: enable it and add `com.zano.app` to the
     **Client IDs** list (the native app's bundle ID is the audience of the identity token). The
     Services ID, Team ID, Key ID and `.p8` secret key are only needed for web/OAuth sign-in, which ZANO
     does not use; if the dashboard insists on them, create a Services ID in the developer portal. Check
     Supabase's current "Login with Apple" guide for the exact fields, they move.
   - Deploy the account deletion function (App Store 5.1.1(v), required once sign-in exists):
     `supabase functions deploy delete-account` (keep JWT verification on).
   - How the app signs in (for reference, unverified against a live project): Apple sign-in sheet with
     the SHA-256 of a random nonce, then `POST {SUPABASE_URL}/auth/v1/token?grant_type=id_token` with
     `{"provider":"apple","id_token":…,"nonce":<raw nonce>}` and the `apikey` header. The session lives in
     the Keychain (this device only) and refreshes with `grant_type=refresh_token` a minute before expiry.

10. **Point the app at it.** The build reads two Info.plist keys fed from build settings (project.yml):
    `SUPABASE_URL` (Project Settings > API > Project URL, e.g. `https://abcd.supabase.co`) and
    `SUPABASE_ANON_KEY` (the **anon / publishable** key; public by design, safe to ship. Never the
    service-role / secret key). They are empty in the repo; set them as environment variables where builds
    run, and every build script passes them to `xcodebuild` on the command line (project.yml's empty
    target settings would otherwise override plain env vars):
    - **Codemagic:** Team settings > Environment variables, group `github` (already listed in
      `codemagic.yaml`): `SUPABASE_URL`, `SUPABASE_ANON_KEY` (and `REVENUECAT_API_KEY`).
    - **GitHub Actions:** repository secrets with the same three names (`ci.yml` build steps and the
      TestFlight job, which hands them to `fastlane beta`).
    - **Local Xcode:** `xcodebuild ... SUPABASE_URL=https://abcd.supabase.co SUPABASE_ANON_KEY=...`. If you
      use an `.xcconfig` instead, write the host only (`SUPABASE_URL = abcd.supabase.co`): `//` starts a
      comment in xcconfig files, and the app adds `https://` itself.
    Nothing else changes in code: `HouseholdAvailability.isLive` and `FamilyLinkAvailability.isLive` are
    computed (keys present AND signed in). Check after building: Settings shows an **Account** section.

## Check it works (needs two phones or two Apple IDs)

- Settings > Account > Sign in with Apple: the section switches to "Signed in with Apple"; Household and
  Family Link rows appear under Setup. In Supabase, Authentication > Users shows the new user and
  Table Editor > `users` has the matching row (0002's trigger).
- Leave the app for over an hour, come back, open Household: it still loads (the token refreshed).
- Sign out: the rows disappear. Sign in again, then Delete account: the user is gone from Authentication
  and their rows and meal photos are gone too.

- Parent creates an invite, teen accepts it: both see the link.
- Parent adds a task needing a photo; teen hands in a photo; parent opens it **once**; the second open says
  it is gone; 10 minutes later the file is gone from Storage and the row is removed.
- A third account cannot read any of it (try with a different user's token: expect empty results).
- Delete the test users afterwards (Authentication > Users).

## Costs and safety

- Free plan pauses an idle project after a week; use Pro (about $25 a month) before real users.
- Turn on daily backups (Pro) and keep the service role key out of every chat, screenshot and commit.
- Set a spending cap with the LLM provider; meal-vision is called once per photo.
