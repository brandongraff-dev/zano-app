// ZANO — meal-vision Edge Function (Deno / Supabase Edge Functions)
//
// Implements docs/spec.md:
//   §9.5  Meal Vision      — photo → vision LLM → strict JSON protein estimate; user
//                             confirms/edits with a slider; confirmed values persist.
//   §13   Data Model       — writes into `meals` exactly as specified there.
//   §11   Architecture     — "Edge Functions (TypeScript): meal-vision, ..." and
//                             "API keys live only in Edge Functions" (also §9, §24).
//
// Ownership boundary (see task brief): this file only touches the `meals` table and the
// private `meal-photos` storage bucket. It deliberately does NOT write `goal_events` — per
// §11's data flow ("every user action → App Intent → Core → SwiftData → ... → Sync outbox
// pushes to Supabase"), turning a confirmed meal into a protein `goal_event` is the app's
// job (LogProteinIntent, client-side, local-first), not this function's. It also does NOT
// generate the `meals.embedding` vector — §5.19's Quick Repeats embedding pipeline is a
// separate, not-yet-assigned piece of work; see the narrow TODO below at the one call site
// that touches it.
//
// ---------------------------------------------------------------------------------------
// HTTP contract
// ---------------------------------------------------------------------------------------
// POST /meal-vision
// Headers:
//   Authorization: Bearer <user's Supabase access token>   (required — this function runs
//                                                            with verify_jwt=true, the
//                                                            Supabase Edge Functions default,
//                                                            and additionally uses the token
//                                                            to build a user-scoped client so
//                                                            every DB/storage call is RLS-safe
//                                                            by construction, not by convention)
//   Content-Type: application/json
//
// Body — action "analyze" (default when `action` is omitted): run vision on an uploaded photo
// and store a *draft* (unconfirmed) meals row so the client can render the confirm/edit slider.
//   {
//     "action"?: "analyze",
//     "photoPath": "<user_id>/<file>",   // object path inside the private "meal-photos" bucket
//     "mealId"?: "<uuid>"                // optional — retry vision on an existing draft row
//   }
// → 200 { "mealId": "<uuid>", "photoPath": "...", "confirmed": false, "result": MealVisionResult }
//
// Body — action "confirm": persist the values the user landed on after editing with the slider.
//   {
//     "action": "confirm",
//     "mealId": "<uuid>",
//     "items": [{ "name": string, "grams_protein_est": number, "confidence": number }],
//     "totalProtein": number
//   }
// → 200 { "mealId": "<uuid>", "confirmed": true, "proteinG": number }
//
// Errors are JSON: { "error": "<machine_readable_code>", "message"?: string }.
//
// ---------------------------------------------------------------------------------------
// Vision LLM provider contract (server-side only — ZANO_LLM_API_KEY never reaches the client)
// ---------------------------------------------------------------------------------------
// This function is written against Anthropic's Messages API request/response shape (the vision
// LLM contract I have high confidence in from training knowledge):
//   POST {ZANO_LLM_API_URL}                     default: https://api.anthropic.com/v1/messages
//   headers: x-api-key, anthropic-version, content-type: application/json
//   body: { model, max_tokens, temperature, system, messages: [{ role: "user", content: [
//            { type: "image", source: { type: "base64", media_type, data } },
//            { type: "text", text } ] }] }
//   response: { content: [{ type: "text", text: "..." }], ... }
// Every provider-specific value is env-configurable (ZANO_LLM_API_URL / ZANO_LLM_MODEL /
// ZANO_LLM_API_VERSION) precisely so swapping providers/models is a config change, not a code
// change — `callVisionLlm` below is the only place that would need to change for a genuinely
// different wire format. See knownIssues in the session report for what to double-check against
// current provider docs before this goes live (model name/version, and that this account has
// vision enabled).
//
// Anthropic's Messages API vision support (per my training knowledge) accepts image/jpeg,
// image/png, image/gif, image/webp — NOT image/heic or image/heif, which is what iOS captures
// by default. We reject unsupported mime types with a clear 415 rather than silently failing
// upstream; the app should upload JPEG/PNG (or convert HEIC client-side) into meal-photos.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const LLM_API_KEY = Deno.env.get("ZANO_LLM_API_KEY") ?? "";
const LLM_API_URL = Deno.env.get("ZANO_LLM_API_URL") ?? "https://api.anthropic.com/v1/messages";
const LLM_API_VERSION = Deno.env.get("ZANO_LLM_API_VERSION") ?? "2023-06-01";
// No default model string: guessing a specific model snapshot and presenting it as fact would
// violate this session's "don't invent provider specifics you're unsure of" constraint. Set
// ZANO_LLM_MODEL explicitly (e.g. via `supabase secrets set`) before deploying.
const LLM_MODEL = Deno.env.get("ZANO_LLM_MODEL") ?? "";

