-- ZANO Household screen-free times — docs/spec.md §5.31 (session 44). Builds on 0007_household.sql.
--
-- A household can agree on shared screen-free windows ("Dinner 18:00-19:00 every day", "Bedtime 22:00-07:00
-- school nights"). This table holds only the agreement: a name, a start and end time, and the days. It holds
-- NOTHING about who joined, nobody's locks, apps or screen time:
--   - Joining a window is a choice each member makes on their own phone, and it stays on that phone (App Group
--     storage). Nobody can turn a lock on for someone else; there is no column or RPC that could.
--   - Which apps lock is picked from the member's own lock sets. Family Controls tokens never leave the device.
--   - Each member can leave a window, or the household, at any time, and the usual emergency unlock always works.
--
-- Times are minutes after local midnight (0-1439), read in each phone's own time zone. A window whose end is
-- earlier than its start crosses midnight (22:00-07:00); `weekdays` are the days the window STARTS on, using
-- Calendar's numbering (1 = Sunday ... 7 = Saturday), the same as the app's lock schedules.
--
-- Rules (same shape as 0007): members may read; nobody writes directly; security-definer RPCs for every change.
-- Any member can create a window; its creator or the household's owner can edit or delete it.
--
-- KNOWN LIMITATIONS: needs a live Supabase project and sign-in (docs/launch/supabase-setup.md); nothing here
-- has been run. No push: a new or changed window reaches other phones the next time they open ZANO.

create table public.household_quiet_times (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    name text not null check (char_length(name) between 1 and 40),
    start_minute integer not null check (start_minute between 0 and 1439),
    end_minute integer not null check (end_minute between 0 and 1439),
    weekdays integer[] not null check (
        cardinality(weekdays) between 1 and 7 and weekdays <@ array[1, 2, 3, 4, 5, 6, 7]
    ),
    created_by uuid references public.users(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- At least 15 minutes long, wrapping past midnight (the iOS DeviceActivity minimum, spec §27).
    check (((end_minute - start_minute + 1440) % 1440) >= 15)
);
create index household_quiet_times_household_idx on public.household_quiet_times (household_id);

alter table public.household_quiet_times enable row level security;

create policy household_quiet_times_select on public.household_quiet_times
    for select using (public.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Days sorted and without repeats, so the app's change detection sees one canonical form.
create or replace function public.normalized_quiet_weekdays(p_weekdays integer[])
returns integer[]
language sql
immutable
set search_path = ''
as $$
    select coalesce(array(select distinct d from unnest(p_weekdays) as d order by d), '{}'::integer[]);
$$;

create or replace function public.create_household_quiet_time(
    p_household_id uuid, p_name text, p_start_minute integer, p_end_minute integer, p_weekdays integer[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    if not public.is_household_member(p_household_id) then raise exception 'not_found'; end if;
    if (select count(*) from public.household_quiet_times where household_id = p_household_id) >= 20 then
        raise exception 'too_many_quiet_times';
    end if;
    insert into public.household_quiet_times (household_id, name, start_minute, end_minute, weekdays, created_by)
        values (p_household_id, trim(p_name), p_start_minute, p_end_minute,
                public.normalized_quiet_weekdays(p_weekdays), auth.uid())
        returning id into v_id;
    return v_id;
end;
$$;

-- The creator or the household's owner can change a window.
create or replace function public.update_household_quiet_time(
    p_id uuid, p_name text, p_start_minute integer, p_end_minute integer, p_weekdays integer[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.household_quiet_times q
        set name = trim(p_name),
            start_minute = p_start_minute,
            end_minute = p_end_minute,
            weekdays = public.normalized_quiet_weekdays(p_weekdays),
            updated_at = now()
        where q.id = p_id
          and public.is_household_member(q.household_id)
          and (q.created_by = auth.uid() or exists (
                select 1 from public.households h where h.id = q.household_id and h.owner_id = auth.uid()));
    if not found then raise exception 'not_found'; end if;
end;
$$;

-- The creator or the household's owner can delete a window. Phones that joined it stop locking for it the
-- next time ZANO opens and sees it gone.
create or replace function public.delete_household_quiet_time(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.household_quiet_times q
        where q.id = p_id
          and public.is_household_member(q.household_id)
          and (q.created_by = auth.uid() or exists (
                select 1 from public.households h where h.id = q.household_id and h.owner_id = auth.uid()));
    if not found then raise exception 'not_found'; end if;
end;
$$;

revoke all on function public.create_household_quiet_time(uuid, text, integer, integer, integer[]) from public, anon;
revoke all on function public.update_household_quiet_time(uuid, text, integer, integer, integer[]) from public, anon;
revoke all on function public.delete_household_quiet_time(uuid) from public, anon;
