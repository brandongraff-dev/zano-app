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
            "Locking: \(name)"
        }

        // MARK: - Plans

        public static let annualBadgeLabel = "BEST VALUE"
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
            "\(perMonth)/mo · \(trialDays) days free"
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

        /// Spec §7.13/§21 verbatim: "Continue with limited free".
        public static let continueWithLimitedFreeLink = "Continue with limited free"

        public static let retryButtonLabel = "Try again"
        public static let errorTitle = "Something went wrong"

        /// Spec §7.13's own promise: "we'll remind you 2 days before it ends."
        public static func trialReminderNote(daysBefore: Int) -> String {
            "We'll remind you \(daysBefore) days before your trial ends."
        }
    }
}
