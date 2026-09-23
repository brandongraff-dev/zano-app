// ZANO — meal-prep-plan Edge Function (Deno / Supabase Edge Functions)
//
// Implements docs/spec.md:
//   §10  Food, Protein & Ordering Integrations — "Meal prep plan: LLM generates weekly plan from
//        protein target, budget, cooking skill, dislikes -> shopping list -> Instacart." This
//        function builds the LLM plan generator and stops at the shopping list; the Instacart cart
//        push itself is a separate, unresolved-availability item (§28: "Instacart Developer
//        Platform current availability and terms.") — not attempted here. See "Out of scope" below.
//   §3   Goal Catalog & Verification — "Meal prep (weekly)" row: this function is the *planning*
//        half (what to prep); `Core/Sources/Core/Verification/MealPrepVerifier.swift` (same task,
//        owned separately) is the *verification* half (a photo confirms it got done). The two are
//        deliberately independent — nothing here writes a `goal_events` row, and nothing there
//        calls this function; a user can verify meal prep without ever generating a plan here.
//   §11  Architecture — "API keys live only in Edge Functions" (also §9, §24).
//   §24  Safety, Legal & App Review — "No restrictive goals ever... additive goals only." This
//        function generates food content, so the same restrictive-eating-language guard
//        `weekly-recap/index.ts` already applies to its own LLM output is reused here (see
//        `containsRestrictiveLanguage`) — protein is additive, never a calorie ceiling.
//
// Ownership boundary (see task brief): this file only calls a text LLM and returns its (validated)
// plan + shopping list in the HTTP response. It does not read or write any table — there is no
// `meal_prep_plans`-style table in `backend/supabase/migrations` yet, and adding one is a schema
// decision for whichever session owns that migration next, not this task's (this task owns exactly
// this file and `Core/Sources/Core/Verification/MealPrepVerifier.swift`, per its brief). So this is
// a stateless "generate on demand" endpoint today: call it, get a plan back, regenerate whenever
// the inputs change. See the TODO at the bottom of the handler for exactly what a future session
// would add to persist/version a user's "current week's plan" instead.
//
// Out of scope, explicitly (§28 "Instacart Developer Platform current availability and terms" is
// an open question, not a decision this task can make): this function's output ends at
// `shopping_list` — a plain, structured ingredient list. Turning that into an Instacart cart (or a
// deep link into one) is a separate, not-yet-assigned piece of work per this task's own brief
// ("stop at producing the shopping list").
//
// ---------------------------------------------------------------------------------------
// HTTP contract
// ---------------------------------------------------------------------------------------
// POST /meal-prep-plan
// Headers:
//   Authorization: Bearer <user's Supabase access token>   (required — this function runs with
//                                                            verify_jwt=true, the Supabase Edge
//                                                            Functions default; unlike
//                                                            weekly-recap's batch/service-role
//                                                            call, this is an on-demand, per-user
//                                                            request the app makes directly —
//                                                            same shape as meal-vision's own auth)
//   Content-Type: application/json
//
// Body:
//   {
//     "dailyProteinTargetG": number,        // required, > 0 — the user's daily protein goal
//                                            // (Goal.targetValue for their protein goal); the
//                                            // week's meals are planned to make that daily number
//                                            // realistic to hit via prepped meals, not to hit some
//                                            // separate weekly sum on its own.
//     "mealsPerWeek"?: number,               // how many prepped meals to plan for the week.
//                                            // default 5 (a Mon-Fri prep is the most common real
//                                            // pattern; not spec-given, a reasonable default — see
//                                            // MEALS_PER_WEEK_DEFAULT). Clamped to [1, 14].
//     "budgetPerWeekUSD"?: number,           // optional soft ceiling for estimated_total_cost_usd.
//     "cookingSkill"?: "beginner" | "intermediate" | "advanced",   // default "beginner".
//     "dislikes"?: string[],                 // ingredients/foods to avoid. Each trimmed, empty
//                                            // entries dropped, capped at MAX_LIST_ITEMS entries
//                                            // of at most MAX_ITEM_LENGTH characters each.
//     "kitchenStaples"?: string[]            // ingredients the user already has (spec §10:
//                                            // "user saves 10-20 staples once") — excluded from
//                                            // the shopping list (marked already_have instead of
//                                            // omitted, so the plan's full ingredient picture is
//                                            // still visible). Same caps as dislikes.
//   }
// → 200:
//   {
//     "dailyProteinTargetG": number,
//     "mealsPerWeek": number,
//     "cookingSkill": string,
//     "plan": {
//       "meals": [{
//         "name": string,
//         "servings": number,
//         "protein_per_serving_g": number,
//         "ingredients": [{ "name": string, "quantity": string }],
//         "instructions": string[]
//       }],
//       "notes": string
//     },
//     "shopping_list": [{
//       "ingredient": string,
//       "quantity": string,
//       "estimated_cost_usd": number | null,
//       "already_have": boolean
//     }],
//     "estimated_total_cost_usd": number | null,
//     "flagged_unsafe_language": boolean,   // true only if the LLM still used restrictive-eating
//                                            // language after one retry (see generateMealPrepPlan)
//                                            // — surfaced so the client can choose to regenerate
//                                            // rather than silently show it, mirroring
//                                            // weekly-recap's own "store flagged" transparency.
//     "generatedAt": "<ISO 8601 timestamp>"
//   }
//
// Errors are JSON: { "error": "<machine_readable_code>", "message"?: string }.
//
// ---------------------------------------------------------------------------------------
// Text LLM provider contract — see meal-vision/index.ts's own header for the full note on why
// this is written against Anthropic's Messages API shape and what to double-check before this
// goes live. Same env-configurable adapter, text-only variant (mirrors weekly-recap's own
// `callTextLlm`, duplicated rather than imported since each Edge Function here is deployed as an
// independent Deno program, same as that file's own `timingSafeEqual` duplication note explains).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const LLM_API_KEY = Deno.env.get("ZANO_LLM_API_KEY") ?? "";
const LLM_API_URL = Deno.env.get("ZANO_LLM_API_URL") ?? "https://api.anthropic.com/v1/messages";
const LLM_API_VERSION = Deno.env.get("ZANO_LLM_API_VERSION") ?? "2023-06-01";
// No default model string — see meal-vision/index.ts for why. Must be set via `supabase secrets set`.
const LLM_MODEL = Deno.env.get("ZANO_LLM_MODEL") ?? "";

