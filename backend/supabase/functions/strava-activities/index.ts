// ZANO — strava-activities Edge Function (Deno / Supabase Edge Functions), session 40.
//
// Returns the signed-in user's Strava activities that started after a timestamp, refreshing the Strava
// access token here when needed. The app feeds them into the same home/outdoor workout check Apple Health
// workouts go through (Core/Sources/Core/Verification/HomeWorkoutVerifier.swift), deduped against Health.
//
// POST /strava-activities
//   Authorization: Bearer <the user's Supabase access token>
//   { "after": <epoch seconds> }   clamped to at most 8 days back
// -> 200 { "activities": [ {
//          "id": "123",                       Strava activity id, as a string (64-bit ids)
//          "sportType": "Run",                sport_type (falls back to type)
//          "startDate": "2026-10-07T06:01:00Z",
//          "elapsedSeconds": 2400,            wall-clock length
//          "movingSeconds": 2280,             time actually moving (what the goal counts)
//          "manual": false,                   typed in by hand on Strava (does not count, spec §3/§9.8)
//          "hasHeartrate": true,
//          "maxHeartrate": 162                null without a heart-rate sensor
//        } ] }
// -> 404 { "error": "not_linked" }     no Strava connection for this user
// -> 410 { "error": "revoked" }        the athlete removed ZANO on Strava; the link was deleted
// -> 429 { "error": "rate_limited" }   Strava's app-wide limit; try again later
// -> 401 / 503 as strava-oauth
//
// Deliberately NOT returned: names, maps, GPS points, places, photos. Nothing is stored server-side
// (docs/spec.md §24: health data stays on the device except aggregated goal completion).
//
// UNVERIFIED (no live project / no Strava app): field names checked against the List Athlete Activities
// sample on developers.strava.com; per_page max (assumed 200) and the rate-limit status code are from memory.

import {
  adminClient,
  authenticatedUserId,
  freshLink,
  json,
  STRAVA_API,
  stravaConfigured,
  type StravaLinkRow,
} from "../_shared/strava.ts";

const MAX_LOOKBACK_S = 8 * 24 * 3600;
const PER_PAGE = 100;
const MAX_PAGES = 2;

interface StravaSummaryActivity {
  id: number;
  type?: string;
  sport_type?: string;
  start_date?: string;
  elapsed_time?: number;
  moving_time?: number;
  manual?: boolean;
  has_heartrate?: boolean;
  max_heartrate?: number | null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const userId = await authenticatedUserId(req);
  if (!userId) return json({ error: "unauthorized" }, 401);
  if (!stravaConfigured()) return json({ error: "not_configured" }, 503);

  let after = 0;
  try {
    after = Number((await req.json()).after ?? 0);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!Number.isFinite(after)) return json({ error: "bad_request" }, 400);
  const nowS = Math.floor(Date.now() / 1000);
  after = Math.max(Math.floor(after), nowS - MAX_LOOKBACK_S);

  const admin = adminClient();
  const { data: row } = await admin
    .from("strava_links")
    .select("user_id, athlete_id, access_token, refresh_token, expires_at, scope")
    .eq("user_id", userId)
    .maybeSingle();
  if (!row) return json({ error: "not_linked" }, 404);

  const link = await freshLink(admin, row as StravaLinkRow);
  if (link === "revoked") return json({ error: "revoked" }, 410);
  if (link === "unavailable") return json({ error: "strava_failed" }, 502);

  const activities: StravaSummaryActivity[] = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = `${STRAVA_API}/athlete/activities?after=${after}&per_page=${PER_PAGE}&page=${page}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${link.access_token}` } });
    if (res.status === 401) {
      await admin.from("strava_links").delete().eq("user_id", userId);
      return json({ error: "revoked" }, 410);
    }
    if (res.status === 429) return json({ error: "rate_limited" }, 429);
    if (!res.ok) return json({ error: "strava_failed" }, 502);
    const batch = await res.json() as StravaSummaryActivity[];
    if (!Array.isArray(batch)) return json({ error: "strava_failed" }, 502);
    activities.push(...batch);
    if (batch.length < PER_PAGE) break;
  }

  return json({
    activities: activities
      .filter((a) => typeof a.id === "number" && typeof a.start_date === "string")
      .map((a) => ({
        id: String(a.id),
        sportType: a.sport_type ?? a.type ?? "Workout",
        startDate: a.start_date,
        elapsedSeconds: Math.max(0, Math.floor(a.elapsed_time ?? 0)),
        movingSeconds: Math.max(0, Math.floor(a.moving_time ?? 0)),
        manual: a.manual === true,
        hasHeartrate: a.has_heartrate === true,
        maxHeartrate: typeof a.max_heartrate === "number" ? a.max_heartrate : null,
      })),
  });
});
