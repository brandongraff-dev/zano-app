// Screen1Hook.swift
// App / Features / Onboarding
//
// Owned by this session (Onboarding screens 1-8; see OnboardingFlowState.swift's header for the
// full 14-screen map and this file list's ownership rules). docs/spec.md §7.1 (screen 1, Hook):
// "Full-bleed. 'Your phone is fighting your goals. Let's flip that.' CTA: 'I'm ready.'"
//
// ASSUMED API — full combined note lives in Screen3MainGoal.swift's header (the first "Q" screen
// in this session, where the list of every `Copy.onboarding.*`/`Copy.common.*` key and the
// `OnboardingQuestion`/`PrimaryButton` assumed shapes are written out in full — this session's
// files do not include Core/Sources/Core/Copy or Core/Sources/Core/UI's component catalog, spec
// §15's other build targets). This screen only needs two keys, and both are spec-verbatim (§7.1,
// not authored copy):
//   Copy.onboarding.hookHeadline = "Your phone is fighting your goals. Let's flip that."
//   Copy.onboarding.hookCTA      = "I'm ready."
// and `PrimaryButton(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void)`.

import SwiftUI
import Core

/// Screen 1 of 14 (spec §7.1). Full-bleed hero: headline + single CTA that advances the flow.
/// No FamilyControls/HealthKit/etc. here — this screen only ever mutates `flowState.currentScreen`
/// (via `advance()`).
struct Screen1Hook: View {
    @Bindable var flowState: OnboardingFlowState

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "lock.iphone")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)

                Text(Copy.onboarding.hookHeadline)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
                Spacer()

                PrimaryButton(title: Copy.onboarding.hookCTA) {
                    flowState.advance()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    Screen1Hook(flowState: OnboardingFlowState())
}
