// Core/Sources/Core/Verification/ProteinGapPlanner.swift
//
// docs/spec.md §5.20 Protein Gap Planner:
//   "At ~4 PM, if the user is behind: three concrete options ranked by proximity and effort —
//   something in their saved kitchen staples, a nearby restaurant item with a deep link, or a
//   quick snack. Closes the gap without opening a recipe app."
// docs/spec.md §10 Food, Protein & Ordering Integrations:
//   "Kitchen staples: user saves 10–20 staples once; the gap planner uses them first."
//   "Restaurant menus: a nutrition API with chain menu data (e.g., Nutritionix — verify current
//   terms/pricing). Combine with location → 'Chipotle chicken bowl, 6 min away, +51g.' Deep link
//   to the restaurant app / DoorDash / Uber Eats search URL."
// docs/spec.md §28 Open Questions: "Which nutrition/restaurant API is worth paying for at
// launch, if any?" — UNRESOLVED. See "Tier 2/3 — extension points" below.
//
// This file lives under Verification/ alongside GymVerifier/FocusSessionVerifier/
// QuickRepeatSuggester rather than a Fuel-specific folder for the same reason
// `QuickRepeatSuggester.swift`'s header gives for itself: deciding which concrete options are
// worth surfacing right now is a verification-adjacent ranking decision, not UI.
//
// Reads `Models/KitchenStaple.swift` (this task's own file, this task's own read of its real,
// current shape — not guessed) directly for Tier 1. Reads `Models/Goal.swift`/`Models/
// GoalEvent.swift` (frozen Session 1 models, read in full before writing this file) only for the
// `Goal`-based convenience overload below; the core `rankedOptions(forGapGrams:userID:)` entry
// point takes a plain `Double` gap and `UUID` user id so it has no dependency on how a caller
// computed "today's remaining gap" in the first place.
//
// *** KNOWN DUPLICATION — flagged, not fixed here (App/ZANO/Features/Fuel/FuelView.swift is a
// different agent's file this task must never touch, per CLAUDE.md/this task's own preamble) ***
// `FuelView.swift` (read in full while building this file, to avoid guessing a shape that
// already exists — its own header documents that it was built in the same batch as this task, in
// parallel, without `KitchenStaple`/`ProteinGapPlanner` existing yet from its point of view) ships
// its own private, independently-written gap-planner heuristic (`FuelView.gapOptions`) RIGHT NOW.
// It does not use `KitchenStaple` at all — its "kitchen staples" tier is actually built from
// `quickRepeats` (recent `Meal` history), because `KitchenStaple` didn't exist yet when it was
// written. This is the exact class of bug this wave's own preamble warns about ("two agents
// independently assuming different shapes for the same thing") — except here it's not a hard
// build break (both compile independently; `FuelView` never references this file), just a real
// product/data inconsistency: a user who saves Kitchen Staples today won't see them in `FuelView`'s
// gap planner at all, and `FuelView`'s restaurant/snack tiers are already live (a static Apple
// Maps search deep link + a hardcoded `FuelReferenceData.quickSnacks` list) where this file
// deliberately stubs those same two tiers pending spec §28. Flagged in this task's `knownIssues`
// as a follow-up consolidation: a future session should point `FuelView.gapOptions` at
// `ProteinGapPlanner.shared.rankedOptions(for:verifiedProteinEventsToday:on:)` instead of its own
// inline heuristic (same kind of refactor `QuickRepeatSuggester.swift`'s header already flags for
// `FuelView`'s independent `quickRepeats` computed property) — not attempted here, since editing
// `FuelView.swift` is outside this task's owned file list.
//
// No Mac/compiler exists to build or run this. Tier 1's fetch/ranking is deliberately split into
// a pure, static, side-effect-free `rank(_:)`/`bestStapleOption(from:gapGrams:)` pair (same
// "testable without a ModelContainer" split `QuickRepeatSuggester`'s clustering functions use) so
// a future session with a working Swift toolchain can unit-test the ranking logic directly in
// `CoreTests` — flagged in this task's `knownIssues` as not yet done here.

import Foundation
import SwiftData
import os

/// The three tiers spec §5.20 describes, in the fixed priority order the spec itself states
/// ("kitchen staples, a nearby restaurant item ..., or a quick snack") — kitchen staples always
/// outrank a restaurant suggestion, which always outranks a quick snack, regardless of proximity.
/// `proximityScore` (see `ProteinGapOption`) only breaks ties *within* a tier, never across tiers;
/// this matches spec's own ordering language rather than a single blended effort+proximity score.
public enum ProteinGapTier: Int, Comparable, Hashable, Sendable {
    case kitchenStaple = 1
    case restaurant = 2
    case quickSnack = 3