const PLAN_TIMEOUT_MS = 30_000;
const MAX_PLAN_TOKENS = 2048; // a week's worth of meals + a shopping list is a lot more JSON than meal-vision's single estimate

const MEALS_PER_WEEK_DEFAULT = 5;
const MEALS_PER_WEEK_MIN = 1;
const MEALS_PER_WEEK_MAX = 14; // two prepped meals/day, 7 days — a generous, not-spec-given ceiling against a runaway prompt
const DAILY_PROTEIN_TARGET_MAX_G = 400; // sanity bound, not a spec number — see GymVerificationDefaults's own doc comment in the Swift codebase for the same "not spec-verbatim, chosen conservatively" convention

const MAX_LIST_ITEMS = 25; // dislikes / kitchenStaples
const MAX_ITEM_LENGTH = 60;

const COOKING_SKILLS = ["beginner", "intermediate", "advanced"] as const;
type CookingSkill = (typeof COOKING_SKILLS)[number];
const DEFAULT_COOKING_SKILL: CookingSkill = "beginner";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------------------
// Strict JSON output shape (mirrors meal-vision/index.ts's own validate-the-LLM's-JSON pattern)
// ---------------------------------------------------------------------------------------

interface MealPrepIngredient {
  name: string;
  quantity: string;
}