const MEAL_PHOTOS_BUCKET = "meal-photos";
const VISION_TIMEOUT_MS = 30_000;

const SUPPORTED_VISION_MIME_TYPES: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};
const UNSUPPORTED_BUT_UPLOADABLE_EXTENSIONS = new Set(["heic", "heif"]); // bucket allows these; vision LLM doesn't

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------------------
// Strict JSON output shape (§9.5) + validation
// ---------------------------------------------------------------------------------------

interface MealVisionItem {
  name: string;
  grams_protein_est: number;
  confidence: number;
}

interface MealVisionResult {
  items: MealVisionItem[];
  total_protein: number;
  notes: string;
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

function validateMealVisionResult(v: unknown): MealVisionResult | null {
  if (typeof v !== "object" || v === null) return null;
  const obj = v as Record<string, unknown>;

  if (!Array.isArray(obj.items)) return null;
  const items: MealVisionItem[] = [];
  for (const raw of obj.items) {
    if (typeof raw !== "object" || raw === null) return null;
    const item = raw as Record<string, unknown>;
    if (typeof item.name !== "string" || item.name.trim().length === 0) return null;
    if (!isFiniteNumber(item.grams_protein_est) || item.grams_protein_est < 0) return null;
    if (!isFiniteNumber(item.confidence) || item.confidence < 0 || item.confidence > 1) return null;
    items.push({
      name: item.name.trim(),
      grams_protein_est: item.grams_protein_est,
      confidence: item.confidence,
    });
  }

  if (!isFiniteNumber(obj.total_protein) || obj.total_protein < 0) return null;
  const notes = typeof obj.notes === "string" ? obj.notes : "";

  return { items, total_protein: obj.total_protein, notes };
}

/** Same shape, but for a user-edited payload coming back from the confirm-step slider UI. */
function validateEditedItems(v: unknown): MealVisionItem[] | null {
  if (!Array.isArray(v)) return null;
  const items: MealVisionItem[] = [];
  for (const raw of v) {
    if (typeof raw !== "object" || raw === null) return null;
    const item = raw as Record<string, unknown>;
    if (typeof item.name !== "string" || item.name.trim().length === 0) return null;
    if (!isFiniteNumber(item.grams_protein_est) || item.grams_protein_est < 0) return null;
    if (!isFiniteNumber(item.confidence) || item.confidence < 0 || item.confidence > 1) return null;
    items.push({
      name: item.name.trim(),
      grams_protein_est: item.grams_protein_est,
      confidence: item.confidence,
    });
  }
  return items;
}

/** Strips ```json fences / stray prose and parses the first {...} block found. */
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
// Vision LLM call
// ---------------------------------------------------------------------------------------

const MEAL_VISION_SYSTEM_PROMPT = [
  "You are a nutrition vision assistant embedded in ZANO, a habit-tracking app. You are given a",
  "photo of a meal and must estimate its protein content only. ZANO never tracks calorie",
  "restriction, weight loss, or dieting — protein is additive, not restrictive — so do not",
  "comment on calories, weight, or whether the meal is 'healthy'.",
  "",
  "Respond with ONLY a single JSON object, no prose before or after it, no markdown fences,",
  "matching exactly this shape:",
  '{"items":[{"name":string,"grams_protein_est":number,"confidence":number}],"total_protein":number,"notes":string}',
  "",
  "Rules:",
  "- items: one entry per distinct food visible. name is short and plain (e.g. \"grilled chicken",
  "  breast\", not a full sentence).",
  "- grams_protein_est: your best-effort estimate of protein in grams for that portion, >= 0.",
  "- confidence: your confidence in that estimate, a number from 0 to 1.",
  "- total_protein: the sum of all items' grams_protein_est (compute it yourself; keep it",
  "  internally consistent with items).",
  "- notes: at most one short, neutral sentence (e.g. portion-size uncertainty). Empty string if",
  "  nothing worth noting. Never mention calories, weight loss, or dieting.",
  "- If you cannot identify any food in the photo, return items: [] and total_protein: 0 and",
  "  explain briefly in notes.",
].join("\n");

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function callVisionLlm(base64Image: string, mediaType: string): Promise<string> {
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
        max_tokens: 1024,
        temperature: 0.2,
        system: MEAL_VISION_SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [
              { type: "image", source: { type: "base64", media_type: mediaType, data: base64Image } },
              { type: "text", text: "Estimate the protein in this meal photo." },
            ],
          },
        ],
      }),
    },
    VISION_TIMEOUT_MS,
  );

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    console.error("meal-vision: vision LLM call failed", res.status, detail.slice(0, 500));
    throw new UpstreamError(`vision LLM returned ${res.status}`);
  }

  const payload = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
  const text = payload.content?.find((block) => block.type === "text")?.text;
  if (!text) throw new UpstreamError("vision LLM response had no text content");
  return text;
}

