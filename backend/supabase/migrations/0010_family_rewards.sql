-- ZANO Family Link: parent reward minutes — docs/spec.md §5.23 (Family Link) and §5.2 (Time Bank).
-- Session 45. Builds on 0006_family_link.sql (untouched here).
--
-- Numbered 0010, not 0009: 0008 is Strava, and a parallel session may take 0009 (household quiet
-- times). Nothing here depends on 0009, so the gap is harmless if that session lands later or not at all.
--
-- What it adds:
--   family_rewards — a parent on an ACTIVE link sends their teen bonus Time Bank minutes with an optional
--                    short note ("+30 min, nice work on the homework"). The teen claims it in the app,
--                    which deposits the minutes into today's Time Bank on the device (they expire at
--                    midnight like every other Time Bank minute, spec §5.2).
--
-- Rules (enforced here, server side, not only in the app):
--   - Only the parent side of an active link can insert, and only for that link's teen (RLS insert policy).
--   - Both sides read the same rows (RLS select policy): the teen sees everything the parent sees.
--   - Only the teen can mark a reward claimed, through `claim_family_reward` (no client update/delete at all).
--   - Caps (trigger `family_rewards_enforce`): 1..120 minutes per reward; at most 240 minutes per link in any
--     rolling 24 hours. A rolling window rather than a calendar day because the server doesn't know either
--     person's time zone; the app mirrors the same numbers (`FamilyRewardRules`) to grey out chips early.
--   - Note: optional, plain text, at most 80 characters, no line breaks (check constraint; the app trims too).
--   - Never a punishment path: minutes are always positive, and there is no way for a parent to take
--     minutes back (no update/delete policy; the teen's Time Bank lives on the teen's device anyway).
--   - Rewards on a link that has been left are void: leaving voids every unclaimed reward (trigger on
--     family_links), and `claim_family_reward` refuses anything whose link isn't active.
--
-- KNOWN LIMITATIONS (flagged, not fixed here):
--   - Nothing here has been run: needs a live Supabase project (same as 0006).
--   - No push to the teen when a reward arrives; the app checks on open/foreground.

-- ---------------------------------------------------------------------------
-- family_rewards
-- ---------------------------------------------------------------------------
create table public.family_rewards (
    id uuid primary key default gen_random_uuid(),
    link_id uuid not null references public.family_links(id) on delete cascade,
    from_user uuid not null references public.users(id) on delete cascade,
    to_user uuid not null references public.users(id) on delete cascade,
    minutes integer not null check (minutes between 1 and 120),
    note text check (note is null or (char_length(note) between 1 and 80 and note !~ '[[:cntrl:]]')),
    created_at timestamptz not null default now(),
    claimed_at timestamptz,
    -- Set when the link is left before the teen claimed it. A void reward can never be claimed.
    voided_at timestamptz,
    check (from_user <> to_user),
    check (claimed_at is null or voided_at is null)
);
create index family_rewards_link_idx on public.family_rewards (link_id, created_at desc);
create index family_rewards_unclaimed_idx on public.family_rewards (to_user) where claimed_at is null and voided_at is null;

alter table public.family_rewards enable row level security;

-- Both sides of the link read the same rows.
create policy family_rewards_select on public.family_rewards
    for select using (exists (
        select 1 from public.family_links l
        where l.id = family_rewards.link_id and auth.uid() in (l.parent_id, l.teen_id)
    ));

-- Only the parent of an active link, only to that link's teen.
create policy family_rewards_parent_insert on public.family_rewards
    for insert to authenticated
    with check (
        from_user = auth.uid()
        and exists (
            select 1 from public.family_links l
            where l.id = family_rewards.link_id
              and l.parent_id = auth.uid()
              and l.teen_id = family_rewards.to_user
              and l.status = 'active'
        )
    );

-- Deliberately no update or delete policy: claiming goes through claim_family_reward, voiding through the
-- trigger below, and nobody can take minutes back.
revoke update, delete on public.family_rewards from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Insert guard: server-owned fields and the caps
-- ---------------------------------------------------------------------------
create or replace function public.family_rewards_enforce()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_recent integer;
begin
    -- Server-owned fields: a client can't backdate a reward to slip under the daily cap, or pre-claim it.
    new.created_at := now();
    new.claimed_at := null;
    new.voided_at := null;
    new.note := nullif(trim(coalesce(new.note, '')), '');

    if new.minutes is null or new.minutes < 1 or new.minutes > 120 then
        raise exception 'reward_too_large';
    end if;

    -- One link at a time, so two quick sends can't both slip under the cap.
    perform pg_advisory_xact_lock(hashtext('family_rewards:' || new.link_id::text));

    select coalesce(sum(minutes), 0) into v_recent
      from public.family_rewards
     where link_id = new.link_id
       and created_at > now() - interval '24 hours'
       and voided_at is null;
    if v_recent + new.minutes > 240 then
        raise exception 'reward_daily_cap';
    end if;
    return new;
end;
$$;

create trigger family_rewards_enforce
    before insert on public.family_rewards
    for each row execute function public.family_rewards_enforce();

-- ---------------------------------------------------------------------------
-- Leaving a link voids every reward not claimed yet
-- ---------------------------------------------------------------------------
create or replace function public.family_rewards_void_on_leave()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.status = 'left' and old.status <> 'left' then
        update public.family_rewards
           set voided_at = now()
         where link_id = new.id and claimed_at is null and voided_at is null;
    end if;
    return new;
end;
$$;

create trigger family_rewards_void_on_leave
    after update of status on public.family_links
    for each row execute function public.family_rewards_void_on_leave();

-- ---------------------------------------------------------------------------
-- The teen claims a reward. Returns the minutes to deposit.
--   'not_found'       — not this teen's reward
--   'void'            — the link was left (or isn't active), so the reward is void
--   'already_claimed' — claimed before; the app must not deposit again
-- ---------------------------------------------------------------------------
create or replace function public.claim_family_reward(p_reward_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_reward public.family_rewards;
    v_link_status text;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    select r.* into v_reward from public.family_rewards r where r.id = p_reward_id and r.to_user = auth.uid() for update;
    if not found then raise exception 'not_found'; end if;
    if v_reward.claimed_at is not null then raise exception 'already_claimed'; end if;
    select l.status into v_link_status from public.family_links l where l.id = v_reward.link_id and l.teen_id = auth.uid();
    if v_reward.voided_at is not null or v_link_status is distinct from 'active' then raise exception 'void'; end if;
    update public.family_rewards set claimed_at = now() where id = p_reward_id;
    return v_reward.minutes;
end;
$$;

revoke all on function public.claim_family_reward(uuid) from public;
grant execute on function public.claim_family_reward(uuid) to authenticated;
revoke all on function public.family_rewards_enforce() from public;
revoke all on function public.family_rewards_void_on_leave() from public;
