// Core/Sources/Core/Retention/SlipRisk.swift
//
// On-device slip-risk score (docs/spec.md §9.2 Slip Prediction; research item 4 "lite" in
// docs/design/growth-and-ml-research.md): the probability that the user misses every goal today.
// The spec's server LightGBM model needs data that doesn't exist yet, so v1 is a logistic score
// with HAND-SET weights over features the device already has. Two decisions use it:
//   1. `NudgeScheduler` only sends the evening streak-at-risk nudge when the score is at least
//      `streakNudgeThreshold` (spec §8 rule 7: a nudge must change what the user does tonight).
//   2. `isHighRisk(_:)` → Today offers Plan B earlier (`planBOfferHour(on:)`, noon instead of
//      5 PM). Spec §9.2 "risk > threshold → offer Plan B".
//
// Features (all as of "now"; the score is for today):
//   - weekend (Sat/Sun)                          +0.35  (+0.60 more if the user said they slip on weekends)
//   - Monday                                     -0.20  (fresh-start effect, spec §8 rule 6)
//   - days since the last earned unlock, beyond 1  +0.35 per day, capped at 6 extra days
//   - streak length                              -0.35 × ln(1 + streak)
//   - streak ≥ 3 and the user said "after a few good days"   +0.50
//   - today is a planned day (if-then plan)      -0.40   ·  unplanned day with a plan  +0.20
//   - yesterday slipped (Never Miss Twice armed) +0.80
//   - Plan B used in the last 3 days             +0.40
//   - bias                                       -1.40   (≈ 0.20 for a typical user)
// Worked examples (see SlipRiskTests): a 5-day streak on a planned weekday ≈ 0.08; a slip
// yesterday, no streak and a recent Plan B ≈ 0.54 (high risk). Replace the weights with fitted
// ones once `goal_events` has volume (spec §9.9) — keep inference on device.
//
// Inputs come from the App Group only (`SharedDefaults`, `LockEngineSharedState`, the plan, and a
// small `Signals` cache), so `score(for:)` is cheap and safe from any process. The cache holds what
// needs SwiftData (the last Plan B day), refreshed by `refreshSignals(...)` on app foreground
// (called from `NudgeScheduler.reschedule()`, which already runs on every foreground).

import Foundation
import SwiftData
import os

/// The feature vector, as plain values so the score is a pure function.
public struct SlipRiskFeatures: Sendable, Equatable {
    /// `Calendar` weekday, 1 = Sunday ... 7 = Saturday.
    public var weekday: Int
    /// Whole days since the last earned unlock (0 = earned today). `nil` = never earned.
    public var daysSinceLastEarned: Int?
    public var streak: Int
    /// `nil` when there is no if-then plan; otherwise whether today is one of its days.
    public var isPlannedDay: Bool?
    public var yesterdayMissed: Bool
    public var planBUsedRecently: Bool
    /// `ImplementationPlan.slipPatternRaw` (onboarding's "when do you slip?").
    public var slipPatternRaw: String?

    public init(
        weekday: Int,
        daysSinceLastEarned: Int? = 1,
        streak: Int = 0,
        isPlannedDay: Bool? = nil,
        yesterdayMissed: Bool = false,
        planBUsedRecently: Bool = false,
        slipPatternRaw: String? = nil
    ) {
        self.weekday = weekday
        self.daysSinceLastEarned = daysSinceLastEarned
        self.streak = streak
        self.isPlannedDay = isPlannedDay
        self.yesterdayMissed = yesterdayMissed
        self.planBUsedRecently = planBUsedRecently
        self.slipPatternRaw = slipPatternRaw
    }
}

public enum SlipRisk {

    // MARK: Weights (hand-set; see file header)

    public enum Weights {
        public static let bias = -1.4
        public static let weekend = 0.35
        public static let weekendPrior = 0.6
        public static let monday = -0.2
        public static let perDaySinceEarned = 0.35
        public static let maxExtraDaysSinceEarned = 6
        public static let streakLog = -0.35
        public static let afterGoodDaysPrior = 0.5
        public static let afterGoodDaysStreak = 3
        public static let plannedDay = -0.4
        public static let unplannedDay = 0.2
        public static let yesterdayMissed = 0.8
        public static let planBRecently = 0.4
        /// A user who has never earned an unlock counts as this many days since one.
        public static let neverEarnedDays = 2
    }

    /// At or above this, the evening streak-at-risk nudge is worth sending.
    public static let streakNudgeThreshold = 0.30
    /// At or above this, today is high-risk: Plan B is offered early.
    public static let highRiskThreshold = 0.50
    /// "Recently" for Plan B use.
    public static let planBRecentDays = 3
    /// Today's usual Plan B offer hour, and the earlier one on a high-risk day.
    public static let normalPlanBOfferHour = 17
    public static let highRiskPlanBOfferHour = 12
    /// Written to `RiskScore.modelVersion` so later models can tell these apart.
    public static let modelVersion = "logreg-handset-1"

    // MARK: Pure score

    /// Logistic score in 0...1.
    public static func score(_ f: SlipRiskFeatures) -> Double {
        var z = Weights.bias
        let isWeekend = f.weekday == 1 || f.weekday == 7
        if isWeekend {
            z += Weights.weekend
            if f.slipPatternRaw == "weekends" { z += Weights.weekendPrior }
        }
        if f.weekday == 2 { z += Weights.monday }

        let days = f.daysSinceLastEarned ?? Weights.neverEarnedDays
        let extraDays = min(max(0, days - 1), Weights.maxExtraDaysSinceEarned)
        z += Weights.perDaySinceEarned * Double(extraDays)

        let streak = max(0, f.streak)
        z += Weights.streakLog * log(1 + Double(streak))
        if f.slipPatternRaw == "afterGoodDays", streak >= Weights.afterGoodDaysStreak {
            z += Weights.afterGoodDaysPrior
        }

        switch f.isPlannedDay {
        case .some(true): z += Weights.plannedDay
        case .some(false): z += Weights.unplannedDay
        case .none: break
        }
        if f.yesterdayMissed { z += Weights.yesterdayMissed }
        if f.planBUsedRecently { z += Weights.planBRecently }
        return 1 / (1 + exp(-z))
    }

