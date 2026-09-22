// Goal.swift
// Core / Models
//
// Mirrors the `goals` table in backend/supabase/migrations/0001_init.sql field-for-field, per
// docs/spec.md §13 (Data Model). `GoalType` enumerates the full goal catalog from docs/spec.md §3
// (Goal Catalog & Verification) — v1 through v3, since §13 is meant to be frozen once, up front,
// rather than reshaped every time a later session adds a new goal type.
//
// Safety rule (docs/spec.md §24, CLAUDE.md): additive goals only. There is intentionally no case
// here for anything restrictive (calorie deficits, weight loss, fasting windows, etc.) — do not add
// one; flag such a request instead.

import Foundation
import SwiftData

/// The full goal catalog from docs/spec.md §3. Raw values are snake_case to match the style of the
/// other check-constrained text columns in backend/supabase/migrations/0001_init.sql (`coach_voice`,
/// `plan_tier`, etc.); `goals.type` itself has no Postgres check constraint (spec keeps the catalog
/// open-ended so new types can be added without a migration), so this enum is the source of truth
/// for valid values on the client.
public enum GoalType: String, Codable, CaseIterable, Sendable {
    /// Gym workout — geofence arrival + minimum dwell + HealthKit workout or elevated HR. Tier A.
    case workoutGym = "workout_gym"
    /// Home/outdoor workout — HealthKit workout or Core Motion active minutes. Tier A.
    case workoutHomeOutdoor = "workout_home_outdoor"
    /// In-app timed focus session with shields active. Tier A.
    case focusSession = "focus_session"
    /// Protein intake — NFC tap, meal photo, barcode, or quick-repeat. Tier B.
    case protein
    /// Water intake — NFC tap or widget button. Tier B.
    case water
    /// Step count vs. target via HealthKit. Tier A.
    case steps
    /// Creatine/supplement — NFC tap or widget button. Tier B.
    case creatine
    /// Morning routine / Sunrise Alarm (docs/spec.md §5.10). Tier A.
    case sunriseAlarm = "sunrise_alarm"
    /// Sleep on time — no pickups after bedtime + HealthKit sleep. Tier A.
    case sleepOnTime = "sleep_on_time"
    /// Reading — timer session or NFC tag inside a book. Tier B.
    case reading
    /// Weekly meal prep — photo confirms multiple meal containers. Tier B.
    case mealPrep = "meal_prep"
    /// Stretch / mobility — guided timer with device-flat accelerometer check. Tier B.
    case stretchMobility = "stretch_mobility"
    /// Cold shower / sauna — one tap + optional photo. Tier C.
    case coldShowerSauna = "cold_shower_sauna"
    /// User-defined goal with user-set friction. Tier C.
    case custom
}

/// Matches the `goals.verification_tier` check constraint (`'A' | 'B' | 'C'`) exactly, including
/// the raw values, so the local field round-trips with Postgres without translation.
/// See docs/spec.md §3: "Auto-verify if possible. One tap if not. Never a form."
public enum VerificationTier: String, Codable, CaseIterable, Sendable {
    /// Fully automatic (geofence, HealthKit, NFC-only-cap-checks, etc.). No user action to confirm.
    case a = "A"
    /// One tap to confirm/log.
    case b = "B"
    /// Honesty + friction (e.g. a hold-to-confirm button). No automatic verification possible.
    case c = "C"
}

/// SwiftData mirror of the `goals` table (docs/spec.md §13; backend/supabase/migrations/0001_init.sql).
@Model
public final class Goal {
    /// Matches `goals.id`.
    @Attribute(.unique) public var id: UUID

    /// Matches `goals.type`. See `GoalType` for the full catalog (docs/spec.md §3).
    public var type: GoalType

    /// Matches `goals.title` — user-facing name for this goal instance (e.g. "Leg day", "Gallon a day").
    /// Actual display copy composition still lives in Core/Sources/Core/Copy, not here.
    public var title: String

    /// Matches `goals.target_value` (Postgres `numeric`, nullable — e.g. grams of protein, minutes).
    public var targetValue: Double?

    /// Matches `goals.unit` (e.g. `"g"`, `"oz"`, `"min"`, `"steps"`).
    public var unit: String?

    /// Matches `goals.cadence` (free text, e.g. `"daily"`, `"weekly"`, `"per-week-count"` — not a
    /// fixed enum in the migration, so kept as a string here rather than over-constraining it).
    public var cadence: String?

    /// Matches `goals.verification_tier`.
    public var verificationTier: VerificationTier

    /// Matches `goals.active`. Default `true`.
    public var active: Bool

    /// Matches `goals.adaptive` — whether `AdaptiveGoalEngine` is allowed to move the daily bar for
    /// this goal (docs/spec.md §9, §11). Default `true`.
    public var adaptive: Bool

    /// Matches `goals.created_at`.
    public var createdAt: Date

    /// Matches `goals.user_id`. Inverse of `User.goals`.
    public var user: User?

    /// Inverse of `DailyPlan.goal`. Deleting the goal locally cascades to its planned days.
    @Relationship(deleteRule: .cascade, inverse: \DailyPlan.goal)
    public var dailyPlans: [DailyPlan] = []

    /// Inverse of `GoalEvent.goal`. Deleting the goal locally cascades to its event history.
    @Relationship(deleteRule: .cascade, inverse: \GoalEvent.goal)
    public var events: [GoalEvent] = []

    public init(
        id: UUID = UUID(),
        type: GoalType,
        title: String,
        targetValue: Double? = nil,
        unit: String? = nil,
        cadence: String? = nil,
        verificationTier: VerificationTier,
        active: Bool = true,
        adaptive: Bool = true,
        createdAt: Date = Date(),
        user: User? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.targetValue = targetValue
        self.unit = unit
        self.cadence = cadence
        self.verificationTier = verificationTier
        self.active = active
        self.adaptive = adaptive
        self.createdAt = createdAt
        self.user = user
    }
}
