// BuddyTests.swift
// Core / Tests / CoreTests
//
// Coverage for Core/Sources/Core/UI/Buddy (mascot redesign, 2026-10-03): the generated pixel data
// (BuddySprites.swift, from scripts/buddies) is well-formed for every buddy and pose, the stored
// choice falls back to Stash, and the day's mood maps to the right pose.
//
// `Buddy.stored` reads the App Group defaults (`SharedDefaults.store`), which have no test seam
// (see StoreTests.swift's header): the test saves and restores the real value, and the suite is
// `.serialized`.

import Testing
import Foundation
@testable import Core

@Suite("Buddies — sprite data, stored choice, pose mapping", .serialized)
struct BuddyTests {

    /// The palette keys, in index order (`BuddyPixels`' own table is private).
    private static let keys = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-/:;<=>?@[]^_`{|}~")

    // MARK: - Sprite data

    @Test(arguments: Buddy.allCases)
    func everyPoseIsSquare(_ buddy: Buddy) {
        for pose in BuddyPose.allCases {
            let pixels = buddy.pixels(pose)
            #expect(pixels.rows.count == BuddyPixels.size, "\(buddy) \(pose): \(pixels.rows.count) rows")
            for (y, row) in pixels.rows.enumerated() {
                #expect(row.count == BuddyPixels.size, "\(buddy) \(pose) row \(y): \(row.count) chars")
            }
        }
    }

    @Test(arguments: Buddy.allCases)
    func everyPixelIndexesItsPalette(_ buddy: Buddy) {
        for pose in BuddyPose.allCases {
            let pixels = buddy.pixels(pose)
            #expect(!pixels.palette.isEmpty, "\(buddy) \(pose): empty palette")
            for (y, row) in pixels.rows.enumerated() {
                for (x, char) in row.enumerated() where char != "." {
                    let index = Self.keys.firstIndex(of: char)
                    #expect(index != nil, "\(buddy) \(pose) (\(x), \(y)): unknown key '\(char)'")
                    if let index {
                        #expect(
                            index < pixels.palette.count,
                            "\(buddy) \(pose) (\(x), \(y)): key '\(char)' past a \(pixels.palette.count)-colour palette"
                        )
                    }
                }
            }
        }
    }

    @Test(arguments: Buddy.allCases)
    func everyPoseDrawsSomething(_ buddy: Buddy) {
        for pose in BuddyPose.allCases {
            let opaque = buddy.pixels(pose).rows.joined().filter { $0 != "." }.count
            #expect(opaque > 0, "\(buddy) \(pose) is fully transparent")
            #expect(buddy.pixels(pose).cgImage() != nil, "\(buddy) \(pose): no image")
        }
    }

    // MARK: - Stored choice

    @Test func storedDefaultsToStash() {
        let defaults = SharedDefaults.store
        let original = defaults.object(forKey: Buddy.storageKey)
        defer {
            if let original {
                defaults.set(original, forKey: Buddy.storageKey)
            } else {
                defaults.removeObject(forKey: Buddy.storageKey)
            }
        }

        #expect(Buddy.default == .stash)

        defaults.removeObject(forKey: Buddy.storageKey)
        #expect(Buddy.stored == .stash)

        defaults.set("not-a-buddy", forKey: Buddy.storageKey)
        #expect(Buddy.stored == .stash)

        defaults.set(Buddy.brick.rawValue, forKey: Buddy.storageKey)
        #expect(Buddy.stored == .brick)
    }

    // MARK: - Pose mapping

    @Test func poseFollowsMood() {
        #expect(BuddyPose(.sleepy) == .sleepy)
        #expect(BuddyPose(.idle) == .idle)
        #expect(BuddyPose(.perky) == .happy)
        #expect(BuddyPose(.charged) == .ecstatic)
    }

    @Test func poseFollowsTheDay() {
        // Locked with nothing done: sleepy. Some done: happy. Everything done: ecstatic.
        #expect(BuddyPose(ZanoMascotMood(done: 0, total: 3, isLocked: true)) == .sleepy)
        #expect(BuddyPose(ZanoMascotMood(done: 0, total: 3, isLocked: false)) == .idle)
        #expect(BuddyPose(ZanoMascotMood(done: 1, total: 3, isLocked: true)) == .happy)
        #expect(BuddyPose(ZanoMascotMood(done: 3, total: 3, isLocked: true)) == .ecstatic)
        #expect(BuddyPose(ZanoMascotMood(done: 3, total: 3, isLocked: false)) == .ecstatic)
        #expect(BuddyPose(ZanoMascotMood(done: 0, total: 0, isLocked: false)) == .idle)
    }

    @Test func poseRoundTripsThroughItsRawValue() {
        for pose in BuddyPose.allCases {
            #expect(BuddyPose(rawValue: pose.rawValue) == pose)
        }
    }

    @Test func faceFollowsTheCharge() {
        #expect(BuddyPose(charge: 0) == .drained)
        #expect(BuddyPose(charge: 0.14) == .drained)
        #expect(BuddyPose(charge: 0.15) == .sad)
        #expect(BuddyPose(charge: 0.3) == .meh)
        #expect(BuddyPose(charge: 0.45) == .idle)
        #expect(BuddyPose(charge: 0.6) == .happy)
        #expect(BuddyPose(charge: 0.75) == .excited)
        #expect(BuddyPose(charge: 0.89) == .excited)
        #expect(BuddyPose(charge: 0.9) == .ecstatic)
        #expect(BuddyPose(charge: 1) == .ecstatic)
    }

    @Test func heroIsEcstaticWhenTheDayIsDoneWhateverTheCharge() {
        #expect(BuddyPose.hero(charge: 0.05, mood: .ecstatic) == .ecstatic)
        #expect(BuddyPose.hero(charge: 0.05, mood: .sleepy) == .drained)
        #expect(BuddyPose.hero(charge: 0.72, mood: .idle) == .happy)
    }

    @Test func spritesAre48Pixels() {
        #expect(BuddyPixels.size == 48)
    }

    // MARK: - Growth (levels and gear)

    @Test func levelFollowsXP() {
        #expect(BuddyProgress(earnedUnlocks: 0, bestStreak: 0).level == 1)
        #expect(BuddyProgress(goalCompletions: 3, earnedUnlocks: 0, bestStreak: 0).xp == 30)
        #expect(BuddyProgress(goalCompletions: 3, earnedUnlocks: 0, bestStreak: 0).level == 2)
        #expect(BuddyProgress(earnedUnlocks: 1, bestStreak: 0).level == 2)
        #expect(BuddyProgress.preview.xp == 310)
        #expect(BuddyProgress.preview.level == 5)
        #expect(BuddyProgress.preview.xpToNextLevel == 140)
        #expect(BuddyProgress(goalCompletions: 999, earnedUnlocks: 999, bestStreak: 0).isMaxLevel)
        #expect(BuddyProgress(goalCompletions: 999, earnedUnlocks: 999, bestStreak: 0).xpToNextLevel == nil)
        let mid = BuddyProgress(goalCompletions: 22, earnedUnlocks: 0, bestStreak: 0).levelFraction // 220 XP: 160...280
        #expect(mid > 0.49 && mid < 0.51)
    }

    @Test func gearUnlocksFromPlay() {
        #expect(BuddyProgress(earnedUnlocks: 0, bestStreak: 0).unlockedGear.isEmpty)
        #expect(BuddyProgress(earnedUnlocks: 1, bestStreak: 0).unlockedGear == [.partyHat])
        #expect(BuddyProgress(earnedUnlocks: 1, bestStreak: 7).unlockedGear == [.partyHat, .shades])
        // Lv 5 (280 XP) brings the cape.
        #expect(BuddyProgress(goalCompletions: 25, earnedUnlocks: 1, bestStreak: 7).unlockedGear == [.partyHat, .shades, .cape])
        // Everything, the diamond only with Diamond rank.
        let all = BuddyProgress(goalCompletions: 200, earnedUnlocks: 30, bestStreak: 30, reachedDiamond: true)
        #expect(all.unlockedGear == BuddyGear.wearable)
        let noDiamond = BuddyProgress(goalCompletions: 200, earnedUnlocks: 30, bestStreak: 30)
        #expect(!noDiamond.unlockedGear.contains(.diamond))
    }

    @Test func newGearIsPutOnOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "BuddyTests.gear.\(UUID().uuidString)"))
        #expect(BuddyProgress.adoptNewGear(BuddyProgress(earnedUnlocks: 0, bestStreak: 0), defaults: defaults) == nil)
        #expect(BuddyProgress.adoptNewGear(BuddyProgress(earnedUnlocks: 1, bestStreak: 0), defaults: defaults) == .partyHat)
        #expect(defaults.string(forKey: BuddyGear.storageKey) == BuddyGear.partyHat.rawValue)
        // Already celebrated: nothing new, and taking it off sticks.
        defaults.set(BuddyGear.bare.rawValue, forKey: BuddyGear.storageKey)
        #expect(BuddyProgress.adoptNewGear(BuddyProgress(earnedUnlocks: 2, bestStreak: 3), defaults: defaults) == nil)
        #expect(defaults.string(forKey: BuddyGear.storageKey) == BuddyGear.bare.rawValue)
        // Two at once: the newest goes on.
        #expect(BuddyProgress.adoptNewGear(BuddyProgress(earnedUnlocks: 2, bestStreak: 14), defaults: defaults) == .beanie)
    }

    @Test(arguments: Buddy.allCases)
    func everyBuddyHasEveryGearOverlay(_ buddy: Buddy) {
        for gear in BuddyGear.wearable {
            for slumped in [false, true] {
                let over = buddy.gearPixels(gear, slumped: slumped)
                let under = buddy.gearUnderPixels(gear, slumped: slumped)
                // Each item is exactly one layer: worn over the buddy, or behind it.
                #expect((over == nil) != (under == nil), "\(buddy) \(gear) slumped=\(slumped)")
                #expect((over ?? under)?.rows.count == BuddyPixels.size)
            }
        }
        #expect(buddy.gearPixels(.bare, slumped: false) == nil)
        #expect(buddy.image(pose: .happy, gear: .crown) != nil)
    }

    @Test func nextGearShowsHowCloseItIs() {
        let fresh = BuddyProgress(earnedUnlocks: 0, bestStreak: 0)
        #expect(fresh.nextGear == .partyHat)
        #expect(fresh.nextGearProgress?.have == 0 && fresh.nextGearProgress?.need == 1)
        let mid = BuddyProgress(goalCompletions: 5, earnedUnlocks: 3, bestStreak: 9) // Lv 3
        #expect(mid.nextGear == .cape)
        #expect(mid.nextGearProgress?.have == 3 && mid.nextGearProgress?.need == 5)
        let done = BuddyProgress(goalCompletions: 300, earnedUnlocks: 40, bestStreak: 45, reachedDiamond: true)
        #expect(done.nextGear == nil)
        #expect(done.nextGearProgress == nil)
    }

    @Test func diamondIsRememberedAcrossSeasons() throws {
        let defaults = try #require(UserDefaults(suiteName: "BuddyTests.rank.\(UUID().uuidString)"))
        BuddyProgress.recordRank(.gold, defaults: defaults)
        #expect(!defaults.bool(forKey: BuddyProgress.reachedDiamondKey))
        BuddyProgress.recordRank(.diamond, defaults: defaults)
        #expect(defaults.bool(forKey: BuddyProgress.reachedDiamondKey))
        BuddyProgress.recordRank(.bronze, defaults: defaults)
        #expect(defaults.bool(forKey: BuddyProgress.reachedDiamondKey))
    }
}
