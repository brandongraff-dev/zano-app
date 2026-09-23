// Screen6Workouts.swift
// App / Features / Onboarding
//
// Owned by this session. docs/spec.md §7.6 (screen 6, Q4): "Current vs target workouts/week — Two
// steppers." `targetWorkoutsPerWeek` is deliberately >= 1 (see OnboardingFlowState.swift) — an
// additive-goals-only product (spec §3, §24) has no "target: 0 workouts" answer.
//
// ASSUMED API — see Screen3MainGoal.swift's header for the full note. New keys beyond that file's
// list: none — `q4Title`, `q4Subtitle`, `q4CurrentLabel`, `q4TargetLabel`,
// `q4WorkoutsPerWeekValue` are already listed there.

import SwiftUI
import Core

/// Screen 6 of 14 (spec §7.6) — Q4, two independent steppers (current, target workouts/week). No
/// validation gate: both fields have sensible defaults and any in-range combination is a valid
/// answer (including target == current, or target < current — the adaptive engine, spec §9.1,
/// reconciles the actual daily bar later; this screen just records stated intent).
struct Screen6Workouts: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q4Title, subtitle: Copy.onboarding.q4Subtitle) {
            VStack(spacing: Theme.Spacing.md) {
                stepperRow(
                    label: Copy.onboarding.q4CurrentLabel,
                    value: $flowState.currentWorkoutsPerWeek,
                    range: 0...7
                )
                stepperRow(
                    label: Copy.onboarding.q4TargetLabel,
                    value: $flowState.targetWorkoutsPerWeek,
                    range: 1...7
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.common.continueButtonLabel) {
                flowState.advance()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "workouts", "screen_number": 6]
            )
        }
    }

    private func stepperRow(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
            Stepper(value: value, in: range) {
                Text(Copy.onboarding.q4WorkoutsPerWeekValue(value.wrappedValue))
                    .font(Theme.Typography.numeralMedium())
                    .foregroundStyle(Theme.Colors.text)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

#Preview {
    Screen6Workouts(flowState: OnboardingFlowState())
}
