// ZANO — shared helpers for the strava-* Edge Functions (session 40).
//
// Supabase bundles `functions/_shared/` into each function that imports it (folders starting with `_` are
// not deployed as functions themselves).
//
// Secrets (Edge Functions > Secrets; never in the app or the repo — CLAUDE.md):
//   STRAVA_CLIENT_ID       the Strava API app's Client ID (a number)
//   STRAVA_CLIENT_SECRET   the Strava API app's Client Secret
//   STRAVA_REDIRECT_URI    optional, default "zano://zano.app/strava". Its host must equal the Strava app's
//                          "Authorization Callback Domain" (zano.app).
//
// Strava API surface, checked against developers.strava.com on 2026-10-07 (authentication + reference
// pages):
//   authorize   GET  https://www.strava.com/oauth/mobile/authorize  client_id, redirect_uri, response_type=code,
//                    approval_prompt=auto, scope, state
//   token       POST https://www.strava.com/oauth/token  client_id, client_secret, code, grant_type=authorization_code
//                    -> access_token, refresh_token, expires_at (epoch s), athlete{id, firstname}, scope(?)
//   refresh     POST https://www.strava.com/oauth/token  grant_type=refresh_token, refresh_token. Each refresh
//                    can return a NEW refresh token and the old one stops working at once, so always store it.
//   revoke      POST https://www.strava.com/oauth/revoke  Basic client_id:client_secret, token=<token>
//                    (recommended from 2026-06-01; the legacy /oauth/deauthorize goes away 2027-06-01)
//   activities  GET  https://www.strava.com/api/v3/athlete/activities?after=<epoch s>&per_page=<n>
// UNVERIFIED: whether the token response always carries `scope` (the docs' field list says so, the example
// response doesn't show it), so the app also forwards the `scope` it received on the redirect.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
export const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
export const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
export const STRAVA_CLIENT_ID = Deno.env.get("STRAVA_CLIENT_ID") ?? "";
export const STRAVA_CLIENT_SECRET = Deno.env.get("STRAVA_CLIENT_SECRET") ?? "";
export const STRAVA_REDIRECT_URI = Deno.env.get("STRAVA_REDIRECT_URI") ?? "zano://zano.app/strava";

/// `activity:read_all`, not `activity:read`: `read` hides activities set to "Only You", and plenty of people
/// keep their workouts private. Either grant is accepted (a person can untick `read_all` on Strava's screen).
export const STRAVA_SCOPE = "activity:read_all";

export const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
export const STRAVA_REVOKE_URL = "https://www.strava.com/oauth/revoke";
export const STRAVA_AUTHORIZE_URL = "https://www.strava.com/oauth/mobile/authorize";
export const STRAVA_API = "https://www.strava.com/api/v3";

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export function stravaConfigured(): boolean {
  return STRAVA_CLIENT_ID !== "" && STRAVA_CLIENT_SECRET !== "" && SERVICE_KEY !== "";
}

/// The caller's user id from their Supabase access token, or null. Same pattern as family-proof-open: a
/// user-scoped client asks Auth who the bearer is.
export async function authenticatedUserId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const asUser = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data } = await asUser.auth.getUser();
  return data?.user?.id ?? null;
}

export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_KEY);
}

export interface StravaLinkRow {
  user_id: string;
  athlete_id: number;
  access_token: string;
  refresh_token: string;
  expires_at: string;
  scope: string;
}

export interface StravaTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  scope?: string;
  athlete?: { id?: number; firstname?: string };
}

/// POSTs a form to Strava's token endpoint. Returns the parsed body, or the HTTP status on failure.
export async function stravaToken(params: Record<string, string>): Promise<StravaTokenResponse | number> {
  const body = new URLSearchParams({ client_id: STRAVA_CLIENT_ID, client_secret: STRAVA_CLIENT_SECRET, ...params });
  const res = await fetch(STRAVA_TOKEN_URL, { method: "POST", body });
  if (!res.ok) return res.status;
  const parsed = await res.json() as StravaTokenResponse;
  if (!parsed.access_token || !parsed.refresh_token || typeof parsed.expires_at !== "number") return 502;
  return parsed;
}

/// Refreshes the link's access token when it expires within 5 minutes and stores the new pair (Strava may
/// rotate the refresh token). Returns the usable row, or "revoked" when Strava refused the refresh token (the
/// athlete removed ZANO on strava.com): that row is deleted so the app shows "not connected".
export async function freshLink(
  admin: SupabaseClient,
  link: StravaLinkRow,
): Promise<StravaLinkRow | "revoked" | "unavailable"> {
  const expiresAtMs = Date.parse(link.expires_at);
  if (Number.isFinite(expiresAtMs) && expiresAtMs - Date.now() > 5 * 60_000) return link;

  const token = await stravaToken({ grant_type: "refresh_token", refresh_token: link.refresh_token });
  if (token === 400 || token === 401) {
    await admin.from("strava_links").delete().eq("user_id", link.user_id);
    return "revoked";
  }
  if (typeof token === "number") return "unavailable";

  const updated: StravaLinkRow = {
    ...link,
    access_token: token.access_token,
    refresh_token: token.refresh_token,
    expires_at: new Date(token.expires_at * 1000).toISOString(),
  };
  await admin
    .from("strava_links")
    .update({
      access_token: updated.access_token,
      refresh_token: updated.refresh_token,
      expires_at: updated.expires_at,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", link.user_id);
  return updated;
}

/// True when a granted scope string lets us list activities.
export function scopeAllowsActivities(scope: string): boolean {
  return scope.split(/[ ,]+/).some((s) => s === "activity:read" || s === "activity:read_all");
}
