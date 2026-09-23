// Core/Sources/Core/Retention/CosmeticsStore.swift
//
// docs/spec.md §5.17 Trophy Case & Cosmetics:
//   "Badges for milestones (first earned unlock, 7/30/100-day streaks, 1,000g protein week, 50
//   gym sessions). Coins from verified goals buy themes, ring styles, shield backgrounds, and
//   coach voice packs. Cosmetics only; never sell power (no buying unlocks)."
// docs/spec.md §21 Monetization & Paywall:
//   "Pro: ... cosmetics." / "Never sell: unlocks, streak restores, or anything that lets money
//   bypass the goal. The moment you do, the product's promise breaks." §21's tier table also puts
//   cosmetics purchasing behind Pro specifically (not viewing — Free users still earn coins and
//   badges; they just can't spend the former here until they upgrade). §25.3 ("Earned Cards")
//   restates the same rule for the physical-goods surface: "Rule from §21 still holds: cosmetics
//   and status only. Never sell unlocks."
// CLAUDE.md "Conventions": "No restrictive goals ever... this is a product-safety rule, not a
// style preference," and this task's own brief goes further — "enforce that as a hard rule in
// code not just a comment." See "Hard rule: never sell power" below for exactly how this file
// does that structurally, not just by promising to in a doc comment.
//
// This is the engine half of §5.17; the two view files this same task owns
// (`App/ZANO/Features/Trophy/CosmeticsShopView.swift` for browsing/purchasing,
// `App/ZANO/Features/Trophy/TrophyCaseView.swift` for the badge grid) are this file's only
// callers today. `Models/Badge.swift` and `Models/Coin.swift` (Session 1, read in full before
// writing this file, not edited here) already carry everything Trophy Case needs — badges are
// read directly via `@Query` in `TrophyCaseView`, no engine required. Coins are this file's job:
// spending `Coin.balance` on purely-cosmetic purchases.
//
// ── Why cosmetic *ownership* lives in App-Group UserDefaults, not a new SwiftData model ──
//
// The obvious shape for "which cosmetics does this user own, and which is equipped per category"
// is a small SwiftData model (e.g. one row per owned item, or one row per category holding the
// equipped key). This file deliberately does NOT add one. `Store/ModelContainer+AppGroup.swift`
// (Session 1, not owned by this task) keeps a hand-maintained `appGroupModelTypes: [any
// PersistentModel.Type]` array and says outright: a `@Model` type left off that list "would
// compile fine... but silently drop every ... row at runtime" the moment `ModelContext(
// ModelContainer.appGroup)` tries to fetch/insert it — that fetch happens at the call site, not
// at this file's compile time, so a new model here would look correct in review and then lose
// every purchase in the field. Registering a new type in that array is this task's one file this
// task is explicitly told not to touch ("DO NOT edit anything you were not explicitly told to
// own"), so a real `CosmeticOwnership`/`CosmeticEquipped` SwiftData table (with a Postgres mirror
// per spec §13, which also has no `cosmetics_owned`/`cosmetics_equipped` table today) is future
// work for whichever session owns that file next — flagged in this task's `knownIssues`.
//
// A separate, App-Group-backed `UserDefaults` suite is this file's answer instead — the exact
// same escape hatch `StreakEngine.swift` (this same directory) already used for its own
// freeze-week anchor, for the same reason (a schema change it didn't own), keyed distinctly so
// the two files' keys can never collide even though they share the suite. It's also not merely a
// workaround here: docs/spec.md §21.11/§27 "Known Platform Gotchas" require the Shield
// (`ZANOShieldConfig`/`ZANOShieldAction`) and Widget extensions to render from App Group state
// alone, with **no networking and no heavy work** — `SharedDefaults.swift`'s own header explains
// this is exactly the "fast path... without opening the SwiftData store" extensions need. A
// purchased *shield background* cosmetic is precisely the kind of thing `ZANOShieldConfig` will
// eventually need to read to render the actual `ShieldConfiguration` — a future session wiring
// that up can read this file's UserDefaults keys directly, the same way it already reads
// `SharedDefaults`, with no SwiftData store to open at all. This file does not do that wiring
// itself (out of scope — no Shield extension file is in this task's list), but the storage choice
// is the one that makes it possible later, not a stopgap that will need re-architecting.
//
// ── Hard rule: never sell power (spec §5.17, §21; CLAUDE.md) ──
//
// This is enforced structurally, not just documented:
//   1. `CosmeticCategory` is a *closed* enum with exactly the four cosmetic categories §5.17
//      names — theme, ring style, shield background, coach voice pack. There is no fifth case
//      (an "unlock", "streak restore", or "extra freeze") to ever add an item under.
//   2. `CosmeticItem` (the purchasable-thing type) carries only a stable `key`, its
//      `CosmeticCategory`, and a coin price. It has no field that could reference or trigger a
//      `LockSet`/`LockSession`/`Streak`/`TimeBank`/`Goal` mutation — there is nothing on the type
//      *to* wire to power even if a future edit tried to.
//   3. `purchase(_:)` below resolves every purchase against this file's own closed, static
//      `catalog` — by key, category, *and* price — before ever touching `Coin.balance`. A caller
//      cannot construct an arbitrary `CosmeticItem` (e.g. with an invented key or a spoofed
//      price) and have it accepted; only an item that is byte-for-byte one of the ones this file
//      already lists is purchasable. Combined with (1)/(2), the set of things money can ever buy
//      here is fixed at compile time to "one of these four purely-cosmetic categories, at this
//      file's own price" — never a caller-supplied effect.
//   4. `purchase(_:)`'s implementation touches exactly two kinds of state: `Coin.balance` (spend)
//      and this file's own UserDefaults-backed ownership set (record). It never imports or
//      references `LockEngineManager`, `StreakEngine`, `TimeBankEngine`, `Goal`, `LockSet`, or
//      `LockSession` — there is no code path in this file that could grant an unlock, restore a
//      streak, or add Time Bank minutes even by accident.
//
// ── Pro gating (spec §21) ──
//
// §21's tier table lists "cosmetics" under Pro, not Free. This file reads that as gating
// *purchasing* only — badges and Trophy Case viewing stay free for everyone (nothing in §5.17
// itself says otherwise, and gating the badges a Free user already earned behind a paywall would
// contradict spec §8's "endowed progress" rule). `purchase(_:)` checks `User.planTier == .pro`
// the same way `PaywallViewModel.refreshLocalProState()` and `StreakEngine.weeklyFreezeAllowance`
// already do (`Models/User.swift`'s local mirror, not a network call, matching this file's other
// engine siblings). Equipping an item the user already owns is never Pro-gated — only the money
// changing hands is (so a lapsed-Pro user keeps what they already bought, matching spec §8's
// "protective, not fragile" spirit applied to a subscription lapse rather than a streak one; this
// file's own `decisions` call this out as this task's own reading, since spec doesn't address the
// downgrade case explicitly).
//
// Zero user-facing strings live in this file (CLAUDE.md: "user-facing copy lives in
// Core/Sources/Core/Copy — no hardcoded UI strings elsewhere"), matching `StreakEngine`'s own
// convention — this is pure spending logic with no copy to get wrong. `CosmeticsShopView.swift`
// (this same task, the other Core-adjacent file) is where `Copy.cosmetics.*` display strings and
// SF Symbol icon lookups for each catalog key live, the same split `Badge.swift`/`Copy.badges`/
// `ProgressBadgeIconMap` already established for badges.

