// ScrollMonster.swift
// Core / Retention
//
// The weekly boss (founder-approved gamification, 2026-10-04). Each week (the user's calendar week)
// a Scroll Monster shows up with HP = a target of locked time. Every minute the apps stay locked
// hits it for 1; every completed goal lands a critical hit for 20. Beat it before the week ends and
// it drops loot: coins (the existing `Coin` balance), once per week. The target adapts: 10% above
// last week's damage, between 5 and 40 hours, 10 hours the first week. Losing costs nothing; next
// week brings a new monster (spec §8: no shame, fresh starts).
//
// Pure maths (`week`, `damage`, `target`) is nonisolated and tested; `current(context:)` reads
// SwiftData on the main actor. SwiftData: no enum is compared inside a `#Predicate`.

import Foundation
import SwiftData

public enum ScrollMonster {
    public enum State: String, Sendable, CaseIterable {
        case healthy, hurt, defeated
    }

    /// One week's fight.
    public struct Week: Sendable, Equatable {
        public let interval: DateInterval
        public let target: Int
        public let damage: Int
        /// Whole days left including today (1 on the last day).
        public let daysLeft: Int
        /// 0...2, picks the monster's colours.
        public let variant: Int

        public init(interval: DateInterval, target: Int, damage: Int, daysLeft: Int, variant: Int) {
            self.interval = interval
            self.target = max(1, target)
            self.damage = max(0, damage)
            self.daysLeft = max(0, daysLeft)
            self.variant = variant
        }

        public var hp: Int { max(0, target - damage) }
        public var isDefeated: Bool { damage >= target }
        /// 0...1 of the monster's health left.
        public var hpFraction: Double { Double(hp) / Double(target) }
        public var state: State {
            if isDefeated { return .defeated }
            return hpFraction <= 0.5 ? .hurt : .healthy
        }
        /// A stable key for the fire-once loot ledger ("2026-10-05").
        public var key: String { ScrollMonster.dayKey(interval.start) }
    }

    public static let goalHit = 20
    public static let defaultTarget = 600
    public static let minimumTarget = 300
    public static let maximumTarget = 2400
    public static let lootCoins = 75
    /// App Group ledger of beaten weeks (`Week.key`), so loot pays once.
    public static let beatenKey = "shared.scrollMonsterBeaten"

    // MARK: - Pure maths

    public static func week(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    /// Locked minutes inside `week` (overlapping locks counted once) plus `goalHit` per completed goal.
    public static func damage(locked: [DateInterval], goalCompletions: [Date], in week: DateInterval) -> Int {
        let clipped = locked.compactMap { $0.intersection(with: week) }.filter { $0.duration > 0 }
        let minutes = Int(MilestoneEngine.lockedSeconds(clipped) / 60)
        let hits = goalCompletions.filter { week.contains($0) }.count
        return minutes + hits * goalHit
    }

    /// 10% above last week's damage, clamped; the default when there's no last week.
    public static func target(lastWeekDamage: Int?) -> Int {
        guard let last = lastWeekDamage, last > 0 else { return defaultTarget }
        return min(maximumTarget, max(minimumTarget, Int((Double(last) * 1.1).rounded())))
    }

    public static func variant(for week: DateInterval, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekOfYear, from: week.start)) % 3
    }

    public static func daysLeft(in week: DateInterval, now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: week.end).day ?? 0
        return max(0, days)
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Reading the week

    /// This week's fight from SwiftData (lock sessions and goal completions).
    @MainActor
    public static func current(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Week {
        let thisWeek = week(containing: now, calendar: calendar)
        let lastWeek = week(containing: thisWeek.start.addingTimeInterval(-1), calendar: calendar)
        let sessions = (try? context.fetch(FetchDescriptor<LockSession>())) ?? []
        let locked = sessions.map { DateInterval(start: $0.startedAt, end: max($0.startedAt, $0.endedAt ?? now)) }
        let events = (try? context.fetch(FetchDescriptor<GoalEvent>())) ?? []
        let completions = events.filter { $0.kind == .complete }.map(\.ts)
        let lastDamage = damage(locked: locked, goalCompletions: completions, in: lastWeek)
        let hadLastWeek = sessions.contains { $0.startedAt < thisWeek.start } || completions.contains { $0 < thisWeek.start }
        return Week(
            interval: thisWeek,
            target: target(lastWeekDamage: hadLastWeek ? lastDamage : nil),
            damage: damage(locked: locked, goalCompletions: completions, in: thisWeek),
            daysLeft: daysLeft(in: thisWeek, now: now, calendar: calendar),
            variant: variant(for: thisWeek, calendar: calendar)
        )
    }

    // MARK: - Loot

    /// Pays the week's loot once if the monster is beaten. Returns the coins paid, or nil.
    @MainActor
    @discardableResult
    public static func claimLoot(for week: Week, context: ModelContext, defaults: UserDefaults = SharedDefaults.store) -> Int? {
        guard week.isDefeated else { return nil }
        var beaten = Set(defaults.stringArray(forKey: beatenKey) ?? [])
        guard !beaten.contains(week.key) else { return nil }
        // Claim first, then pay (the VariableReward order): a crash in between loses one payout
        // instead of paying twice.
        beaten.insert(week.key)
        defaults.set(beaten.sorted(), forKey: beatenKey)
        guard let user = try? context.fetch(FetchDescriptor<User>()).first else { return lootCoins }
        let userID = user.id
        var descriptor = FetchDescriptor<Coin>(predicate: #Predicate { $0.userID == userID })
        descriptor.fetchLimit = 1
        if let coin = try? context.fetch(descriptor).first {
            coin.balance += lootCoins
        } else {
            context.insert(Coin(userID: userID, balance: lootCoins))
        }
        try? context.save()
        return lootCoins
    }

    /// How many monsters this user has beaten.
    public static func beatenCount(defaults: UserDefaults = SharedDefaults.store) -> Int {
        (defaults.stringArray(forKey: beatenKey) ?? []).count
    }
}
