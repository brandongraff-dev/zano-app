// Screen3MainGoal.swift
// App / Features / Onboarding
//
// docs/spec.md §7.3 (screen 3, Q1): "Main goal — Get consistent at the gym / Hit my protein / Stop
// doomscrolling / Lock in on work-school / All of it." Option labels are spec-verbatim
// (`MainGoal.displayLabel`, `OnboardingFlowState.swift`).
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered, there is no Mac).
//
// Screens 1-7 were first restyled before the shared design system existed, so this file carried its
// own stand-ins for it. Those are gone now and everything points at the real Core pieces:
//   - `OnboardingDerivedColors`  -> `Theme.Colors.hairline / hairlineStrong / track / accentWash`
//   - `OnboardingCardPressStyle` -> `PressableStyle`
//   - the bespoke choice row     -> `SelectableCard` (one selected/unselected look app-wide: white
//                                   selection; visible 12% hairline otherwise)
//   - the hand-rolled pinned bar -> `zanoActionBar` (`StickyActionBar`)
// What is still hosted here for the question steps to share: `View.onboardingPinnedContinue`
// (pass 2 retired `OnboardingSingleChoiceList`). (Short flow, 2026-10-02: this is step 3 of 8.)
//
// Pacing (docs/design/competitive-research.md §3.5, "every input triggers a visible consequence"; Cal
// AI, Opal, Duolingo): Q1 used to be five text rows and nothing happened when you tapped one. Now a
// "Your plan" card above the options shows the three rings the app is built around (workout, protein,
// focus - the same trio screen 2 introduces). They start dim and empty; picking an answer ignites the
// ring(s) it will produce, so "All of it" lights all three. It is a literal preview of what screen 10
// builds (see `MainGoal.previewGoalTypes`), not decoration, and it is the visual link between "what I
// said" and "what the app will make me". Decorative for VoiceOver (the options carry the meaning).
//
// Motion: one-shot staggered entrance of the options (never blocks input), the ring ignite, one
// `.selection` haptic per change. All of it is off under Reduce Motion (rows are simply present, rings
// snap, no scale/offset).

// VISUAL PASS 2 (2026-10-03, "make it more playful"): a character select. The guide star sits under
// the question and says one line in a speech bubble; picking an answer makes it react (a charge
// burst, a new line, a soft haptic) and charges it a little more. The five answers are chunky glass
// tiles washed in a colour each, two to a row with "All of it" across the bottom (one per row at
// accessibility text sizes); the picked tile gets a coloured rim, a glow, a check sticker and a
// bouncing sticker icon. The "Your plan" ring preview row is gone: the star's reaction is the
// consequence of the tap now, and the plan step shows the rings for real.

// CHARACTER PASS (session 30, 2026-10-06): the guide acts out the answer: lifting for the gym,
// eating for protein, guarding (its padlock) for doomscrolling, focused for work/school, and for
// "All of it" it flexes while a confetti burst goes off behind it. Each change is a hop (the guide's
// own reaction). Reduce Motion: the faces change, the confetti cross-fades in place (Core handles it).

import SwiftUI
import Core