import Foundation
import Observation
import SwiftData
import os

// MARK: - Category (closed — see "Hard rule: never sell power" above)

/// The four, and only four, kinds of cosmetic a user can own — exactly docs/spec.md §5.17's list
/// ("themes, ring styles, shield backgrounds, and coach voice packs"). Closed by design: adding a
/// fifth case here is the one place a future edit would have to touch to even attempt selling
/// something that isn't cosmetic, which keeps that decision visible in review rather than buried
/// in a `purchase(_:)` call site.
public enum CosmeticCategory: String, Codable, CaseIterable, Sendable {
    case theme
    case ringStyle = "ring_style"
    case shieldBackground = "shield_background"

    /// A purely decorative "skin" for how the user's chosen coach voice is presented (e.g. an
    /// alternate persona/avatar treatment, bonus flavor lines) — **not** a way to buy a different
    /// `CoachVoice` itself. `User.coachVoice` (`Models/User.swift`) and its four voices (Hype /
    /// Tough Love / Chill / Data) are a free onboarding choice (spec §7 Q6) that drives real copy
    /// generation everywhere (`Copy/CoachVoice.swift`'s `CoachVoiceTone`) — this file never reads
    /// or writes `User.coachVoice` and a coach-voice-pack purchase never changes which of the
    /// four voices generates a user's copy. Rendering what an equipped pack actually changes is
    /// future work for whichever screen ends up showing it (no such screen is in this task's
    /// file list) — see `knownIssues`.
    case coachVoicePack = "coach_voice_pack"
}

