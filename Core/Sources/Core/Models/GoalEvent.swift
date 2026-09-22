// GoalEvent.swift
// Core / Models
//
// Mirrors the `goal_events` table in backend/supabase/migrations/0001_init.sql field-for-field, per
// docs/spec.md §13 (Data Model). This is "the training table for §9 ML systems" — every log,
// verification, completion, miss, Plan B, and freeze gets a row here. `AdaptiveGoalEngine.
// adjustDifficulty(for:last28Days:)` reads arrays of these directly (see system contracts).

import Foundation
import SwiftData

/// Matches the `goal_events.kind` check constraint exactly
/// (`'log' | 'verify' | 'complete' | 'miss' | 'plan_b' | 'freeze'`).
public enum GoalEventKind: String, Codable, CaseIterable, Sendable {
    /// A raw data point (e.g. an NFC tap, a widget button press) before verification.
    case log
    /// An automatic or one-tap verification fired (Tier A/B).
    case verify
    /// The goal was fully completed for the day.
    case complete
    /// The goal was missed for the day (streak logic reads this — docs/spec.md §8).
    case miss
    /// The easier Plan B target was completed instead of the full goal.
    case planB = "plan_b"
    /// A streak freeze was spent to cover this day instead of a completion.
    case freeze
}

/// Matches the `goal_events.source` check constraint exactly (`'nfc' | 'widget' | 'photo' |
/// 'barcode' | 'geofence' | 'healthkit' | 'timer' | 'manual' | 'siri'`).
public enum GoalEventSource: String, Codable, CaseIterable, Sendable {
    case nfc
    case widget
    case photo
    case barcode
    case geofence
    case healthKit = "healthkit"
    case timer
    case manual
    case siri
}

/// A minimal, self-contained representation of an arbitrary JSON value, used only to give
/// `GoalEvent.meta` (mirroring the Postgres `jsonb` column `goal_events.meta`) a structured,
/// Codable shape without assuming a fixed schema up front — different goal types attach different
/// metadata (e.g. an NFC tag id, a barcode, a photo confidence score).
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in GoalEvent.meta"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// SwiftData mirror of the `goal_events` table (docs/spec.md §13; backend/supabase/migrations/0001_init.sql).
@Model
public final class GoalEvent {
    /// Matches `goal_events.id`.
    @Attribute(.unique) public var id: UUID

    /// Matches `goal_events.ts`.
    public var ts: Date

    /// Matches `goal_events.kind`.
    public var kind: GoalEventKind

    /// Matches `goal_events.value` (Postgres `numeric`, nullable — e.g. grams logged, minutes dwelt).
    public var value: Double?

    /// Matches `goal_events.source`.
    public var source: GoalEventSource

    /// Matches `goal_events.verified`. Default `false`.
    public var verified: Bool

    /// Backing storage for `meta`, matching `goal_events.meta jsonb not null default '{}'`.
    ///
    /// Stored as raw JSON `Data` rather than persisting `JSONValue` (a recursive Codable enum)
    /// directly as a SwiftData attribute: `Data` is a core, unambiguously-supported SwiftData
    /// attribute type on iOS 17, whereas SwiftData's handling of open-ended recursive Codable enums
    /// as attributes is not something this environment can compile-check (no Mac/Swift toolchain
    /// available — see knownIssues). Use the `meta` computed property below for structured access;
    /// it round-trips through this field automatically.
    public var metaData: Data

    /// Matches `goal_events.user_id`. Inverse of `User.goalEvents`.
    public var user: User?

    /// Matches `goal_events.goal_id`. Inverse of `Goal.events`.
    public var goal: Goal?

    /// Structured view over `metaData`. Reads default to `.object([:])` (matching the column's
    /// `not null default '{}'::jsonb`) if `metaData` is ever empty or not valid JSON.
    public var meta: JSONValue {
        get {
            (try? JSONDecoder().decode(JSONValue.self, from: metaData)) ?? .object([:])
        }
        set {
            metaData = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8)
        }
    }

    public init(
        id: UUID = UUID(),
        ts: Date = Date(),
        kind: GoalEventKind,
        value: Double? = nil,
        source: GoalEventSource,
        verified: Bool = false,
        meta: JSONValue = .object([:]),
        user: User? = nil,
        goal: Goal? = nil
    ) {
        self.id = id
        self.ts = ts
        self.kind = kind
        self.value = value
        self.source = source
        self.verified = verified
        self.metaData = (try? JSONEncoder().encode(meta)) ?? Data("{}".utf8)
        self.user = user
        self.goal = goal
    }
}
