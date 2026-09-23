// Core/Sources/Core/Sync/SyncEngine.swift
//
// docs/spec.md §11 (Architecture — outbox pattern, "app pulls on launch and via silent push") and
// §13 (Data Model).
//
// SyncEngine does the local half of sync — queue durably, drain through whatever `SyncBackend` is
// configured, and give launch a `pullAndMerge()` hook — entirely behind the `SyncBackend` protocol
// below. It deliberately knows nothing about HTTP, Supabase, or auth: the real, networked
// conformance is `SupabaseSyncBackend` (`Core/Sources/Core/Sync/SupabaseSyncBackend.swift`), wired
// in via `configure(modelContainer:backend:)`/`setBackend(_:)` exactly as this file always
// documented. See that file for the wire contract against `backend/supabase/functions/sync/
// index.ts` and what's still unverified (no live Supabase project to test against yet).
//
// `SyncPullBackend` below is an additive, separate protocol — not a new requirement bolted onto
// `SyncBackend` itself — specifically so `SyncBackend`'s existing shape (and every conformer that
// only implements `push(_:)`, including `SyncTests.swift`'s `FakeSyncBackend`) stays untouched and
// compiling exactly as before. Only a backend that actually supports pulling (today, just
// `SupabaseSyncBackend`) conforms to it.

import Foundation
import SwiftData
import os

/// The network transport `SyncEngine` pushes queued `OutboxEvent`s through.
///
/// This is the exact shape called out in this session's task, so Session 7 can drop in a real
/// Supabase-backed implementation without touching `SyncEngine` itself: construct one, call
/// `SyncEngine.shared.configure(modelContainer:backend:)` (or `setBackend(_:)`) once at launch, and
/// pushes start flowing. Conforms to `Sendable` so it can be stored as actor state and passed into
/// `configure`/`setBackend` from any isolation domain.
public protocol SyncBackend: Sendable {
    /// Pushes a batch of not-yet-synced outbox events to the remote backend.
    ///
    /// Implementations should be all-or-nothing for `events`: either every event in the batch was
    /// durably accepted by the backend (so `SyncEngine` marks all of them `synced`), or this
    /// throws and none are marked synced, so the same batch is retried on the next `flush()`.
    func push(_ events: [OutboxEventSnapshot]) async throws
}

/// A `SyncBackend` that can also pull server-side changes — additive to `SyncBackend` itself (see
/// this file's header for why it's a separate protocol rather than a new requirement on
/// `SyncBackend`). `pullAndMerge()` below only pulls when the currently-configured `backend`
/// happens to also conform to this; a plain `SyncBackend` that only pushes (or none at all) makes
/// `pullAndMerge()` a silent no-op, same as before this existed.
public protocol SyncPullBackend: SyncBackend {
    /// Fetches server-side changes strictly after `since` (`nil` means "everything" — a device
    /// with no cursor yet). `SupabaseSyncBackend` serves this from the same Edge Function endpoint
    /// `push(_:)` posts to (docs: `backend/supabase/functions/sync/index.ts` answers both push and
    /// pull from one POST), called with an empty `events` array so this is a pull-only round trip.
    func pull(since: Date?) async throws -> SyncPullResult
}

/// One server-side "what changed since I last checked" result. Deliberately as generic as
/// `OutboxEvent` itself: `changes` holds each changed row's own JSON object, still-encoded as
/// `Data`, keyed by entity name — never decoded into `Goal`/`LockSession`/etc. here, so `Sync`
/// never needs to import every other module's model types (the same reasoning `OutboxEvent.swift`
/// documents for its own `payload: Data`). A future per-entity consumer (out of this file's scope —
/// docs/sessions/07-backend.md flags the pull/merge *policy* as its own open decision) decodes each
/// row with its own `Codable` shape, e.g. via `OutboxEvent.makeJSONDecoder()`.
public struct SyncPullResult: Sendable, Equatable {
    /// Echoes the server's response `syncedAt` — pass this back as `since` on the next pull. Also
    /// what `SyncEngine` persists as its own cursor after a successful `pullAndMerge()`.
    public let syncedAt: Date
    /// `changes["goal"]` (etc.) — one `Data` per changed row, each independently JSON-decodable.
    /// An entity name with no changes since `since` is simply absent, never an empty array.
    public let changes: [String: [Data]]
    /// Entity names where the server had more rows than it returned in this call (its own
    /// per-entity page cap — see `MAX_ROWS_PER_ENTITY_PULL` in the Edge Function). A consumer that
    /// needs completeness should treat this like "there's more — pull again," not "this is stale."
    public let truncated: Set<String>

