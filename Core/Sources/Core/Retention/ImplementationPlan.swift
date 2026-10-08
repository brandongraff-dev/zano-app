// Core/Sources/Core/Retention/ImplementationPlan.swift
//
// The onboarding "if-then plan" (implementation intention): "If it's Mon/Wed/Fri at 6 PM, I go to
// the gym." Research basis: Gollwitzer & Sheeran's meta-analysis (94 studies, d = 0.65), see
// docs/design/growth-and-ml-research.md item 2. Written once when the user commits on the plan
// step (`Screen10PlanReveal`), and read by three things that used to guess:
//   1. The default lock schedule (`LockSchedule.planAwareDefault`, below): which days the morning
//      lock runs and how early it starts, so it never fights the plan (a gym-only plan on Mon/Wed/
//      Fri must not keep apps locked until 23:59 on a rest day the user never planned to train).
//   2. `NudgeScheduler`: on a planned day, a reminder ~45 min before the planned time is one of
//      the bandit's arms, with a strong prior (the user told us when).
//   3. `SlipRisk`: planned vs unplanned day is a feature, and the onboarding "when do you slip"
//      answer is stored here as the cold-start prior.
//
// Storage: one small JSON blob in the App Group defaults (device-local, like `LockSchedule`). It
// holds goal types, weekdays and a minute of the day — nothing sensitive, and no Screen Time token.

import Foundation
import SwiftData

/// The user's "when will you do it?" answers, one entry per planned goal.
public struct ImplementationPlan: Codable, Sendable, Equatable {

    /// One "if it's <days> at <time>, I <do the goal>".
    public struct Entry: Codable, Sendable, Equatable, Hashable {
        public var goalType: GoalType
        /// `Calendar` numbering: 1 = Sunday ... 7 = Saturday. Never empty for a valid entry.
        public var weekdays: Set<Int>
        /// Minutes after local midnight.
        public var minuteOfDay: Int

        public init(goalType: GoalType, weekdays: Set<Int>, minuteOfDay: Int) {
            self.goalType = goalType
            self.weekdays = weekdays.filter { (1...7).contains($0) }
            self.minuteOfDay = min(max(0, minuteOfDay), LockSchedule.endOfDayMinute)
        }

        public var isEveryDay: Bool { weekdays == LockSchedule.allWeekdays }

        public func isPlanned(on date: Date, calendar: Calendar = .current) -> Bool {
            weekdays.contains(calendar.component(.weekday, from: date))
        }
    }

    public var entries: [Entry]
    /// The onboarding "when do you usually slip?" answer (`FallOffPattern.rawValue`), if any. Only
    /// `SlipRisk` reads it, as a prior.
    public var slipPatternRaw: String?
    public var createdAt: Date

    public init(entries: [Entry], slipPatternRaw: String? = nil, createdAt: Date = .now) {
        self.entries = entries.filter { !$0.weekdays.isEmpty }
        self.slipPatternRaw = slipPatternRaw
        self.createdAt = createdAt
    }

    // MARK: Queries

    /// Entries planned on `date`'s weekday, earliest first.
    public func entries(on date: Date, calendar: Calendar = .current) -> [Entry] {
        entries.filter { $0.isPlanned(on: date, calendar: calendar) }.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    /// Whether anything is planned on `date`'s weekday.
    public func isPlannedDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        !entries(on: date, calendar: calendar).isEmpty
    }

    /// The earliest planned minute on `date`, or `nil` when nothing is planned that day.
    public func earliestMinute(on date: Date, calendar: Calendar = .current) -> Int? {
        entries(on: date, calendar: calendar).first?.minuteOfDay
    }

    /// The days anything is planned, across all entries.
    public var plannedWeekdays: Set<Int> {
        entries.reduce(into: Set<Int>()) { $0.formUnion($1.weekdays) }
    }

    // MARK: Defaults for the onboarding picker

    /// Default gym days for a weekly workout target, spread across the week so rest days fall in
    /// between: 1 → Mon, 2 → Mon/Thu, 3 → Mon/Wed/Fri, 4 → Mon/Tue/Thu/Fri, 5 → Mon–Fri,
    /// 6 → Mon–Sat, 7 → every day.
    public static func defaultWorkoutDays(perWeek: Int) -> Set<Int> {
        switch min(max(perWeek, 1), 7) {
        case 1: [2]
        case 2: [2, 5]
        case 3: [2, 4, 6]
        case 4: [2, 3, 5, 6]
        case 5: [2, 3, 4, 5, 6]
        case 6: [2, 3, 4, 5, 6, 7]
        default: LockSchedule.allWeekdays
        }
    }

