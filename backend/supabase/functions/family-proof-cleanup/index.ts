// ZANO — family-proof-cleanup Edge Function (Deno / Supabase Edge Functions)
//
// docs/spec.md §5.23: proof photos are view-once and short-lived. This deletes every proof whose
// `expires_at` has passed (10 minutes after the one open, 24 hours if never opened, or right away once the
// parent has answered): the file in the private `family-proofs` bucket first, then its record. Run it every
// 5 minutes (see the pg_cron + pg_net note at the end of 0006_family_link.sql).
//
// POST /family-proof-cleanup
//   x-cron-secret: <FAMILY_CLEANUP_SECRET>    (a shared secret; this is not a user-facing endpoint)
// -> 200 { "deleted": <count> }
//
// A record is only deleted after its file was removed (or was already gone), so a storage hiccup leaves
// the row for the next run instead of orphaning a picture.
//
// UNVERIFIED (no live project): written from memory of supabase-js v2 Storage `remove`.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CRON_SECRET = Deno.env.get("FAMILY_CLEANUP_SECRET") ?? "";
const BUCKET = "family-proofs";
const BATCH = 200;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) return json({ error: "unauthorized" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: expired, error } = await admin
    .from("family_proofs")
    .select("id, storage_path")
    .lte("expires_at", new Date().toISOString())
    .limit(BATCH);
  if (error) return json({ error: "query_failed" }, 500);
  if (!expired || expired.length === 0) return json({ deleted: 0 });

  const { error: removeError } = await admin.storage.from(BUCKET).remove(expired.map((p) => p.storage_path));
  if (removeError) return json({ error: "storage_failed" }, 502);

  const { error: deleteError } = await admin.from("family_proofs").delete().in("id", expired.map((p) => p.id));
  if (deleteError) return json({ error: "delete_failed" }, 500);
  return json({ deleted: expired.length });
});
