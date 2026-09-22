// ZANO — weekly-recap Edge Function (Deno / Supabase Edge Functions)
//
// Implements docs/spec.md:
//   §9.6  Weekly Recap Writer — "Sunday 6 PM job: aggregate the week, call an LLM with a strict
//                                template (max 60 words, coach voice, one specific win, one
//                                specific suggestion, no shame). Store as a card; render as
//                                shareable image on device."
//   §13   Data Model          — reads `goal_events`/`goals`/`daily_plans`/`streaks`/`users`,
//                                writes into `recaps` exactly as specified there.
//   §11   Architecture        — "pg_cron jobs: nightly features, Sunday recaps" and
//                                "API keys live only in Edge Functions" (also §9, §24).
//
// Ownership boundary (see task brief): this file only reads the tables above and writes
// `recaps`. It writes `text` + `stats` only — `image_path` is intentionally left null, because
// §9.6/§5.14 render the shareable 9:16 image on-device, not here.
//
// ---------------------------------------------------------------------------------------
// How this gets invoked (reference only — wiring the actual pg_cron schedule is a migration
// under backend/supabase/migrations/, which is out of this file's owned scope; this is the SQL
// whichever session owns that migration should run, using pg_cron + pg_net, both Supabase
// extensions):
//
//   select cron.schedule(
//     'zano-weekly-recap',
//     '0 18 * * 0',  -- Sunday 18:00 UTC. NOTE: pg_cron has one schedule for the whole project,
//                    -- so this is "6pm server time", not 6pm in each user's own timezone. Each
//                    -- user's own week boundary is still computed correctly per-user below
//                    -- (via users.tz) — only the *invocation* moment is a shared UTC clock tick.
//                    -- True per-user local-6pm delivery would need per-user scheduling, which
//                    -- is a real product nuance, not solved here.
//     $$
//     select net.http_post(
//       url := 'https://<project-ref>.functions.supabase.co/weekly-recap',
//       headers := jsonb_build_object(
//         'Content-Type', 'application/json',
//         -- The service role key belongs in Vault, decrypted only inside this cron job body —
//         -- never hardcode it into the migration source itself.
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
// POST /weekly-recap
// Headers:
//   Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>   (required — this is a system/batch job
//                                                          with no single user's session to scope
//                                                          it to, so it authenticates as the
//                                                          service role rather than a user JWT,
//                                                          and uses the service-role client
//                                                          deliberately to read/write across
//                                                          users. See "Auth" below.)
//   Content-Type: application/json
// Body (all optional):
//   {
//     "userId"?: "<uuid>",      // process exactly this user (testing / on-demand regen / backfill)
//     "weekStart"?: "YYYY-MM-DD" // override the computed week (backfill a past week); interpreted
//                                 // as that user's local calendar date for the Monday the week starts
//   }
// → 200:
//   - single-user mode: { "userId", "weekStart", "stored": true } or an error object
//   - batch mode:       { "usersProcessed", "succeeded", "failed": [{ "userId", "error" }] }
//
// Auth: the caller must present the project's service role key as a bearer token. That's the
// standard pattern for a pg_cron → pg_net → Edge Function call (see the SQL above) — the service
// role key itself is a valid Supabase JWT (role: "service_role"), so it also satisfies this
// function's default verify_jwt=true gate. Comparing it again here (string equality) is a second,
// explicit check so this endpoint can never be triggered by an arbitrary authenticated user.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const LLM_API_KEY = Deno.env.get("ZANO_LLM_API_KEY") ?? "";
const LLM_API_URL = Deno.env.get("ZANO_LLM_API_URL") ?? "https://api.anthropic.com/v1/messages";
const LLM_API_VERSION = Deno.env.get("ZANO_LLM_API_VERSION") ?? "2023-06-01";
// No default model string — see meal-vision/index.ts for why. Must be set via `supabase secrets set`.
const LLM_MODEL = Deno.env.get("ZANO_LLM_MODEL") ?? "";

