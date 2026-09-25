// GoalCatalog.swift
// App / Features / Goals / Model
//
// What the app knows about each goal type when adding or editing one: its picker group, its
// verification tier, its target rule, and the one setup step it needs to verify. docs/spec.md §3
// (goal catalog and tiers A/B/C), §8 rule 1 (start small), §24 (ADDITIVE goals only — every type
// here is "do more of something good"; there is no calorie ceiling, weight target, or fasting type,
// and a custom goal's name is checked for those too).

import Foundation
import SwiftData
import Core

// MARK: - Groups

enum GoalCategory: String, CaseIterable, Identifiable {
    case move, fuel, mind, mornings, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: Copy.goals.categoryMove
        case .fuel: Copy.goals.categoryFuel
        case .mind: Copy.goals.categoryMind
        case .mornings: Copy.goals.categoryMornings
        case .custom: Copy.goals.categoryCustom
        }
    }

    /// Picker order within the group.
    var types: [GoalType] {
        switch self {
        case .move: [.workoutGym, .workoutHomeOutdoor, .steps, .stretchMobility]
        case .fuel: [.protein, .water, .creatine, .mealPrep]
        case .mind: [.focusSession, .reading]
        case .mornings: [.sunriseAlarm, .sleepOnTime, .coldShowerSauna]
        case .custom: [.custom]
        }
    }
}

// MARK: - Setup

/// The one thing a goal type needs set up before it can verify itself.
enum GoalSetupStep: String, Identifiable {
    /// A saved gym (geofence) — `GymSetupView`.
    case gym
    /// A mapped NFC tag — `NFCTagsView`.
    case tag
    /// Apple Health read access — `HealthPermissionPrimer`.
    case health

    var id: String { rawValue }
}

enum GoalCatalog {
    /// Every goal type can be added (all are additive; `GoalCategory.types` lists each once).
    /// Only `custom` can be on the plan more than once.
    static func allowsMultiple(_ type: GoalType) -> Bool { type == .custom }

    /// Spec §3's tier for each type.
    static func tier(for type: GoalType) -> VerificationTier {
        switch type {
        case .workoutGym, .workoutHomeOutdoor, .focusSession, .steps, .sunriseAlarm, .sleepOnTime: .a
        case .protein, .water, .creatine, .reading, .mealPrep, .stretchMobility: .b
        case .coldShowerSauna, .custom: .c
        }
    }

    static func tierSymbol(for tier: VerificationTier) -> String {
        switch tier {
        case .a: "checkmark.seal.fill"
        case .b: "hand.tap.fill"
        case .c: "hand.raised.fill"
        }
    }

    /// Meal prep is weekly (spec §3 "Weekly only"); everything else is daily. Workouts store a
    /// weekly count with `cadence: "daily"`, mirroring onboarding's Plan Reveal as-is.
    static func cadence(for type: GoalType) -> String {
        type == .mealPrep ? "weekly" : "daily"
    }

    static func setupStep(for type: GoalType) -> GoalSetupStep? {
        switch type {
        case .workoutGym: .gym
        case .workoutHomeOutdoor, .steps, .sleepOnTime: .health
        case .protein, .water, .creatine, .sunriseAlarm: .tag
        case .focusSession, .reading, .mealPrep, .stretchMobility, .coldShowerSauna, .custom: nil
        }
    }

    /// Whether the goal can't verify at all without its setup step. A tag is optional for protein,
    /// water, and creatine (one tap logs them too) but is how the Sunrise Alarm turns off.
    static func setupIsRequired(for type: GoalType) -> Bool {
        switch setupStep(for: type) {
        case .gym, .health: true
        case .tag: type == .sunriseAlarm
        case nil: false
        }
    }

    /// Words that make a custom goal restrictive (spec §24). A heuristic, not a filter to argue
    /// with: it only blocks the obvious "eat less" goals. Identifiers, not copy.
    private static let restrictivePhrases = [
        "calorie", "kcal", "fasting", "intermittent", "lose weight", "weight loss", "lose fat",
        "eat less", "diet", "skip meal", "skip breakfast", "skip lunch", "skip dinner", "starve",
        "purge", "no food", "no carbs", "no sugar", "cut weight",
    ]
    private static let restrictiveWords: Set<String> = ["fast", "cals", "weigh"]

    static func isRestrictive(customTitle: String) -> Bool {
        let lower = customTitle.lowercased()
        if restrictivePhrases.contains(where: { lower.contains($0) }) { return true }
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: restrictiveWords.contains)
    }
}

// MARK: - Target rules

/// Sensible target bounds, step, default, and quick presets per goal type, in the units the rest
/// of the app reads (`Goal.unit`: "workouts", "min", "g", "ml", "steps"). A type with no numeric
/// target is binary: done once logged or verified (`GoalDayProgress`). Values are identifiers
/// and numbers, not copy.
struct GoalTargetRule {
    let range: ClosedRange<Int>
    let step: Int
    let defaultValue: Int
    let presets: [Int]
    let unit: String?
    /// `false` for binary goals (creatine, cold shower, custom, …): stored with `targetValue: nil`.
    let hasTarget: Bool

