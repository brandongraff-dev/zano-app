// ZANO — risk-check Edge Function (Deno / Supabase Edge Functions)
//
// Implements docs/spec.md:
//   §11   Architecture        — "ML Service (Python/FastAPI, later) / /plan /risk /nudge (called
//                                by Edge Functions)" and "pg_cron jobs: nightly features, Sunday
//                                recaps" (this is the third pg_cron-driven job in that family).
//   §9.2  Slip Prediction     — "risk > threshold at 9 AM -> offer Plan B in the widget and shield
//                                copy; schedule a nudge at the user's historically best action
//                                hour." This function owns the *scoring* half (call the model,
//                                store the score) — reacting to a high score (surfacing Plan B,
//                                scheduling a nudge) is a separate consumer's job; see "Ownership
//                                boundary" below.
//   §13   Data Model          — reads `goals`/`users`/`streaks`/`goal_events`, upserts exactly the
//                                four columns `risk_scores` has: `(user_id, date, p_miss,
//                                model_version)`.
//
// Ownership boundary (see task brief): this file only reads the tables above and writes
// `risk_scores`. It does not write `nudges` or `daily_plans` — the ML response's `offer_plan_b`
// and `risk_tier` are echoed back in this function's own HTTP response (useful for the caller /
// for manual testing) but are NOT persisted anywhere, because `risk_scores` (docs/spec.md §13)
// has no column for them. Whichever future session wires "offer Plan B" / "schedule a nudge" off
// a high score needs to either (a) have that consumer re-derive the same threshold from
// `risk_scores.p_miss`, or (b) extend `risk_scores`'s columns in a migration — neither is decided
// here; flagged in this task's knownIssues rather than guessed at.
//
// ML service contract (read from the real ml-service/app/main.py + app/models.py, not guessed):
//   POST {ML_SERVICE_URL}/risk
//   Request  (RiskRequest,  app/models.py):
//     { user_id: uuid, date: "YYYY-MM-DD", day_of_week?: 0-6 (0=Mon..6=Sun),
//       days_since_last_miss?: int>=0, streak_length: int>=0, yesterday_completed?: bool,
//       sleep_hours?: number, calendar_density?: number, weather?: string, travel_flag?: bool,
//       hour_of_first_app_open?: 0-23 }
//   Response (RiskResponse, app/models.py):
//     { user_id: uuid, date: "YYYY-MM-DD", p_miss: 0..1, risk_tier: "low"|"medium"|"high",
//       model_version: string, offer_plan_b: bool }
//   main.py's /risk handler today is a stateless heuristic stub (STATUS comment at the top of that
//   file) that reads only a subset of RiskRequest's fields — this function still populates every
//   field it can derive from real tables, so the wiring is correct the moment a real model reads
//   the rest of them too. main.py has no auth check on /risk today; see `callRiskEndpoint` below
//   for how this function stays forward-compatible with that changing.
//
// "Active user" (this task's own wording, not a column on `users`): interpreted as any user with
// at least one row in `goals` where `active = true` (docs/spec.md §13's `goals.active`) — there's
// nothing to slip-predict for a user with zero active goals. This is a judgment call flagged here
// rather than left implicit; a future session may want a cheaper/broader definition.
//
// Feature sourcing (why this doesn't read `public.user_day_features`, migration 0004): that table
// is a *lagged* training table — a row for calendar date D is only materialized (by the nightly
// `zano_nightly_user_day_features` job, after D has fully elapsed) the day after D, and its own
// `completed_any` is D's actual outcome, not a forecast input. There is no "today" row to read at
// 9 AM. This function instead computes the same features live from `streaks` (already
// continuously up to date) and a bounded, timezone-aware read of recent `goal_events`, matching
// the exact field names/semantics `user_day_features`'s column comments document (which were
// themselves written to match ml-service's `RiskRequest` convention) — see `days_since_last_miss`
// / `streak_length` below.
//
// ---------------------------------------------------------------------------------------
// How this gets invoked (reference only — wiring the actual pg_cron schedule is a migration
// under backend/supabase/migrations/, out of this file's owned scope; this is the SQL whichever
// session owns that migration should run, using pg_cron + pg_net, both Supabase extensions. Same
// pattern as weekly-recap/index.ts's reference block):
//
//   select cron.schedule(
//     'zano-risk-check',
//     '0 9 * * *',  -- 9 AM server time daily. NOTE, same caveat as weekly-recap: pg_cron has one
//                   -- schedule for the whole project, so this is "9am server time", not 9am in
//                   -- each user's own timezone (docs/spec.md §9.2 says "risk > threshold at
//                   -- 9 AM" meaning the user's local 9 AM). Each user's own *target date* is
//                   -- still computed correctly per-user below (via users.tz) — only the
//                   -- invocation moment is a shared UTC clock tick. True per-user local-9am
//                   -- scoring would need per-user scheduling, not solved here.
//     $$
//     select net.http_post(
//       url := 'https://<project-ref>.functions.supabase.co/risk-check',
//       headers := jsonb_build_object(
//         'Content-Type', 'application/json',
//         'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
//                                          where name = 'service_role_key')
//       ),
//       body := '{}'::jsonb
//     );
//     $$
//   );
//
// ---------------------------------------------------------------------------------------
// HTTP contract
// ---------------------------------------------------------------------------------------
// POST /risk-check
// Headers:
//   Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>   (required — system/batch job, same
//                                                          rationale as weekly-recap/index.ts)
//   Content-Type: application/json
// Body (all optional):
//   {
//     "userId"?: "<uuid>",   // process exactly this user (testing / on-demand regen / backfill)
//     "date"?: "YYYY-MM-DD"  // override the target date (backfill a past day); interpreted as
//                             // that user's local calendar date, "yesterday" is derived from it
//   }
// -> 200:
//   - single-user mode: { "userId", "date", "stored": true, "pMiss", "riskTier", "offerPlanB",
//                          "modelVersion" } or an error object
//   - batch mode:       { "usersProcessed", "succeeded", "failed": [{ "userId", "error" }] }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// The ML service (docs/spec.md §11/§9.9) is not deployed anywhere yet — this is the env var that
// wires it in the moment it is. No default: an empty value means "not configured", handled as a
// ConfigError below rather than silently pointing at localhost or similar.
const ML_SERVICE_URL = Deno.env.get("ML_SERVICE_URL") ?? "";
// Optional: main.py's /risk endpoint has no auth check today (read from the real file, not
// guessed). If/when the ML service grows one, setting this env var starts sending it without any
// code change here; unset (the current reality) means no Authorization header is sent at all.
const ML_SERVICE_API_KEY = Deno.env.get("ML_SERVICE_API_KEY") ?? "";

