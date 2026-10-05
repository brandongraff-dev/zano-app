// Core/Sources/Core/Copy/TrophyCosmeticsCopy.swift
//
// docs/spec.md §5.17 Trophy Case & Cosmetics — screen-chrome and display copy for
// `App/ZANO/Features/Trophy/{TrophyCaseView,CosmeticsShopView}.swift` and (incidentally, since it
// declares the same `Copy.badges` members) `App/ZANO/Features/Progress/ProgressView.swift`'s badge
// tiles.
//
// THIS FILE FIXES A REAL BUILD BREAK, same situation `SunriseAlarmScreenCopy.swift` (this
// directory) documents for the Sunrise Alarm cluster: `TrophyCaseView.swift` and
// `CosmeticsShopView.swift` each document an "ASSUMED API" for `Copy.trophyCase.*` /
// `Copy.cosmetics.*` / `Copy.badges.*`, following this codebase's real `extension Copy { enum
// <area> { ... } }` per-file convention — but nothing had actually declared those three
// namespaces anywhere in `Core/Sources/Core/Copy`, so every one of those views (plus
// `ProgressView.swift`'s badge tiles, which read `Copy.badges.*` too) failed to compile. Every key
// below matches the exact call sites in those files, not the header comments' own (slightly wider)
// documented lists.
//
// `Copy.badges.title(forKey:)` also has to cover badge keys no fixed catalog lists: `StreakEngine.
// awardComebackBadge`/`ComebackMode.awardChallengeCompleteBadge`/`SeasonsAndRanks.
// awardMonthlyChallengeBadgeIfComplete` each stamp a *dated* key (`"comeback_<yyyy-MM-dd>"`,
// `"comeback_challenge_<yyyy-MM-dd>"`, `"monthly_challenge_<challenge key>"`) rather than one of a
// fixed set — `title(forKey:)` pattern-matches those prefixes before falling back to a generic
// title-cased rendering of the raw key, so a badge this file has never heard of still renders
// something reasonable instead of an empty string.

import Foundation

// MARK: - Copy.badges (TrophyCaseView.swift's grid + "Other achievements", ProgressView.swift's tiles)

extension Copy {
    public enum badges {
        /// Display title for a `Badge.key`. Exact matches first (the six spec §5.17 milestones),
        /// then the known dated-prefix families real engines already award, then a generic
        /// fallback so an unrecognized key never renders blank.
        public static func title(forKey key: String) -> String {
            if let exact = fixedTitles[key] { return exact }
            if let season = Copy.progress.seasonBadgeTitle(forKey: key) { return season }
            if key.hasPrefix("comeback_challenge_") { return "Comeback Challenge" }
            if key.hasPrefix("comeback_") { return "Comeback" }
            if key.hasPrefix("monthly_challenge_") { return "Monthly Challenge" }
            return titleCased(key)
        }

        /// spec §5.17's exact six: "first earned unlock, 7/30/100-day streaks, 1,000g protein
        /// week, 50 gym sessions."
        private static let fixedTitles: [String: String] = [
            "first_earned_unlock": "First Unlock",
            "streak_7": "7-Day Streak",
            "streak_14": "14-Day Streak",
            "streak_30": "30-Day Streak",
            "streak_100": "100-Day Streak",
            "streak_365": "365-Day Streak",
            "protein_1000g_week": "1,000g Protein Week",
            "gym_50_sessions": "50 Gym Sessions",
        ]

        /// `"comeback_challenge_2026-01-05"` → `"Comeback Challenge 2026 01 05"`-style fallback is
        /// avoided by the prefix checks in `title(forKey:)` above; this is only ever reached for a
        /// genuinely unrecognized key, so it just makes the raw `snake_case` readable rather than
        /// trying to be clever about it.
        private static func titleCased(_ key: String) -> String {
            key.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }

        /// "Earned Mar 3" — short, no year (matches `RecapCard`'s own short-date convention
        /// elsewhere in this codebase; a badge earned this calendar year doesn't need one, and one
        /// earned last year is still unambiguous enough for a trophy-case tile).
        public static func earnedOnLabel(date: Date) -> String {
            "Earned \(shortDateFormatter.string(from: date))"
        }

        private static let shortDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d"
            formatter.timeZone = .current
            return formatter
        }()
    }
}

// MARK: - Copy.trophyCase (TrophyCaseView.swift)

extension Copy {
    public enum trophyCase {
        public static let screenTitle = "Trophy Case"
        public static let screenSubtitle = "Every badge, earned the real way."

        /// "earned", not "unlocked": matches "Earned Mar 3" on each tile and the "Not yet earned"
        /// hint, and keeps "unlock" for the lock mechanic.
        public static func progressLabel(earned: Int, total: Int) -> String {
            "\(earned) of \(total) earned"
        }

        /// Beside the big earned-count numeral in the hero: "2" + "of 6 earned".
        public static func progressTotalLabel(total: Int) -> String { "of \(total) earned" }
        /// Day 1 hero line, when nothing is earned yet.
        public static let emptyHeroMessage = "Your first earned unlock puts the first trophy on the shelf."

