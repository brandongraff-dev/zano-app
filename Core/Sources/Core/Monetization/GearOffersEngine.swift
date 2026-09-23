// Core/Sources/Core/Monetization/GearOffersEngine.swift
//
// docs/spec.md §25.6 "In-app store behavior":
//   "The app is the store and the CRM: Settings → Gear, contextual offers ('You've logged 40
//   shakes — here's the bottle that logs itself'), Sunrise Alarm setup prompting a tag pack,
//   reorder prompts when a tub is likely empty, and earned-card shipping prompts at milestones."
// Cross-referenced against §25.0 (launch lineup / COGS / price), §25.1 (Tag Pack), §25.3 (★ Earned
// Cards — 30/100/365-day streak milestones → Bronze/Silver/Diamond), §25.4 (Shaker with embedded
// tag), §25.5 ("Store: Shopify, linked from Settings → Gear... plus TikTok Shop"), and §5.10
// (Sunrise Alarm's tag-dismiss variant), plus `docs/hardware/tag-pack-spec.md` and
// `docs/hardware/lock-card-spec.md` for the exact product line this engine deep-links to.
//
// This task's own scope (per its brief): "evaluates trigger conditions against real
// GoalEvent/Streak history and returns a typed offer to show, deep-linking to docs/hardware's
// described products (no live store exists yet - use a placeholder URL clearly marked TODO)." —
// a logic file only. It does NOT wire itself into any screen (no `App/ZANO/Features/**` file is
// touched here — a concurrent workflow owns every one of those this run); see `knownIssues` for
// the exact follow-up call site (`Settings → Gear`, per §25.6's own framing, once that screen
// exists and is safe to touch).
//
// MARK: - Decisions this file makes (see this task's own `decisions` output for the short form)
//
// 1. **§25.6's own example line ("You've logged 40 shakes — here's the bottle that logs
//    itself") is read as pointing at the Shaker SKU** (§25.4: "Tap when you drink → protein
//    logged... the first product that's on camera in every gym video"), not the Tag Pack's plain
//    "Bottle" placement tag (§25.1) — a bottle with no embedded logic can't itself "log"
//    anything; the Shaker is the one product in the catalog that actually does. See
//    `Copy/GearOffersCopy.swift`'s own header for the same note.
// 2. **"40 shakes" is read as 40 *verified protein-intake `GoalEvent`s*** (`kind == .log` or
//    `.complete`, any source) for the user's active `.protein` goal — the closest real signal
//    `Models/GoalEvent.swift` exposes to "a shake logged". This intentionally does NOT require
//    `source == .nfc` (i.e. does not require the user to already own a Shaker/Tag): gating a
//    "here's the bottle that logs itself" upsell behind already owning that exact bottle would be
//    circular. It also does not distinguish an actual protein shake from a logged meal — `Models/
//    GoalEvent.swift`/`Models/Meal.swift` have no "this was a shake vs. a plate of chicken" field
//    to distinguish on — flagged as the honest limit of the current data model, not silently
//    assumed away.
// 3. **"reorder prompts when a tub is likely empty" (product #4, §25.0's "Protein / electrolyte")
//    has no real inventory model to read from** — no `Models/*.swift` file in this codebase
//    tracks a purchase date, tub size, or remaining-servings count for that not-yet-launched
//    product (confirmed: `Core/Sources/Core/Models` has no `ProteinOrder`/`Inventory`-shaped
//    type as of this task), and building one is out of this task's scope (a `Models/*.swift` file
//    is not in this task's owned file list, and introducing a new `@Model` type would also need
//    `Store/ModelContainer+AppGroup.swift`'s `appGroupModelTypes` updated — another file this
//    task does not own; `Models/KitchenStaple.swift`'s own header documents this exact same class
//    of gap for its own new model). This engine instead reuses the same verified-protein-`GoalEvent`
//    count as decision 2, against an assumed servings-per-tub constant
//    (`estimatedServingsPerProteinTub`), as the best available proxy. **This is a heuristic, not
//    real inventory tracking** — flagged prominently in `knownIssues`.
// 4. **Earned Card milestones (§25.3) reuse `Retention/StreakEngine.swift`'s existing
//    `currentStreak()` CONTRACTS method** (read-only call — this file never mutates `Streak`,
//    consistent with "StreakEngine is the sole owner of mutating the one `Streak` row per user",
//    `Models/Streak.swift`'s own doc comment) rather than re-deriving streak length from raw
//    `GoalEvent` history itself.
// 5. **Sunrise Alarm → Tag Pack (§25.6 bullet 2) reads `Verification/SunriseAlarmManager.swift`'s
//    already-public `currentSettings()`** (a read-only call to another task's file — explicitly
//    allowed per this run's own instructions: reading a non-owned file, without editing it, is
//    fine) to detect "has an active Sunrise Alarm goal, but isn't dismissing via the physical Tag
//    yet" — the one condition under which recommending a Tag Pack purchase is actually useful
//    (a user already dismissing via Tag already has one).
// 6. **`GearProductID.deepLinkURL`'s placeholder host reuses `https://gear.zano.app`, not an
//    independently-invented domain.** `App/ZANO/Features/Settings/SettingsView.swift` (read-only —
//    on this run's forbidden-to-write list) already declares `SettingsReferenceData.gearStoreURL =
//    URL(string: "https://gear.zano.app")!` with the identical "placeholder pending a real domain"
//    caveat. Matching it here means the two independent placeholders converge on one guess instead
//    of two different ones a future session would have to reconcile.
// 7. **REAL, CONFIRMED DUPLICATION — flagged, not fixed here** (same shape of gap `Verification/
//    QuickRepeatSuggester.swift`'s own header documents for `FuelView.swift`'s independent
//    heuristic): `SettingsView.swift` already ships its own inline `contextualGearOffer: String?`
//    computed property (its "Gear (spec §25.6)" section) implementing a narrower, independent
//    version of two of this file's four triggers directly against `@Query private var recentEvents:
//    [GoalEvent]` / `@Query private var streaks: [Streak]`, with real, visible differences from this
//    file's own read of the same spec bullet:
//      - Its shaker trigger requires `source == .nfc` (i.e. only counts taps that already came
//        through a physical NFC tag/shaker) — this file's `verifiedProteinLogCount` deliberately
//        does not (see decision 2 above: gating a "here's the bottle" upsell behind already owning
//        that exact bottle is circular).
//      - Its earned-card check is `[30, 100, 365].contains(streak.current)` — an exact-day match
//        with no persistence, so it silently stops appearing the moment `current` ticks past the
//        milestone (even if never seen/acted on), and reappears with no memory of a prior dismissal
//        if a streak break + rebuild ever lands exactly back on 30. This file's `dismissals` log
//        (decision 8 below) instead persists per-milestone-id state and cascades highest-tier-first.
//      - It never implements the Sunrise Tag Pack (§25.6 bullet 2) or reorder-tub (§25.6 bullet 3)
//        triggers at all.
//    `SettingsView.swift` is explicitly off-limits to write this run (owned by a concurrent
//    workflow) even though reading it is fine — this file's own brief is explicit that UI wiring is
//    a follow-up, not this task's job. The real fix for a future session: delete `SettingsView.
//    swift`'s inline `contextualGearOffer` and its two backing `@Query` properties, and call
//    `GearOffersEngine.shared.bestOffer()` (or `.evaluateOffers()` for a full list) from `gearSection`
//    instead — CLAUDE.md's "never duplicate the same logic in two places" rule, made concrete.
// 8. **Dismissal/idempotency is this file's own concern**, not `Badge`'s: an earlier draft of
//    this file considered awarding `Badge(key: "streak_30")`-style rows (those exact keys are
//    already reserved and displayed by `Copy/TrophyCosmeticsCopy.swift`'s `Copy.badges.
//    fixedTitles`, but nothing in this codebase currently awards them) to double as this engine's
//    "already offered" signal. Rejected: conflating "the user was shown a shipping-confirmation
//    commerce prompt" with "the user earned a trophy" is the wrong coupling, and inserting into a
//    shared `@Model` type from a monetization engine is a bigger, riskier surface than this task's
//    scope calls for (CLAUDE.md: "don't add abstractions... beyond what the current session's
//    scope requires"). This file keeps its own small, App-Group-backed `UserDefaults` dismissal
//    log instead — same pattern `Retention/StreakEngine.swift`'s own `freezeDefaults`/
//    `Verification/SunriseAlarmManager.swift`'s own `defaults` already establish for "a small bit
//    of engine-private state with no dedicated `@Model` column".
//
// MARK: - `#Predicate` conservatism
//
// Every fetch below follows this codebase's now-consistent convention (`Retention/
// StreakEngine.swift`, `Verification/SunriseAlarmManager.swift`, `Verification/
// QuickRepeatSuggester.swift`): a `#Predicate` may compare simple `Bool`/`Date` stored properties
// and (per `Intents/IntentSupport.swift`'s own already-relied-upon `event.goal?.id == goalID`
// pattern, which this file's own call sites into that same file already trust to compile) a
// to-one relationship's `id`, but never a custom `Codable` enum like `GoalEvent.kind` — that
// filter always happens in plain Swift after the fetch. No Mac/Swift toolchain exists in this
// environment to compile-check any of this; flagged in `knownIssues`.

