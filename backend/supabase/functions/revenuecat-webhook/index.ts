// backend/supabase/functions/revenuecat-webhook/index.ts
//
// ZANO RevenueCat webhook receiver — docs/spec.md §21 (Monetization & Paywall: Free/Pro tiers,
// RevenueCat as the subscription system of record) and §13 (Data Model:
// `subscriptions (user_id, rc_customer_id, status, product, renews_at) -- from RevenueCat webhook`).
// Also docs/spec.md §11 (`Edge Functions: ... webhooks (RevenueCat)`) and §12
// (`Subscriptions | RevenueCat (+ optional Superwall for paywall A/B) | Fast, tested`).
//
// This function assumes the app configures RevenueCat's `appUserID` to be the Supabase Auth user
// id (`Purchases.logIn(<supabase user id>)`), which is the standard, documented way to align
// RevenueCat with a backend's own user identity. Until the app is authenticated (spec §11:
// "anonymous-first (no account required until sync/paywall)"), RevenueCat may still be running
// under its own auto-generated anonymous id (`$RCAnonymousID:...`); events carrying one of those
// can't be mapped to a `users.id` yet and are acknowledged (200) without a DB write rather than
// retried forever — see the TODO below and knownIssues in the session report for the identity-
// linking sequencing this depends on (owned by the onboarding/paywall session).
//
// Auth: RevenueCat does not sign webhook payloads. Instead, the dashboard lets you set a fixed
// "Authorization header value" that RevenueCat echoes back on every request; we compare that
// against REVENUECAT_WEBHOOK_SECRET (Deno.env only, never hardcoded) with a constant-time compare.
//
// Response contract with RevenueCat: any non-2xx causes RevenueCat to retry with backoff. We only
// return non-2xx for auth failures and malformed requests, never for "nothing to do" cases (e.g.
// TEST events, unmappable anonymous ids) — those are 200s that skip the DB write, so a webhook we
// can't yet act on doesn't retry forever.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// RevenueCat webhook payload shape
// https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
// ---------------------------------------------------------------------------

type RCEventType =
  | "TEST"
  | "INITIAL_PURCHASE"
  | "RENEWAL"
  | "CANCELLATION"
  | "UNCANCELLATION"
  | "NON_RENEWING_PURCHASE"
  | "SUBSCRIPTION_PAUSED"
  | "EXPIRATION"
  | "BILLING_ISSUE"
  | "PRODUCT_CHANGE"
  | "TRANSFER"
  | "SUBSCRIBER_ALIAS"
  | "TEMPORARY_ENTITLEMENT_GRANT"
  | string; // RevenueCat has added new event types over time — don't hard-fail on an unknown one.

interface RCEvent {
  type: RCEventType;
  app_user_id: string;
  original_app_user_id?: string;
  transferred_from?: string[];
  transferred_to?: string[];
  product_id?: string;
  entitlement_ids?: string[];
  purchased_at_ms?: number;
  expiration_at_ms?: number | null;
  environment?: "SANDBOX" | "PRODUCTION";
  store?: string;
}

interface RCWebhookBody {
  api_version?: string;
  event?: RCEvent;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Constant-time string compare — avoids leaking the configured secret's value through response
 *  timing. Deliberately dependency-free (no std/crypto import) since this can't be verified with
 *  `deno check`/`deno test` in this environment; a straightforward XOR-accumulate is easy to audit
 *  by eye. */
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const bytesA = enc.encode(a);
  const bytesB = enc.encode(b);
  // Always compare the same number of bytes regardless of length, then fold in a length mismatch,
  // so total work (and therefore timing) doesn't depend on how much of the secret matched.
  const len = Math.max(bytesA.length, bytesB.length, 1);
  let diff = bytesA.length === bytesB.length ? 0 : 1;
  for (let i = 0; i < len; i++) {
    const byteA = i < bytesA.length ? bytesA[i] : 0;
    const byteB = i < bytesB.length ? bytesB[i] : 0;
    diff |= byteA ^ byteB;
  }
  return diff === 0;
}

function isAuthorized(req: Request, expectedSecret: string): boolean {
  const header = req.headers.get("Authorization");
  if (!header) return false;
  // RevenueCat sends back exactly what was configured in the dashboard; accept it whether that
  // value was entered as a bare secret or already includes a "Bearer " prefix.
  const presented = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : header;
  return timingSafeEqual(presented, expectedSecret);
}