// ---------------------------------------------------------------------------------------
// Errors / response helpers
// ---------------------------------------------------------------------------------------

class ConfigError extends Error {}
class UpstreamError extends Error {}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

const badRequest = (error: string, message?: string) => jsonResponse({ error, message }, 400);
const unauthorized = (message?: string) => jsonResponse({ error: "unauthorized", message }, 401);
const forbidden = (message?: string) => jsonResponse({ error: "forbidden", message }, 403);
const notFound = (message?: string) => jsonResponse({ error: "not_found", message }, 404);
const unsupportedMedia = (message?: string) => jsonResponse({ error: "unsupported_media_type", message }, 415);
const conflict = (error: string, message?: string) => jsonResponse({ error, message }, 409);
const badGateway = (message?: string) => jsonResponse({ error: "upstream_unavailable", message }, 502);
const serverError = (message?: string) => jsonResponse({ error: "internal_error", message }, 500);

function bytesToBase64(bytes: Uint8Array): string {
  const chunkSize = 0x8000; // avoid String.fromCharCode argument-count limits on large images
  let binary = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function mimeTypeForPath(path: string): { mime: string | null; unsupportedButUploadable: boolean } {
  const ext = path.split(".").pop()?.toLowerCase() ?? "";
  if (SUPPORTED_VISION_MIME_TYPES[ext]) {
    return { mime: SUPPORTED_VISION_MIME_TYPES[ext], unsupportedButUploadable: false };
  }
  return { mime: null, unsupportedButUploadable: UNSUPPORTED_BUT_UPLOADABLE_EXTENSIONS.has(ext) };
}

// ---------------------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    console.error("meal-vision: SUPABASE_URL / SUPABASE_ANON_KEY not available in function env");
    return serverError("server misconfigured");
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return unauthorized("missing Authorization header");

  // User-scoped client: every query below runs as the caller, so RLS (meals_owner,
  // meal_photos_select_own, ...) is the actual enforcement — not application-level checks we
  // could get wrong. See docs/spec.md §13 ("RLS = user_id = auth.uid() on everything").
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) return unauthorized("invalid or expired session");
  const userId = userData.user.id;

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return badRequest("invalid_json", "request body must be JSON");
  }

  const action = typeof body.action === "string" ? body.action : "analyze";

  try {
    if (action === "analyze") return await handleAnalyze(supabase, userId, body);
    if (action === "confirm") return await handleConfirm(supabase, userId, body);
    return badRequest("invalid_action", `unknown action "${action}"`);
  } catch (err) {
    if (err instanceof ConfigError) {
      console.error("meal-vision: config error", err.message);
      return serverError("server misconfigured");
    }
    if (err instanceof UpstreamError) {
      return badGateway("meal photo analysis is temporarily unavailable, please try again");
    }
    console.error("meal-vision: unhandled error", err);
    return serverError("unexpected error");
  }
});