    public init(syncedAt: Date, changes: [String: [Data]], truncated: Set<String>) {
        self.syncedAt = syncedAt
        self.changes = changes
        self.truncated = truncated
    }

    /// What a backend without real pull support effectively returns — `pullAndMerge()` never
    /// constructs this itself (a `SyncBackend` that isn't also `SyncPullBackend` is skipped
    /// entirely, see above), but it's a convenient, honest "nothing happened" value for tests/
    /// previews and for a `SyncPullBackend` conformer that has nothing new to report.
    public static let empty = SyncPullResult(syncedAt: .distantPast, changes: [:], truncated: [])
}

/// Errors `SyncEngine` throws itself, as opposed to errors bubbled up from a `SyncBackend`.
public enum SyncEngineError: Error, Sendable, Equatable {
    /// `configure(modelContainer:backend:)` hasn't been called yet, so there's no `ModelContext` to
    /// read or write outbox rows through. Every app/extension target must call it once at launch,
    /// pointed at the shared App Group container (docs/spec.md §11) — see `docs/PROGRESS.md`
    /// Session 1 ("Store") for where that container gets built.
    case notConfigured

    /// `configure` ran, but no `SyncBackend` has been supplied yet (expected before Session 7
    /// lands). `enqueue` still works with this — only `flush()` needs a backend.
    case backendUnavailable
}

