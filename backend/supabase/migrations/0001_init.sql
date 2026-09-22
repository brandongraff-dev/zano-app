-- ZANO initial schema — mirrors docs/spec.md §13 exactly (table/column names match).
-- Session 7 (feat/backend) owns wiring this to real auth flows (anon → Sign in with Apple linking)
-- and battle-testing the RLS policies below; treat this migration as a frozen *shape* (per §17's
-- ordering rule: "Freeze §13 before splitting"), not a finished, audited backend.
--
-- Apply with the Supabase CLI once a project exists — this is fully runnable on Windows (needs
-- Docker for local dev, no Mac required):
--   supabase init          (if backend/supabase/config.toml doesn't exist yet)
--   supabase start
--   supabase db reset      (applies all migrations to the local db)

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists vector;      -- pgvector, for meal embeddings (Quick Repeats, §5.19)

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
create table users (
    id uuid primary key references auth.users(id) on delete cascade,
    apple_sub text unique,
    created_at timestamptz not null default now(),
    tz text not null default 'UTC',
    coach_voice text not null default 'hype' check (coach_voice in ('hype', 'tough_love', 'chill', 'data')),
    plan_tier text not null default 'free' check (plan_tier in ('free', 'pro')),
    referral_code text unique,
    referred_by uuid references users(id)
);

-- ---------------------------------------------------------------------------
-- goals
-- ---------------------------------------------------------------------------
create table goals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    type text not null,                       -- see docs/spec.md §3 goal catalog
    title text not null,
    target_value numeric,
    unit text,
    cadence text,                             -- e.g. daily, weekly, per-week-count
    verification_tier text not null check (verification_tier in ('A', 'B', 'C')),
    active boolean not null default true,
    adaptive boolean not null default true,
    created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- daily_plans
-- ---------------------------------------------------------------------------
create table daily_plans (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    date date not null,
    goal_id uuid not null references goals(id) on delete cascade,
    planned_value numeric,
    difficulty_step integer not null default 0,
    plan_b_value numeric,
    source text not null default 'rules' check (source in ('rules', 'bandit', 'manual')),
    unique (user_id, goal_id, date)
);

-- ---------------------------------------------------------------------------
-- goal_events — the training table for §9 ML systems
-- ---------------------------------------------------------------------------
create table goal_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    goal_id uuid not null references goals(id) on delete cascade,
    ts timestamptz not null default now(),
    kind text not null check (kind in ('log', 'verify', 'complete', 'miss', 'plan_b', 'freeze')),
    value numeric,
    source text not null check (source in (
        'nfc', 'widget', 'photo', 'barcode', 'geofence', 'healthkit', 'timer', 'manual', 'siri'
    )),
    verified boolean not null default false,
    meta jsonb not null default '{}'::jsonb
);
create index goal_events_user_ts_idx on goal_events (user_id, ts desc);

-- ---------------------------------------------------------------------------
-- lock_sets — FamilyControls app tokens never leave the device (§13); the blob column exists for
-- schema completeness but the real (device-local) token store is SwiftData, not Postgres.
-- ---------------------------------------------------------------------------
create table lock_sets (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    name text not null,
    app_tokens_blob bytea,
    is_default boolean not null default false
);

-- ---------------------------------------------------------------------------
-- lock_sessions
-- ---------------------------------------------------------------------------
create table lock_sessions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    lock_set_id uuid references lock_sets(id) on delete set null,
    started_at timestamptz not null default now(),
    ended_at timestamptz,
    trigger text check (trigger in ('nfc', 'schedule', 'manual', 'auto')),
    mode text check (mode in ('full', 'earn')),
    required_goal_ids uuid[] not null default '{}',
    unlock_kind text check (unlock_kind in ('earned', 'emergency', 'schedule_end', 'manual'))
);

-- ---------------------------------------------------------------------------
-- time_bank — Earn Mode, §5.2
-- ---------------------------------------------------------------------------
create table time_bank (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    date date not null,
    earned_min integer not null default 0,
    spent_min integer not null default 0,
    unique (user_id, date)
);

-- ---------------------------------------------------------------------------
-- streaks
-- ---------------------------------------------------------------------------
create table streaks (
    user_id uuid primary key references users(id) on delete cascade,
    current integer not null default 0,
    best integer not null default 0,
    freezes_left integer not null default 1,
    last_earned_date date,
    never_miss_twice_armed boolean not null default false
);

-- ---------------------------------------------------------------------------
-- gyms
-- ---------------------------------------------------------------------------
create table gyms (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    lat double precision not null,
    lng double precision not null,
    radius_m integer not null default 150,
    name text,
    auto_detected boolean not null default false,
    confirmed boolean not null default false
);