const RECAP_TIMEOUT_MS = 20_000;
const MAX_RECAP_WORDS = 60;
// Serial per-user loop; caps one invocation's blast radius until a fan-out redesign exists.
// See knownIssues in the session report.
const BATCH_LIMIT = Number(Deno.env.get("ZANO_WEEKLY_RECAP_BATCH_LIMIT") ?? "500");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------------------
// Timezone-aware week-boundary math
// ---------------------------------------------------------------------------------------
// goal_events.ts is a timestamptz; a user's "week" should be Mon–Sun in *their* local time
// (users.tz, §13), not server UTC. Deno ships full ICU, so Intl.DateTimeFormat with a
// timeZone option gives correct local wall-clock fields for any IANA zone without a third-party
// tz database. Converting that local wall-clock back to a precise UTC instant (to bound the
// goal_events query) uses the standard "double formatting" offset trick below — correct for the
// vast majority of zones/dates; see knownIssues for the rare DST-boundary edge case.

const WEEKDAY_INDEX: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
const WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

interface LocalParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  weekday: number; // 1=Mon .. 7=Sun
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
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
    weekday: "short",
  });
  const parts = fmt.formatToParts(instant);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")) % 24, // some locales render midnight as "24"
    minute: Number(get("minute")),
    second: Number(get("second")),
    weekday: WEEKDAY_INDEX[get("weekday")] ?? 1,
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
 *  calendar date by a day. */
function addDaysToYmd(y: number, m: number, d: number, days: number): { y: number; m: number; d: number } {
  const anchor = new Date(Date.UTC(y, m - 1, d + days, 12, 0, 0));
  return { y: anchor.getUTCFullYear(), m: anchor.getUTCMonth() + 1, d: anchor.getUTCDate() };
}

/** UTC instant for local midnight (00:00:00) on the given calendar date in `tz`. */
function zonedMidnightToUtc(y: number, m: number, d: number, tz: string): Date {
  const guess = Date.UTC(y, m - 1, d, 0, 0, 0);
  const seen = localPartsAt(new Date(guess), tz);
  const seenAsUtc = Date.UTC(seen.year, seen.month - 1, seen.day, seen.hour, seen.minute, seen.second);
  const correction = guess - seenAsUtc;
  return new Date(guess + correction);
}

function mostRecentMondayLocal(nowUtc: Date, tz: string): { y: number; m: number; d: number } {
  const parts = localPartsAt(nowUtc, tz);
  const daysSinceMonday = parts.weekday - 1; // weekday 1=Mon
  return addDaysToYmd(parts.year, parts.month, parts.day, -daysSinceMonday);
}

interface WeekRange {
  weekStartStr: string; // Monday, local calendar date, "YYYY-MM-DD"
  weekEndStr: string; // following Monday, local calendar date (exclusive)
  startUtc: Date;
  endUtc: Date;
  tz: string;
}

function computeWeekRange(nowUtc: Date, tz: string, weekStartOverride?: string): WeekRange {
  let y: number, m: number, d: number;
  if (weekStartOverride) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(weekStartOverride);
    if (!match) throw new BadRequestError("weekStart must be YYYY-MM-DD");
    y = Number(match[1]);
    m = Number(match[2]);
    d = Number(match[3]);
  } else {
    ({ y, m, d } = mostRecentMondayLocal(nowUtc, tz));
  }
  const end = addDaysToYmd(y, m, d, 7);
  return {
    weekStartStr: ymd(y, m, d),
    weekEndStr: ymd(end.y, end.m, end.d),
    startUtc: zonedMidnightToUtc(y, m, d, tz),
    endUtc: zonedMidnightToUtc(end.y, end.m, end.d, tz),
    tz,
  };
}

function localDateString(instant: Date, tz: string): string {
  const p = localPartsAt(instant, tz);
  return ymd(p.year, p.month, p.day);
}

// ---------------------------------------------------------------------------------------
// Aggregation
// ---------------------------------------------------------------------------------------

interface GoalRow {
  id: string;
  title: string;
  type: string;
  unit: string | null;
  target_value: number | null;
  active: boolean;
}
interface DailyPlanRow {
  goal_id: string;
  date: string;
}
interface GoalEventRow {
  goal_id: string;
  ts: string;
  kind: "log" | "verify" | "complete" | "miss" | "plan_b" | "freeze";
  value: number | null;
}
interface StreakRow {
  current: number;
  best: number;
  freezes_left: number;
}

interface PerGoalSummary {
  goalId: string;
  title: string;
  type: string;
  unit: string | null;
  planned: number;
  completedDays: number;
  missedCount: number;
  totalValue: number | null;
}

