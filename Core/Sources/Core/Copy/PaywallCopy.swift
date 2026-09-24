// PaywallCopy.swift
// Core / Copy
//
// `Copy.paywall` — every user-facing string for the real paywall screen (docs/spec.md §7.13, §21,
// §16 P5), `App/ZANO/Features/Onboarding/PaywallView.swift` (screen 13 of onboarding; backed by
// `Core/Sources/Core/Monetization/PaywallViewModel.swift`). That file's own header comment
// documents this exact key list as an "ASSUMED API" gap — every key below is taken directly from
// its call sites, not re-derived, so it compiles unchanged against this file. Wording follows spec
// §21's paywall copy rules ("benefits in the user's words from onboarding; show the plan they
// built; no dark patterns") and is this file's own authored copy except where a comment marks it
// spec-verbatim. The paywall is hard (decision 2026-09-23): there is no free path. Benefits name
// only what the app ships today (goals and lock sets, the adaptive plan, Earn Mode and the Time
// Bank, the weekly recap, the Sunrise Alarm): no squads or friends until that screen exists.

extension Copy {
    public enum paywall {

        /// Spec §16 P5 mockup headline, with its period ("Earn your phone back."). UI tests find it
        /// with a CONTAINS match on "Earn your phone back", so the words must stay.
        public static let headline = "Earn your phone back."

        // MARK: - Lapsed subscription (the paywall shown by the app shell, not onboarding)

        /// Line one on the paywall the app shell shows after a trial or subscription ran out
        /// (`PaywallView(context: .lapsed)`). Line two stays `headline`.
        public static let lapsedHeadline = "Welcome back."

        /// VoiceOver label for the plan tiles' loading placeholder.
        public static let loadingPlansLabel = "Loading plans"

        /// One line under the headline: the product's promise in the user's terms.
        public static let subheadline = "Do what you said you'd do, and your apps open back up."

        // MARK: - Benefits (spec §16 P5: three benefit rows, verbatim phrases)

        public static let benefitUnlimitedGoalsTitle = "Unlimited goals & lock sets"
        public static let benefitAdaptivePlanTitle = "Adaptive plan that learns you"
        public static let benefitTimeBankTitle = "Earn Mode & Time Bank"
        public static let benefitWeeklyRecapTitle = "Weekly recap"
        public static let benefitSunriseAlarmTitle = "Sunrise Alarm"

        /// Squads and duels are not built yet, so the paywall no longer promises them. Kept only so
        /// `Copy.settings.proBenefits` compiles until it moves to `benefitTimeBankTitle`.
        @available(*, deprecated, renamed: "benefitTimeBankTitle")
        public static let benefitSquadsDuelsTitle = benefitTimeBankTitle

        // One supporting line per benefit, in the user's own terms (spec §21).
        public static let benefitUnlimitedGoalsDetail = "Gym, protein, focus: put any app behind any goal."
        public static let benefitAdaptivePlanDetail = "Starts easy, then grows as you show up."
        public static let benefitTimeBankDetail = "Verified goals bank minutes you can spend on locked apps."
        public static let benefitWeeklyRecapDetail = "What you earned this week, in one card."
        public static let benefitSunriseAlarmDetail = "An alarm that stops when your morning goal is done."

        // MARK: - "The plan you built" (spec §21 copy rule)

        public static let yourPlanSectionTitle = "The plan you built"

        public static func lockSetSummary(name: String) -> String {
            "Lock set: \(name)"
        }

        // MARK: - Plans

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
        // The live `PaywallView` uses `termsParagraph(trialDays:price:period:)` below.

        /// e.g. `afterTrialPriceLine(price: "$39.99", period: "year")` -> "After the trial: $39.99
        /// per year." `price` comes from StoreKit/RevenueCat, never a literal.
        public static func afterTrialPriceLine(price: String, period: String) -> String {
            "After the trial: \(price) per \(period)."
        }

        // MARK: Paywall v3 (2026-09-24, premium UI pass round 3)

        /// Under the hero number: `"days a year, back"`.
        public static let daysBackLabel = "days a year, back"
        /// The line that says where the hero number comes from.
        public static func daysBackDetail(hours: String) -> String {
            "That's \(hours) a day you earn back by doing what you said you'd do."
        }
        public static let answersHeading = "Built from your answers"
        public static func workoutsPerWeekLine(_ count: Int) -> String {
            count == 1 ? "1 workout a week, verified" : "\(count) workouts a week, verified"
        }
        public static func lockSetLockedLine(name: String) -> String {
            "\(name) stays locked until you earn it"
        }
        public static let appsLockedLine = "Your apps stay locked until you earn them"
        public static func coachLine(voice: String) -> String { "\(voice) coach in your corner" }
        public static let includedLine = "Every plan includes unlimited goals and lock sets, the adaptive plan, Earn Mode and the weekly recap."
        public static let perYearSuffix = "/year"
        public static let perMonthSuffix = "/month"
        public static func tileTrialLabel(days: Int) -> String { "\(days) days free" }
        public static let billedMonthlyLabel = "Billed monthly"
        public static let choosePlanHeading = "Choose your plan"

        // MARK: Paywall v4 (2026-09-24): the trial-timeline layout the user picked as reference

        /// Headline line one while a trial is on offer; line two is `headline`.
        public static func trialHeadline(days: Int) -> String { "Start your \(days)-day free trial." }
        public static let subscribeHeadline = "Subscribe to continue."
        public static let timelineTodayTitle = "Today"
        public static let timelineTodayDetail = "Unlimited goals and lock sets, Earn Mode, the adaptive plan and the Sunrise Alarm."
        public static func timelineReminderTitle(inDays days: Int) -> String { days == 1 ? "Reminder in 1 day" : "Reminder in \(days) days" }
        public static let timelineReminderDetail = "We'll remind you before your trial ends, if notifications are on."
        public static func timelineBillingTitle(inDays days: Int) -> String { days == 1 ? "Billing starts in 1 day" : "Billing starts in \(days) days" }
        public static func timelineBillingDetail(date: String) -> String {
            "You'll be charged on \(date) unless you cancel before then."
        }
        public static let noPaymentDueNow = "No payment due now"
        public static let cancelAnytime = "Cancel anytime"
        /// The full terms under the button: what, when, how much, how to cancel. `price` is the
        /// store-formatted price for `period` (never a literal).
        public static func termsParagraph(trialDays: Int?, price: String, period: SubscriptionPackage.Period) -> String {
            let unit: String
            switch period {
            case .lifetime: return "\(price). One-time purchase."
            case .weekly: unit = "week"
            case .monthly: unit = "month"
            case .twoMonth: unit = "2 months"
            case .threeMonth: unit = "3 months"
            case .sixMonth: unit = "6 months"
            case .annual: unit = "year"
            case .other: unit = "billing period"
            }
            let renew = "Auto-renews until you cancel. Cancel anytime in Settings > [your name] > Subscriptions."
            if let trialDays, trialDays > 0 {
                let days = trialDays == 1 ? "1 day" : "\(trialDays) days"
                return "\(days) free, then \(price) per \(unit). \(renew)"
            }
            return "\(price) per \(unit). \(renew)"
        }
        public static func trialPill(days: Int) -> String { days == 1 ? "1 day free" : "\(days) days free" }

        public static let termsLinkLabel = "Terms of use"
        public static let privacyLinkLabel = "Privacy policy"
    }
}