interface MealPrepMeal {
  name: string;
  servings: number;
  protein_per_serving_g: number;
  ingredients: MealPrepIngredient[];
  instructions: string[];
}

interface ShoppingListItem {
  ingredient: string;
  quantity: string;
  estimated_cost_usd: number | null;
  already_have: boolean;
}

interface MealPrepPlanResult {
  meals: MealPrepMeal[];
  shopping_list: ShoppingListItem[];
  estimated_total_cost_usd: number | null;
  notes: string;
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}

function validateIngredient(v: unknown): MealPrepIngredient | null {
  if (typeof v !== "object" || v === null) return null;
  const obj = v as Record<string, unknown>;
  if (!isNonEmptyString(obj.name) || !isNonEmptyString(obj.quantity)) return null;
  return { name: obj.name.trim(), quantity: obj.quantity.trim() };
}

function validateMeal(v: unknown): MealPrepMeal | null {
  if (typeof v !== "object" || v === null) return null;
  const obj = v as Record<string, unknown>;

  if (!isNonEmptyString(obj.name)) return null;
  if (!isFiniteNumber(obj.servings) || obj.servings <= 0) return null;
  if (!isFiniteNumber(obj.protein_per_serving_g) || obj.protein_per_serving_g < 0) return null;

  if (!Array.isArray(obj.ingredients) || obj.ingredients.length === 0) return null;
  const ingredients: MealPrepIngredient[] = [];
  for (const raw of obj.ingredients) {
    const ing = validateIngredient(raw);
    if (!ing) return null;
    ingredients.push(ing);
  }

  if (!Array.isArray(obj.instructions)) return null;
  const instructions: string[] = [];
  for (const raw of obj.instructions) {
    if (typeof raw !== "string" || raw.trim().length === 0) return null;
    instructions.push(raw.trim());
  }

  return {
    name: obj.name.trim(),
    servings: obj.servings,
    protein_per_serving_g: obj.protein_per_serving_g,
    ingredients,
    instructions,
  };
}

function validateShoppingItem(v: unknown): ShoppingListItem | null {
  if (typeof v !== "object" || v === null) return null;
  const obj = v as Record<string, unknown>;
  if (!isNonEmptyString(obj.ingredient) || !isNonEmptyString(obj.quantity)) return null;
  if (obj.estimated_cost_usd !== null && (!isFiniteNumber(obj.estimated_cost_usd) || obj.estimated_cost_usd < 0)) return null;
  if (typeof obj.already_have !== "boolean") return null;
  return {
    ingredient: obj.ingredient.trim(),
    quantity: obj.quantity.trim(),
    estimated_cost_usd: obj.estimated_cost_usd === null ? null : (obj.estimated_cost_usd as number),
    already_have: obj.already_have,
  };
}

function validateMealPrepPlanResult(v: unknown): MealPrepPlanResult | null {
  if (typeof v !== "object" || v === null) return null;
  const obj = v as Record<string, unknown>;

  if (!Array.isArray(obj.meals) || obj.meals.length === 0) return null;
  const meals: MealPrepMeal[] = [];
  for (const raw of obj.meals) {
    const meal = validateMeal(raw);
    if (!meal) return null;
    meals.push(meal);
  }

  if (!Array.isArray(obj.shopping_list)) return null;
  const shoppingList: ShoppingListItem[] = [];
  for (const raw of obj.shopping_list) {
    const item = validateShoppingItem(raw);
    if (!item) return null;
    shoppingList.push(item);
  }

  if (obj.estimated_total_cost_usd !== null && (!isFiniteNumber(obj.estimated_total_cost_usd) || obj.estimated_total_cost_usd < 0)) {
    return null;
  }
  const notes = typeof obj.notes === "string" ? obj.notes : "";

  return {
    meals,
    shopping_list: shoppingList,
    estimated_total_cost_usd: obj.estimated_total_cost_usd === null ? null : (obj.estimated_total_cost_usd as number),
    notes,
  };
}