// MARK: - Catalog item (closed set of fields — see "Hard rule: never sell power" above)

/// One ownable/equippable cosmetic. Only reference data — a stable, non-user-facing `key` (the
/// exact same pattern `Badge.key` documents: "looked up in Copy for its display title/
/// description... this model never stores display text itself"), its `category`, and its coin
/// price. `CosmeticsShopView.swift` (this task's other file) is where `key` resolves to an actual
/// title/description/icon.
public struct CosmeticItem: Identifiable, Hashable, Sendable {
    public var id: String { key }

    /// Stable, non-user-facing identifier, e.g. `"theme_electric_blue"`. Namespaced with a
    /// per-category prefix so keys stay unique across categories at a glance even though
    /// uniqueness is only actually enforced within `CosmeticsStore.catalog` (two different
    /// categories are never expected to share a key, but nothing besides convention prevents it).
    public let key: String
    public let category: CosmeticCategory
    public let priceCoins: Int

    /// `true` for the one free, always-owned, always-equippable item each category starts with
    /// (e.g. the existing look every user already has before spending a single coin). Exactly one
    /// `CosmeticItem` per `CosmeticCategory` in `CosmeticsStore.catalog` should set this `true`;
    /// `CosmeticsStore.defaultItem(for:)` is what the rest of this file relies on that invariant
    /// for.
    public let isDefault: Bool

    public init(key: String, category: CosmeticCategory, priceCoins: Int, isDefault: Bool = false) {
        self.key = key
        self.category = category
        self.priceCoins = priceCoins
        self.isDefault = isDefault
    }
}

// MARK: - Outcomes

/// Result of `CosmeticsStore.purchase(_:)`. Deliberately not a thrown error: every case here is
/// an expected, UI-actionable outcome (insufficient coins, needs Pro, ...) rather than a system
/// failure, matching `RevenueCatManager`'s own `PurchaseResult`-style enum over throwing for the
/// same reason (a declined purchase isn't a bug).
public enum CosmeticPurchaseOutcome: Sendable, Equatable {
    /// Debited and recorded as owned.
    case purchased
    /// Already owned (or `isDefault`) — no coins spent, nothing changed.
    case alreadyOwned
    /// `Coin.balance` is short by this many coins.
    case insufficientCoins(shortBy: Int)
    /// `User.planTier != .pro` (spec §21 — cosmetics purchasing is a Pro perk).
    case proRequired
    /// No local `User` row exists yet.
    case noSignedInUser
    /// `item` does not match anything in `CosmeticsStore.catalog` by key **and** category **and**
    /// price — see "Hard rule: never sell power" above for why this check exists at all.
    case unknownItem
    /// The `Coin` debit failed to persist (SwiftData save error). Coins were not spent and the
    /// item was not recorded as owned.
    case storeFailure
}

/// Result of `CosmeticsStore.equip(_:)`.
public enum CosmeticEquipOutcome: Sendable, Equatable {
    case equipped
    /// The item isn't owned (and isn't the category's free default), so it can't be equipped.
    case notOwned
}

// MARK: - CosmeticsStore

/// Spends `Coin.balance` on purely-cosmetic items and tracks what's owned/equipped.
/// `.shared` singleton (mirrors `StreakEngine`'s convention: a small Retention engine every
/// screen that needs it reaches through one process-wide instance, not a per-screen view model)
/// and `@Observable` (mirrors `PaywallViewModel`'s convention: `CosmeticsShopView`/`TrophyCaseView`
/// read `coinBalance`/`isProSubscriber` straight off `.shared` inside their `body`s and get
/// automatic re-renders on purchase/equip — no extra wrapper view model needed for that).
///
/// `@MainActor`: touches a `ModelContext` (not `Sendable`) and drives SwiftUI state directly, the
/// same reasoning `StreakEngine`/`PaywallViewModel` each document at their own declaration.
@MainActor
@Observable
public final class CosmeticsStore {
    public static let shared = CosmeticsStore()

