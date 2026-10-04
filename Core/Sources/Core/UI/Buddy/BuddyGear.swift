// BuddyGear.swift
// Core / UI / Buddy
//
// Buddy growth (2026-10-03): levels and gear, both earned, never sold. Gear is drawn as a pixel
// overlay on any face (`Buddy.gearPixels`, generated from scripts/buddies/gear.py); the worn item
// lives in the App Group defaults so widgets, the Screen Time report and the shield draw it too.
//
//   * XP and level: 10 XP per completed goal, 30 per earned unlock (`BuddyProgress.xp`), so the bar
//     on Today moves every time something gets done; levels from `levelThresholds`.
//   * Gear: party hat (first earned unlock), shades (7-day best streak), cape (Lv 5), beanie (14-day),
//     crown (30-day), jetpack (Lv 10), diamond (reached Diamond rank). Cape and jetpack are worn
//     behind the buddy (`gearUnderPixels`), the rest over it (`gearPixels`).
//     The first time an item unlocks the buddy puts it on (`adoptNewGear`), once; after that the
//     user picks what to wear (or nothing) on the Buddy screen.
//
// SwiftData: no enum is compared inside a `#Predicate`; sessions are fetched whole and filtered in
// Swift (the same rule as Milestones.swift).

import SwiftUI
import SwiftData

public enum BuddyGear: String, CaseIterable, Sendable, Identifiable {
    /// Nothing worn. (Not `none`, which would read as `Optional.none` wherever a `BuddyGear?` is.)
    case bare, partyHat, shades, beanie, crown, cape, jetpack, diamond

    public var id: String { rawValue }

    /// The worn item (App Group defaults, `SharedDefaults.store`).
    public static let storageKey = "shared.buddyGear"
    /// Items already celebrated (put on automatically once).
    public static let seenKey = "shared.buddyGearSeen"

    /// Every item that can be worn, in unlock order.
    public static let wearable: [BuddyGear] = [.partyHat, .shades, .cape, .beanie, .crown, .jetpack, .diamond]

    /// The stored worn item (`.bare` when unset or unreadable).
    public static var stored: BuddyGear {
        SharedDefaults.store.string(forKey: storageKey).flatMap(BuddyGear.init(rawValue:)) ?? .bare
    }

    public enum Requirement: Sendable, Equatable {
        case earnedUnlocks(Int)
        case bestStreak(Int)
        case level(Int)
        case diamondRank
    }

    public var requirement: Requirement? {
        switch self {
        case .bare: nil
        case .partyHat: .earnedUnlocks(1)
        case .shades: .bestStreak(7)
        case .beanie: .bestStreak(14)
        case .crown: .bestStreak(30)
        case .cape: .level(5)
        case .jetpack: .level(10)
        case .diamond: .diamondRank
        }
    }

    public func isUnlocked(by progress: BuddyProgress) -> Bool {
        switch requirement {
        case .none: true
        case .earnedUnlocks(let count): progress.earnedUnlocks >= count
        case .bestStreak(let days): progress.bestStreak >= days
        case .level(let level): progress.level >= level
        case .diamondRank: progress.reachedDiamond
        }
    }
}

/// What the buddy's growth is computed from: completed goals, earned unlocks, the best streak and
/// whether the user has ever reached Diamond rank.
public struct BuddyProgress: Sendable, Equatable {
    public let goalCompletions: Int
    public let earnedUnlocks: Int
    public let bestStreak: Int
    public let reachedDiamond: Bool

    public init(goalCompletions: Int = 0, earnedUnlocks: Int, bestStreak: Int, reachedDiamond: Bool = false) {
        self.goalCompletions = max(0, goalCompletions)
        self.earnedUnlocks = max(0, earnedUnlocks)
        self.bestStreak = max(0, bestStreak)
        self.reachedDiamond = reachedDiamond
    }

    public static let xpPerGoal = 10
    public static let xpPerEarnedUnlock = 30

    public var xp: Int { goalCompletions * Self.xpPerGoal + earnedUnlocks * Self.xpPerEarnedUnlock }

