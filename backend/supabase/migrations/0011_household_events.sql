-- ZANO Household calendar — docs/spec.md §5.30 / §5.31 (session 46). Builds on 0007_household.sql.
--
-- A household can keep shared calendar events ("Soccer practice", "Grandma visits"). Each event says who can
-- see it:
--   - visibility = 'household': everyone in the household.
--   - visibility = 'members':   only the people listed in `audience` (member user ids), plus its creator.
-- "Only me" events are NEVER sent here: the app keeps them on the iPhone (the Planner's App Group store) or in
-- the person's own iOS calendars. There is no 'private' value on purpose, so a private event can't be uploaded
-- by mistake.
--
-- Row-level security is the privacy boundary, not the app: a member can read a row only if they created it, it
-- is household-wide, or their id is in its audience. Only the creator can insert, change or delete their event;
-- the household's owner can also delete events the owner can see (never one they aren't in the audience of:
-- Postgres applies the SELECT policy to a DELETE's rows too, so those rows don't exist for the owner).
--
-- The app also filters with the same rule after every fetch (`HouseholdEventRules.visible`), as a second line.
--
-- A trigger (security definer, so it can see rows the caller can't) checks what a policy can't:
--   - the audience is members of that household, without repeats or the creator, and non-empty for 'members';
--   - at most 500 upcoming events (not ended yet) per household;
--   - the household and creator of an event never change, and the timestamps are the server's.
-- When someone leaves a household, their own events there are deleted and they are taken out of every audience
-- (an event whose audience empties stays visible to its creator only).
--
-- Times are timestamptz. An all-day event is stored as the creator's local midnight to 23:59:59 of its last day;
-- a member in another time zone sees it shifted (known limitation).
--
-- KNOWN LIMITATIONS: needs a live Supabase project and sign-in (docs/launch/supabase-setup.md); nothing here has
-- been run. No push: a new or changed event reaches other phones the next time they open ZANO. No repeats or
-- invitations: people use their own iOS calendar for those.

create table public.household_events (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    created_by uuid not null default auth.uid() references public.users(id) on delete cascade,
    title text not null check (char_length(btrim(title)) between 1 and 120),
    notes text not null default '' check (char_length(notes) <= 500),
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    all_day boolean not null default false,
    visibility text not null default 'household' check (visibility in ('household', 'members')),
    audience uuid[] not null default '{}',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (ends_at >= starts_at),
    check (ends_at - starts_at <= interval '31 days'),
    -- Household-wide events carry no audience; a members-only event names at most 7 others (8 per household).
    -- An empty audience on a 'members' row only happens when everyone it was shared with left (see the trigger).
    check (
        (visibility = 'household' and cardinality(audience) = 0)
        or (visibility = 'members' and cardinality(audience) <= 7)
    )
);
create index household_events_household_idx on public.household_events (household_id, starts_at);
create index household_events_ends_idx on public.household_events (household_id, ends_at);

alter table public.household_events enable row level security;

-- Read: my own events, household-wide events, and events I'm in the audience of. Members only.
create policy household_events_select on public.household_events
    for select using (
        public.is_household_member(household_id)
        and (
            created_by = auth.uid()
            or visibility = 'household'
            or auth.uid() = any (audience)
        )
    );

-- Write: only as myself, only into a household I'm in.
create policy household_events_insert on public.household_events
    for insert with check (
        created_by = auth.uid()
        and public.is_household_member(household_id)
    );

create policy household_events_update on public.household_events
    for update using (created_by = auth.uid())
    with check (
        created_by = auth.uid()
        and public.is_household_member(household_id)
    );

-- Delete: the creator, or the household's owner (only rows the owner can see, see the header).
create policy household_events_delete on public.household_events
    for delete using (
        created_by = auth.uid()
        or exists (
            select 1 from public.households h
            where h.id = household_id and h.owner_id = auth.uid()
        )
    );

revoke all on public.household_events from anon;

-- ---------------------------------------------------------------------------
-- Checks a policy can't express
-- ---------------------------------------------------------------------------

create or replace function public.household_events_enforce()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_audience uuid[];
begin
    if tg_op = 'INSERT' then
        if auth.uid() is null then raise exception 'not_signed_in'; end if;
        new.created_by := auth.uid();
        new.created_at := now();
        -- One count at a time per household, so two quick inserts can't both slip under the cap.
        perform pg_advisory_xact_lock(hashtext('household_events:' || new.household_id::text));
        if (select count(*) from public.household_events e
                where e.household_id = new.household_id and e.ends_at >= now()) >= 500 then
            raise exception 'too_many_events';
        end if;
    else
        if new.household_id is distinct from old.household_id or new.created_by is distinct from old.created_by then
            raise exception 'not_allowed';
        end if;
        new.created_at := old.created_at;
    end if;
    new.updated_at := now();
    new.title := btrim(new.title);

    if new.visibility = 'household' then
        new.audience := '{}';
    else
        -- Without repeats and without the creator (they always see their own event).
        v_audience := coalesce(array(
            select distinct a from unnest(new.audience) as a
            where a is not null and a <> new.created_by
            order by a
        ), '{}'::uuid[]);
        -- A person choosing "Choose people" must pick someone. The leave trigger below (one level deeper) may
        -- leave an audience empty; that event then stays visible to its creator only.
        if cardinality(v_audience) = 0 and pg_trigger_depth() <= 1 then
            raise exception 'empty_audience';
        end if;
        if exists (
            select 1 from unnest(v_audience) as a
            where not exists (
                select 1 from public.household_members m
                where m.household_id = new.household_id and m.user_id = a
            )
        ) then
            raise exception 'bad_audience';
        end if;
        new.audience := v_audience;
    end if;
    return new;
end;
$$;

create trigger household_events_enforce
    before insert or update on public.household_events
    for each row execute function public.household_events_enforce();

-- Leaving a household: delete the leaver's own events there and take them out of every audience.
create or replace function public.household_events_on_member_left()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.household_events
        where household_id = old.household_id and created_by = old.user_id;
    update public.household_events
        set audience = array_remove(audience, old.user_id)
        where household_id = old.household_id and old.user_id = any (audience);
    return old;
end;
$$;

create trigger household_events_member_left
    after delete on public.household_members
    for each row execute function public.household_events_on_member_left();

-- Events that ended more than 90 days ago can be cleared by the daily job (optional; see the setup guide).
create or replace function public.clear_old_household_events()
returns integer
language sql
security definer
set search_path = ''
as $$
    with gone as (
        delete from public.household_events where ends_at < now() - interval '90 days'
        returning 1
    )
    select count(*)::integer from gone;
$$;
revoke all on function public.clear_old_household_events() from public, anon, authenticated;
revoke all on function public.household_events_enforce() from public, anon, authenticated;
revoke all on function public.household_events_on_member_left() from public, anon, authenticated;
