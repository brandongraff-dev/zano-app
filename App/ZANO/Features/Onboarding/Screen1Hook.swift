// Screen1Hook.swift
// App / Features / Onboarding
//
// docs/spec.md §7.1 (screen 1, Hook): "Full-bleed. 'Your phone is fighting your goals. Let's flip
// that.' CTA: 'I'm ready.'" Both strings are spec-verbatim (`Copy.onboarding.hookHeadline/hookCTA`).
//
// LIVELINESS PASS (2026-09-24; the founder: onboarding "feels dull and lifeless"). Nothing here has
// been rendered - there is no Mac.
//
// The hero is now the brand's signature object, `ZanoLivingMark`: the silver swoosh star, big (120pt since the short flow),
// charging from empty to ~85% over ~1.2s as the screen opens, then idling (float, turn, light sweep,
// breathing blue glow - all inside the component, all Reduce Motion aware). That is the product line
// ("the star charges while you're off your phone") shown before it is said, and it is the same star
// the header then carries through the rest of the flow. A blue bloom behind it brightens with the
// charge (opacity only), and one soft haptic lands as the charge settles.
//
// Layout: the wordmark sits above the star, the spec-verbatim headline below (split at the sentence
// boundary: the problem quiet in `textSecondary`, "Let's flip that." in `text`). Centered, scrolling
// only when it must. The CTA is pinned and live from frame one; the intro never gates it (spec §8
// rule 8). The old ring-and-padlock hero is gone: two hero objects on the first screen split the eye.
//
// SHORT FLOW (2026-10-02): the social-proof screen is gone and its three product claims sit here,
// under the headline, as a quiet "How it works" strip (`Copy.onboarding.socialProofQuotes`, same
// entries, same rule: claims, never invented testimonials). They fade in after the headline and
// never gate the CTA. Step 1 of 8.
//
// Handoff (not editable here): spec §7.1 calls this screen full-bleed and `OnboardingContainerView`
// already hides its header on screen 1. The straight apostrophes in the stored headline
// ("Let's") belong to the Copy owner (typography audit T9).

// BUDDIES (2026-10-03): the hero is the user's buddy (Stash, the default and the app icon, until
// the next step lets them pick), over the same bloom. It no longer charges; the bloom still
// brightens on the intro and the haptic still lands as it settles.

// VISUAL PASS 2 (2026-10-03, "make it more playful"): the three-sentence "How it works" card is now
// the game loop as three stickers, Lock it -> Earn it -> Get it back, each a colour sticker with
// two to five words under it (`Copy.onboarding.hookLoop`). They pop in one after another as the
// star finishes charging: the screen's one orchestrated moment. The offline / location claims
// moved out of the first screen (they read as a spec sheet); the plan step and Today carry them.

// CHARACTER PASS (session 30, 2026-10-06, "fun, with super good animations"): the buddy runs in
// from the left with two crewmates hopping in beside it (a tease of the next step's picker), and
// then acts out the loop as each sticker lands: guarding (Lock it), lifting (Earn it), ecstatic (Get
// it back), settling happy. The stickers now land one at a time (~0.45s apart) so each beat has
// its face. Still one orchestrated moment; the CTA is live from frame one. Reduce Motion: everyone
// is in place, the loop is shown, the hero is happy.

import SwiftUI
import Core