    public static func < (lhs: ProteinGapTier, rhs: ProteinGapTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One ranked, concrete option for closing today's remaining protein gap (spec §5.20).
///
/// Intentionally carries no user-facing copy (no "title"/"subtitle" string) — matching
/// `GymAutoDetect.GymCandidate`'s own precedent of returning plain data from Verification/ and
/// letting the caller compose display copy from `Core/Sources/Core/Copy` (CLAUDE.md: "no
/// hardcoded user-facing strings in views" cuts both ways — this layer shouldn't hardcode them
/// either).
public struct ProteinGapOption: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let tier: ProteinGapTier

    /// The `KitchenStaple.id` this option was built from, when `tier == .kitchenStaple`. `nil`
    /// for every other tier (they're not sourced from a saved staple row).
    public let kitchenStapleID: UUID?

    /// User-facing food/item name — e.g. a `KitchenStaple.name` for Tier 1. Never itself
    /// `Copy`-routed (same reasoning `FuelView.swift`'s header already gives for its own
    /// quick-snack reference names: this is per-item real-world data, not persona/coach-voice
    /// copy — spec §5.13's four voices don't apply to "Greek yogurt tub").
    public let name: String

    /// Grams of protein this option provides.
    public let proteinGrams: Double

    /// `abs(proteinGrams - gapGrams)` at the time this option was built — smaller is a closer
    /// match to what's actually needed. Only meaningful for ordering options *within* the same
    /// `tier`; see `ProteinGapTier`'s doc comment for why tier always wins across tiers.
    public let proximityScore: Double

    public init(
        id: UUID = UUID(),
        tier: ProteinGapTier,
        kitchenStapleID: UUID? = nil,
        name: String,
        proteinGrams: Double,
        proximityScore: Double
    ) {
        self.id = id
        self.tier = tier
        self.kitchenStapleID = kitchenStapleID
        self.name = name
        self.proteinGrams = proteinGrams
        self.proximityScore = proximityScore
    }
}

/// Ranks concrete options for closing today's remaining protein gap (spec §5.20). Tier 1 (kitchen
/// staples) is fully real and always available — it only reads the user's own saved
/// `KitchenStaple` rows, no network. Tiers 2 (restaurant) and 3 (quick snack) are deliberately
/// left as clearly-marked, empty-returning extension points: spec §28's open question ("Which
/// nutrition/restaurant API is worth paying for at launch, if any?") is unresolved, and wiring a
/// specific vendor SDK/HTTP client here before that's decided would mean redoing this entire tier
/// (auth, request shape, rate limits, cost) the moment a vendor is actually picked — see each
/// stub's own doc comment below for exactly what a future session should replace it with.
///
/// `@MainActor final class` with a `.shared` singleton and an injectable `modelContainer`:
/// identical reasoning to `QuickRepeatSuggester`'s own declaration-site comment — every realistic
/// call site (a SwiftUI Fuel screen, a 4 PM local notification handler, a widget timeline
/// provider) is already on the main actor or happy to hop onto it, and a `@MainActor final class`
/// is implicitly `Sendable`, which is what lets `.shared` stay callable from any isolation domain.
@MainActor
public final class ProteinGapPlanner {
    public static let shared = ProteinGapPlanner()

    /// Spec §5.20: "At ~4 PM". Exposed so a caller building its own eligibility check (e.g. a
    /// scheduled local notification, or `FuelView`'s own already-shipped `isGapPlannerEligible`)
    /// can share this exact constant instead of re-typing "16" — mirrors `GymAutoDetect`'s own
    /// fully-public tunables for the same reason.
    public nonisolated static let eligibleHour = 16

    /// Upper bound on how many of the user's own saved staples a single lookup fetches. Spec §10
    /// expects "10–20 staples" total per user, so this comfortably covers the real case while
    /// still bounding one pathological user's list from making every call unboundedly expensive
    /// (same defensive-limit reasoning `QuickRepeatSuggester.historyFetchLimit` documents for
    /// itself).
    public nonisolated static let stapleFetchLimit = 200

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "ProteinGapPlanner")

    /// Not `private`, only so `CoreTests` can construct an isolated instance against an in-memory
    /// container — mirrors `QuickRepeatSuggester`/`GymAutoDetect`'s own convention. Every real
    /// call site uses `.shared`.
    ///
    /// `modelContainer: ModelContainer = .appGroup` is the same App Group container every other
    /// Verification/ engine defaults to. `KitchenStaple.self` was briefly missing from that
    /// container's schema (`Core/Sources/Core/Store/ModelContainer+AppGroup.swift`'s
    /// `appGroupModelTypes` — see `KitchenStaple.swift`'s own header comment) — flagged
    /// independently here and in three other files, then closed in that array — so
    /// `kitchenStapleOption(gapGrams:userID:)` below now fetches real rows against the on-device
    /// store rather than silently seeing an empty Tier 1.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public contract

