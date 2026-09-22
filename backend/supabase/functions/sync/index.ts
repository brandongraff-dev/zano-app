// backend/supabase/functions/sync/index.ts
//
// ZANO outbox sync endpoint — docs/spec.md §11 ("Sync (Supabase client, outbox pattern)" /
// "Sync outbox pushes to Supabase when online → ... → app pulls on launch and via silent push")
// and §13 (Data Model — table/column shapes this function reads and writes).
//
// Contract with the client: Core/Sources/Core/Sync/OutboxEvent.swift (owned by another session;
// this function does not assume that file's exact Swift declaration, only the JSON wire shape
// described in this session's task: `entityName`, `entityID`, `payload`, `createdAt`).
//
// Request (POST, JSON body):
//   {
//     "events": [
//       { "entityName": "goal", "entityID": "<uuid>", "payload": { ... }, "createdAt": "<iso8601 or epoch-seconds>" }
//     ],
//     "since": "<iso8601>"   // optional — server changes strictly after this instant are returned
//   }
//
// Response 200 JSON:
//   {
//     "syncedAt": "<iso8601>",              // pass this back as `since` on the next call
//     "accepted": [{ "entityName": ..., "entityID": ... }],
//     "rejected": [{ "entityName": ..., "entityID": ..., "reason": "..." }],
//     "changes": { "<entityName>": [ <row>, ... ], ... },
//     "truncated": ["<entityName>", ...]    // entities where more rows exist than the page cap
//   }
//
// Auth: every request must carry `Authorization: Bearer <supabase user JWT>` (anonymous or
// Sign-in-with-Apple-linked — spec §11 "Auth (Sign in with Apple, anonymous → linked)"). The JWT
// is verified against Supabase Auth itself (`auth.getUser()`), never by hand-decoding it — that is
// the documented, supported way to authenticate an Edge Function request. Once we know the caller,
// all writes are force-scoped to that user's own rows: a client can never smuggle another user's
// `user_id` through the outbox payload, regardless of what RLS on the table would otherwise allow.
//
// Secrets: SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are the reserved env vars
// Supabase injects into every Edge Function automatically — read via Deno.env only, never hardcoded.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Config: which outbox entities are syncable, and how each maps onto docs/spec.md §13 tables.
// ---------------------------------------------------------------------------

interface EntityConfig {
  /** Postgres table name (docs/spec.md §13 / backend/supabase/migrations/0001_init.sql). */
  table: string;
  /** Primary key column on that table. */
  pk: string;
  /** Column enforcing per-user ownership — always forced to the authenticated user's id. */
  ownerColumn: string;
  /** True when pk === ownerColumn (one row per user — e.g. streaks, coins). */
  ownerIsPk: boolean;
  /** Payload keys the client may write. Anything else in `payload` is dropped, not errored on,
   *  so older/newer app builds can send extra fields without breaking sync. */
  allowedColumns: string[];
  /** Column used to answer "what changed since <since>?". `null` = table has no reliable
   *  change-timestamp column in the frozen §13 schema, so we always return the full (small,
   *  per-user-bounded) set instead of filtering — see knownIssues in the session report. */
  changeColumn: string | null;
}

// Canonical entity keys are matched case- and separator-insensitively (see `normalize`), so
// "Goal", "goal", "goals", "GOAL_EVENT" and "goalEvent" all resolve correctly regardless of the
// exact string OutboxEvent's Swift call sites end up using — that spelling isn't finalized yet on
// the Core side, and this endpoint has to be tolerant of it rather than assume one convention.
const ENTITY_CONFIG: Record<string, EntityConfig> = {
  goal: {
    table: "goals",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: [
      "type",
      "title",
      "target_value",
      "unit",
      "cadence",
      "verification_tier",
      "active",
      "adaptive",
    ],
    changeColumn: "created_at",
  },
  dailyPlan: {
    table: "daily_plans",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: ["date", "goal_id", "planned_value", "difficulty_step", "plan_b_value", "source"],
    changeColumn: null,
  },
  goalEvent: {
    table: "goal_events",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: ["goal_id", "ts", "kind", "value", "source", "verified", "meta"],
    changeColumn: "ts",
  },
  lockSet: {
    table: "lock_sets",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    // `app_tokens_blob` is deliberately NOT syncable: FamilyControls app tokens never leave the
    // device (CLAUDE.md, docs/spec.md §11/§13) — Postgres only ever stores the lock-set *name*.
    allowedColumns: ["name", "is_default"],
    changeColumn: null,
  },
  lockSession: {
    table: "lock_sessions",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: [
      "lock_set_id",
      "started_at",
      "ended_at",
      "trigger",
      "mode",
      "required_goal_ids",
      "unlock_kind",
    ],
    changeColumn: "started_at",
  },
  timeBank: {
    table: "time_bank",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: ["date", "earned_min", "spent_min"],
    changeColumn: null,
  },
  streak: {
    table: "streaks",
    pk: "user_id",
    ownerColumn: "user_id",
    ownerIsPk: true,
    allowedColumns: ["current", "best", "freezes_left", "last_earned_date", "never_miss_twice_armed"],
    changeColumn: null,
  },
  gym: {
    table: "gyms",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: ["lat", "lng", "radius_m", "name", "auto_detected", "confirmed"],
    changeColumn: null,
  },
  meal: {
    table: "meals",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    // `embedding` is excluded: it's computed server-side (meal-vision function, §9.5), never
    // client-supplied.
    allowedColumns: ["ts", "photo_path", "items", "protein_g", "confirmed"],
    changeColumn: "ts",
  },
  badge: {
    table: "badges",
    pk: "id",
    ownerColumn: "user_id",
    ownerIsPk: false,
    allowedColumns: ["key", "earned_at"],
    changeColumn: "earned_at",
  },
  coin: {
    table: "coins",
    pk: "user_id",
    ownerColumn: "user_id",
    ownerIsPk: true,
    allowedColumns: ["balance"],
    changeColumn: null,
  },
  user: {
    table: "users",
    pk: "id",
    ownerColumn: "id",
    ownerIsPk: true,
    // Only user-editable preferences. `apple_sub` (Sign-in-with-Apple linking), `plan_tier`
    // (revenuecat-webhook owns this), and `referral_code`/`referred_by` are never client-writable
    // through the outbox.
    allowedColumns: ["tz", "coach_voice"],
    changeColumn: "created_at",
  },
};

