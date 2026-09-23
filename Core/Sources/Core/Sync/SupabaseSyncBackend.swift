// Core/Sources/Core/Sync/SupabaseSyncBackend.swift
//
// docs/spec.md §11 (Architecture — "Sync outbox pushes to Supabase when online... app pulls on
// launch and via silent push") and §13 (Data Model).
//
// The real, networked `SyncBackend`/`SyncPullBackend` conformance `SyncEngine.swift` has always
// documented as a future seam. This is the concrete gap docs/sessions/07-backend.md flagged as not
// done: "the app-side half of Sync isn't wired to these functions." This file is that wiring.
//
// New file rather than adding this to SyncEngine.swift, on purpose: SyncEngine's own job is local
// outbox durability (SwiftData reads/writes, actor-isolated state) and deliberately knows nothing
// about HTTP, JSON wire shapes, or auth (see that file's header). This file is the opposite: it
// owns exactly one concern — turning `[OutboxEvent]`/`SyncPullResult` into real HTTP calls against
// one specific Edge Function — and has no SwiftData/ModelContext access at all. Splitting them
// keeps each file's diff, for whoever touches either concern next, small and single-purpose,
// matching this directory's existing convention of one concern per file (`OutboxEvent.swift` vs.
// `SyncEngine.swift` already split the same way) and `Verification`'s (`BarcodeProteinLookup.swift`
// is a similarly self-contained, stateless, `URLSession`-based `Sendable` struct with its own
// protocol seam for the one piece — there, a nutrition-API vendor; here, an auth-token source —
// that this session can't build for real yet).
//
// Wire contract — read directly from `backend/supabase/functions/sync/index.ts` for this task, not
// assumed from memory:
//   Request  (POST, JSON body): { events: [{ entityName, entityID, payload, createdAt }], since? }
//   Response (200, JSON body):  { syncedAt, accepted: [{entityName,entityID}],
//                                  rejected: [{entityName,entityID,reason}],
//                                  changes: { "<entityName>": [<row>, ...] }, truncated: [...] }
//   Auth: `Authorization: Bearer <supabase user JWT>`, verified server-side via `auth.getUser()`.
//   `entityName` matching is case/separator-insensitive server-side (`normalize()` in index.ts), so
//   this file doesn't need to match the server's exact canonical spelling for each entity — see
//   `OutboxEvent.swift`'s own doc comment on `entityName` for the strings callers already use
//   (`"Goal"`, `"LockSession"`, `"TimeBank"`, ...).
//
// A crucial, easy-to-get-wrong detail this file gets right on purpose: `OutboxEvent.payload` is
// already-JSON-encoded `Data` (see OutboxEvent.swift). The wire contract above needs `payload` to
// be a JSON *object* nested in the request body, not a JSON string/base64 blob — so this file
// decodes each event's `payload` with `JSONSerialization` and re-embeds the resulting object
// directly, rather than naively `Codable`-encoding `[OutboxEvent]` (which would emit `payload` as
// a base64 string via `Data`'s default `Encodable` conformance and silently violate the contract).
//
// Real Supabase API surface — NOT verified live (no Supabase project exists yet, per
// docs/PROGRESS.md — flagged per CLAUDE.md working rule 5, not presented as certain):
//   - The exact Edge Function invocation URL shape. This file takes the caller's full
//     `functionsBaseURL` rather than guessing/constructing one from a project ref, specifically to
//     avoid baking in an unverified URL pattern — training knowledge says Supabase Edge Functions
//     are served at `https://<project-ref>.supabase.co/functions/v1/<function-name>`, but that
//     hasn't been checked against a live project for this codebase.
//   - Whether Supabase's API gateway requires an `apikey` header (the anon key) on Edge Function
//     requests in addition to `Authorization: Bearer <user JWT>`, the way it does for
//     PostgREST/Storage/Realtime. `supabase-js`'s `functions.invoke()` sends both together, so this
//     file does too (`apikey` = anon key, `Authorization` = the user's own JWT, never the anon key)
//     — but whether the gateway actually rejects a request missing `apikey` for Functions
//     specifically, on the Supabase version this project ends up on, is unverified.
//   - Whether a 401 from the gateway itself (bad/missing `apikey`) is distinguishable from a 401
//     the function returns itself (`auth.getUser()` failed) — both are treated identically here
//     (`.unauthorized`) since neither the request nor response shape documented in index.ts gives a
//     client-visible way to tell them apart.
//   - `Date.prototype.toISOString()` (what `index.ts` builds `syncedAt` from) always includes
//     millisecond fractional seconds; `parseISO8601FromServer(_:)` below is written to expect that,
//     falling back to no-fractional-seconds parsing defensively, but this exact wire value has
//     never been observed from a live response.
//
// Not the app-side networking's fault, but worth restating here since this file is the one that
// finally makes it observable: docs/sessions/07-backend.md also flags that the SQL/TypeScript
// itself has never run against a real or local Postgres instance either — so the *server* half of
// this contract is equally unverified, independent of anything in this file.

