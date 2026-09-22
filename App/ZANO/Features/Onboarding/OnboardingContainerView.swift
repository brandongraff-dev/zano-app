// OnboardingContainerView.swift
// App / Features / Onboarding
//
// Owned by: this session's task ("Screens 9-14 + OnboardingContainerView"). Do not edit from
// another session — CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §7 (Onboarding Flow, screen by screen) lists all 14 screens; §17 Session 6
// (`feat/onboarding`) owns "Onboarding (14 screens) + permission priming + RevenueCat paywall +
// first-win flow" as one unit. This file is the single root that wires every screen — 1-8 and the
// shared `OnboardingFlowState` (owned by a sibling agent this same batch, `OnboardingFlowState.
// swift` — read in full, never edited) plus 9-14 (this session's own files, `Screen9WakeUp.swift`
// through `Screen14FirstWin.swift`) — into one sequential flow, per this task's brief:
// "OnboardingContainerView wiring all 14 in order."
//
// ============================================================================================
// VERIFIED — `OnboardingFlowState` (`App/ZANO/Features/Onboarding/OnboardingFlowState.swift`,
// sibling-owned; this file quotes its real, on-disk shape rather than an assumption, since that
// file landed on disk while this task was in progress — every property/method name below was
// read directly off it, not guessed):
//
//     @MainActor @Observable final class OnboardingFlowState {
//         static let firstScreen = 1; static let lastScreen = 14
//         var currentScreen: Int                       // 1...14, drives this container's switch
//         var mainGoal: MainGoal?                       // Q1 (screen 3)
//         var selectedApps = FamilyActivitySelection()  // Q2 (screen 4)
//         var dailyPhoneTimeHours: Double = 5            // Q3 (screen 5), slider 1...10
//         var currentWorkoutsPerWeek: Int = 0            // Q4 (screen 6)
//         var targetWorkoutsPerWeek: Int = 3             // Q4 (screen 6)
//         var fallOffPattern: FallOffPattern?            // Q5 (screen 7)
//         var coachVoice: CoachVoice = .hype             // Q6 (screen 8) — Core's own type, reused
//         private(set) var committedAt: Date?            // screen 11: recordCommitment(at:)
//         func advance()                                 // currentScreen += 1, clamped at lastScreen
//         func goBack()                                  // currentScreen -= 1, clamped at firstScreen
//         var progressFraction: Double                   // currentScreen / lastScreen
//         func recordCommitment(at date: Date = .now)
//         var estimatedDaysPerYearOnPhone: Double         // dailyPhoneTimeHours * 365 / 24
//     }
//     enum MainGoal: String, CaseIterable, Sendable, Hashable {
//         case gymConsistency, protein, stopDoomscrolling, lockInWorkSchool, allOfIt
//         var displayLabel: String { ... }  // App-target-only exception to Copy-routing — see
//     }                                     // that file's own doc comment for why.
//     enum FallOffPattern: String, CaseIterable, Sendable, Hashable {
//         case weekends, evenings, whenStressed, afterGoodDays, travel
//         var displayLabel: String { ... }
//     }
//
// `MainGoal`/`FallOffPattern` are App-target types — Core (and therefore any `Copy.onboarding.*`
// function this session assumes) cannot take either as a parameter. Every screen in this session
// that needs one of their labels resolves `.displayLabel` on the App side first and only passes
// the resulting `String` across the Core boundary (see `Screen10PlanReveal.swift`).
//
// Every screen (1-14) takes `@Bindable var flowState: OnboardingFlowState` and advances itself via
// `flowState.advance()`; this container never drives navigation from the outside beyond back-button
// chrome (`flowState.goBack()`, `OnboardingScaffold` below).
//
// ============================================================================================
// Screen 13 note — a genuine cross-agent duplication, resolved here: this session's own task asked
// for "a paywall placeholder screen with a clear extension point for the real RevenueCat wiring"
// (`Screen13Paywall.swift`, built and kept — see that file's own updated header). While this task
// was in progress, a separate "Monetization/Paywall" task this same batch independently built a
// full, real `PaywallView.swift` backed by `Core/Sources/Core/Monetization/PaywallViewModel.swift`
// (real RevenueCat offerings, purchase/restore flow, a `PaywallCard` component, `Copy.paywall.*`) —
// strictly more complete than this session's own placeholder. Since only one screen 13 can be
// wired, this container routes to the real `PaywallView`, not `Screen13Paywall`. Flagged for the
// orchestrator in this task's `knownIssues`/`decisions`; `Screen13Paywall.swift` is left on disk,
// fully working, as delivered per this session's literal assignment, but is dead code as wired.
// ============================================================================================

import SwiftUI
import SwiftData
import Core

