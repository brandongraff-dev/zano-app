// Screen8CoachVoice.swift
// App / Features / Onboarding
//
// Owned by this session. docs/spec.md §7.8 (screen 8, Q6): "Coach voice — Hype / Tough Love /
// Chill / Data, each with a sample line." §5.13 gives the exact sample line per voice, already
// implemented as `CoachVoice.displayName` / `CoachVoice.sampleLine`
// (`Core/Sources/Core/Copy/CoachVoice.swift`) — this screen reuses both directly rather than
// re-authoring them, so onboarding shows exactly what the user will actually get later (that
// file's own doc comment: "what the user previews is what they actually get").
//
// ASSUMED API — see Screen3MainGoal.swift's header for the full note. New keys beyond that file's
// list: none — `q6Title`/`q6Subtitle` are already listed there.
//
// `CoachVoice` (`Core/Sources/Core/Models/User.swift`) is `Codable, CaseIterable, Sendable` but
// does not declare `Hashable`, so `ForEach` below keys off `\.rawValue` (a `String`, always
// Hashable) rather than `\.self`.

import SwiftUI
import Core

/// Screen 8 of 14 (spec §7.8) — the last screen owned by this session. Selecting a voice sets
/// `flowState.coachVoice`; screen 9 (onboarding-2) picks up from here.
struct Screen8CoachVoice: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        OnboardingQuestion(title: Copy.onboarding.q6Title, subtitle: Copy.onboarding.q6Subtitle) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(CoachVoice.allCases, id: \.rawValue) { voice in
                    voiceRow(voice)
                }
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
                properties: ["screen": "coach_voice", "screen_number": 8]
            )
        }
    }

    private func voiceRow(_ voice: CoachVoice) -> some View {
        let isSelected = flowState.coachVoice == voice
        return Button {
            flowState.coachVoice = voice
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack {
                    Text(voice.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                Text("\u{201C}\(voice.sampleLine)\u{201D}")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .italic()
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
    Screen8CoachVoice(flowState: OnboardingFlowState())
}
