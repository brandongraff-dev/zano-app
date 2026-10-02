// OnboardingFlowState.swift
// App / Features / Onboarding
//
// The shared, transient state of the onboarding flow (docs/spec.md §7).
//
// SHORT FLOW (founder decision 2026-10-02: "first real win within ~3 minutes"). The flow was 15
// screens; it is now 7 steps. Nothing good was thrown away: screens were merged, and the optional
// setup topics moved to Today's "Finish setup" card (`App/ZANO/Features/Today/FinishSetupCard.swift`).
//
//   step  name            file                          was (old screen numbers)
//   1     hook            Screen1Hook.swift             1 Hook + 2 Social proof (claims now under the headline)
//   2     main_goal       Screen3MainGoal.swift         3 Q1 Main goal
//   3     your_why        ScreenYourWhy.swift           5 Q3 Phone time + 7 Q5 Fall-off + 10 Wake-up math
//   4     app_selection   Screen4AppSelection.swift     4 Q2 Apps (Screen Time permission + picker)
//   5     plan            Screen10PlanReveal.swift      11 Plan reveal + 6 Q4 workout target + 12 Commitment
//   6     paywall         PaywallView.swift             13 Paywall (hard; still directly after the commitment)
//   7     first_win       Screen14FirstWin.swift        14 Notification priming (folded into Start) + 15 First win
//
// Moved to the Today "Finish setup" card: 8 Coach voice (default Hype), 9 ZANO tags, gym setup,
// Sunrise alarm (wake time stays unset), squads. Q4's "current workouts" answer is gone; the target
// is a stepper on the plan card (default 3/week).
//
// The order keeps spec §7's two placement rules: nothing sits between the commitment and the hard
// paywall, and the paywall comes before the first win. Step numbers are the CI
// `-ZANOScreen onboarding-N` ids (`ScreenshotGallery.swift`) and the "Step N of 7" accessibility label
// the UI tests wait on.
//
// Persistence: this type is transient, in-memory UI state for the onboarding flow only. Nothing here
// is a SwiftData `@Model`. The plan step turns the answers into real `Goal` rows and the default
// `LockSet` at the moment the user commits.

import Foundation
import Observation
import FamilyControls
import Core

/// The seven onboarding steps, in order. `rawValue` is the 1-based step number.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case hook = 1
    case mainGoal
    case yourWhy
    case appSelection
    case plan
    case paywall
    case firstWin

    /// The `screen` property of every onboarding analytics event (identifiers, not copy).
    var analyticsName: String {
        switch self {
        case .hook: "hook"
        case .mainGoal: "main_goal"
        case .yourWhy: "your_why"
        case .appSelection: "app_selection"
        case .plan: "plan"
        case .paywall: "paywall"
        case .firstWin: "first_win"
        }
    }

    /// The analytics properties for "this step was viewed": its name, its number and the flow length.
    var viewedProperties: [String: Any] {
        ["screen": analyticsName, "screen_number": rawValue, "screen_count": OnboardingStep.allCases.count]
    }
}

/// The onboarding flow's shared state machine. Created once per onboarding attempt by
/// `OnboardingContainerView` and threaded to every step via `@Bindable`.
@MainActor
@Observable
final class OnboardingFlowState {

    static let firstScreen = OnboardingStep.hook.rawValue
    /// The last step number (First win).
    static let lastScreen = OnboardingStep.firstWin.rawValue

    /// 1-indexed step number (see the file header table).
    var currentScreen: Int = 1

    /// `currentScreen` as a step, clamped into range.
    var currentStep: OnboardingStep {
        OnboardingStep(rawValue: min(max(currentScreen, Self.firstScreen), Self.lastScreen)) ?? .hook
    }

    // MARK: - Answers

    /// Step 2: "Get consistent at the gym / Hit my protein / Stop doomscrolling / Lock in on
    /// work-school / All of it". `nil` until the user picks one.
    var mainGoal: MainGoal?