/// Step 1 of 8 (spec §7.1, plus §7.2's proof strip). Full-bleed hero: headline + single CTA that advances the flow.
/// No FamilyControls/HealthKit/etc. here - this screen only ever mutates `flowState.currentScreen`
/// (via `advance()`).
struct Screen1Hook: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false
    @State private var charge: Double = 0
    @State private var chargedTick = 0
    /// How many loop stickers have landed (0...3). Reduce Motion: all of them from the start.
    @State private var litBeats = 0
    /// The hero runs in from off-screen left; the crew hops in after it lands.
    @State private var heroArrived = false
    @State private var crewArrived = false
    @State private var heroPose: BuddyPose = .idle

    /// Where the intro leaves the star: nearly full, so there is still something left to earn.
    private static let introCharge = 0.85
    /// The loop row is shorter than the old proof card, so the hero can be big. 128 = 4x the
    /// buddy's 32px grid (crisp pixels).
    private static let starHeight: CGFloat = 128

    private var isShown: Bool { revealed || reduceMotion }
    private var shownBeats: Int { reduceMotion ? 3 : litBeats }
    /// The face for each landed beat: Lock it, Earn it, Get it back.
    private static let beatPoses: [BuddyPose] = [.guarding, .lifting, .ecstatic]
    private static let beatMilliseconds = 450

    /// Under Reduce Motion the star is drawn charged from the first frame (derived here, not set in
    /// `.task`, so there is no frame of an empty star).
    private var shownCharge: Double { reduceMotion ? Self.introCharge : charge }

    var body: some View {
        HookCenteredScroll {
            VStack(spacing: Theme.Spacing.lg) {
                // The brand's first appearance: the wordmark, then the star it names.
                ZanoWordmark(height: 22)
                    .opacity(isShown ? 1 : 0)
                    .animation(reveal(delay: 0), value: revealed)

                HookStar(
                    charge: shownCharge,
                    height: Self.starHeight,
                    pose: reduceMotion ? .happy : heroPose,
                    heroArrived: heroArrived || reduceMotion,
                    crewArrived: crewArrived || reduceMotion
                )
                .opacity(isShown ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
                .padding(.vertical, Theme.Spacing.md)

                headline
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown ? 0 : Theme.Spacing.sm)
                    .animation(reveal(delay: 0.35), value: revealed)

                HookLoopRow(litBeats: shownBeats)
            }
            .padding(.horizontal, Theme.Spacing.md)
            // Bottom padding keeps the strip clear of the pinned CTA.
            .padding(.bottom, Theme.Spacing.xl)
        }
        .onboardingPinnedContinue(title: Copy.onboarding.hookCTA) {
            flowState.advance()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: chargedTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: litBeats)
        .task { await playIntro() }
        .onAppear {
            // docs/spec.md §23 "Instrument from day one: every screen view..."
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: OnboardingStep.hook.viewedProperties
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

    /// One-shot: the hero runs in and lands (one soft haptic), the crew hops in beside it, then the
    /// three loop stickers land one at a time while the hero acts each one out, and it settles happy.
    /// Under Reduce Motion there is no sequence and no haptic: `body` already draws the end state.
    @MainActor
    private func playIntro() async {
        revealed = true
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        heroArrived = true
        charge = Self.introCharge
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        chargedTick += 1
        crewArrived = true
        try? await Task.sleep(for: .milliseconds(500))
        for beat in 0..<Self.beatPoses.count {
            guard !Task.isCancelled else { return }
            litBeats = beat + 1
            heroPose = Self.beatPoses[beat]
            try? await Task.sleep(for: .milliseconds(Self.beatMilliseconds))
        }
        try? await Task.sleep(for: .milliseconds(Self.beatMilliseconds))
        guard !Task.isCancelled else { return }
        heroPose = .happy
    }
}

/// Lock it -> Earn it -> Get it back: three stickers in a row, joined by little arrows. The first
/// `litBeats` are shown; each pops in (and its arrow with it) as the count reaches it. One VoiceOver
/// element for the whole loop.
private struct HookLoopRow: View {
    let litBeats: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Matched to `Copy.onboarding.hookLoop` by position: locked, earned (goal volt), unlocked.
    private static let symbols = ["lock.fill", "dumbbell.fill", "lock.open.fill"]
    private static let tints = [Theme.Colors.Aurora.violet, Theme.Colors.Ring.workout, Theme.Colors.accent]
    /// Stickers lean a little, alternately, like they were slapped on.
    private static let tilts: [Double] = [-6, 4, -3]

    var body: some View {
        let beats = Copy.onboarding.hookLoop
        HStack(alignment: .top, spacing: Theme.Spacing.xxs) {
            ForEach(Array(beats.enumerated()), id: \.offset) { index, beat in
                if index > 0 {
                    Image(systemName: "chevron.forward")
                        .font(Theme.Typography.icon(.xsmall, weight: .heavy))
                        .foregroundStyle(Theme.Colors.muted)
                        .padding(.top, 20)
                        .opacity(index < litBeats ? 1 : 0)
                        .animation(pop, value: litBeats)
                }
                beatView(beat, index: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.onboarding.hookLoopSpoken)
    }

    private func beatView(_ beat: Copy.onboarding.LoopBeat, index: Int) -> some View {
        let i = index % Self.symbols.count
        let isShown = index < litBeats
        return VStack(spacing: Theme.Spacing.xs) {
            OnboardingSticker(systemImage: Self.symbols[i], tint: Self.tints[i], size: 52, bounceTrigger: isShown ? 1 : 0, tilt: Self.tilts[i])
            Text(beat.title)
                .font(Theme.Typography.headline.weight(.heavy))
                .foregroundStyle(Theme.Colors.text)
            Text(beat.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown || reduceMotion ? 1 : 0.6)
        .offset(y: isShown || reduceMotion ? 0 : -Theme.Spacing.md)
        .animation(pop, value: isShown)
    }

    private var pop: Animation? {
        reduceMotion ? nil : Theme.Motion.springPop
    }
}

/// The hero: the user's buddy (the living star until 2026-10-03) over a blue bloom that brightens
/// with the intro's charge, flanked by two crewmates (session 30). The hero runs in from the left
/// with little hops; the crew pops up from below once it lands, waving. The bloom only ever changes
/// opacity (never an animated blur or radius). Decorative; the headline carries the meaning.
private struct HookStar: View {
    let charge: Double
    let height: CGFloat
    let pose: BuddyPose
    let heroArrived: Bool
    let crewArrived: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    /// A crewmate is half the hero (still a multiple of 16pt).
    private var crewSize: CGFloat { height / 2 }

    /// One cozy and one hype buddy that aren't the hero, so the row shows the range on offer.
    private var crew: [Buddy] {
        let others = Buddy.allCases.filter { $0 != buddy }
        let cozy = others.first { $0.crew == .cozy } ?? .zib
        let hype = others.first { $0.crew == .hype } ?? .brick
        return [cozy, hype]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: -Theme.Spacing.sm) {
            crewmate(crew[0], delay: 0)
            hero
                .zIndex(1)
            crewmate(crew[1], delay: 0.12)
        }
        .accessibilityHidden(true)
    }

    private var hero: some View {
        // Half-height hops: a full 128pt leap reached the wordmark above (CI clip, 2026-10-06).
        OnboardingBuddyActor(pose: pose, size: height, burstColor: buddy.color, hopScale: 0.5)
            .background {
                // Bigger than the star on purpose; a `background` never affects layout.
                OnboardingKit.StarBloom(diameter: height * 3)
                    .opacity(0.2 + 0.8 * charge)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: charge)
            }
            .modifier(HookRunIn(arrived: heroArrived, distance: height * 3))
    }

    private func crewmate(_ crewBuddy: Buddy, delay: Double) -> some View {
        OnboardingBuddyActor(pose: crewArrived ? .excited : .idle, size: crewSize, buddy: crewBuddy)
            .opacity(crewArrived ? 0.9 : 0)
            .offset(y: crewArrived ? 0 : crewSize * 0.6)
            .scaleEffect(crewArrived ? 1 : 0.5, anchor: .bottom)
            .animation(reduceMotion ? nil : Theme.Motion.springPop.delay(delay), value: crewArrived)
    }
}

/// Runs the hero in from `distance` points to the left: a springy slide with three quick hops on
/// the way, and a little lean into the run that straightens as it lands. Reduce Motion: in place.
private struct HookRunIn: ViewModifier {
    let arrived: Bool
    let distance: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            let hop = Double(distance / 18)
            content
                .rotationEffect(.degrees(arrived ? 0 : 10), anchor: .bottom)
                .offset(x: arrived ? 0 : -distance)
                .animation(.spring(response: 0.6, dampingFraction: 0.78), value: arrived)
                .keyframeAnimator(initialValue: 0.0, trigger: arrived) { view, lift in
                    view.offset(y: -lift)
                } keyframes: { _ in
                    CubicKeyframe(hop, duration: 0.1)
                    CubicKeyframe(0, duration: 0.1)
                    CubicKeyframe(hop, duration: 0.1)
                    CubicKeyframe(0, duration: 0.1)
                    CubicKeyframe(hop * 0.6, duration: 0.09)
                    SpringKeyframe(0, duration: 0.25, spring: .bouncy)
                }
        }
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
