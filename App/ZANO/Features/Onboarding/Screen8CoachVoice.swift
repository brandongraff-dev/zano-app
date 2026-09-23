// Screen8CoachVoice.swift
// App / Features / Onboarding
//
// docs/spec.md §7.8 (screen 8, Q6): "Coach voice — Hype / Tough Love / Chill / Data, each with a
// sample line." §5.13 gives the exact sample line per voice, already implemented as
// `CoachVoice.displayName` / `CoachVoice.sampleLine` (`Core/Sources/Core/Copy/CoachVoice.swift`) —
// this screen reuses both directly so onboarding shows exactly what the user will actually get
// later (that file's own doc comment: "what the user previews is what they actually get").
//
// Design pass (docs/design/better-ui-findings.md ICO-03/MOT-02/MOT-03/MOT-08, better-layout 4.2/4.3,
// typography-color C5/C7): the four voices were four identical text rows. This is the brand's
// personality moment, so it is a choice of coach:
//   - each voice has its own glyph (the coach-pack vocabulary `CosmeticsShopView` already uses) in
//     Core's `IconBadge`, and its own typographic character for the sample line (Hype heavy and
//     loud, Tough Love flat and firm, Chill soft, Data monospaced), so the four read as four voices
//     before you read them. This is why the screen is not `SelectableCard`: that component sets
//     every subtitle in one caption style, which would erase exactly the difference being sold;
//   - the unselected edge is the shared `Theme.Colors.hairline` (12% white, 1.4:1 over `surface`;
//     the old value was 1.06:1 and drew nothing), selection is a 2pt accent edge over the on-hue
//     `accentWash` (not `accent` at 6%, which composites to olive), with a haptic tick on change;
//   - press feedback on touch-down (`PressableStyle`), symbol-replace on the check, and every
//     animation gated on Reduce Motion;
//   - the sample line is a Dynamic Type text style with only weight and design varying per voice
//     (it was a fixed 15pt), and the CTA sits in the shared pinned action bar on the flow's single
//     16pt margin.
//
// `CoachVoice` (`Core/Sources/Core/Models/User.swift`) is `Codable, CaseIterable, Sendable`, so
// `ForEach` keys off `\.rawValue`.

import SwiftUI
import Core

/// Screen 8 of 14 (spec §7.8). Selecting a voice sets `flowState.coachVoice`; screen 9 picks up
/// from here (and screens 10 and 12 echo the choice back).
struct Screen8CoachVoice: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q6Title, subtitle: Copy.onboarding.q6Subtitle) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(CoachVoice.allCases, id: \.rawValue) { voice in
                    voiceCard(voice)
                }
            }
        }
        .background {
            OnboardingKit.Glow(tint: Theme.Colors.accent, opacity: 0.07)
        }
        .onboardingKitActionBar {
            PrimaryButton(title: Copy.common.continueButtonLabel) {
                flowState.advance()
            }
        }
        .sensoryFeedback(.selection, trigger: flowState.coachVoice)
        .preferredColorScheme(.dark)
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "coach_voice", "screen_number": 8]
            )
        }
    }

    // MARK: - Voice card

    private func voiceCard(_ voice: CoachVoice) -> some View {
        let isSelected = flowState.coachVoice == voice
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)

        return Button {
            flowState.coachVoice = voice
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(
                    systemName: OnboardingKit.icon(for: voice),
                    tint: isSelected ? Theme.Colors.accent : Theme.Colors.text,
                    size: .medium
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(voice.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)

                    Text("\u{201C}\(voice.sampleLine)\u{201D}")
                        .font(sampleFont(for: voice))
                        .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.xs)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.muted)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.Colors.accentWash : Theme.Colors.surface, in: shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.accent : Theme.Colors.hairline,
                    lineWidth: isSelected ? 2 : Theme.Metrics.edgeWidth
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Each voice sets its sample line differently so the choice is felt, not just read. All four
    /// are Subheadline (Theme's 15pt `body` tier) and follow Dynamic Type; only weight and design
    /// change.
    private func sampleFont(for voice: CoachVoice) -> Font {
        switch voice {
        case .hype: .system(.subheadline, design: .rounded, weight: .heavy)
        case .toughLove: .system(.subheadline, design: .default, weight: .semibold)
        case .chill: .system(.subheadline, design: .rounded, weight: .regular)
        case .data: .system(.subheadline, design: .monospaced, weight: .medium)
        }
    }
}

#Preview {
    Screen8CoachVoice(flowState: OnboardingFlowState())
}