        public static let openShopButtonTitle = "Cosmetics Shop"
        public static let lockedAccessibilityHint = "Not yet earned"
        public static let otherAchievementsSectionTitle = "More badges"
    }
}

// MARK: - Copy.cosmetics (CosmeticsShopView.swift, plus TrophyCaseView.swift's coin pill)

extension Copy {
    public enum cosmetics {
        public static let screenTitle = "Cosmetics Shop"
        public static let screenSubtitle = "Spend coins you earned from real goals."
        public static let categoryPickerAccessibilityLabel = "Category"

        public static func categoryTitle(_ category: CosmeticCategory) -> String {
            switch category {
            case .theme: "Themes"
            case .ringStyle: "Ring styles"
            case .shieldBackground: "Shield backgrounds"
            case .coachVoicePack: "Coach voice packs"
            }
        }

        /// Display name per `CosmeticsStore.catalog` key. Exact matches for every key that catalog
        /// defines today; an unrecognized future key falls back to a title-cased rendering rather
        /// than a blank label, same fallback `Copy.badges.title(forKey:)` uses.
        public static func title(forKey key: String) -> String {
            fixedTitles[key] ?? Copy.badges.title(forKey: key)
        }

        public static func itemDescription(forKey key: String) -> String {
            fixedDescriptions[key] ?? "A cosmetic reward from your verified goals."
        }

        private static let fixedTitles: [String: String] = [
            "theme_classic": "Classic",
            "theme_electric_blue": "Electric Blue",
            "theme_magenta_pulse": "Magenta Pulse",
            "theme_gold_rush": "Gold Rush",
            "theme_ice_mint": "Ice Mint",

            "ring_solid": "Solid",
            "ring_gradient_sweep": "Gradient Sweep",
            "ring_dashed_pulse": "Dashed Pulse",
            "ring_glow_trail": "Glow Trail",
            "ring_double_ring": "Double Ring",

            "shield_classic": "Classic",
            "shield_city_skyline": "City Skyline",
            "shield_gym_floor": "Gym Floor",
            "shield_mountain_dawn": "Mountain Dawn",
            "shield_abstract_wave": "Abstract Wave",

            "coachpack_stock": "Stock",
            "coachpack_captain_intensity": "Captain Intensity",
            "coachpack_zen_minimal": "Zen Minimal",
            "coachpack_data_stream": "Data Stream",
            "coachpack_hype_squad": "Hype Squad",
        ]

        private static let fixedDescriptions: [String: String] = [
            "theme_classic": "The look you started with.",
            "theme_electric_blue": "A cool, high-contrast blue accent.",
            "theme_magenta_pulse": "A bold magenta accent with a subtle pulse.",
            "theme_gold_rush": "A warm gold accent for your rings and shield.",
            "theme_ice_mint": "A crisp, cool mint accent.",

            "ring_solid": "The default solid ring stroke.",
            "ring_gradient_sweep": "A sweeping gradient stroke on every ring.",
            "ring_dashed_pulse": "A dashed stroke that pulses as it fills.",
            "ring_glow_trail": "A soft glow trails the ring as it fills.",
            "ring_double_ring": "A second, thinner ring traces just outside the main one.",

            "shield_classic": "The default shield backdrop.",
            "shield_city_skyline": "A city skyline behind your shield.",
            "shield_gym_floor": "A gym floor backdrop — a little extra motivation.",
            "shield_mountain_dawn": "A mountain sunrise backdrop.",
            "shield_abstract_wave": "An abstract wave pattern backdrop.",

            "coachpack_stock": "Your coach voice, unchanged.",
            "coachpack_captain_intensity": "A more intense presentation for your coach's lines.",
            "coachpack_zen_minimal": "A calmer, minimal presentation for your coach's lines.",
            "coachpack_data_stream": "A data-forward presentation for your coach's lines.",
            "coachpack_hype_squad": "A louder, squad-hype presentation for your coach's lines.",
        ]

        public static let equipButtonTitle = "Equip"
        public static let equippedButtonTitle = "Equipped"
        public static let equippedBadgeLabel = "Equipped"

        /// Names the currency: a bare "Buy · 250" beside real-money Pro copy reads as dollars.
        public static func purchaseButtonTitle(priceCoins: Int) -> String {
            "Buy for \(priceCoins) \(priceCoins == 1 ? "coin" : "coins")"
        }

        // No Pro-gate copy: the paywall is hard, so everyone who reaches the shop is subscribed.

        public static let insufficientCoinsAlertTitle = "Not enough coins"
        public static func insufficientCoinsAlertMessage(shortBy: Int) -> String {
            "You're \(shortBy) coin\(shortBy == 1 ? "" : "s") short. Complete goals to earn more coins."
        }

        public static func coinBalanceAccessibilityLabel(balance: Int) -> String {
            "\(balance) coin\(balance == 1 ? "" : "s")"
        }
    }
}