const RISK_TIMEOUT_MS = 15_000;
// Serial per-user loop, same caps-the-blast-radius tradeoff weekly-recap/index.ts documents (see
// its BATCH_LIMIT comment) — a fan-out redesign is future work, not this task's scope.
const BATCH_LIMIT = Number(Deno.env.get("ZANO_RISK_CHECK_BATCH_LIMIT") ?? "500");
// Safety cap on the "which users have an active goal" query itself, independent of BATCH_LIMIT
// (which caps *distinct users* after dedup) — this caps raw `goals` rows scanned.
const ACTIVE_GOALS_ROW_CAP = Number(Deno.env.get("ZANO_RISK_CHECK_GOALS_ROW_CAP") ?? "20000");
// How far back to look for the most recent `miss` goal_event when computing
// `days_since_last_miss`. A miss older than this reads as "unknown" (undefined), not "never
// missed" — see computeFeaturesForUsers's comment.
const MISS_LOOKBACK_DAYS = 90;
// Window used to detect "did the user complete/verify anything yesterday (their local time)".
// 3 days safely contains any single local "yesterday" for every IANA timezone's UTC offset
// (-12..+14), with margin.
const RECENT_COMPLETION_LOOKBACK_DAYS = 3;
// Row cap on each of the two batched goal_events reads in computeFeaturesForUsers (PostgREST's
// own default max-rows would otherwise silently apply, e.g. 1000) — generous for this app's
// current pre-launch scale; see knownIssues if the active-user batch and its event volume grow
// enough for a single invocation to need pagination here.
const RECENT_EVENTS_ROW_CAP = 20_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------------------
// Timezone-aware local-date math (duplicated from weekly-recap/index.ts rather than shared —
// each Edge Function is deployed as an independent Deno program, same rationale that file states
// for its own duplicated `timingSafeEqual`).
// ---------------------------------------------------------------------------------------

interface LocalParts {
  year: number;
  month: number;
  day: number;
}

function safeTz(tz: string | null | undefined): string {
  if (!tz) return "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return "UTC";
  }
}

function localPartsAt(instant: Date, tz: string): LocalParts {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = fmt.formatToParts(instant);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
  };
}

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

