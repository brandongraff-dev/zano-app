// User.swift
// Core / Models
//
// Mirrors the `users` table in backend/supabase/migrations/0001_init.sql field-for-field, per
// docs/spec.md §13 (Data Model). §13 states local (SwiftData) and remote (Postgres) share the same
// shapes; UUIDs everywhere; timestamps are UTC with the user's timezone stored on the user row.
//
// In practice this device's local SwiftData store holds exactly one `User` row — the signed-in (or
// anonymous, per spec §4 "anonymous-first") owner of the device — plus that user's own `Goal`,
// `DailyPlan`, and `GoalEvent` rows. Other users (squad members, duel opponents, a referrer) live
// remotely only; see `referredBy` below for why that FK is a plain id, not a `@Relationship`.

import Foundation
import SwiftData

/// The coach voice used to generate copy for this user (docs/spec.md §5.13). Mirrors the
/// `users.coach_voice` check constraint (`hype | tough_love | chill | data`) exactly.
public enum CoachVoice: String, Codable, CaseIterable, Sendable {
    case hype
    case toughLove = "tough_love"
    case chill
    case data
}

/// Mirrors the `users.plan_tier` check constraint (`free | pro`). Drives paywall gating
/// (docs/spec.md §21) — never used to restrict goal types, only monetized conveniences.
public enum PlanTier: String, Codable, CaseIterable, Sendable {
    case free
    case pro
}

/// SwiftData mirror of the `users` table (docs/spec.md §13; backend/supabase/migrations/0001_init.sql).
///
/// `id` matches `auth.users(id)` on the backend (Sign in with Apple, or an anonymous auth id before
/// the user ever links an Apple ID — see spec §4/§7). It is assigned by the auth flow, not this
/// model; the default `UUID()` below only covers ad hoc/local construction (e.g. previews, tests).
@Model
public final class User {
    /// Matches `users.id`, which itself references `auth.users(id)` on the backend.
    @Attribute(.unique) public var id: UUID

    /// Matches `users.apple_sub` (unique). `nil` until the user links Sign in with Apple.
    public var appleSub: String?

    /// Matches `users.created_at`.
    public var createdAt: Date

    /// Matches `users.tz` (IANA timezone identifier, e.g. `"America/Chicago"`). Default `"UTC"`.
    public var tz: String

    /// Matches `users.coach_voice`. Default `.hype`.
    public var coachVoice: CoachVoice

    /// Matches `users.plan_tier`. Default `.free`.
    public var planTier: PlanTier

    /// Matches `users.referral_code` (unique). `nil` until one is generated/assigned.
    public var referralCode: String?

    /// Matches `users.referred_by` — the *id* of the user who referred this one, if any.
    ///
    /// This is intentionally a plain `UUID?`, not a `@Relationship` to another `User`: the
    /// referrer is a different person's account and their row is not expected to exist in this
    /// device's local store (local-first storage only ever holds the signed-in user's own graph).
    /// The referral bonus itself is applied server-side (docs/spec.md §4 "Referral").
    public var referredBy: UUID?

    /// Inverse of `Goal.user`. Deleting the user locally cascades to their goals.
    @Relationship(deleteRule: .cascade, inverse: \Goal.user)
    public var goals: [Goal] = []

    /// Inverse of `DailyPlan.user`. Deleting the user locally cascades to their daily plans.
    @Relationship(deleteRule: .cascade, inverse: \DailyPlan.user)
    public var dailyPlans: [DailyPlan] = []

    /// Inverse of `GoalEvent.user`. Deleting the user locally cascades to their event history.
    @Relationship(deleteRule: .cascade, inverse: \GoalEvent.user)
    public var goalEvents: [GoalEvent] = []

    public init(
        id: UUID = UUID(),
        appleSub: String? = nil,
        createdAt: Date = Date(),
        tz: String = "UTC",
        coachVoice: CoachVoice = .hype,
        planTier: PlanTier = .free,
        referralCode: String? = nil,
        referredBy: UUID? = nil
    ) {
        self.id = id
        self.appleSub = appleSub
        self.createdAt = createdAt
        self.tz = tz
        self.coachVoice = coachVoice
        self.planTier = planTier
        self.referralCode = referralCode
        self.referredBy = referredBy
    }
}
