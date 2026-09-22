// Core/Sources/Core/Retention/AdaptiveGoalEngine.swift
//
// docs/spec.md §9.1 Adaptive Goal Engine (highest priority):
//   "Input: user intent (target/week), 28-day completion history per goal, day-of-week effects,
//   recent streak, sleep (if available).
//   v1 (rules): target completion rate 75–85%. If 7-day rate < 60% → lower the daily bar one step
//   (fewer minutes / fewer days / lower grams). If > 90% for 10 days → raise one step. Never
//   change more than one step per week.
//   v2 (bandit): per-user contextual bandit over difficulty levels... (out of scope here — v1
//   rules only, per this task).
//   Output: `daily_plan` rows."
// docs/spec.md §8 Retention Psychology Rules, rule 1 ("Early wins are engineered"):
//   "First 3 days' goals are ~70% of stated capability. The engine raises the bar only after
//   wins." Folded into `dailyPlan(for:on:)` below as a cold-start path that runs *before* the
//   rules engine has any history to reason about, rather than a separate feature.
//
// This file implements EXACTLY the public shape from this task's SYSTEM CONTRACTS block:
//
//   final class AdaptiveGoalEngine {
//       static let shared = AdaptiveGoalEngine()
//       func dailyPlan(for goal: Goal, on date: Date) async -> DailyPlan
//       func adjustDifficulty(for goal: Goal, last28Days: [GoalEvent]) async -> Int
//   }
//
// so other agents' code (LockEngineManager, App Intents, UI) can call
// `AdaptiveGoalEngine.shared.dailyPlan(for:on:)` today, before this file exists on disk from
// their point of view, and keep compiling once it lands. `PlanB.swift` (this same task, this
// same directory) is this file's one real, same-module caller right now — see its header comment
// for how the two fit together.
//
// v1 rules only. v2's contextual bandit (spec §9.1) is explicitly out of scope for this task.

import Foundation
import SwiftData
import os

/// docs/spec.md §9.1's v1 rules engine, and the sole owner of producing/persisting `DailyPlan`
/// rows (spec §13 `daily_plans`) for a given `(goal, date)`.
///
/// `@MainActor`, not a bare `final class` with no isolation: the same reasoning
/// `LockEngineManager` documents at its own declaration applies verbatim here — under Swift 6
/// strict concurrency a plain `final class` singleton needs either `Sendable` conformance (not
/// realistic for a type that owns a `ModelContext`) or isolation to a global actor, and every
/// realistic call site (SwiftUI views, App Intents, `PlanB.swift`) is already `@MainActor` or
/// happy to `await` a hop onto it. A `@MainActor final class` is implicitly `Sendable`, so
/// `.shared` and every method below stay callable from any isolation domain exactly the way
/// CONTRACTS' other call sites assume. See this task's `knownIssues` for the one real wrinkle
/// this doesn't fully resolve: CONTRACTS' own signatures pass `Goal`/`GoalEvent` (SwiftData
/// `@Model` classes, not `Sendable`) as arguments to `async` methods on this actor.
@MainActor
public final class AdaptiveGoalEngine {
    public static let shared = AdaptiveGoalEngine()

    // MARK: - v1 rules constants (spec §9.1)

    /// "If 7-day rate < 60% → lower the daily bar one step."
    private static let lowerStepThreshold: Double = 0.60
    private static let lowerStepWindowDays = 7

    /// "If > 90% for 10 days → raise one step."
    private static let raiseStepThreshold: Double = 0.90
    private static let raiseStepWindowDays = 10

    /// Neither threshold fires between these two windows' results — that's the spec's stated
    /// "target completion rate 75–85%" band in practice: not a third rule, just where the 60%/90%
    /// guardrails are aiming to keep a user. Not a symbol anywhere below on purpose (nothing
    /// branches on it directly) — recorded here only so the number in this comment can't drift
    /// from spec §9.1's text.

    /// "Never change more than one step per week." Enforced in `dailyPlan(for:on:)` (the only
    /// place that knows a goal's *persisted* step history — see `stepBaseline(for:before:)`), not
    /// in `adjustDifficulty` itself, which is a pure function of the history it's handed and has
    /// no notion of "when did this goal's step last change."
    private static let minStepChangeInterval: TimeInterval = 7 * 24 * 60 * 60

    /// How much history `dailyPlan(for:on:)` fetches to hand `adjustDifficulty` — spec §9.1's
    /// input list: "28-day completion history per goal."
    private static let adjustmentWindowDays = 28

