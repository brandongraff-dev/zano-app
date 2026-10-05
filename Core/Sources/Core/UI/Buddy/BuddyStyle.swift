// BuddyStyle.swift
// Core / UI / Buddy
//
// The Buddy Closet's cosmetics (session 15, 2026-10-05; docs/spec.md §5.17). Everything a buddy can
// wear that is bought with coins: eight skins per buddy, hats, eyewear, neckwear, back items and
// backdrops. The art is generated (BuddyStyleSprites.swift, from scripts/buddies/style.py).
//
//   * Cosmetic only. Nothing here reaches a goal, a lock, a streak or the Time Bank, and the shop
//     engine (`CosmeticsStore`) only ever sells items in its own closed catalog (spec §5.17, §21).
//   * Earned gear (`BuddyGear`: party hat, shades, cape...) stays earned, never sold. A bought item in
//     the same slot is worn instead of the earned one; take it off and the earned item comes back.
//   * What each buddy wears is saved per buddy in the App Group defaults, so every screen, widget
//     and the Screen Time report draw the same outfit.
//
// Prices are placeholders (spec gives none): a boss drop is 75 coins and bonus drops are 25-75, so a
// hat is about two weeks of play and the rare skins about a month.

import SwiftUI

// MARK: - Slots and earned gear

extension BuddyGear {
    /// The style slot this earned item occupies: a bought item in the same slot is worn instead.
    public var slot: BuddyStyleSlot? {
        switch self {
        case .bare: nil
        case .partyHat, .beanie, .crown, .diamond: .hat
        case .shades: .eyewear
        case .cape, .jetpack: .back
        }
    }
}

// MARK: - Prices and catalog keys

extension BuddySkin {
    public var priceCoins: Int {
        switch self {
        case .midnight, .sunset, .mint, .bubblegum, .ghost: 300
        case .gold, .lava, .galaxy: 450
        }
    }
}

extension BuddyStyleItem {
    public var priceCoins: Int {
        switch self {
        case .hatCap, .hatHeadband, .hatFlowers, .hatChef: 150
        case .hatCowboy, .hatTophat, .hatSanta, .hatPirate, .hatWizard: 200
        case .hatHalo: 300
        case .eyewearRoundGlasses, .eyewearGoggles: 150
        case .eyewearHeartShades, .eyewearStarShades: 200
        case .neckBowtie, .neckTie, .neckCollarBell: 120
        case .neckScarf, .neckBandana: 150
        case .neckGoldChain: 250
        case .backBackpack: 250
        case .backLeafWings, .backBatWings: 350
        case .backAngelWings, .backButterflyWings, .backDragonWings: 450
        case .backdropSunrise, .backdropGym, .backdropForest, .backdropBeach, .backdropSnow, .backdropCandy,
             .backdropLibrary: 250
        case .backdropSpace, .backdropCity, .backdropArcade: 300
        }
    }

    /// The stable `CosmeticsStore` catalog key.
    public var cosmeticKey: String { "style_\(rawValue)" }
}

/// The closet's slice of `CosmeticsStore.catalog`: one free default plus every item and skin.
/// Hats, eyewear, neckwear, back items and backdrops are bought once and worn by any buddy; skins
/// are bought per buddy (a Stash skin does not paint Zib).
public enum BuddyStyleCatalog {
    public static let noneKey = "buddy_style_none"

    public static func skinKey(_ skin: BuddySkin, for buddy: Buddy) -> String {
        "style_skin_\(buddy.rawValue)_\(skin.rawValue)"
    }

    public static func cosmeticItem(_ item: BuddyStyleItem) -> CosmeticItem {
        CosmeticItem(key: item.cosmeticKey, category: .buddyStyle, priceCoins: item.priceCoins)
    }

    public static func cosmeticItem(_ skin: BuddySkin, for buddy: Buddy) -> CosmeticItem {
        CosmeticItem(key: skinKey(skin, for: buddy), category: .buddyStyle, priceCoins: skin.priceCoins)
    }

    /// Everything the closet sells, default first. 36 shared items plus 72 skins (8 per buddy).
    public static let items: [CosmeticItem] =
        [CosmeticItem(key: noneKey, category: .buddyStyle, priceCoins: 0, isDefault: true)]
        + BuddyStyleItem.allCases.map { cosmeticItem($0) }
        + Buddy.allCases.flatMap { buddy in BuddySkin.allCases.map { cosmeticItem($0, for: buddy) } }
}

// MARK: - Outfit