import Foundation
import SwiftData
import os

// MARK: - GearProductID

/// Every physical product this engine can point an offer at — the full launch lineup from spec
/// §25.0/§25.2's variants/§25.3's tiers, plus the Product #4 placeholder (`proteinTub`, not yet
/// launched — see decision 3 above).
public enum GearProductID: String, Sendable, CaseIterable, Codable {
    case tagPack = "tag_pack"
    case lockCard = "lock_card"
    case lockCardDesk = "lock_card_desk"
    case lockKey = "lock_key"
    case lockCardMagSafe = "lock_card_magsafe"
    case shaker = "shaker"
    case proteinTub = "protein_tub"
    case earnedCardBronze = "earned_card_bronze"
    case earnedCardSilver = "earned_card_silver"
    case earnedCardDiamond = "earned_card_diamond"

    /// **TODO(store):** placeholder deep link only. Spec §25.5: "Store: Shopify, linked from
    /// Settings → Gear" — no Shopify store (or any live store) exists yet in this repo/session,
    /// per this task's own brief ("no live store exists yet - use a placeholder URL clearly
    /// marked TODO"). Host matches `SettingsView.swift`'s own already-declared
    /// `SettingsReferenceData.gearStoreURL` (`"https://gear.zano.app"`, same "placeholder pending
    /// a real domain" caveat) rather than a second, independently-invented guess — see this
    /// file's header decision 6. This URL exists only so `GearOffer.deepLinkURL` is a real,
    /// well-formed `URL` today (never `nil`, never a crash-prone force-unwrap of malformed input)
    /// and so a future screen has exactly one place to swap in the real Shopify product URL per
    /// SKU, once it exists. **Replace every case's value here before this ever ships to a real
    /// user.**
    public var deepLinkURL: URL {
        // Force-unwrap is safe: every input is a static, hand-written ASCII literal below, never
        // user/network input.
        URL(string: "https://gear.zano.app/\(rawValue)")! // TODO(store): placeholder — no live store yet.
    }
}