/** Strips ```json fences / stray prose and parses the first {...} block found. Identical to
 *  meal-vision/index.ts's own helper — duplicated, not imported, for the same "independent Deno
 *  program per function" reason as callTextLlm below. */
function parseJsonFromLlmText(raw: string): unknown {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : raw;
  try {
    return JSON.parse(candidate.trim());
  } catch {
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) throw new Error("no_json_object_found");
    return JSON.parse(candidate.slice(start, end + 1));
  }
}

// ---------------------------------------------------------------------------------------
// Restrictive-eating-language guard (§24) — identical pattern/word list to weekly-recap/index.ts's
// own guard, duplicated for the same "independent Deno program" reason. A meal-prep plan is even
// more likely than a recap to accidentally drift into "low-calorie"/"diet" framing (it's food
// content), so this runs over every user-visible string the plan produces: meal names, notes, and
// instructions (ingredient/quantity text is not natural-language enough to meaningfully flag).
// ---------------------------------------------------------------------------------------

const RESTRICTIVE_LANGUAGE_PATTERNS = [
  /\blose weight\b/i,
  /\bweight loss\b/i,
  /\bcalorie(s)? deficit\b/i,
  /\blow[- ]calorie\b/i,
  /\bfasting\b/i,
  /\bcutting calories\b/i,
  /\bdiet(ing)?\b/i,
  /\bslim(ming)? down\b/i,
  /\blbs? lost\b/i,
];

function planText(plan: MealPrepPlanResult): string {
  const parts: string[] = [plan.notes];
  for (const meal of plan.meals) {
    parts.push(meal.name, ...meal.instructions);
  }
  return parts.join(" \n ");
}

function containsRestrictiveLanguage(text: string): boolean {
  return RESTRICTIVE_LANGUAGE_PATTERNS.some((p) => p.test(text));
}

// ---------------------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------------------

interface PlanRequest {
  dailyProteinTargetG: number;
  mealsPerWeek: number;
  budgetPerWeekUSD: number | null;
  cookingSkill: CookingSkill;
  dislikes: string[];
  kitchenStaples: string[];
}

