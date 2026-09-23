// Screen2SocialProof.swift
// App / Features / Onboarding
//
// Owned by this session. docs/spec.md §7.2 (screen 2, Social proof strip): "3 rotating quotes
// (real ones once you have them; placeholder copy marked clearly until then)."
//
// ASSUMED API — see Screen3MainGoal.swift's header for the full note. This screen needs
// `Copy.onboarding.socialProofQuotes: [String]` (exactly 3 entries expected, placeholder copy
// today per spec §7.2 — whoever builds Core/Sources/Core/Copy should mark them clearly as
// placeholder, e.g. a `// TODO: replace with real testimonials` above the array literal, so
// nobody ships them believing they're real quotes) and `Copy.common.continueButtonLabel`.

import SwiftUI
import Core

/// Screen 2 of 14 (spec §7.2). Auto-rotating quote carousel with a manual Continue CTA (the
/// rotation is decorative pacing, not a gate — the user can always tap through immediately).
struct Screen2SocialProof: View {
    @Bindable var flowState: OnboardingFlowState

    @State private var activeIndex = 0

    private var quotes: [String] { Copy.onboarding.socialProofQuotes }
    private let rotationInterval: Duration = .seconds(3.5)

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                TabView(selection: $activeIndex) {
                    ForEach(Array(quotes.enumerated()), id: \.offset) { index, quote in
                        Text(quote)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 140)

                dots

                Spacer()
                Spacer()

                PrimaryButton(title: Copy.common.continueButtonLabel) {
                    flowState.advance()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .preferredColorScheme(.dark)
        .task { await runRotation() }
        .onAppear {
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "social_proof", "screen_number": 2]
            )
        }
    }

    private var dots: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(quotes.indices, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? Theme.Colors.accent : Theme.Colors.surface2)
                    .frame(width: 6, height: 6)
                    .animation(Theme.Motion.springStandard, value: activeIndex)
            }
        }
    }

    /// Auto-advances the carousel while this screen is on screen. `.task` cancels this
    /// automatically the moment the view disappears (e.g. the user taps Continue and the
    /// coordinator swaps to screen 3), so there's no timer to invalidate manually.
    private func runRotation() async {
        guard quotes.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: rotationInterval)
            guard !Task.isCancelled else { return }
            activeIndex = (activeIndex + 1) % quotes.count
        }
    }
}

#Preview {
    Screen2SocialProof(flowState: OnboardingFlowState())
}
