// Core/Sources/Core/Copy/GearOffersCopy.swift
//
// docs/spec.md §25.6 "In-app store behavior": "The app is the store and the CRM: Settings → Gear,
// contextual offers ('You've logged 40 shakes — here's the bottle that logs itself'), Sunrise
// Alarm setup prompting a tag pack, reorder prompts when a tub is likely empty, and earned-card
// shipping prompts at milestones."
//
// `Core/Sources/Core/Monetization/GearOffersEngine.swift` (this same task) composes every
// `GearOffer.headline`/`.body`/`.ctaLabel` string from this file rather than inlining literals —
// same "engine composes from Copy, doesn't invent copy inline" precedent
// `Verification/SunriseAlarmManager.swift` already sets with `SunriseAlarmCopy.
// ringingNotification(escalationIndex:variant:)`. `Copy.<area>` per-file umbrella pattern, not a
// flat standalone enum — matches `Copy.swift`'s own documented convention and every real sibling
// file in this directory (`TrophyCosmeticsCopy.swift`, `SunriseAlarmCopy.swift`, etc.).
//
// This file's four `shaker*`/`sunriseTagPack*`/`reorderProtein*`/`earnedCard*` groups map 1:1 to
// §25.6's four bullets in the order listed there. Every copy voice here is plain/neutral — spec
// §5.13's Hype/Tough Love/Chill/Data coach-voice system (`Copy/CoachVoice.swift`) is scoped to
// goal nudges/shield/widget copy, not commerce prompts, and §25.6 gives no indication these
// offers should ventriloquize the coach voice; flagged as an assumption, not a guess presented as
// certain — a future session may want `CoachVoice`-aware phrasing here instead.

import Foundation

// MARK: - Copy.gearOffers (GearOffersEngine.swift)

extension Copy {
    public enum gearOffers {

        // MARK: Shaker offer (§25.6 bullet 1 — exact spec copy: "You've logged 40 shakes —
        // here's the bottle that logs itself.")
        //
        // "the bottle that logs itself" in spec's own example line is, in the actual product
        // catalog (§25.4), the **Shaker** ("tap when you drink → protein logged... on camera in
        // every gym video") — the Tag Pack's own "Bottle" tag (§25.1) is just a placement label
        // for a plain water bottle, not a product that itself "logs" anything. Read literally as
        // pointing at the Shaker SKU; flagged as a spec-wording reconciliation, not a guess.

        /// "You've logged 40 shakes" — `shakesLogged` is always a multiple of
        /// `GearOffersEngine.shakesPerShakerOffer`, per that engine's own milestone-crossing
        /// design.
        public static func shakerOfferHeadline(shakesLogged: Int) -> String {
            "You've logged \(shakesLogged) shakes"
        }
        public static let shakerOfferBody =
            "Tap the ZANO Shaker when you drink and protein logs itself — no more manual entries."
        public static let shakerOfferCTA = "See the Shaker"

        // MARK: Sunrise Alarm → Tag Pack (§25.6 bullet 2: "Sunrise Alarm setup prompting a tag pack")

        public static let sunriseTagPackHeadline = "Set up your Sunrise Tag"
        public static let sunriseTagPackBody =
            "Stick a Sunrise Tag to your mirror so dismissing the alarm is one real tap — not the fallback."
        public static let sunriseTagPackCTA = "Get a Tag Pack"

        // MARK: Reorder protein (§25.6 bullet 3: "reorder prompts when a tub is likely empty")

        /// `estimatedScoopsUsed` is always a multiple of
        /// `GearOffersEngine.estimatedServingsPerProteinTub` — an estimate, not a confirmed empty
        /// tub (no purchase/inventory model exists yet; see that engine's own doc comment), so
        /// this deliberately says "probably", never a hard claim.
        public static func reorderProteinHeadline(estimatedScoopsUsed: Int) -> String {
            "About \(estimatedScoopsUsed) scoops logged"
        }
        public static let reorderProteinBody = "Your tub is probably getting low. Reorder before you run out."
        public static let reorderProteinCTA = "Reorder Protein"

        // MARK: Earned Card shipping (§25.6 bullet 4: "earned-card shipping prompts at milestones";
        // §25.3's three tiers)

        public static func earnedCardHeadline(tierName: String) -> String {
            "Your \(tierName) Lock Card is earned"
        }
        public static func earnedCardBody(tierName: String) -> String {
            "You hit the streak that earns a \(tierName) Lock Card — free, engraved, and on us. Confirm your shipping address."
        }
        public static let earnedCardCTA = "Confirm shipping"

        // MARK: Shared chrome

        public static let dismissAccessibilityLabel = "Dismiss this offer"
    }
}