async function handleAnalyze(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const photoPath = typeof body.photoPath === "string" ? body.photoPath : null;
  const existingMealId = typeof body.mealId === "string" ? body.mealId : null;
  if (!photoPath) return badRequest("missing_photo_path", "photoPath is required");

  // Defense in depth: storage RLS (meal_photos_select_own) already scopes downloads to the
  // caller's own folder, but fail fast with a clear error instead of a generic storage 403.
  if (!photoPath.startsWith(`${userId}/`)) {
    return forbidden("photoPath must be under the caller's own folder");
  }

  const { mime, unsupportedButUploadable } = mimeTypeForPath(photoPath);
  if (!mime) {
    return unsupportedMedia(
      unsupportedButUploadable
        ? "HEIC/HEIF photos aren't supported by meal vision yet — please upload as JPEG, PNG, or WebP"
        : "unsupported image type",
    );
  }

  if (existingMealId) {
    const { data: existing, error: existingErr } = await supabase
      .from("meals")
      .select("id, confirmed")
      .eq("id", existingMealId)
      .eq("user_id", userId)
      .maybeSingle();
    if (existingErr) {
      console.error("meal-vision: lookup existing meal failed", existingErr);
      return serverError("could not look up meal");
    }
    if (!existing) return notFound("mealId not found for this user");
    // `mealId` here is documented as "retry vision on an existing *draft* row" — never silently
    // clobber a meal the user already confirmed (and possibly hand-edited via the slider) with a
    // fresh, unconfirmed auto-estimate. Without this guard, a stale client retry or a duplicate
    // request racing a confirm could wipe a user-approved protein value back to a guess.
    if (existing.confirmed) {
      return conflict("already_confirmed", "this meal was already confirmed; analyze only retries a draft");
    }
  }

  const { data: fileBlob, error: downloadErr } = await supabase.storage
    .from(MEAL_PHOTOS_BUCKET)
    .download(photoPath);
  if (downloadErr || !fileBlob) {
    console.error("meal-vision: photo download failed", downloadErr);
    return notFound("photo not found");
  }

  const bytes = new Uint8Array(await fileBlob.arrayBuffer());
  const base64Image = bytesToBase64(bytes);

  const llmText = await callVisionLlm(base64Image, mime);

  let parsed: unknown;
  try {
    parsed = parseJsonFromLlmText(llmText);
  } catch (err) {
    console.error("meal-vision: could not parse LLM JSON", err, llmText.slice(0, 500));
    return badGateway("could not read meal analysis, please try again");
  }

  const result = validateMealVisionResult(parsed);
  if (!result) {
    console.error("meal-vision: LLM JSON failed shape validation", llmText.slice(0, 500));
    return badGateway("could not read meal analysis, please try again");
  }

  const mealId = existingMealId ?? crypto.randomUUID();
  // TODO(cross-module, §5.19): generate `embedding` for photo+name here once an embeddings
  // endpoint/session owns Quick Repeats — intentionally left null; out of scope for meal-vision
  // per this task's brief.
  const row = {
    id: mealId,
    user_id: userId,
    photo_path: photoPath,
    items: result.items,
    protein_g: result.total_protein,
    confirmed: false,
  };

  const { error: upsertErr } = await supabase.from("meals").upsert(row, { onConflict: "id" });
  if (upsertErr) {
    console.error("meal-vision: failed to store draft meal", upsertErr);
    return serverError("could not save meal analysis");
  }

  return jsonResponse({ mealId, photoPath, confirmed: false, result }, 200);
}

async function handleConfirm(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const mealId = typeof body.mealId === "string" ? body.mealId : null;
  if (!mealId) return badRequest("missing_meal_id", "mealId is required");

  const items = validateEditedItems(body.items);
  if (!items) return badRequest("invalid_items", "items must match [{name, grams_protein_est, confidence}]");

  const totalProtein = body.totalProtein;
  if (!isFiniteNumber(totalProtein) || totalProtein < 0) {
    return badRequest("invalid_total_protein", "totalProtein must be a non-negative number");
  }

  const { data: updated, error: updateErr } = await supabase
    .from("meals")
    .update({ items, protein_g: totalProtein, confirmed: true })
    .eq("id", mealId)
    .eq("user_id", userId)
    .select("id")
    .maybeSingle();

  if (updateErr) {
    console.error("meal-vision: confirm update failed", updateErr);
    return serverError("could not confirm meal");
  }
  if (!updated) return notFound("mealId not found for this user");

  return jsonResponse({ mealId, confirmed: true, proteinG: totalProtein }, 200);
}
