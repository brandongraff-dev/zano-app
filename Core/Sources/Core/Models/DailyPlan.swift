// DailyPlan.swift
// Core / Models
//
// Mirrors the `daily_plans` table in backend/supabase/migrations/0001_init.sql field-for-field, per
// docs/spec.md §13 (Data Model). One row per (user, goal, date) — the adaptive engine's decision for
// what "done" means for that goal on that day (docs/spec.md §9, `AdaptiveGoalEngine.dailyPlan`).

import Foundation
import SwiftData

/// Matches the `daily_plans.source` check constraint (`'rules' | 'bandit' | 'manual'`) exactly.
/// Records which system produced this day's plan: the v1 rules engine, the v3 bandit
/// (docs/spec.md §9), or a manual override.
public enum DailyPlanSource: String, Codable, CaseIterable, Sendable {
    case rules
    case bandit
    case manual
}

/// SwiftData mirror of the `daily_plans` table (docs/spec.md §13; backend/supabase/migrations/0001_init.sql).
///
/// Postgres enforces `unique (user_id, goal_id, date)`. SwiftData on iOS 17 (this package's minimum
/// deployment target, see Core/Package.swift) has no composite-uniqueness attribute — that requires
/// the iOS 18 `#Unique` macro — so this constraint is enforced server-side only for now; local
/// writers (LockEngine/Retention modules) are responsible for not creating duplicate local rows for
/// the same (user, goal, date). Flagged in this task's knownIssues for the orchestrator.
@Model
public final class DailyPlan {
    /// Matches `daily_plans.id`.
    @Attribute(.unique) public var id: UUID

    /// Matches `daily_plans.date` (Postgres `date`, stored locally as a `Date` at midnight in the
    /// user's timezone — callers should normalize with `Calendar.startOfDay` before querying/saving).
    public var date: Date

    /// Matches `daily_plans.planned_value` (Postgres `numeric`, nullable — the day's target amount).
    public var plannedValue: Double?

    /// Matches `daily_plans.difficulty_step`. Signed step away from the goal's baseline difficulty,
    /// moved by `AdaptiveGoalEngine.adjustDifficulty`. Default `0`.
    public var difficultyStep: Int

    /// Matches `daily_plans.plan_b_value` — the easier fallback target for "Plan B" days
    /// (docs/spec.md §8 Retention Psychology Rules).
    public var planBValue: Double?

    /// Matches `daily_plans.source`. Default `.rules`.
    public var source: DailyPlanSource

    /// Matches `daily_plans.user_id`. Inverse of `User.dailyPlans`.
    public var user: User?

    /// Matches `daily_plans.goal_id`. Inverse of `Goal.dailyPlans`.
    public var goal: Goal?

    public init(
        id: UUID = UUID(),
        date: Date,
        plannedValue: Double? = nil,
        difficultyStep: Int = 0,
        planBValue: Double? = nil,
        source: DailyPlanSource = .rules,
        user: User? = nil,
        goal: Goal? = nil
    ) {
        self.id = id
        self.date = date
        self.plannedValue = plannedValue
        self.difficultyStep = difficultyStep
        self.planBValue = planBValue
        self.source = source
        self.user = user
        self.goal = goal
    }
}
