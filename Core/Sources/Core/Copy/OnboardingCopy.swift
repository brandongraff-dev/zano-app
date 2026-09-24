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
// The paywall's strings live in `Copy.paywall` (`PaywallCopy.swift`). The superseded
// `Screen13Paywall.swift` and its `paywall*` keys here are gone.

import Foundation

extension Copy {
    public enum onboarding {

        // MARK: - Screen 1: Hook (spec §7.1 — verbatim)

        public static let hookHeadline = "Your phone is fighting your goals. Let's flip that."
        /// Spec §7.1's "I'm ready." without the trailing period: it is the only button label in the
        /// product that ended in one (docs/design/writing-findings.md §5.5). The words are unchanged.
        public static let hookCTA = "I'm ready"

        // MARK: - Screen 2: Social proof (spec §7.2)

        // TODO: replace with real testimonials once they exist (spec §7.2: "real ones once you
        // have them"). Until then this strip carries plain product claims, not invented quotes:
        // fabricated endorsements are a ship risk (App Review and consumer-protection), and the old
        // "(placeholder)" attribution was user-visible. Every line below is a fact about how ZANO
        // works (CLAUDE.md, docs/spec.md §3). Screen2SocialProof renders each entry as centered
        // headline text and expects exactly 3, so a real quote drops in as `"..." — Name`.
        public static let socialProofQuotes: [String] = [
            "Your distracting apps stay locked until you've earned them back.",
            "Workouts verify from your gym's location and Apple Health. Verified by your phone.",
            "Works offline. Your apps open the second your last goal verifies.",
        ]

        // MARK: - Screen 3: Q1 main goal (spec §7.3)

        public static let q1Title = "What's your main goal?"
        public static let q1Subtitle = "We'll build your plan around this."

        // MARK: - Screen 4: Q2 app selection (spec §7.4)

        public static let q2Title = "Which apps steal your time?"
        public static let q2Subtitle = "Pick the apps and sites you want locked until you've earned them back."
        public static let q2PickerButtonLabel = "Choose apps"

        /// Reuses `Copy.lockSetup.selectionSummary` so apps, categories and websites are counted
        /// precisely ("1 app, 1 category selected") instead of calling everything an "app".
        public static func q2SelectionSummary(appCount: Int, categoryCount: Int, webDomainCount: Int) -> String {
            let total = appCount + categoryCount + webDomainCount
            guard total > 0 else { return q2PickerButtonLabel }
            let summary = Copy.lockSetup.selectionSummary(
                appCount: appCount,
                categoryCount: categoryCount,
                webDomainCount: webDomainCount
            )
            return "\(summary) selected"
        }

        // Same wording as `Copy.lockSetup.authorization*` — one failure, one phrasing.
        public static let q2AuthorizationErrorTitle = "Couldn't turn on Screen Time access"
        public static let q2AuthorizationErrorMessage =
            "Screen Time access wasn't turned on. Try again, or check the iPhone Settings app > Screen Time if it's restricted."
        public static let q2AuthorizationDeniedTitle = "Screen Time access needed"
        /// The alert's second button: opens this app's page in the iPhone Settings app.
        public static let q2OpenSettingsButton = "Open Settings"
        /// The inline card under the picker once access was refused: re-runs the request.
        public static let q2TryAgainButton = "Try again"
        public static let q2AuthorizationDeniedMessage =
            "ZANO needs Screen Time access to lock apps until you've earned them back. Turn it on in the iPhone Settings app, then come back."

        // MARK: - Screen 5: Q3 daily phone time (spec §7.5)

        public static let q3Title = "How long are you on your phone each day?"
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

        public static let q4Title = "How many workouts a week?"
        public static let q4Subtitle = "Current pace vs. where you want to be."
        public static let q4CurrentLabel = "Right now"
        public static let q4TargetLabel = "My goal"

        public static func q4WorkoutsPerWeekValue(_ count: Int) -> String {
            count == 1 ? "1x/week" : "\(count)x/week"
        }

        /// Accessibility labels for the counters' round buttons, so Voice Control can name them.
        public static let q4DecrementButtonLabel = "Fewer workouts"
        public static let q4IncrementButtonLabel = "More workouts"

        // MARK: - Screen 7: Q5 fall-off pattern (spec §7.7)

        public static let q5Title = "When does your routine usually slip?"
        public static let q5Subtitle = "ZANO will plan extra support for those moments."

        // MARK: - Screen 8: Q6 coach voice (spec §7.8)

        public static let q6Title = "Pick your coach voice"
        public static let q6Subtitle = "How should ZANO talk to you?"

        // MARK: - Screen 9: Wake-up moment (spec §7.9)

        // Eyebrows are stored in sentence case; every onboarding screen that shows one applies
        // `.textCase(.uppercase)` itself (casing is rendering, and stored caps localize badly).
        public static let wakeUpEyebrow = "The math"

        /// Spec §7.9's own worked example: "At 5h/day, that's ~76 days a year on your phone."
        public static func wakeUpHeadline(dailyHours: Int, daysPerYear: Int) -> String {
            "At \(dailyHours)h/day, that's ~\(daysPerYear) days a year on your phone."
        }

        public static let daysPerYearUnitLabel = "days a year on your phone"

        /// Spec §7.9's own worked example: "Earning even 2h back = 30 days a year."
        public static func wakeUpReclaimLine(daysReclaimed: Int) -> String {
            "Earning even 2h back = \(daysReclaimed) days a year."
        }