function ymd(y: number, m: number, d: number): string {
  return `${y}-${pad2(m)}-${pad2(d)}`;
}

/** Adds `days` (may be negative) to a local calendar date via a UTC-noon anchor, so month/year
 *  rollovers are handled by Date.UTC's own normalization and no DST transition can shift the
 *  calendar date by a day. Mirrors weekly-recap/index.ts's helper of the same name. */
function addDaysToYmd(y: number, m: number, d: number, days: number): { y: number; m: number; d: number } {
  const anchor = new Date(Date.UTC(y, m - 1, d + days, 12, 0, 0));
  return { y: anchor.getUTCFullYear(), m: anchor.getUTCMonth() + 1, d: anchor.getUTCDate() };
}

function localDateString(instant: Date, tz: string): string {
  const p = localPartsAt(instant, tz);
  return ymd(p.year, p.month, p.day);
}

/** Calendar-date difference in whole days (a - b). Timezone-independent: a given Y-M-D triple's
 *  weekday/ordinal position never depends on which instant "midnight" maps to in any zone, so
 *  this anchors both sides at UTC noon rather than re-deriving from a formatted instant. */
function daysBetweenYmd(ay: number, am: number, ad: number, by: number, bm: number, bd: number): number {
  const a = Date.UTC(ay, am - 1, ad, 12, 0, 0);
  const b = Date.UTC(by, bm - 1, bd, 12, 0, 0);
  return Math.round((a - b) / 86_400_000);
}

/** ISO day-of-week for a calendar date, 0=Monday..6=Sunday (matches ml-service's
 *  `RiskRequest.day_of_week` convention, app/models.py, and migration 0004's
 *  `(extract(isodow from date)::int - 1)`). Pure calendar-date math — timezone-independent, same
 *  reasoning as `daysBetweenYmd`. */
function isoDayOfWeek0to6(y: number, m: number, d: number): number {
  const jsDay = new Date(Date.UTC(y, m - 1, d, 12, 0, 0)).getUTCDay(); // 0=Sun..6=Sat
  return (jsDay + 6) % 7; // 0=Mon..6=Sun
}

interface YmdParts {
  y: number;
  m: number;
  d: number;
}

function parseYmd(s: string): YmdParts {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!match) throw new BadRequestError("date must be YYYY-MM-DD");
  return { y: Number(match[1]), m: Number(match[2]), d: Number(match[3]) };
}

// ---------------------------------------------------------------------------------------
// ML service client
// ---------------------------------------------------------------------------------------

class ConfigError extends Error {}
class UpstreamError extends Error {}
class BadRequestError extends Error {}

/** Constant-time string compare — same rationale/approach as weekly-recap/index.ts's
 *  `timingSafeEqual`, duplicated here for the same reason. */
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const bytesA = enc.encode(a);
  const bytesB = enc.encode(b);
  const len = Math.max(bytesA.length, bytesB.length, 1);
  let diff = bytesA.length === bytesB.length ? 0 : 1;
  for (let i = 0; i < len; i++) {
    const byteA = i < bytesA.length ? bytesA[i] : 0;
    const byteB = i < bytesB.length ? bytesB[i] : 0;
    diff |= byteA ^ byteB;
  }
  return diff === 0;
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// Mirrors ml-service/app/models.py's RiskRequest exactly (field names/optionality), read from
// that file, not guessed.
interface RiskRequestBody {
  user_id: string;
  date: string; // YYYY-MM-DD
  day_of_week?: number; // 0=Mon..6=Sun
  days_since_last_miss?: number;
  streak_length: number;
  yesterday_completed?: boolean;
  sleep_hours?: number;
  calendar_density?: number;
  weather?: string;
  travel_flag?: boolean;
  hour_of_first_app_open?: number;
}

// Mirrors ml-service/app/models.py's RiskResponse exactly.
interface RiskResponseBody {
  user_id: string;
  date: string;
  p_miss: number;
  risk_tier: "low" | "medium" | "high";
  model_version: string;
  offer_plan_b: boolean;
}

function isRiskResponseBody(v: unknown): v is RiskResponseBody {
  if (typeof v !== "object" || v === null) return false;
  const r = v as Record<string, unknown>;
  return (
    typeof r.user_id === "string" &&
    typeof r.date === "string" &&
    typeof r.p_miss === "number" &&
    (r.risk_tier === "low" || r.risk_tier === "medium" || r.risk_tier === "high") &&
    typeof r.model_version === "string" &&
    typeof r.offer_plan_b === "boolean"
  );
}

