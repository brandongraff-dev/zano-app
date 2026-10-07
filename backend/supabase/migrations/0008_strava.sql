-- ZANO direct Strava link (session 40) — docs/spec.md §3 "Workout (home/outdoor)" ("HealthKit workout
-- logged (Apple Watch, Strava, ...)") and §24 (health data stays on the device; keys stay server-side).
--
-- What it adds:
--   1. strava_links        — one row per ZANO user who connected Strava: the athlete id and the OAuth
--                            tokens. Only the service role (the strava-* Edge Functions) can touch it.
--                            Row-level security is ON with NO policies, and table privileges are revoked
--                            from anon/authenticated, so the app can never read the refresh token.
--   2. strava_oauth_states — short-lived `state` values for the authorize redirect (CSRF protection),
--                            tying a Strava callback to the ZANO user who started it. Service role only.
--   3. goal_events.source  — gains 'strava' (a workout verified from a Strava activity, not from Health).
--
-- Not stored on purpose: activities. `strava-activities` fetches them from Strava on request and hands
-- the app a slim list (times, durations, manual flag, heart rate); nothing about a workout is kept here.
--
-- KNOWN LIMITATIONS (flagged, not fixed here):
--   - Never run against a live project (none exists yet). docs/launch/supabase-setup.md has the steps.
--   - Tokens are stored as plain text, protected by RLS + revoked grants (same trust level as every other
--     row the service role can read). Supabase Vault would be stronger; not used yet.
--   - Migration number 0008: a parallel session may also add an 0008. If both land, renumber one before
--     `supabase db push` (the CLI treats the numeric prefix as the version).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- strava_links
-- ---------------------------------------------------------------------------
create table public.strava_links (
    user_id uuid primary key references public.users(id) on delete cascade,
    athlete_id bigint not null unique,
    access_token text not null,
    refresh_token text not null,
    expires_at timestamptz not null,
    scope text not null default '',
    connected_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.strava_links enable row level security;
-- No policies: with RLS on and no policy, anon/authenticated see zero rows and can write nothing. The
-- revoke below makes that explicit instead of relying on it.
revoke all on table public.strava_links from anon, authenticated;

-- ---------------------------------------------------------------------------
-- strava_oauth_states
-- ---------------------------------------------------------------------------
create table public.strava_oauth_states (
    state text primary key check (state ~ '^[0-9a-f]{64}$'),
    user_id uuid not null references public.users(id) on delete cascade,
    created_at timestamptz not null default now()
);
create index strava_oauth_states_created_idx on public.strava_oauth_states (created_at);

alter table public.strava_oauth_states enable row level security;
revoke all on table public.strava_oauth_states from anon, authenticated;

-- ---------------------------------------------------------------------------
-- goal_events.source += 'strava'
-- ---------------------------------------------------------------------------
-- 0001 declared the check inline, so Postgres named it goal_events_source_check.
alter table public.goal_events drop constraint if exists goal_events_source_check;
alter table public.goal_events add constraint goal_events_source_check check (source in (
    'nfc', 'widget', 'photo', 'barcode', 'geofence', 'healthkit', 'timer', 'manual', 'siri', 'strava'
));
