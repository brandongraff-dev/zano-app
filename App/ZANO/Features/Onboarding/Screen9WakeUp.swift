// Screen9WakeUp.swift
// App / Features / Onboarding
//
// docs/spec.md §7.9 "Wake-up moment": 'Compute: "At 5h/day, that's ~76 days a year on your
// phone." Then: "Earning even 2h back = 30 days a year." Animated counter.' This is the emotional
// pivot of the flow — the first screen that turns the user's own Q3 answer (`dailyPhoneTimeHours`)
// into a stake big enough to justify everything that follows (spec §8 rule 10, "loss aversion,
// ethically": show what's at stake before a lock, never as a threat after a miss). It is also the
// app's "Focus Report" (competitive-research §3.5, Opal): the single most shareable fact.
//
// `flowState.estimatedDaysPerYearOnPhone` (`OnboardingFlowState.swift`, read, never edited) already
// computes the `dailyPhoneTimeHours * 365 / 24` arithmetic spec §7.9 asks for.
//
// Design pass (composition-audit offender 4, typography-color T3/T4/T5, better-layout 2.3,
// better-ui TYP-01/MOT-08):
//   - The hierarchy was inverted: the fear was 44pt and the reward 28pt, and the same fact was
//     stated three times (headline, counter, caption). Now one sentence is split around a
//     display numeral — lead-in, NUMBER, unit — so the number is stated once and is the loudest
//     thing on screen (96pt, `OnboardingKit.HeroNumeral`). The reward is the same size as the loss
//     and in accent, so the reason to continue is no smaller than the fear.
//   - It is staged: the loss lands first (red glow at the top of the screen, red numeral counting
//     up), then the reclaim (green glow rising from the bottom, accent numeral counting up), then a
//     success haptic. The CTA is available from the first frame; nothing gates it on the animation.
//   - Reduce Motion: no count-up, no stagger, no drift — both numbers are shown at their final
//     values immediately (the count-up was previously ungated; better-ui MOT-08).
//   - Each number now has a scale: a slim year bar under it (days / 365) fills in with its beat, so
//     the stat is a proportion you can see rather than a claim you have to trust (a bar that was
//     pure decoration would not earn its place; this one is the same fact the numeral states).
//   - Uses the shared pinned action bar (16pt margin) and a centered-or-scroll layout instead of a
//     fixed `Spacer` stack.

import SwiftUI
import Foundation
import Core

/// docs/spec.md §7.9. Reads `flowState.dailyPhoneTimeHours`/`.estimatedDaysPerYearOnPhone` (Q3,
/// screen 5) and turns them into two staged numerals with an animated count-up.
@MainActor
struct Screen9WakeUp: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = lead-in only, 1 = the loss numeral, 2 = the reclaim numeral.
    @State private var stage = 0

    /// Spec's second line is anchored to "2h back" specifically, not a fraction of the user's own
    /// total — reclaiming 2h reads as a concrete, achievable target regardless of how many hours
    /// they start from, and never exceeds their own daily total, so someone who reported *less*
    /// than 2h/day doesn't see a reclaim number bigger than their whole day.
    private var reclaimHours: Double {
        min(flowState.dailyPhoneTimeHours, 2)
    }

    private var daysPerYearOnPhone: Int {
        Int(flowState.estimatedDaysPerYearOnPhone.rounded())
    }

    private var daysReclaimedPerYear: Int {
        Int((reclaimHours * 365 / 24).rounded())
    }

    /// Reduce Motion shows everything at once, with no flash of the unrevealed state.
    private var visibleStage: Int {
        reduceMotion ? 2 : stage
    }

    var body: some View {
        OnboardingKit.CenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                lossBlock
                gainBlock
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background {
            // No opaque fill: the scaffold's flow ambient shows through under the two glows.
            ZStack {
                OnboardingKit.Glow(tint: Theme.Colors.danger, opacity: 0.10, anchor: .top)
                OnboardingKit.Glow(tint: Theme.Colors.accent, opacity: 0.12, anchor: .bottom)
                    .opacity(visibleStage >= 2 ? 1 : 0)
                    .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: visibleStage)
            }
        }
        .onboardingKitActionBar {
            PrimaryButton(title: Copy.onboarding.wakeUpContinueButton) {
                flowState.advance()
            }
        }
        .sensoryFeedback(.success, trigger: stage) { _, newValue in
            newValue == 2
        }
        .task {
            await runStages()
        }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "wake_up", "screen_number": 10]
            )
        }
    }

    // MARK: - Beat 1: the loss

    private var lossBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            OnboardingKit.Eyebrow(text: Copy.onboarding.wakeUpEyebrow)

            Text(Copy.onboardingReveal.wakeUpLeadIn(dailyHours: Int(flowState.dailyPhoneTimeHours.rounded())))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.top, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.xxs) {
                OnboardingAnimatedCount(
                    target: daysPerYearOnPhone,
                    color: Theme.Colors.danger,
                    isActive: visibleStage >= 1
                )
                Text(Copy.onboarding.daysPerYearUnitLabel)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                YearBar(days: daysPerYearOnPhone, color: Theme.Colors.danger, isActive: visibleStage >= 1)
                    .padding(.top, Theme.Spacing.xs)
            }
            .onboardingStaged(isVisible: visibleStage >= 1, reduceMotion: reduceMotion)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Beat 2: the reclaim

    private var gainBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // The reclaim, as the star: it charges as the "+N days" beat lands. Decorative.
            ZanoLivingMark(charge: visibleStage >= 2 ? 0.8 : 0.1, height: 44)
                .padding(.bottom, Theme.Spacing.xs)
                .accessibilityHidden(true)

            Text(
                Copy.onboardingReveal.wakeUpReclaimLeadIn(
                    hoursLabel: Copy.onboarding.q3HoursValue(reclaimHours)
                )
            )
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.muted)

            VStack(spacing: Theme.Spacing.xxs) {
                OnboardingAnimatedCount(
                    target: daysReclaimedPerYear,
                    color: Theme.Colors.accent,
                    prefix: "+",
                    isActive: visibleStage >= 2
                )
                Text(Copy.onboardingReveal.wakeUpReclaimUnit)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                YearBar(days: daysReclaimedPerYear, color: Theme.Colors.accent, isActive: visibleStage >= 2)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .onboardingStaged(isVisible: visibleStage >= 2, reduceMotion: reduceMotion)
    }

    // MARK: - Staging

    private func runStages() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.Motion.springStandard) { stage = 1 }

        // The loss numeral counts for ~0.9s (`OnboardingAnimatedCount`); the reclaim lands after it
        // has settled and had a beat to be read.
        try? await Task.sleep(for: .milliseconds(1700))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.Motion.springStandard) { stage = 2 }
    }
}

