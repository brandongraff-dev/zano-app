// Core/Sources/Core/LockEngine/GoalDayProgress.swift
//
// One rule for "how far along is this goal today", shared by the UI (Today, Lock) and the engine
// (`GoalCompletionCoordinator`, `LockEngineManager.isGoalVerified`). docs/spec.md §2 ("Unlock: when
// all required goals for the current lock are verified") and §3 (protein/water are logged in
// amounts, a goal is met when the day's amount reaches the target). Before this lived in
// `App/ZANO/Features/Today/TodayView.swift`, so the UI could call a goal done while the engine
// (which only read `.complete` events) disagreed.

import Foundation

/// A goal's progress for today.
///
/// A goal with no numeric target (a dwell-based workout, creatine, a custom goal) is binary: done
/// once a verified completion (`.complete`, `.planB`, `.freeze`) or a verified `.verify` lands.
///
/// A numeric goal (protein g, water ml, focus min, steps) is done when the verified logged amount
/// reaches the target, on a verified completion, or on a verified `.verify` that carries no amount.
/// A `.verify` *with* an amount is a log (protein and water intents write `.verify` + grams/ml), so
/// one +25g doesn't mark a 150g goal done. Unverified events (a duplicate NFC tap, a focus session
/// that ended early) never count.
public struct GoalDayProgress: Sendable, Equatable {
    /// `0...1`.
    public let fraction: Double
    /// Logged amount so far (numeric goals only). Never shown below the target once the goal is
    /// complete, so a ring can't read "0 of 35 min" while full.
    public let current: Int?
    /// Target amount (numeric goals only).
    public let target: Int?
    public let unit: String
    /// The unrounded verified amount logged today (0 for binary goals).
    public let loggedAmount: Double

    public var isComplete: Bool { fraction >= 1 }
    public var hasStarted: Bool { fraction > 0 }

    /// - Parameters:
    ///   - todaysEvents: this goal's events for the day (callers filter by goal and day).
    ///   - plannedValue: today's `DailyPlan.plannedValue`, which overrides `goal.targetValue`.
    public init(goal: Goal, todaysEvents events: [GoalEvent], plannedValue: Double?) {
        self.init(targetValue: plannedValue ?? goal.targetValue, unit: goal.unit, events: events)
    }

    init(targetValue: Double?, unit goalUnit: String?, events: [GoalEvent]) {
        let hasVerifiedCompletion = events.contains(where: Self.isVerifiedCompletion)

        guard let targetValue, targetValue > 0 else {
            let done = hasVerifiedCompletion || events.contains { $0.verified && $0.kind == .verify }
            fraction = done ? 1 : 0
            current = nil
            target = nil
            unit = ""
            loggedAmount = 0
            return
        }

        let hasCompletion = hasVerifiedCompletion
            || events.contains { $0.verified && $0.kind == .verify && $0.value == nil }
        let logged = events
            .filter(Self.countsTowardAmount)
            .compactMap(\.value)
            .reduce(0, +)
        let targetInt = Int(targetValue.rounded())
        let loggedInt = Int(logged.rounded())
        fraction = hasCompletion ? 1 : min(1, logged / targetValue)
        current = hasCompletion ? max(loggedInt, targetInt) : loggedInt
        target = targetInt
        unit = goalUnit ?? ""
        loggedAmount = logged
    }

    /// The engine's definition of "this goal is verified for the day" (spec §2): a verified
    /// `.complete`, `.planB` (spec §5.5 Plan B still counts), or `.freeze` event.
    public static func isVerifiedCompletion(_ event: GoalEvent) -> Bool {
        event.verified && (event.kind == .complete || event.kind == .planB || event.kind == .freeze)
    }

    /// Whether an event's `value` adds to the day's logged amount. Misses and freezes never do.
    static func countsTowardAmount(_ event: GoalEvent) -> Bool {
        guard event.verified, event.value != nil else { return false }
        switch event.kind {
        case .log, .verify, .complete, .planB: return true
        case .miss, .freeze: return false
        }
    }
}