/// Root of the 14-screen onboarding flow (docs/spec.md §7). Owns the one shared
/// `OnboardingFlowState` for the whole flow and renders whichever screen
/// `flowState.currentScreen` names, with a consistent progress-bar/back-button chrome
/// (`OnboardingScaffold`, below) wrapping every screen.
///
/// Expected to be hosted by whatever decides onboarding should show at all (e.g. `ContentView`,
/// or a future "has this device finished onboarding?" gate) — that decision, and what happens
/// after `onFinished` fires, belong to that caller, not this file. This container's only two
/// jobs are (1) own `flowState` for the whole flow's lifetime, and (2) route between screens.
@MainActor
struct OnboardingContainerView: View {
    /// Called once, after Screen 14's widget-add prompt is dismissed. Defaults to a no-op so this
    /// view compiles and behaves standalone (e.g. in `#Preview`); a real host wires it to record
    /// "onboarding complete" and swap to the app's main tab UI.
    var onFinished: () -> Void = {}

    @State private var flowState = OnboardingFlowState()

    var body: some View {
        OnboardingScaffold(flowState: flowState) {
            screen(for: flowState.currentScreen)
                .id(flowState.currentScreen)
                .transition(screenTransition)
        }
        .animation(Theme.Motion.springStandard, value: flowState.currentScreen)
    }

    @ViewBuilder
    private func screen(for screenNumber: Int) -> some View {
        switch screenNumber {
        case 1: Screen1Hook(flowState: flowState)
        case 2: Screen2SocialProof(flowState: flowState)
        case 3: Screen3MainGoal(flowState: flowState)
        case 4: Screen4AppSelection(flowState: flowState)
        case 5: Screen5PhoneTime(flowState: flowState)
        case 6: Screen6Workouts(flowState: flowState)
        case 7: Screen7FallOff(flowState: flowState)
        case 8: Screen8CoachVoice(flowState: flowState)
        case 9: Screen9WakeUp(flowState: flowState)
        case 10: Screen10PlanReveal(flowState: flowState)
        case 11: Screen11Commitment(flowState: flowState)
        case 12: Screen12PermissionPriming(flowState: flowState)
        case 13: PaywallView(flowState: flowState)
        default: Screen14FirstWin(flowState: flowState, onFinished: onFinished)
        }
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Shared chrome

/// Consistent top progress bar + back button wrapped around every onboarding screen, per
/// docs/spec.md §7's framing ("Target: 10-14 screens, under 3 minutes") — a visible progress bar
/// is what makes a 14-screen flow feel short rather than endless. `internal` (default access), not
/// `private`, so `Screen9WakeUp.swift`...`Screen14FirstWin.swift` can reuse it too instead of each
/// re-implementing the same header.
@MainActor
struct OnboardingScaffold<Content: View>: View {
    @Bindable var flowState: OnboardingFlowState
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                if flowState.currentScreen > OnboardingFlowState.firstScreen {
                    Button {
                        flowState.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.muted)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(Copy.onboarding.backButtonAccessibilityLabel)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
                Spacer()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.surface2)
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: proxy.size.width * flowState.progressFraction)
                        .animation(Theme.Motion.ringFill, value: flowState.progressFraction)
                }
            }
            .frame(height: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Copy.onboarding.progressAccessibilityLabel(
                    screen: flowState.currentScreen,
                    total: OnboardingFlowState.lastScreen
                )
            )
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Shared helpers (used by this session's Screen9...Screen14 files)

/// Fetch-or-create the device's one local `User` row (per `Models/User.swift`'s own doc comment:
/// exactly one exists locally, the signed-in-or-anonymous owner of this device). Onboarding is the
/// natural place this row first comes into existence — everything before Screen 10/11 only mutates
/// `flowState`, never SwiftData, so this is the first point in the flow that actually needs a real
/// `User` to attach a `Goal`/`LockSet` to. Idempotent: returns the existing row (refreshing its
/// `coachVoice`) on every call after the first.
///
/// `internal`, not `private`, so `Screen10PlanReveal.swift`, `Screen11Commitment.swift`, and
/// `Screen14FirstWin.swift` can share it rather than each re-fetching/re-creating independently
/// (CLAUDE.md: "never duplicate the same logic in two places").
@MainActor
func onboardingResolveOrCreateUser(coachVoice: CoachVoice, in context: ModelContext) throws -> User {
    var descriptor = FetchDescriptor<User>()
    descriptor.fetchLimit = 1
    if let existing = try context.fetch(descriptor).first {
        existing.coachVoice = coachVoice
        return existing
    }
    let user = User(coachVoice: coachVoice)
    context.insert(user)
    try context.save()
    return user
}

#Preview {
    OnboardingContainerView()
        .modelContainer(for: User.self, inMemory: true)
}