/// Step 3 of 8 (spec §7.3) - Q1, single-select main goal.
struct Screen3MainGoal: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var guideLine: String {
        flowState.mainGoal.map { Copy.onboarding.guideMainGoalReaction(rawValue: $0.rawValue) }
            ?? Copy.onboarding.guideMainGoalPrompt
    }

    private var guideTint: Color {
        flowState.mainGoal.map(tint(for:)) ?? Theme.Colors.accent
    }

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q1Title) {
            VStack(spacing: Theme.Spacing.lg) {
                OnboardingGuideStar(
                    line: guideLine,
                    charge: flowState.mainGoal == nil ? 0.3 : 0.55,
                    tint: guideTint,
                    mood: flowState.mainGoal == nil ? .idle : .perky,
                    pose: flowState.mainGoal.map(pose(for:)) ?? .idle
                )
                .overlay(alignment: .leading) {
                    if flowState.mainGoal == .allOfIt {
                        // Mounted on the pick, so it fires once per "All of it".
                        CelebrationBurst(trigger: 0)
                            .frame(width: 200, height: 200)
                            .offset(x: -68)
                            .allowsHitTesting(false)
                    }
                }
                tiles
            }
        }
        .onboardingEntrance()
        .onboardingPinnedContinue(
            title: Copy.common.continueButtonLabel,
            isEnabled: flowState.mainGoal != nil
        ) {
            flowState.advance()
        }
        .sensoryFeedback(.selection, trigger: flowState.mainGoal)
        .onAppear {
            appeared = true
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: OnboardingStep.mainGoal.viewedProperties
            )
        }
    }

    // MARK: - Tiles

    private var isSingleColumn: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The first four answers two to a row, the last ("All of it") across the bottom.
    private var tiles: some View {
        let options = MainGoal.allCases
        let gridOptions = isSingleColumn ? options : Array(options.dropLast())
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm),
            count: isSingleColumn ? 1 : 2
        )
        return VStack(spacing: Theme.Spacing.sm) {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(Array(gridOptions.enumerated()), id: \.element) { index, goal in
                    tile(goal, index: index, isWide: isSingleColumn)
                        .frame(minHeight: isSingleColumn ? nil : 136)
                }
            }
            if !isSingleColumn, let last = options.last {
                tile(last, index: options.count - 1, isWide: true)
            }
        }
    }

    private func tile(_ goal: MainGoal, index: Int, isWide: Bool) -> some View {
        OnboardingPickTile(
            title: goal.displayLabel,
            systemImage: symbol(for: goal),
            tint: tint(for: goal),
            isSelected: flowState.mainGoal == goal,
            isWide: isWide
        ) {
            flowState.mainGoal = goal
        }
        // A short one-shot stagger; never gates input (the tiles are tappable from frame one).
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : Theme.Spacing.sm)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard.delay(0.15 + Double(index) * 0.05), value: appeared)
    }

    /// The face the guide pulls for each answer.
    private func pose(for goal: MainGoal) -> BuddyPose {
        switch goal {
        case .gymConsistency: .lifting
        case .protein: .eating
        case .stopDoomscrolling: .guarding
        case .lockInWorkSchool: .focused
        case .allOfIt: .flexing
        }
    }

    /// SF Symbol identifiers (not user-facing copy).
    private func symbol(for goal: MainGoal) -> String {
        switch goal {
        case .gymConsistency: "dumbbell.fill"
        case .protein: "fork.knife"
        case .stopDoomscrolling: "iphone.slash"
        case .lockInWorkSchool: "book.closed.fill"
        case .allOfIt: "sparkles"
        }
    }

    /// Each answer wears the colour of the goal it builds (gym volt, protein apricot, focus violet);
    /// the two focus answers split violet and periwinkle so they read apart; "All of it" is sun.
    private func tint(for goal: MainGoal) -> Color {
        switch goal {
        case .gymConsistency: Theme.Colors.Ring.workout
        case .protein: Theme.Colors.Ring.protein
        case .stopDoomscrolling: Theme.Colors.Ring.sleepOnTime
        case .lockInWorkSchool: Theme.Colors.Ring.focus
        case .allOfIt: Theme.Colors.Ring.sunriseAlarm
        }
    }
}

// MARK: - Q1 -> plan preview

extension MainGoal {
    /// The goal types the plan reveal builds for this answer. This mirrors
    /// `Screen10PlanReveal.planGoals` (workout for gym, protein for protein, a focus session for both
    /// "stop doomscrolling" and "lock in", all three for "all of it"). It is a second copy of that
    /// switch on purpose: screen 10 is not editable from this wave. This is internal (not private) so
    /// that when screen 10 next changes it can read this property instead, making one source of truth
    /// and ensuring the preview here can never promise a ring the plan will not contain.
    var previewGoalTypes: [GoalType] {
        switch self {
        case .gymConsistency: [.workoutGym]
        case .protein: [.protein]
        case .stopDoomscrolling, .lockInWorkSchool: [.focusSession]
        case .allOfIt: [.workoutGym, .protein, .focusSession]
        }
    }
}

// MARK: - Shared by the question steps

extension View {
    /// Pins the onboarding "Continue" CTA to the bottom safe area in the shared `StickyActionBar`:
    /// one 16pt margin, one position and width for every screen 1-7, with a fade (not a blurred
    /// material strip) so content scrolling underneath dissolves instead of sliding behind an
    /// unbacked button. A disabled Continue is the palette's real disabled state (`surface2` +
    /// `muted`), not a dimmed accent.
    func onboardingPinnedContinue(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        zanoActionBar {
            PrimaryButton(title: title, isEnabled: isEnabled, action: action)
        }
    }
}

#Preview {
    Screen3MainGoal(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
