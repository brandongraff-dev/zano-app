-- ZANO Household — docs/spec.md §5.31 (a shared task list for the people someone lives or works with:
-- family, flatmates, a couple). Builds on 0001/0002 (users) and sits beside 0006 (Family Link, which is the
-- parent and teen link with homework proof). Optional, invite-only, and anyone can leave at any time.
--
-- What it adds:
--   1. households          — a name and a rotating invite code. The creator is the owner.
--   2. household_members   — who is in it and the name they chose to show (not their account name).
--   3. household_tasks     — shared to-dos: title, notes, due time, an optional assignee, who finished it.
--   4. Security-definer RPCs for every change, so row-level security can stay strict (members may read;
--      nobody writes directly).
--
-- Not in here on purpose: photos, locations, chat, or anything about screen time or locks. A household sees
-- tasks and who ticked them, nothing else about anyone.
--
-- KNOWN LIMITATIONS (flagged, not fixed here):
--   - Needs a live Supabase project and the app's sign-in wired (docs/launch/supabase-setup.md, step 9);
--     nothing here has been run.
--   - No push notifications: an assignment appears the next time the other person opens ZANO (their app then
--     re-plans local reminders). Real push needs APNs and a server job; flagged in the session doc.
--   - Eight members at most; ages are not checked (the Terms say 13+).

create extension if not exists pgcrypto;

create table public.households (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 1 and 40),
    owner_id uuid not null references public.users(id) on delete cascade,
    invite_code text not null unique check (invite_code ~ '^[A-Z0-9]{8}$'),
    created_at timestamptz not null default now()
);

create table public.household_members (
    household_id uuid not null references public.households(id) on delete cascade,
    user_id uuid not null references public.users(id) on delete cascade,
    display_name text not null check (char_length(display_name) between 1 and 30),
    joined_at timestamptz not null default now(),
    primary key (household_id, user_id)
);
create index household_members_user_idx on public.household_members (user_id);

create table public.household_tasks (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    title text not null check (char_length(title) between 1 and 120),
    notes text not null default '' check (char_length(notes) <= 500),
    due_at timestamptz,
    assignee_id uuid references public.users(id) on delete set null,
    created_by uuid references public.users(id) on delete set null,
    created_at timestamptz not null default now(),
    done_by uuid references public.users(id) on delete set null,
    done_at timestamptz
);
create index household_tasks_household_idx on public.household_tasks (household_id, done_at);

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_tasks enable row level security;

-- A helper the policies share: is the caller in this household?
create or replace function public.is_household_member(p_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.household_members m
        where m.household_id = p_household and m.user_id = auth.uid()
    );
$$;

create policy households_select on public.households
    for select using (public.is_household_member(id));

create policy household_members_select on public.household_members
    for select using (public.is_household_member(household_id));

