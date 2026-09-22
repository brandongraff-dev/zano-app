-- ZANO auth + storage wiring — docs/spec.md §11 (Architecture: "Auth (Sign in with Apple,
-- anonymous → linked)") and §24 (Safety, Legal & App Review — health/photo data handling).
-- Builds on top of 0001_init.sql (frozen shape, untouched here). Do not edit 0001_init.sql.
--
-- What this migration does:
--   1. A trigger on auth.users that auto-provisions the matching public.users row, so the app
--      (and Edge Functions) never have to insert into public.users manually after sign-up.
--   2. A private "meal-photos" Storage bucket + RLS on storage.objects so a user can only ever
--      read/write objects that live under their own auth.uid() path prefix. `public.meals.photo_path`
--      (0001_init.sql) is expected to store that same "<user_id>/<file>" path.
--
-- Auth flow this supports (§11): the app signs the user in anonymously on first launch
-- (`supabase.auth.signInAnonymously()`), which inserts a new row into auth.users immediately —
-- the trigger below fires exactly once at that point and creates the public.users row. If the
-- user later links Sign in with Apple, Supabase attaches a new identity to the SAME auth.users.id
-- (auth.users.is_anonymous flips to false; no new auth.users row is inserted), so the trigger does
-- not need to run again and this migration does not have to distinguish anonymous vs. linked here.
-- Populating users.apple_sub once linked is a separate, app-triggered write (the linking Edge
-- Function / App Intent owns that — not this trigger) and is intentionally out of scope for this
-- file; it is a narrow cross-module integration point for Session 7's Sync/Auth work, not this
-- migration.

-- ---------------------------------------------------------------------------
-- 1. Auto-provision public.users on new auth.users row
-- ---------------------------------------------------------------------------
-- id, created_at, tz, plan_tier all already default correctly at the public.users table level
-- (0001_init.sql), so the trigger only needs to supply the new auth user's id.
--
-- SECURITY DEFINER + empty search_path is the current Supabase-recommended pattern for triggers
-- on auth.users: the function runs with its owner's (migration role's) privileges — which is how
-- it can insert into public.users despite RLS being enabled on that table — and the empty
-- search_path plus fully-qualified `public.users` avoids search_path-hijacking.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.users (id)
    values (new.id)
    on conflict (id) do nothing;

    return new;
end;
$$;

comment on function public.handle_new_auth_user() is
    'Auto-creates the matching public.users row for every new auth.users row (anonymous sign-in '
    'or direct Sign in with Apple sign-up). See docs/spec.md §11.';

-- Explicit belt-and-suspenders grant: the role that performs the INSERT into auth.users
-- (supabase_auth_admin, via GoTrue) must be able to invoke this function to fire the trigger.
-- PostgreSQL grants EXECUTE to PUBLIC by default on function creation, so this is normally
-- redundant, but we make it explicit rather than relying on that default not having been revoked.
grant execute on function public.handle_new_auth_user() to supabase_auth_admin;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- 2. "meal-photos" private Storage bucket — §5.19 Quick Repeats / §9.5 meal vision
-- ---------------------------------------------------------------------------
-- public = false: objects are never served over a public URL; the app must always request a
-- signed URL (or rely on RLS via an authenticated client) to read a photo back. Meal photos are
-- health-adjacent data per §24 ("Health data ... never sell or share it").
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'meal-photos',
    'meal-photos',
    false,
    10485760,  -- 10 MB per object
    array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
)
on conflict (id) do nothing;

-- storage.objects ships with RLS already enabled on a standard Supabase project; this is
-- idempotent/defensive in case a bare Postgres instance is used instead.
alter table storage.objects enable row level security;

-- Path convention (must be followed by every writer — app upload code, meal-vision Edge Function):
--   meal-photos/<auth.uid()>/<file>
-- storage.foldername(name) splits the object's path on '/' and returns everything but the
-- filename, so (storage.foldername(name))[1] is the top-level folder — the owning user's id.
drop policy if exists "meal_photos_select_own" on storage.objects;
create policy "meal_photos_select_own"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'meal-photos'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "meal_photos_insert_own" on storage.objects;
create policy "meal_photos_insert_own"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'meal-photos'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "meal_photos_update_own" on storage.objects;
create policy "meal_photos_update_own"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'meal-photos'
        and auth.uid()::text = (storage.foldername(name))[1]
    )
    with check (
        bucket_id = 'meal-photos'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "meal_photos_delete_own" on storage.objects;
create policy "meal_photos_delete_own"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'meal-photos'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
