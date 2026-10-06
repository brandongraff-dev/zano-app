# Supabase setup (hosted project, step by step)

Written 2026-10-06 from the repo (`backend/supabase/`). Dashboard menu names move; where a step names a
screen, search the Supabase docs if it has changed. Nothing here has been run against a live project.

## Do you need this to submit version 1.0? No.

ZANO is local-first. Everything that gates a lock (goals, shield, timers, emergency unlock) works with no
server. Supabase powers extras: cloud backup/sync, photo meal estimates (`meal-vision`), the weekly recap
text, the risk check, the RevenueCat webhook and Family Link. **None of them can run yet anyway:** the app
has no sign-in, and nothing implements `SupabaseAuthTokenProviding` (step 9). Recommended: submit 1.0 without
Supabase, with Family Link hidden (`FamilyLinkAvailability.isLive = false`) and the photo-estimate buttons
saying "not available right now". Turn Supabase on in 1.1 once sign-in is built.

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

3. **Apply the database.** `supabase db push` applies `migrations/0001` to `0006` (schema, RLS, auth/storage,
   waitlist, ML feature job, staples, Family Link). Then open Table Editor and confirm RLS shows as enabled
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

9. **Build sign-in (the missing code).** The app needs a type that conforms to `SupabaseAuthTokenProviding`
   and is passed to `FamilyLinkClient.shared.configure(tokenProvider:)`, `MealVisionClient` and the sync
   backend at launch. Recommended: Sign in with Apple exchanged for a Supabase session
   (`POST /auth/v1/token?grant_type=id_token` with `provider: apple`), refresh tokens kept in the Keychain.
   Dashboard side: Authentication > Providers > Apple (needs your Services ID and key from the Apple
   Developer portal), and add the "Sign in with Apple" capability to the app. This is a code task I can do
   next; it cannot be tested without the project and a device.

10. **Point the app at it.** Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as build settings (the anon key is
    public by design, safe to ship) the way `REVENUECAT_API_KEY` is passed (`project.yml`, Codemagic env
    group). Then set `FamilyLinkAvailability.isLive = true` and rebuild.

## Check it works (needs two phones or two Apple IDs)

- Parent creates an invite, teen accepts it: both see the link.
- Parent adds a task needing a photo; teen hands in a photo; parent opens it **once**; the second open says
  it is gone; 10 minutes later the file is gone from Storage and the row is removed.
- A third account cannot read any of it (try with a different user's token: expect empty results).
- Delete the test users afterwards (Authentication > Users).

## Costs and safety

- Free plan pauses an idle project after a week; use Pro (about $25 a month) before real users.
- Turn on daily backups (Pro) and keep the service role key out of every chat, screenshot and commit.
- Set a spending cap with the LLM provider; meal-vision is called once per photo.
