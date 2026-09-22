// OnboardingCopy.swift
// Core / Copy
//
// `Copy.onboarding` — every user-facing string for the 14-screen onboarding flow (docs/spec.md §7),
// screens 1-14 (`App/ZANO/Features/Onboarding/Screen1Hook.swift` through `Screen14FirstWin.swift`,
// plus `OnboardingContainerView.swift`'s chrome). This is the file two independent onboarding
// sessions (screens 1-8, screens 9-14) each documented in full as an "ASSUMED API" gap in their own
// headers (see e.g. `Screen3MainGoal.swift`, `Screen9WakeUp.swift`) — every key below is taken
// directly from those call sites, not re-derived, so every screen compiles unchanged against this
// file. Wording is this file's own authored copy except where a comment marks it spec-verbatim.
//
// `Screen13Paywall.swift`'s own keys (`paywall*`-prefixed, under this same `onboarding` namespace
// rather than `Copy.paywall`) are also included even though that screen is superseded/unwired by
// `OnboardingContainerView.swift` (routes to the real `PaywallView`/`Copy.paywall` instead, per that
// file's header) — `Screen13Paywall.swift` is still compiled as part of the app target, so its keys
// must resolve to something real even though the flow never reaches it.

import Foundation

extension Copy {
    public enum onboarding {

        // MARK: - Screen 1: Hook (spec §7.1 — verbatim)

        public static let hookHeadline = "Your phone is fighting your goals. Let's flip that."
        public static let hookCTA = "I'm ready."

        // MARK: - Screen 2: Social proof (spec §7.2)

        // TODO: replace with real testimonials once available (spec §7.2: "real ones once you
        // have them; placeholder copy marked clearly until then"). These three are placeholder.
        public static let socialProofQuotes: [String] = [
            "\"I stopped doomscrolling and actually hit the gym 4x this week.\" — early user (placeholder)",
            "\"My streak's at 32 days. Longest I've ever gone at anything.\" — early user (placeholder)",
            "\"The lock screen alone changed how I pick up my phone.\" — early user (placeholder)",
        ]

        // MARK: - Screen 3: Q1 main goal (spec §7.3)

        public static let q1Title = "What's your main goal?"
        public static let q1Subtitle = "We'll build your plan around this."

        // MARK: - Screen 4: Q2 app selection (spec §7.4)

        public static let q2Title = "Which apps steal your time?"
        public static let q2Subtitle = "Pick the apps and sites you want locked until you've earned them back."
        public static let q2PickerButtonLabel = "Choose apps"

        public static func q2SelectionSummary(appCount: Int, categoryCount: Int, webDomainCount: Int) -> String {
            let total = appCount + categoryCount + webDomainCount
            guard total > 0 else { return q2PickerButtonLabel }
            return total == 1 ? "1 app selected" : "\(total) apps selected"
        }

        public static let q2AuthorizationErrorTitle = "Couldn't request permission"
        public static let q2AuthorizationErrorMessage =
            "Something went wrong asking for Screen Time access. Try again in a moment."
        public static let q2AuthorizationDeniedTitle = "Screen Time access needed"
        public static let q2AuthorizationDeniedMessage =
            "ZANO needs Screen Time access to lock apps until you've earned them back. You can enable it in Settings > Screen Time."

        // MARK: - Screen 5: Q3 daily phone time (spec §7.5)

        public static let q3Title = "How much time do you spend on your phone daily?"
        public static let q3Subtitle = "Be honest — this is just for you."

