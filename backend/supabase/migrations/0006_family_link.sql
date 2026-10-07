-- ZANO Family Link — docs/spec.md §5.23 (optional, teen-consented parent link; tasks; view-once proof
-- photos) and §24 (age 13+, photos and teen privacy). Builds on 0001/0002 (frozen shape, untouched here).
--
-- What it adds:
--   1. family_links  — a parent invites a teen with a code; the TEEN accepts (consent) and can leave
--                       at any time. Either side can end the link. Nothing is hidden from the teen.
--   2. family_tasks  — homework/chores the parent sets for a linked teen (title, due time, whether a
--                       photo is wanted) and the parent's answer: approved, or asked to redo.
--   3. family_proofs — the *record* of a proof photo (never the picture). The picture lives in the
--                       private `family-proofs` bucket and is VIEW-ONCE: the parent can open it one time
--                       (Edge Function `family-proof-open`); it is deleted 10 minutes after that first
--                       open, or 24 hours after upload if nobody opens it, or as soon as the parent
--                       answers. `family-proof-cleanup` does the deleting. Never used for model training.
--   4. Security-definer RPCs for every state change, so row-level security can stay strict (no direct
--      updates by clients at all).
--
-- Storage rule: the teen may upload to `family-proofs/<link_id>/<task_id>/<file>` only while the link is
-- active; there is NO select policy on the bucket, so no client can read a proof directly. The parent
-- sees one only through the Edge Function, which hands out a 60-second signed URL once.
--
-- KNOWN LIMITATIONS (flagged, not fixed here):
--   - Needs a live Supabase project and the app's auth wired (Session 7); nothing here has been run.
--   - Deleting storage files must go through the Storage API (deleting `storage.objects` rows in SQL
--     leaves the bytes behind), so cleanup is an Edge Function. Schedule it with pg_cron + pg_net (see the
--     comment at the end) or any external scheduler, every 5 minutes.
--   - A screenshot of an open proof can't be prevented; the app tells the teen when one is taken.
--   - Age is not verified server-side (spec §24: 13+ by the Terms; no ID check).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- family_links
-- ---------------------------------------------------------------------------
create table public.family_links (
    id uuid primary key default gen_random_uuid(),
    parent_id uuid not null references public.users(id) on delete cascade,
    teen_id uuid references public.users(id) on delete cascade,
    invite_code text not null unique check (invite_code ~ '^[A-Z0-9]{8}$'),
    status text not null default 'invited' check (status in ('invited', 'active', 'left')),
    created_at timestamptz not null default now(),
    accepted_at timestamptz,
    left_at timestamptz,
    check (teen_id is null or teen_id <> parent_id)
);
create index family_links_parent_idx on public.family_links (parent_id);
create index family_links_teen_idx on public.family_links (teen_id);

-- ---------------------------------------------------------------------------
-- family_tasks
-- ---------------------------------------------------------------------------
create table public.family_tasks (
    id uuid primary key default gen_random_uuid(),
    link_id uuid not null references public.family_links(id) on delete cascade,
    title text not null check (char_length(title) between 1 and 120),
    due_at timestamptz,
    requires_photo boolean not null default false,
    status text not null default 'open' check (status in ('open', 'submitted', 'approved', 'redo')),
    created_at timestamptz not null default now(),
    submitted_at timestamptz,
    decided_at timestamptz,
    decision_note text check (decision_note is null or char_length(decision_note) <= 200)
);
create index family_tasks_link_idx on public.family_tasks (link_id, status);

-- ---------------------------------------------------------------------------
-- family_proofs (the record, never the picture)
-- ---------------------------------------------------------------------------
create table public.family_proofs (
    id uuid primary key default gen_random_uuid(),
    task_id uuid not null references public.family_tasks(id) on delete cascade,
    storage_path text not null,
    uploaded_at timestamptz not null default now(),
    first_opened_at timestamptz,
    -- 24 hours after upload while unopened; set to first_opened_at + 10 minutes on the one open.
    expires_at timestamptz not null default (now() + interval '24 hours')
);
create index family_proofs_task_idx on public.family_proofs (task_id);
create index family_proofs_expiry_idx on public.family_proofs (expires_at);

-- ---------------------------------------------------------------------------
-- Row-level security: members read; nobody writes directly (RPCs below do)
-- ---------------------------------------------------------------------------
alter table public.family_links enable row level security;
alter table public.family_tasks enable row level security;
alter table public.family_proofs enable row level security;

create policy family_links_select on public.family_links
    for select using (auth.uid() in (parent_id, teen_id));

create policy family_tasks_select on public.family_tasks
    for select using (exists (
        select 1 from public.family_links l
        where l.id = family_tasks.link_id and auth.uid() in (l.parent_id, l.teen_id)
    ));

-- Members can see THAT a proof exists and when it expires, never the file.
create policy family_proofs_select on public.family_proofs
    for select using (exists (
        select 1 from public.family_tasks t
        join public.family_links l on l.id = t.link_id
        where t.id = family_proofs.task_id and auth.uid() in (l.parent_id, l.teen_id)
    ));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- A parent makes an invite. Returns the code to share (8 characters, A-Z and 0-9).