    // MARK: - Engineered early wins (spec §8 rule 1)

    private static let earlyWinDays = 3
    private static let earlyWinFraction = 0.70

    // MARK: - Step sizing (spec §9.1: "fewer minutes / fewer days / lower grams")
    //
    // Spec §9.1 says *what* a step does directionally; it does not pin an exact step size per
    // unit. The values below are this task's best-effort, simple v1 read of "fewer
    // minutes/grams" as roughly a 10% move per step (rounded to a unit-appropriate granularity),
    // never crushing a goal below `minimumFractionOfBase` of its stated target — additive goals
    // only (CLAUDE.md, spec §24) means a "harder step" or "easier step" must still be a real,
    // meaningful goal, never a goal reduced to nothing. Flagged as an assumption in this task's
    // `decisions`, not exact spec text.
    private static let minimumFractionOfBase = 0.3

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "AdaptiveGoalEngine")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container (mirrors `FocusSessionVerifier`'s/`LockEngineManager`'s own
    /// convention); every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - CONTRACTS: dailyPlan

    /// Returns today's (or `date`'s) `DailyPlan` for `goal`, creating and persisting one if it
    /// doesn't exist yet. Idempotent: a second call for the same `(goal, date)` returns the
    /// already-persisted row rather than creating a duplicate — `DailyPlan.swift`'s own doc
    /// comment calls this out as this engine's responsibility, since SwiftData on this package's
    /// iOS 17 minimum has no composite-uniqueness attribute to enforce `unique (user_id, goal_id,
    /// date)` locally the way Postgres does (spec §13).
    ///
    /// Never throws (CONTRACTS: `async -> DailyPlan`, not `async throws`): if persistence fails,
    /// this logs and still returns the computed plan so a caller with no error-handling path in
    /// this signature gets a usable value for `date` — it just won't survive a relaunch until the
    /// next successful save. Mirrors `LockEngineManager`/`FocusSessionVerifier`'s general stance
    /// of degrading rather than crashing a caller whose contract has nowhere to put an error.
    ///
    /// - Parameters:
    ///   - goal: The goal to plan. Only `goal.adaptive == true` goals ever move off their stated
    ///     `targetValue` (spec §9, §11 — `Goal.adaptive`'s own doc comment); a non-adaptive goal
    ///     is planned flatly at `targetValue`, step `0`, every day.
    ///   - date: Normalized to the local calendar day via `Calendar.current.startOfDay(for:)`,
    ///     per `DailyPlan.swift`'s own doc comment ("callers should normalize... before
    ///     querying/saving").
    public func dailyPlan(for goal: Goal, on date: Date) async -> DailyPlan {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        if let existing = fetchDailyPlan(goalID: goal.id, day: day) {
            return existing
        }

        let plannedValue: Double?
        let resultingStep: Int

        if !goal.adaptive {
            // spec §9/§11: `adaptive == false` opts this goal out of automatic difficulty
            // movement entirely — flat plan at the stated target, forever.
            plannedValue = goal.targetValue
            resultingStep = 0
        } else if isWithinEngineeredEarlyWinWindow(goal: goal, day: day, calendar: calendar) {
            // spec §8 rule 1: no rules-engine math yet — there isn't enough history in the first
            // `earlyWinDays` days for it to say anything meaningful, and spec is explicit this
            // window is engineered, not earned.
            plannedValue = goal.targetValue.map { $0 * Self.earlyWinFraction }
            resultingStep = 0
        } else {
            let baseline = stepBaseline(for: goal, before: day)
            let recentEvents = fetchRecentEvents(
                for: goal,
                endingBefore: day,
                windowDays: Self.adjustmentWindowDays
            )
            let recommendedDelta = await adjustDifficulty(for: goal, last28Days: recentEvents)
            let appliedDelta = weeklyCappedDelta(recommendedDelta, baseline: baseline, asOf: day)
            resultingStep = baseline.step + appliedDelta
            plannedValue = steppedValue(base: goal.targetValue, step: resultingStep, unit: goal.unit)
        }

        let plan = DailyPlan(
            date: day,
            plannedValue: plannedValue,
            difficultyStep: resultingStep,
            planBValue: nil,
            source: .rules,
            user: goal.user,
            goal: goal
        )
        context.insert(plan)
        do {
            try context.save()
        } catch {
            logger.error(
                "dailyPlan: failed to persist DailyPlan for goal \(goal.id.uuidString, privacy: .public) on \(day.timeIntervalSince1970, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
        return plan
    }

    // MARK: - CONTRACTS: adjustDifficulty

    /// Pure v1-rules read of `last28Days` (spec §9.1): recommends a difficulty-step delta —
    /// `-1`, `0`, or `+1` — with no notion of a goal's *current* step or when it last changed
    /// (that state lives only in persisted `DailyPlan` history, which `dailyPlan(for:on:)` reads
    /// separately via `stepBaseline(for:before:)` and is what actually enforces "never more than
    /// one step per week"). Returning a delta rather than an absolute step is this task's
    /// resolution of an ambiguity in CONTRACTS' bare `-> Int`: this method's parameters carry no
    /// "current step" input to move an absolute value *from*, so a signed adjustment is the only
    /// reading that makes the function meaningful on its own — flagged in this task's
    /// `decisions`.
    ///
    /// The "as of" day for the 7-day/10-day trailing windows is derived from `last28Days` itself
    /// (the latest calendar day any event in the array falls on), not `Date.now` — this keeps the
    /// method a pure, deterministic function of its input (trivially unit-testable with
    /// hand-built `GoalEvent`s) and matches how `dailyPlan(for:on:)` calls it: with events already
    /// filtered to strictly before the day being planned, so "latest day in the array" is exactly
    /// "the most recent day with complete data." An empty array returns `0` (no signal, no
    /// change) rather than guessing a reference day.
    ///
    /// "Completed" here means a `GoalEvent` with `verified == true` and `kind` of `.complete` or
    /// `.planB` on that calendar day — a Plan B completion (spec §5.5) still counts as genuine
    /// engagement with the goal for this purpose, unlike `.freeze` (a streak-protection spend,
    /// not evidence the user could or couldn't hit the current bar) or bare `.log`/`.verify`
    /// events, which are excluded.
    public func adjustDifficulty(for goal: Goal, last28Days: [GoalEvent]) async -> Int {
        let events = last28Days.filter { $0.goal?.id == goal.id }
        guard let asOf = referenceDay(from: events) else { return 0 }

        let completedDays = completedDayKeys(in: events)

        let sevenDayRate = completionRate(
            completedDayKeys: completedDays,
            trailingDays: Self.lowerStepWindowDays,
            asOf: asOf
        )
        if sevenDayRate < Self.lowerStepThreshold {
            return -1
        }

        let tenDayRate = completionRate(
            completedDayKeys: completedDays,
            trailingDays: Self.raiseStepWindowDays,
            asOf: asOf
        )
        if tenDayRate > Self.raiseStepThreshold {
            return 1
        }

        return 0
    }

    // MARK: - Cross-module integration point: PlanB.swift (same task, same module)

    /// Persists a Plan B reduced target (spec §5.5) onto `plan.planBValue` through *this* engine's
    /// `ModelContext` — not `public` (CONTRACTS says "implement EXACTLY this public shape"; this
    /// is deliberately kept `internal` so it adds no public API to `AdaptiveGoalEngine` beyond the
    /// three CONTRACTS members) but reachable from `PlanB.swift` since both files compile into the
    /// same `Core` module target. `plan` must have been produced by `dailyPlan(for:on:)` on this
    /// same `.shared` instance — SwiftData model instances can only be safely mutated/saved
    /// through the `ModelContext` that fetched/inserted them, and this engine owns the one
    /// `ModelContext` every `DailyPlan` it hands out was created through.
    @discardableResult
    func setPlanBValue(_ value: Double?, on plan: DailyPlan) async -> Bool {
        plan.planBValue = value
        do {
            try context.save()
            return true
        } catch {
            logger.error(
                "setPlanBValue: failed to persist planBValue for DailyPlan (goal \(plan.goal?.id.uuidString ?? "nil", privacy: .public)): \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Engineered early wins

    private func isWithinEngineeredEarlyWinWindow(goal: Goal, day: Date, calendar: Calendar) -> Bool {
        let createdDay = calendar.startOfDay(for: goal.createdAt)
        guard let daysSinceCreated = calendar.dateComponents([.day], from: createdDay, to: day).day else {
            return false
        }
        return daysSinceCreated >= 0 && daysSinceCreated < Self.earlyWinDays
    }

    // MARK: - Step baseline (persisted history → current step + how long it's been in effect)

    private struct StepBaseline {
        let step: Int
        /// See `stepBaseline(for:before:)`'s doc comment — a conservative lower bound on "since
        /// when," not necessarily the exact date the step last changed.
        let inEffectSince: Date
    }

    /// Reconstructs "what difficulty step is `goal` currently on, and since when" purely from its
    /// own persisted `DailyPlan` history. Neither `Goal` nor `DailyPlan` (Session 1's models —
    /// not this task's file list to modify, per this task's instructions) has a dedicated
    /// "current step" or "step last changed at" column, so this walks `dailyPlans` (newest day
    /// first) instead of maintaining a second, parallel piece of state that could drift from
    /// what's actually stored.
    ///
    /// If every fetched prior plan shares the same step, this returns the *oldest* of those
    /// matching rows' dates as `inEffectSince` — a deliberately conservative lower bound: the step
    /// may genuinely have started even earlier than local history goes back (a first run of this
    /// engine, or a fresh install with a partial local cache, both look identical to "stable for a
    /// long time" here). That only ever makes `weeklyCappedDelta` *more* permissive (willing to
    /// allow a change slightly sooner than a fuller history might justify), never less — this
    /// never blocks a legitimate change, which matches spec §9.1's "never more than one step per
    /// week" reading as a ceiling on churn, not a promise to always wait the full week when in
    /// doubt. Flagged as a best-effort v1 approximation in this task's `decisions`.
    ///
    /// Only walks `.rules`/`.bandit`-sourced rows (`fetchPriorDailyPlans` excludes `.manual`) —
    /// fixed in this batch's cross-check: `ComebackMode.swift` (same directory) writes `.manual`
    /// `DailyPlan` rows with its own `difficultyStepMarker` sentinel onto the same `(goal, date)`
    /// series this engine produces. Before this fix, a comeback challenge's temporary reduced
    /// plan would get read back as this engine's own "current step" the next time it planned a
    /// day past the challenge — permanently anchoring every future day to the comeback's
    /// artificially-low difficulty instead of resuming the rules engine's real step history.
    private func stepBaseline(for goal: Goal, before day: Date) -> StepBaseline {
        let priorPlans = fetchPriorDailyPlans(for: goal, before: day)
        guard let mostRecent = priorPlans.first else {
            return StepBaseline(step: 0, inEffectSince: .distantPast)
        }

        var inEffectSince = mostRecent.date
        for plan in priorPlans.dropFirst() {
            guard plan.difficultyStep == mostRecent.difficultyStep else { break }
            inEffectSince = plan.date
        }
        return StepBaseline(step: mostRecent.difficultyStep, inEffectSince: inEffectSince)
    }

    /// "Never change more than one step per week" (spec §9.1). `delta == 0` always passes through
    /// untouched (there's nothing to cap); a non-zero `delta` is only allowed once at least
    /// `minStepChangeInterval` has elapsed since the current step took effect.
    private func weeklyCappedDelta(_ delta: Int, baseline: StepBaseline, asOf day: Date) -> Int {
        guard delta != 0 else { return 0 }
        guard day.timeIntervalSince(baseline.inEffectSince) >= Self.minStepChangeInterval else { return 0 }
        return delta
    }

    // MARK: - Step sizing

    private func steppedValue(base: Double?, step: Int, unit: String?) -> Double? {
        guard let base, step != 0 else { return base }
        let size = Self.stepSize(forUnit: unit, baseValue: base)
        // Floor is `minimumFractionOfBase` of the goal's own stated target (this file's doc
        // comment above, and CLAUDE.md/spec §24's additive-goals-only rule: a lowered goal must
        // still be a real goal). Deliberately NOT `max(size, base * minimumFractionOfBase)` — a
        // fixed-unit `size` (e.g. 10g) can exceed a small goal's own `base` (e.g. a 5g creatine
        // target), which would make the "floor" bigger than 100% of the original target and
        // invert a difficulty *decrease* into an increase. Fixed here: reviewed this batch
        // (Retention cross-check task) after finding that edge case; the original per-unit
        // `size` floor was this task's own invention, not something spec §9.1 asked for.
        let floor = base * Self.minimumFractionOfBase
        let candidate = base + Double(step) * size
        return max(floor, candidate)
    }

    /// See the "Step sizing" constants comment above for why these numbers are a best-effort v1
    /// approximation, not exact spec text.
    private static func stepSize(forUnit unit: String?, baseValue: Double) -> Double {
        switch unit?.lowercased() {
        case "min", "mins", "minute", "minutes": return 5
        case "g", "gram", "grams": return 10
        case "ml": return 125
        case "oz": return 4
        case "steps": return 500
        default: return max(1, (baseValue * 0.1).rounded())
        }
    }

    // MARK: - Completion-rate math (pure; no SwiftData)

    /// The latest calendar day any event in `events` falls on, at local-calendar-day resolution —
    /// see `adjustDifficulty`'s doc comment for why this (not `Date.now`) is the reference day.
    private func referenceDay(from events: [GoalEvent]) -> Date? {
        guard let latest = events.map(\.ts).max() else { return nil }
        return Calendar.current.startOfDay(for: latest)
    }

    /// The set of calendar days (as `dayKey(for:)` strings) on which `events` contains at least
    /// one completed event — see `adjustDifficulty`'s doc comment for exactly what counts.
    private func completedDayKeys(in events: [GoalEvent]) -> Set<String> {
        Set(events.compactMap { event -> String? in
            guard event.verified, event.kind == .complete || event.kind == .planB else { return nil }
            return Self.dayKey(for: event.ts)
        })
    }

    /// Fraction of the `trailingDays` calendar days ending at (and including) `referenceDay` that
    /// appear in `completedDayKeys`.
    private func completionRate(completedDayKeys: Set<String>, trailingDays: Int, asOf referenceDay: Date) -> Double {
        guard trailingDays > 0 else { return 0 }
        let calendar = Calendar.current
        var hits = 0
        for offset in 0..<trailingDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: referenceDay) else { continue }
            if completedDayKeys.contains(Self.dayKey(for: day)) { hits += 1 }
        }
        return Double(hits) / Double(trailingDays)
    }

    /// Local-calendar-day key, coarse enough that two `Date`s on the same day always match
    /// regardless of time-of-day — deliberately simpler than `TimeBank.swift`'s UTC-pinned
    /// `dayKey` (which exists to be a stable SwiftData `@Attribute(.unique)` key across
    /// processes); this one is purely an in-memory grouping key for one synchronous computation,
    /// so using the same calendar as the rest of this file (`Calendar.current`, matching
    /// `DailyPlan.swift`'s own normalization convention) keeps it consistent with
    /// `dailyPlan(for:on:)`'s day boundaries instead.
    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - SwiftData

    private func fetchDailyPlan(goalID: UUID, day: Date) -> DailyPlan? {
        let descriptor = FetchDescriptor<DailyPlan>(predicate: #Predicate<DailyPlan> { $0.date == day })
        guard let plans = try? context.fetch(descriptor) else { return nil }
        return plans.first { $0.goal?.id == goalID }
    }

    /// All of `goal`'s persisted, engine-produced (`.rules`/`.bandit`, never `.manual`)
    /// `DailyPlan`s strictly before `day`, newest first. Filters the `goal` relationship in plain
    /// Swift rather than inside `#Predicate` — the same conservative choice
    /// `LockEngineManager.isGoalVerified` documents: this session has no Mac/Swift toolchain to
    /// compile-verify how `#Predicate` handles optional-relationship chaining
    /// (`plan.goal?.id == goal.id`) on this SDK version, so only the unambiguous `Date` comparison
    /// stays in the predicate.
    ///
    /// Excludes `source == .manual` rows (also filtered here in plain Swift, matching this file's
    /// own stated caution about enum equality inside `#Predicate`, not just the relationship
    /// filter): `stepBaseline(for:before:)` uses this history to reconstruct "what step is this
    /// goal currently on," and a manual override's `difficultyStep` (e.g. `ComebackMode.swift`'s
    /// `difficultyStepMarker` sentinel) is not a real continuation of this engine's own step
    /// ladder — see `stepBaseline`'s doc comment.
    private func fetchPriorDailyPlans(for goal: Goal, before day: Date) -> [DailyPlan] {
        let descriptor = FetchDescriptor<DailyPlan>(
            predicate: #Predicate<DailyPlan> { $0.date < day },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let plans = try? context.fetch(descriptor) else { return [] }
        return plans.filter { $0.goal?.id == goal.id && $0.source != .manual }
    }

    /// `goal`'s verified `GoalEvent`s in `[day - windowDays, day)` — spec §9.1's "28-day
    /// completion history," fetched fresh each call rather than cached, since this engine has no
    /// invalidation hook for new events landing between calls. Same conservative
    /// filter-after-fetch pattern as `fetchPriorDailyPlans` above.
    private func fetchRecentEvents(for goal: Goal, endingBefore day: Date, windowDays: Int) -> [GoalEvent] {
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -windowDays, to: day) else {
            return []
        }
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= windowStart && $0.ts < day }
        )
        guard let events = try? context.fetch(descriptor) else { return [] }
        return events.filter { $0.goal?.id == goal.id }
    }
}