        public static func q3HoursValue(_ hours: Double) -> String {
            let rounded = (hours * 2).rounded() / 2
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(rounded))h"
            }
            return String(format: "%.1fh", rounded)
        }

        public static let q3SliderMinLabel = "1h"
        public static let q3SliderMaxLabel = "10h+"

        // MARK: - Screen 6: Q4 workouts/week (spec §7.6)

        public static let q4Title = "How many times do you work out?"
        public static let q4Subtitle = "Current pace vs. where you want to be."
        public static let q4CurrentLabel = "Right now"
        public static let q4TargetLabel = "My goal"

        public static func q4WorkoutsPerWeekValue(_ count: Int) -> String {
            count == 1 ? "1x/week" : "\(count)x/week"
        }

        // MARK: - Screen 7: Q5 fall-off pattern (spec §7.7)

        public static let q5Title = "When do you usually fall off?"
        public static let q5Subtitle = "This helps us catch you before it happens."

        // MARK: - Screen 8: Q6 coach voice (spec §7.8)

        public static let q6Title = "Pick your coach voice"
        public static let q6Subtitle = "How should ZANO talk to you?"

        // MARK: - Screen 9: Wake-up moment (spec §7.9)

        public static let wakeUpEyebrow = "THE MATH"

        /// Spec §7.9's own worked example: "At 5h/day, that's ~76 days a year on your phone."
        public static func wakeUpHeadline(dailyHours: Int, daysPerYear: Int) -> String {
            "At \(dailyHours)h/day, that's ~\(daysPerYear) days a year on your phone."
        }

        public static let daysPerYearUnitLabel = "days a year on your phone"

        /// Spec §7.9's own worked example: "Earning even 2h back = 30 days a year."
        public static func wakeUpReclaimLine(daysReclaimed: Int) -> String {
            "Earning even 2h back = \(daysReclaimed) days a year."
        }

        public static let wakeUpContinueButton = "Let's fix that"

        // MARK: - Screen 10: Plan reveal (spec §7.10)

        public static let planRevealEyebrow = "YOUR PLAN"
        /// Spec §7.10 verbatim: "Your Lock-In Plan".
        public static let planRevealHeadline = "Your Lock-In Plan"
        public static let planLockedAppsDetailLine = "These stay locked until you earn them back."

        public static func planLockedAppsStatusLine(appCount: Int, categoryCount: Int, webDomainCount: Int) -> String {
            let total = appCount + categoryCount + webDomainCount
            guard total > 0 else { return "No apps locked yet" }
            return total == 1 ? "1 app locked" : "\(total) apps locked"
        }

        /// Title for one plan-preview goal row. `type` is Core's own `GoalType`
        /// (`Core/Sources/Core/Models/Goal.swift`) — see that model for the full catalog.
        public static func planGoalTitle(for type: GoalType) -> String {
            switch type {
            case .workoutGym: "Workout at the gym"
            case .workoutHomeOutdoor: "Home / outdoor workout"
            case .focusSession: "Focus session"
            case .protein: "Hit your protein"
            case .water: "Drink water"
            case .steps: "Hit your step count"
            case .creatine: "Take your creatine"
            case .sunriseAlarm: "Morning routine"
            case .sleepOnTime: "Sleep on time"
            case .reading: "Reading"
            case .mealPrep: "Meal prep"
            case .stretchMobility: "Stretch / mobility"
            case .coldShowerSauna: "Cold shower / sauna"
            case .custom: "Your goal"
            }
        }

        public static func planGoalStartingDetail(current: Int, target: Int, unit: String) -> String {
            "Starting at \(current) \(unit) · target \(target) \(unit)"
        }

        /// Spec §7.10 verbatim example: "Built for you in 2:14."
        public static let planBuiltInLabel = "Built for you in 2:14."
        public static let planContinueButton = "Let's do this"
        public static let planScheduleLine = "Locks each morning until your goals are done."

        public static func planScheduleFallOffNote(patternLabel: String) -> String {
            "We'll watch out for you on \(patternLabel.lowercased()) — that's usually when things slip."
        }

        /// Shared between screen 10 (Plan Reveal) and screen 14 (First Win): the name given to the
        /// default `LockSet` created from the onboarding app selection (Q2).
        public static let lockSetName = "Distractions"

        // MARK: - Screen 11: Commitment (spec §7.11)

        public static let commitEyebrow = "LAST STEP"
        public static let commitHeadline = "Commit to your plan"
        public static let commitSubtitle = "Hold the button for 2 seconds. This is you, deciding."
        public static let commitHoldButtonLabel = "Hold to commit"
        public static let commitHoldHint = "Keep holding…"

        public static func commitRecapLine(goalCount: Int, appCount: Int) -> String {
            let goals = goalCount == 1 ? "1 goal" : "\(goalCount) goals"
            let apps = appCount == 1 ? "1 app" : "\(appCount) apps"
            return "\(goals) · \(apps) locked"
        }

        // MARK: - Screen 12: Permission priming (spec §7.12)

        public static let permissionEyebrow = "STAY IN THE LOOP"
        public static let permissionHeadline = "Turn on notifications"
        /// Spec §7.12 verbatim: "We'll only nudge when it matters."
        public static let permissionSubtitle = "We'll only nudge when it matters."
        public static let permissionAllowButton = "Allow notifications"
        public static let permissionSkipButton = "Not now"

        // MARK: - Screen 13: Paywall placeholder (spec §7.13) — superseded by `Copy.paywall`/
        // `PaywallView.swift`; kept because `Screen13Paywall.swift` is still compiled. See file
        // header.

        public static let paywallHeadline = "Earn your phone back"
        public static let paywallSubtitle = "Unlock everything by doing what you already said you'd do."
        /// Spec §7.13's own promise: "we'll remind you 2 days before it ends."
        public static let paywallTrialReminder = "We'll remind you 2 days before your trial ends."
        public static let paywallCTAButton = "Start my 7-day free trial"
        /// Spec §7.13/§21 verbatim: "Continue with limited free".
        public static let paywallContinueFreeButton = "Continue with limited free"
        public static let paywallFreeTierDetail = "1 goal, 1 lock set, no strings attached."
        public static let paywallAutoRenewDisclaimer = "Auto-renews unless canceled. Cancel anytime in Settings."
        public static let paywallMonthlyLabel = "Monthly"
        public static let paywallAnnualLabel = "Annual"
        public static let paywallLifetimeLabel = "Lifetime"
        public static let paywallAnnualBadge = "BEST VALUE"

        public static func paywallPriceSuffix(period: String) -> String {
            period == "once" ? "One-time purchase" : "Billed per \(period)"
        }

        // MARK: - Screen 14: First win (spec §7.14)

        public static let firstWinEyebrow = "YOUR FIRST WIN"
        /// Spec §7.14 verbatim: "Start your first lock now."
        public static let firstWinHeadline = "Start your first lock now"
        /// Spec §7.14 verbatim: "10-minute focus to unlock."
        public static let firstWinSubtitle = "10-minute focus to unlock."
        public static let firstWinStartButton = "Start focus session"
        public static let firstWinGoalTitle = "Focus session"
        public static let firstWinRunningHeadline = "Stay locked in"
        public static let firstWinRunningDetail = "Leaving the app pauses your timer. Come back to keep going."
        public static let firstWinEmergencyLabel = "Emergency"
        public static let firstWinCelebrationTitle = "Earned."

        public static func firstWinCelebrationSubtitle(streak: Int) -> String {
            "Streak: \(streak) 🔥 Day \(streak) starts now."
        }

        public static let firstWinNotVerifiedTitle = "No worries"
        public static let firstWinNotVerifiedSubtitle = "You can always try again — your plan is already saved."
        public static let firstWinWidgetPromptHeadline = "Add ZANO to your Home Screen"
        public static let firstWinWidgetPromptStep1 = "Touch and hold your Home Screen"
        public static let firstWinWidgetPromptStep2 = "Tap the + button in the top corner"
        public static let firstWinWidgetPromptStep3 = "Search for ZANO and add the widget"
        public static let firstWinDoneButton = "Let's go"

        // MARK: - Container chrome (`OnboardingContainerView.swift`)

        public static let backButtonAccessibilityLabel = "Back"

        public static func progressAccessibilityLabel(screen: Int, total: Int) -> String {
            "Step \(screen) of \(total)"
        }
    }
}
