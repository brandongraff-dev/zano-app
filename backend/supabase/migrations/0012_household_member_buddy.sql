-- ZANO Family page — docs/spec.md §5.31 (session 47). Builds on 0007_household.sql.
--
-- The Family page shows each household member as the buddy they picked ("the family portrait"). For that the
-- household needs to know two small, display-only things about each member:
--   - buddy:  which of the nine buddies they picked (null = the default, Stash),
--   - outfit: what that buddy is wearing (a small JSON object of item names, e.g. {"hat":"hatWizard"}).
-- Nothing else: no level, XP, streak, goals or screen time. Each member's own phone sets them when their buddy or
-- outfit changes; nobody can set anyone else's.
--
-- Also lets a member change the name they show in a household (they chose it when they joined).
--
-- KNOWN LIMITATIONS: needs a live Supabase project and sign-in; nothing here has been run. Other members see a
-- new buddy the next time they open ZANO (no push).

alter table public.household_members
    add column buddy text check (buddy in ('stash', 'zib', 'lox', 'pip', 'moko', 'brick', 'tank', 'volt', 'howl')),
    add column outfit jsonb check (outfit is null or (jsonb_typeof(outfit) = 'object' and octet_length(outfit::text) <= 512));

-- Sets my buddy (and outfit) on every household I'm in. Returns how many memberships changed.
create or replace function public.set_household_buddy(p_buddy text, p_outfit jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_count integer;
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    update public.household_members
        set buddy = p_buddy,
            outfit = case when p_outfit is null or p_outfit = '{}'::jsonb then null else p_outfit end
        where user_id = auth.uid();
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

-- Changes the name I show in one household.
create or replace function public.rename_household_member(p_household_id uuid, p_display_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then raise exception 'not_signed_in'; end if;
    update public.household_members
        set display_name = btrim(p_display_name)
        where household_id = p_household_id and user_id = auth.uid();
    if not found then raise exception 'not_found'; end if;
end;
$$;

revoke all on function public.set_household_buddy(text, jsonb) from public, anon;
revoke all on function public.rename_household_member(uuid, text) from public, anon;
