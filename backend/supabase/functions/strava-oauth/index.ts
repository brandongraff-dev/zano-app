// ZANO — strava-oauth Edge Function (Deno / Supabase Edge Functions), session 40.
//
// Connects a ZANO user's Strava account. The client secret and both tokens stay here; the app only ever
// sees an authorize URL and "connected / not connected" (docs/spec.md §24, CLAUDE.md: keys live only in Edge
// Functions).
//
// POST /strava-oauth
//   Authorization: Bearer <the user's Supabase access token>
//   { "action": "start" }
//     -> 200 { "authorizeURL": "https://www.strava.com/oauth/mobile/authorize?..." }
//        The app opens it in ASWebAuthenticationSession; Strava redirects to zano://zano.app/strava?...
//   { "action": "exchange", "code": "...", "state": "...", "scope": "<scope from the redirect>" }
//     -> 200 { "connected": true, "athleteFirstName": "Sam" | null }
//     -> 400 { "error": "bad_state" }        unknown, expired (10 min) or someone else's state
//     -> 400 { "error": "scope_missing" }     the person unticked activity access on Strava's screen
//     -> 502 { "error": "strava_failed" }
//   { "action": "status" }
//     -> 200 { "connected": false } | { "connected": true, "scope": "...", "connectedAt": "<ISO>" }
//   { "action": "disconnect" }
//     -> 200 { "connected": false }            revokes at Strava (best effort), then deletes the row
// -> 401 { "error": "unauthorized" }   no or bad Supabase token
// -> 503 { "error": "not_configured" } STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET not set
//
// One Strava athlete belongs to one ZANO account: connecting an athlete already linked elsewhere moves the
// link here (the newer sign-in wins), so a single Strava workout can't verify two accounts.
//
// UNVERIFIED (no live project): supabase-js v2 calls written from memory; Strava endpoints checked against
// developers.strava.com (see ../_shared/strava.ts).

import {
  adminClient,
  authenticatedUserId,
  json,
  scopeAllowsActivities,
  STRAVA_AUTHORIZE_URL,
  STRAVA_CLIENT_ID,
  STRAVA_CLIENT_SECRET,
  STRAVA_REDIRECT_URI,
  STRAVA_REVOKE_URL,
  STRAVA_SCOPE,
  stravaConfigured,
  stravaToken,
} from "../_shared/strava.ts";

const STATE_TTL_MS = 10 * 60_000;

function randomState(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const userId = await authenticatedUserId(req);
  if (!userId) return json({ error: "unauthorized" }, 401);
  if (!stravaConfigured()) return json({ error: "not_configured" }, 503);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const action = String(body.action ?? "");
  const admin = adminClient();

  switch (action) {
    case "start": {
      // Drop this user's stale states, then mint a fresh one.
      await admin.from("strava_oauth_states").delete().eq("user_id", userId);
      const state = randomState();
      const { error } = await admin.from("strava_oauth_states").insert({ state, user_id: userId });
      if (error) return json({ error: "server_error" }, 500);
      const url = new URL(STRAVA_AUTHORIZE_URL);
      url.searchParams.set("client_id", STRAVA_CLIENT_ID);
      url.searchParams.set("redirect_uri", STRAVA_REDIRECT_URI);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("approval_prompt", "auto");
      url.searchParams.set("scope", STRAVA_SCOPE);
      url.searchParams.set("state", state);
      return json({ authorizeURL: url.toString() });
    }

    case "exchange": {
      const code = String(body.code ?? "");
      const state = String(body.state ?? "");
      const redirectScope = String(body.scope ?? "");
      if (!code || !/^[0-9a-f]{64}$/.test(state)) return json({ error: "bad_request" }, 400);

      // Claim the state once: delete it and check it was this user's and still fresh.
      const { data: claimed } = await admin
        .from("strava_oauth_states")
        .delete()
        .eq("state", state)
        .eq("user_id", userId)
        .select("created_at")
        .maybeSingle();
      if (!claimed || Date.now() - Date.parse(claimed.created_at) > STATE_TTL_MS) {
        return json({ error: "bad_state" }, 400);
      }

      const token = await stravaToken({ code, grant_type: "authorization_code" });
      if (typeof token === "number") return json({ error: "strava_failed" }, 502);
      const scope = token.scope ?? redirectScope;
      if (!scopeAllowsActivities(scope)) return json({ error: "scope_missing" }, 400);
      const athleteId = token.athlete?.id;
      if (typeof athleteId !== "number") return json({ error: "strava_failed" }, 502);

      // One athlete, one ZANO account: remove a link to this athlete held by another user first.
      await admin.from("strava_links").delete().eq("athlete_id", athleteId).neq("user_id", userId);
      const { error } = await admin.from("strava_links").upsert({
        user_id: userId,
        athlete_id: athleteId,
        access_token: token.access_token,
        refresh_token: token.refresh_token,
        expires_at: new Date(token.expires_at * 1000).toISOString(),
        scope,
        connected_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
      if (error) return json({ error: "server_error" }, 500);
      return json({ connected: true, athleteFirstName: token.athlete?.firstname ?? null });
    }

    case "status": {
      const { data } = await admin
        .from("strava_links")
        .select("scope, connected_at")
        .eq("user_id", userId)
        .maybeSingle();
      if (!data) return json({ connected: false });
      return json({ connected: true, scope: data.scope, connectedAt: data.connected_at });
    }

    case "disconnect": {
      const { data } = await admin
        .from("strava_links")
        .select("refresh_token")
        .eq("user_id", userId)
        .maybeSingle();
      if (data?.refresh_token) {
        // Best effort: Strava answers 200 whether or not the token existed. A failure here still unlinks
        // locally; the person can also remove ZANO under strava.com > Settings > My Apps.
        try {
          await fetch(STRAVA_REVOKE_URL, {
            method: "POST",
            headers: { Authorization: "Basic " + btoa(`${STRAVA_CLIENT_ID}:${STRAVA_CLIENT_SECRET}`) },
            body: new URLSearchParams({ token: data.refresh_token, token_type_hint: "refresh_token" }),
          });
        } catch {
          // ignore
        }
      }
      await admin.from("strava_links").delete().eq("user_id", userId);
      return json({ connected: false });
    }

    default:
      return json({ error: "bad_request" }, 400);
  }
});