    /// Step 4: the FamilyControls selection. Device-local only, same rule as
    /// `LockSet.appTokensBlob` — never synced, never logged. Empty when Screen Time access was
    /// refused and the user continued without locking (the first win then runs as a plain timer).
    var selectedApps = FamilyActivitySelection()

    /// Step 3: daily phone time in hours, slider range 1...10.
    var dailyPhoneTimeHours: Double = 5

    /// Step 5 (plan card stepper): target workouts/week. Always >= 1: an additive-goals-only product
    /// has no "0 workouts" goal. Only shown when the plan contains a workout goal.
    var targetWorkoutsPerWeek: Int = 3

    /// Step 3 (optional chip): when the routine usually slips. Feeds slip prediction's cold start.
    /// `nil` when the user didn't pick one.
    var fallOffPattern: FallOffPattern?

    /// No longer asked in onboarding (moved to the Finish setup card). Stays the documented default,
    /// matching `SharedDefaults.coachVoice` and `User.coachVoice`.
    var coachVoice: CoachVoice = .hype

    /// Set when the user completes the hold-to-commit on the plan step.
    private(set) var committedAt: Date?

    init() {}

    // MARK: - Navigation

    /// Moves to the next step, clamped at `lastScreen`. Steps validate themselves before calling.
    func advance() {
        guard currentScreen < Self.lastScreen else { return }
        currentScreen += 1
    }

    /// Moves to the previous step, clamped at `firstScreen`.
    func goBack() {
        guard currentScreen > Self.firstScreen else { return }
        currentScreen -= 1
    }

    /// `currentScreen` as a 0...1 fraction of the flow (progress bar, header star charge).
    var progressFraction: Double {
        Double(currentScreen) / Double(Self.lastScreen)
    }

    /// Records the commitment timestamp. The most recent real hold wins.
    func recordCommitment(at date: Date = .now) {
        committedAt = date
    }

    // MARK: - Derived

    /// Whether step 4 produced anything to lock.
    var hasAppSelection: Bool {
        !selectedApps.applicationTokens.isEmpty
            || !selectedApps.categoryTokens.isEmpty
            || !selectedApps.webDomainTokens.isEmpty
    }

    /// "At 5h/day, that's ~76 days a year on your phone": `dailyPhoneTimeHours * 365 / 24`.
    var estimatedDaysPerYearOnPhone: Double {
        dailyPhoneTimeHours * 365 / 24
    }

    /// The reclaim half of the math: earning back up to 2 hours a day, in days a year.
    var reclaimHours: Double {
        min(dailyPhoneTimeHours, 2)
    }

    var reclaimDaysPerYear: Int {
        Int((reclaimHours * 365 / 24).rounded())
    }
}

// MARK: - MainGoal (step 2)

/// Copy note: this App-target enum's labels can't live in Core's `Copy` (Core cannot see App types),
/// so `displayLabel` is a narrow, documented exception to the "copy lives in Copy" rule. The labels
/// are spec §7.3's option list verbatim.
enum MainGoal: String, CaseIterable, Sendable, Hashable {
    case gymConsistency
    case protein
    case stopDoomscrolling
    case lockInWorkSchool
    case allOfIt

    var displayLabel: String {
        switch self {
        case .gymConsistency: "Get consistent at the gym"
        case .protein: "Hit my protein"
        case .stopDoomscrolling: "Stop doomscrolling"
        case .lockInWorkSchool: "Lock in on work-school"
        case .allOfIt: "All of it"
        }
    }
}

// MARK: - FallOffPattern (step 3)

/// See `MainGoal` for why `displayLabel` is inline here. Spec §7.7's option list verbatim.
enum FallOffPattern: String, CaseIterable, Sendable, Hashable {
    case weekends
    case evenings
    case whenStressed
    case afterGoodDays
    case travel

    var displayLabel: String {
        switch self {
        case .weekends: "Weekends"
        case .evenings: "Evenings"
        case .whenStressed: "When stressed"
        case .afterGoodDays: "After a few good days"
        case .travel: "Travel"
        }
    }
}
