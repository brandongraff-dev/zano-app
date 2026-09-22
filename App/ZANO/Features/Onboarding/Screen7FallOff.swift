// Screen7FallOff.swift
// App / Features / Onboarding
//
// Owned by this session. docs/spec.md §7.7 (screen 7, Q5): "When do you usually fall off? —
// Weekends / Evenings / When stressed / After a few good days / Travel. (Feeds slip prediction
// cold start.)" §9.2 Slip Prediction lists "historical miss pattern from onboarding Q5" as a
// cold-start feature for the logistic-regression fallback model — `flowState.fallOffPattern` is
// that raw answer; turning it into an actual `risk_scores` cold-start feature is §9.2's job
// downstream (spec §17 row 12, `feat/ml`), not this screen's.
//
// ASSUMED API — see Screen3MainGoal.swift's header for the full note. New keys beyond that file's
// list: none — `q5Title`/`q5Subtitle` are already listed there.

import SwiftUI
import Core

/// Screen 7 of 14 (spec §7.7) — Q5, single-select fall-off pattern. Same card-row treatment as
/// `Screen3MainGoal`.
struct Screen7FallOff: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q5Title, subtitle: Copy.onboarding.q5Subtitle) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(FallOffPattern.allCases, id: \.self) { pattern in
                    optionRow(pattern)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: Copy.common.continueButtonLabel, isEnabled: flowState.fallOffPattern != nil) {
                flowState.advance()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .preferredColorScheme(.dark)
    }

    private func optionRow(_ pattern: FallOffPattern) -> some View {
        let isSelected = flowState.fallOffPattern == pattern
        return Button {
            flowState.fallOffPattern = pattern
        } label: {
            HStack {
                Text(pattern.displayLabel)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.surface2 : Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent : Theme.Colors.hairline,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.springStandard, value: isSelected)
    }
}

#Preview {
    Screen7FallOff(flowState: OnboardingFlowState())
}
