// Screen7FallOff.swift
// App / Features / Onboarding
//
// docs/spec.md §7.7 (screen 7, Q5): "When do you usually fall off? — Weekends / Evenings / When
// stressed / After a few good days / Travel. (Feeds slip prediction cold start.)" §9.2 Slip
// Prediction lists "historical miss pattern from onboarding Q5" as a cold-start feature for the
// logistic-regression fallback model - `flowState.fallOffPattern` is that raw answer; turning it
// into an actual `risk_scores` feature is §9.2's job downstream, not this screen's.
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered). This screen renders
// through `OnboardingSingleChoiceList` (hosted in `Screen3MainGoal.swift`; `SelectableCard` rows with
// a leading glyph, a visible unselected edge, a press state, a Reduce-Motion-gated selection and a
// haptic). Glyphs are chosen so the pattern reads before the label does. Tone (spec §8 rule 9, no
// shame): "After a few good days" gets a neutral trend glyph, not a warning symbol; the flow says where
// slips happen so the app can help, not that the user is failing.
//
// Pacing (docs/design/competitive-research.md §3.5, "every input triggers a visible consequence"): a
// slip pattern used to be a tap that did nothing visible. Now picking one shows, below the list, the
// promise the answer buys - "We'll watch weekends, when things usually slip." That is the same
// sentence the plan reveal shows on screen 10 (`Copy.onboarding.planScheduleFallOffNote`, no new
// copy), so the app visibly listens here and keeps the promise there. It sits BELOW the options
// rather than expanding the chosen row, so no tap target moves under the user's finger when they
// change their mind. It fades and rises in (a plain fade under Reduce Motion) and re-keys per answer,
// so switching answers cross-fades the note instead of silently swapping text.

import SwiftUI
import Core

/// Screen 7 of 15 (spec §7.7) - Q5, single-select fall-off pattern.
struct Screen7FallOff: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q5Title, subtitle: Copy.onboarding.q5Subtitle) {
            VStack(spacing: Theme.Spacing.lg) {
                OnboardingSingleChoiceList(
                    options: FallOffPattern.allCases,
                    selection: flowState.fallOffPattern,
                    title: { $0.displayLabel },
                    symbol: { symbol(for: $0) },
                    onSelect: { flowState.fallOffPattern = $0 }
                )

                slipNote
            }
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: flowState.fallOffPattern)
        }
        .onboardingEntrance()
        .onboardingPinnedContinue(
            title: Copy.common.continueButtonLabel,
            isEnabled: flowState.fallOffPattern != nil
        ) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "fall_off", "screen_number": 7]
            )
        }
    }

    // MARK: - Consequence

    /// "We'll watch ...": neutral on purpose (`text` glyph, plain card). The note is a promise, not a
    /// selection state, so it does not spend the accent.
    @ViewBuilder
    private var slipNote: some View {
        if let pattern = flowState.fallOffPattern {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "shield.lefthalf.filled", tint: Theme.Colors.text, size: .small)

                // `FallOffPattern` is App-target-only (`OnboardingFlowState.swift`), so its label is
                // resolved here and only the plain `String` crosses into Core's `Copy` (the same
                // narrow routing exception screen 10 uses for the same sentence).
                Text(Copy.onboarding.planScheduleFallOffNote(patternLabel: pattern.displayLabel))
                    .zanoText(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
            .accessibilityElement(children: .combine)
            .id(pattern)
            .transition(noteTransition)
        }
    }

    /// Fade and rise in; a plain fade under Reduce Motion. Typed explicitly so it cannot resolve to
    /// iOS 17's `Transition` protocol overload of `.transition(_:)`.
    private var noteTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: AnyTransition.offset(y: Theme.Spacing.xs))
    }

    /// SF Symbol identifiers (not user-facing copy).
    private func symbol(for pattern: FallOffPattern) -> String {
        switch pattern {
        case .weekends: "calendar"
        case .evenings: "moon.stars.fill"
        case .whenStressed: "waveform.path.ecg"
        case .afterGoodDays: "chart.line.downtrend.xyaxis"
        case .travel: "airplane"
        }
    }
}

#Preview {
    Screen7FallOff(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