interface DaySummary {
  date: string;
  weekday: string;
  completedGoalCount: number;
}

interface WeekSummary {
  weekStart: string;
  weekEnd: string;
  timezone: string;
  days: DaySummary[];
  daysActive: number;
  bestDay: DaySummary | null;
  totals: {
    byKind: Record<string, number>;
    completedGoalInstances: number;
    missedGoalInstances: number;
  };
  goals: PerGoalSummary[];
  weakestGoal: PerGoalSummary | null;
  streak: { current: number; best: number } | null;
  hasActivity: boolean;
}

function computeWeekSummary(
  range: WeekRange,
  goals: GoalRow[],
  dailyPlans: DailyPlanRow[],
  events: GoalEventRow[],
  streak: StreakRow | null,
): WeekSummary {
  const goalsById = new Map(goals.map((g) => [g.id, g]));

  const plannedByGoal = new Map<string, number>();
  for (const p of dailyPlans) plannedByGoal.set(p.goal_id, (plannedByGoal.get(p.goal_id) ?? 0) + 1);

  const completedDatesByGoal = new Map<string, Set<string>>();
  const missedCountByGoal = new Map<string, number>();
  const valueSumByGoal = new Map<string, number>();
  const byKind: Record<string, number> = {};

  for (const ev of events) {
    byKind[ev.kind] = (byKind[ev.kind] ?? 0) + 1;
    if (ev.kind === "complete" || ev.kind === "verify") {
      const date = localDateString(new Date(ev.ts), range.tz);
      const set = completedDatesByGoal.get(ev.goal_id) ?? new Set<string>();
      set.add(date);
      completedDatesByGoal.set(ev.goal_id, set);
    } else if (ev.kind === "miss") {
      missedCountByGoal.set(ev.goal_id, (missedCountByGoal.get(ev.goal_id) ?? 0) + 1);
    }
    if (ev.value !== null && Number.isFinite(ev.value)) {
      valueSumByGoal.set(ev.goal_id, (valueSumByGoal.get(ev.goal_id) ?? 0) + ev.value);
    }
  }

  const involvedGoalIds = new Set<string>([
    ...plannedByGoal.keys(),
    ...completedDatesByGoal.keys(),
    ...missedCountByGoal.keys(),
  ]);

  const goalSummaries: PerGoalSummary[] = [...involvedGoalIds].map((goalId) => {
    const goal = goalsById.get(goalId);
    return {
      goalId,
      title: goal?.title ?? "Unknown goal",
      type: goal?.type ?? "unknown",
      unit: goal?.unit ?? null,
      planned: plannedByGoal.get(goalId) ?? 0,
      completedDays: completedDatesByGoal.get(goalId)?.size ?? 0,
      missedCount: missedCountByGoal.get(goalId) ?? 0,
      totalValue: valueSumByGoal.get(goalId) ?? null,
    };
  });
  goalSummaries.sort((a, b) => a.title.localeCompare(b.title));

  let weakestGoal: PerGoalSummary | null = null;
  for (const g of goalSummaries) {
    if (g.planned <= 0) continue;
    const ratio = g.completedDays / g.planned;
    const weakestRatio = weakestGoal ? weakestGoal.completedDays / Math.max(weakestGoal.planned, 1) : Infinity;
    if (ratio < weakestRatio) weakestGoal = g;
  }

  const days: DaySummary[] = [];
  const [sy, sm, sd] = range.weekStartStr.split("-").map(Number);
  for (let i = 0; i < 7; i++) {
    const { y, m, d } = addDaysToYmd(sy, sm, sd, i);
    const dateStr = ymd(y, m, d);
    let completedGoalCount = 0;
    for (const set of completedDatesByGoal.values()) {
      if (set.has(dateStr)) completedGoalCount++;
    }
    days.push({ date: dateStr, weekday: WEEKDAY_NAMES[i], completedGoalCount });
  }
  const daysActive = days.filter((d) => d.completedGoalCount > 0).length;
  const bestDay = days.reduce<DaySummary | null>(
    (best, d) => (best === null || d.completedGoalCount > best.completedGoalCount ? d : best),
    null,
  );

  const completedGoalInstances = (byKind["complete"] ?? 0) + (byKind["verify"] ?? 0);
  const missedGoalInstances = byKind["miss"] ?? 0;

  return {
    weekStart: range.weekStartStr,
    weekEnd: range.weekEndStr,
    timezone: range.tz,
    days,
    daysActive,
    bestDay: bestDay && bestDay.completedGoalCount > 0 ? bestDay : null,
    totals: { byKind, completedGoalInstances, missedGoalInstances },
    goals: goalSummaries,
    weakestGoal,
    streak: streak ? { current: streak.current, best: streak.best } : null,
    hasActivity: events.length > 0 || dailyPlans.length > 0,
  };
}