async function callRiskEndpoint(req: RiskRequestBody): Promise<RiskResponseBody> {
  if (!ML_SERVICE_URL) throw new ConfigError("ML_SERVICE_URL is not set");

  const base = ML_SERVICE_URL.replace(/\/+$/, "");
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (ML_SERVICE_API_KEY) headers["authorization"] = `Bearer ${ML_SERVICE_API_KEY}`;

  let res: Response;
  try {
    res = await fetchWithTimeout(
      `${base}/risk`,
      { method: "POST", headers, body: JSON.stringify(req) },
      RISK_TIMEOUT_MS,
    );
  } catch (err) {
    throw new UpstreamError(`risk service request failed: ${err instanceof Error ? err.message : "unknown error"}`);
  }

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    console.error("risk-check: ML /risk call failed", res.status, detail.slice(0, 500));
    throw new UpstreamError(`risk service returned ${res.status}`);
  }

  const payload = await res.json().catch(() => null);
  if (!isRiskResponseBody(payload)) {
    throw new UpstreamError("risk service response did not match the expected RiskResponse shape");
  }
  return payload;
}

// ---------------------------------------------------------------------------------------
// Feature sourcing — live tables only (see header comment for why not user_day_features)
// ---------------------------------------------------------------------------------------

interface UserRow {
  id: string;
  tz: string | null;
}
interface StreakRow {
  user_id: string;
  current: number;
}
interface GoalEventTsRow {
  user_id: string;
  ts: string;
}

interface UserFeatures {
  dayOfWeek: number; // 0=Mon..6=Sun, for the target date
  streakLength: number;
  yesterdayCompleted: boolean | undefined;
  daysSinceLastMiss: number | undefined;
}

/** Computes each active user's RiskRequest feature fields from `streaks` (already live/current)
 *  and two bounded, batched `goal_events` reads (recent completions + recent misses), bucketed
 *  into each user's own local calendar day. One round trip per table for the whole batch, not per
 *  user — matches the read pattern the rest of this codebase (weekly-recap) uses for its own
 *  per-user aggregation, just batched across users up front instead of per-user in the loop. */
async function computeFeaturesForUsers(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  users: Array<{ id: string; tz: string }>,
  targetDateByUser: Map<string, YmdParts>,
  nowUtc: Date,
): Promise<Map<string, UserFeatures>> {
  const userIds = users.map((u) => u.id);
  const tzById = new Map(users.map((u) => [u.id, u.tz]));

  const [{ data: streakRows, error: streakErr }, { data: recentCompletions, error: completionsErr }, { data: recentMisses, error: missesErr }] =
    await Promise.all([
      supabase.from("streaks").select("user_id,current").in("user_id", userIds),
      supabase
        .from("goal_events")
        .select("user_id,ts")
        .in("user_id", userIds)
        .in("kind", ["complete", "verify"])
        .gte("ts", new Date(nowUtc.getTime() - RECENT_COMPLETION_LOOKBACK_DAYS * 86_400_000).toISOString())
        .lte("ts", nowUtc.toISOString())
        .limit(RECENT_EVENTS_ROW_CAP),
      supabase
        .from("goal_events")
        .select("user_id,ts")
        .in("user_id", userIds)
        .eq("kind", "miss")
        .gte("ts", new Date(nowUtc.getTime() - MISS_LOOKBACK_DAYS * 86_400_000).toISOString())
        .lte("ts", nowUtc.toISOString())
        .limit(RECENT_EVENTS_ROW_CAP),
    ]);

  if (streakErr) throw new Error(`streaks query failed: ${streakErr.message}`);
  if (completionsErr) throw new Error(`goal_events (completions) query failed: ${completionsErr.message}`);
  if (missesErr) throw new Error(`goal_events (misses) query failed: ${missesErr.message}`);

  const streakByUser = new Map<string, number>();
  for (const s of (streakRows ?? []) as StreakRow[]) streakByUser.set(s.user_id, s.current);

  // "Yesterday" (relative to each user's own target date) local-date string, computed once.
  const yesterdayYmdByUser = new Map<string, YmdParts>();
  for (const [userId, target] of targetDateByUser) {
    yesterdayYmdByUser.set(userId, addDaysToYmd(target.y, target.m, target.d, -1));
  }

  const yesterdayCompletedByUser = new Map<string, boolean>();
  for (const row of (recentCompletions ?? []) as GoalEventTsRow[]) {
    const yest = yesterdayYmdByUser.get(row.user_id);
    if (!yest) continue;
    const tz = safeTz(tzById.get(row.user_id));
    const localDate = localDateString(new Date(row.ts), tz);
    if (localDate === ymd(yest.y, yest.m, yest.d)) yesterdayCompletedByUser.set(row.user_id, true);
  }

  // Latest miss local-date per user (spec §9.2 "days since last miss"; migration 0004 convention:
  // "measured back from the day before `date`, 0 = yesterday itself was the last miss").
  const latestMissYmdByUser = new Map<string, YmdParts>();
  for (const row of (recentMisses ?? []) as GoalEventTsRow[]) {
    const tz = safeTz(tzById.get(row.user_id));
    const p = localPartsAt(new Date(row.ts), tz);
    const existing = latestMissYmdByUser.get(row.user_id);
    if (!existing || daysBetweenYmd(p.year, p.month, p.day, existing.y, existing.m, existing.d) > 0) {
      latestMissYmdByUser.set(row.user_id, { y: p.year, m: p.month, d: p.day });
    }
  }

  const result = new Map<string, UserFeatures>();
  for (const [userId, target] of targetDateByUser) {
    const yest = yesterdayYmdByUser.get(userId)!;
    const latestMiss = latestMissYmdByUser.get(userId);
    let daysSinceLastMiss: number | undefined;
    if (latestMiss) {
      const diff = daysBetweenYmd(yest.y, yest.m, yest.d, latestMiss.y, latestMiss.m, latestMiss.d);
      daysSinceLastMiss = Math.max(diff, 0);
    }
    result.set(userId, {
      dayOfWeek: isoDayOfWeek0to6(target.y, target.m, target.d),
      streakLength: streakByUser.get(userId) ?? 0,
      yesterdayCompleted: yesterdayCompletedByUser.has(userId) ? true : undefined,
      daysSinceLastMiss,
    });
  }
  return result;
}