// MARK: - Year bar

/// The number as a share of the year: a slim track with a hue fill, `days / 365` wide. A stat with
/// no scale is just a claim; this is the consequence made visible (the pattern Cal AI and Opal use
/// to make every onboarding answer *do* something, competitive-research §3.5). Decorative — the
/// numeral above it carries the meaning — so it is hidden from VoiceOver. The fill grows once
/// when its beat lands; under Reduce Motion it is simply drawn at its final width.
private struct YearBar: View {
    let days: Int
    let color: Color
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width: CGFloat = 240

    private var fraction: Double {
        min(1, max(0, Double(days) / 365))
    }

    private var isFilled: Bool {
        isActive || reduceMotion
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.Colors.track)
            Capsule()
                .fill(color)
                .frame(width: Self.width * (isFilled ? fraction : 0))
                .shadow(color: color.opacity(0.3), radius: 4)
        }
        .frame(width: Self.width, height: Theme.Spacing.xs)
        .animation(reduceMotion ? nil : Theme.Motion.ringFill, value: isFilled)
        .accessibilityHidden(true)
    }
}

// MARK: - Staged reveal

private extension View {
    /// Fades and rises a block in when `isVisible` flips. Under Reduce Motion the caller already
    /// passes `true` from the first frame, so there is nothing to animate.
    func onboardingStaged(isVisible: Bool, reduceMotion: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : Theme.Spacing.md)
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isVisible)
            .accessibilityHidden(!isVisible)
    }
}

// MARK: - Animated count

/// A display numeral that counts up from 0 to `target` once when it becomes active — the "animated
/// counter" spec §7.9 asks for. `internal` so a later pass can reuse the effect; today only this
/// file uses it. Under Reduce Motion it shows `target` immediately (no loop at all).
@MainActor
struct OnboardingAnimatedCount: View {
    let target: Int
    let color: Color
    /// A symbol (not copy) shown before the digits, e.g. "+".
    var prefix: String = ""
    /// The count starts when this becomes `true`; before that it rests at 0.
    var isActive: Bool = true
    var tier: OnboardingKit.HeroNumeral.Tier = .hero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedValue = 0

    /// Total time the count-up animates over. Kept comfortably inside
    /// `Theme.Motion.unlockCelebrationMaxDuration` (spec §15: "unlock celebration <= 1.2s") even
    /// though this isn't an unlock celebration itself — the same "don't overstay the moment"
    /// motion budget reads right here too.
    private static let countDuration: TimeInterval = 0.9
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    private struct CountKey: Equatable {
        let target: Int
        let isActive: Bool
    }

    /// Reduce Motion never shows the intermediate frames (or the initial 0).
    private var shownValue: Int {
        reduceMotion ? target : displayedValue
    }

    var body: some View {
        OnboardingKit.HeroNumeral(text: "\(prefix)\(shownValue)", color: color, tier: tier)
            .task(id: CountKey(target: target, isActive: isActive)) {
                await count()
            }
            .accessibilityLabel("\(prefix)\(target)")
    }

    private func count() async {
        guard isActive else {
            displayedValue = 0
            return
        }
        guard !reduceMotion, target > 0 else {
            displayedValue = target
            return
        }
        displayedValue = 0
        let steps = max(1, Int(Self.countDuration / Self.frameInterval))
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(Self.frameInterval))
            if Task.isCancelled { return }
            let progress = Double(step) / Double(steps)
            // Ease-out: the count decelerates into its final value instead of stopping dead.
            let eased = 1 - pow(1 - progress, 3)
            withAnimation(.linear(duration: Self.frameInterval)) {
                displayedValue = Int((Double(target) * eased).rounded())
            }
        }
        displayedValue = target
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen9WakeUp(flowState: flowState)
    }
}