    /// Whether `now` falls in the spec §5.20 eligibility window ("At ~4 PM, if the user is
    /// behind"). Pure convenience — this planner never decides *when* to prompt on its own; a
    /// caller still owns actually invoking it (e.g. `FuelView`'s own `.task`/timer, a scheduled
    /// local notification).
    public nonisolated static func isEligible(gapGrams: Double, now: Date = .now, calendar: Calendar = .current) -> Bool {
        gapGrams > 0 && calendar.component(.hour, from: now) >= eligibleHour
    }

    /// Core entry point: ranks up to 3 concrete options (one per tier that has anything to offer)
    /// for closing `gapGrams` of remaining protein, for the user identified by `userID`. Returns
    /// `[]` (never throws) when `gapGrams <= 0` — matching `QuickRepeatSuggester`'s "no
    /// suggestion right now is not an error condition" contract — or when nothing in any tier is
    /// currently available (e.g. the user has never saved a kitchen staple, and Tiers 2/3 are
    /// still stubs).
    ///
    /// `async` even though today's Tier 1 body is fully synchronous: Tier 2/3, once a vendor is
    /// picked (spec §28), will need a real network round trip, and keeping this signature `async`
    /// now avoids a breaking API change for every caller the moment those tiers go live.
    public func rankedOptions(forGapGrams gapGrams: Double, userID: UUID) async -> [ProteinGapOption] {
        guard gapGrams > 0 else { return [] }

        var options: [ProteinGapOption] = []
        if let staple = kitchenStapleOption(gapGrams: gapGrams, userID: userID) {
            options.append(staple)
        }
        options.append(contentsOf: Self.restaurantOptions(gapGrams: gapGrams))
        options.append(contentsOf: Self.quickSnackOptions(gapGrams: gapGrams))

        return Self.rank(options)
    }

    /// Convenience overload for a caller that already has a protein `Goal` and today's verified
    /// `GoalEvent`s on hand (e.g. via `@Query`, the way `FuelView.swift` already does) — computes
    /// the remaining gap the same way spec §9.1's `AdaptiveGoalEngine.dailyPlan` is meant to be
    /// used everywhere else (today's actual bar, falling back to the goal's static
    /// `targetValue`), then delegates to ``rankedOptions(forGapGrams:userID:)``.
    ///
    /// Returns `[]` (logged, not thrown) if `proteinGoal` has no linked `user` — every real
    /// on-device `Goal` row has one (see `Models/Goal.swift`), so this only guards against a
    /// malformed/preview-only goal rather than an expected runtime state.
    public func rankedOptions(
        for proteinGoal: Goal,
        verifiedProteinEventsToday: [GoalEvent],
        on date: Date = .now
    ) async -> [ProteinGapOption] {
        guard let userID = proteinGoal.user?.id else {
            logger.notice("rankedOptions(for:verifiedProteinEventsToday:on:): goal has no linked user — cannot look up kitchen staples.")
            return []
        }

        let plan = await AdaptiveGoalEngine.shared.dailyPlan(for: proteinGoal, on: date)
        let target = plan.plannedValue ?? proteinGoal.targetValue ?? 0
        let loggedSoFar = verifiedProteinEventsToday.reduce(0.0) { $0 + ($1.value ?? 0) }
        let gapGrams = target - loggedSoFar

        return await rankedOptions(forGapGrams: gapGrams, userID: userID)
    }

    // MARK: - Tier 1: kitchen staples (spec §10 — "the gap planner uses them first")