// squads / squad_members / duels are intentionally NOT in ENTITY_CONFIG: their RLS ownership is
// multi-party (member-readable, creator-writable / both-duelist-writable — see
// backend/supabase/migrations/0001_init.sql) rather than the simple "one owner column" shape this
// generic engine enforces. Syncing them safely needs bespoke per-entity authorization (e.g. "only
// the squad creator may rename it, but any member may see it"), which is a product decision docs/
// spec.md §11/§13 don't pin down for the outbox specifically — flagged as a follow-up rather than
// guessed at here. `recaps`, `nudges`, `risk_scores` and `subscriptions` are server-written only
// (weekly-recap job, ML service, this session's revenuecat-webhook) and are rejected below if a
// client ever sends them.
const SERVER_OWNED_ENTITY_NAMES = ["recap", "nudge", "riskScore", "subscription", "squad", "squadMember", "duel"];

function normalize(raw: string): string {
  return raw.toLowerCase().replace(/[^a-z0-9]/g, "");
}

const ENTITY_LOOKUP: Record<string, string> = {};
for (const key of Object.keys(ENTITY_CONFIG)) {
  const cfg = ENTITY_CONFIG[key];
  ENTITY_LOOKUP[normalize(key)] = key;
  ENTITY_LOOKUP[normalize(cfg.table)] = key;
  // also accept the singular of the table name (tables are plural nouns) and a trailing-"s" plural
  // of the canonical key, since both are common client-side spellings.
  ENTITY_LOOKUP[normalize(cfg.table.replace(/s$/, ""))] = key;
  ENTITY_LOOKUP[normalize(`${key}s`)] = key;
}
const SERVER_OWNED_LOOKUP = new Set(SERVER_OWNED_ENTITY_NAMES.map(normalize));

function resolveEntity(entityName: string): EntityConfig | null {
  const key = ENTITY_LOOKUP[normalize(entityName)];
  return key ? ENTITY_CONFIG[key] : null;
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

interface IncomingOutboxEvent {
  entityName: string;
  entityID: string;
  payload: Record<string, unknown>;
  createdAt: string | number;
}

interface SyncRequestBody {
  events?: unknown;
  since?: unknown;
}

const MAX_EVENTS_PER_REQUEST = 500;
const MAX_ROWS_PER_ENTITY_PULL = 1000;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

/** Swift's default JSONEncoder emits Date as epoch-seconds unless `.iso8601` strategy is set
 *  explicitly on the Sync module's encoder; accept either so this endpoint doesn't break depending
 *  on which strategy OutboxEvent.swift's JSONEncoder ends up configured with. */
function parseFlexibleDate(value: unknown): Date | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value * 1000);
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  return null;
}