    // MARK: Published state

    /// Mirrors the signed-in user's `Coin.balance`. `0` before the first `refresh()`/mutation, or
    /// if there's no local `User`/`Coin` row yet.
    public private(set) var coinBalance: Int = 0

    /// Local mirror of `User.planTier == .pro` (spec §21) — the same "cheap, synchronous local
    /// substitute" `PaywallViewModel.isProSubscriber` documents, reused here rather than calling
    /// `RevenueCatManager` (a network-backed check this purely-local spending logic shouldn't
    /// depend on).
    public private(set) var isProSubscriber = false

    /// Every non-default key this user has purchased. Default items are always considered owned
    /// (`isOwned(_:)`) without needing an entry here.
    public private(set) var ownedKeys: Set<String> = []

    /// The equipped item's key per category, only for categories where the user has explicitly
    /// equipped something other than the free default. `equippedItem(for:)` is the total,
    /// default-falling-back accessor everything else should call instead of reading this
    /// directly.
    public private(set) var equippedKeys: [CosmeticCategory: String] = [:]

    // MARK: Dependencies

    private let modelContainer: ModelContainer
    @ObservationIgnored private lazy var context = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "CosmeticsStore")

    /// Separate App-Group `UserDefaults` instance — see this file's header ("Why cosmetic
    /// ownership lives in App-Group UserDefaults") for why, and why its keys below are namespaced
    /// distinctly from every key `Store/SharedDefaults.swift` or `StreakEngine`'s own
    /// `freezeDefaults` already define, so all three can share the suite with zero collision risk.
    private let ownershipDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private enum DefaultsKeys {
        static let ownedKeys = "com.zano.app.cosmeticsStore.ownedKeys.v1"
        static let equippedKeys = "com.zano.app.cosmeticsStore.equippedKeys.v1"
    }

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container — mirrors `StreakEngine`'s own convention. Every real call site uses
    /// `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
        loadOwnershipFromDisk()
        refreshLocalState()
    }

    // MARK: - Catalog (see "Hard rule: never sell power" above)

    /// The complete, closed set of purchasable cosmetics. Exactly one `isDefault` item per
    /// `CosmeticCategory`. Keys, categories, and prices here are this task's own placeholder
    /// content — spec §5.17 names the four *categories* exactly but gives no concrete item list
    /// or pricing, and there is no design/content pass for this yet — flagged as an assumption in
    /// this task's `decisions`. Whoever implements `Copy.cosmetics.*` needs display copy for
    /// every key below; `CosmeticsShopView.swift`'s header lists them all explicitly for that.
    public static let catalog: [CosmeticItem] = [
        // Themes — an accent/skin variant layered on Theme.swift's fixed dark palette (that
        // file's own header: "a single, fixed dark palette, not a light/dark adaptive theme" —
        // a purchased theme re-skins within that constraint, it doesn't add a light mode).
        CosmeticItem(key: "theme_classic", category: .theme, priceCoins: 0, isDefault: true),
        CosmeticItem(key: "theme_electric_blue", category: .theme, priceCoins: 250),
        CosmeticItem(key: "theme_magenta_pulse", category: .theme, priceCoins: 250),
        CosmeticItem(key: "theme_gold_rush", category: .theme, priceCoins: 400),
        CosmeticItem(key: "theme_ice_mint", category: .theme, priceCoins: 250),

        // Ring styles — how a GoalRing's stroke renders (`Core/Sources/Core/UI/Components/
        // GoalRing.swift`, not owned by this task; a future session wires the equipped style in).
        CosmeticItem(key: "ring_solid", category: .ringStyle, priceCoins: 0, isDefault: true),
        CosmeticItem(key: "ring_gradient_sweep", category: .ringStyle, priceCoins: 200),
        CosmeticItem(key: "ring_dashed_pulse", category: .ringStyle, priceCoins: 200),
        CosmeticItem(key: "ring_glow_trail", category: .ringStyle, priceCoins: 350),
        CosmeticItem(key: "ring_double_ring", category: .ringStyle, priceCoins: 350),

        // Shield backgrounds — the backdrop behind the blocked-app Shield screen
        // (`ShieldPreview.swift` in-app, `ZANOShieldConfig` for the real thing; neither owned by
        // this task).
        CosmeticItem(key: "shield_classic", category: .shieldBackground, priceCoins: 0, isDefault: true),
        CosmeticItem(key: "shield_city_skyline", category: .shieldBackground, priceCoins: 300),
        CosmeticItem(key: "shield_gym_floor", category: .shieldBackground, priceCoins: 300),
        CosmeticItem(key: "shield_mountain_dawn", category: .shieldBackground, priceCoins: 300),
        CosmeticItem(key: "shield_abstract_wave", category: .shieldBackground, priceCoins: 450),

        // Coach voice packs — see `CosmeticCategory.coachVoicePack`'s doc comment: decorative
        // only, never changes `User.coachVoice`.
        CosmeticItem(key: "coachpack_stock", category: .coachVoicePack, priceCoins: 0, isDefault: true),
        CosmeticItem(key: "coachpack_captain_intensity", category: .coachVoicePack, priceCoins: 250),
        CosmeticItem(key: "coachpack_zen_minimal", category: .coachVoicePack, priceCoins: 250),
        CosmeticItem(key: "coachpack_data_stream", category: .coachVoicePack, priceCoins: 250),
        CosmeticItem(key: "coachpack_hype_squad", category: .coachVoicePack, priceCoins: 250),
    ]

    /// `catalog` filtered to one category, in catalog order (default item first).
    public static func items(in category: CosmeticCategory) -> [CosmeticItem] {
        catalog.filter { $0.category == category }
    }

    /// The category's free, always-owned starting item. Falls back to a synthesized zero-price
    /// placeholder rather than crashing if `catalog` is ever missing one for a category (it
    /// shouldn't be — see `catalog`'s own doc comment — but nothing here should ever force-unwrap
    /// on catalog content).
    public static func defaultItem(for category: CosmeticCategory) -> CosmeticItem {
        catalog.first { $0.category == category && $0.isDefault }
            ?? CosmeticItem(key: "\(category.rawValue)_default", category: category, priceCoins: 0, isDefault: true)
    }

    // MARK: - Ownership / equipped queries

    public func isOwned(_ item: CosmeticItem) -> Bool {
        item.isDefault || ownedKeys.contains(item.key)
    }

    public func isEquipped(_ item: CosmeticItem) -> Bool {
        equippedItem(for: item.category).key == item.key
    }

    /// The currently-equipped item for `category` — whatever was last `equip(_:)`ed, or that
    /// category's free default if nothing has been equipped yet.
    public func equippedItem(for category: CosmeticCategory) -> CosmeticItem {
        if let key = equippedKeys[category],
           let item = Self.catalog.first(where: { $0.key == key && $0.category == category }) {
            return item
        }
        return Self.defaultItem(for: category)
    }

    // MARK: - Refresh

    /// Re-reads `Coin.balance` and `User.planTier` from SwiftData. Call from a screen's `.task`
    /// on appear — coins/plan tier can change from elsewhere (a badge/duel coin award, a
    /// completed Pro purchase in `PaywallViewModel`) that this singleton doesn't otherwise observe.
    public func refresh() async {
        refreshLocalState()
    }

    private func refreshLocalState() {
        guard let user = try? fetchCurrentUser() else {
            coinBalance = 0
            isProSubscriber = false
            return
        }
        coinBalance = fetchOrCreateCoin(userID: user.id).balance
        isProSubscriber = user.planTier == .pro
    }

    // MARK: - Purchase (see "Hard rule: never sell power" / "Pro gating" above)

    /// Attempts to buy `item`. Never throws — every failure mode is a normal, UI-actionable
    /// `CosmeticPurchaseOutcome` case, not an exceptional one (mirrors `StreakEngine`'s CONTRACTS
    /// methods never propagating an error outward, for the same reason: a spending screen must
    /// always be able to show *something* rather than crash).
    @discardableResult
    public func purchase(_ item: CosmeticItem) async -> CosmeticPurchaseOutcome {
        // Hard rule enforcement: only an item that is byte-for-byte in this file's own closed
        // catalog — same key, same category, same price — is ever purchasable. A caller cannot
        // get a discount, a different category's price, or an item this file doesn't already
        // list accepted here.
        guard let catalogItem = Self.catalog.first(where: { $0.key == item.key }),
              catalogItem.category == item.category,
              catalogItem.priceCoins == item.priceCoins
        else {
            logger.error("purchase: \(item.key, privacy: .public) is not in CosmeticsStore.catalog — refusing.")
            return .unknownItem
        }

        guard !catalogItem.isDefault, !ownedKeys.contains(catalogItem.key) else {
            return .alreadyOwned
        }

        guard let user = try? fetchCurrentUser() else {
            logger.error("purchase: no local User row — cannot purchase.")
            return .noSignedInUser
        }

        guard user.planTier == .pro else {
            return .proRequired
        }

        let coin = fetchOrCreateCoin(userID: user.id)
        guard coin.balance >= catalogItem.priceCoins else {
            return .insufficientCoins(shortBy: catalogItem.priceCoins - coin.balance)
        }

        coin.balance -= catalogItem.priceCoins
        do {
            try context.save()
        } catch {
            // Roll back the in-memory debit so `coin.balance` (still attached to `context`)
            // doesn't drift from what's actually on disk if this same `Coin` is read again
            // before the next successful save.
            coin.balance += catalogItem.priceCoins
            logger.error("purchase: failed to save Coin debit for \(catalogItem.key, privacy: .public): \(String(describing: error), privacy: .public)")
            return .storeFailure
        }

        ownedKeys.insert(catalogItem.key)
        persistOwnedKeys()
        coinBalance = coin.balance
        return .purchased
    }

    // MARK: - Equip

    /// Equips `item` as the active choice for its category. Requires the item to already be
    /// owned (or be its category's free default) — equipping is never itself Pro-gated (see this
    /// file's header, "Pro gating").
    @discardableResult
    public func equip(_ item: CosmeticItem) -> CosmeticEquipOutcome {
        guard let catalogItem = Self.catalog.first(where: { $0.key == item.key && $0.category == item.category }),
              isOwned(catalogItem)
        else {
            return .notOwned
        }
        equippedKeys[catalogItem.category] = catalogItem.key
        persistEquippedKeys()
        return .equipped
    }

    // MARK: - UserDefaults ownership store

    private func loadOwnershipFromDisk() {
        if let data = ownershipDefaults.data(forKey: DefaultsKeys.ownedKeys),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            ownedKeys = decoded
        }
        if let data = ownershipDefaults.data(forKey: DefaultsKeys.equippedKeys),
           let decodedRaw = try? JSONDecoder().decode([String: String].self, from: data) {
            var decoded: [CosmeticCategory: String] = [:]
            for (rawCategory, key) in decodedRaw {
                if let category = CosmeticCategory(rawValue: rawCategory) {
                    decoded[category] = key
                }
            }
            equippedKeys = decoded
        }
    }

    private func persistOwnedKeys() {
        guard let data = try? JSONEncoder().encode(ownedKeys) else { return }
        ownershipDefaults.set(data, forKey: DefaultsKeys.ownedKeys)
    }

    private func persistEquippedKeys() {
        let raw = Dictionary(uniqueKeysWithValues: equippedKeys.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        ownershipDefaults.set(data, forKey: DefaultsKeys.equippedKeys)
    }

    // MARK: - SwiftData

    private func fetchOrCreateCoin(userID: UUID) -> Coin {
        var descriptor = FetchDescriptor<Coin>(predicate: #Predicate { $0.userID == userID })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let coin = Coin(userID: userID)
        context.insert(coin)
        return coin
    }

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment) — same convention `StreakEngine.fetchCurrentUser()` uses.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw CosmeticsStoreError.noSignedInUser
        }
        return user
    }
}

/// Errors this file's private `fetchCurrentUser()` throws internally. Never propagated out of any
/// public method (mirrors `StreakEngineError`'s convention) — kept only so that helper has a
/// typed failure to `try?` at each call site.
enum CosmeticsStoreError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
