// Screen5PhoneTime.swift
// App / Features / Onboarding
//
// docs/spec.md §7.5 (screen 5, Q3): "Daily phone time - Slider 1-10h." Feeds screen 9's "Wake-up
// moment" (spec §7.9, `OnboardingFlowState.estimatedDaysPerYearOnPhone`).
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered). This is the flow's most
// interactive input, and the competitive research's onboarding-pacing finding (§3.5: Cal AI / Opal /
// Duolingo, "every input triggers a visible consequence") applies to it directly. It was already
// wired that way; this pass makes it one composed object instead of four stacked bits:
//   - A single hero card holds the answer as a picture. Top: the hours as the screen's hero numeral
//     (`NumeralText(.hero)`: 72pt heavy digits with the "h" as a small baseline unit, rolling with
//     `.numericText` as the slider moves; Dynamic Type aware and clamped so it cannot outgrow the
//     card). Middle: a 24-segment "your day" bar lighting hour by hour (half-hours light half a
//     segment). Bottom, in a recessed `zanoWell` (concentric: the hero radius 28 minus the 16pt inset
//     is the small radius 12): the live consequence, "N days a year on your phone", updating as you
//     drag. Screen 9 then lands as confirmation instead of first news.
//   - The slider sits below the card, in the thumb zone, not above the number it drives. The native
//     `Slider` is kept on purpose: drag physics, VoiceOver adjustability and, on iOS 26, the system's
//     tinted track. Its label/value come from existing Copy so VoiceOver reads "6.5h", not "40%".
//   - Color has one meaning: `danger` is time on the phone (the day bar and the days-a-year figure,
//     the same meaning screen 9 gives it). The hours themselves are `text`; nothing here is accent.
//   - Tone: it states a fact the user asked to see about their own answer; it does not scold (spec §8
//     rule 9) and it makes no prediction about them.
//   - One `.selection` haptic per half-hour step. Every animation is gated on Reduce Motion (`nil`
//     animation; the numeral and bar simply snap, and `NumeralText` swaps its transition for none).
//
// Note for screen 9's owner: its counter now repeats what this screen already showed; the stronger
// beat there is the reclaim half ("earning 2h back = N days").

import SwiftUI
import Core

/// Screen 5 of 14 (spec §7.5) - Q3, a single slider bound directly to
/// `flowState.dailyPhoneTimeHours`. No validation gate: any value in 1...10 is a valid answer, so
/// Continue is always enabled here.
struct Screen5PhoneTime: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let hoursInDay = 24

    private var hours: Double { flowState.dailyPhoneTimeHours }
    private var hoursText: String { Copy.onboarding.q3HoursValue(hours) }
    private var daysPerYear: Int { Int(flowState.estimatedDaysPerYearOnPhone.rounded()) }

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q3Title, subtitle: Copy.onboarding.q3Subtitle) {
            VStack(spacing: Theme.Spacing.lg) {
                readoutCard
                slider
            }
            .sensoryFeedback(.selection, trigger: hours)
        }
        .onboardingPinnedContinue(title: Copy.common.continueButtonLabel) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "phone_time", "screen_number": 5]
            )
        }
    }

    // MARK: - Pieces

    /// The answer as a picture: hours, the day it takes up, and what that adds up to.
    private var readoutCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Decorative repeat of the slider's value; the slider itself carries the VoiceOver value.
            NumeralText(hoursText, size: .hero)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            dayBar

            consequence
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoCard(radius: Theme.Radius.large)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: hours)
    }

    /// 24 hour-segments of "your day"; the first `hours` of them are lit. Half-hours light half a
    /// segment (the slider steps by 0.5). Purely a picture of the answer, hidden from VoiceOver.
    private var dayBar: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(0..<hoursInDay, id: \.self) { hour in
                let fill = min(1, max(0, hours - Double(hour)))
                Capsule()
                    .fill(Theme.Colors.track)
                    .overlay(alignment: .bottom) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.Colors.danger)
                                .frame(height: proxy.size.height * fill)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: Theme.Spacing.xl)
        .accessibilityHidden(true)
    }

    /// The live consequence: the same number screen 9 reveals, updating as the slider moves.
    private var consequence: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            NumeralText("\(daysPerYear)", size: .large, color: Theme.Colors.danger)
            Text(Copy.onboarding.daysPerYearUnitLabel)
                .zanoText(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoWell()
        .accessibilityElement(children: .combine)
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
}

#Preview {
    Screen5PhoneTime(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
