# ZANO backend (Supabase)

Fully runnable on Windows (needs Docker Desktop for local dev — no Mac required), unlike the rest
of the stack. Good place to make real, verified progress while waiting on a Mac.

## First-time setup

```sh
# from repo root
brew install supabase/tap/supabase   # macOS — on Windows, use scoop or npm: see
                                      # https://supabase.com/docs/guides/cli/getting-started
cd backend
supabase init      # only if config.toml doesn't exist yet — this repo doesn't hand-write it,
                    # the CLI generates a version-correct one
supabase start      # spins up local Postgres/Auth/Storage/Studio in Docker
supabase db reset    # applies migrations/0001_init.sql (see that file — mirrors docs/spec.md §13)
```

## Layout

- `migrations/0001_init.sql` — full schema + RLS from docs/spec.md §13, frozen at Session 0 per
  the spec's ordering rule ("Freeze §13 before splitting"). Session 7 owns hardening RLS against
  real auth flows and adding any migrations beyond this baseline.
- `functions/` — Edge Functions (TypeScript). Empty until Session 7/8 — see `functions/README.md`
  for what's planned and which session owns it.

## What's NOT done yet (Session 7+ scope)

- No Supabase project has been created (this is all local-migration scaffolding). Creating the
  hosted project, wiring Auth (anonymous → Sign in with Apple linking, per docs/spec.md §11), and
  connecting the app's Sync outbox are Session 7.
- `config.toml` doesn't exist yet — run `supabase init` to generate one rather than trusting a
  hand-written guess (the format changes across CLI versions).
- Edge Functions are unwritten — see `functions/README.md`.
