// OnboardingRevealCopy.swift
// Core / Copy
//
// Two small `Copy.<area>` additions written for the onboarding/paywall design pass (screens 9-14,
// docs/design/{competitive-research,composition-audit,better-layout-findings}.md), in the
// `extension Copy { public enum <area> }` shape every other file in this directory uses. They live
// in their own new file (rather than as edits to `OnboardingCopy.swift`/`PaywallCopy.swift`) so this
// pass could add strings without touching files another workflow may be editing; a copy owner is
// free to fold either enum into its natural home later — every call site names the enum, so moving
// a member is a one-line change per site.
//
// - `Copy.onboardingReveal` — strings the redesigned screens 9, 10, 12 and 14 need that
//   `Copy.onboarding` doesn't have (the split "lead-in / number / unit" wake-up math, the plan
//   build beat, the mock notification, the first-win celebration).
// - `Copy.paywallTimeline` — the paywall's dated trial timeline, the price/trial terms line under
//   the CTA, and a corrected per-month plan detail (see `perMonthAndTrialLine`).
//
// Wording rules followed here: no fabricated stats (writing-findings: "Built for you in 2:14" was a
// constant), "slipped"-style calm language, no countdown or urgency copy (spec §21 "no dark
// patterns", §8 rule 9 "no shame").

import Foundation

extension Copy {

    // MARK: - Copy.onboardingReveal (screens 9, 10, 12, 14)

    public enum onboardingReveal {

        // MARK: Screen 9 — wake-up math, split so the number can be the hero
        //
        // Reads as one sentence around the numeral:
        //   "At 5h/day, that's about" [76] "days a year on your phone"   (unit: `Copy.onboarding`)
        //   "Earn even 2h back and that's" [+30] "days a year back"

        public static func wakeUpLeadIn(dailyHours: Int) -> String {
            "At \(dailyHours)h/day, that's about"
        }

        /// `hoursLabel` is a pre-formatted duration such as "2h" or "1.5h" (`Copy.onboarding.q3HoursValue`).
        public static func wakeUpReclaimLeadIn(hoursLabel: String) -> String {
            "Earn even \(hoursLabel) back and that's"
        }

        public static let wakeUpReclaimUnit = "days a year back"

        // MARK: Screen 10 — plan reveal

        public static let planBuildingTitle = "Building your plan…"

        /// Spec §16 P4's difficulty tag; the day-one target really is ~70% of the stated one
        /// (spec §8 rule 1).
        public static let planEasyStartTag = "Starting easy on purpose"

        // The Lock-In Plan card's three section labels (sentence case, not tracked caps).
        public static let planTicketAppsLabel = "Locked until earned"
        public static let planTicketGoalsLabel = "Your goals"
        public static let planTicketScheduleLabel = "Schedule"

        /// The card's footer: the coach the user picked on screen 8, and an honest provenance line
        /// (no fabricated "built in 2:14").
        /// The last tile in the locked-apps row when more apps are picked than it shows: "+3".
        public static func planAppOverflow(_ count: Int) -> String {
            "+\(count)"
        }

        public static func planTicketCoachLine(voiceName: String) -> String {
            "\(voiceName) coach · built from your answers"
        }

        // MARK: Screen 12 — mock notification

        /// The app name shown on the mock notification banner.
        public static let notificationPreviewAppName = "ZANO"
        /// The banner's timestamp, as iOS prints it for a notification that just arrived.
        public static let notificationPreviewTime = "now"
        /// The letter on the mock app icon (the real icon is a "Z" on near-black).
        public static let notificationPreviewAppMonogram = "Z"

        // MARK: Screen 14 — first win

        public static let firstWinStreakUnit = "day streak"
        public static let firstWinCelebrationBody = "Focus verified. Day 1 is on the board."

        /// Names the hold gesture on the emergency exit (CLAUDE.md: the way out must be findable).
        public static let firstWinEmergencyHint = "Press and hold to end the lock"

        public static func firstWinEmergencySeconds(_ seconds: Int) -> String {
            "\(seconds)s"
        }
    }

    // MARK: - Copy.paywallTimeline (screen 13)

    public enum paywallTimeline {

        // MARK: Dated trial timeline (spec §7.13: "we'll remind you 2 days before it ends")
        //
        // Three nodes; dates are real calendar dates formatted by the system, not "Day 7".

        public static let timelineToday = "Today"
        public static let timelineStartTitle = "Full access"
        public static let timelineStartDetail = "Every feature, starting now. Nothing due today."
        public static let timelineReminderTitle = "Reminder"
        // The reminder node's detail is `Copy.paywall.trialReminderNote(daysBefore:)`.
        public static let timelineChargeTitle = "Billing starts"

        /// The day-of-trial label beside each timeline date: "Day 5".
        public static func timelineDayLabel(_ day: Int) -> String {
            "Day \(day)"
        }

        public static func timelineChargeDetail(priceLine: String) -> String {
            "\(priceLine) starts unless you cancel."
        }

        // MARK: Terms under the CTA

        /// e.g. "7-day free trial, then $39.99/yr. Nothing due today." `priceLine` is the caller's
        /// already-composed price, e.g. `Copy.paywall.annualPriceLine(price:)`.
        public static func trialTermsLine(trialDays: Int, priceLine: String) -> String {
            "\(trialDays)-day free trial, then \(priceLine). Nothing due today."
        }

        // MARK: Plan card detail

        /// e.g. "$3.33/mo · 7 days free". `perMonth` is `SubscriptionPackage.pricePerMonthString`,
        /// which already ends in "/mo" — `Copy.paywall.annualDetailLine(perMonth:trialDays:)`
        /// appends a second "/mo" to it ("$3.33/mo/mo · 7 days free"), so the paywall uses this
        /// instead. Also singular-aware ("1 day free").
        public static func perMonthAndTrialLine(perMonth: String, trialDays: Int) -> String {
            let days = trialDays == 1 ? "1 day" : "\(trialDays) days"
            return "\(perMonth) · \(days) free"
        }
    }
}