// MARK: - GearOfferKind

/// Which of spec §25.6's four bullets this offer is. Kept distinct from `GearProductID` (an offer
/// *kind* can, in principle, point at more than one product — e.g. a future "you're a Squad of
/// gym-goers" offer for `lockKey`), even though today each kind happens to map to exactly one
/// product.
public enum GearOfferKind: String, Sendable, CaseIterable {
    /// §25.6 bullet 1 — "You've logged 40 shakes — here's the bottle that logs itself."
    case shakerAfterProteinMilestone = "shaker_after_protein_milestone"
    /// §25.6 bullet 2 — "Sunrise Alarm setup prompting a tag pack."
    case sunriseAlarmTagPack = "sunrise_alarm_tag_pack"
    /// §25.6 bullet 3 — "reorder prompts when a tub is likely empty."
    case reorderProteinTub = "reorder_protein_tub"
    /// §25.6 bullet 4 — "earned-card shipping prompts at milestones."
    case earnedCardShipping = "earned_card_shipping"
}

// MARK: - GearOffer

/// One fully-composed, ready-to-render contextual offer. `Foundation`-only (no SwiftUI import),
/// so a widget timeline, a push-notification payload builder, or a plain SwiftUI screen can all
/// consume the same value — mirrors `GhostMode.GhostComparison`'s own "plain data type, not a
/// view" shape, which `UI/Components/GhostProgressBanner.swift` renders.
public struct GearOffer: Identifiable, Equatable, Sendable {
    /// Stable per-instance identity, used both as this struct's `Identifiable` id and as the key
    /// `GearOffersEngine` dismissals are recorded/checked against (see
    /// `GearOffersEngine.dismiss(_:on:)`). For a milestone-crossing offer (shaker, reorder), this
    /// encodes the exact threshold crossed (e.g. `"shaker_offer_shakes_40"`) so dismissing *this*
    /// instance never silences the *next* threshold's offer (80, 120, ...) — each is a distinct,
    /// re-triggerable id by construction. For a continuously-true-condition offer (Sunrise Tag
    /// Pack), the id is stable and dismissal instead uses `reofferInterval` as a cooldown.
    public let id: String
    public let kind: GearOfferKind
    public let product: GearProductID
    public let headline: String
    public let body: String
    public let ctaLabel: String
    /// **TODO(store):** see `GearProductID.deepLinkURL`'s own doc comment — this is that same
    /// placeholder, carried onto the offer so a caller never has to re-resolve `product` back to
    /// a URL itself.
    public let deepLinkURL: URL
    /// `nil` for a one-shot-per-threshold offer (dismissing it is final until the *next*
    /// threshold produces a new `id`). Non-`nil` for a continuously-true-condition offer: how
    /// long a dismissal silences this exact `id` before it's eligible to resurface (still subject
    /// to its underlying condition still being true).
    public let reofferInterval: TimeInterval?

