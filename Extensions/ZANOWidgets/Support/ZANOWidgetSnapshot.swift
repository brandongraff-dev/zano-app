// ZANOWidgetSnapshot.swift
// Extensions/ZANOWidgets/Support
//
// Extension-only data types + loader for every ZANO widget/control/live-activity-adjacent
// timeline. Not shared with the main app (it belongs to the extension's own presentation layer,
// not Core), per this session's task: "Shared code goes ONLY in Core/Sources/Core/<Module>...
// Extension-only code in Extensions/<Name>/".
//
// docs/spec.md §6: Home Screen widgets need streak, lock status, 3 goal rings (protein/water/
// focus), Time Bank, and next lock time. §11/§27: "Timeline data reads App Group only, no
// networking" — this file only ever touches `SharedDefaults` (fast-path UserDefaults mirror) and
// a fresh, short-lived SwiftData `ModelContext` against `ModelContainer.appGroup`, both of which
// live inside the App Group container. It never imports Foundation networking types.

import Foundation
import SwiftData
import Core

/// One day's progress toward a single ring/goal (protein, water, or focus), in whatever unit the
/// underlying `Goal.unit` uses. Mirrors the "3 goal rings" from docs/spec.md §6's Medium widget
/// and the ring colors in §15 (protein/focus/water — workout is intentionally not one of the
/// three widget rings; see `ZANOWidgetDataStore` doc comment for why).
public struct ZANORingProgress: Sendable, Hashable {
    public let goalID: UUID?
    public let title: String
    public let current: Double
    public let target: Double
    public let unit: String

    public init(goalID: UUID?, title: String, current: Double, target: Double, unit: String) {
        self.goalID = goalID
        self.title = title
        self.current = current
        self.target = target
        self.unit = unit
    }

    /// `0...1`. A goal with no target yet (no `DailyPlan` and no `Goal.targetValue`) reads as
    /// "done" once anything has been logged, and empty otherwise — never a divide-by-zero NaN.
    public var fraction: Double {
        guard target > 0 else { return current > 0 ? 1 : 0 }
        return min(max(current / target, 0), 1)
    }

    public var isComplete: Bool { fraction >= 1 }

    static func empty(title: String, unit: String) -> ZANORingProgress {
        ZANORingProgress(goalID: nil, title: title, current: 0, target: 0, unit: unit)
    }
}

/// Everything every ZANO widget family, Control, and (non-ActivityKit-pushed) timeline needs to
/// render one frame. Loaded once per timeline reload by `ZANOWidgetDataStore.loadSnapshot()` and
/// handed down to entry views — nothing downstream touches `SharedDefaults` or SwiftData
/// directly, so every widget/control renders from the exact same shape of data.
public struct ZANOWidgetSnapshot: Sendable {
    public let asOf: Date

    // Streak (spec §5.6, §8) — mirrors `SharedDefaults.currentStreak`/`bestStreak`.
    public let currentStreak: Int
    public let bestStreak: Int

    // Active lock (spec §5.1 Living Shield) — mirrors `SharedDefaults` lock keys.
    public let isLocked: Bool
    public let lockMode: LockMode?
    public let goalsRemainingForActiveLock: Int
    public let lockSetName: String?

    // Time Bank (spec §5.2 Earn Rate) — mirrors `SharedDefaults.earnedMinutesRemainingToday`,
    // already zeroed out by the loader when the mirror is stale (see
    // `SharedDefaults.earnedMinutesMirrorIsForToday`) so nobody downstream has to re-check that.
    public let earnedMinutesRemainingToday: Int

    // Next scheduled lock (spec §5.1, §5.2) — mirrors `SharedDefaults.nextScheduledLockAt`.
    public let nextScheduledLockAt: Date?

    // The 3 goal rings shown on the Medium/Large Home Screen widgets (spec §6) and selectable on
    // the Lock Screen circular widget (protein/water; streak is read from `currentStreak` above).
    public let protein: ZANORingProgress
    public let water: ZANORingProgress
    public let focus: ZANORingProgress

    // Needed to build `StartLockIntent`/the Lock toggle Control's "on" action without a second
    // SwiftData round trip from the caller.
    public let defaultLockSetID: UUID?
    public let todaysActiveGoalIDs: [UUID]

    public init(
        asOf: Date,
        currentStreak: Int,
        bestStreak: Int,
        isLocked: Bool,
        lockMode: LockMode?,
        goalsRemainingForActiveLock: Int,
        lockSetName: String?,
        earnedMinutesRemainingToday: Int,
        nextScheduledLockAt: Date?,
        protein: ZANORingProgress,
        water: ZANORingProgress,
        focus: ZANORingProgress,
        defaultLockSetID: UUID?,
        todaysActiveGoalIDs: [UUID]
    ) {
        self.asOf = asOf
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.isLocked = isLocked
        self.lockMode = lockMode
        self.goalsRemainingForActiveLock = goalsRemainingForActiveLock
        self.lockSetName = lockSetName
        self.earnedMinutesRemainingToday = earnedMinutesRemainingToday
        self.nextScheduledLockAt = nextScheduledLockAt
        self.protein = protein
        self.water = water
        self.focus = focus
        self.defaultLockSetID = defaultLockSetID
        self.todaysActiveGoalIDs = todaysActiveGoalIDs
    }

