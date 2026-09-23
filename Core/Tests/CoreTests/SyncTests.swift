// SyncTests.swift
// Core / Tests / CoreTests
//
// Coverage for Core/Sources/Core/Sync/*.swift (docs/spec.md §11 "Sync outbox pushes to Supabase
// when online", §13 Data Model): `OutboxEvent` enqueue/flush state transitions through
// `SyncEngine`.
//
// `SyncEngine.shared` is a process-wide singleton actor with a private `init()` (see
// SyncEngine.swift) — there's no way to construct a second, test-local instance. Every test below
// therefore starts by calling `configure(modelContainer:backend:)` with its own fresh in-memory
// `ModelContainer`; `configure` fully replaces the actor's stored `context`/`backend`, so each test
// gets an effectively isolated outbox table even though they all share the one actor. The suite is
// `.serialized` so `configure` calls from different tests can never interleave with each other's
// `enqueue`/`flush` calls.
//
// Deliberately NOT covered: `SyncEngineError.notConfigured`. That only happens before the very
// first `configure()` call this process ever makes, and Swift Testing doesn't guarantee test
// execution order (not even within a `.serialized` suite) — asserting on "before anything else in
// this process touched the singleton" would be flaky by construction rather than a real test.
// Flagged in this task's knownIssues.

import Testing
import SwiftData
import Foundation
@testable import Core

/// A `Sendable`, `Encodable` stand-in for a real entity snapshot (e.g. what `Goal`'s own payload
/// would look like) — `OutboxEvent.payload` is opaque JSON, so any `Encodable & Sendable` value
/// exercises `enqueue` the same way.
private struct FakePayload: Codable, Sendable, Equatable {
    var value: Int
}

/// An error type distinct from anything `SyncEngine` itself throws, so tests can tell "the backend's
/// own failure propagated" apart from "`SyncEngine` threw one of its own `SyncEngineError`s".
private struct FakeBackendError: Error, Sendable, Equatable {
    var message: String
}

/// Records every batch it's asked to push and can be scripted to fail specific calls — the
/// `SyncBackend` double these tests configure `SyncEngine.shared` with.
///
/// Declared as an `actor` (rather than a `final class` with manual locking) so it can safely be
/// mutated from inside `push(_:)`, which `SyncEngine` calls while itself actor-isolated —
/// `SyncBackend: Sendable` requires the conforming type to be safe to hand across that boundary,
/// and an actor satisfies that automatically.
private actor FakeSyncBackend: SyncBackend {
    /// Explicitly `Sendable` (rather than relying on implicit inference) since values of this type
    /// cross into the actor through `script(_:)`'s parameter from outside its isolation domain.
    enum Outcome: Sendable {
        case succeed
        case fail(FakeBackendError)
    }

    private(set) var pushCallCount = 0
    private(set) var pushedEventIDs: [[UUID]] = []

    private var scriptedOutcomes: [Outcome] = []
    private let defaultOutcome: Outcome
    private var gate: (@Sendable () async -> Void)?

    init(defaultOutcome: Outcome = .succeed) {
        self.defaultOutcome = defaultOutcome
    }

    /// Queues outcomes consumed one-per-call, in order; once exhausted, `defaultOutcome` applies to
    /// every subsequent call.
    func script(_ outcomes: [Outcome]) {
        scriptedOutcomes.append(contentsOf: outcomes)
    }

    /// Installs a one-shot gate `push` awaits before returning, so a test can hold a call "in
    /// flight" — used by the reentrancy test to guarantee a second `flush()` observes the first
    /// one still running.
    func holdNextPush(untilSignaledBy gate: @escaping @Sendable () async -> Void) {
        self.gate = gate
    }

    func push(_ events: [OutboxEventSnapshot]) async throws {
        pushCallCount += 1
        pushedEventIDs.append(events.map(\.id))

        if let gate {
            self.gate = nil
            await gate()
        }

        let outcome = scriptedOutcomes.isEmpty ? defaultOutcome : scriptedOutcomes.removeFirst()
        switch outcome {
        case .succeed:
            return
        case .fail(let error):
            throw error
        }
    }
}

