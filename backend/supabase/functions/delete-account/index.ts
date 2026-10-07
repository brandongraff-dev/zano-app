// ZANO — delete-account Edge Function (Deno / Supabase Edge Functions)
//
// Session 34. App Store guideline 5.1.1(v): an app that lets people create an account must let them delete
// it from inside the app. Settings > Account > Delete account calls this.
//
// POST /delete-account
//   Authorization: Bearer <the caller's Supabase access token>
// -> 200 { "deleted": true }
// -> 401 { "error": "unauthorized" }
// -> 500 { "error": "delete_failed" }   nothing is reported deleted unless the auth user is gone
//
// What goes:
//   1. Storage objects that row deletion alone doesn't remove: the caller's `meal-photos/<uid>/...` folder,
//      and every Family Link proof photo on a link the caller is part of (parent or teen).
//   2. The auth user. Every public table hangs off `public.users(id) on delete cascade`, and `public.users.id`
//      references `auth.users(id) on delete cascade` (0001_init.sql), so deleting the auth user removes the
//      caller's rows everywhere: goals, events, meals, streaks, the subscriptions mirror, squads they
//      created, household membership and households they own, family links. Household tasks other people
//      created stay, with `assignee_id` / `done_by` set to null (0007).
// Photo cleanup is best effort (logged); the user deletion is not: if it fails the function says so and the
// app keeps the person signed in so they can retry.
//
// The service-role key stays in this function (CLAUDE.md: API keys live only in Edge Functions). Deploy WITH
// JWT verification (the default): `supabase functions deploy delete-account`.
//
// UNVERIFIED (no live project): written from memory of supabase-js v2 (`auth.admin.deleteUser`,
// `storage.from().list()/remove()`, embedded-resource filters), in the same style as family-proof-open.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MEAL_BUCKET = "meal-photos";
const PROOF_BUCKET = "family-proofs";
const PAGE = 1000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "server_misconfigured" }, 500);

  // Who is asking? Verified by Supabase Auth from the caller's own token.
  const asUser = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data: userData } = await asUser.auth.getUser();
  const userId = userData?.user?.id;
  if (!userId) return json({ error: "unauthorized" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // 1a. Meal photos: everything under the caller's own folder, a page at a time.
  try {
    for (let round = 0; round < 50; round++) {
      const { data: files, error } = await admin.storage.from(MEAL_BUCKET).list(userId, { limit: PAGE });
      if (error || !files || files.length === 0) break;
      const paths = files.map((f: { name: string }) => `${userId}/${f.name}`);
      const { error: removeError } = await admin.storage.from(MEAL_BUCKET).remove(paths);
      if (removeError || files.length < PAGE) break;
    }
  } catch (e) {
    console.error("delete-account: meal photo cleanup failed", e);
  }

  // 1b. Family Link proof photos on any link the caller belongs to (the rows cascade; the files don't).
  try {
    const { data: links } = await admin
      .from("family_links")
      .select("id")
      .or(`parent_id.eq.${userId},teen_id.eq.${userId}`);
    const linkIds = (links ?? []).map((l: { id: string }) => l.id);
    if (linkIds.length > 0) {
      const { data: proofs } = await admin
        .from("family_proofs")
        .select("storage_path, family_tasks!inner(link_id)")
        .in("family_tasks.link_id", linkIds);
      const paths = (proofs ?? [])
        .map((p: { storage_path: string }) => p.storage_path)
        .filter((p: string) => Boolean(p));
      if (paths.length > 0) await admin.storage.from(PROOF_BUCKET).remove(paths);
    }
  } catch (e) {
    console.error("delete-account: proof photo cleanup failed", e);
  }

  // 2. The account itself; every row cascades from it.
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error("delete-account: deleteUser failed", deleteError);
    return json({ error: "delete_failed" }, 500);
  }
  return json({ deleted: true });
});