    /// A representative, entirely fake snapshot for `placeholder(in:)`/redacted previews. Never
    /// triggers a SwiftData fetch, so it's always cheap and safe to build synchronously on
    /// WidgetKit's rendering thread.
    public static let placeholder = ZANOWidgetSnapshot(
        asOf: .now,
        currentStreak: 14,
        bestStreak: 21,
        isLocked: true,
        lockMode: .earn,
        goalsRemainingForActiveLock: 2,
        lockSetName: "Distractions",
        earnedMinutesRemainingToday: 35,
        nextScheduledLockAt: Calendar.current.date(byAdding: .hour, value: 3, to: .now),
        protein: ZANORingProgress(goalID: nil, title: "Protein", current: 72, target: 150, unit: "g"),
        water: ZANORingProgress(goalID: nil, title: "Water", current: 750, target: 2000, unit: "ml"),
        focus: ZANORingProgress(goalID: nil, title: "Focus", current: 25, target: 50, unit: "min"),
        defaultLockSetID: nil,
        todaysActiveGoalIDs: []
    )
}

/// Reads everything in `ZANOWidgetSnapshot` from the App Group — the fast-path mirrors in
/// `SharedDefaults` for anything that has one, plus a fresh `ModelContext` against
/// `ModelContainer.appGroup` (Core/Sources/Core/Store) for the per-goal ring progress
/// `SharedDefaults` doesn't mirror. No networking, matching docs/spec.md §6/§11/§27 and this
/// session's task instructions ("Timeline data reads App Group only, no networking").
///
/// Deliberately reads `DailyPlan` rows directly instead of calling
/// `AdaptiveGoalEngine.dailyPlan(for:on:)`: that engine may create/write a new plan row on first
/// call for a day (docs/spec.md §9.1), which is a write with side effects this read-only,
/// short-lived, memory-limited widget/control context shouldn't be responsible for triggering
/// (spec §27 "extensions must be tiny"). If a `DailyPlan` doesn't exist yet for today, this falls
/// back to `Goal.targetValue` — the plan hasn't adapted yet, which is a fine widget-only
/// approximation. Flagged in this task's knownIssues for the orchestrator to confirm.
public enum ZANOWidgetDataStore {
    public static func loadSnapshot() -> ZANOWidgetSnapshot {
        let context = ModelContext(ModelContainer.appGroup)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)

        let activeGoals = (try? context.fetch(
            FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active })
        )) ?? []

        func ring(for type: GoalType, title: String, defaultUnit: String) -> ZANORingProgress {
            guard let goal = activeGoals.first(where: { $0.type == type }) else {
                return .empty(title: title, unit: defaultUnit)
            }
            let plannedToday = goal.dailyPlans.first { calendar.isDate($0.date, inSameDayAs: .now) }
            let target = plannedToday?.plannedValue ?? goal.targetValue ?? 0
            // `.verify` is included alongside `.log`/`.complete`/`.planB`: Core/Sources/Core/
            // Intents' Tier B one-tap log intents (LogProteinIntent, LogWaterIntent,
            // QuickRepeatMealIntent) write their GoalEvents with `kind: .verify` (a tap *is* its
            // own verification — see those files' header comments), so omitting it here left the
            // Protein/Water rings permanently stuck at 0 despite real logged events. `.miss`/
            // `.freeze` stay excluded — neither represents progress toward today's amount.
            let loggedToday = goal.events
                .filter { event in
                    event.ts >= startOfToday
                        && (event.kind == .log || event.kind == .verify || event.kind == .complete || event.kind == .planB)
                }
                .reduce(into: 0.0) { $0 += $1.value ?? 0 }
            return ZANORingProgress(
                goalID: goal.id,
                title: title,
                current: loggedToday,
                target: target,
                unit: goal.unit ?? defaultUnit
            )
        }

        let defaultLockSet = (try? context.fetch(
            FetchDescriptor<LockSet>(predicate: #Predicate<LockSet> { $0.isDefault })
        ))?.first

        var activeLockSetName: String?
        if let activeID = SharedDefaults.activeLockSetID {
            if activeID == defaultLockSet?.id {
                activeLockSetName = defaultLockSet?.name
            } else {
                let descriptor = FetchDescriptor<LockSet>(
                    predicate: #Predicate<LockSet> { $0.id == activeID }
                )
                activeLockSetName = (try? context.fetch(descriptor))?.first?.name
            }
        }

        let remainingMinutes = SharedDefaults.earnedMinutesMirrorIsForToday
            ? SharedDefaults.earnedMinutesRemainingToday
            : 0

        return ZANOWidgetSnapshot(
            asOf: .now,
            currentStreak: SharedDefaults.currentStreak,
            bestStreak: SharedDefaults.bestStreak,
            isLocked: SharedDefaults.activeLockSessionID != nil,
            lockMode: SharedDefaults.activeLockMode,
            goalsRemainingForActiveLock: SharedDefaults.goalsRemainingForActiveLock,
            lockSetName: activeLockSetName,
            earnedMinutesRemainingToday: remainingMinutes,
            nextScheduledLockAt: SharedDefaults.nextScheduledLockAt,
            protein: ring(for: .protein, title: "Protein", defaultUnit: "g"),
            water: ring(for: .water, title: "Water", defaultUnit: "ml"),
            focus: ring(for: .focusSession, title: "Focus", defaultUnit: "min"),
            defaultLockSetID: defaultLockSet?.id,
            todaysActiveGoalIDs: activeGoals.map(\.id)
        )
    }
}