import Foundation
import os

// MARK: - Auth seam

/// Supplies the Supabase user JWT this backend attaches as `Authorization: Bearer <token>` on
/// every request (index.ts: "every request must carry `Authorization: Bearer <supabase user
/// JWT>`... anonymous or Sign-in-with-Apple-linked").
///
/// A seam, not a concrete type, on purpose: no Auth/session module exists yet anywhere in `Core` —
/// docs/sessions/07-backend.md's own known issue is that "Anonymous → Sign in with Apple account
/// linking... is not built," only the downstream Postgres trigger is. Guessing that future
/// module's shape here is exactly the mistake this wave's own instructions warn against, so this
/// file only declares the seam a future Auth session type conforms to and hands in at
/// `SupabaseSyncBackend.init(...)` — mirroring `BarcodeNutritionFallbackProvider`'s
/// (`Verification/BarcodeProteinLookup.swift`) identical situation: a real vendor/module doesn't
/// exist yet, so only the protocol ships.
public protocol SupabaseAuthTokenProviding: Sendable {
    /// Returns the current user's Supabase access token, refreshing it first if the conformer
    /// knows it has expired. Throws — never returns an empty/placeholder string — when no session
    /// exists yet or a refresh failed, since `SupabaseSyncBackend` has nothing meaningful to try
    /// without a real token (the Edge Function rejects a missing/invalid one with 401 regardless).
    func supabaseAccessToken() async throws -> String
}

// MARK: - Errors

/// Errors `SupabaseSyncBackend` throws. Kept `Sendable`/`Equatable` with plain `String`/nested-
/// struct associated values (never a raw `Error`), matching this directory's and `Verification`'s
/// existing convention (`BarcodeProteinLookupError`, `SyncEngineError`).
public enum SupabaseSyncBackendError: Error, Sendable, Equatable {
    /// No token was available (`SupabaseAuthTokenProviding` threw), or the server itself rejected
    /// the request as unauthorized (HTTP 401 — either the gateway's own check or `auth.getUser()`
    /// failing inside the function; index.ts's response shape doesn't let a client tell those
    /// apart, see this file's header).
    case unauthorized
    /// The network request itself failed (no connectivity, timeout, DNS/TLS failure, ...). The
    /// associated string is `(error as NSError).localizedDescription`.
    case transportFailure(String)
    /// A non-2xx, non-401 HTTP status. `message` is the Edge Function's own `{"error","message"}`
    /// body field when present (index.ts returns this shape for its own validation failures —
    /// `bad_request`, `payload_too_large`, `method_not_allowed`, `server_misconfigured`), `nil`
    /// otherwise.
    case serverError(status: Int, message: String?)
    /// A 2xx response arrived but its body didn't decode as the documented shape at all (missing/
    /// malformed `syncedAt`, non-object top level, a `changes` row that wasn't a JSON object, ...).
    case decodingFailure(String)
    /// An `OutboxEvent.payload` couldn't be re-decoded as JSON before being embedded in the request
    /// body — would only happen if something upstream of `SyncEngine.enqueue` wrote a corrupt
    /// payload, since `OutboxEvent`'s own initializer always JSON-encodes it first.
    case encodingFailure(String)
    /// `push(_:)`'s batch was rejected, in whole or in part, by the Edge Function (bad `entityID`
    /// format, unknown `entityName`, a server-owned entity, a Postgres constraint/RLS failure, ...
    /// — see index.ts's `rejected` cases). Per `SyncBackend.push`'s documented all-or-nothing
    /// contract (`SyncEngine.swift`), this backend throws for the **whole batch** even if only one
    /// event was rejected, so `SyncEngine` doesn't mark a partially-accepted batch synced.
    ///
    /// Known tradeoff, not an oversight: a *permanently* invalid event (e.g. a stale app build
    /// sending a since-renamed `entityName`) will keep failing — and therefore keep blocking every
    /// other queued event behind it in outbox order — on every future `flush()`, since
    /// `SyncBackend.push`'s current shape has no way to report "these succeeded, these didn't"
    /// back to `SyncEngine` for partial marking. Fixing that needs a richer `SyncBackend.push`
    /// return/throw shape, which is a real protocol change other conformers (and
    /// `SyncTests.swift`'s `FakeSyncBackend`) would need to follow — out of this task's scope,
    /// flagged here rather than silently worked around.
    case eventsRejected([RejectedEvent])