    public init(
        id: String,
        kind: GearOfferKind,
        product: GearProductID,
        headline: String,
        body: String,
        ctaLabel: String,
        deepLinkURL: URL,
        reofferInterval: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.product = product
        self.headline = headline
        self.body = body
        self.ctaLabel = ctaLabel
        self.deepLinkURL = deepLinkURL
        self.reofferInterval = reofferInterval
    }
}

// MARK: - GearOffersEngine

/// Evaluates every §25.6 trigger against real `GoalEvent`/`Streak` history and returns the
/// currently-eligible contextual offer(s).
///
/// `@MainActor final class` with a `.shared` singleton and an injectable `modelContainer` — same
/// reasoning `Retention/StreakEngine.swift`/`Verification/QuickRepeatSuggester.swift` each give at
/// their own declaration: every realistic call site (a future Settings → Gear screen, a widget
/// timeline provider) is already on the main actor or happy to hop onto it, and a `@MainActor
/// final class` is implicitly `Sendable`, which is what lets `.shared` stay callable from any
/// isolation domain despite owning a non-`Sendable` `ModelContext`.
@MainActor
public final class GearOffersEngine {
    public static let shared = GearOffersEngine()

    // MARK: Tunables (public, explainable-heuristic constants — mirrors `QuickRepeatSuggester`'s
    // own fully-public-tunables convention so another session, or a future unit test, can read or
    // override these without reverse-engineering magic numbers).

    /// Spec §25.6's own example number, verbatim: "You've logged 40 shakes". Not a guess.
    public static let shakesPerShakerOffer = 40

    /// **Assumption, not a spec number** (see this file's header decision 3): a typical whey
    /// protein tub is commonly sized around 25–30 servings; `30` is picked as a round, slightly
    /// conservative middle of that range so this engine under-prompts rather than nags before a
    /// real tub would plausibly be empty. Revisit once product #4 (§25.0) actually ships with a
    /// real serving size.
    public static let estimatedServingsPerProteinTub = 30

    /// How long the Sunrise Alarm → Tag Pack prompt (a continuously-true condition, not a
    /// threshold crossing — see `GearOffer.reofferInterval`'s own doc comment) stays quiet after
    /// being dismissed before it's eligible to resurface. Not spec-pinned; ~3 weeks is picked to
    /// be well clear of "annoying" (spec §5.22's own framing for a *different* feature, but the
    /// same product spirit applies here) while still eventually reminding a user who never
    /// actually bought a Tag Pack.
    public static let sunriseTagPackReofferInterval: TimeInterval = 21 * 24 * 60 * 60

    /// Safety cap on how many verified `GoalEvent` rows a single protein-history fetch reads —
    /// same "don't let one extremely heavy user's lifetime history make every call unboundedly
    /// expensive" tradeoff `Verification/QuickRepeatSuggester.swift`'s own `historyFetchLimit`
    /// documents. Sorted newest-first, so if this cap is ever actually hit, only the *oldest*
    /// events for an exceptionally long-tenured, exceptionally heavy logger are excluded — this
    /// engine's milestone counters would undercount for that one user, never crash or hang.
    public static let proteinEventHistoryFetchLimit = 4_000

