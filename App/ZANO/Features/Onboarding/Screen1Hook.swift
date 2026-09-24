// Screen1Hook.swift
// App / Features / Onboarding
//
// docs/spec.md §7.1 (screen 1, Hook): "Full-bleed. 'Your phone is fighting your goals. Let's flip
// that.' CTA: 'I'm ready.'" Both strings are spec-verbatim (`Copy.onboarding.hookHeadline/hookCTA`).
//
// LIVELINESS PASS (2026-09-24; the founder: onboarding "feels dull and lifeless"). Nothing here has
// been rendered - there is no Mac.
//
// The hero is now the brand's signature object, `ZanoLivingMark`: the silver swoosh star, big (150pt),
// charging from empty to ~85% over ~1.2s as the screen opens, then idling (float, turn, light sweep,
// breathing blue glow - all inside the component, all Reduce Motion aware). That is the product line
// ("the star charges while you're off your phone") shown before it is said, and it is the same star
// the header then carries through the next 12 screens. A blue bloom behind it brightens with the
// charge (opacity only), and one soft haptic lands as the charge settles.
//
// Layout: the wordmark sits above the star, the spec-verbatim headline below (split at the sentence
// boundary: the problem quiet in `textSecondary`, "Let's flip that." in `text`). Centered, scrolling
// only when it must. The CTA is pinned and live from frame one; the intro never gates it (spec §8
// rule 8). The old ring-and-padlock hero is gone: two hero objects on the first screen split the eye.
//
// Handoff (not editable here): spec §7.1 calls this screen full-bleed and `OnboardingContainerView`
// already hides its header on screen 1. The straight apostrophes in the stored headline
// ("Let's") belong to the Copy owner (typography audit T9).

import SwiftUI
import Core

/// Screen 1 of 14 (spec §7.1). Full-bleed hero: headline + single CTA that advances the flow.
/// No FamilyControls/HealthKit/etc. here - this screen only ever mutates `flowState.currentScreen`
/// (via `advance()`).
struct Screen1Hook: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false
    @State private var charge: Double = 0
    @State private var chargedTick = 0

    /// Where the intro leaves the star: nearly full, so there is still something left to earn.
    private static let introCharge = 0.85
    /// `ZanoLivingMark` eases a charge change over 1.2s; the haptic lands as it settles.
    private static let chargeMilliseconds = 1200
    private static let starHeight: CGFloat = 150

    private var isShown: Bool { revealed || reduceMotion }

    /// Under Reduce Motion the star is drawn charged from the first frame (derived here, not set in
    /// `.task`, so there is no frame of an empty star).
    private var shownCharge: Double { reduceMotion ? Self.introCharge : charge }

    var body: some View {
        HookCenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                // The brand's first appearance: the wordmark, then the star it names.
                ZanoWordmark(height: 15)
                    .opacity(isShown ? 1 : 0)
                    .animation(reveal(delay: 0), value: revealed)

                HookStar(charge: shownCharge, height: Self.starHeight)
                    .opacity(isShown ? 1 : 0)
                    .scaleEffect(isShown ? 1 : 0.9)
                    .animation(reduceMotion ? nil : Theme.Motion.springCelebration.delay(0.05), value: revealed)
                    .padding(.vertical, Theme.Spacing.md)

                headline
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown ? 0 : Theme.Spacing.sm)
                    .animation(reveal(delay: 0.35), value: revealed)
            }
            .padding(.horizontal, Theme.Spacing.md)
            // Bottom-heavy padding lifts the group above true center, where the eye rests.
            .padding(.bottom, Theme.Spacing.xl * 2)
        }
        .onboardingPinnedContinue(title: Copy.onboarding.hookCTA) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: chargedTick)
        .task { await playIntro() }
        .onAppear {
            // docs/spec.md §23 "Instrument from day one: every screen view..."
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "hook", "screen_number": 1]
            )
        }
    }

    // MARK: - Pieces

    /// Two beats, same size: the problem quiet (`textSecondary`), the flip loud (`text`). White, not
    /// accent: the star's blue light is the promise, the headline is not an earned state.
    /// Stacked so the second sentence always starts its own line instead of dangling after a wrap.
    private var headline: some View {
        let parts = Self.headlineParts(from: Copy.onboarding.hookHeadline)
        return VStack(spacing: Theme.Spacing.xxs) {
            Text(parts.lead)
                .foregroundStyle(parts.flip == nil ? Theme.Colors.text : Theme.Colors.textSecondary)
            if let flip = parts.flip {
                Text(flip)
                    .foregroundStyle(Theme.Colors.text)
            }
        }
        .zanoText(.display)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Splits "Sentence one. Sentence two." at the first ". " so the second sentence can take the
    /// emphasis. Falls back to one un-split line if the copy ever loses that shape.
    private static func headlineParts(from full: String) -> (lead: String, flip: String?) {
        guard let cut = full.range(of: ". ") else { return (full, nil) }
        let lead = String(full[..<cut.lowerBound]) + "."
        let flip = String(full[cut.upperBound...])
        return (lead, flip.isEmpty ? nil : flip)
    }

    private func reveal(delay: Double) -> Animation? {
        reduceMotion ? nil : Animation.easeOut(duration: 0.5).delay(delay)
    }

    // MARK: - Intro sequence

    /// One-shot: fade the star in, then charge it to `introCharge` (the star eases the fill itself,
    /// ~1.2s), and tick one soft haptic as it settles. Under Reduce Motion there is no sequence and no
    /// haptic: `body` already draws the charged star.
    @MainActor
    private func playIntro() async {
        revealed = true
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        charge = Self.introCharge
        try? await Task.sleep(for: .milliseconds(Self.chargeMilliseconds))
        guard !Task.isCancelled else { return }
        chargedTick += 1
    }
}

/// The hero: the living star over a blue bloom that brightens with its charge. The bloom only ever
/// changes opacity (never an animated blur or radius). Decorative; the headline carries the meaning.
private struct HookStar: View {
    let charge: Double
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZanoLivingMark(charge: charge, height: height)
            .background {
                // Bigger than the star on purpose; a `background` never affects layout.
                OnboardingKit.StarBloom(diameter: height * 3)
                    .opacity(0.2 + 0.8 * charge)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: charge)
            }
            .accessibilityHidden(true)
    }
}

/// Centers `content` in the available height when it fits and scrolls when it does not (large Dynamic
/// Type on a small phone), instead of a fixed `Spacer` stack that clips.
private struct HookCenteredScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

#Preview {
    Screen1Hook(flowState: OnboardingFlowState())
        .preferredColorScheme(.dark)
}
