# Session 7 — Supabase: schema, RLS, auth, storage, sync Edge Function, RevenueCat webhook

- **Branch:** `main`
- **Spec sections:** §11 (architecture), §13 (data model, schema already frozen in Session 0)
- **Status:** Scaffolded — Unverified (partial — see Known issues)
- **Built:** 2026-09-22, split across the "Foundation" phase's backend agents (not a dedicated
  cluster — this session's scope was folded into Foundation since it has no dependency on the
  Swift Core package).

## Scope covered here

- Auth auto-provisioning (a trigger inserting into `public.users` on every `auth.users` insert)
  and a private `meal-photos` Storage bucket with per-user-prefix RLS.
- `sync` Edge Function: accepts a batch of outbox events (matching
  `Core/Sources/Core/Sync/OutboxEvent.swift`'s shape), upserts by entity name, authenticated via
  JWT.
- `revenuecat-webhook` Edge Function: verifies RevenueCat's webhook auth, upserts `subscriptions`.

## Files

- `backend/supabase/migrations/0002_auth_storage.sql`
- `backend/supabase/functions/sync/index.ts`, `revenuecat-webhook/index.ts`

(Schema + RLS themselves are `backend/supabase/migrations/0001_init.sql`, from Session 0 — not
rebuilt here, only extended.)

## Known issues / what's NOT done

- **No Supabase project exists yet** (tracked in `docs/PROGRESS.md`'s environment table) — none of
  this SQL/TypeScript has run against a real or even local Docker Postgres instance.
- **The app-side half of Sync isn't wired to these functions.** `Core/Sources/Core/Sync/SyncEngine.swift`
  (Session 1) defines a `SyncBackend` protocol as an extension point; nothing yet implements it
  against these two Edge Functions. That's the concrete remaining gap in this session — a
  reasonably small, well-scoped follow-up task once a Supabase project exists to point it at.
- Anonymous → Sign in with Apple account linking (the auth flow itself, not just the
  auto-provisioning trigger) is not built — §11 calls for anonymous-first auth with linking at
  sync/paywall time; only the downstream trigger exists so far.

## Needs verification on

Windows is actually sufficient here (Supabase CLI + Docker, no Mac needed) — this is the one
backend area that could get *real* automated verification before anything else does. Run
`supabase start && supabase db reset` from `backend/`, confirm 0001→0002 apply cleanly, then
exercise both Edge Functions locally.
