// ScreenYourWhy.swift
// App / Features / Onboarding
//
// Step 3 of 7, "Your why" (short flow, founder decision 2026-10-02). Three old screens in one:
//   - Q3 daily phone time (spec §7.5): the slider, with the hours as the hero numeral;
//   - the wake-up math (spec §7.9): "~N days a year on your phone", then the reclaim half,
//     "earn 2h a day back: N days a year back", both updating live as the slider moves;
//   - Q5 "when do you usually fall off?" (spec §7.7): optional chips under the card. Feeds slip
//     prediction's cold start when picked; Continue never waits on it.
//
// Color has one meaning each: `danger` is time on the phone, `text` is the reclaim (a promise, not an
// earned state), white is the selected chip. Every animation is gated on Reduce Motion; one
// `.selection` haptic per half-hour step and per chip.

import SwiftUI
import Core

@MainActor
struct ScreenYourWhy: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hours: Double { flowState.dailyPhoneTimeHours }
    private var hoursText: String { Copy.onboarding.q3HoursValue(hours) }
    private var daysPerYear: Int { Int(flowState.estimatedDaysPerYearOnPhone.rounded()) }

    private let chipColumns = [
        GridItem(.flexible(), spacing: Theme.Spacing.xs),
        GridItem(.flexible(), spacing: Theme.Spacing.xs),
    ]

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.yourWhyTitle, subtitle: Copy.onboarding.yourWhySubtitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                readoutCard
                slider
                slipChips
            }
            .sensoryFeedback(.selection, trigger: hours)
        }
        .onboardingEntrance()
        .onboardingPinnedContinue(title: Copy.common.continueButtonLabel) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: OnboardingStep.yourWhy.viewedProperties
            )
        }
    }

    // MARK: - The math

    private var readoutCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Decorative repeat of the slider's value; the slider carries the VoiceOver value.
            NumeralText(hoursText, size: .hero)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    NumeralText("\(daysPerYear)", size: .large, color: Theme.Colors.danger)
                    Text(Copy.onboarding.daysPerYearUnitLabel)
                        .zanoText(.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.text)
                        .accessibilityHidden(true)
                    Text(
                        Copy.onboarding.yourWhyReclaimLine(
                            hoursLabel: Copy.onboarding.q3HoursValue(flowState.reclaimHours),
                            days: flowState.reclaimDaysPerYear
                        )
                    )
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoWell()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoCard(radius: Theme.Radius.large)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: hours)
    }

    private var slider: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Slider(value: $flowState.dailyPhoneTimeHours, in: 1...10, step: 0.5) {
                Text(Copy.onboarding.q3Title)
            }
            .tint(Theme.Colors.interactive)
            .accessibilityValue(Text(hoursText))

            HStack {
                Text(Copy.onboarding.q3SliderMinLabel)
                Spacer()
                Text(Copy.onboarding.q3SliderMaxLabel)
            }
            .zanoText(.caption)
            .foregroundStyle(Theme.Colors.muted)
            .accessibilityHidden(true)
        }
    }

    // MARK: - When it slips (optional)

    private var slipChips: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.onboarding.yourWhySlipLabel)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)

            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(FallOffPattern.allCases, id: \.self) { pattern in
                    chip(pattern)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: flowState.fallOffPattern)
    }

    /// Tap to pick, tap again to clear: the answer is optional.
    private func chip(_ pattern: FallOffPattern) -> some View {
        let isSelected = flowState.fallOffPattern == pattern
        let shape = Capsule()
        return Button {
            flowState.fallOffPattern = isSelected ? nil : pattern
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol(for: pattern))
                    .font(Theme.Typography.icon(.xsmall))
                    .accessibilityHidden(true)
                Text(pattern.displayLabel)
                    .font(Theme.Typography.captionEmphasized)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget, alignment: .leading)
            .background(isSelected ? Theme.Colors.surface2 : Theme.Colors.surface, in: shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.interactive : Theme.Colors.hairline,
                    lineWidth: isSelected ? Theme.Metrics.selectedStroke : Theme.Metrics.edgeWidth
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.96))
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        ScreenYourWhy(flowState: flowState)
    }
}