// ---------------------------------------------------------------------------------------
// Coach voice + strict recap prompt (§9.6 / §5.13)
// ---------------------------------------------------------------------------------------

const COACH_VOICE_STYLES: Record<string, string> = {
  hype: 'High-energy hype coach. Short, punchy, celebratory, exclamation points welcome. Example tone: "LET\'S GO, 3 more grams."',
  tough_love:
    'Direct, no-nonsense accountability coach. States the gap between intent and action plainly — never mean, never sarcastic. Example tone: "You said 4 days. It\'s Thursday. You\'re at 2."',
  chill:
    'Relaxed, low-pressure, encouraging without urgency. Example tone: "Whenever you\'re ready, the gym\'s open till 11."',
  data: 'Numbers-first, matter-of-fact, minimal adjectives. Example tone: "Protein 72/150g. Avg completion 81% this month."',
};
const DEFAULT_COACH_VOICE = "hype"; // matches users.coach_voice default, migrations/0001_init.sql

function summaryLines(summary: WeekSummary): string[] {
  const lines: string[] = [];
  lines.push(`Days with at least one completed goal: ${summary.daysActive}/7`);
  if (summary.bestDay) lines.push(`Best day: ${summary.bestDay.weekday} (${summary.bestDay.completedGoalCount} goals completed)`);
  if (summary.streak) lines.push(`Streak: ${summary.streak.current} days (best ${summary.streak.best})`);

  if (summary.goals.length === 0) {
    lines.push("No goal activity recorded this week.");
  } else {
    for (const g of summary.goals) {
      const parts = [`${g.title}: ${g.completedDays}/${Math.max(g.planned, g.completedDays)} completed`];
      if (g.missedCount > 0) parts.push(`${g.missedCount} missed`);
      if (g.totalValue !== null && g.unit) parts.push(`total ${g.totalValue}${g.unit}`);
      lines.push(`- ${parts.join(", ")}`);
    }
  }
  if (summary.weakestGoal) {
    lines.push(
      `Weakest goal this week: ${summary.weakestGoal.title} (${summary.weakestGoal.completedDays}/${summary.weakestGoal.planned})`,
    );
  }
  return lines;
}

function buildRecapPrompt(coachVoice: string, summary: WeekSummary): { system: string; user: string } {
  const style = COACH_VOICE_STYLES[coachVoice] ?? COACH_VOICE_STYLES[DEFAULT_COACH_VOICE];
  const system = [
    "You are the in-app coach for ZANO, a habit app that keeps distracting apps shielded until",
    "the user completes verified goals (workouts, focus sessions, protein, water, and similar",
    "additive habits — never calorie limits, weight targets, or fasting). You write the user's",
    "Sunday Weekly Recap card.",
    "",
    `Voice for this user: ${style}`,
    "",
    "Strict rules for the recap text:",
    `- Maximum ${MAX_RECAP_WORDS} words. Fewer is fine.`,
    "- Exactly one specific win, citing a real number or goal name from the data given.",
    "- Exactly one specific, concrete suggestion for next week, citing a real goal name.",
    "- No shame, no guilt, no scolding, no sarcasm about missed goals — state gaps as fact, not",
    "  failure. If the week had little or no activity, invite them back warmly, don't scold.",
    "- Never mention weight loss, calories, dieting, fasting, or any restrictive eating goal.",
    "- Never make a medical or health-outcome claim. Only speak to consistency, discipline, focus.",
    '- Second person ("you"). No emoji. No hashtags. No markdown.',
    "- Output ONLY the recap text itself — no preamble, no quotes, no label, no word count.",
  ].join("\n");

  const user = `This user's week (${summary.weekStart} to ${summary.weekEnd}, local time):\n${summaryLines(summary).join("\n")}`;
  return { system, user };
}