/// A tiny reusable async gate: `wait()` suspends until `open()` is called (once), from any task.
/// Used to sequence the two concurrent `flush()` calls in the reentrancy test without adding any
/// test-only introspection hooks to `SyncEngine` itself.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for continuation in pending {
            continuation.resume()
        }
    }
}

@Suite("SyncEngine — OutboxEvent enqueue/flush state transitions", .serialized)
struct SyncTests {

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: ModelContainer.appGroupSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: ModelContainer.appGroupSchema, configurations: [configuration])
    }

    /// Fetches an `OutboxEvent` by id through a *fresh* `ModelContext` against `container`,
    /// independent of whatever context `SyncEngine` built internally in `configure` — confirms
    /// state actually persisted to the shared store, not just to `SyncEngine`'s own objects.
    private func fetchEvent(id: UUID, in container: ModelContainer) throws -> OutboxEvent? {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<OutboxEvent>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Enqueue

    @Test func enqueuePersistsAnUnsyncedOutboxEventWithItsJSONPayload() async throws {
        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        let entityID = UUID()
        let payload = FakePayload(value: 42)
        let eventID = try await SyncEngine.shared.enqueue(
            entityName: "Goal",
            entityID: entityID,
            payload: payload
        )

        let pending = try await SyncEngine.shared.pendingCount()
        #expect(pending == 1)

        let stored = try #require(try fetchEvent(id: eventID, in: container))
        #expect(stored.entityName == "Goal")
        #expect(stored.entityID == entityID)
        #expect(stored.synced == false)

        let decoded = try OutboxEvent.makeJSONDecoder().decode(FakePayload.self, from: stored.payload)
        #expect(decoded == payload)
    }

    @Test func enqueueAssignsADistinctIDToEachCallEvenForTheSameEntity() async throws {
        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        let entityID = UUID()
        let firstEventID = try await SyncEngine.shared.enqueue(
            entityName: "TimeBank", entityID: entityID, payload: FakePayload(value: 1)
        )
        let secondEventID = try await SyncEngine.shared.enqueue(
            entityName: "TimeBank", entityID: entityID, payload: FakePayload(value: 2)
        )

        #expect(firstEventID != secondEventID)
        // Not `pendingCount() == 2`: SyncEngine.shared is process-wide, and other suites' managers
        // (DuelManager, NudgeSender, ...) enqueue into whichever container is configured at that
        // moment, so a global count is racy under parallel suites. Check our two events are present.
        let storedIDs = Set(try ModelContext(container).fetch(FetchDescriptor<OutboxEvent>()).map(\.id))
        #expect(storedIDs.isSuperset(of: [firstEventID, secondEventID]))
    }

    // MARK: - Flush: success path

    @Test func flushPushesOldestFirstAndMarksEveryPushedEventSynced() async throws {
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        // Enqueued newer-first, on purpose, so a passing test actually proves flush() sorts by
        // `createdAt` rather than happening to match insertion order.
        let newerID = try await SyncEngine.shared.enqueue(
            entityName: "Goal", entityID: UUID(), payload: FakePayload(value: 2), createdAt: newer
        )
        let olderID = try await SyncEngine.shared.enqueue(
            entityName: "Goal", entityID: UUID(), payload: FakePayload(value: 1), createdAt: older
        )

        let pushedCount = try await SyncEngine.shared.flush()
        #expect(pushedCount == 2)

        let pushedIDs = await backend.pushedEventIDs
        #expect(pushedIDs == [[olderID, newerID]])

        #expect(try await SyncEngine.shared.pendingCount() == 0)
        #expect(try #require(try fetchEvent(id: olderID, in: container)).synced)
        #expect(try #require(try fetchEvent(id: newerID, in: container)).synced)
    }

    @Test func flushWithNothingPendingIsANoOpThatReturnsZero() async throws {
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        let pushedCount = try await SyncEngine.shared.flush()
        #expect(pushedCount == 0)
        #expect(await backend.pushCallCount == 0)
    }

    @Test func flushDrainsMultipleBatchesWhenPendingCountExceedsTheBatchSize() async throws {
        // `SyncEngine`'s batch size is `private static let batchSize = 200`
        // (Core/Sources/Core/Sync/SyncEngine.swift) — not visible even via @testable, so this
        // hardcodes the known value read from source rather than referencing it directly. Enqueuing
        // 205 events should therefore produce exactly two `push` calls (200, then 5).
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        let total = 205
        for i in 0..<total {
            _ = try await SyncEngine.shared.enqueue(
                entityName: "Nudge",
                entityID: UUID(),
                payload: FakePayload(value: i),
                createdAt: Date(timeIntervalSince1970: Double(i))
            )
        }
        #expect(try await SyncEngine.shared.pendingCount() == total)

        let pushedCount = try await SyncEngine.shared.flush()
        #expect(pushedCount == total)
        #expect(await backend.pushCallCount == 2)

        let batches = await backend.pushedEventIDs
        #expect(batches.map(\.count) == [200, 5])
        #expect(try await SyncEngine.shared.pendingCount() == 0)
    }

    // MARK: - Flush: failure / retry path

    @Test func flushThrowsBackendUnavailableAndLeavesTheEventUnsyncedWhenNoBackendIsConfigured() async throws {
        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        let eventID = try await SyncEngine.shared.enqueue(
            entityName: "LockSession", entityID: UUID(), payload: FakePayload(value: 7)
        )

        do {
            _ = try await SyncEngine.shared.flush()
            Issue.record("Expected flush() to throw SyncEngineError.backendUnavailable")
        } catch let error as SyncEngineError {
            #expect(error == .backendUnavailable)
        } catch {
            Issue.record("Expected SyncEngineError.backendUnavailable, got \(error)")
        }

        let stored = try #require(try fetchEvent(id: eventID, in: container))
        #expect(stored.synced == false)
    }

    @Test func flushLeavesTheBatchUnsyncedWhenTheBackendThrowsAndRetriesItOnTheNextFlush() async throws {
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        await backend.script([.fail(FakeBackendError(message: "network down"))])
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        let eventID = try await SyncEngine.shared.enqueue(
            entityName: "Meal", entityID: UUID(), payload: FakePayload(value: 3)
        )

        do {
            _ = try await SyncEngine.shared.flush()
            Issue.record("Expected flush() to rethrow the backend's error")
        } catch is FakeBackendError {
            // Expected — SyncEngine rethrows whatever the backend throws, per its doc comment.
        } catch {
            Issue.record("Expected FakeBackendError, got \(error)")
        }

        // Per `SyncBackend.push`'s contract, a thrown batch marks nothing synced; the row must
        // still be there, still unsynced, ready to retry.
        let afterFailure = try #require(try fetchEvent(id: eventID, in: container))
        #expect(afterFailure.synced == false)
        #expect(try await SyncEngine.shared.pendingCount() == 1)

        // The scripted failure was consumed; the backend now defaults to succeeding, so the exact
        // same row is retried (not skipped, not duplicated) on the next flush.
        let pushedCount = try await SyncEngine.shared.flush()
        #expect(pushedCount == 1)
        #expect(await backend.pushedEventIDs == [[eventID], [eventID]])

        let afterRetry = try #require(try fetchEvent(id: eventID, in: container))
        #expect(afterRetry.synced == true)
        #expect(try await SyncEngine.shared.pendingCount() == 0)
    }

    @Test func flushOnlyMarksThePriorBatchSyncedWhenALaterBatchFails() async throws {
        // Two full batches (batchSize == 200): the first succeeds, the second fails. flush() must
        // leave the first batch's events marked synced (it already committed) while the second
        // batch's events stay unsynced for the next retry — never lose or duplicate either half.
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        await backend.script([.succeed, .fail(FakeBackendError(message: "second batch rejected"))])
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        var eventIDs: [UUID] = []
        for i in 0..<205 {
            let id = try await SyncEngine.shared.enqueue(
                entityName: "Badge",
                entityID: UUID(),
                payload: FakePayload(value: i),
                createdAt: Date(timeIntervalSince1970: Double(i))
            )
            eventIDs.append(id)
        }

        do {
            _ = try await SyncEngine.shared.flush()
            Issue.record("Expected flush() to rethrow the second batch's error")
        } catch is FakeBackendError {
            // Expected.
        } catch {
            Issue.record("Expected FakeBackendError, got \(error)")
        }

        let firstBatchIDs = eventIDs.prefix(200)
        let secondBatchIDs = eventIDs.suffix(5)

        for id in firstBatchIDs {
            #expect(try #require(try fetchEvent(id: id, in: container)).synced)
        }
        for id in secondBatchIDs {
            #expect(try #require(try fetchEvent(id: id, in: container)).synced == false)
        }
        #expect(try await SyncEngine.shared.pendingCount() == 5)
    }

    // MARK: - Flush: reentrancy guard

    @Test func aFlushAlreadyInFlightMakesAConcurrentFlushCallANoOpThatReturnsZero() async throws {
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        let gate = AsyncGate()
        await backend.holdNextPush { await gate.wait() }
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        _ = try await SyncEngine.shared.enqueue(
            entityName: "Squad", entityID: UUID(), payload: FakePayload(value: 1)
        )

        async let firstFlush = SyncEngine.shared.flush()

        // There's no observable "isFlushing" signal exposed to tests; a short delay is the
        // least-invasive way to let the first flush() reach (and suspend on) the gate before the
        // second call fires, without adding test-only API surface to SyncEngine itself. This makes
        // the test timing-sensitive in principle — flagged in knownIssues.
        try await Task.sleep(nanoseconds: 50_000_000)

        let secondFlushResult = try await SyncEngine.shared.flush()
        #expect(secondFlushResult == 0)

        await gate.open()
        let firstFlushResult = try await firstFlush
        #expect(firstFlushResult == 1)
        #expect(try await SyncEngine.shared.pendingCount() == 0)
    }

    // MARK: - pruneSyncedEvents

    @Test func pruneSyncedEventsDeletesOnlySyncedRowsOlderThanTheGivenDate() async throws {
        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        // Built directly against the container (bypassing `enqueue`) so this test exercises exactly
        // `pruneSyncedEvents`'s own predicate — `synced == true && createdAt < date` — independent
        // of how rows came to be synced.
        let context = ModelContext(container)
        let oldSynced = OutboxEvent(
            entityName: "Badge", entityID: UUID(), payload: Data("{}".utf8),
            createdAt: Date(timeIntervalSince1970: 1_000), synced: true
        )
        let newSynced = OutboxEvent(
            entityName: "Badge", entityID: UUID(), payload: Data("{}".utf8),
            createdAt: Date(timeIntervalSince1970: 20_000), synced: true
        )
        let oldUnsynced = OutboxEvent(
            entityName: "Badge", entityID: UUID(), payload: Data("{}".utf8),
            createdAt: Date(timeIntervalSince1970: 500), synced: false
        )
        context.insert(oldSynced)
        context.insert(newSynced)
        context.insert(oldUnsynced)
        try context.save()

        let cutoff = Date(timeIntervalSince1970: 10_000)
        try await SyncEngine.shared.pruneSyncedEvents(olderThan: cutoff)

        #expect(try fetchEvent(id: oldSynced.id, in: container) == nil)
        #expect(try fetchEvent(id: newSynced.id, in: container) != nil)
        // Never touches unsynced rows, regardless of age — per the method's own doc comment.
        #expect(try fetchEvent(id: oldUnsynced.id, in: container) != nil)
    }

    // MARK: - setBackend

    @Test func setBackendSwapsTheBackendWithoutDisturbingAlreadyQueuedEvents() async throws {
        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        let eventID = try await SyncEngine.shared.enqueue(
            entityName: "RiskScore", entityID: UUID(), payload: FakePayload(value: 9)
        )

        // No backend yet — flush() must fail without touching the queued row.
        await #expect(throws: SyncEngineError.self) {
            try await SyncEngine.shared.flush()
        }
        #expect(try #require(try fetchEvent(id: eventID, in: container)).synced == false)

        // Swapping in a backend (the seam a real Supabase-backed implementation uses) lets the
        // exact same previously-queued row flush successfully.
        let backend = FakeSyncBackend()
        await SyncEngine.shared.setBackend(backend)
        let pushedCount = try await SyncEngine.shared.flush()
        #expect(pushedCount == 1)
        #expect(await backend.pushedEventIDs == [[eventID]])
        #expect(try #require(try fetchEvent(id: eventID, in: container)).synced == true)
    }

    // MARK: - OutboxEvent: JSON payload shape, independent of SyncEngine

    @Test func outboxEventConvenienceInitRoundTripsADateFieldAsISO8601() throws {
        // `OutboxEvent.makeJSONEncoder()`/`makeJSONDecoder()`'s whole reason to exist (per their doc
        // comments) is so a payload encoded today decodes the same way a year from now regardless of
        // locale — this exercises that directly against the throwing convenience initializer, one
        // level below `SyncEngine.enqueue`, with a payload shape that actually has a `Date` in it
        // (unlike `FakePayload`, which is int-only and so can't catch a date-strategy regression).
        struct TimestampedPayload: Codable, Sendable, Equatable {
            var occurredAt: Date
            var note: String
        }

        let payload = TimestampedPayload(occurredAt: Date(timeIntervalSince1970: 1_700_000_000), note: "gym check-in")
        let event = try OutboxEvent(entityName: "GoalEvent", entityID: UUID(), payload: payload)

        let decoded = try OutboxEvent.makeJSONDecoder().decode(TimestampedPayload.self, from: event.payload)
        #expect(decoded == payload)
        #expect(event.synced == false)
    }

    // MARK: - Enqueue: payload encoding failure

    @Test func enqueueRethrowsTheEncodingErrorAndPersistsNoRowWhenThePayloadCannotBeEncoded() async throws {
        // `JSONEncoder` throws `EncodingError.invalidValue` for a non-finite `Double` (`.infinity`/
        // `.nan`) by default — a real way a caller could hand `enqueue` a payload that fails to
        // encode (e.g. a corrupted sensor reading), distinct from every other test in this suite,
        // which only ever exercises payloads that encode cleanly. `enqueue` must propagate that
        // failure rather than silently writing a partially-broken row.
        struct BadPayload: Codable, Sendable {
            var ratio: Double
        }

        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        await #expect(throws: (any Error).self) {
            _ = try await SyncEngine.shared.enqueue(
                entityName: "Goal",
                entityID: UUID(),
                payload: BadPayload(ratio: .infinity)
            )
        }
        #expect(try await SyncEngine.shared.pendingCount() == 0)
    }

    // MARK: - Flush: idempotent once fully drained

    @Test func flushCalledAgainAfterEverythingIsAlreadySyncedPushesNothingFurther() async throws {
        // Distinct from `flushWithNothingPendingIsANoOpThatReturnsZero` above, which covers a queue
        // that was *never* populated — this covers the more realistic steady state of a queue that
        // was populated, fully drained by an earlier `flush()`, and then asked to flush again (e.g.
        // a periodic background task firing on its normal cadence with nothing new to send).
        let container = try makeContainer()
        let backend = FakeSyncBackend()
        await SyncEngine.shared.configure(modelContainer: container, backend: backend)

        _ = try await SyncEngine.shared.enqueue(
            entityName: "Streak", entityID: UUID(), payload: FakePayload(value: 5)
        )
        let firstPush = try await SyncEngine.shared.flush()
        #expect(firstPush == 1)
        #expect(await backend.pushCallCount == 1)

        let secondPush = try await SyncEngine.shared.flush()
        #expect(secondPush == 0)
        // No new `push` call at all — the already-synced row must not be re-fetched into a batch.
        #expect(await backend.pushCallCount == 1)
    }

    // MARK: - pendingCount: mixed entity names share one outbox

    @Test func pendingCountSumsAcrossEveryEntityNameNotJustOneTable() async throws {
        // Per `OutboxEvent`'s own doc comment, the outbox is deliberately entity-agnostic so "every
        // table in docs/spec.md §13 can flow through the same pipe" — this confirms `pendingCount`
        // (and, by extension, `flush`'s single unsorted-by-entity fetch) actually treats a mix of
        // entity names as one queue rather than needing to be called per entity type.
        let container = try makeContainer()
        await SyncEngine.shared.configure(modelContainer: container, backend: nil)

        _ = try await SyncEngine.shared.enqueue(entityName: "Goal", entityID: UUID(), payload: FakePayload(value: 1))
        _ = try await SyncEngine.shared.enqueue(entityName: "Meal", entityID: UUID(), payload: FakePayload(value: 2))
        _ = try await SyncEngine.shared.enqueue(entityName: "Duel", entityID: UUID(), payload: FakePayload(value: 3))

        #expect(try await SyncEngine.shared.pendingCount() == 3)
    }
}