/// Queues local changes durably (as `OutboxEvent` rows) and drains them to the backend when one is
/// configured.
///
/// Every app/extension target that writes state gets its own `SyncEngine.shared` in its own
/// process — actor singletons don't cross process boundaries, so each target must call
/// `configure(modelContainer:backend:)` once, early, pointed at the same App Group SwiftData store
/// (docs/spec.md §11: "SwiftData store + shared UserDefaults live here"). In practice only the
/// main app is expected to call `flush()`/`pullAndMerge()` — extensions do no networking
/// (`CLAUDE.md` "Architecture") but may still legitimately `enqueue` a change for the app to flush
/// later.
///
/// Declared as a plain `actor` — not built on SwiftData's `@ModelActor` macro — specifically so
/// `static let shared` can stay a trivial no-argument singleton, matching every other engine in
/// `Core` (`LockEngineManager`, `TimeBankEngine`, `StreakEngine`, ...). Sync doesn't own the shared
/// `ModelContainer` (Session 1's Store module does), so it can't build one inside its own `init`
/// the way `@ModelActor`'s generated initializer would require; `configure(modelContainer:)` is
/// the seam instead. See this session's `knownIssues` for the tradeoffs of that choice.
public actor SyncEngine {
    public static let shared = SyncEngine()

    /// How many outbox rows one `push` call handles at a time, so a device that's been offline for
    /// a long time doesn't try to push its entire backlog in a single request.
    private static let batchSize = 200

    /// App Group `UserDefaults` key `pullAndMerge()` persists its cursor under. Deliberately its
    /// own key rather than a new case on `Store/SharedDefaults.swift` (out of this file's scope,
    /// and that enum's own doc comment scopes it to state a Shield/Widget extension mirrors for
    /// instant rendering — a sync cursor is neither) — written straight to the same App Group
    /// suite (`AppGroup.identifier`, `Store/ModelContainer+AppGroup.swift`) via a private
    /// `UserDefaults` handle below, namespaced `sync.*` so it can never collide with
    /// `SharedDefaults`'s own `shared.*` keys.
    private static let lastPulledAtDefaultsKey = "sync.lastPulledAt"

    private var modelContainer: ModelContainer?
    private var context: ModelContext?
    private var backend: SyncBackend?
    private var isFlushing = false

    /// This process's App Group `UserDefaults` handle, purely for persisting the pull cursor below
    /// — separate from `context`/`modelContainer` since the cursor isn't a SwiftData row and needs
    /// to survive even before `configure(modelContainer:)` has ever run. Falls back to `.standard`
    /// when the App Group entitlement is missing (e.g. a unit-test host), matching
    /// `SharedDefaults`'s own documented fallback — per-process only in that case, never actually
    /// shared, but `pullAndMerge()` degrades to "always pulls everything since the beginning" in
    /// that situation rather than crashing, which is the correct failure mode for something this
    /// non-critical.
    private let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    /// In-memory cache of the last successful pull's cursor, so a `pullAndMerge()` later in the
    /// same process doesn't need to round-trip through `UserDefaults` first. Seeded from
    /// `UserDefaults` lazily, the first time `pullAndMerge()` actually runs (not in `init()`,
    /// which — like every other engine in `Core`, see this file's own header — has to stay a
    /// trivial no-argument singleton initializer).
    private var lastPulledAt: Date?
    /// `true` once `lastPulledAt` has been seeded from `UserDefaults` at least once this process,
    /// distinguishing "no cursor yet" (`nil`, seeded) from "haven't checked `UserDefaults` yet".
    private var hasLoadedPulledAtFromDefaults = false

    /// The most recent successful `pullAndMerge()` result, for a caller (a future per-entity merge
    /// consumer, or a debug screen) to inspect — see ``latestPullResult()``. `nil` until the first
    /// successful pull this process.
    private var pulledChanges: SyncPullResult?

    private let pullLogger = Logger(subsystem: "com.zano.app.Core", category: "SyncEngine")

    private init() {}

    // MARK: - Configuration

    /// Points this `SyncEngine` at the shared App Group `ModelContainer` and (optionally) a real
    /// backend. Call once, as early as possible during app/extension launch — before anything else
    /// calls `enqueue`, since that throws `.notConfigured` until this runs.
    ///
    /// Safe to call again later purely to swap in a real `SyncBackend` once Session 7 lands
    /// (passing the same container) — re-running just opens a fresh `ModelContext` and replaces
    /// whatever was stored before.
    public func configure(modelContainer: ModelContainer, backend: SyncBackend? = nil) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.backend = backend
    }

    /// Swaps in a `SyncBackend` without touching the `ModelContainer` — the seam Session 7 uses to
    /// go from "no networking" to "real Supabase client" without any other call site changing.
    public func setBackend(_ backend: SyncBackend) {
        self.backend = backend
    }

    // MARK: - Enqueue

    /// Builds an `OutboxEvent` for `payload` and persists it into the outbox immediately. Durable
    /// as soon as this returns — a crash or force-quit right after can only ever lose work that
    /// hadn't reached this call yet, never work that had.
    ///
    /// This — not a raw `OutboxEvent`-taking overload — is the entry point the rest of `Core`
    /// should call. `OutboxEvent` is a mutable SwiftData `@Model` class and therefore not
    /// `Sendable`; building it here, entirely inside this actor's isolation domain, from a
    /// `Sendable` `Payload` is what keeps every call site of this method valid under Swift 6
    /// strict concurrency regardless of which actor/thread it's called from.
    ///
    /// - Parameters:
    ///   - entityName: One of the tables in docs/spec.md §13, e.g. `"Goal"`, `"LockSession"`.
    ///   - entityID: The primary key of the row that changed.
    ///   - payload: The entity's current `Codable` shape. JSON-encoded right here — see
    ///     `OutboxEvent.makeJSONEncoder()`.
    ///   - createdAt: When the change happened; defaults to now. Also the flush ordering key.
    /// - Returns: the new outbox row's `id`, mainly useful for logging/debugging.
    @discardableResult
    public func enqueue<Payload: Encodable & Sendable>(
        entityName: String,
        entityID: UUID,
        payload: Payload,
        createdAt: Date = .now
    ) async throws -> UUID {
        guard let context else { throw SyncEngineError.notConfigured }
        let event = try OutboxEvent(
            entityName: entityName,
            entityID: entityID,
            payload: payload,
            createdAt: createdAt
        )
        context.insert(event)
        try context.save()
        return event.id
    }

    // MARK: - Flush (push)

    /// Drains every not-yet-synced `OutboxEvent`, oldest first, through the configured
    /// `SyncBackend`, in batches of `batchSize`. Marks a batch `synced` only after `push` returns
    /// successfully for it, so a push failure partway through leaves the remaining rows queued for
    /// the next `flush()` rather than losing or duplicating them.
    ///
    /// A no-op (returns `0`, throws nothing) if a flush is already in flight — callers such as a
    /// periodic background task and a "network became reachable" observer firing at the same
    /// moment don't need to coordinate with each other.
    ///
    /// - Returns: how many events were successfully pushed in this call.
    /// - Throws: `SyncEngineError.notConfigured` / `.backendUnavailable`, or whatever the
    ///   `SyncBackend` throws from `push(_:)` (network, auth, server errors, ...) — always after
    ///   any earlier batches in this same call already succeeded and were marked synced.
    @discardableResult
    public func flush() async throws -> Int {
        guard let context else { throw SyncEngineError.notConfigured }
        guard let backend else { throw SyncEngineError.backendUnavailable }
        guard !isFlushing else { return 0 }

        isFlushing = true
        defer { isFlushing = false }

        var totalPushed = 0
        while true {
            var descriptor = FetchDescriptor<OutboxEvent>(
                predicate: #Predicate { $0.synced == false },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            descriptor.fetchLimit = Self.batchSize

            let batch = try context.fetch(descriptor)
            guard !batch.isEmpty else { break }

            try await backend.push(batch.map(OutboxEventSnapshot.init))

            for event in batch {
                event.synced = true
            }
            try context.save()

            totalPushed += batch.count
            if batch.count < Self.batchSize { break }
        }
        return totalPushed
    }

    // MARK: - Pull (launch)

    /// Called once at app launch (docs/spec.md §11: "app pulls on launch and via silent push") to
    /// bring down anything another device changed while this one was offline.
    ///
    /// Pulls for real when the configured `backend` conforms to ``SyncPullBackend`` (today, that's
    /// `SupabaseSyncBackend`); otherwise a silent no-op, exactly as before this existed. On
    /// success, advances the persisted cursor (`lastPulledAt`) and stashes the result for
    /// ``latestPullResult()`` — it does **not** write anything into `Goal`/`LockSession`/etc.'s own
    /// SwiftData rows itself. Turning the raw per-entity JSON in ``SyncPullResult/changes`` into
    /// actual local writes is a deliberately separate, still-open decision (docs/sessions/
    /// 07-backend.md: "Session 7 is the right place to decide the pull/merge policy" — docs/
    /// spec.md §13 has no `updated_at` column on most tables yet, so "last write wins" needs a
    /// real timestamp source first) that belongs to whichever module owns each entity, not to
    /// `Sync` itself (see `OutboxEvent.swift`'s header for why this module stays generic rather
    /// than importing every model type).
    ///
    /// Deliberately never throws, including when `configure` hasn't run or the pull itself fails:
    /// launch must never fail or block because sync isn't wired up yet, or the network hiccuped
    /// (docs/spec.md §11 — "unlock must be instant and offline"). A failed pull just leaves
    /// `lastPulledAt` wherever it was, so the same (or overlapping) window is requested again next
    /// time this runs — never advances the cursor past data it didn't actually receive.
    public func pullAndMerge() async {
        guard let backend, let pullBackend = backend as? SyncPullBackend else { return }

        if !hasLoadedPulledAtFromDefaults {
            lastPulledAt = defaults.object(forKey: Self.lastPulledAtDefaultsKey) as? Date
            hasLoadedPulledAtFromDefaults = true
        }

        do {
            let result = try await pullBackend.pull(since: lastPulledAt)
            lastPulledAt = result.syncedAt
            defaults.set(result.syncedAt, forKey: Self.lastPulledAtDefaultsKey)
            pulledChanges = result
        } catch {
            pullLogger.error(
                "pullAndMerge: pull(since:) failed, cursor left unadvanced: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// The most recent successful ``pullAndMerge()`` result this process, for a future per-entity
    /// merge consumer (or a debug/diagnostics screen) to inspect. `nil` until the first successful
    /// pull, or forever on a backend that isn't ``SyncPullBackend``.
    public func latestPullResult() -> SyncPullResult? {
        pulledChanges
    }

    // MARK: - Housekeeping

    /// Deletes already-synced rows older than `date`, so the outbox table doesn't grow without
    /// bound. Never touches unsynced rows, regardless of age.
    public func pruneSyncedEvents(olderThan date: Date) async throws {
        guard let context else { throw SyncEngineError.notConfigured }
        let descriptor = FetchDescriptor<OutboxEvent>(
            predicate: #Predicate { $0.synced == true && $0.createdAt < date }
        )
        for event in try context.fetch(descriptor) {
            context.delete(event)
        }
        try context.save()
    }

    // MARK: - Introspection

    /// How many outbox rows are still waiting to be pushed. Handy for a Settings/debug "N changes
    /// pending sync" indicator without exposing the underlying `ModelContext`.
    public func pendingCount() async throws -> Int {
        guard let context else { throw SyncEngineError.notConfigured }
        let descriptor = FetchDescriptor<OutboxEvent>(
            predicate: #Predicate { $0.synced == false }
        )
        return try context.fetchCount(descriptor)
    }
}