function buildPlanPrompt(req: PlanRequest): { system: string; user: string } {
  const system = [
    "You are the meal-prep planner for ZANO, a habit-tracking app that keeps distracting apps",
    "shielded until the user completes verified goals — one of which is a weekly 'prep multiple",
    "meal containers' goal. You generate a realistic weekly meal-prep plan and its shopping list.",
    "",
    "ZANO never tracks calorie restriction, weight loss, or dieting — protein is an ADDITIVE goal",
    "(hit a daily gram target), never a ceiling on anything. Do not mention calories, weight,",
    "dieting, fasting, or 'healthy eating' framing anywhere in your output. Protein grams per",
    "serving are the only nutrition number you report.",
    "",
    "Respond with ONLY a single JSON object, no prose before or after it, no markdown fences,",
    "matching exactly this shape:",
    '{"meals":[{"name":string,"servings":number,"protein_per_serving_g":number,' +
      '"ingredients":[{"name":string,"quantity":string}],"instructions":[string,...]}],' +
      '"shopping_list":[{"ingredient":string,"quantity":string,"estimated_cost_usd":number|null,' +
      '"already_have":boolean}],"estimated_total_cost_usd":number|null,"notes":string}',
    "",
    "Rules:",
    `- Produce exactly ${req.mealsPerWeek} meal(s) in "meals" — these are batch-prepped meals meant`,
    "  to be portioned into containers and eaten across the week, not one meal per calendar day",
    "  necessarily (e.g. one recipe can become several of the week's containers via its servings",
    "  count) — use your judgment on the most realistic batch-cooking split for this many meals.",
    `- Each meal's protein_per_serving_g should make it realistic for a day that includes this meal`,
    `  to reach a ${req.dailyProteinTargetG}g daily protein target across that day's meals — you`,
    "  don't know the rest of the day's eating, so aim roughly a third to a half of the daily",
    "  target per serving rather than the full target in one meal.",
    `- Match the cook's skill level: "${req.cookingSkill}" — beginner means minimal technique and`,
    "  few steps, advanced can use more involved technique. instructions is a short ordered list",
    "  of concrete steps, not a wall of text.",
    req.budgetPerWeekUSD !== null
      ? `- Keep estimated_total_cost_usd at or below approximately $${req.budgetPerWeekUSD} if realistic; if you cannot, say so plainly in notes rather than silently exceeding it without comment.`
      : "- No budget constraint was given; make reasonable, unremarkable cost estimates.",
    req.dislikes.length > 0
      ? `- Never use these disliked ingredients/foods: ${req.dislikes.join(", ")}.`
      : "- No dislikes were given.",
    req.kitchenStaples.length > 0
      ? `- The cook already has these on hand: ${req.kitchenStaples.join(", ")}. You may use them in` +
        ' recipes, but mark their shopping_list entry (if you include one at all) with' +
        ' "already_have": true rather than omitting it, so the full ingredient picture stays' +
        " visible; do not add estimated_cost_usd for an already_have item (use null)."
      : "- The cook has no saved kitchen staples on file.",
    "- shopping_list should be the consolidated ingredient list across all meals (combine repeated",
    "  ingredients into one line with a summed quantity where that's sensible), each with a rough",
    "  estimated_cost_usd (null if you genuinely can't estimate) and already_have set correctly.",
    "- estimated_total_cost_usd is the sum of shopping_list's non-null, non-already_have costs;",
    "  null only if every item's cost is null.",
    "- notes: at most two short, neutral sentences — e.g. a prep-order tip, or a budget/skill",
    "  caveat. Never mention calories, weight, dieting, fasting, or restrictive eating in any form.",
  ].join("\n");

  const user = [
    `Daily protein target: ${req.dailyProteinTargetG}g`,
    `Meals to plan: ${req.mealsPerWeek}`,
    `Cooking skill: ${req.cookingSkill}`,
    req.budgetPerWeekUSD !== null ? `Weekly budget: $${req.budgetPerWeekUSD}` : "Weekly budget: not specified",
    req.dislikes.length > 0 ? `Dislikes: ${req.dislikes.join(", ")}` : "Dislikes: none",
    req.kitchenStaples.length > 0 ? `Kitchen staples on hand: ${req.kitchenStaples.join(", ")}` : "Kitchen staples on hand: none",
  ].join("\n");

  return { system, user };
}

// ---------------------------------------------------------------------------------------
// LLM call (text) — see meal-vision/index.ts's header for the full provider-contract note.
// ---------------------------------------------------------------------------------------

class ConfigError extends Error {}
class UpstreamError extends Error {}

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
        max_tokens: MAX_PLAN_TOKENS,
        temperature: 0.4, // structured, mostly-deterministic output — lower than weekly-recap's 0.7 creative-text setting
        system,
        messages: [{ role: "user", content: [{ type: "text", text: user }] }],
      }),
    },
    PLAN_TIMEOUT_MS,
  );

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    console.error("meal-prep-plan: LLM call failed", res.status, detail.slice(0, 500));
    throw new UpstreamError(`meal-prep-plan LLM returned ${res.status}`);
  }

  const payload = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
  const text = payload.content?.find((b) => b.type === "text")?.text;
  if (!text || !text.trim()) throw new UpstreamError("meal-prep-plan LLM response had no text content");
  return text.trim();
}

/** Calls the LLM, validates its JSON, and retries once (with a stronger reminder) if either the
 *  JSON is malformed/off-shape or the text drifts into restrictive-eating language — same
 *  "generate, check, retry once, flag if still bad" shape as weekly-recap's own
 *  `generateRecapText`, extended here to also cover shape validation (meal-vision doesn't retry;
 *  its caller can just re-call "analyze", but this endpoint is stateless per-call, so retrying
 *  inline is the only chance to recover within one request). */
