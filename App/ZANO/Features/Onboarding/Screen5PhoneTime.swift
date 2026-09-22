// Screen5PhoneTime.swift
// App / Features / Onboarding
//
// Owned by this session. docs/spec.md §7.5 (screen 5, Q3): "Daily phone time — Slider 1–10h."
// Feeds screen 9's "Wake-up moment" (spec §7.9, `OnboardingFlowState.estimatedDaysPerYearOnPhone`)
// downstream in onboarding-2.
//
// ASSUMED API — see Screen3MainGoal.swift's header for the full note. New keys beyond that file's
// list: none — `q3Title`, `q3Subtitle`, `q3HoursValue`, `q3SliderMinLabel`, `q3SliderMaxLabel` are
// already listed there.

import SwiftUI
import Core

/// Screen 5 of 14 (spec §7.5) — Q3, a single slider bound directly to
/// `flowState.dailyPhoneTimeHours`. No validation gate: any value in 1...10 is a valid answer, so
/// Continue is always enabled here.
struct Screen5PhoneTime: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q3Title, subtitle: Copy.onboarding.q3Subtitle) {
            VStack(spacing: Theme.Spacing.lg) {
                Text(Copy.onboarding.q3HoursValue(flowState.dailyPhoneTimeHours))
                    .font(Theme.Typography.numeralLarge())
                    .foregroundStyle(Theme.Colors.accent)
                    .animation(Theme.Motion.springStandard, value: flowState.dailyPhoneTimeHours)

                Slider(value: $flowState.dailyPhoneTimeHours, in: 1...10, step: 0.5)
                    .tint(Theme.Colors.accent)

                HStack {
                    Text(Copy.onboarding.q3SliderMinLabel)
                    Spacer()
                    Text(Copy.onboarding.q3SliderMaxLabel)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.common.continueButtonLabel) {
                flowState.advance()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    Screen5PhoneTime(flowState: OnboardingFlowState())
}
