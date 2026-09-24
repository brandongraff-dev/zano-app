// PaywallCopy.swift
// Core / Copy
//
// `Copy.paywall` — every user-facing string for the real paywall screen (docs/spec.md §7.13, §21,
// §16 P5), `App/ZANO/Features/Onboarding/PaywallView.swift` (screen 13 of onboarding; backed by
// `Core/Sources/Core/Monetization/PaywallViewModel.swift`). That file's own header comment
// documents this exact key list as an "ASSUMED API" gap — every key below is taken directly from
// its call sites, not re-derived, so it compiles unchanged against this file. Wording follows spec
// §21's paywall copy rules ("benefits in the user's words from onboarding; show the plan they
// built; social proof; clear free path; no dark patterns") and is this file's own authored copy
// except where a comment marks it spec-verbatim.

extension Copy {
    public enum paywall {

        /// Spec §16 P5 mockup headline, verbatim: "Earn your phone back".
        public static let headline = "Earn your phone back"

        /// One line under the headline: the product's promise in the user's terms.
        public static let subheadline = "Do what you said you'd do, and your apps open back up."

        // MARK: - Benefits (spec §16 P5: three benefit rows, verbatim phrases)

        public static let benefitUnlimitedGoalsTitle = "Unlimited goals & lock sets"
        public static let benefitAdaptivePlanTitle = "Adaptive plan that learns you"
        public static let benefitSquadsDuelsTitle = "Squads & duels"

        // One supporting line per benefit, in the user's own terms (spec §21).
        public static let benefitUnlimitedGoalsDetail = "Gym, protein, focus: put any app behind any goal."
        public static let benefitAdaptivePlanDetail = "Starts easy, then grows as you show up."
        public static let benefitSquadsDuelsDetail = "Friends who notice when you skip."

        // MARK: - "The plan you built" (spec §21 copy rule)

        public static let yourPlanSectionTitle = "The plan you built"

        public static func lockSetSummary(name: String) -> String {
            "Lock set: \(name)"
        }

        // MARK: - Plans

        public static let annualBadgeLabel = "Best value"
        public static let annualPlanTitle = "Annual"
        public static let monthlyPlanTitle = "Monthly"
        public static let weeklyPlanTitle = "Weekly"
        public static let lifetimePlanTitle = "Lifetime"

        public static func annualPriceLine(price: String) -> String {
            "\(price)/yr"
        }

        public static func monthlyPriceLine(price: String) -> String {
            "\(price)/mo"
        }

        /// Spec §16 P5 mockup shape: "$3.33/mo · 7 days free".
        public static func annualDetailLine(perMonth: String, trialDays: Int) -> String {
            "\(perMonth)/mo · \(trialDays) \(trialDays == 1 ? "day" : "days") free"
        }

        public static func trialDaysLabel(_ days: Int) -> String {
            "\(days)-day free trial"
        }

        /// The pill on the highlighted plan card: "7 days free".
        public static func trialBadgeLabel(trialDays: Int) -> String {
            trialDays == 1 ? "1 day free" : "\(trialDays) days free"
        }

        // MARK: - CTA / restore (hard paywall: there is no free path, decision 2026-09-23)

        public static func startTrialButtonLabel(trialDays: Int) -> String {
            "Start my \(trialDays)-day free trial"
        }

        public static let subscribeButtonLabel = "Subscribe"
        public static let restorePurchasesButtonLabel = "Restore purchases"

        public static let retryButtonLabel = "Try again"
        /// The alert title for a failed purchase (`PaywallView`'s `.failed` purchase state): names
        /// the action that failed instead of "Something went wrong". The alert's message carries
        /// the specific cause.
        public static let errorTitle = "Couldn't complete purchase"

        /// Spec §7.13's own promise: "we'll remind you 2 days before it ends."
        public static func trialReminderNote(daysBefore: Int) -> String {
            "We'll remind you \(daysBefore) \(daysBefore == 1 ? "day" : "days") before your trial ends."
        }

        // MARK: - Subscription terms (docs/spec.md §24: "subscription terms in the paywall per App
        // Store rules")
        //
        // ADDED, NOT YET REFERENCED: the live `PaywallView` shows a trial reminder, Restore and the
        // free link, but no price-after-trial, auto-renew/cancel note, or Terms and Privacy links
        // (the auto-renew text only existed for the superseded `Screen13Paywall`). These are the
        // strings it needs; wiring them in is a `PaywallView` change. See
        // docs/design/writing-findings.md §5.1 (HIGH).

        /// e.g. `afterTrialPriceLine(price: "$39.99", period: "year")` -> "After the trial: $39.99
        /// per year." `price` comes from StoreKit/RevenueCat, never a literal.
        public static func afterTrialPriceLine(price: String, period: String) -> String {
            "After the trial: \(price) per \(period)."
        }

        public static let autoRenewNote = "Auto-renews until you cancel. Cancel anytime in your Apple ID settings."
        public static let termsLinkLabel = "Terms of use"
        public static let privacyLinkLabel = "Privacy policy"
    }
}