/// What one buddy is wearing. Every slot is optional; `nil` is bare.
public struct BuddyOutfit: Codable, Equatable, Sendable {
    public var skin: BuddySkin?
    public var hat: BuddyStyleItem?
    public var eyewear: BuddyStyleItem?
    public var neck: BuddyStyleItem?
    public var back: BuddyStyleItem?
    public var backdrop: BuddyStyleItem?

    public init(skin: BuddySkin? = nil, hat: BuddyStyleItem? = nil, eyewear: BuddyStyleItem? = nil,
                neck: BuddyStyleItem? = nil, back: BuddyStyleItem? = nil, backdrop: BuddyStyleItem? = nil) {
        self.skin = skin
        self.hat = hat
        self.eyewear = eyewear
        self.neck = neck
        self.back = back
        self.backdrop = backdrop
    }

    public var isBare: Bool { self == BuddyOutfit() }

    public func item(in slot: BuddyStyleSlot) -> BuddyStyleItem? {
        switch slot {
        case .hat: hat
        case .eyewear: eyewear
        case .neck: neck
        case .back: back
        case .backdrop: backdrop
        }
    }

    /// This outfit with `item` worn in its slot (`nil` clears `slot`).
    public func wearing(_ item: BuddyStyleItem?, in slot: BuddyStyleSlot) -> BuddyOutfit {
        var next = self
        switch slot {
        case .hat: next.hat = item
        case .eyewear: next.eyewear = item
        case .neck: next.neck = item
        case .back: next.back = item
        case .backdrop: next.backdrop = item
        }
        return next
    }

    // MARK: Storage (App Group defaults, one JSON blob per buddy)

    public static func storageKey(for buddy: Buddy) -> String { "shared.buddyOutfit.\(buddy.rawValue)" }

    public static func stored(for buddy: Buddy, defaults: UserDefaults = SharedDefaults.store) -> BuddyOutfit {
        guard let data = defaults.data(forKey: storageKey(for: buddy)) else { return BuddyOutfit() }
        return decode(data)
    }

    public static func decode(_ data: Data) -> BuddyOutfit {
        (try? JSONDecoder().decode(BuddyOutfit.self, from: data)) ?? BuddyOutfit()
    }

    public func save(for buddy: Buddy, defaults: UserDefaults = SharedDefaults.store) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.storageKey(for: buddy))
    }
}

// MARK: - Drawing

extension BuddyPixels {
    /// These pixels with palette colours swapped through `pairs` (`[original, new, original, new...]`
    /// starting at `offset`, four pairs). A colour with no pair keeps its value.
    func recoloured(_ pairs: [UInt32], offset: Int) -> BuddyPixels {
        var table: [UInt32: UInt32] = [:]
        var i = offset
        while i + 1 < min(pairs.count, offset + 8) {
            table[pairs[i]] = pairs[i + 1]
            i += 2
        }
        return BuddyPixels(palette: palette.map { table[$0] ?? $0 }, rows: rows)
    }
}

extension Buddy {
    /// The buddy in `pose` wearing `gear` and `outfit`, as one image. Layers, bottom to top: backdrop,
    /// back item (or earned cape/jetpack), the buddy in its skin, neckwear, earned gear worn over
    /// (unless a bought item took its slot), eyewear, hat.
    public func image(pose: BuddyPose, gear: BuddyGear, outfit: BuddyOutfit, showsBackdrop: Bool = false) -> CGImage? {
        let slumped = pose == .drained || pose == .sad
        var layers: [BuddyPixels] = []
        if showsBackdrop, let scene = outfit.backdrop?.backdropPixels() { layers.append(scene) }
        // Earned gear is worn unless a bought item already fills its slot.
        let earned: BuddyGear? = {
            guard gear != .bare else { return nil }
            if let slot = gear.slot, outfit.item(in: slot) != nil { return nil }
            return gear
        }()
        if let back = outfit.back {
            if let pixels = stylePixels(back, slumped: slumped) { layers.append(pixels) }
        } else if let earned, let pixels = gearUnderPixels(earned, slumped: slumped) {
            layers.append(pixels)
        }
        var face = pixels(pose)
        if let skin = outfit.skin {
            face = face.recoloured(skinColours(skin), offset: pose == .drained ? 8 : 0)
        }
        layers.append(face)
        if let neck = outfit.neck, let pixels = stylePixels(neck, slumped: slumped) { layers.append(pixels) }
        if let earned, let pixels = gearPixels(earned, slumped: slumped) { layers.append(pixels) }
        if let eyewear = outfit.eyewear, let pixels = stylePixels(eyewear, slumped: slumped) { layers.append(pixels) }
        if let hat = outfit.hat, let pixels = stylePixels(hat, slumped: slumped) { layers.append(pixels) }
        return BuddyPixels.image(layers: layers)
    }
}