-- ---------------------------------------------------------------------------
-- meals — Quick Repeats (§5.19), meal vision (§9.5)
-- ---------------------------------------------------------------------------
create table meals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    ts timestamptz not null default now(),
    photo_path text,
    items jsonb not null default '[]'::jsonb,
    protein_g numeric,
    confirmed boolean not null default false,
    embedding vector(1536)   -- dimension is a placeholder; match to whatever embedding model Session 8 picks
);
create index meals_embedding_idx on meals using ivfflat (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- squads
-- ---------------------------------------------------------------------------
create table squads (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_by uuid not null references users(id) on delete cascade,
    invite_code text unique not null
);

create table squad_members (
    squad_id uuid not null references squads(id) on delete cascade,
    user_id uuid not null references users(id) on delete cascade,
    role text not null default 'member' check (role in ('owner', 'member')),
    primary key (squad_id, user_id)
);

-- ---------------------------------------------------------------------------
-- duels
-- ---------------------------------------------------------------------------
create table duels (
    id uuid primary key default gen_random_uuid(),
    a_user uuid not null references users(id) on delete cascade,
    b_user uuid not null references users(id) on delete cascade,
    start_date date not null,
    end_date date not null,
    a_points integer not null default 0,
    b_points integer not null default 0,
    status text not null default 'pending' check (status in ('pending', 'active', 'complete', 'declined'))
);

-- ---------------------------------------------------------------------------
-- badges / coins
-- ---------------------------------------------------------------------------
create table badges (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    key text not null,
    earned_at timestamptz not null default now(),
    unique (user_id, key)
);

create table coins (
    user_id uuid primary key references users(id) on delete cascade,
    balance integer not null default 0
);

-- ---------------------------------------------------------------------------
-- recaps — Weekly Report Card, §5.14, §9.6
-- ---------------------------------------------------------------------------
create table recaps (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    week_start date not null,
    text text,
    stats jsonb not null default '{}'::jsonb,
    image_path text,
    unique (user_id, week_start)
);

-- ---------------------------------------------------------------------------
-- nudges — §9.3 nudge optimizer
-- ---------------------------------------------------------------------------
create table nudges (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    ts timestamptz not null default now(),
    arm jsonb not null default '{}'::jsonb,
    delivered boolean not null default false,
    acted_within_3h boolean
);

-- ---------------------------------------------------------------------------
-- risk_scores — §9.2 slip prediction
-- ---------------------------------------------------------------------------
create table risk_scores (
    user_id uuid not null references users(id) on delete cascade,
    date date not null,
    p_miss numeric,
    model_version text,
    primary key (user_id, date)
);

-- ---------------------------------------------------------------------------
-- subscriptions — from RevenueCat webhook, §21
-- ---------------------------------------------------------------------------
create table subscriptions (
    user_id uuid primary key references users(id) on delete cascade,
    rc_customer_id text,
    status text,
    product text,
    renews_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Row Level Security — "user_id = auth.uid() on everything; squad tables readable by members"
-- (docs/spec.md §13). This is a first pass; Session 7 owns hardening against real auth flows.
-- ---------------------------------------------------------------------------

alter table users enable row level security;
create policy "users_self" on users for all using (id = auth.uid()) with check (id = auth.uid());

alter table goals enable row level security;
create policy "goals_owner" on goals for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table daily_plans enable row level security;
create policy "daily_plans_owner" on daily_plans for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table goal_events enable row level security;
create policy "goal_events_owner" on goal_events for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table lock_sets enable row level security;
create policy "lock_sets_owner" on lock_sets for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table lock_sessions enable row level security;
create policy "lock_sessions_owner" on lock_sessions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table time_bank enable row level security;
create policy "time_bank_owner" on time_bank for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table streaks enable row level security;
create policy "streaks_owner" on streaks for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table gyms enable row level security;
create policy "gyms_owner" on gyms for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table meals enable row level security;
create policy "meals_owner" on meals for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table badges enable row level security;
create policy "badges_owner" on badges for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table coins enable row level security;
create policy "coins_owner" on coins for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table recaps enable row level security;
create policy "recaps_owner" on recaps for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table nudges enable row level security;
create policy "nudges_owner" on nudges for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table risk_scores enable row level security;
create policy "risk_scores_owner" on risk_scores for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table subscriptions enable row level security;
create policy "subscriptions_owner" on subscriptions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- squads: members can read; only the creator can write/update metadata
alter table squads enable row level security;
create policy "squads_member_read" on squads for select using (
    exists (select 1 from squad_members m where m.squad_id = squads.id and m.user_id = auth.uid())
);
create policy "squads_owner_write" on squads for insert with check (created_by = auth.uid());
create policy "squads_owner_update" on squads for update using (created_by = auth.uid());

alter table squad_members enable row level security;
create policy "squad_members_member_read" on squad_members for select using (
    exists (select 1 from squad_members m2 where m2.squad_id = squad_members.squad_id and m2.user_id = auth.uid())
);
create policy "squad_members_self_write" on squad_members for insert with check (user_id = auth.uid());
create policy "squad_members_self_delete" on squad_members for delete using (user_id = auth.uid());

-- duels: both participants can read/update
alter table duels enable row level security;
create policy "duels_participant" on duels for all
    using (a_user = auth.uid() or b_user = auth.uid())
    with check (a_user = auth.uid() or b_user = auth.uid());