create or replace function public.create_family_invite()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_code text;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    loop
        v_code := substr(upper(encode(extensions.gen_random_bytes(4), 'hex')), 1, 8);
        begin
            insert into public.family_links (parent_id, invite_code) values (auth.uid(), v_code);
            return v_code;
        exception when unique_violation then
            -- try another code
        end;
    end loop;
end;
$$;

-- The teen accepts (this is the consent). Returns the link id.
create or replace function public.accept_family_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    update public.family_links
       set teen_id = auth.uid(), status = 'active', accepted_at = now()
     where invite_code = upper(trim(p_code))
       and status = 'invited' and teen_id is null and parent_id <> auth.uid()
    returning id into v_id;
    if v_id is null then raise exception 'invalid_invite'; end if;
    return v_id;
end;
$$;

-- Either side can end a link at any time.
create or replace function public.leave_family_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.family_links
       set status = 'left', left_at = now()
     where id = p_link_id and auth.uid() in (parent_id, teen_id) and status in ('invited', 'active');
    if not found then raise exception 'not_found'; end if;
end;
$$;

-- A parent adds a task for an active link.
create or replace function public.create_family_task(p_link_id uuid, p_title text, p_due_at timestamptz, p_requires_photo boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not exists (select 1 from public.family_links where id = p_link_id and parent_id = auth.uid() and status = 'active') then
        raise exception 'not_found';
    end if;
    insert into public.family_tasks (link_id, title, due_at, requires_photo)
    values (p_link_id, trim(p_title), p_due_at, coalesce(p_requires_photo, false))
    returning id into v_id;
    return v_id;
end;
$$;

-- The teen hands a task in, with the uploaded proof's storage path when a photo is wanted.
create or replace function public.submit_family_task(p_task_id uuid, p_proof_path text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_task public.family_tasks;
begin
    select t.* into v_task
      from public.family_tasks t
      join public.family_links l on l.id = t.link_id
     where t.id = p_task_id and l.teen_id = auth.uid() and l.status = 'active'
       and t.status in ('open', 'redo');
    if not found then raise exception 'not_found'; end if;
    if v_task.requires_photo and p_proof_path is null then raise exception 'photo_required'; end if;
    if p_proof_path is not null and p_proof_path not like (v_task.link_id::text || '/' || v_task.id::text || '/%') then
        raise exception 'bad_path';
    end if;
    update public.family_tasks set status = 'submitted', submitted_at = now() where id = p_task_id;
    if p_proof_path is not null then
        insert into public.family_proofs (task_id, storage_path) values (p_task_id, p_proof_path);
    end if;
end;
$$;

-- The parent answers: 'approved' or 'redo'. The proof (if any) is set to expire right now.
create or replace function public.decide_family_task(p_task_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_decision not in ('approved', 'redo') then raise exception 'bad_decision'; end if;
    update public.family_tasks t
       set status = p_decision, decided_at = now(), decision_note = nullif(left(coalesce(p_note, ''), 200), '')
      from public.family_links l
     where t.id = p_task_id and l.id = t.link_id and l.parent_id = auth.uid()
       and l.status = 'active' and t.status = 'submitted';
    if not found then raise exception 'not_found'; end if;
    update public.family_proofs set expires_at = least(expires_at, now()) where task_id = p_task_id;
end;
$$;

revoke all on function public.create_family_invite() from public;
revoke all on function public.accept_family_invite(text) from public;
revoke all on function public.leave_family_link(uuid) from public;
revoke all on function public.create_family_task(uuid, text, timestamptz, boolean) from public;
revoke all on function public.submit_family_task(uuid, text) from public;
revoke all on function public.decide_family_task(uuid, text, text) from public;
grant execute on function public.create_family_invite() to authenticated;
grant execute on function public.accept_family_invite(text) to authenticated;
grant execute on function public.leave_family_link(uuid) to authenticated;
grant execute on function public.create_family_task(uuid, text, timestamptz, boolean) to authenticated;
grant execute on function public.submit_family_task(uuid, text) to authenticated;
grant execute on function public.decide_family_task(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: a private bucket the teen can write to (while linked) and nobody can read from a client
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('family-proofs', 'family-proofs', false)
on conflict (id) do nothing;

create policy family_proofs_teen_upload on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'family-proofs'
        and exists (
            select 1 from public.family_links l
            where l.id::text = (storage.foldername(name))[1] and l.teen_id = auth.uid() and l.status = 'active'
        )
    );
-- Deliberately no select/update/delete policy on this bucket: the Edge Functions (service role) are the
-- only readers and deleters.

-- ---------------------------------------------------------------------------
-- Cleanup schedule (run family-proof-cleanup every 5 minutes). Needs pg_cron and pg_net, and a secret
-- stored in the project's vault; shown commented because it needs project-specific values:
--
--   select cron.schedule('zano_family_proof_cleanup', '*/5 * * * *', $$
--     select net.http_post(
--       url := 'https://<project-ref>.supabase.co/functions/v1/family-proof-cleanup',
--       headers := jsonb_build_object('x-cron-secret', '<FAMILY_CLEANUP_SECRET>', 'Content-Type', 'application/json'),
--       body := '{}'::jsonb);
--   $$);
-- ---------------------------------------------------------------------------