// ---------------------------------------------------------------------------------------
// Per-user pipeline
// ---------------------------------------------------------------------------------------

interface RiskCheckResult {
  date: string;
  pMiss: number;
  riskTier: "low" | "medium" | "high";
  offerPlanB: boolean;
  modelVersion: string;
  stored: boolean;
}

async function processUserRisk(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  target: YmdParts,
  features: UserFeatures,
): Promise<RiskCheckResult> {
  const dateStr = ymd(target.y, target.m, target.d);

  const reqBody: RiskRequestBody = {
    user_id: userId,
    date: dateStr,
    day_of_week: features.dayOfWeek,
    streak_length: features.streakLength,
  };
  if (features.daysSinceLastMiss !== undefined) reqBody.days_since_last_miss = features.daysSinceLastMiss;
  if (features.yesterdayCompleted !== undefined) reqBody.yesterday_completed = features.yesterdayCompleted;
  // sleep_hours / calendar_density / weather / travel_flag / hour_of_first_app_open: no source
  // table in this schema yet (migration 0004's header comment documents the same gap for
  // user_day_features) — left unset, which the Pydantic model treats as "unknown", not "false"/0.

  const risk = await callRiskEndpoint(reqBody);

  const { error: upsertErr } = await supabase
    .from("risk_scores")
    .upsert(
      { user_id: userId, date: dateStr, p_miss: risk.p_miss, model_version: risk.model_version },
      { onConflict: "user_id,date" },
    );
  if (upsertErr) throw new Error(`risk_scores upsert failed: ${upsertErr.message}`);

  return {
    date: dateStr,
    pMiss: risk.p_miss,
    riskTier: risk.risk_tier,
    offerPlanB: risk.offer_plan_b,
    modelVersion: risk.model_version,
    stored: true,
  };
}

// ---------------------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------------------

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