    /// Spec §25.3's exact three milestones, ordered highest-tier first (see
    /// `earnedCardShippingOffer(userID:asOf:dismissals:)`'s own doc comment for why highest-first
    /// is the intended cascade behavior, not an arbitrary ordering).
    private static let earnedCardMilestones: [(threshold: Int, product: GearProductID, tierName: String)] = [
        (365, .earnedCardDiamond, "Diamond"),
        (100, .earnedCardSilver, "Silver"),
        (30, .earnedCardBronze, "Bronze"),
    ]

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GearOffersEngine")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container — mirrors `StreakEngine`/`QuickRepeatSuggester`'s own convention.
    /// Every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public contract

    /// Every currently-eligible offer, most-time-sensitive first (earned-card shipping, since
    /// that's a real physical shipment waiting on the user's address; then the shaker milestone;
    /// then the Sunrise Alarm prompt; then the reorder-tub heuristic). Never throws — a missing
    /// local `User` row or a fetch failure just means "nothing to offer right now", mirroring
    /// `StreakEngine`/`QuickRepeatSuggester`'s identical CONTRACTS-style non-throwing convention.
    ///
    /// At most one offer per `GearOfferKind` is ever returned (each private builder below returns
    /// at most one `GearOffer?`) — deliberately not "every milestone ever crossed", so a caller
    /// showing all of these at once (e.g. a future Settings → Gear "offers for you" section) never
    /// shows a wall of redundant shaker-milestone cards.
    public func evaluateOffers(asOf date: Date = .now) async -> [GearOffer] {
        guard let user = try? fetchCurrentUser() else {
            logger.notice("evaluateOffers: no local User row — nothing to offer.")
            return []
        }
        let userID = user.id
        let dismissals = loadDismissals()

        var offers: [GearOffer] = []
        if let offer = await earnedCardShippingOffer(userID: userID, asOf: date, dismissals: dismissals) {
            offers.append(offer)
        }
        if let offer = shakerOffer(userID: userID, dismissals: dismissals) {
            offers.append(offer)
        }
        if let offer = await sunriseTagPackOffer(userID: userID, asOf: date, dismissals: dismissals) {
            offers.append(offer)
        }
        if let offer = reorderProteinTubOffer(userID: userID, dismissals: dismissals) {
            offers.append(offer)
        }
        return offers
    }

    /// Convenience for a single-card surface (e.g. one contextual card on Today/Progress, once a
    /// future task wires this in — see this file's header): the single highest-priority eligible
    /// offer, or `nil` if none apply right now.
    public func bestOffer(asOf date: Date = .now) async -> GearOffer? {
        await evaluateOffers(asOf: date).first
    }

    /// Records that `offer` was shown to the user, and dismisses it: for a milestone-crossing
    /// `id` (shaker/reorder/earned-card), this instance never resurfaces (the *next* threshold
    /// produces a fresh `id`, per `GearOffer.id`'s own doc comment); for a continuous-condition
    /// `id` (Sunrise Tag Pack), it resurfaces once `reofferInterval` elapses if its underlying
    /// condition is still true.
    public func dismiss(_ offer: GearOffer, on date: Date = .now) {
        var dismissals = loadDismissals()
        dismissals[offer.id] = date
        saveDismissals(dismissals)
        Analytics.shared.capture(event: "gear_offer_dismissed", properties: [
            "offer_id": offer.id,
            "kind": offer.kind.rawValue,
            "product": offer.product.rawValue,
        ])
    }

    /// Fire-and-forget impression logging (spec §23: "Instrument from day one... every screen
    /// view"). Safe to call every time a caller actually renders an offer; does not affect
    /// eligibility.
    public func recordShown(_ offer: GearOffer) {
        Analytics.shared.capture(event: "gear_offer_shown", properties: [
            "offer_id": offer.id,
            "kind": offer.kind.rawValue,
            "product": offer.product.rawValue,
        ])
    }

    /// Fire-and-forget CTA-tap logging. Does not itself dismiss the offer or open
    /// `offer.deepLinkURL` — that's the caller's job (a future screen deciding how to present the
    /// placeholder store link, e.g. `openURL`), matching every other engine in this codebase never
    /// reaching into UIKit/SwiftUI presentation APIs itself.
    public func recordTapped(_ offer: GearOffer) {
        Analytics.shared.capture(event: "gear_offer_tapped", properties: [
            "offer_id": offer.id,
            "kind": offer.kind.rawValue,
            "product": offer.product.rawValue,
        ])
    }

