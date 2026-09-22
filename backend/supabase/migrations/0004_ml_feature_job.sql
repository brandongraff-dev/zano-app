-- ZANO ML feature pipeline — docs/spec.md §9.9 ("`goal_events` is the training table. Nightly
-- job materializes `user_day` features ... pg_cron jobs: nightly features") and §9.2 (Slip
-- Prediction feature list). Builds on top of 0001_init.sql/0002_auth_storage.sql/0003_waitlist.sql
-- (frozen shape, untouched here). Do not edit 0001/0002/0003.
--
-- What this migration does:
--   1. `public.user_day_features` — one row per (user_id, date), the materialized training/
--      scoring table for spec §9.2's slip-risk model. Column set mirrors §9.2's feature list as
--      closely as the current schema allows; see the "not yet derivable" block below for the
--      features spec §9.2 lists that no table in this schema captures yet.
--   2. `public.materialize_user_day_features(p_start_date, p_end_date)` — the nightly job itself,
--      a SECURITY DEFINER function that recomputes and upserts feature rows for a date range from
--      `goal_events` / `daily_plans` / `streaks` / `users`.
--   3. A pg_cron schedule (`zano_nightly_user_day_features`) that runs it nightly for "yesterday".
--
-- ml-service/app/features.py consumes rows from this table (or dicts shaped like it) to build the
-- model feature vector; ml-service/app/train_risk_model.py trains against them. See that
-- directory's module docstrings for the ml-service side of this pipeline.
--
-- KNOWN LIMITATIONS (flagged here, not fixed by this migration — see task's knownIssues):
--   - pg_cron availability depends on the Supabase project's plan/config (Database > Extensions).
--     If pg_cron isn't enabled, the `create extension` below fails and this migration cannot be
--     applied as-is until it is (or the cron.schedule block is removed and the job is triggered
--     externally, e.g. a scheduled Edge Function / GitHub Action calling this function over
--     `pg_net`/`postgres-js`).
--   - Day boundaries use each user's own `users.tz` (falling back to UTC) via `at time zone`, so
--     a "day" here means that user's local calendar day, not a single global UTC cutoff.
--   - `sleep_hours`, `calendar_density`, `weather`, `travel_flag`, and the onboarding Q5
--     fall-off pattern (spec §9.2's remaining listed features) have no source table in this
--     schema yet (no HealthKit sync table, no Calendar/travel-detection table, no
--     onboarding-answers table) — those columns exist on `user_day_features` for forward
--     compatibility but are always NULL until a future migration owns ingesting them.
--   - `streaks_current_at_materialize_time` / `streaks_freezes_left_at_materialize_time` are a
--     snapshot of `streaks`' CURRENT state at the moment this job runs, not a historically
--     accurate value for backfilled past dates (`streaks` only stores current state, not
--     history) — the `streak_length` column is the historically-correct one, computed fresh from
--     `goal_events` for whatever date it describes; prefer it over the snapshot columns.
--   - Recomputes a 400-day lookback per active user on every run to get correct rolling
--     streak/gap continuity (no incremental state is persisted between runs). Fine at current
--     scale; revisit (e.g. persist running state per user) if the user base grows large enough
--     for this to matter.
--   - `label_missed_all_goals` is `NOT completed_any` for that date, for every day a user existed
--     (from their `users.created_at` date onward) — it does not check whether the user had any
--     *active* goal that day, so very early post-signup days before onboarding finished a goal
--     could be mislabeled as a "miss" with nothing to miss. Acceptable noise for a v1 training
--     table; a future pass could join `goals` to gate this on `active` goals existing that day.
--   - `hour_of_first_event` approximates spec §9.2's "hour-of-first-app-open" using the first
--     `goal_events` row of the day — this schema has no separate app-open telemetry table, so it
--     is really "hour of first *verified goal action*", a day-open proxy, not a true app-open.

-- ---------------------------------------------------------------------------
-- 1. public.user_day_features
-- ---------------------------------------------------------------------------
create table if not exists public.user_day_features (
    user_id uuid not null references public.users(id) on delete cascade,
    date date not null,

    -- calendar / temporal (spec §9.2: "DOW", "hour-of-first-app-open")
    day_of_week smallint not null check (day_of_week between 0 and 6),  -- 0=Monday .. 6=Sunday,
        -- matches ml-service's RiskRequest.day_of_week convention (app/models.py)
    hour_of_first_event smallint check (hour_of_first_event between 0 and 23),

    -- this day's own goal_events rollup (becomes the training label below, and is itself useful
    -- context for the day it describes)
    completed_any boolean not null default false,
    events_count integer not null default 0,
    verified_events_count integer not null default 0,

    -- rolling features, computed as of the START of `date` (i.e. using only history strictly
    -- before `date` — what a real-time scorer would actually know at 9am that day)
    yesterday_completed boolean,          -- spec §9.2: "yesterday's completion"
    streak_length integer not null default 0,   -- spec §9.2: "streak length", consecutive
        -- completed days ending the day before `date`
    days_since_last_miss integer,         -- spec §9.2: "days since last miss", measured back
        -- from the day before `date` (0 = yesterday itself was the last miss) — matches
        -- ml-service/app/main.py's RiskRequest.days_since_last_miss test convention

    -- daily_plans rollup for this date (a user can have several goals, each with its own plan row)
    active_goal_count integer not null default 0,
    avg_difficulty_step numeric,
    any_plan_b_offered boolean not null default false,

    -- streaks CURRENT-state snapshot at materialize time — see "KNOWN LIMITATIONS" above
    streaks_current_at_materialize_time integer,
    streaks_freezes_left_at_materialize_time integer,

    -- spec §9.2 features with no source table yet — always NULL until a future session owns
    -- ingesting HealthKit sync / Calendar+travel detection / onboarding answers (see header)
    sleep_hours numeric,
    calendar_density numeric check (calendar_density between 0 and 1),
    weather text,
    travel_flag boolean,
    onboarding_fall_off_pattern text,     -- spec §7 Q5 answer, once an onboarding-answers table exists

    -- training label — spec §9.2: "did the user miss all goals on day D?"
    label_missed_all_goals boolean not null,

    materialized_at timestamptz not null default now(),

    primary key (user_id, date)
);

create index if not exists user_day_features_date_idx on public.user_day_features (date);

comment on table public.user_day_features is
    'Nightly-materialized per-(user,date) feature/label rows for the slip-risk model, '
    'docs/spec.md §9.2/§9.9. Written only by public.materialize_user_day_features(); see that '
    'function and this file''s header comment for exactly what each column means and what is '
    'still missing.';

alter table public.user_day_features enable row level security;

-- Read-only for the owning user (this table is internal ML plumbing, not something the app UI
-- displays directly today, but §13's blanket "RLS = user_id = auth.uid() on everything" rule
-- still applies). No insert/update/delete policy for `authenticated`/`anon` — every write goes
-- through the SECURITY DEFINER function below, which runs as the table owner and so is not
-- itself subject to RLS (same pattern as 0002_auth_storage.sql's handle_new_auth_user trigger).
drop policy if exists "user_day_features_owner_read" on public.user_day_features;
create policy "user_day_features_owner_read"
    on public.user_day_features for select
    using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. public.materialize_user_day_features(p_start_date, p_end_date)
-- ---------------------------------------------------------------------------
-- Recomputes and upserts public.user_day_features rows for every user who has ever logged a
-- goal_event, for each date in [p_start_date, p_end_date] (inclusive; p_end_date defaults to
-- p_start_date, so a single-date call is the common case). Idempotent: safe to re-run for the
-- same date range (e.g. manual backfill), since it's a plain upsert keyed on (user_id, date).
--
-- SECURITY DEFINER + empty search_path: this function reads/writes across ALL users' rows
-- (goal_events, daily_plans, streaks, users, user_day_features), which RLS would otherwise block
-- for any role that isn't each row's own owner. It runs with the owning (migration) role's
-- privileges instead, same pattern as 0002_auth_storage.sql's handle_new_auth_user(). Because of
-- that cross-user reach, EXECUTE is explicitly revoked from PUBLIC below — this must never be
-- callable by `authenticated`/`anon` (e.g. via PostgREST RPC), only by whatever role runs the
-- pg_cron schedule (postgres) or a service-role-authenticated admin path.
create or replace function public.materialize_user_day_features(
    p_start_date date default (current_date - 1),
    p_end_date date default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_end_date date := coalesce(p_end_date, p_start_date);
    v_rows_upserted integer := 0;
begin
    if p_start_date is null then
        raise exception 'materialize_user_day_features: p_start_date is required';
    end if;
    if v_end_date < p_start_date then
        raise exception 'materialize_user_day_features: p_end_date (%) is before p_start_date (%)',
            v_end_date, p_start_date;
    end if;

    with
    -- Users who have logged at least one goal_event, ever — no point materializing feature rows
    -- for an account that has never touched a goal.
    active_users as (
        select distinct user_id from public.goal_events
    ),
    -- One row per (user, local calendar date) across a 400-day lookback ending at v_end_date, so
    -- the rolling window functions below (streak_length, days_since_last_miss) see real
    -- day-to-day continuity instead of only the requested [p_start_date, v_end_date] slice. Never
    -- generates a date before the user's own signup date.
    timeline as (
        select
            au.user_id,
            gs::date as date,
            coalesce(bool_or(ge.kind = 'complete'), false) as completed_any
        from active_users au
        join public.users u on u.id = au.user_id
        cross join lateral generate_series(
            greatest(p_start_date - 400, u.created_at::date),
            v_end_date,
            interval '1 day'
        ) as gs
        left join public.goal_events ge
            on ge.user_id = au.user_id
            and (ge.ts at time zone coalesce(u.tz, 'UTC'))::date = gs::date
        group by au.user_id, gs::date
    ),
    -- Gaps-and-islands: miss_group increments every time a day is NOT completed (including that
    -- day itself), so consecutive completed=true days between misses share one group.
    streak_calc as (
        select
            user_id, date, completed_any,
            sum(case when completed_any then 0 else 1 end)
                over (partition by user_id order by date rows unbounded preceding) as miss_group,
            max(case when not completed_any then date end)
                over (partition by user_id order by date rows unbounded preceding) as last_miss_date_inclusive
        from timeline
    ),
    streak_calc2 as (
        select
            user_id, date, completed_any, last_miss_date_inclusive,
            case when completed_any
                 then row_number() over (partition by user_id, miss_group order by date)
                 else 0
            end as running_streak
        from streak_calc
    ),
    -- Shift everything by one day: `date`'s features describe state as of the START of `date`
    -- (i.e. derived only from `date - 1` and earlier), which is what a real predictor would know.
    timeline_lagged as (
        select
            user_id,
            date,
            completed_any,
            lag(completed_any) over (partition by user_id order by date) as prev_day_completed,
            lag(running_streak) over (partition by user_id order by date) as prev_day_streak,
            lag(last_miss_date_inclusive) over (partition by user_id order by date) as prev_last_miss_date
        from streak_calc2
    ),
    -- This date's own goal_events rollup (only needed for the requested range, not the lookback).
    -- The ts::date pre-filter is widened by a day on each side as a cheap index-friendly filter;
    -- the real (timezone-correct) bucketing happens in the GROUP BY below.
    daily_events_today as (
        select
            ge.user_id,
            (ge.ts at time zone coalesce(u.tz, 'UTC'))::date as date,
            count(*) as events_count,
            count(*) filter (where ge.verified) as verified_events_count,
            min(ge.ts) as first_event_ts
        from public.goal_events ge
        join public.users u on u.id = ge.user_id
        where ge.ts::date between p_start_date - 1 and v_end_date + 1
        group by ge.user_id, (ge.ts at time zone coalesce(u.tz, 'UTC'))::date
    ),
    -- This date's daily_plans rollup, aggregated across however many goals the user has.
    daily_plan_rollup as (
        select
            dp.user_id, dp.date,
            count(distinct dp.goal_id) as active_goal_count,
            avg(dp.difficulty_step) as avg_difficulty_step,
            bool_or(dp.plan_b_value is not null) as any_plan_b_offered
        from public.daily_plans dp
        where dp.date between p_start_date and v_end_date
        group by dp.user_id, dp.date
    ),
    to_upsert as (
        select
            tl.user_id,
            tl.date,
            (extract(isodow from tl.date)::int - 1)::smallint as day_of_week,
            case when de.first_event_ts is not null
                 then extract(hour from de.first_event_ts at time zone coalesce(u.tz, 'UTC'))::smallint
            end as hour_of_first_event,
            tl.completed_any,
            coalesce(de.events_count, 0) as events_count,
            coalesce(de.verified_events_count, 0) as verified_events_count,
            tl.prev_day_completed as yesterday_completed,
            coalesce(tl.prev_day_streak, 0) as streak_length,
            case when tl.prev_last_miss_date is null then null
                 else (tl.date - 1 - tl.prev_last_miss_date)
            end as days_since_last_miss,
            coalesce(dpr.active_goal_count, 0) as active_goal_count,
            dpr.avg_difficulty_step,
            coalesce(dpr.any_plan_b_offered, false) as any_plan_b_offered,
            s.current as streaks_current_at_materialize_time,
            s.freezes_left as streaks_freezes_left_at_materialize_time,
            (not tl.completed_any) as label_missed_all_goals
        from timeline_lagged tl
        join public.users u on u.id = tl.user_id
        left join daily_events_today de on de.user_id = tl.user_id and de.date = tl.date
        left join daily_plan_rollup dpr on dpr.user_id = tl.user_id and dpr.date = tl.date
        left join public.streaks s on s.user_id = tl.user_id
        where tl.date between p_start_date and v_end_date
    )
    insert into public.user_day_features (
        user_id, date, day_of_week, hour_of_first_event,
        completed_any, events_count, verified_events_count,
        yesterday_completed, streak_length, days_since_last_miss,
        active_goal_count, avg_difficulty_step, any_plan_b_offered,
        streaks_current_at_materialize_time, streaks_freezes_left_at_materialize_time,
        label_missed_all_goals, materialized_at
    )
    select
        user_id, date, day_of_week, hour_of_first_event,
        completed_any, events_count, verified_events_count,
        yesterday_completed, streak_length, days_since_last_miss,
        active_goal_count, avg_difficulty_step, any_plan_b_offered,
        streaks_current_at_materialize_time, streaks_freezes_left_at_materialize_time,
        label_missed_all_goals, now()
    from to_upsert
    on conflict (user_id, date) do update set
        day_of_week = excluded.day_of_week,
        hour_of_first_event = excluded.hour_of_first_event,
        completed_any = excluded.completed_any,
        events_count = excluded.events_count,
        verified_events_count = excluded.verified_events_count,
        yesterday_completed = excluded.yesterday_completed,
        streak_length = excluded.streak_length,
        days_since_last_miss = excluded.days_since_last_miss,
        active_goal_count = excluded.active_goal_count,
        avg_difficulty_step = excluded.avg_difficulty_step,
        any_plan_b_offered = excluded.any_plan_b_offered,
        streaks_current_at_materialize_time = excluded.streaks_current_at_materialize_time,
        streaks_freezes_left_at_materialize_time = excluded.streaks_freezes_left_at_materialize_time,
        label_missed_all_goals = excluded.label_missed_all_goals,
        materialized_at = excluded.materialized_at;

    get diagnostics v_rows_upserted = row_count;
    return v_rows_upserted;
end;
$$;

comment on function public.materialize_user_day_features(date, date) is
    'Nightly feature job (docs/spec.md §9.9): recomputes public.user_day_features for every '
    'active user across [p_start_date, p_end_date] (default: yesterday only) from goal_events, '
    'daily_plans, streaks and users. SECURITY DEFINER — see this file''s header comment before '
    'granting EXECUTE to any role beyond the pg_cron/postgres path.';

revoke all on function public.materialize_user_day_features(date, date) from public;

-- ---------------------------------------------------------------------------
-- 3. pg_cron schedule — nightly, for "yesterday" in whatever timezone the database session
--    defaults to (the function itself buckets each user's OWN day by their `tz`, independent of
--    what time the cron trigger fires in).
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;

do $$
begin
    if exists (select 1 from cron.job where jobname = 'zano_nightly_user_day_features') then
        perform cron.unschedule('zano_nightly_user_day_features');
    end if;
end;
$$;

select cron.schedule(
    'zano_nightly_user_day_features',
    '15 3 * * *',  -- 03:15 daily; late enough that "yesterday" is done everywhere pg_cron's own
                    -- clock considers it, early enough to be ready well before any 9 AM risk scoring
    $$select public.materialize_user_day_features();$$
);
