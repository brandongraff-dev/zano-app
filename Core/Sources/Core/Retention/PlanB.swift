// Core/Sources/Core/Retention/PlanB.swift
//
// docs/spec.md §5.5 Plan B Days:
//   "When slip prediction says today is high-risk (or the user says 'rough day'), the app offers
//   a Plan B: a smaller goal that still preserves the streak (20-min walk instead of gym; 25-min
//   focus instead of 90). Half credit in Earn Mode. This is the single biggest retention lever: it
//   stops one bad day from becoming a quit."
// docs/spec.md §8 Retention Psychology Rules, rule 3 ("Streaks have forgiveness"): lists Plan B
// alongside freezes/Never Miss Twice/Comeback mode as one of the mechanics that make a streak
// "feel protective, not fragile."
// docs/spec.md §9.2 Slip Prediction is the real ML risk signal that decides *when* today counts
// as high-risk (gradient-boosted trees / logistic-regression cold start) — that model is Session
// 12, explicitly out of scope for this task, which per this task's own instructions "just take[s]
// the Bool."
//
// This file owns: given a goal and an already-decided `isHighRisk` signal, what a reduced-but-
// still-meaningful version of *today's* plan looks like, and how much Earn Mode credit completing
// it is worth. It deliberately does NOT: run risk prediction itself (§9.2/Session 12); decide
// *when*/whether to surface the offer in shield/widget/UI copy (a `Core/Sources/Core/Copy` or
// App-layer concern, not this file's); or log the `goal_events.kind = 'plan_b'` row / deposit
// Earn Mode minutes once a user actually *completes* a Plan B goal — that happens at verification
// time, inside whichever goal verifier (`FocusSessionVerifier`, `GymVerifier`, an Intents handler
// for Tier B/C goals, ...) is running, none of which are this task's file list.
//
// TODO(cross-module integration — Verification/Intents layer, spec §5.5 + §14
// `LogCustomGoalIntent`/`EndFocusIntent`/goal verifiers; not this task's file list): when a goal
// is completed as its Plan B version, that layer should (a) log a `GoalEvent(kind: .planB, ...)`
// and (b), in Earn Mode, call `TimeBankEngine.shared.deposit(minutes: PlanB.earnModeMinutes(
// forFullMinutes: <that goal type's normal full-credit minute value, spec §5.2>), for: <date>)`.
// Neither call exists yet anywhere in the codebase as of this task — this file only provides the
// math (`earnModeMinutes(forFullMinutes:)`) those call sites need once they're written.

import Foundation
import SwiftData

/// v1 rules for Plan B (spec §5.5): a fixed reduction of today's adaptive target
/// (`AdaptiveGoalEngine.dailyPlan`, this same task's other file), worth half credit toward Earn
/// Mode's Time Bank. No ML lives here — `isHighRisk` is an opaque input decided elsewhere (spec
/// §9.2, Session 12); this file's whole job starts *after* that decision is made.
///
/// A plain `enum` namespace (uninstantiable, no stored state) rather than a class with a
/// `.shared` singleton — matches this codebase's convention for pure-computation Copy/Store
/// helpers (`ShieldCopy`, `CoachVoiceTone`, `SharedDefaults`) rather than CONTRACTS' engine
/// pattern, since CONTRACTS does not give this file a fixed public shape to match the way it does
/// `AdaptiveGoalEngine`.
@MainActor
public enum PlanB {

    // MARK: - v1 constants (spec §5.5)

    /// "Half credit in Earn Mode." Applies to whatever Earn Mode minutes a completed Plan B goal
    /// would otherwise be worth at full credit — see `earnModeMinutes(forFullMinutes:)`.
    public static let earnModeCreditFraction: Double = 0.5

    /// Spec §5.5's own examples are a steep cut, not a small nudge — "20-min walk instead of gym"
    /// (a ~60-90 min session, spec §5.2's earn-rate example), "25-min focus instead of 90" (a
    /// ~72% cut). Plan B has to feel meaningfully lighter than `AdaptiveGoalEngine`'s own
    /// single-step reduction (~10%/step, spec §9.1) or it can't do its job as "the single biggest
    /// retention lever" on a day the user is already at risk of missing entirely. Kept as one flat
    /// fraction (not per-goal-type tuning) for v1 simplicity — flagged as this task's best-effort
    /// read of spec §5.5's examples, not an exact number spec pins down, in `decisions`.
    public static let reducedTargetFraction: Double = 0.4