    // MARK: - §25.6 bullet 4: Earned Card shipping prompts at milestones (spec §25.3)

    /// Walks §25.3's three milestones **highest-tier first** and returns the first one that's
    /// both reached (`streak >= threshold`) and not yet dismissed. This is a deliberate cascade,
    /// not an arbitrary scan order: a user who has raced straight past 30 and 100 to a 400-day
    /// streak should be asked to confirm shipping for the Diamond card they *just* earned first,
    /// not be re-asked about a Bronze card from months ago before ever seeing the Diamond prompt.
    /// Once Diamond is dismissed, the next call naturally falls through to Silver, then Bronze,
    /// if either was never individually confirmed — each tier is a real, distinct physical
    /// shipment per spec §25.3, so surfacing all three (one at a time, across separate app opens)
    /// is correct, not redundant.
    private func earnedCardShippingOffer(userID: UUID, asOf date: Date, dismissals: [String: Date]) async -> GearOffer? {
        let streak = await StreakEngine.shared.currentStreak()
        for milestone in Self.earnedCardMilestones where streak >= milestone.threshold {
            let id = "earned_card_shipping_streak_\(milestone.threshold)"
            guard dismissals[id] == nil else { continue }
            return GearOffer(
                id: id,
                kind: .earnedCardShipping,
                product: milestone.product,
                headline: Copy.gearOffers.earnedCardHeadline(tierName: milestone.tierName),
                body: Copy.gearOffers.earnedCardBody(tierName: milestone.tierName),
                ctaLabel: Copy.gearOffers.earnedCardCTA,
                deepLinkURL: milestone.product.deepLinkURL,
                reofferInterval: nil
            )
        }
        return nil
    }

    // MARK: - §25.6 bullet 1: Shaker offer after a protein-logging milestone

    /// See this file's header decisions 1–2 for what "40 shakes" is read as. Fires once per
    /// `shakesPerShakerOffer`-multiple crossed (40, 80, 120, ...), each as its own dismissible
    /// `id`.
    private func shakerOffer(userID: UUID, dismissals: [String: Date]) -> GearOffer? {
        let count = verifiedProteinLogCount(userID: userID)
        let milestone = (count / Self.shakesPerShakerOffer) * Self.shakesPerShakerOffer
        guard milestone > 0 else { return nil }

        let id = "shaker_offer_shakes_\(milestone)"
        guard dismissals[id] == nil else { return nil }
        return GearOffer(
            id: id,
            kind: .shakerAfterProteinMilestone,
            product: .shaker,
            headline: Copy.gearOffers.shakerOfferHeadline(shakesLogged: milestone),
            body: Copy.gearOffers.shakerOfferBody,
            ctaLabel: Copy.gearOffers.shakerOfferCTA,
            deepLinkURL: GearProductID.shaker.deepLinkURL,
            reofferInterval: nil
        )
    }

    // MARK: - §25.6 bullet 2: Sunrise Alarm → Tag Pack

    /// True only while the user has an active `.sunriseAlarm` goal (they've actually turned the
    /// feature on) but their configured dismiss variant isn't `.tag` yet (§5.10's default/intended
    /// variant — a user already on `.tag` already owns a working tag; recommending one again is
    /// pointless). Reads `SunriseAlarmManager.shared.currentSettings()` read-only — see this
    /// file's header decision 5.
    private func sunriseTagPackOffer(userID: UUID, asOf date: Date, dismissals: [String: Date]) async -> GearOffer? {
        guard (try? IntentSupport.activeGoal(ofType: .sunriseAlarm, for: userID, in: context)) != nil else { return nil }

        let settings = await SunriseAlarmManager.shared.currentSettings()
        guard settings.enabled, settings.dismissVariant != .tag else { return nil }

        let id = "sunrise_alarm_tag_pack"
        if let dismissedAt = dismissals[id], date.timeIntervalSince(dismissedAt) < Self.sunriseTagPackReofferInterval {
            return nil
        }
        return GearOffer(
            id: id,
            kind: .sunriseAlarmTagPack,
            product: .tagPack,
            headline: Copy.gearOffers.sunriseTagPackHeadline,
            body: Copy.gearOffers.sunriseTagPackBody,
            ctaLabel: Copy.gearOffers.sunriseTagPackCTA,
            deepLinkURL: GearProductID.tagPack.deepLinkURL,
            reofferInterval: Self.sunriseTagPackReofferInterval
        )
    }