async function generateMealPrepPlan(req: PlanRequest): Promise<{ plan: MealPrepPlanResult; flagged: boolean }> {
  const { system, user } = buildPlanPrompt(req);

  const attempt = async (extraReminder?: string): Promise<MealPrepPlanResult | null> => {
    const raw = await callTextLlm(system, extraReminder ? `${user}\n\n${extraReminder}` : user);
    let parsed: unknown;
    try {
      parsed = parseJsonFromLlmText(raw);
    } catch (err) {
      console.error("meal-prep-plan: could not parse LLM JSON", err, raw.slice(0, 500));
      return null;
    }
    return validateMealPrepPlanResult(parsed);
  };

  let plan = await attempt();
  if (!plan) {
    console.warn("meal-prep-plan: first attempt failed shape validation, retrying once");
    plan = await attempt("Reminder: respond with ONLY the exact JSON shape described, no other text.");
  }
  if (!plan) {
    throw new UpstreamError("could not generate a valid meal prep plan, please try again");
  }

  let flagged = false;
  if (containsRestrictiveLanguage(planText(plan))) {
    console.warn("meal-prep-plan: draft used restrictive-eating language, retrying once");
    const retried = await attempt(
      "Reminder: do not mention calories, weight, dieting, fasting, or restrictive eating in any form.",
    );
    if (retried && !containsRestrictiveLanguage(planText(retried))) {
      plan = retried;
    } else {
      flagged = true;
      console.error("meal-prep-plan: plan still contains restrictive-eating language after retry, returning flagged");
    }
  }

  return { plan, flagged };
}

// ---------------------------------------------------------------------------------------
// Request validation
// ---------------------------------------------------------------------------------------

class BadRequestError extends Error {}

function sanitizeStringList(v: unknown, fieldName: string): string[] {
  if (v === undefined) return [];
  if (!Array.isArray(v)) throw new BadRequestError(`${fieldName} must be an array of strings`);
  const out: string[] = [];
  for (const raw of v) {
    if (typeof raw !== "string") throw new BadRequestError(`${fieldName} entries must be strings`);
    const trimmed = raw.trim();
    if (trimmed.length === 0) continue;
    if (trimmed.length > MAX_ITEM_LENGTH) throw new BadRequestError(`${fieldName} entries must be at most ${MAX_ITEM_LENGTH} characters`);
    out.push(trimmed);
    if (out.length >= MAX_LIST_ITEMS) break;
  }
  return out;
}

