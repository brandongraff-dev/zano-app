// BuddyStyleTests.swift
// Core / Tests / CoreTests
//
// Coverage for the Buddy Closet (session 15, 2026-10-05): the generated overlay and backdrop data is
// well-formed for every buddy, every skin recolours something, the closet's catalog is part of the
// shop's closed catalog (and sells only cosmetics), outfits survive a save and load, and a bought
// item takes its slot from earned gear.

import Testing
import Foundation
@testable import Core

@Suite("Buddy Closet — style sprites, skins, catalog, outfits")
struct BuddyStyleTests {

    private static let keys = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-/:;<=>?@[]^_`{|}~")

    private func wellFormed(_ pixels: BuddyPixels, _ label: String) {
        #expect(pixels.rows.count == BuddyPixels.size, "\(label): \(pixels.rows.count) rows")
        for (y, row) in pixels.rows.enumerated() {
            #expect(row.count == BuddyPixels.size, "\(label) row \(y): \(row.count) chars")
            for char in row where char != "." {
                let index = Self.keys.firstIndex(of: char)
                #expect(index != nil && index! < pixels.palette.count, "\(label): bad key \(char)")
            }
        }
    }

    // MARK: Sprite data

    @Test(arguments: Buddy.allCases)
    func everyWearableHasPixelsForEveryBuddy(_ buddy: Buddy) {
        for item in BuddyStyleItem.allCases where item.slot != .backdrop {
            for slumped in [false, true] {
                guard let pixels = buddy.stylePixels(item, slumped: slumped) else {
                    Issue.record("\(buddy) \(item) has no pixels")
                    continue
                }
                wellFormed(pixels, "\(buddy) \(item)")
                #expect(pixels.rows.joined().contains { $0 != "." }, "\(buddy) \(item) draws nothing")
            }
        }
    }

    @Test func backdropsHaveFullScenesAndWearablesHaveNone() {
        for item in BuddyStyleItem.allCases {
            if item.slot == .backdrop {
                let scene = item.backdropPixels()
                #expect(scene != nil, "\(item)")
                if let scene {
                    wellFormed(scene, "\(item)")
                    #expect(scene.rows.joined().filter { $0 == "." }.isEmpty, "\(item) has holes")
                }
            } else {
                #expect(item.backdropPixels() == nil, "\(item)")
            }
        }
    }

    @Test(arguments: Buddy.allCases)
    func wearablesAndBackdropsRenderAnImage(_ buddy: Buddy) {
        for item in BuddyStyleItem.allCases {
            let outfit = BuddyOutfit().wearing(item, in: item.slot)
            #expect(buddy.image(pose: .happy, gear: .bare, outfit: outfit, showsBackdrop: true) != nil, "\(buddy) \(item)")
        }
    }

    // MARK: Skins

    @Test(arguments: Buddy.allCases)
    func everySkinRecoloursTheBuddy(_ buddy: Buddy) {
        let plain = buddy.pixels(.happy)
        for skin in BuddySkin.allCases {
            let colours = buddy.skinColours(skin)
            #expect(colours.count == 16, "\(buddy) \(skin)")
            let recoloured = plain.recoloured(colours, offset: 0)
            #expect(recoloured.palette != plain.palette, "\(buddy) \(skin) changed nothing")
            #expect(recoloured.rows == plain.rows)
            let outfit = BuddyOutfit(skin: skin)
            #expect(buddy.image(pose: .happy, gear: .bare, outfit: outfit) != nil)
            #expect(buddy.image(pose: .drained, gear: .bare, outfit: outfit) != nil)
        }
    }

    @Test func aDrainedFaceUsesTheWashedOutColours() {
        let skin = BuddySkin.gold
        let colours = Buddy.stash.skinColours(skin)
        let plain = Buddy.stash.pixels(.drained).recoloured(colours, offset: 0)
        let washed = Buddy.stash.pixels(.drained).recoloured(colours, offset: 8)
        #expect(plain.palette == Buddy.stash.pixels(.drained).palette, "the normal table matches nothing on a washed-out face")
        #expect(washed.palette != Buddy.stash.pixels(.drained).palette)
    }

    // MARK: Catalog

    @MainActor @Test func catalogIsPartOfTheShopsClosedCatalog() {
        let items = BuddyStyleCatalog.items
        #expect(items.count == 1 + BuddyStyleItem.allCases.count + Buddy.allCases.count * BuddySkin.allCases.count)
        #expect(Set(items.map(\.key)).count == items.count, "duplicate keys")
        #expect(items.allSatisfy { $0.category == .buddyStyle })
        #expect(items.filter(\.isDefault).count == 1)
        for item in items {
            #expect(CosmeticsStore.catalog.contains(item), "\(item.key) is not in CosmeticsStore.catalog")
            if !item.isDefault { #expect(item.priceCoins > 0, "\(item.key)") }
        }
        // Every category still has exactly one free default.
        for category in CosmeticCategory.allCases {
            #expect(CosmeticsStore.catalog.filter { $0.category == category && $0.isDefault }.count == 1, "\(category)")
        }
    }

    @Test func everyItemHasAnEnglishNameAndDescription() {
        for item in BuddyStyleCatalog.items where !item.isDefault {
            #expect(Copy.buddyStyle.title(forCosmeticKey: item.key) != nil, "\(item.key)")
            #expect(Copy.buddyStyle.description(forCosmeticKey: item.key) != nil, "\(item.key)")
            #expect(!Copy.cosmetics.title(forKey: item.key).isEmpty)
        }
        #expect(Copy.buddyStyle.title(forCosmeticKey: "style_skin_stash_gold") == "Stash Gold")
        #expect(Copy.buddyStyle.title(forCosmeticKey: "style_hatCap") == "Red Cap")
        #expect(Copy.buddyStyle.title(forCosmeticKey: "theme_classic") == nil)
    }

    // MARK: Outfits

    @Test func anOutfitRoundTripsThroughItsStorage() throws {
        let name = "BuddyStyleTests.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        #expect(BuddyOutfit.stored(for: .zib, defaults: suite).isBare)
        let outfit = BuddyOutfit(skin: .mint, hat: .hatChef, eyewear: .eyewearGoggles, neck: .neckScarf,
                                 back: .backBackpack, backdrop: .backdropGym)
        outfit.save(for: .zib, defaults: suite)
        #expect(BuddyOutfit.stored(for: .zib, defaults: suite) == outfit)
        #expect(BuddyOutfit.stored(for: .lox, defaults: suite).isBare, "outfits are per buddy")
        suite.set(Data("not json".utf8), forKey: BuddyOutfit.storageKey(for: .zib))
        #expect(BuddyOutfit.stored(for: .zib, defaults: suite).isBare, "unreadable data falls back to bare")
    }

    @Test func wearingFillsAndClearsOneSlot() {
        let outfit = BuddyOutfit().wearing(.hatCap, in: .hat)
        #expect(outfit.hat == .hatCap)
        #expect(outfit.item(in: .hat) == .hatCap)
        #expect(outfit.item(in: .eyewear) == nil)
        #expect(outfit.wearing(nil, in: .hat).isBare)
    }

    @Test func earnedGearSharesASlotWithBoughtItems() {
        #expect(BuddyGear.crown.slot == .hat)
        #expect(BuddyGear.partyHat.slot == .hat)
        #expect(BuddyGear.shades.slot == .eyewear)
        #expect(BuddyGear.cape.slot == .back)
        #expect(BuddyGear.jetpack.slot == .back)
        #expect(BuddyGear.bare.slot == nil)
        for item in BuddyStyleItem.allCases {
            #expect(item.slot == BuddyStyleSlot(rawValue: String(item.rawValue.prefix { $0.isLowercase })))
        }
    }
}