    // MARK: - §25.6 bullet 3: Reorder protein tub (heuristic — see header decision 3)

    /// Fires once per `estimatedServingsPerProteinTub`-multiple of verified protein-`GoalEvent`s
    /// crossed, exactly mirroring `shakerOffer`'s own milestone shape but against a different
    /// threshold and a different message — **not real inventory tracking**; see this file's
    /// header decision 3 and `knownIssues` for what a correct version would need.
    private func reorderProteinTubOffer(userID: UUID, dismissals: [String: Date]) -> GearOffer? {
        let count = verifiedProteinLogCount(userID: userID)
        let milestone = (count / Self.estimatedServingsPerProteinTub) * Self.estimatedServingsPerProteinTub
        guard milestone > 0 else { return nil }

        let id = "reorder_protein_tub_servings_\(milestone)"
        guard dismissals[id] == nil else { return nil }
        return GearOffer(
            id: id,
            kind: .reorderProteinTub,
            product: .proteinTub,
            headline: Copy.gearOffers.reorderProteinHeadline(estimatedScoopsUsed: milestone),
            body: Copy.gearOffers.reorderProteinBody,
            ctaLabel: Copy.gearOffers.reorderProteinCTA,
            deepLinkURL: GearProductID.proteinTub.deepLinkURL,
            reofferInterval: nil
        )
    }

    // MARK: - Shared GoalEvent query

    /// Count of verified `GoalEvent`s (`kind == .log || .complete`) against the user's active
    /// `.protein` goal — the shared signal both `shakerOffer` and `reorderProteinTubOffer` read
    /// (see header decisions 2–3 for why one signal legitimately backs two different offers).
    /// Returns `0` if there's no active protein goal at all, or the fetch fails.
    ///
    /// The predicate filters `goal?.id == goalID` directly (the same relationship-id-equality
    /// `Intents/IntentSupport.swift`'s own `hasVerifiedEventToday`/`recentEventCount` already rely
    /// on compiling); `kind` is filtered afterward, in plain Swift, per this file's header
    /// "`#Predicate` conservatism" note.
    private func verifiedProteinLogCount(userID: UUID) -> Int {
        guard let goal = try? IntentSupport.activeGoal(ofType: .protein, for: userID, in: context) else { return 0 }
        let goalID = goal.id

        var descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.goal?.id == goalID && $0.verified == true }
        )
        descriptor.sortBy = [SortDescriptor(\.ts, order: .reverse)]
        descriptor.fetchLimit = Self.proteinEventHistoryFetchLimit

        guard let events = try? context.fetch(descriptor) else { return 0 }
        return events.filter { $0.kind == .log || $0.kind == .complete }.count
    }

    // MARK: - SwiftData / User lookup

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `StreakEngine.fetchCurrentUser()`/`QuickRepeatSuggester.fetchCurrentUser()` each use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw GearOffersEngineError.noSignedInUser
        }
        return user
    }

    // MARK: - Dismissal log (own App Group `UserDefaults` key — see header decision 8)

    private func loadDismissals() -> [String: Date] {
        guard let data = Self.defaults.data(forKey: Self.dismissalsKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveDismissals(_ dismissals: [String: Date]) {
        guard let data = try? JSONEncoder().encode(dismissals) else { return }
        Self.defaults.set(data, forKey: Self.dismissalsKey)
    }

    /// Mirrors `StreakEngine`/`SunriseAlarmManager`/`NFCTagMapper`'s identical `nonisolated(unsafe)`
    /// App Group `UserDefaults` fallback pattern — created once, never reassigned, only ever
    /// touched from this `@MainActor` type.
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let dismissalsKey = "core.gearOffers.dismissals.v1"
}

/// Errors this file's private `fetchCurrentUser()` throws internally. Never propagated out of
/// `evaluateOffers(asOf:)`/`bestOffer(asOf:)` (both non-throwing by contract, mirroring
/// `StreakEngineError`/`QuickRepeatSuggesterError`'s identical convention) — kept only so that
/// helper has a typed failure to `try?` at its one call site.
enum GearOffersEngineError: Error, Sendable, LocalizedError {
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}
