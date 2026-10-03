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
    private static let keys = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    // MARK: - Sprite data

    @Test(arguments: Buddy.allCases)
    func everyPoseIs32By32(_ buddy: Buddy) {
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
        #expect(BuddyPose(.perky) == .idle)
        #expect(BuddyPose(.charged) == .happy)
    }

    @Test func poseFollowsTheDay() {
        // Locked with nothing done: sleepy. Everything done: happy. Otherwise idle.
        #expect(BuddyPose(ZanoMascotMood(done: 0, total: 3, isLocked: true)) == .sleepy)
        #expect(BuddyPose(ZanoMascotMood(done: 0, total: 3, isLocked: false)) == .idle)
        #expect(BuddyPose(ZanoMascotMood(done: 1, total: 3, isLocked: true)) == .idle)
        #expect(BuddyPose(ZanoMascotMood(done: 3, total: 3, isLocked: true)) == .happy)
        #expect(BuddyPose(ZanoMascotMood(done: 3, total: 3, isLocked: false)) == .happy)
        #expect(BuddyPose(ZanoMascotMood(done: 0, total: 0, isLocked: false)) == .idle)
    }

    @Test func poseRoundTripsThroughItsRawValue() {
        for pose in BuddyPose.allCases {
            #expect(BuddyPose(rawValue: pose.rawValue) == pose)
        }
    }

    @Test func faceFollowsTheCharge() {
        #expect(BuddyPose(charge: 0) == .tired)
        #expect(BuddyPose(charge: 0.19) == .tired)
        #expect(BuddyPose(charge: 0.2) == .meh)
        #expect(BuddyPose(charge: 0.44) == .meh)
        #expect(BuddyPose(charge: 0.45) == .idle)
        #expect(BuddyPose(charge: 0.69) == .idle)
        #expect(BuddyPose(charge: 0.7) == .grin)
        #expect(BuddyPose(charge: 0.89) == .grin)
        #expect(BuddyPose(charge: 0.9) == .happy)
        #expect(BuddyPose(charge: 1) == .happy)
    }

    @Test func heroBeamsWhenTheDayIsDoneWhateverTheCharge() {
        #expect(BuddyPose.hero(charge: 0.05, mood: .happy) == .happy)
        #expect(BuddyPose.hero(charge: 0.05, mood: .sleepy) == .tired)
        #expect(BuddyPose.hero(charge: 0.72, mood: .idle) == .grin)
    }
}