    /// Fetches the user's saved `KitchenStaple` rows and picks the single closest match to
    /// `gapGrams` (spec §5.20 says "something in their saved kitchen staples" — singular — not
    /// "every staple ranked"; matches `FuelView.gapOptions`'s own already-shipped precedent of
    /// picking exactly one staple-tier candidate via `.min(by:)`). Returns `nil` (logged, not
    /// thrown) on a fetch failure or an empty staple list — both are "no Tier 1 option right now",
    /// not error conditions a caller needs to handle separately.
    private func kitchenStapleOption(gapGrams: Double, userID: UUID) -> ProteinGapOption? {
        var descriptor = FetchDescriptor<KitchenStaple>(
            predicate: #Predicate<KitchenStaple> { $0.userID == userID }
        )
        descriptor.fetchLimit = Self.stapleFetchLimit

        let staples: [KitchenStaple]
        do {
            staples = try context.fetch(descriptor)
        } catch {
            logger.error("kitchenStapleOption: fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        return Self.bestStapleOption(from: staples, gapGrams: gapGrams)
    }

    /// Pure, static, side-effect-free selection step — see this file's header comment for why
    /// this is split out from ``kitchenStapleOption(gapGrams:userID:)``. Picks the staple whose
    /// `proteinG` is closest to `gapGrams`; ties keep the first encountered (fetch order), same as
    /// `Array.min(by:)`'s own documented tie-breaking behavior.
    nonisolated static func bestStapleOption(from staples: [KitchenStaple], gapGrams: Double) -> ProteinGapOption? {
        guard let best = staples.min(by: {
            abs($0.proteinG - gapGrams) < abs($1.proteinG - gapGrams)
        }) else {
            return nil
        }

        return ProteinGapOption(
            id: best.id,
            tier: .kitchenStaple,
            kitchenStapleID: best.id,
            name: best.name,
            proteinGrams: best.proteinG,
            proximityScore: abs(best.proteinG - gapGrams)
        )
    }

    // MARK: - Tier 2/3 — extension points, blocked on spec §28's open vendor question
    //
    // Both intentionally return `[]` today. This is not "not implemented because there was no
    // time" — it's a deliberate decision documented in this task's own instructions: wiring a
    // specific nutrition/restaurant vendor (Tier 2) or inventing a second, independent
    // quick-snack reference list (Tier 3, which would just duplicate `FuelView.swift`'s own
    // already-shipped `FuelReferenceData.quickSnacks` — see this file's header "KNOWN
    // DUPLICATION" note) before spec §28 is answered would both (a) very likely need to be redone
    // once a real vendor choice lands, and (b) risk exactly the "two agents, two shapes for the
    // same thing" bug class this wave's preamble warns about. A caller MUST treat an empty result
    // from either of these as "no suggestion available in this tier right now", not an error.

    /// EXTENSION POINT — Tier 2, nearby restaurant (spec §5.20 / §10).
    ///
    /// TODO(spec §28 — "Which nutrition/restaurant API is worth paying for at launch, if any?"):
    /// once a vendor is chosen, replace this stub's body with a real call: combine that vendor's
    /// nearby-menu-item search (location-biased the same best-effort, no-new-auth-prompt way
    /// `FuelView.openNearbyRestaurantSearch()` already does for its own Apple Maps deep link —
    /// permission priming is onboarding's job per spec §7, not this planner's) with a
    /// `.restaurant`-tier `ProteinGapOption` per candidate menu item: `name` = the menu item
    /// label, `proteinGrams` = its listed protein, `proximityScore = abs(proteinGrams -
    /// gapGrams)`. The deep link itself (spec §10: "Deep link to the restaurant app / DoorDash /
    /// Uber Eats search URL") is a UI-layer concern once a real candidate exists, not something
    /// this data-only type carries.
    public nonisolated static func restaurantOptions(gapGrams: Double) -> [ProteinGapOption] {
        // Intentionally empty — no vendor call, no fabricated menu data. See doc comment above.
        []
    }

    /// EXTENSION POINT — Tier 3, quick snack (spec §5.20 / §10).
    ///
    /// Unlike Tier 2, a real quick-snack tier doesn't strictly *need* a vendor at all —
    /// `FuelView.swift` already ships one today as a small static local reference list
    /// (`FuelReferenceData.quickSnacks`: "Greek yogurt", "2 eggs", etc.) with no network call.
    /// This stub deliberately does NOT copy that list into `Core` on its own: doing so would
    /// create a second, independent "quick snack data" shape alongside `FuelView`'s
    /// already-shipped one — precisely the duplication class this wave's preamble warns about —
    /// and this task's own instructions are explicit that Tier 3 should be stubbed here, not
    /// given an invented data source. Two real, non-conflicting paths forward for a future
    /// session (either is fine; neither is blocked on spec §28 the way Tier 2 actually is):
    ///   1. Promote `FuelView.FuelReferenceData.quickSnacks` into a shared `Core` reference list
    ///      this file (and `FuelView`, once refactored per this file's header "KNOWN
    ///      DUPLICATION" note) both read from — no vendor needed, could happen any time.
    ///   2. Once spec §28's nutrition API is chosen anyway (for Tier 2), reuse it here too for a
    ///      wider, more accurate snack catalog than a fixed 7-item list.
    /// TODO(spec §28 and/or the above): replace this stub once one of those paths is taken.
    public nonisolated static func quickSnackOptions(gapGrams: Double) -> [ProteinGapOption] {
        // Intentionally empty — no invented data source. See doc comment above.
        []
    }

    // MARK: - Ranking (pure, static — unit-testable without a `ModelContainer`)

    /// Sorts by tier first (spec §5.20's fixed "kitchen staples, ... restaurant ..., or ... quick
    /// snack" order — see `ProteinGapTier`'s doc comment), then by `proximityScore` ascending
    /// within a tier.
    nonisolated static func rank(_ options: [ProteinGapOption]) -> [ProteinGapOption] {
        options.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.proximityScore < rhs.proximityScore
        }
    }
}