    /// One rejected event, exactly as the Edge Function reported it.
    public struct RejectedEvent: Sendable, Equatable {
        public let entityName: String
        public let entityID: String?
        public let reason: String
    }
}

// MARK: - SupabaseSyncBackend

/// Real `SyncBackend`/`SyncPullBackend` conformance: POSTs queued `OutboxEvent`s to the `sync`
/// Edge Function and fetches server-side changes from the same endpoint. See this file's header
/// for the exact wire contract and what's unverified.
///
/// A plain `Sendable` struct, not an actor — exactly `BarcodeProteinLookup`'s reasoning
/// (`Verification/BarcodeProteinLookup.swift`): every stored property is itself `Sendable`
/// (`URL`, `String`, `URLSession`, `any SupabaseAuthTokenProviding`, `Logger`) and each
/// `push`/`pull` call is a self-contained request/response with no state shared across calls, so
/// there's nothing here that needs an actor's mutual-exclusion the way `SyncEngine`'s own
/// outbox-batch bookkeeping does. Construct one and hand it to
/// `SyncEngine.shared.configure(modelContainer:backend:)` / `setBackend(_:)` once a real
/// `SupabaseAuthTokenProviding` exists to pass in — nothing else about `SyncEngine` changes.
public struct SupabaseSyncBackend: SyncPullBackend {
    /// Path (relative to `functionsBaseURL`) of the one Edge Function this backend talks to.
    static let functionPath = "sync"
    static let requestTimeoutSeconds: TimeInterval = 20

    /// Base URL for this project's Edge Functions, e.g. `https://<project-ref>.supabase.co/
    /// functions/v1` (no trailing slash) — see this file's header for why this is taken as-is
    /// rather than constructed from a project ref internally. Wiring the real value in is a future
    /// app-target config concern (no Supabase project exists yet — docs/PROGRESS.md), not this
    /// file's.
    private let functionsBaseURL: URL
    /// The project's public anon key — safe to ship in the app by Supabase's own design (unlike
    /// the service-role key, which `backend/supabase/functions/sync/index.ts` reads server-side
    /// only and which must never appear here or anywhere else in the app, per CLAUDE.md
    /// "API keys live only in Edge Functions"). Sent as the `apikey` header alongside the per-user
    /// bearer token — see this file's header for why both are sent.
    private let anonKey: String
    private let tokenProvider: any SupabaseAuthTokenProviding
    private let session: URLSession
    /// `static` (not an instance `let`) specifically so the `static func` parsing/encoding helpers
    /// below (kept static, and internal rather than `private`, so a future `CoreTests` can exercise
    /// them directly without constructing a whole backend or making a network call) can log too,
    /// without needing an instance around — `push`/`pull`/`performSyncRequest` reference the same
    /// one via `Self.logger`.
    static let logger = Logger(subsystem: "com.zano.app.Core", category: "SupabaseSyncBackend")

