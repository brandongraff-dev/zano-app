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
//   - the bespoke choice row     -> `SelectableCard` (one selected/unselected look app-wide: accent wash
//                                   + 2pt accent edge + filled check; visible 12% hairline otherwise)
//   - the hand-rolled pinned bar -> `zanoActionBar` (`StickyActionBar`)
// What is still hosted here for screens 1-7 to share: `OnboardingSingleChoiceList` (screens 3 and 7)
// and `View.onboardingPinnedContinue` (all seven).
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

import SwiftUI
import Core

/// Screen 3 of 14 (spec §7.3) - Q1, single-select main goal.
struct Screen3MainGoal: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q1Title, subtitle: Copy.onboarding.q1Subtitle) {
            VStack(spacing: Theme.Spacing.lg) {
                OnboardingPlanPreview(selection: flowState.mainGoal)

                OnboardingSingleChoiceList(
                    options: MainGoal.allCases,
                    selection: flowState.mainGoal,
                    title: { $0.displayLabel },
                    symbol: { symbol(for: $0) },
                    onSelect: { flowState.mainGoal = $0 }
                )
            }
        }
        .onboardingPinnedContinue(
            title: Copy.common.continueButtonLabel,
            isEnabled: flowState.mainGoal != nil
        ) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "main_goal", "screen_number": 3]
            )
        }
    }

    /// SF Symbol identifiers (not user-facing copy). Chosen so each answer is recognizable from the
    /// glyph alone before the label is read.
    private func symbol(for goal: MainGoal) -> String {
        switch goal {
        case .gymConsistency: "dumbbell.fill"
        case .protein: "fork.knife"
        case .stopDoomscrolling: "iphone.slash"
        case .lockInWorkSchool: "book.closed.fill"
        case .allOfIt: "sparkles"
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

/// "Your plan" card: the three core rings, dim until the chosen answer makes them part of the plan.
/// Order matches Today (spec §16 P1: workout, protein, focus) and screen 2's ring trio.
private struct OnboardingPlanPreview: View {
    let selection: MainGoal?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Slot: Identifiable {
        let type: GoalType
        let icon: String
        var id: String { type.rawValue }
    }

    private let slots: [Slot] = [
        Slot(type: .workoutGym, icon: "dumbbell.fill"),
        Slot(type: .protein, icon: "fork.knife"),
        Slot(type: .focusSession, icon: "timer"),
    ]

    /// How full a lit ring is drawn. Partial on purpose (spec §8 rule 2: progress is always partially
    /// filled); it is a picture of "a ring you will fill", not a claim about the user's progress.
    private let litProgress = 0.62

    /// One compact row (eyebrow left, rings right, ~72pt) rather than a stacked card: the five options
    /// below need ~370pt, and a taller preview pushed the last one under the pinned Continue on a
    /// 393x852 phone (arithmetic, not a render).
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(Copy.onboarding.planRevealEyebrow)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)

            Spacer(minLength: Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(slots) { slot in
                    let isLit = selection?.previewGoalTypes.contains(slot.type) ?? false
                    GoalRing(
                        progress: isLit ? litProgress : 0,
                        color: isLit ? Theme.Colors.Ring.color(for: slot.type) : Theme.Colors.muted,
                        size: .custom(48),
                        center: .icon(systemName: slot.icon)
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: selection)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared by screens 1-7

/// A vertical list of single-select options, each a `SelectableCard` with a leading SF Symbol. Used by
/// Q1 (screen 3) and Q5 (screen 7). Titles come from the caller (spec-verbatim `displayLabel`s);
/// symbols are identifiers, not copy.
struct OnboardingSingleChoiceList<Option: Hashable>: View {
    let options: [Option]
    let selection: Option?
    let title: (Option) -> String
    let symbol: (Option) -> String
    let onSelect: (Option) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                SelectableCard(
                    title: title(option),
                    icon: symbol(option),
                    isSelected: selection == option
                ) {
                    onSelect(option)
                }
                // A short, one-shot stagger (onboarding is once-ever, so the sequence can carry
                // hierarchy). Never gates input: the cards are tappable from the first frame.
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : Theme.Spacing.xs)
                .animation(
                    reduceMotion ? nil : Animation.easeOut(duration: 0.35).delay(Double(index) * 0.06),
                    value: appeared
                )
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { appeared = true }
    }
}

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
