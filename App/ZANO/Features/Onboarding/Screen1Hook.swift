// Screen1Hook.swift
// App / Features / Onboarding
//
// docs/spec.md §7.1 (screen 1, Hook): "Full-bleed. 'Your phone is fighting your goals. Let's flip
// that.' CTA: 'I'm ready.'" Both strings are spec-verbatim (`Copy.onboarding.hookHeadline/hookCTA`).
//
// DESIGN PASS 2 (docs/design/*, 2026-09-23; nothing here has been rendered - there is no Mac).
//
// The hero is the product's whole loop in about a second: an empty ring fills, then the padlock inside
// it opens (one-shot, never loops). That is the "flip" the headline promises, and it puts the app's ring
// language on screen before any explanation. "Earned" is the accent, so the one-accent rule holds.
//
// What changed in this pass, and why:
//   - The ring is the real `GoalRing(.hero)` now, not a private copy. It brings the ring's own hue
//     track (the empty ring is visible: the old file drew its own track because the shared ring's was
//     ~1.16:1), the arc glow, the Reduce Motion handling and its completion pulse.
//   - That pulse used to fire at the START of the fill (progress jumped 0 -> 1 instantly and only the
//     drawing animated), i.e. while nothing was visible. The fill now runs to 0.999 and closes to 1.0
//     when it lands, so the pulse, the padlock flip and the haptic all happen at the moment the ring
//     actually completes: one beat, on the payoff.
//   - The headline is `Theme.Typography.display` (Dynamic Type aware, -0.4 tracking) instead of a
//     file-local `@ScaledMetric` rounded font. Copy stays one string in `Copy.onboarding`; only the
//     styling splits it at the sentence boundary (the problem quiet, "Let's flip that." in white).
//   - The backdrop is the shared `zanoBackdrop(glow:)` plus a static halo behind the ring that
//     brightens (opacity only, never an animated blur radius) when the padlock opens.
//   - The padlock swap is gated on Reduce Motion (it was an ungated `.symbolEffect(.replace)`).
//   - Content is centered and scrolls only when it must (large Dynamic Type, small phones) instead of a
//     fixed `Spacer` stack that could clip. It sits a touch above true center (optical center).
//   - The CTA is pinned and live from frame one; the sequence never gates it (spec §8 rule 8).
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
    @State private var ringProgress: Double = 0
    @State private var isUnlocked = false
    @State private var unlockTick = 0

    /// The ring fill runs on `Theme.Motion.ringFill` (0.6s); the unlock beat waits for it.
    private static let fillMilliseconds = 600

    private var isShown: Bool { revealed || reduceMotion }

    var body: some View {
        HookCenteredScroll {
            VStack(spacing: Theme.Spacing.xl) {
                // Under Reduce Motion the hero is drawn in its final state from the first frame
                // (deriving it here, not setting state in `.task`, avoids one frame of empty ring).
                HookHero(progress: reduceMotion ? 1 : ringProgress, isUnlocked: reduceMotion || isUnlocked)
                    .opacity(isShown ? 1 : 0)
                    .scaleEffect(isShown ? 1 : 0.92)
                    .animation(reveal(delay: 0), value: revealed)

                headline
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown ? 0 : Theme.Spacing.sm)
                    .animation(reveal(delay: 0.12), value: revealed)
            }
            .padding(.horizontal, Theme.Spacing.md)
            // Bottom-heavy padding lifts the group above true center, where the eye rests.
            .padding(.bottom, Theme.Spacing.xl * 2)
        }
        .zanoAmbient(.neutral)
        .onboardingPinnedContinue(title: Copy.onboarding.hookCTA) {
            flowState.advance()
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: unlockTick)
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
    /// accent: the ring's green is the promise of the unlock, the headline is not an earned state.
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

    /// ~1.1s total, one-shot: fade in, fill the ring, then - as it lands - pulse, flip the padlock and
    /// tick the haptic. Under Reduce Motion there is no sequence and no haptic: `body` already draws
    /// the final state.
    @MainActor
    private func playIntro() async {
        revealed = true
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        // 0.999, not 1: `GoalRing` plays its completion pulse when progress crosses 1.0, and that
        // should happen when the arc lands, not when it starts drawing. The 0.36 degree gap is
        // invisible under the round cap.
        ringProgress = 0.999
        try? await Task.sleep(for: .milliseconds(Self.fillMilliseconds))
        guard !Task.isCancelled else { return }
        ringProgress = 1
        isUnlocked = true
        unlockTick += 1
    }
}

/// The hero: the real hero ring with a padlock at its center, over a static halo that brightens when
/// the lock opens. The halo only ever changes opacity (HIG Reduce Motion: no animated blur/depth).
private struct HookHero: View {
    let progress: Double
    let isUnlocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GoalRing(progress: progress, color: Theme.Colors.accent, size: .hero, center: .none)
            .overlay {
                Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(isUnlocked ? Theme.Colors.accent : Theme.Colors.text)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .background {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.Colors.accent.opacity(isUnlocked ? 0.26 : 0.12),
                                Theme.Colors.accent.opacity(0),
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 210
                        )
                    )
                    // Bigger than the ring on purpose; a `background` never affects layout.
                    .frame(width: 420, height: 420)
            }
            .animation(reduceMotion ? nil : Theme.Motion.iconSwap, value: isUnlocked)
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