function parsePlanRequest(body: Record<string, unknown>): PlanRequest {
  const dailyProteinTargetG = body.dailyProteinTargetG;
  if (!isFiniteNumber(dailyProteinTargetG) || dailyProteinTargetG <= 0) {
    throw new BadRequestError("dailyProteinTargetG must be a positive number");
  }
  if (dailyProteinTargetG > DAILY_PROTEIN_TARGET_MAX_G) {
    throw new BadRequestError(`dailyProteinTargetG must be at most ${DAILY_PROTEIN_TARGET_MAX_G}`);
  }

  let mealsPerWeek = MEALS_PER_WEEK_DEFAULT;
  if (body.mealsPerWeek !== undefined) {
    if (!isFiniteNumber(body.mealsPerWeek) || !Number.isInteger(body.mealsPerWeek)) {
      throw new BadRequestError("mealsPerWeek must be an integer");
    }
    if (body.mealsPerWeek < MEALS_PER_WEEK_MIN || body.mealsPerWeek > MEALS_PER_WEEK_MAX) {
      throw new BadRequestError(`mealsPerWeek must be between ${MEALS_PER_WEEK_MIN} and ${MEALS_PER_WEEK_MAX}`);
    }
    mealsPerWeek = body.mealsPerWeek;
  }

  let budgetPerWeekUSD: number | null = null;
  if (body.budgetPerWeekUSD !== undefined && body.budgetPerWeekUSD !== null) {
    if (!isFiniteNumber(body.budgetPerWeekUSD) || body.budgetPerWeekUSD < 0) {
      throw new BadRequestError("budgetPerWeekUSD must be a non-negative number");
    }
    budgetPerWeekUSD = body.budgetPerWeekUSD;
  }

  let cookingSkill: CookingSkill = DEFAULT_COOKING_SKILL;
  if (body.cookingSkill !== undefined) {
    if (typeof body.cookingSkill !== "string" || !(COOKING_SKILLS as readonly string[]).includes(body.cookingSkill)) {
      throw new BadRequestError(`cookingSkill must be one of: ${COOKING_SKILLS.join(", ")}`);
    }
    cookingSkill = body.cookingSkill as CookingSkill;
  }

  const dislikes = sanitizeStringList(body.dislikes, "dislikes");
  const kitchenStaples = sanitizeStringList(body.kitchenStaples, "kitchenStaples");

  return { dailyProteinTargetG, mealsPerWeek, budgetPerWeekUSD, cookingSkill, dislikes, kitchenStaples };
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

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    console.error("meal-prep-plan: SUPABASE_URL / SUPABASE_ANON_KEY not available in function env");
    return jsonResponse({ error: "internal_error", message: "server misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "unauthorized", message: "missing Authorization header" }, 401);

  // User-scoped client, matching meal-vision/index.ts's own reasoning: this function reads no
  // table today (see this file's header — stateless generator), but authenticating the caller as
  // a real, current ZANO user — rather than accepting any bearer token — is still the right
  // default for an on-demand, per-user Edge Function, and costs nothing to keep even though no
  // RLS-guarded query currently depends on it.
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: "unauthorized", message: "invalid or expired session" }, 401);

  let rawBody: Record<string, unknown>;
  try {
    rawBody = (await req.json()) as Record<string, unknown>;
  } catch {
    return jsonResponse({ error: "invalid_json", message: "request body must be JSON" }, 400);
  }

  try {
    const planRequest = parsePlanRequest(rawBody);
    const { plan, flagged } = await generateMealPrepPlan(planRequest);

    return jsonResponse(
      {
        dailyProteinTargetG: planRequest.dailyProteinTargetG,
        mealsPerWeek: planRequest.mealsPerWeek,
        cookingSkill: planRequest.cookingSkill,
        plan: { meals: plan.meals, notes: plan.notes },
        shopping_list: plan.shopping_list,
        estimated_total_cost_usd: plan.estimated_total_cost_usd,
        flagged_unsafe_language: flagged,
        generatedAt: new Date().toISOString(),
      },
      200,
    );
  } catch (err) {
    if (err instanceof BadRequestError) return jsonResponse({ error: "bad_request", message: err.message }, 400);
    if (err instanceof ConfigError) {
      console.error("meal-prep-plan: config error", err.message);
      return jsonResponse({ error: "internal_error", message: "server misconfigured" }, 500);
    }
    if (err instanceof UpstreamError) {
      return jsonResponse({ error: "upstream_unavailable", message: err.message }, 502);
    }
    console.error("meal-prep-plan: unhandled error", err);
    return jsonResponse({ error: "internal_error", message: err instanceof Error ? err.message : "unknown error" }, 500);
  }

  // TODO(future session, needs its own migration): persist generated plans into a
  // `meal_prep_plans` table (user_id, week_start, protein_target_g, meals jsonb, shopping_list
  // jsonb, created_at) so the app can show "this week's plan" without regenerating, and so a
  // regenerate action can be distinguished from a first generate. Not built here — no such table
  // exists yet and adding one is a schema decision outside this task's owned files.
});
