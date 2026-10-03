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

// VISUAL PASS 2 (2026-10-03, "make it more playful"): the math is the screen's one big moment. The
// days-a-year number is a huge score numeral in ember-to-red that counts up from zero when the
// screen opens (a rolling `numericText` with a tick of haptics, then one heavier tap as it lands),
// and rolls live as the slider moves. The hours sit above it as a chip; the reclaim half is a mint
// "+N days back a year" sticker (Core's `ZanoSticker`) under it. The slip chips are glass capsules with an "Optional" tag
// instead of "(optional)" in the heading. Reduce Motion: the final number from the first frame.

import SwiftUI
import Core

@MainActor
struct ScreenYourWhy: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The number on screen: counts up on appear, then follows the slider.
    @State private var shownDays = 0
    @State private var hasCounted = false
    @State private var landTick = 0

    private var hours: Double { flowState.dailyPhoneTimeHours }
    private var hoursText: String { Copy.onboarding.q3HoursValue(hours) }
    private var daysPerYear: Int { Int(flowState.estimatedDaysPerYearOnPhone.rounded()) }
    private var visibleDays: Int { reduceMotion ? daysPerYear : shownDays }

    private let chipColumns = [
        GridItem(.flexible(), spacing: Theme.Spacing.xs),
        GridItem(.flexible(), spacing: Theme.Spacing.xs),
    ]

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.yourWhyTitle, subtitle: Copy.onboarding.yourWhySubtitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                counterCard
                slider
                slipChips
            }
            .sensoryFeedback(.selection, trigger: hours)
        }
        .onboardingEntrance()
        .onboardingPinnedContinue(title: Copy.common.continueButtonLabel) {
            flowState.advance()
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: landTick)
        .preferredColorScheme(.dark)
        .task { await countUp() }
        .onChange(of: daysPerYear) { _, newValue in
            guard hasCounted else { return }
            withAnimation(reduceMotion ? nil : .snappy) { shownDays = newValue }
        }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: OnboardingStep.yourWhy.viewedProperties
            )
        }
    }

    // MARK: - The counter

    private var counterCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZanoGlassChip(Copy.onboarding.yourWhyHoursChip(hoursText), systemImage: "iphone", tint: Theme.Colors.ember)
                .contentTransition(.numericText())
                .accessibilityHidden(true)

            daysNumeral

            Text(Copy.onboarding.daysPerYearUnitLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            reclaimSticker
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoHero(tint: Theme.Colors.danger)
        .accessibilityElement(children: .combine)
    }

    /// The days, as big as the phone allows, ember into red. Shrinks rather than clips.
    private var daysNumeral: some View {
        Text("\(visibleDays)")
            .font(Theme.Typography.score(size: 104))
            .foregroundStyle(
                LinearGradient(colors: [Theme.Colors.ember, Theme.Colors.danger], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: Theme.Colors.danger.opacity(0.45), radius: 18)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: Double(visibleDays)))
            .accessibilityLabel("\(daysPerYear)")
    }

    /// "+30 days back a year", a mint sticker, and the condition under it.
    private var reclaimSticker: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ZanoSticker(
                Copy.onboarding.yourWhyReclaimChip(days: flowState.reclaimDaysPerYear),
                systemImage: "arrow.uturn.backward",
                color: Theme.Colors.Ring.steps,
                style: .filled,
                size: .large,
                bounceTrigger: flowState.reclaimDaysPerYear
            )

            Text(Copy.onboarding.yourWhyReclaimCondition(hoursLabel: Copy.onboarding.q3HoursValue(flowState.reclaimHours)))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    private var slider: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Slider(value: $flowState.dailyPhoneTimeHours, in: 1...10, step: 0.5) {
                Text(Copy.onboarding.q3Title)
            }
            .tint(Theme.Colors.ember)
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
            HStack(spacing: Theme.Spacing.xs) {
                Text(Copy.onboarding.yourWhySlipTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                ZanoGlassChip(Copy.onboarding.yourWhySlipOptional, tint: Theme.Colors.muted)
            }

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
        let shape = Capsule(style: .continuous)
        return Button {
            flowState.fallOffPattern = isSelected ? nil : pattern
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol(for: pattern))
                    .font(Theme.Typography.icon(.small, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .symbolEffect(.bounce, options: .nonRepeating, value: isSelected && !reduceMotion)
                    .accessibilityHidden(true)
                Text(pattern.displayLabel)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget, alignment: .leading)
            .background {
                if isSelected {
                    shape.fill(Theme.Colors.accentWash)
                } else {
                    ZanoGlass(shape)
                }
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(Theme.Colors.accent, lineWidth: Theme.Metrics.selectedStroke)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.95))
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: isSelected)
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

    // MARK: - Count-up

    /// Rolls the number up from zero in ten steps (~0.9s), ticking lightly, then lands with one
    /// heavier tap. Once only; the slider takes over after.
    private func countUp() async {
        guard !hasCounted else { return }
        guard !reduceMotion else {
            shownDays = daysPerYear
            hasCounted = true
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        let steps = 10
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let target = daysPerYear
            withAnimation(.snappy(duration: 0.12)) {
                shownDays = Int((Double(target) * Double(step) / Double(steps)).rounded())
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
        shownDays = daysPerYear
        hasCounted = true
        landTick += 1
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        ScreenYourWhy(flowState: flowState)
    }
}
