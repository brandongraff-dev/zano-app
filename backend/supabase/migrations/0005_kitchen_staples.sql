-- ZANO kitchen staples — docs/spec.md §5.20 (Protein Gap Planner: "At ~4 PM, if the user is
-- behind: three concrete options ranked by proximity and effort — something in their saved
-- kitchen staples, a nearby restaurant item with a deep link, or a quick snack.") and §10
-- ("Kitchen staples: user saves 10–20 staples once; the gap planner uses them first.").
-- Builds on top of 0001_init.sql/0002_auth_storage.sql/0003_waitlist.sql/0004_ml_feature_job.sql
-- (frozen shape, untouched here). Do not edit 0001-0004.
--
-- What this migration does:
--   Creates `public.kitchen_staples`, a small per-user list of foods the user already has on
--   hand and already knows the protein content of. This is Tier 1 of the Protein Gap Planner
--   (`Core/Sources/Core/Verification/ProteinGapPlanner.swift`, this same task) — the only tier
--   that needs no network call or third-party vendor, since it's just the user's own saved data.
--   Tier 2 (nearby restaurant) and Tier 3 (quick snack) are intentionally NOT backed by any new
--   table here: spec §28 (Open Questions) has not decided "Which nutrition/restaurant API is
--   worth paying for at launch, if any?" yet, so there is nothing to migrate a schema for until
--   that's answered — see `ProteinGapPlanner.swift`'s own header comment.
--
-- `kitchen_staples` is not one of the tables docs/spec.md §13 (Data Model) lists — that table
-- predates §5.20/§10 being fleshed out into a real feature. Same situation 0002's
-- `user_day_features`/0003's `waitlist_signups` were already in for their own new tables: this is
-- an additive migration, not a §13 edit. §13's blanket RLS rule ("user_id = auth.uid() on
-- everything") still applies below.
--
-- Style note: unlike 0001_init.sql (written before the `public.`-qualification convention
-- settled), this migration follows 0002-0004's more explicit style — `public.` schema
-- qualification, `create table if not exists`, `drop policy if exists` before `create policy`,
-- and a `comment on table` — since that's the more current precedent to match going forward.

-- ---------------------------------------------------------------------------
-- kitchen_staples
-- ---------------------------------------------------------------------------
create table if not exists public.kitchen_staples (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.users(id) on delete cascade,
    name text not null,
    -- No upper bound enforced here: spec §10's "10–20 staples" is a UX expectation for the
    -- Kitchen Staples setup screen to nudge toward, not a hard data-layer cap (same reasoning
    -- 0001_init.sql's `goals.type` has no check constraint despite the catalog being effectively
    -- fixed — see Core/Sources/Core/Models/Goal.swift's header comment for that precedent).
    protein_g numeric not null check (protein_g >= 0),
    created_at timestamptz not null default now()
);

-- Every real read of this table is "give me this user's staples" (Tier 1 ranking in
-- ProteinGapPlanner, and the Kitchen Staples setup/list screen) — a small table (10-20 rows/user
-- per spec §10) doesn't strictly need this for performance, but it costs nothing and matches
-- 0002_auth_storage.sql/0004_ml_feature_job.sql's own habit of indexing the column RLS/lookups
-- actually filter on.
create index if not exists kitchen_staples_user_id_idx on public.kitchen_staples (user_id);

comment on table public.kitchen_staples is
    'User-saved "always have it, already know the protein" foods (docs/spec.md §10). Tier 1 '
    'source for the Protein Gap Planner (§5.20) — see Core/Sources/Core/Verification/'
    'ProteinGapPlanner.swift.';

alter table public.kitchen_staples enable row level security;

drop policy if exists "kitchen_staples_owner" on public.kitchen_staples;
create policy "kitchen_staples_owner"
    on public.kitchen_staples for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());
