// Core/Sources/Core/Models/Gym.swift
//
// Mirrors the `gyms` table field-for-field.
// Source of truth: docs/spec.md §13 (Data Model) and
// backend/supabase/migrations/0001_init.sql ("gyms").
//
//   create table gyms (
//       id uuid primary key default gen_random_uuid(),
//       user_id uuid not null references users(id) on delete cascade,
//       lat double precision not null,
//       lng double precision not null,
//       radius_m integer not null default 150,
//       name text,
//       auto_detected boolean not null default false,
//       confirmed boolean not null default false
//   );
//
// This is the on-device (SwiftData, App Group–backed) mirror of that row. Used by the Workout
// goal's Tier A verification path (spec §3: "Geofence arrival at saved gym + minimum dwell
// (default 35 min) + HealthKit workout OR elevated HR during dwell") and by §9.4 gym
// auto-detection (CLVisit clustering suggests a candidate, the user confirms "Is this your gym?").
//
// Consumed by `GymVerifier` (Core/Sources/Core/Verification/GymVerifier.swift), which is called
// with just a `gymID: UUID` — so this model intentionally has no relationships wired to it yet;
// callers look gyms up by id from the shared ModelContext.

import Foundation
import SwiftData

/// A user-saved gym location: a geofence center + radius used to verify the Workout goal by
/// arrival + minimum dwell time (spec §3, §9.4).
///
/// `userID` mirrors the remote schema's `user_id` foreign key for shape parity with Postgres and
/// future sync (Session 7), even though the on-device store only ever holds rows for the
/// signed-in user. FamilyControls app tokens are never stored here — this model holds only
/// location data, never anything from `lock_sets` (spec §13's "app tokens never leave the
/// device" rule doesn't apply to this file, but nothing here should ever gain such a field).
@Model
public final class Gym {
    /// Primary key. Matches `gyms.id` (`uuid primary key default gen_random_uuid()`).
    @Attribute(.unique)
    public var id: UUID

    /// Matches `gyms.user_id`. Owning user of this saved gym.
    public var userID: UUID

    /// Matches `gyms.lat` (`double precision not null`).
    public var lat: Double

    /// Matches `gyms.lng` (`double precision not null`).
    public var lng: Double

    /// Matches `gyms.radius_m` (`integer not null default 150`). Geofence radius in meters used
    /// by `GymVerifier` for arrival + dwell tracking.
    public var radiusMeters: Int

    /// Matches `gyms.name` (`text`, nullable). User-facing label, e.g. "Equinox Downtown".
    public var name: String?

    /// Matches `gyms.auto_detected` (`boolean not null default false`). True when this gym was
    /// proposed by the §9.4 auto-detection pipeline (clustered `CLVisit`s, recurring ≥ 2×/14
    /// days) rather than picked manually on the map in Gym Setup.
    public var autoDetected: Bool

    /// Matches `gyms.confirmed` (`boolean not null default false`). True once the user has
    /// confirmed this as their gym — either immediately for a manually-picked gym, or via the
    /// "Is this your gym?" prompt for an auto-detected candidate. `GymVerifier` must only use
    /// confirmed gyms for real unlocks; an unconfirmed `autoDetected` row is a suggestion only.
    public var confirmed: Bool

    public init(
        id: UUID = UUID(),
        userID: UUID,
        lat: Double,
        lng: Double,
        radiusMeters: Int = 150,
        name: String? = nil,
        autoDetected: Bool = false,
        confirmed: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.lat = lat
        self.lng = lng
        self.radiusMeters = radiusMeters
        self.name = name
        self.autoDetected = autoDetected
        self.confirmed = confirmed
    }
}
