// Core/Sources/Core/Sync/OutboxEvent.swift
//
// docs/spec.md §11 (Architecture — "Sync outbox pushes to Supabase when online") and §13
// (Data Model — every table listed there is a potential `entityName`).
//
// This file owns the *local* half of the outbox pattern only: a durable record of "this changed
// and still needs to reach the backend." Nothing here talks to the network — see SyncEngine.swift
// for the actor that drains these rows through a `SyncBackend`.

import Foundation
import SwiftData

/// A pending local change waiting to be pushed to the backend.
///
/// One `OutboxEvent` is written every time a user action changes something that also needs to
/// exist on the server (a goal, a lock session, a streak update, ...). The event itself doesn't
/// interpret `payload` — that's up to whichever `SyncBackend` eventually pushes it, keyed by
/// `entityName`. Keeping this generic (a name + a UUID + opaque JSON) means the outbox never needs
/// to import every other module's model types, and every table in docs/spec.md §13 can flow
/// through the same pipe.
///
/// Lives in the same App Group SwiftData store as the entities it describes (docs/spec.md §11),
/// so a change recorded by an extension (e.g. `ZANOShieldAction` logging an emergency unlock) is
/// still here the next time the main app launches and calls `SyncEngine.flush()`.
@Model
public final class OutboxEvent {
    /// Stable local identity for this outbox row. Distinct from `entityID` — a single entity can
    /// produce many outbox events (one per change) over its lifetime.
    @Attribute(.unique)
    public var id: UUID

    /// The entity this event describes, e.g. `"Goal"`, `"LockSession"`, `"TimeBank"` — one of the
    /// tables in docs/spec.md §13. A plain string rather than an enum on purpose: this model must
    /// stay importable from every module without depending on all of their types, and
    /// `SyncBackend` implementations are what actually switch on it.
    public var entityName: String

    /// The primary key of the affected row in its own table.
    public var entityID: UUID

    /// The entity's own `Codable` shape at the moment it changed, JSON-encoded by the caller (see
    /// the convenience initializer below) before this row is ever created. `SyncEngine` never
    /// decodes this — it only ever moves bytes to `SyncBackend`.
    public var payload: Data

    /// When this change was queued locally. Also the flush ordering key, so events for the same
    /// (or different) entities are always pushed oldest-first.
    public var createdAt: Date

    /// `true` once `SyncBackend.push` has durably accepted this event. Only ever flips
    /// false → true; a failed push retries the same row rather than resetting it.
    public var synced: Bool

    public init(
        id: UUID = UUID(),
        entityName: String,
        entityID: UUID,
        payload: Data,
        createdAt: Date = .now,
        synced: Bool = false
    ) {
        self.id = id
        self.entityName = entityName
        self.entityID = entityID
        self.payload = payload
        self.createdAt = createdAt
        self.synced = synced
    }
}

extension OutboxEvent {
    /// Convenience for the common case: JSON-encode `payload` right here instead of making every
    /// call site carry its own `JSONEncoder`. Used by `SyncEngine.enqueue(entityName:entityID:
    /// payload:createdAt:)`, which is the entry point most of `Core` should actually call.
    ///
    /// `Payload` is constrained to `Sendable` (in addition to `Encodable`) because this initializer
    /// exists to be called from `SyncEngine`'s actor-isolated `enqueue` — the value crossing into
    /// that call has to be safe to hand across an isolation boundary even though the resulting
    /// `OutboxEvent` itself (a mutable SwiftData model) does not need to be, since it's built and
    /// used entirely inside that one actor.
    ///
    /// - Throws: whatever `JSONEncoder` throws for a value that isn't cleanly encodable to JSON.
    public convenience init<Payload: Encodable & Sendable>(
        id: UUID = UUID(),
        entityName: String,
        entityID: UUID,
        payload: Payload,
        createdAt: Date = .now,
        synced: Bool = false
    ) throws {
        let data = try OutboxEvent.makeJSONEncoder().encode(payload)
        self.init(
            id: id,
            entityName: entityName,
            entityID: entityID,
            payload: data,
            createdAt: createdAt,
            synced: synced
        )
    }

    /// A fresh, consistently-configured encoder for outbox payloads (ISO-8601 dates, so a payload
    /// encoded today decodes the same way a year from now regardless of locale). Returns a new
    /// instance every call rather than a shared `static let` — `JSONEncoder`'s own Sendability is
    /// one of the several API surfaces this session can't verify against a real SDK (see
    /// knownIssues), so this sidesteps the question instead of asserting an answer.
    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decoder counterpart to `makeJSONEncoder()`, for callers that decode `payload` back out
    /// (a `SyncBackend` building its wire format, or a future pull-and-merge step).
    public static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