        /// Names the next screen instead of a catchphrase; "Let's ..." baked Hype into every user's
        /// buttons before and after they picked a voice (docs/design/writing-findings.md §5.5).
        public static let wakeUpContinueButton = "See my plan"

        // MARK: - Screen 10: Plan reveal (spec §7.10)

        public static let planRevealEyebrow = "Your plan"
        /// Spec §7.10's "Your Lock-In Plan", in the product's sentence case.
        public static let planRevealHeadline = "Your lock-in plan"
        public static let planLockedAppsDetailLine = "These stay locked until you earn them back."

        public static func planLockedAppsStatusLine(appCount: Int, categoryCount: Int, webDomainCount: Int) -> String {
            let total = appCount + categoryCount + webDomainCount
            guard total > 0 else { return "No apps locked yet" }
            let summary = Copy.lockSetup.selectionSummary(
                appCount: appCount,
                categoryCount: categoryCount,
                webDomainCount: webDomainCount
            )
            return "\(summary) locked"
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

        /// Spec §7.10's example was "Built for you in 2:14." — a constant, so every user "built"
        /// their plan in exactly 2:14. A fake number presented as fact, so this states what is
        /// true instead. (Restoring the real elapsed time needs a parameter; see
        /// docs/design/writing-findings.md §5.1.)
        public static let planBuiltInLabel = "Built from your answers."
        public static let planContinueButton = "Continue"
        public static let planScheduleLine = "Locks each morning until your goals are done."

        /// `patternLabel` is `FallOffPattern.displayLabel` ("Weekends", "Evenings", "When stressed",
        /// "After a few good days", "Travel"). Each known answer gets its own full sentence — a
        /// sentence assembled around the raw label read "on when stressed" and "on travel". An
        /// unrecognised label falls back to a sentence that needs no label at all.
        public static func planScheduleFallOffNote(patternLabel: String) -> String {
            switch patternLabel.lowercased() {
            case "weekends": "We'll watch weekends, when things usually slip."
            case "evenings": "We'll watch evenings, when things usually slip."
            case "when stressed": "We'll watch for stressful days, when things usually slip."
            case "after a few good days": "We'll watch the days after a few good ones, when things usually slip."
            case "travel": "We'll watch your travel days, when things usually slip."
            default: "We'll watch for the moments when things usually slip."
            }
        }

        /// Shared between screen 10 (Plan Reveal) and screen 14 (First Win): the name given to the
        /// default `LockSet` created from the onboarding app selection (Q2).
        public static let lockSetName = "Distractions"

        // MARK: - Screen 11: Commitment (spec §7.11)

        public static let commitEyebrow = "Last step"
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

        public static let permissionEyebrow = "Stay in the loop"
        public static let permissionHeadline = "Turn on notifications"
        /// Says exactly what gets sent (spec §7.12's promise, made checkable).
        public static let permissionSubtitle = "A reminder before a lock starts, and when your time bank runs low. Nothing else."
        public static let permissionAllowButton = "Allow notifications"
        public static let permissionSkipButton = "Not now"

        // MARK: - Screen 14: First win (spec §7.14)

        public static let firstWinEyebrow = "Your first win"
        /// Spec §7.14 verbatim: "Start your first lock now."
        public static let firstWinHeadline = "Start your first lock now"
        /// Spec §7.14's "10-minute focus to unlock", shortened to 2 minutes so the first earned
        /// unlock lands inside spec §17's 4-minute budget. Keep in step with
        /// `Screen14FirstWin.plannedMinutes`.
        public static let firstWinSubtitle = "2-minute focus to unlock."
        public static let firstWinStartButton = "Start focus session"
        /// The intro's secondary action: skips the first win and goes straight into the app.
        public static let firstWinLaterButton = "Do it later"
        /// The alert when the focus session can't start (never the raw system error text).
        public static let firstWinStartErrorTitle = "Couldn't start the session"
        public static let firstWinStartErrorMessage = "Try again, or tap Do it later and start one from Today."
        public static let firstWinGoalTitle = "Focus session"
        public static let firstWinRunningHeadline = "Stay locked in"
        public static let firstWinRunningDetail = "Leaving the app pauses your timer. Come back to keep going."
        public static let firstWinEmergencyLabel = "Emergency unlock"
        public static let firstWinCelebrationTitle = "Earned."

        public static func firstWinCelebrationSubtitle(streak: Int) -> String {
            "Day \(streak) is on the board."
        }

        /// Neutral on purpose: this constant is shown to every coach voice, and "No worries" was
        /// Chill leaking in as everyone's default. (Per-voice variants need a voice parameter; see
        /// docs/design/writing-findings.md §3.6.)
        public static let firstWinNotVerifiedTitle = "Not this time"
        public static let firstWinNotVerifiedSubtitle = "You can always try again — your plan is already saved."
        public static let firstWinWidgetPromptHeadline = "Add ZANO to your Home Screen"
        public static let firstWinWidgetPromptStep1 = "Touch and hold your Home Screen"
        public static let firstWinWidgetPromptStep2 = "Tap the + button in the top corner"
        public static let firstWinWidgetPromptStep3 = "Search for ZANO and add the widget"
        public static let firstWinDoneButton = "Done"

        // MARK: - Container chrome (`OnboardingContainerView.swift`)

        public static let backButtonAccessibilityLabel = "Back"

        public static func progressAccessibilityLabel(screen: Int, total: Int) -> String {
            "Step \(screen) of \(total)"
        }
    }
}