// ---------------------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("risk-check: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not available in function env");
    return jsonResponse({ error: "internal_error", message: "server misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const expected = `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`;
  if (!timingSafeEqual(authHeader, expected)) {
    return jsonResponse({ error: "unauthorized", message: "service role authorization required" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    const raw = await req.text();
    if (raw.trim().length > 0) body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const userIdOverride = typeof body.userId === "string" ? body.userId : undefined;
  const dateOverride = typeof body.date === "string" ? body.date : undefined;
  const nowUtc = new Date();

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    let dateOverrideParts: YmdParts | undefined;
    if (dateOverride) dateOverrideParts = parseYmd(dateOverride);

    // ------------------------------------------------------------------
    // Resolve which user(s) to process, and each one's tz.
    // ------------------------------------------------------------------
    let targetUsers: UserRow[];
    if (userIdOverride) {
      const { data: userRow, error: userErr } = await supabase
        .from("users")
        .select("id, tz")
        .eq("id", userIdOverride)
        .single();
      if (userErr || !userRow) throw new Error(`user ${userIdOverride} not found`);
      targetUsers = [userRow as UserRow];
    } else {
      // "Active user" = has at least one active goal (docs/spec.md §13 `goals.active`) — see
      // header comment for why this reading was chosen. Two queries (distinct active-goal user
      // ids, then their tz) rather than a PostgREST embedded join, since this file doesn't know
      // the goals->users foreign-key constraint name PostgREST's embed syntax needs and guessing
      // it wrong would silently return zero rows rather than erroring loudly.
      const { data: activeGoalRows, error: goalsErr } = await supabase
        .from("goals")
        .select("user_id")
        .eq("active", true)
        .limit(ACTIVE_GOALS_ROW_CAP);
      if (goalsErr) throw new Error(`goals query failed: ${goalsErr.message}`);

      const distinctUserIds = [...new Set(((activeGoalRows ?? []) as Array<{ user_id: string }>).map((r) => r.user_id))].slice(
        0,
        BATCH_LIMIT,
      );

      if (distinctUserIds.length === 0) {
        return jsonResponse({ usersProcessed: 0, succeeded: 0, failed: [] }, 200);
      }

      const { data: userRows, error: usersErr } = await supabase.from("users").select("id, tz").in("id", distinctUserIds);
      if (usersErr) throw new Error(`users query failed: ${usersErr.message}`);
      targetUsers = (userRows ?? []) as UserRow[];
    }

    const usersWithTz = targetUsers.map((u) => ({ id: u.id, tz: safeTz(u.tz) }));

    // Defensive: avoids relying on supabase-js's `.in()` behavior for an empty id array (only
    // reachable if a user row was deleted between the two queries above — `goals.user_id` cascades
    // on delete, so this is a narrow race, not the common case already handled above).
    if (usersWithTz.length === 0) {
      return jsonResponse({ usersProcessed: 0, succeeded: 0, failed: [] }, 200);
    }

    // ------------------------------------------------------------------
    // Resolve each user's target date (override, or their own local "today").
    // ------------------------------------------------------------------
    const targetDateByUser = new Map<string, YmdParts>();
    for (const u of usersWithTz) {
      if (dateOverrideParts) {
        targetDateByUser.set(u.id, dateOverrideParts);
      } else {
        const p = localPartsAt(nowUtc, u.tz);
        targetDateByUser.set(u.id, { y: p.year, m: p.month, d: p.day });
      }
    }

    // ------------------------------------------------------------------
    // Batched feature computation, then per-user ML call + upsert.
    // ------------------------------------------------------------------
    const featuresByUser = await computeFeaturesForUsers(supabase, usersWithTz, targetDateByUser, nowUtc);

    if (userIdOverride) {
      const u = usersWithTz[0];
      const target = targetDateByUser.get(u.id)!;
      const features = featuresByUser.get(u.id)!;
      const result = await processUserRisk(supabase, u.id, target, features);
      return jsonResponse({ userId: u.id, ...result }, 200);
    }

    const failed: Array<{ userId: string; error: string }> = [];
    let succeeded = 0;

    for (const u of usersWithTz) {
      try {
        const target = targetDateByUser.get(u.id)!;
        const features = featuresByUser.get(u.id)!;
        await processUserRisk(supabase, u.id, target, features);
        succeeded++;
      } catch (err) {
        console.error("risk-check: failed for user", u.id, err);
        failed.push({ userId: u.id, error: err instanceof Error ? err.message : "unknown error" });
      }
    }

    return jsonResponse({ usersProcessed: usersWithTz.length, succeeded, failed }, 200);
  } catch (err) {
    if (err instanceof BadRequestError) return jsonResponse({ error: "bad_request", message: err.message }, 400);
    if (err instanceof ConfigError) {
      console.error("risk-check: config error", err.message);
      return jsonResponse({ error: "internal_error", message: "server misconfigured" }, 500);
    }
    if (err instanceof UpstreamError) {
      return jsonResponse({ error: "upstream_unavailable", message: err.message }, 502);
    }
    console.error("risk-check: unhandled error", err);
    return jsonResponse({ error: "internal_error", message: err instanceof Error ? err.message : "unknown" }, 500);
  }
});