    public static func isHighRisk(score: Double) -> Bool { score >= highRiskThreshold }

    // MARK: App Group reads

    /// Today's score from App Group state (cheap; any process). `date` picks the weekday and the
    /// plan day; the rest of the features are "as of now".
    public static func score(for date: Date, calendar: Calendar = .current) -> Double {
        score(features(for: date, calendar: calendar))
    }

    /// Spec §9.2's "risk > threshold → offer Plan B". Today's hook: Today's Plan B card.
    public static func isHighRisk(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        isHighRisk(score: score(for: date, calendar: calendar))
    }

    /// The hour from which Today offers Plan B: noon on a high-risk day, 5 PM otherwise.
    public static func planBOfferHour(on date: Date = .now, calendar: Calendar = .current) -> Int {
        isHighRisk(date, calendar: calendar) ? highRiskPlanBOfferHour : normalPlanBOfferHour
    }

    /// Builds today's features from the App Group.
    public static func features(
        for date: Date,
        calendar: Calendar = .current,
        plan: ImplementationPlan? = ImplementationPlan.current,
        signals: Signals = Signals.current
    ) -> SlipRiskFeatures {
        let today = calendar.startOfDay(for: date)
        let lastEarned = [LockEngineSharedState.lastEarnedUnlockAt, signals.lastEarnedDay].compactMap { $0 }.max()
        let daysSince = lastEarned.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day
        }.map { max(0, $0) }
        let planBRecent = signals.lastPlanBDay.map { day -> Bool in
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: today).day ?? Int.max
            return gap >= 0 && gap < planBRecentDays
        } ?? false
        return SlipRiskFeatures(
            weekday: calendar.component(.weekday, from: date),
            daysSinceLastEarned: daysSince,
            streak: SharedDefaults.currentStreak,
            isPlannedDay: plan.map { $0.isPlannedDay(date, calendar: calendar) },
            yesterdayMissed: SharedDefaults.neverMissTwiceArmed,
            planBUsedRecently: planBRecent,
            slipPatternRaw: plan?.slipPatternRaw
        )
    }

    // MARK: Signals cache (what needs SwiftData)

    public struct Signals: Codable, Sendable, Equatable {
        public var lastPlanBDay: Date?
        public var lastEarnedDay: Date?

        public init(lastPlanBDay: Date? = nil, lastEarnedDay: Date? = nil) {
            self.lastPlanBDay = lastPlanBDay
            self.lastEarnedDay = lastEarnedDay
        }

        private static let key = "zano.slipRisk.signals.v1"

        public static var current: Signals {
            get {
                guard let data = SharedDefaults.store.data(forKey: key),
                      let value = try? JSONDecoder().decode(Signals.self, from: data) else { return Signals() }
                return value
            }
            set {
                if let data = try? JSONEncoder().encode(newValue) { SharedDefaults.store.set(data, forKey: key) }
            }
        }
    }

    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "SlipRisk")

    /// Reads the last Plan B day and last earned day from SwiftData into `Signals.current`, and
    /// records today's score as a `RiskScore` row (once per day) so a later model has history.
    /// Reads in one context, writes in a fresh one.
    @MainActor
    public static func refreshSignals(modelContainer: ModelContainer = .appGroup, now: Date = .now, calendar: Calendar = .current) {
        let context = ModelContext(modelContainer)
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        guard let userID = (try? context.fetch(userDescriptor))?.first?.id else { return }

        let since = calendar.date(byAdding: .day, value: -planBRecentDays, to: calendar.startOfDay(for: now)) ?? now
        // Dates only in the predicate; the enum kind and the user relationship are checked in Swift.
        let recent = (try? context.fetch(FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.ts >= since && $0.verified == true }
        ))) ?? []
        let lastPlanB = recent
            .filter { $0.kind == .planB && $0.user?.id == userID }
            .map(\.ts)
            .max()

        var streakDescriptor = FetchDescriptor<Streak>(predicate: #Predicate<Streak> { $0.userID == userID })
        streakDescriptor.fetchLimit = 1
        let lastEarned = (try? context.fetch(streakDescriptor))?.first?.lastEarnedDate

        var signals = Signals.current
        if let lastPlanB { signals.lastPlanBDay = max(lastPlanB, signals.lastPlanBDay ?? .distantPast) }
        if let lastEarned { signals.lastEarnedDay = lastEarned }
        Signals.current = signals

        recordTodayScore(userID: userID, modelContainer: modelContainer, now: now, calendar: calendar)
    }

    @MainActor
    private static func recordTodayScore(userID: UUID, modelContainer: ModelContainer, now: Date, calendar: Calendar) {
        let context = ModelContext(modelContainer)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        var descriptor = FetchDescriptor<RiskScore>(
            predicate: #Predicate<RiskScore> { $0.userID == userID && $0.date >= start && $0.date < end }
        )
        descriptor.fetchLimit = 1
        let p = score(for: now, calendar: calendar)
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.pMiss = p
                existing.modelVersion = modelVersion
            } else {
                context.insert(RiskScore(userID: userID, date: start, pMiss: p, modelVersion: modelVersion))
            }
            try context.save()
        } catch {
            logger.error("Could not record today's risk score: \(String(describing: error), privacy: .public)")
        }
    }
}