/** Maps a RevenueCat event to the `subscriptions.status` text this app reads (paywall/entitlement
 *  gating logic elsewhere trusts these exact strings). Unknown/future event types map to `null`
 *  (skip the write) rather than guessing at a status. */
function statusForEvent(type: RCEventType): string | null {
  switch (type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
    case "PRODUCT_CHANGE":
    case "NON_RENEWING_PURCHASE":
    case "TEMPORARY_ENTITLEMENT_GRANT":
      return "active";
    case "CANCELLATION":
      // Auto-renew turned off but the entitlement is typically still active until
      // `expiration_at_ms` — record the intent as `canceled`; `renews_at` still carries the real
      // expiry so callers can tell "canceled but not yet expired" from "expired".
      return "canceled";
    case "SUBSCRIPTION_PAUSED":
      return "paused";
    case "EXPIRATION":
      return "expired";
    case "BILLING_ISSUE":
      return "billing_issue";
    default:
      return null;
  }
}

function msToISOStringOrNull(ms: number | null | undefined): string | null {
  if (typeof ms !== "number" || !Number.isFinite(ms)) return null;
  return new Date(ms).toISOString();
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed", message: "revenuecat-webhook only accepts POST" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !webhookSecret) {
    console.error("revenuecat-webhook: missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / REVENUECAT_WEBHOOK_SECRET env vars");
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  if (!isAuthorized(req, webhookSecret)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: RCWebhookBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "bad_request", message: "body must be JSON" }, 400);
  }

  const event = body.event;
  if (!event || typeof event.type !== "string" || typeof event.app_user_id !== "string") {
    return jsonResponse({ error: "bad_request", message: "missing event.type or event.app_user_id" }, 400);
  }

  // RevenueCat's "Send Test" button in the dashboard sends a TEST event with a placeholder
  // app_user_id that will never be a real Supabase user — acknowledge it and stop, so dashboard
  // configuration can be verified without needing a matching `users` row.
  if (event.type === "TEST") {
    return jsonResponse({ ok: true, skipped: "test_event" });
  }

  // TRANSFER moves entitlements from one app_user_id to another (e.g. RevenueCat's anonymous id
  // being merged into the now-identified Supabase user id at `Purchases.logIn()` time). It carries
  // `transferred_from`/`transferred_to` id lists but, unlike other event types, no reliable
  // product_id/expiration_at_ms — and `subscriptions.user_id` is this table's primary key, so
  // blindly re-pointing a row risks a primary-key collision if the destination already has one.
  // TODO(cross-module — onboarding/paywall session): decide the merge policy once it's confirmed
  // exactly when `Purchases.logIn(<supabase id>)` runs relative to auth/sync bootstrap. Until then
  // we deliberately do NOT mutate `subscriptions` for TRANSFER — we acknowledge it (so RevenueCat
  // doesn't retry) and rely on the RENEWAL/PRODUCT_CHANGE event RC sends alongside most transfers
  // to (re)populate the destination user's row with real data via the normal path below.
  if (event.type === "TRANSFER") {
    return jsonResponse({ ok: true, skipped: "transfer_event_not_migrated" });
  }

  const destinationUserID = event.app_user_id;

  if (!UUID_RE.test(destinationUserID)) {
    // Most commonly a still-anonymous RevenueCat id ($RCAnonymousID:...) that hasn't been linked
    // to a Supabase user yet. Nothing to write; ack so RevenueCat doesn't retry.
    return jsonResponse({ ok: true, skipped: "app_user_id_not_a_supabase_uuid" });
  }

  const status = statusForEvent(event.type);
  if (status === null) {
    // Known-but-unhandled or genuinely unknown event type — ack without guessing at a status.
    return jsonResponse({ ok: true, skipped: `unhandled_event_type:${event.type}` });
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const row = {
    user_id: destinationUserID,
    rc_customer_id: event.original_app_user_id ?? event.app_user_id,
    status,
    product: event.product_id ?? null,
    renews_at: msToISOStringOrNull(event.expiration_at_ms ?? null),
  };

  const { error } = await admin.from("subscriptions").upsert(row, { onConflict: "user_id" });
  if (error) {
    console.error("revenuecat-webhook: upsert failed", error);
    return jsonResponse({ error: "db_write_failed", message: error.message }, 500);
  }

  return jsonResponse({ ok: true });
});