    public init(
        functionsBaseURL: URL,
        anonKey: String,
        tokenProvider: any SupabaseAuthTokenProviding,
        session: URLSession = .shared
    ) {
        self.functionsBaseURL = functionsBaseURL
        self.anonKey = anonKey
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private var functionURL: URL {
        functionsBaseURL.appendingPathComponent(Self.functionPath)
    }

    // MARK: - SyncBackend

    /// POSTs `events` to the `sync` Edge Function. All-or-nothing, per `SyncBackend.push`'s
    /// contract: throws `SupabaseSyncBackendError.eventsRejected` (or a transport/server error) if
    /// even one event in `events` wasn't accepted, so `SyncEngine.flush()` never marks a partially-
    /// accepted batch synced. The response's `changes` are intentionally discarded here — `pull
    /// (since:)` (called separately, by `SyncEngine.pullAndMerge()`) fetches the same server-side
    /// changes on its own schedule, since the Edge Function always answers with the full pull set
    /// for this user regardless of what was pushed alongside it. Kept as two separate round trips
    /// rather than threading `push`'s response into a pull, to match `SyncEngine`'s existing
    /// two-entry-point design (`flush()` on outbox-drain, `pullAndMerge()` on launch/silent-push —
    /// spec §11) rather than coupling their timing together.
    public func push(_ events: [OutboxEventSnapshot]) async throws {
        guard !events.isEmpty else { return }

        let response = try await performSyncRequest(events: events, since: nil)
        guard response.rejected.isEmpty else {
            Self.logger.error(
                "push: \(response.rejected.count, privacy: .public) of \(events.count, privacy: .public) events were rejected by the sync Edge Function."
            )
            throw SupabaseSyncBackendError.eventsRejected(response.rejected)
        }
    }

    // MARK: - SyncPullBackend

    /// Fetches server-side changes strictly after `since` from the same `sync` Edge Function, with
    /// an empty `events` array — a pull-only round trip. See `SyncPullResult`'s own doc comment
    /// (`SyncEngine.swift`) for why the result stays opaque per-entity JSON rather than decoded
    /// model rows.
    public func pull(since: Date?) async throws -> SyncPullResult {
        let response = try await performSyncRequest(events: [], since: since)
        return SyncPullResult(syncedAt: response.syncedAt, changes: response.changes, truncated: response.truncated)
    }

    // MARK: - Request

    private func performSyncRequest(events: [OutboxEventSnapshot], since: Date?) async throws -> ParsedSyncResponse {
        let token: String
        do {
            token = try await tokenProvider.supabaseAccessToken()
        } catch {
            Self.logger.error(
                "performSyncRequest: no Supabase access token available: \(String(describing: error), privacy: .public)"
            )
            throw SupabaseSyncBackendError.unauthorized
        }

        let bodyData = try Self.makeRequestBody(events: events, since: since)

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Both headers sent together, matching `supabase-js`'s own `functions.invoke()` behavior —
        // see this file's header for what's unverified about whether the gateway requires `apikey`
        // for Edge Functions specifically.
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let description = (error as NSError).localizedDescription
            Self.logger.error("performSyncRequest: request failed: \(description, privacy: .public)")
            throw SupabaseSyncBackendError.transportFailure(description)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseSyncBackendError.transportFailure("Non-HTTP response from the sync Edge Function.")
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseSyncBackendError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseSyncBackendError.serverError(
                status: httpResponse.statusCode,
                message: Self.extractErrorMessage(from: data)
            )
        }

        return try Self.parseSyncResponse(data)
    }

    // MARK: - Request body (internal, not `private`, so a future `CoreTests` can exercise these
    // pure functions directly without a network call — same convention
    // `BarcodeProteinLookup`/`QuickRepeatSuggester` use in this same package.)