    /// 6:00 PM: the most common gym time, and late enough that a morning lock is earned by it.
    public static let defaultWorkoutMinute = 18 * 60
    /// 9:00 AM: start of a work or school block.
    public static let defaultFocusMinute = 9 * 60

    // MARK: Persistence (App Group)

    private static let key = "zano.implementationPlan.v1"

    /// The saved plan, or `nil` before onboarding's plan step committed one.
    public static var current: ImplementationPlan? {
        get { load(from: SharedDefaults.store) }
        set { save(newValue, to: SharedDefaults.store) }
    }

    /// Injectable for tests.
    public static func load(from defaults: UserDefaults) -> ImplementationPlan? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ImplementationPlan.self, from: data)
    }

    public static func save(_ plan: ImplementationPlan?, to defaults: UserDefaults) {
        guard let plan, let data = try? JSONEncoder().encode(plan) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Plan-aware default lock schedule

extension LockSchedule {
    /// How long before the earliest planned time the morning lock starts, when that time is
    /// earlier than the usual 7:00 start (so the plan "earns" the day instead of finishing before
    /// the lock even begins).
    public static let planLeadMinutes = 60

    /// The schedule seeded for the default lock set on the first foreground after onboarding.
    /// Replaces `morningDefault` there (through `seededDefault(lockSetID:)`, below): same "until your
    /// goals are done" window, but shaped by the if-then plan so it doesn't fight it:
    ///   - Days: every day, unless the only planned goal is the gym on specific days — then just
    ///     those days. A rest day the user never planned to train is not a locked day.
    ///   - Start: 7:00, or `planLeadMinutes` before the earliest planned time when that is earlier
    ///     (a 6 AM gym plan locks from 5 AM), rounded down to a quarter hour.
    /// No plan (or an empty one) gives exactly `morningDefault`.
    ///
    /// - Parameter activeGoalTypes: the types of the user's active daily goals, when known. The
    ///   gym-days narrowing only applies when every one of them is in the plan with specific days
    ///   (a protein goal with no planned time still needs locking every day).
    public static func planAwareDefault(
        lockSetID: UUID,
        plan: ImplementationPlan?,
        activeGoalTypes: Set<GoalType>? = nil,
        mode: LockMode = LockPreferences.defaultMode
    ) -> LockSchedule {
        var schedule = morningDefault(lockSetID: lockSetID, mode: mode)
        guard let plan, !plan.entries.isEmpty else { return schedule }

        let plannedTypes = Set(plan.entries.map(\.goalType))
        let goalTypes = activeGoalTypes ?? plannedTypes
        let everyGoalPlanned = goalTypes.isSubset(of: plannedTypes)
        let everyEntryHasDays = plan.entries.allSatisfy { !$0.isEveryDay }
        if everyGoalPlanned, everyEntryHasDays {
            schedule.weekdays = plan.plannedWeekdays
        }

        if let earliest = plan.entries.map(\.minuteOfDay).min() {
            let lead = earliest - planLeadMinutes
            if lead < schedule.startMinuteOfDay {
                schedule.startMinuteOfDay = max(0, lead - lead % 15)
            }
        }
        if schedule.validate() != nil { return morningDefault(lockSetID: lockSetID, mode: mode) }
        return schedule
    }
}

extension LockSchedule {
    /// `planAwareDefault` for the saved plan and the local user's active daily goals — what the
    /// app seeds once, on the first foreground after onboarding (the `ContentView` hook). Reads
    /// SwiftData in its own context; types are compared in Swift, never in a predicate.
    @MainActor
    public static func seededDefault(
        lockSetID: UUID,
        plan: ImplementationPlan? = ImplementationPlan.current,
        modelContainer: ModelContainer = .appGroup
    ) -> LockSchedule {
        let context = ModelContext(modelContainer)
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        var types: Set<GoalType>?
        if let userID = (try? context.fetch(userDescriptor))?.first?.id,
           let goals = try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active == true })) {
            let daily = goals
                .filter { $0.user?.id == userID }
                .filter { !($0.cadence?.lowercased().contains("week") ?? false) }
            if !daily.isEmpty { types = Set(daily.map(\.type)) }
        }
        return planAwareDefault(lockSetID: lockSetID, plan: plan, activeGoalTypes: types)
    }
}
