-- ZANO waitlist signups — docs/spec.md §22 (Launch & Content Plan, Phase 0: "landing page +
-- waitlist"). Builds on top of 0001_init.sql and 0002_auth_storage.sql (frozen shape, untouched
-- here). Do not edit 0001_init.sql or 0002_auth_storage.sql.
--
-- What this migration does:
--   Creates waitlist_signups, a standalone table (no FK to auth.users/public.users — signups
--   happen pre-auth, straight from the public marketing site in landing/index.html, before anyone
--   has ever signed in) that captures an email address submitted via the Supabase anon key.
--
-- Why RLS is insert-only for anon:
--   landing/index.html talks to Supabase directly with the anon key (no Edge Function — see
--   landing/README.md), so that key is visible to anyone who views the page source. RLS is what
--   makes that safe: anon can INSERT a row and nothing else. No select/update/delete policy exists
--   for anon (or authenticated), so those actions are denied by default once RLS is enabled —
--   nobody using the public anon key can read back who else signed up, edit an entry, or delete
--   one. Only service_role (which bypasses RLS entirely, e.g. from Supabase Studio or a future
--   Edge Function that emails the list at launch) can read waitlist_signups.

create table if not exists waitlist_signups (
    id uuid primary key default gen_random_uuid(),
    email text unique not null,
    source text,
    created_at timestamptz not null default now()
);

alter table waitlist_signups enable row level security;

drop policy if exists "waitlist_signups_insert_anon" on waitlist_signups;
create policy "waitlist_signups_insert_anon"
    on waitlist_signups for insert
    to anon
    with check (true);
