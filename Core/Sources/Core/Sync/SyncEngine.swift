// Core/Sources/Core/Sync/SyncEngine.swift
//
// docs/spec.md §11 (Architecture — outbox pattern, "app pulls on launch and via silent push") and
// §13 (Data Model).
//
// This is the skeleton described in this session's task: no real networking yet. SyncEngine does
// the local half of sync — queue durably, drain through whatever `SyncBackend` is configured, and
// give launch a `pullAndMerge()` hook — behind a `SyncBackend` protocol Session 7 (`feat/backend`,
// docs/spec.md §11/§13) implements for real against Supabase.

import Foundation
import SwiftData

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
    func push(_ events: [OutboxEvent]) async throws
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

    private var modelContainer: ModelContainer?
    private var context: ModelContext?
    private var backend: SyncBackend?
    private var isFlushing = false

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

            try await backend.push(batch)

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
    /// TODO(Session 7, `feat/backend`, docs/spec.md §11 + §13): there is no pull transport yet —
    /// this session's task defines `SyncBackend` with only `push(_:)`, and this method honors that
    /// exactly rather than inventing a pull API Session 7 didn't ask for. Session 7 is the right
    /// place to decide the pull/merge policy (docs/spec.md §13 has no `updated_at` column on most
    /// tables yet, so "last write wins" needs a real timestamp source first) and to add a matching
    /// `pull(since:)` requirement to `SyncBackend` — or a sibling protocol — at that point.
    ///
    /// Deliberately a silent no-op today, including when `configure` hasn't run: launch must never
    /// fail or block because sync isn't wired up yet (docs/spec.md §11 — "unlock must be instant
    /// and offline").
    public func pullAndMerge() async {
        // No-op skeleton — see TODO above.
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
