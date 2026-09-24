// Screen6Workouts.swift
// App / Features / Onboarding
//
// docs/spec.md §7.6 (screen 6, Q4): "Current vs target workouts/week - Two steppers."
// `targetWorkoutsPerWeek` is deliberately >= 1 (see OnboardingFlowState.swift): an additive-goals-only
// product (spec §3, §24) has no "target: 0 workouts" answer. No validation gate: both fields have
// sensible defaults and any in-range combination is a valid answer (including target == current, or
// target < current - the adaptive engine, spec §9.1, reconciles the actual daily bar later; this
// screen just records stated intent).
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered). Findings applied:
//   - The two system `Stepper`s (~94x32pt) are 44pt round minus/plus buttons flanking a numeral
//     (better-ui HIT-07: the system stepper is the input for onboarding's Q4). The value is a
//     `NumeralText(.large)`: 44pt digits with "x/week" as a small baseline unit (it was one 44pt
//     string, unit and all), rolling with `.numericText` on change.
//   - It is ONE card with two counters, "Right now" above "My goal", joined by a hairline with a small
//     arrow. Two identical sibling cards read as two unrelated inputs; the connector makes it a
//     from -> to story (spec: "current vs target"). The card is the shared `zanoCard`.
//   - Each answer keeps its visible consequence (competitive-research §3.5): a 7-segment "week" bar
//     under the value. "Right now" lights N segments in `muted`; "My goal" lights the same segments in
//     `muted` and the growth beyond them in white (not accent: a goal is not earned yet), so the gap between today and the goal is
//     literally drawn. Where the goal is below the current pace the bar just shows the goal count (no
//     shame framing, spec §8 rule 9). The segments are counts, not weekdays, and unlabeled on purpose:
//     workouts/week is not "which days".
//   - The labels are the shared `eyebrow` style (sentence case), the buttons the shared
//     `PressableStyle` (0.94: a small control shrinks more than a card), the empty segments the shared
//     `track` token. One `.selection` haptic per change. Gated on Reduce Motion.
//   - Accessibility: each counter is one adjustable element (label + value + increment/decrement), the
//     way a system stepper reads, so VoiceOver users swipe up/down instead of hunting two tiny
//     buttons. The visual buttons are hidden from the accessibility tree. Trade-off: Voice Control
//     users have no spoken "tap minus" target (that would need new Copy keys, not editable here); the
//     adjustable action is still reachable via Voice Control's and Switch Control's action menus.

import SwiftUI
import Core

/// Screen 6 of 15 (spec §7.6) - Q4, two independent counters (current, target workouts/week).
struct Screen6Workouts: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q4Title, subtitle: Copy.onboarding.q4Subtitle) {
            VStack(spacing: 0) {
                WorkoutsCounterRow(
                    label: Copy.onboarding.q4CurrentLabel,
                    value: $flowState.currentWorkoutsPerWeek,
                    range: 0...7,
                    baseline: nil
                )

                connector

                WorkoutsCounterRow(
                    label: Copy.onboarding.q4TargetLabel,
                    value: $flowState.targetWorkoutsPerWeek,
                    range: 1...7,
                    baseline: flowState.currentWorkoutsPerWeek
                )
            }
            .zanoCard()
        }
        .onboardingEntrance()
        .onboardingPinnedContinue(title: Copy.common.continueButtonLabel) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "workouts", "screen_number": 6]
            )
        }
    }

    /// A hairline with a small "from -> to" arrow riding on it. The badge is 24pt (`Spacing.lg`), so
    /// its 12pt radius sits inside the rows' 16pt padding and never touches a bar or a label.
    private var connector: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: Theme.Metrics.edgeWidth)
            .overlay {
                Image(systemName: "arrow.down")
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: Theme.Spacing.lg, height: Theme.Spacing.lg)
                    .background(Theme.Colors.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
            }
            .accessibilityHidden(true)
    }
}

/// One counter: label, big value with minus/plus, and a 7-segment week bar. It has no surface of its
/// own; `Screen6Workouts` wraps both counters in one card.
private struct WorkoutsCounterRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// When non-nil, segments up to `min(value, baseline)` are drawn as "already doing this" (muted)
    /// and any segments beyond that up to `value` as growth (white). When nil, every lit segment is
    /// muted (this row *is* the baseline).
    let baseline: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning

    private let segmentCount = 7

    private var valueText: String { Copy.onboarding.q4WorkoutsPerWeekValue(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)

            HStack(spacing: Theme.Spacing.sm) {
                NumeralText(valueText, size: .large)
                Spacer(minLength: 0)
                roundButton(
                    symbol: "minus",
                    label: Copy.onboarding.q4DecrementButtonLabel,
                    isEnabled: value > range.lowerBound
                ) {
                    value -= 1
                }
                roundButton(
                    symbol: "plus",
                    label: Copy.onboarding.q4IncrementButtonLabel,
                    isEnabled: value < range.upperBound
                ) {
                    value += 1
                }
            }

            weekBar
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: value)
        // The goal row's bar also changes when the "right now" row moves (its muted/white split
        // depends on the baseline), so it animates on that too.
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: baseline)
        .sensoryFeedback(.selection, trigger: value)
        // Under VoiceOver: one adjustable element, like a system stepper (swipe up/down), and the
        // round buttons are hidden. Everywhere else (Voice Control, Switch Control, Full Keyboard
        // Access) the buttons stay reachable by their names ("Tap More workouts").
        .accessibilityElement(children: voiceOverRunning ? .ignore : .contain)
        .accessibilityLabel(label)
        .accessibilityValue(Text(valueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if value < range.upperBound { value += 1 }
            case .decrement:
                if value > range.lowerBound { value -= 1 }
            @unknown default:
                break
            }
        }
    }

    private var weekBar: some View {
        let shared = min(value, baseline ?? value)
        return HStack(spacing: Theme.Spacing.xxs) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(segmentColor(index: index, shared: shared))
                    .frame(height: Theme.Spacing.xs)
            }
        }
    }

    private func segmentColor(index: Int, shared: Int) -> Color {
        if index < shared { return Theme.Colors.muted }
        // Growth is white, not accent: a target is a plan, not an earned state (2026-09-24).
        if index < value { return Theme.Colors.interactive }
        return Theme.Colors.track
    }

    private func roundButton(symbol: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.icon(.medium, weight: .bold))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .background(Theme.Colors.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityHidden(voiceOverRunning)
    }
}

#Preview {
    Screen6Workouts(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