function pickAllowed(payload: Record<string, unknown>, allowedColumns: string[]): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const col of allowedColumns) {
    if (Object.prototype.hasOwnProperty.call(payload, col)) {
      out[col] = payload[col];
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed", message: "sync only accepts POST" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("sync: missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY env vars");
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "unauthorized", message: "missing Authorization header" }, 401);
  }

  // Scoped to the caller's own JWT so `auth.getUser()` validates it against Supabase Auth itself —
  // this is the supported way to authenticate a request inside an Edge Function; we never hand-
  // decode or hand-verify the JWT ourselves.
  const userClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: authError } = await userClient.auth.getUser();
  if (authError || !userData?.user) {
    return jsonResponse({ error: "unauthorized", message: "invalid or expired session" }, 401);
  }
  const userID = userData.user.id;

  let body: SyncRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "bad_request", message: "body must be JSON" }, 400);
  }

  const rawEvents = Array.isArray(body.events) ? body.events : [];
  if (rawEvents.length > MAX_EVENTS_PER_REQUEST) {
    return jsonResponse(
      { error: "payload_too_large", message: `at most ${MAX_EVENTS_PER_REQUEST} events per request` },
      413,
    );
  }

  let since: Date | null = null;
  if (typeof body.since === "string" && body.since.length > 0) {
    const parsed = new Date(body.since);
    if (Number.isNaN(parsed.getTime())) {
      return jsonResponse({ error: "bad_request", message: "`since` must be a valid ISO 8601 timestamp" }, 400);
    }
    since = parsed;
  }

  // Service-role client for the actual writes/reads: every query below is hand-scoped to `userID`
  // (never trusts a `user_id` in the client payload), so bypassing RLS here is safe and is what
  // lets a single request touch several tables inside one authenticated call.
  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const accepted: { entityName: string; entityID: string }[] = [];
  const rejected: { entityName: string; entityID: string | null; reason: string }[] = [];

  for (const raw of rawEvents) {
    const event = raw as Partial<IncomingOutboxEvent>;
    const entityNameRaw = typeof event.entityName === "string" ? event.entityName : null;
    const entityID = typeof event.entityID === "string" ? event.entityID : null;
    const payload = event.payload && typeof event.payload === "object" ? (event.payload as Record<string, unknown>) : null;

    if (!entityNameRaw || !entityID || !payload) {
      rejected.push({
        entityName: entityNameRaw ?? "unknown",
        entityID: entityID,
        reason: "missing entityName, entityID, or payload",
      });
      continue;
    }
    if (!UUID_RE.test(entityID)) {
      rejected.push({ entityName: entityNameRaw, entityID, reason: "entityID is not a valid UUID" });
      continue;
    }
    if (parseFlexibleDate(event.createdAt) === null) {
      rejected.push({ entityName: entityNameRaw, entityID, reason: "createdAt is not a valid date" });
      continue;
    }
    if (SERVER_OWNED_LOOKUP.has(normalize(entityNameRaw))) {
      rejected.push({ entityName: entityNameRaw, entityID, reason: "entity is server-managed, not syncable from client" });
      continue;
    }

    const config = resolveEntity(entityNameRaw);
    if (!config) {
      rejected.push({ entityName: entityNameRaw, entityID, reason: `unknown entityName "${entityNameRaw}"` });
      continue;
    }

    const row = pickAllowed(payload, config.allowedColumns);
    row[config.ownerColumn] = userID; // always force ownership — never trust the client here
    if (!config.ownerIsPk) {
      row[config.pk] = entityID;
    }

    const { error } = await admin.from(config.table).upsert(row, { onConflict: config.pk });
    if (error) {
      console.error(`sync: upsert failed for ${config.table}`, error);
      rejected.push({ entityName: entityNameRaw, entityID, reason: error.message });
      continue;
    }
    accepted.push({ entityName: entityNameRaw, entityID });
  }

  // Pull phase: server-side changes since the client's last cursor, per syncable entity.
  const syncedAt = new Date();
  const changes: Record<string, unknown[]> = {};
  const truncated: string[] = [];

  for (const key of Object.keys(ENTITY_CONFIG)) {
    const config = ENTITY_CONFIG[key];
    let query = admin.from(config.table).select("*").eq(config.ownerColumn, userID).limit(MAX_ROWS_PER_ENTITY_PULL);

    if (config.changeColumn) {
      query = query.order(config.changeColumn, { ascending: true });
      if (since) {
        query = query.gt(config.changeColumn, since.toISOString());
      }
    } else {
      // No reliable change-timestamp column on this table (see ENTITY_CONFIG's `changeColumn`
      // doc) — we always return the full per-user set instead of filtering by `since`. Postgres
      // gives `LIMIT` no defined row order without an explicit `ORDER BY`, so without this
      // fallback a user whose rows exceed MAX_ROWS_PER_ENTITY_PULL could get a different,
      // incomplete slice on every call and never converge on the full set. Ordering by the
      // primary key is deterministic and stable across calls (it doesn't fix the underlying
      // "no incremental pull for this entity" limitation — see knownIssues).
      query = query.order(config.pk, { ascending: true });
    }

    const { data, error } = await query;
    if (error) {
      console.error(`sync: pull failed for ${config.table}`, error);
      continue; // a failed pull for one entity shouldn't fail the whole response
    }
    if (data && data.length > 0) {
      changes[key] = data;
      if (data.length === MAX_ROWS_PER_ENTITY_PULL) {
        truncated.push(key);
      }
    }
  }

  return jsonResponse({
    syncedAt: syncedAt.toISOString(),
    accepted,
    rejected,
    changes,
    truncated,
  });
});
