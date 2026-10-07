// ZANO — strava-webhook Edge Function (Deno / Supabase Edge Functions), session 40. Optional.
//
// Strava's push subscription (one per Strava API app). It does ONE job: when an athlete removes ZANO on
// strava.com, Strava sends a deauthorization event and this deletes their `strava_links` row (tokens), so
// nothing is kept for someone who left. New-activity events are acknowledged and ignored: there is no push
// to the phone (no APNs in this app), and the app already fetches on every foreground and Health wake-up.
//
// GET  /strava-webhook?hub.mode=subscribe&hub.challenge=X&hub.verify_token=T
//   -> 200 { "hub.challenge": "X" }   only when T == STRAVA_WEBHOOK_VERIFY_TOKEN (Strava waits 2 seconds)
// POST /strava-webhook   { object_type, object_id, aspect_type, updates, owner_id, subscription_id, event_time }
//   -> 200 always for well-formed events (Strava retries non-200s, up to 3 attempts)
//
// Deploy with --no-verify-jwt (Strava sends no Supabase token). Strava does not sign events, so an event is
// only acted on when `subscription_id` equals STRAVA_WEBHOOK_SUBSCRIPTION_ID (set it after creating the
// subscription; see docs/launch/supabase-setup.md, "Strava"). Until that secret is set, events are ignored.
//
// UNVERIFIED (no live project): the deauthorization event's exact `aspect_type` isn't documented; this
// matches on object_type "athlete" + updates.authorized == "false" as the docs describe.

import { adminClient, json } from "../_shared/strava.ts";

const VERIFY_TOKEN = Deno.env.get("STRAVA_WEBHOOK_VERIFY_TOKEN") ?? "";
const SUBSCRIPTION_ID = Deno.env.get("STRAVA_WEBHOOK_SUBSCRIPTION_ID") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method === "GET") {
    const params = new URL(req.url).searchParams;
    const challenge = params.get("hub.challenge") ?? "";
    if (params.get("hub.mode") !== "subscribe" || !VERIFY_TOKEN || params.get("hub.verify_token") !== VERIFY_TOKEN) {
      return json({ error: "forbidden" }, 403);
    }
    return json({ "hub.challenge": challenge });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let event: Record<string, unknown>;
  try {
    event = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!SUBSCRIPTION_ID || String(event.subscription_id ?? "") !== SUBSCRIPTION_ID) return json({ ok: true });

  const updates = (event.updates ?? {}) as Record<string, unknown>;
  const ownerId = Number(event.owner_id);
  if (event.object_type === "athlete" && String(updates.authorized) === "false" && Number.isFinite(ownerId)) {
    await adminClient().from("strava_links").delete().eq("athlete_id", ownerId);
  }
  return json({ ok: true });
});
