// ZANO — family-proof-open Edge Function (Deno / Supabase Edge Functions)
//
// docs/spec.md §5.23: a Family Link proof photo is VIEW-ONCE. The parent opens it one time; it is deleted
// 10 minutes after that first open (a photo nobody opens is deleted after 24 hours, and an answered task's
// photo is deleted right away, see 0006_family_link.sql and family-proof-cleanup).
//
// POST /family-proof-open
//   Authorization: Bearer <the PARENT's Supabase access token>
//   { "proofId": "<uuid>" }
// -> 200 { "url": "<signed URL, valid 60 seconds>", "expiresAt": "<ISO time the photo is deleted>" }
// -> 403 { "error": "not_parent" }     the caller isn't the parent of this proof's link
// -> 410 { "error": "gone" }           already opened once, or expired
// -> 404 { "error": "not_found" }
//
// The first open is claimed with a single conditional UPDATE (first_opened_at is null and not expired), so
// two taps, two devices or a retry can never both get a URL. The signed URL is short on purpose: the app
// downloads the bytes straight away and shows them from memory; it must not cache or save them.
//
// The service-role key stays in this function (CLAUDE.md: API keys live only in Edge Functions).
//
// UNVERIFIED (no live project): written from memory of supabase-js v2 and the Storage signed-URL API.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUCKET = "family-proofs";
const OPEN_WINDOW_MINUTES = 10;
const URL_SECONDS = 60;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  let proofId = "";
  try {
    proofId = String((await req.json()).proofId ?? "");
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(proofId)) return json({ error: "bad_request" }, 400);

  // Who is asking? A user-scoped client, so row-level security decides what they may see.
  const asUser = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data: userData } = await asUser.auth.getUser();
  const userId = userData?.user?.id;
  if (!userId) return json({ error: "unauthorized" }, 401);

  // The caller must be able to see the proof's record (a member of the link)...
  const { data: proof } = await asUser.from("family_proofs").select("id, task_id").eq("id", proofId).maybeSingle();
  if (!proof) return json({ error: "not_found" }, 404);

  // ...and must be the PARENT, not the teen.
  const { data: link } = await asUser
    .from("family_tasks")
    .select("link_id, family_links!inner(parent_id)")
    .eq("id", proof.task_id)
    .maybeSingle();
  const parentId = (link as { family_links?: { parent_id?: string } } | null)?.family_links?.parent_id;
  if (parentId !== userId) return json({ error: "not_parent" }, 403);

  // Claim the one open. Only the service role may do this write.
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const now = new Date();
  const deleteAt = new Date(now.getTime() + OPEN_WINDOW_MINUTES * 60_000);
  const { data: claimed } = await admin
    .from("family_proofs")
    .update({ first_opened_at: now.toISOString(), expires_at: deleteAt.toISOString() })
    .eq("id", proofId)
    .is("first_opened_at", null)
    .gt("expires_at", now.toISOString())
    .select("storage_path")
    .maybeSingle();
  if (!claimed) return json({ error: "gone" }, 410);

  const { data: signed, error } = await admin.storage.from(BUCKET).createSignedUrl(claimed.storage_path, URL_SECONDS);
  if (error || !signed) return json({ error: "storage_failed" }, 502);
  return json({ url: signed.signedUrl, expiresAt: deleteAt.toISOString() });
});