const RESTRICTIVE_LANGUAGE_PATTERNS = [
  /\blose weight\b/i,
  /\bweight loss\b/i,
  /\bcalorie(s)? deficit\b/i,
  /\bfasting\b/i,
  /\bcutting calories\b/i,
  /\bdiet(ing)?\b/i,
  /\bslim(ming)? down\b/i,
  /\blbs? lost\b/i,
];
function containsRestrictiveLanguage(text: string): boolean {
  return RESTRICTIVE_LANGUAGE_PATTERNS.some((p) => p.test(text));
}

function enforceWordLimit(text: string, maxWords: number): string {
  const trimmed = text.trim().replace(/^["']|["']$/g, "");
  const words = trimmed.split(/\s+/).filter(Boolean);
  if (words.length <= maxWords) return trimmed;
  return words.slice(0, maxWords).join(" ").replace(/[,;:]+$/, "") + ".";
}

// ---------------------------------------------------------------------------------------
// LLM call (text) — see meal-vision/index.ts for the full provider-contract note; same
// env-configurable Anthropic-Messages-API-shaped adapter, text-only variant.
// ---------------------------------------------------------------------------------------

class ConfigError extends Error {}
class UpstreamError extends Error {}
class BadRequestError extends Error {}

/** Constant-time string compare — avoids leaking the service role key's value through response
 *  timing. Same rationale/approach as revenuecat-webhook/index.ts's `timingSafeEqual`; duplicated
 *  here rather than shared because each Edge Function is deployed as an independent Deno program. */
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

async function callTextLlm(system: string, user: string): Promise<string> {
  if (!LLM_API_KEY) throw new ConfigError("ZANO_LLM_API_KEY is not set");
  if (!LLM_MODEL) throw new ConfigError("ZANO_LLM_MODEL is not set");

  const res = await fetchWithTimeout(
    LLM_API_URL,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": LLM_API_KEY,
        "anthropic-version": LLM_API_VERSION,
      },
      body: JSON.stringify({
        model: LLM_MODEL,
        max_tokens: 200,
        temperature: 0.7,
        system,
        messages: [{ role: "user", content: [{ type: "text", text: user }] }],
      }),
    },
    RECAP_TIMEOUT_MS,
  );

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    console.error("weekly-recap: LLM call failed", res.status, detail.slice(0, 500));
    throw new UpstreamError(`recap LLM returned ${res.status}`);
  }

  const payload = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
  const text = payload.content?.find((b) => b.type === "text")?.text;
  if (!text || !text.trim()) throw new UpstreamError("recap LLM response had no text content");
  return text.trim();
}

async function generateRecapText(coachVoice: string, summary: WeekSummary): Promise<{ text: string; flagged: boolean }> {
  const { system, user } = buildRecapPrompt(coachVoice, summary);
  let raw = await callTextLlm(system, user);
  let flagged = false;

  if (containsRestrictiveLanguage(raw)) {
    console.warn("weekly-recap: first draft used restrictive-eating language, retrying once");
    const retryUser = `${user}\n\nReminder: do not mention weight, calories, dieting, or fasting in any form.`;
    try {
      raw = await callTextLlm(system, retryUser);
    } catch (err) {
      console.error("weekly-recap: retry after restrictive-language flag failed", err);
    }
    if (containsRestrictiveLanguage(raw)) {
      flagged = true;
      console.error("weekly-recap: recap still contains restrictive-eating language after retry, storing flagged");
    }
  }

  return { text: enforceWordLimit(raw, MAX_RECAP_WORDS), flagged };
}

// ---------------------------------------------------------------------------------------
// Per-user pipeline
// ---------------------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
type ServiceClient = any;

