// BuddyGear.swift
// Core / UI / Buddy
//
// Buddy growth (2026-10-03): levels and gear, both earned, never sold. Gear is drawn as a pixel
// overlay on any face (`Buddy.gearPixels`, generated from scripts/buddies/gear.py); the worn item
// lives in the App Group defaults so widgets, the Screen Time report and the shield draw it too.
//
//   * Level: from lifetime earned unlocks (`BuddyProgress.levelThresholds`).
//   * Gear: party hat (first earned unlock), shades (7-day best streak), beanie (14), crown (30).
//     The first time an item unlocks the buddy puts it on (`adoptNewGear`), once; after that the
//     user picks what to wear (or nothing) on the Buddy screen.
//
// SwiftData: no enum is compared inside a `#Predicate`; sessions are fetched whole and filtered in
// Swift (the same rule as Milestones.swift).

import SwiftUI
import SwiftData

public enum BuddyGear: String, CaseIterable, Sendable, Identifiable {
    /// Nothing worn. (Not `none`, which would read as `Optional.none` wherever a `BuddyGear?` is.)
    case bare, partyHat, shades, beanie, crown

    public var id: String { rawValue }

    /// The worn item (App Group defaults, `SharedDefaults.store`).
    public static let storageKey = "shared.buddyGear"
    /// Items already celebrated (put on automatically once).
    public static let seenKey = "shared.buddyGearSeen"

    /// Every item that can be worn, in unlock order.
    public static let wearable: [BuddyGear] = [.partyHat, .shades, .beanie, .crown]

    /// The stored worn item (`.bare` when unset or unreadable).
    public static var stored: BuddyGear {
        SharedDefaults.store.string(forKey: storageKey).flatMap(BuddyGear.init(rawValue:)) ?? .bare
    }

    public enum Requirement: Sendable, Equatable {
        case earnedUnlocks(Int)
        case bestStreak(Int)
    }

    public var requirement: Requirement? {
        switch self {
        case .bare: nil
        case .partyHat: .earnedUnlocks(1)
        case .shades: .bestStreak(7)
        case .beanie: .bestStreak(14)
        case .crown: .bestStreak(30)
        }
    }

    public func isUnlocked(by progress: BuddyProgress) -> Bool {
        switch requirement {
        case .none: true
        case .earnedUnlocks(let count): progress.earnedUnlocks >= count
        case .bestStreak(let days): progress.bestStreak >= days
        }
    }
}

/// What the buddy's growth is computed from: lifetime earned unlocks and the best streak.
public struct BuddyProgress: Sendable, Equatable {
    public let earnedUnlocks: Int
    public let bestStreak: Int

    public init(earnedUnlocks: Int, bestStreak: Int) {
        self.earnedUnlocks = max(0, earnedUnlocks)
        self.bestStreak = max(0, bestStreak)
    }

    /// Earned unlocks needed for each level: Lv 1 at 0, Lv 2 at 1, Lv 3 at 3, ...
    public static let levelThresholds = [0, 1, 3, 7, 15, 30, 50, 75, 100, 150, 200, 300]

    public var level: Int { max(1, Self.levelThresholds.filter { earnedUnlocks >= $0 }.count) }
    public var isMaxLevel: Bool { level >= Self.levelThresholds.count }

    /// Earned unlocks still needed for the next level (nil at the top).
    public var unlocksToNextLevel: Int? {
        Self.levelThresholds.first { $0 > earnedUnlocks }.map { $0 - earnedUnlocks }
    }

    /// 0...1 through the current level.
    public var levelFraction: Double {
        guard let next = Self.levelThresholds.first(where: { $0 > earnedUnlocks }) else { return 1 }
        let floor = Self.levelThresholds.last { $0 <= earnedUnlocks } ?? 0
        return Double(earnedUnlocks - floor) / Double(max(1, next - floor))
    }

    public var unlockedGear: [BuddyGear] { BuddyGear.wearable.filter { $0.isUnlocked(by: self) } }

    /// Screenshots and previews: Lv 4, party hat and shades unlocked.
    public static let preview = BuddyProgress(earnedUnlocks: 12, bestStreak: 9)

    /// Reads the user's numbers from SwiftData (earned locks, best streak).
    @MainActor
    public static func load(from context: ModelContext) -> BuddyProgress {
        let sessions = (try? context.fetch(FetchDescriptor<LockSession>())) ?? []
        let earned = sessions.filter { $0.unlockKind == .earned }.count
        let best = ((try? context.fetch(FetchDescriptor<Streak>())) ?? []).map { max($0.best, $0.current) }.max() ?? 0
        return BuddyProgress(earnedUnlocks: earned, bestStreak: best)
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