    /// XP needed for each level: Lv 1 at 0, Lv 2 at 30, ... About a week of steady days reaches Lv 5,
    /// a month Lv 10.
    public static let levelThresholds = [0, 30, 80, 160, 280, 450, 680, 1000, 1400, 1900, 2500, 3200]

    public var level: Int { max(1, Self.levelThresholds.filter { xp >= $0 }.count) }
    public var isMaxLevel: Bool { level >= Self.levelThresholds.count }

    /// XP still needed for the next level (nil at the top).
    public var xpToNextLevel: Int? {
        Self.levelThresholds.first { $0 > xp }.map { $0 - xp }
    }

    /// 0...1 through the current level.
    public var levelFraction: Double {
        guard let next = Self.levelThresholds.first(where: { $0 > xp }) else { return 1 }
        let floor = Self.levelThresholds.last { $0 <= xp } ?? 0
        return Double(xp - floor) / Double(max(1, next - floor))
    }

    public var unlockedGear: [BuddyGear] { BuddyGear.wearable.filter { $0.isUnlocked(by: self) } }

    /// The next item to earn (in unlock order), nil once everything is unlocked.
    public var nextGear: BuddyGear? { BuddyGear.wearable.first { !$0.isUnlocked(by: self) } }

    /// How far along the next item is: (have, need), e.g. (9, 14) days.
    public var nextGearProgress: (have: Int, need: Int)? {
        switch nextGear?.requirement {
        case .earnedUnlocks(let count): (min(earnedUnlocks, count), count)
        case .bestStreak(let days): (min(bestStreak, days), days)
        case .level(let target): (min(level, target), target)
        case .diamondRank: (reachedDiamond ? 1 : 0, 1)
        case .none: nil
        }
    }

    /// Screenshots and previews: Lv 5 (party hat, shades and cape unlocked), part-way to Lv 6.
    public static let preview = BuddyProgress(goalCompletions: 22, earnedUnlocks: 3, bestStreak: 9)

    /// Reads the user's numbers from SwiftData (earned locks, best streak).
    /// The App Group flag set the first time Diamond rank is seen (`recordRank`).
    public static let reachedDiamondKey = "shared.buddyReachedDiamond"

    /// Reads the user's numbers from SwiftData (completed goals, earned locks, best streak) and the
    /// Diamond flag from the App Group.
    @MainActor
    public static func load(from context: ModelContext, defaults: UserDefaults = SharedDefaults.store) -> BuddyProgress {
        let sessions = (try? context.fetch(FetchDescriptor<LockSession>())) ?? []
        let earned = sessions.filter { $0.unlockKind == .earned }.count
        let events = (try? context.fetch(FetchDescriptor<GoalEvent>())) ?? []
        let completions = events.filter { $0.kind == .complete }.count
        let best = ((try? context.fetch(FetchDescriptor<Streak>())) ?? []).map { max($0.best, $0.current) }.max() ?? 0
        return BuddyProgress(
            goalCompletions: completions,
            earnedUnlocks: earned,
            bestStreak: best,
            reachedDiamond: defaults.bool(forKey: reachedDiamondKey)
        )
    }

    /// Remembers that Diamond rank was reached (ranks reset each season; the diamond stays).
    public static func recordRank(_ rank: SeasonsAndRanks.Rank, defaults: UserDefaults = SharedDefaults.store) {
        if rank == .diamond { defaults.set(true, forKey: reachedDiamondKey) }
    }

    /// Puts on the newest item that unlocked since the last check, once per item (a fire-once
    /// ledger in the App Group defaults). Returns the item put on, if any.
    @discardableResult
    public static func adoptNewGear(_ progress: BuddyProgress, defaults: UserDefaults = SharedDefaults.store) -> BuddyGear? {
        let seen = Set(defaults.stringArray(forKey: BuddyGear.seenKey) ?? [])
        let fresh = progress.unlockedGear.filter { !seen.contains($0.rawValue) }
        guard let newest = fresh.last else { return nil }
        defaults.set(Array(seen.union(fresh.map(\.rawValue))).sorted(), forKey: BuddyGear.seenKey)
        defaults.set(newest.rawValue, forKey: BuddyGear.storageKey)
        return newest
    }
}