create policy household_tasks_select on public.household_tasks
    for select using (public.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.create_household(p_name text, p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
    v_code text;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    if (select count(*) from public.household_members where user_id = auth.uid()) >= 5 then
        raise exception 'too_many_households';
    end if;
    loop
        v_code := substr(upper(encode(extensions.gen_random_bytes(4), 'hex')), 1, 8);
        exit when not exists (select 1 from public.households where invite_code = v_code);
    end loop;
    insert into public.households (name, owner_id, invite_code) values (trim(p_name), auth.uid(), v_code)
        returning id into v_id;
    insert into public.household_members (household_id, user_id, display_name)
        values (v_id, auth.uid(), trim(p_display_name));
    return v_id;
end;
$$;

-- Join with a code. Returns the household id.
create or replace function public.join_household(p_code text, p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    select id into v_id from public.households where invite_code = upper(trim(p_code));
    if v_id is null then raise exception 'invalid_invite'; end if;
    if (select count(*) from public.household_members where household_id = v_id) >= 8 then
        raise exception 'household_full';
    end if;
    insert into public.household_members (household_id, user_id, display_name)
        values (v_id, auth.uid(), trim(p_display_name))
        on conflict (household_id, user_id) do update set display_name = excluded.display_name;
    return v_id;
end;
$$;

-- The owner can change the code (to stop an old one working). Returns the new code.
create or replace function public.rotate_household_invite(p_household_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_code text;
begin
    if not exists (select 1 from public.households where id = p_household_id and owner_id = auth.uid()) then
        raise exception 'not_found';
    end if;
    loop
        v_code := substr(upper(encode(extensions.gen_random_bytes(4), 'hex')), 1, 8);
        exit when not exists (select 1 from public.households where invite_code = v_code);
    end loop;
    update public.households set invite_code = v_code where id = p_household_id;
    return v_code;
end;
$$;

-- Anyone can leave. The owner leaving hands ownership to the longest-standing member, or removes an empty
-- household.
create or replace function public.leave_household(p_household_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_next uuid;
begin
    delete from public.household_members where household_id = p_household_id and user_id = auth.uid();
    if not found then raise exception 'not_found'; end if;
    update public.household_tasks set assignee_id = null
        where household_id = p_household_id and assignee_id = auth.uid() and done_at is null;
    if exists (select 1 from public.households where id = p_household_id and owner_id = auth.uid()) then
        select user_id into v_next from public.household_members
            where household_id = p_household_id order by joined_at limit 1;
        if v_next is null then
            delete from public.households where id = p_household_id;
        else
            update public.households set owner_id = v_next where id = p_household_id;
        end if;
    end if;
end;
$$;

create or replace function public.create_household_task(
    p_household_id uuid, p_title text, p_due_at timestamptz, p_assignee uuid, p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not public.is_household_member(p_household_id) then raise exception 'not_found'; end if;
    if p_assignee is not null and not exists (
        select 1 from public.household_members where household_id = p_household_id and user_id = p_assignee
    ) then
        raise exception 'bad_assignee';
    end if;
    if (select count(*) from public.household_tasks where household_id = p_household_id and done_at is null) >= 200 then
        raise exception 'too_many_tasks';
    end if;
    insert into public.household_tasks (household_id, title, notes, due_at, assignee_id, created_by)
        values (p_household_id, trim(p_title), coalesce(p_notes, ''), p_due_at, p_assignee, auth.uid())
        returning id into v_id;
    return v_id;
end;
$$;

-- Anyone in the household can tick a task done (or undo it) and (re)assign it.
create or replace function public.set_household_task_done(p_task_id uuid, p_done boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_household uuid;
begin
    select household_id into v_household from public.household_tasks where id = p_task_id;
    if v_household is null or not public.is_household_member(v_household) then raise exception 'not_found'; end if;
    update public.household_tasks
        set done_by = case when p_done then auth.uid() else null end,
            done_at = case when p_done then now() else null end
        where id = p_task_id;
end;
$$;

create or replace function public.assign_household_task(p_task_id uuid, p_assignee uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_household uuid;
begin
    select household_id into v_household from public.household_tasks where id = p_task_id;
    if v_household is null or not public.is_household_member(v_household) then raise exception 'not_found'; end if;
    if p_assignee is not null and not exists (
        select 1 from public.household_members where household_id = v_household and user_id = p_assignee
    ) then
        raise exception 'bad_assignee';
    end if;
    update public.household_tasks set assignee_id = p_assignee where id = p_task_id;
end;
$$;

-- The person who made a task, or the owner, can delete it.
create or replace function public.delete_household_task(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.household_tasks t
        where t.id = p_task_id
          and public.is_household_member(t.household_id)
          and (t.created_by = auth.uid() or exists (
                select 1 from public.households h where h.id = t.household_id and h.owner_id = auth.uid()));
    if not found then raise exception 'not_found'; end if;
end;
$$;

-- Finished tasks older than 14 days can be cleared by the daily job (optional; see the setup guide).
create or replace function public.clear_old_household_tasks()
returns integer
language sql
security definer
set search_path = ''
as $$
    with gone as (
        delete from public.household_tasks where done_at is not null and done_at < now() - interval '14 days'
        returning 1
    )
    select count(*)::integer from gone;
$$;
revoke all on function public.clear_old_household_tasks() from public, anon, authenticated;

-- Lock the helper RPCs to signed-in users only.
revoke all on function public.create_household(text, text) from public, anon;
revoke all on function public.join_household(text, text) from public, anon;
revoke all on function public.rotate_household_invite(uuid) from public, anon;
revoke all on function public.leave_household(uuid) from public, anon;
revoke all on function public.create_household_task(uuid, text, timestamptz, uuid, text) from public, anon;
revoke all on function public.set_household_task_done(uuid, boolean) from public, anon;
revoke all on function public.assign_household_task(uuid, uuid) from public, anon;
revoke all on function public.delete_household_task(uuid) from public, anon;