    /// A reduction is never allowed to round a goal away to nothing — CLAUDE.md/spec §24's
    /// additive-goals-only spirit: "a smaller goal that still preserves the streak" (spec §5.5) is
    /// still a goal, not a cancellation of one.
    private static let minimumFractionOfFull: Double = 0.1

    // MARK: - Offer

    /// A reduced-difficulty version of one goal's plan for one day (spec §5.5). Only ever produced
    /// when `isHighRisk` was `true` — see `offer(for:on:isHighRisk:)`.
    public struct Offer: Sendable, Equatable {
        public let goalID: UUID
        /// Local calendar day this offer is for — matches `DailyPlan.date`'s normalization
        /// (`AdaptiveGoalEngine.dailyPlan(for:on:)`).
        public let date: Date
        /// Today's full adaptive target before reduction (`DailyPlan.plannedValue`, falling back
        /// to the goal's raw `targetValue` if the plan row somehow has neither).
        public let fullValue: Double?
        /// The Plan B target: `fullValue * reducedTargetFraction`, floored per
        /// `minimumFractionOfFull` — see `reducedValue(fromFull:)`.
        public let reducedValue: Double?
        public let unit: String?
        /// Always `earnModeCreditFraction` in v1 — carried on the offer itself so a caller (shield
        /// copy, widget, the eventual Verification-layer integration above) never has to know this
        /// rule lives here rather than look it up separately.
        public let earnModeCreditFraction: Double
    }

    /// Produces today's Plan B offer for `goal`, or `nil` when `isHighRisk` is `false` — there is
    /// no Plan B to offer on a normal-risk day, only the regular adaptive plan from
    /// `AdaptiveGoalEngine.dailyPlan(for:on:)`.
    ///
    /// As a side effect, persists `reducedValue` onto today's `DailyPlan.planBValue` (spec §13 —
    /// that column exists exactly for this) via `AdaptiveGoalEngine`'s internal
    /// `setPlanBValue(_:on:)` hook, so shield/widget copy and the eventual Verification-layer
    /// integration (see this file's header TODO) can read the offer back from the persisted plan
    /// alone, without needing to recompute or re-call this function. Reuses
    /// `AdaptiveGoalEngine.dailyPlan(for:on:)` for "today's plan" (rather than recomputing the
    /// adaptive target independently) so a Plan B reduction is always relative to the *actual* bar
    /// the user is looking at today (spec §8 rule 1's engineered early wins, §9.1's difficulty
    /// steps included) — never a second, drifting notion of "today's goal."
    ///
    /// - Parameters:
    ///   - goal: The goal to offer a reduced version of.
    ///   - date: Defaults to now; normalized to the local calendar day the same way
    ///     `AdaptiveGoalEngine.dailyPlan(for:on:)` does.
    ///   - isHighRisk: The Slip Prediction signal (spec §9.2). The real model is Session
    ///     12/out of scope here — this takes the already-decided `Bool`, per this task's scope.
    @discardableResult
    public static func offer(for goal: Goal, on date: Date = .now, isHighRisk: Bool) async -> Offer? {
        guard isHighRisk else { return nil }

        let plan = await AdaptiveGoalEngine.shared.dailyPlan(for: goal, on: date)
        let full = plan.plannedValue ?? goal.targetValue
        let reduced = reducedValue(fromFull: full)

        await AdaptiveGoalEngine.shared.setPlanBValue(reduced, on: plan)

        return Offer(
            goalID: goal.id,
            date: plan.date,
            fullValue: full,
            reducedValue: reduced,
            unit: goal.unit,
            earnModeCreditFraction: earnModeCreditFraction
        )
    }

    /// Pure math half of `offer(for:on:isHighRisk:)`, for callers that already have a full value
    /// in hand (e.g. previewing what a Plan B offer *would* look like in shield/widget copy
    /// without the `AdaptiveGoalEngine` round-trip or a SwiftData write). `nil`/non-positive input
    /// passes through unchanged — there's nothing meaningful to reduce.
    public static func reducedValue(fromFull fullValue: Double?) -> Double? {
        guard let fullValue, fullValue > 0 else { return fullValue }
        let reduced = fullValue * reducedTargetFraction
        let floor = fullValue * minimumFractionOfFull
        return max(floor, reduced)
    }

    // MARK: - Earn Mode credit

