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

        // MARK: - Benefits (spec §16 P5: three benefit rows, verbatim phrases)

        public static let benefitUnlimitedGoalsTitle = "Unlimited goals & lock sets"
        public static let benefitAdaptivePlanTitle = "Adaptive plan that learns you"
        public static let benefitSquadsDuelsTitle = "Squads & duels"

        // MARK: - "The plan you built" (spec §21 copy rule)

        public static let yourPlanSectionTitle = "The plan you built"

        public static func lockSetSummary(name: String) -> String {
            "Lock set: \(name)"
        }

        // MARK: - Plans

        public static let annualBadgeLabel = "BEST VALUE"
        public static let annualPlanTitle = "Annual"
        public static let monthlyPlanTitle = "Monthly"
        public static let weeklyPlanTitle = "Weekly"
        public static let lifetimePlanTitle = "Lifetime"
        /// Spec §21 Family annual plan (decision 2026-10-06).
        public static let familyPlanTitle = "Family"
        /// Apple Family Sharing covers the buyer plus up to 5 family members.
        public static let familyPeopleLabel = "Up to 6 people"

        /// The family card's detail line, e.g. "Up to 6 people · 7 days free".
        public static func familyDetailLine(trialDays: Int?) -> String {
            guard let trialDays, trialDays > 0 else { return familyPeopleLabel }
            let days = trialDays == 1 ? "1 day" : "\(trialDays) days"
            return "\(familyPeopleLabel) · \(days) free"
        }

        /// The price with its period, e.g. "$39.99/yr" or "$6.99/mo". Shared by the paywall's
        /// cards and the trial reminder notification so both quote the same thing.
        public static func priceLine(for package: SubscriptionPackage) -> String {
            switch package.period {
            case .annual: annualPriceLine(price: package.priceString)
            case .monthly: monthlyPriceLine(price: package.priceString)
            default: package.priceString
            }
        }

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

        // MARK: - CTA / restore / free path

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

// MARK: - Free trial (docs/spec.md §21 "Free trials, done well", decision 2026-10-06)
//
// The reminder notification the paywall promises, and the day-5 "what your trial earned you" card
// on Today. Calm and factual: no countdown, no guilt, and the cancel path is named plainly.

extension Copy {
    public enum trial {

        public static func reminderTitle(daysBefore: Int) -> String {
            "Your free trial ends in \(daysBefore) \(daysBefore == 1 ? "day" : "days")"
        }

        /// e.g. "On Oct 13 your plan continues at $39.99/yr. Want to stop? Cancel anytime in
        /// Settings > Apple ID > Subscriptions."
        public static func reminderBody(endDate: String, priceLine: String) -> String {
            "On \(endDate) your plan continues at \(priceLine). Want to stop? Cancel anytime in Settings > Apple ID > Subscriptions."
        }

        public static let valueCardTitle = "What your trial earned you"
        public static let reclaimedLabel = "Reclaimed"
        public static let streakLabel = "Streak"
        public static let goalsHitLabel = "Goals hit"
        public static let dismissLabel = "Hide"

        public static func streakValue(days: Int) -> String {
            days == 1 ? "1 day" : "\(days) days"
        }

        /// e.g. "6h 40m", "25m".
        public static func duration(minutes: Int) -> String {
            let hours = minutes / 60
            let mins = minutes % 60
            guard hours > 0 else { return "\(mins)m" }
            return "\(hours)h \(mins)m"
        }

        /// e.g. "Trial ends Oct 13, then $39.99/yr. Cancel anytime in Settings."
        public static func valueCardFooter(endDate: String, priceLine: String) -> String {
            "Trial ends \(endDate), then \(priceLine). Cancel anytime in Settings."
        }
    }
}