async function processUserRecap(
  supabase: ServiceClient,
  userId: string,
  nowUtc: Date,
  weekStartOverride: string | undefined,
  userTzHint: string | null,
  coachVoiceHint: string | null,
): Promise<{ weekStart: string; stored: boolean }> {
  let tz = userTzHint;
  let coachVoice = coachVoiceHint;
  if (tz === null || coachVoice === null) {
    const { data: userRow, error: userErr } = await supabase
      .from("users")
      .select("tz, coach_voice")
      .eq("id", userId)
      .single();
    if (userErr || !userRow) throw new Error(`user ${userId} not found`);
    tz = tz ?? userRow.tz;
    coachVoice = coachVoice ?? userRow.coach_voice;
  }

  const range = computeWeekRange(nowUtc, safeTz(tz), weekStartOverride);

  const [{ data: goals, error: goalsErr }, { data: dailyPlans, error: plansErr }, { data: events, error: eventsErr }, { data: streak, error: streakErr }] =
    await Promise.all([
      supabase.from("goals").select("id,title,type,unit,target_value,active").eq("user_id", userId),
      supabase
        .from("daily_plans")
        .select("goal_id,date")
        .eq("user_id", userId)
        .gte("date", range.weekStartStr)
        .lt("date", range.weekEndStr),
      supabase
        .from("goal_events")
        .select("goal_id,ts,kind,value")
        .eq("user_id", userId)
        .gte("ts", range.startUtc.toISOString())
        .lt("ts", range.endUtc.toISOString()),
      supabase.from("streaks").select("current,best,freezes_left").eq("user_id", userId).maybeSingle(),
    ]);

  if (goalsErr) throw new Error(`goals query failed: ${goalsErr.message}`);
  if (plansErr) throw new Error(`daily_plans query failed: ${plansErr.message}`);
  if (eventsErr) throw new Error(`goal_events query failed: ${eventsErr.message}`);
  if (streakErr) throw new Error(`streaks query failed: ${streakErr.message}`);

  const summary = computeWeekSummary(
    range,
    (goals ?? []) as GoalRow[],
    (dailyPlans ?? []) as DailyPlanRow[],
    (events ?? []) as GoalEventRow[],
    (streak ?? null) as StreakRow | null,
  );

  const { text, flagged } = await generateRecapText(coachVoice ?? DEFAULT_COACH_VOICE, summary);

  const stats = {
    weekStart: summary.weekStart,
    weekEnd: summary.weekEnd,
    timezone: summary.timezone,
    daysActive: summary.daysActive,
    bestDay: summary.bestDay,
    totals: summary.totals,
    streak: summary.streak,
    goals: summary.goals,
    weakestGoal: summary.weakestGoal,
    flaggedUnsafeLanguage: flagged,
  };

  const { error: upsertErr } = await supabase
    .from("recaps")
    .upsert(
      { user_id: userId, week_start: range.weekStartStr, text, stats, image_path: null },
      { onConflict: "user_id,week_start" },
    );
  if (upsertErr) throw new Error(`recaps upsert failed: ${upsertErr.message}`);

  return { weekStart: range.weekStartStr, stored: true };
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
    console.error("weekly-recap: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not available in function env");
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

  const userId = typeof body.userId === "string" ? body.userId : undefined;
  const weekStartOverride = typeof body.weekStart === "string" ? body.weekStart : undefined;
  const nowUtc = new Date();

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    if (userId) {
      const result = await processUserRecap(supabase, userId, nowUtc, weekStartOverride, null, null);
      return jsonResponse({ userId, ...result }, 200);
    }

    const { data: users, error: usersErr } = await supabase
      .from("users")
      .select("id, tz, coach_voice")
      .limit(BATCH_LIMIT);
    if (usersErr) throw new Error(`users query failed: ${usersErr.message}`);

    const failed: Array<{ userId: string; error: string }> = [];
    let succeeded = 0;

    for (const u of users ?? []) {
      try {
        await processUserRecap(supabase, u.id, nowUtc, weekStartOverride, u.tz, u.coach_voice);
        succeeded++;
      } catch (err) {
        console.error("weekly-recap: failed for user", u.id, err);
        failed.push({ userId: u.id, error: err instanceof Error ? err.message : "unknown error" });
      }
    }

    return jsonResponse({ usersProcessed: (users ?? []).length, succeeded, failed }, 200);
  } catch (err) {
    if (err instanceof BadRequestError) return jsonResponse({ error: "bad_request", message: err.message }, 400);
    if (err instanceof ConfigError) {
      console.error("weekly-recap: config error", err.message);
      return jsonResponse({ error: "internal_error", message: "server misconfigured" }, 500);
    }
    if (err instanceof UpstreamError) {
      return jsonResponse({ error: "upstream_unavailable", message: err.message }, 502);
    }
    console.error("weekly-recap: unhandled error", err);
    return jsonResponse({ error: "internal_error", message: err instanceof Error ? err.message : "unknown" }, 500);
  }
});
