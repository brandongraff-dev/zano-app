import Foundation
import SwiftData

/// One day's slip-risk prediction for a user (spec §9.2): the modeled probability that the user
/// misses every goal on that day. Written by the risk model — cold start is logistic regression on
/// onboarding answers + population priors, later a gradient-boosted-trees (LightGBM) model — and
/// read around 9 AM to decide whether to offer Plan B in the widget/shield copy and schedule a
/// nudge at the user's historically best action hour.
///
/// Mirrors the Supabase `risk_scores` table (`backend/supabase/migrations/0001_init.sql`)
/// field-for-field. Postgres has no surrogate id there — its primary key is the composite
/// `(user_id, date)`. SwiftData's composite `#Unique` macro needs iOS 18+ and this package targets
/// iOS 17 (see `Core/Package.swift`), so `id` below is a local-only SwiftData identity; the Sync
/// outbox (Session 7) reconciles rows against the server by `(userID, date)`, not by `id`.
@Model
public final class RiskScore {
    /// Local SwiftData identity only — no Postgres counterpart (see type doc comment above).
    @Attribute(.unique) public var id: UUID

    /// Mirrors `risk_scores.user_id` (part of the remote composite primary key).
    public var userID: UUID

    /// Mirrors `risk_scores.date` (part of the remote composite primary key) — the calendar day
    /// this prediction is *for*, not the day it was computed.
    public var date: Date

    /// Mirrors `risk_scores.p_miss` — predicted probability (0...1) the user misses every goal on
    /// `date`. Nil if a prediction hasn't been computed yet for this row.
    public var pMiss: Double?

    /// Mirrors `risk_scores.model_version` — identifies which model produced `pMiss` (e.g.
    /// `"logreg-coldstart-1"`, `"lgbm-2024-03"`), so the app/ML service can distinguish cold-start
    /// scores from trained-model scores and reason about drift.
    public var modelVersion: String?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        date: Date,
        pMiss: Double? = nil,
        modelVersion: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.date = date
        self.pMiss = pMiss
        self.modelVersion = modelVersion
    }
}
