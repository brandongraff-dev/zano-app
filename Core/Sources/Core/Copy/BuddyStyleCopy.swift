// BuddyStyleCopy.swift
// Core / Copy
//
// Display copy for the Buddy Closet (session 15; docs/spec.md §5.17): slot names, item and skin
// names, and the screen's chrome. Names are the same in every coach voice (a hat is a hat), the way
// the Shop's other item names are.

import Foundation

extension Copy {
    public enum buddyStyle {
        // MARK: Screen chrome
        public static let screenTitle = "Buddy Closet"
        public static let screenSubtitle = "Dress your buddy with coins you earned."
        public static let openClosetButtonTitle = "Open the closet"
        public static let equippedTag = "Wearing"
        public static let wearButtonTitle = "Wear"
        public static let takeOffButtonTitle = "Take off"
        public static let ownedTag = "Owned"
        public static let earnedGearNote = "Earned items come back when you take a bought one off."
        public static let sharedItemsNote = "Bought once, worn by every buddy."
        public static func skinsNote(buddy: Buddy) -> String { "Skins are bought per buddy. These are \(Copy.buddy.name(buddy))'s." }

        public static func slotTitle(_ slot: BuddyStyleSlot) -> String {
            switch slot {
            case .hat: "Hats"
            case .eyewear: "Eyewear"
            case .neck: "Neckwear"
            case .back: "Back"
            case .backdrop: "Backdrops"
            }
        }

        public static func priceLabel(coins: Int) -> String { "\(coins) \(coins == 1 ? "coin" : "coins")" }
        public static func tileLabel(_ name: String, state: String) -> String { "\(name), \(state)" }
        public static let skinsTitle = "Skins"
        public static let noneTitle = "None"

        // MARK: Names

        public static func title(for skin: BuddySkin) -> String {
            switch skin {
            case .midnight: "Midnight"
            case .sunset: "Sunset"
            case .mint: "Mint"
            case .bubblegum: "Bubblegum"
            case .gold: "Gold"
            case .ghost: "Ghost"
            case .lava: "Lava"
            case .galaxy: "Galaxy"
            }
        }

        public static func title(for item: BuddyStyleItem) -> String {
            switch item {
            case .hatCap: "Red Cap"
            case .hatWizard: "Wizard Hat"
            case .hatChef: "Chef Hat"
            case .hatCowboy: "Cowboy Hat"
            case .hatTophat: "Top Hat"
            case .hatHalo: "Halo"
            case .hatHeadband: "Sweatband"
            case .hatSanta: "Santa Hat"
            case .hatPirate: "Pirate Hat"
            case .hatFlowers: "Flower Crown"
            case .eyewearRoundGlasses: "Round Glasses"
            case .eyewearHeartShades: "Heart Shades"
            case .eyewearStarShades: "Star Shades"
            case .eyewearGoggles: "Goggles"
            case .neckBowtie: "Bow Tie"
            case .neckScarf: "Striped Scarf"
            case .neckBandana: "Bandana"
            case .neckGoldChain: "Gold Chain"
            case .neckCollarBell: "Bell Collar"
            case .neckTie: "Blue Tie"
            case .backAngelWings: "Angel Wings"
            case .backBatWings: "Bat Wings"
            case .backButterflyWings: "Butterfly Wings"
            case .backDragonWings: "Dragon Wings"
            case .backLeafWings: "Leaf Wings"
            case .backBackpack: "Backpack"
            case .backdropSunrise: "Sunrise"
            case .backdropGym: "Gym"
            case .backdropForest: "Forest"
            case .backdropSpace: "Space"
            case .backdropBeach: "Beach"
            case .backdropCity: "City Night"
            case .backdropSnow: "Snowy Day"
            case .backdropCandy: "Candy Land"
            case .backdropLibrary: "Library"
            case .backdropArcade: "Arcade"
            }
        }

        public static func description(for item: BuddyStyleItem) -> String {
            switch item.slot {
            case .hat: "A hat for your buddy."
            case .eyewear: "A look for your buddy's eyes."
            case .neck: "Something for your buddy's neck."
            case .back: "Worn on your buddy's back."
            case .backdrop: "A scene behind your buddy."
            }
        }

        // MARK: Shop-catalog keys (`CosmeticsStore.catalog`)

        /// `"style_hatCap"` or `"style_skin_stash_gold"` -> its display name; nil for any other key.
        public static func title(forCosmeticKey key: String) -> String? {
            if let (buddy, skin) = parseSkin(key) { return "\(Copy.buddy.name(buddy)) \(title(for: skin))" }
            return parseItem(key).map(title(for:))
        }

        public static func description(forCosmeticKey key: String) -> String? {
            if let (buddy, _) = parseSkin(key) { return "A new colour for \(Copy.buddy.name(buddy))." }
            return parseItem(key).map(description(for:))
        }

        static func parseItem(_ key: String) -> BuddyStyleItem? {
            guard key.hasPrefix("style_") else { return nil }
            return BuddyStyleItem(rawValue: String(key.dropFirst("style_".count)))
        }

        static func parseSkin(_ key: String) -> (Buddy, BuddySkin)? {
            let parts = key.split(separator: "_")
            guard parts.count == 4, parts[0] == "style", parts[1] == "skin",
                  let buddy = Buddy(rawValue: String(parts[2])), let skin = BuddySkin(rawValue: String(parts[3]))
            else { return nil }
            return (buddy, skin)
        }
    }
}