    /// How many Earn Mode minutes a completed Plan B goal deposits, given the goal type's normal
    /// (full-credit) minute value for one completion (spec §5.2 — e.g. a gym session = 90 min, a
    /// focus block = 30 min; that per-goal-type earn-rate table isn't owned by this file — see
    /// this file's header TODO for the integration point that has it). Always
    /// `earnModeCreditFraction` of the full amount, floored to a whole minute (not rounded) so a
    /// small goal's Plan B credit is never silently rounded *up* past what "half credit" actually
    /// means, and never negative for a nonsensical negative input.
    public static func earnModeMinutes(forFullMinutes fullMinutes: Int) -> Int {
        guard fullMinutes > 0 else { return 0 }
        return max(0, Int((Double(fullMinutes) * earnModeCreditFraction).rounded(.down)))
    }

    // MARK: - Accepting and counting Plan B (Today's suggestion card, Wave 2F)
    //
    // The user taps "Switch to Plan B" on Today: `accept(_:on:)` persists the reduced target
    // (`offer(for:on:isHighRisk:)` with `isHighRisk: true` -- the user saying "rough day" is the
    // spec's own second trigger) and remembers the choice for the day. Once the verified amount
    // reaches the reduced target, `recordCompletion(goalID:verifiedAmount:on:)` writes one verified
    // `.planB` event and hands it to `GoalCompletionCoordinator`, which already pays half Earn Mode
    // credit for `.planB` (`PlanB.earnModeMinutes`) and ends a lock whose goals are all verified.

    /// App Group defaults, same suite every retention engine uses. Keyed distinctly.
    private static let acceptanceDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let acceptedKey = "com.zano.app.planB.accepted.v1"

    /// Switches today's plan for `goal` to Plan B. Returns the persisted offer (`nil` only if the
    /// goal has no numeric target to reduce; the choice is still remembered either way).
    @discardableResult
    public static func accept(_ goal: Goal, on date: Date = .now) async -> Offer? {
        let offer = await offer(for: goal, on: date, isHighRisk: true)
        markAccepted(goalID: goal.id, on: date)
        return offer
    }

    /// Whether the user switched `goalID` to Plan B on `date`'s local day.
    public static func isAccepted(goalID: UUID, on date: Date = .now) -> Bool {
        acceptedEntries().contains(entry(goalID: goalID, on: date))
    }

    /// Writes one verified `.planB` completion for `goalID` today and runs the coordinator. The
    /// caller passes an amount that is already verified (logged grams/ml, Health steps/workout
    /// minutes, gym dwell minutes); this only records it. No-op when the goal already has a verified
    /// completion today, so a double tap never writes two.
    ///
    /// - Returns: `true` if a Plan B completion was written.
    @discardableResult
    public static func recordCompletion(
        goalID: UUID,
        verifiedAmount: Double?,
        on date: Date = .now
    ) async throws -> Bool {
        let context = ModelContext(ModelContainer.appGroup)
        var goalDescriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == goalID })
        goalDescriptor.fetchLimit = 1
        guard let goal = try context.fetch(goalDescriptor).first else { return false }

        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let eventDescriptor = FetchDescriptor<GoalEvent>(predicate: #Predicate { $0.ts >= start && $0.ts < end })
        let todays = try context.fetch(eventDescriptor).filter { $0.goal?.id == goalID }
        guard !todays.contains(where: GoalDayProgress.isVerifiedCompletion) else { return false }

        var meta: [String: JSONValue] = ["planB": .bool(true)]
        if let verifiedAmount { meta["verifiedAmount"] = .number(verifiedAmount) }
        // `value: nil` so the amount already logged by other events isn't counted twice.
        let event = GoalEvent(
            ts: date,
            kind: .planB,
            value: nil,
            source: .manual,
            verified: true,
            meta: .object(meta),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        try context.save()
        await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID, at: date)
        return true
    }

    private static func entry(goalID: UUID, on date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return "\(goalID.uuidString)|\(Int(day.timeIntervalSince1970))"
    }

    private static func acceptedEntries() -> [String] {
        acceptanceDefaults.stringArray(forKey: acceptedKey) ?? []
    }

    /// Keeps a week of entries; older ones are pruned on each write.
    private static func markAccepted(goalID: UUID, on date: Date) {
        let newEntry = entry(goalID: goalID, on: date)
        let cutoff = Calendar.current.startOfDay(for: date).addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        var entries = acceptedEntries().filter { item in
            guard let stamp = item.split(separator: "|").last, let t = Double(stamp) else { return false }
            return t >= cutoff
        }
        guard !entries.contains(newEntry) else { return }
        entries.append(newEntry)
        acceptanceDefaults.set(entries, forKey: acceptedKey)
    }
}