    /// Builds the request body exactly matching index.ts's documented shape. Critically,
    /// re-embeds each `OutboxEvent.payload` as a JSON *object* (decoded via `JSONSerialization`,
    /// not passed through as `Data`/base64) — see this file's header for why a naive `Codable`
    /// encode of `[OutboxEvent]` would silently violate the wire contract here.
    static func makeRequestBody(events: [OutboxEventSnapshot], since: Date?) throws -> Data {
        var wireEvents: [[String: Any]] = []
        wireEvents.reserveCapacity(events.count)
        for event in events {
            let payloadObject: Any
            do {
                payloadObject = try JSONSerialization.jsonObject(with: event.payload)
            } catch {
                throw SupabaseSyncBackendError.encodingFailure(
                    "OutboxEvent \(event.id) (entityName: \(event.entityName)) has a payload that isn't valid JSON: \(error)"
                )
            }
            wireEvents.append([
                "entityName": event.entityName,
                "entityID": event.entityID.uuidString,
                "payload": payloadObject,
                "createdAt": iso8601String(from: event.createdAt),
            ])
        }

        var body: [String: Any] = ["events": wireEvents]
        if let since {
            body["since"] = iso8601String(from: since)
        }

        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw SupabaseSyncBackendError.encodingFailure("Failed to serialize the sync request body: \(error)")
        }
    }

    // MARK: - Response parsing

    /// The pieces of index.ts's response this file actually reads. `accepted` isn't kept — `push`
    /// only needs to know whether `rejected` is empty, and `SyncPullResult` (what `pull(since:)`
    /// returns) never surfaces it either.
    struct ParsedSyncResponse: Equatable {
        let syncedAt: Date
        let rejected: [SupabaseSyncBackendError.RejectedEvent]
        let changes: [String: [Data]]
        let truncated: Set<String>
    }

    static func parseSyncResponse(_ data: Data) throws -> ParsedSyncResponse {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SupabaseSyncBackendError.decodingFailure("sync response was not valid JSON: \(error)")
        }
        guard let root = jsonObject as? [String: Any] else {
            throw SupabaseSyncBackendError.decodingFailure("sync response's top level was not a JSON object.")
        }
        guard
            let syncedAtString = root["syncedAt"] as? String,
            let syncedAt = parseISO8601FromServer(syncedAtString)
        else {
            throw SupabaseSyncBackendError.decodingFailure("sync response is missing a parseable `syncedAt`.")
        }

        var rejected: [SupabaseSyncBackendError.RejectedEvent] = []
        if let rawRejected = root["rejected"] as? [[String: Any]] {
            rejected = rawRejected.map { entry in
                SupabaseSyncBackendError.RejectedEvent(
                    entityName: entry["entityName"] as? String ?? "unknown",
                    entityID: entry["entityID"] as? String,
                    reason: entry["reason"] as? String ?? "unspecified"
                )
            }
        }

        // Cast per-entity, not the whole `changes` dictionary in one nested `as?` — a single
        // malformed entity's rows must never silently blank out every *other* (well-formed)
        // entity's changes. Skips (and logs) only the one entity whose shape doesn't match,
        // instead of one bad `as?` anywhere in the nesting dropping the entire payload.
        var changes: [String: [Data]] = [:]
        if let rawChanges = root["changes"] as? [String: Any] {
            for (entityName, rawRows) in rawChanges {
                guard let rows = rawRows as? [[String: Any]] else {
                    Self.logger.error(
                        "parseSyncResponse: changes.\(entityName, privacy: .public) wasn't an array of JSON objects — skipped, other entities unaffected."
                    )
                    continue
                }
                changes[entityName] = try rows.map { row in
                    do {
                        return try JSONSerialization.data(withJSONObject: row)
                    } catch {
                        throw SupabaseSyncBackendError.decodingFailure(
                            "sync response's changes.\(entityName) contained a row that couldn't be re-encoded: \(error)"
                        )
                    }
                }
            }
        }

        let truncated = Set((root["truncated"] as? [String]) ?? [])

        return ParsedSyncResponse(syncedAt: syncedAt, rejected: rejected, changes: changes, truncated: truncated)
    }

    /// `error.message` from index.ts's own `{"error","message"}` shape, when the body decodes
    /// that far. Best-effort only — used purely for `SupabaseSyncBackendError.serverError`'s
    /// associated value, never thrown itself if this fails.
    static func extractErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = object as? [String: Any] else { return nil }
        return dict["message"] as? String
    }

    // MARK: - Dates
    //
    // Fresh `ISO8601DateFormatter()` per call rather than a shared `static let` — matching
    // `OutboxEvent.makeJSONEncoder()`'s own documented reasoning (`OutboxEvent.swift`): this
    // formatter class's `Sendable`-ness under Swift 6 strict concurrency isn't something this
    // session can verify against a real SDK, so this sidesteps the question rather than asserting
    // an answer by caching one across calls/threads.

    /// Matches `OutboxEvent.makeJSONEncoder()`'s `.iso8601` `JSONEncoder` strategy exactly (no
    /// fractional seconds) — what this file sends as `createdAt`/`since` in the request body.
    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Parses the server's own `syncedAt`. `Date.prototype.toISOString()` (what index.ts builds it
    /// from) always includes millisecond fractional seconds, which the plain `.withInternetDateTime`
    /// formatter above does NOT parse — so this tries a fractional-seconds-aware formatter first,
    /// then falls back to the plain one for robustness. See this file's header: the exact live
    /// wire value has never been observed.
    static func parseISO8601FromServer(_ string: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