    init(type: GoalType, unit: String?) {
        switch type {
        case .workoutGym, .workoutHomeOutdoor:
            // Workouts per week (onboarding's Q4 target).
            self.init(range: 1...7, step: 1, defaultValue: 3, presets: [2, 3, 4, 5], unit: "workouts")
        case .focusSession:
            // Minutes; 25 matches onboarding's `FocusSessionPreset.twentyFiveMinutes`.
            self.init(range: 5...180, step: 5, defaultValue: 25, presets: [25, 50, 90], unit: "min")
        case .protein:
            // Grams a day; 120 matches onboarding's placeholder baseline.
            self.init(range: 20...300, step: 5, defaultValue: 120, presets: [100, 120, 150, 180], unit: "g")
        case .steps:
            self.init(range: 1_000...30_000, step: 500, defaultValue: 8_000, presets: [6_000, 8_000, 10_000], unit: "steps")
        case .water where unit == "oz":
            self.init(range: 8...200, step: 8, defaultValue: 64, presets: [48, 64, 96], unit: "oz")
        case .water:
            // Millilitres: the water intents, widgets, and NFC tags all log ml.
            self.init(range: 250...5_000, step: 250, defaultValue: 2_000, presets: [1_500, 2_000, 3_000], unit: unit ?? "ml")
        default:
            self.init(range: 1...999, step: 1, defaultValue: 1, presets: [], unit: unit, hasTarget: false)
        }
    }

    private init(
        range: ClosedRange<Int>, step: Int, defaultValue: Int, presets: [Int], unit: String?, hasTarget: Bool = true
    ) {
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.presets = presets
        self.unit = unit
        self.hasTarget = hasTarget
    }

    func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Creation

@MainActor
enum GoalCreation {
    /// Adds a goal of `type` for `user`, the way onboarding's Plan Reveal does (same titles,
    /// units, cadence, tiers). A non-custom type reactivates the newest inactive goal of that type
    /// (keeping its history) with the chosen target instead of creating a duplicate row.
    ///
    /// - Throws: the `ModelContext.save()` error. The caller shows the save-failed alert.
    static func add(
        type: GoalType,
        target: Int?,
        customTitle: String?,
        user: User,
        existingGoals: [Goal],
        in context: ModelContext
    ) throws -> Goal {
        let rule = GoalTargetRule(type: type, unit: nil)
        let targetValue = rule.hasTarget ? Double(rule.clamped(target ?? rule.defaultValue)) : nil

        let goal: Goal
        if !GoalCatalog.allowsMultiple(type),
           let previous = existingGoals.last(where: { $0.type == type && !$0.active && $0.user?.id == user.id }) {
            previous.active = true
            if let targetValue, previous.unit == rule.unit {
                previous.targetValue = targetValue
            }
            goal = previous
        } else {
            let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            goal = Goal(
                type: type,
                title: type == .custom && !trimmed.isEmpty ? trimmed : Copy.onboarding.planGoalTitle(for: type),
                targetValue: targetValue,
                unit: rule.unit,
                cadence: GoalCatalog.cadence(for: type),
                verificationTier: GoalCatalog.tier(for: type),
                user: user
            )
            context.insert(goal)
        }
        try context.save()
        Analytics.shared.capture(event: "goal_added", properties: ["type": type.rawValue])
        GoalVerificationStarter.startIfReady(goalID: goal.id, type: type)
        return goal
    }
}

// MARK: - Starting verifiers

/// Starts the Core verifier a new goal needs, where that is safe to do from here. Only steps has
/// a start/observe API today (`StepsVerifier.startObserving`), and only once Health has been asked;
/// home workouts and sleep are checked by Today (`HomeWorkoutVerifier.verify`), gym by geofence.
enum GoalVerificationStarter {
    static func startIfReady(goalID: UUID, type: GoalType) {
        guard type == .steps else { return }
        Task {
            guard await HealthAuthorization.hasRequestedRead(for: [.steps]) else { return }
            try? await StepsVerifier.shared.startObserving(goalID: goalID)
        }
    }
}

// MARK: - Setup status

/// Which setup steps are already done, for the editor's "Set up" affordances and the picker's
/// next step. Gyms come from SwiftData (`Gym.confirmed`); tags and Health are loaded async.
struct GoalSetupStatus: Equatable {
    var hasConfirmedGym = false
    var mappedTagTypes: Set<GoalType> = []
    var healthRequestedTypes: Set<GoalType> = []

    func isMissing(for type: GoalType) -> Bool {
        switch GoalCatalog.setupStep(for: type) {
        case .gym: !hasConfirmedGym
        case .tag: !mappedTagTypes.contains(type)
        case .health: !healthRequestedTypes.contains(type)
        case nil: false
        }
    }

    /// Loads the async parts for `types` (tag mappings from `NFCTagMapper`, Health request status).
    static func load(for types: [GoalType], hasConfirmedGym: Bool) async -> GoalSetupStatus {
        var status = GoalSetupStatus(hasConfirmedGym: hasConfirmedGym)
        let wanted = Set(types)

        if wanted.contains(where: { GoalCatalog.setupStep(for: $0) == .tag }) {
            status.mappedTagTypes = await mappedTagGoalTypes()
        }
        for type in wanted where GoalCatalog.setupStep(for: type) == .health {
            if await HealthAuthorization.hasRequestedRead(for: [type]) {
                status.healthRequestedTypes.insert(type)
            }
        }
        return status
    }

    /// Goal types that at least one saved tag logs. `if case` rather than a `switch` so a new
    /// `NFCTagAction` case doesn't break this.
    static func mappedTagGoalTypes() async -> Set<GoalType> {
        var types = Set<GoalType>()
        for mapping in await NFCTagMapper.shared.allMappings() {
            if case .logWater = mapping.action { types.insert(.water) }
            if case .logProtein = mapping.action { types.insert(.protein) }
            if case .logCreatine = mapping.action { types.insert(.creatine) }
            if case .sunriseKey = mapping.action { types.insert(.sunriseAlarm) }
        }
        return types
    }
}
