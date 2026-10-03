// OnboardingContainerView.swift
// App / Features / Onboarding
//
// docs/spec.md §7 (Onboarding Flow, screen by screen); §17 Session 6 (`feat/onboarding`). This file
// is the single root that wires every step into one sequential flow, plus the shared chrome and the
// small design toolkit (`OnboardingKit`, below) the steps build on.
//
// SHORT FLOW (founder decision 2026-10-02): 7 steps, down from 15, so a new user reaches a real
// earned win in about 3 minutes. Hook -> main goal -> your why -> apps -> plan + hold to commit ->
// paywall -> first win. Buddies (2026-10-03, approved): a "Pick your buddy" step after the hook
// (`BuddyPickerView`, Features/Buddy) makes it 8. See `OnboardingFlowState.swift` for the old-to-new map; the optional setup
// topics live on Today's Finish setup card.
//
// `OnboardingFlowState` (`OnboardingFlowState.swift`, read here, never edited) is the shared state:
// `currentScreen` (1...8), the answers, `advance()`/`goBack()`, `progressFraction`,
// `recordCommitment(at:)`. Every screen takes `@Bindable var flowState: OnboardingFlowState` and
// advances itself via `flowState.advance()`; this container never drives navigation from the
// outside beyond the back button.
//
// Design pass (docs/design/*, 2026-09-23 — better-ui, better-layout, typography-color,
// composition-audit, competitive-research, 2026-ios-trends), applied to this file:
//   - One header row instead of two: [back 44pt][progress bar]. Saves ~48pt per screen
//     (better-layout 7.6) and the back target is 44pt (better-ui HIT-01).
//   - The header is hidden on screen 1 (the full-bleed hook, spec §7.1) and on the last screen (the live
//     first-win lock: a Back there used to return to the paywall mid-session — better-layout 7.6).
//     The "Step N of 8" accessibility element is NOT hidden with it: on those two screens it is
//     kept as a 1pt invisible marker, so VoiceOver still announces where the user is and the UI-test
//     harness (`ZANOUITests`, which detects onboarding and waits on steps 1 and 7 through that
//     label) keeps working.
//   - The progress track is the shared `Theme.Colors.track` (it was a `surface2` fill at 1.16:1,
//     invisible) and its fill carries the static accent glow that spec §16 asks of active elements.
//   - Screen exit is softer than entry (opacity plus a small drift instead of a second full-width
//     slide), and a plain cross-fade under Reduce Motion (better-ui MOT-07/MOT-08).
//   - `OnboardingKit` is now a thin layer over the Wave A Core/UI system (`Theme.Colors.hairline`/
//     `track`, `zanoText`, `zanoCard`, `zanoActionBar`, `IconBadge`, `PressableStyle`, `HeroGlow`
//     tokens) instead of a private copy of it: the two `text`-opacity tones, the card recipe, the
//     action bar and the press style it used to define are gone. What is left is only what Core
//     does not have — a glow with an anchor, a 96pt display numeral, a centered-or-scroll layout
//     and the coach-voice glyph map.
//
// Liveliness pass (2026-09-24, founder: "onboarding feels dull and lifeless"): the header carries a
// small `ZanoLivingMark` that charges with progress (charge = step / 7), the product line ("the star
// charges while you're off your phone") played out while the user answers. The scaffold paints one
// continuous ambient (`OnboardingKit.Ambient`): deep navy from above that warms toward ZANO Blue as
// the steps advance, so screens no longer paint their own flat `zanoAmbient(.neutral)`. The progress
// fill is blue with a soft glow, and advancing a step ticks a soft haptic. The "Step N of 8"
// element is unchanged (the star is hidden from VoiceOver so it adds no second element).
//
// Visual pass 2 (2026-10-03, founder: "make it more playful"): the flow plays like a game's
// character select. The header is a charge meter (one power cell per step, ending in the buddy since 2026-10-03), the
// backdrop is the shared aurora, and the star is a guide character with a speech bubble on the
// question steps (`OnboardingPlayKit.swift`). Flow, steps, analytics and plan saving are unchanged.
//
// Order note (decision 2026-09-23, kept): the hard paywall sits directly after the commitment (the
// plan step's hold), so nothing sits between the peak and the payment ask, and the first win comes
// after it. File names keep their older numbers.

import SwiftUI
import SwiftData
import Core

/// Root of the 8-step onboarding flow (docs/spec.md §7). Owns the one shared
/// `OnboardingFlowState` for the whole flow and renders whichever screen
/// `flowState.currentScreen` names, wrapped in `OnboardingScaffold`'s chrome.
///
/// Expected to be hosted by whatever decides onboarding should show at all (e.g. `ContentView`,
/// or a future "has this device finished onboarding?" gate) — that decision, and what happens
/// after `onFinished` fires, belong to that caller, not this file.
@MainActor
struct OnboardingContainerView: View {
    /// Called once, after the first-win screen's widget-add prompt is dismissed. Defaults to a no-op so this
    /// view compiles and behaves standalone (e.g. in `#Preview`).
    var onFinished: () -> Void = {}

    @State private var flowState: OnboardingFlowState

    /// `initialScreen` exists so the CI screenshot gallery (`ScreenshotGallery.swift`) can photograph
    /// any of the 8 steps directly; every real caller leaves it at the first screen.
    init(onFinished: @escaping () -> Void = {}, initialScreen: Int = OnboardingFlowState.firstScreen) {
        self.onFinished = onFinished
        let state = OnboardingFlowState()
        state.currentScreen = min(max(initialScreen, OnboardingFlowState.firstScreen), OnboardingFlowState.lastScreen)
        _flowState = State(initialValue: state)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScaffold(flowState: flowState) {
            screen(for: flowState.currentStep)
                .id(flowState.currentScreen)
                .transition(screenTransition)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springStandard,
            value: flowState.currentScreen
        )
    }

    @ViewBuilder
    private func screen(for step: OnboardingStep) -> some View {
        switch step {
        case .hook: Screen1Hook(flowState: flowState)
        case .buddy: buddyStep
        case .mainGoal: Screen3MainGoal(flowState: flowState)
        case .yourWhy: ScreenYourWhy(flowState: flowState)
        case .appSelection: Screen4AppSelection(flowState: flowState)
        case .plan: Screen10PlanReveal(flowState: flowState)
        case .paywall: PaywallView(flowState: flowState)
        case .firstWin: Screen14FirstWin(flowState: flowState, onFinished: onFinished)
        }
    }

    /// Step 2 (Buddies, 2026-10-03): the shared picker; its "Team up" button advances.
    private var buddyStep: some View {
        BuddyPickerView(context: .onboarding) { flowState.advance() }
            .onAppear {
                Analytics.shared.capture(
                    event: "onboarding_screen_viewed",
                    properties: OnboardingStep.buddy.viewedProperties
                )
            }
    }

    /// Enter from the trailing edge; leave softly (fade plus a small drift) so the outgoing screen
    /// doesn't slide a second full width across the incoming one. Reduce Motion: cross-fade only.
    private var screenTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity.combined(with: .offset(x: -Theme.Spacing.sm))
        )
    }
}

// MARK: - Shared chrome

/// Consistent back button + progress bar wrapped around steps 2-6, per docs/spec.md §7's
/// framing ("under 3 minutes") — a visible progress bar is what makes the flow feel short.
/// `internal` (not `private`) so the per-screen `#Preview`s can wrap themselves in the same chrome.
@MainActor
struct OnboardingScaffold<Content: View>: View {
    @Bindable var flowState: OnboardingFlowState
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Screen 1 is the full-bleed hook and the last screen is the live first-win lock; both own the whole
    /// screen (better-layout 7.6).
    private var showsChrome: Bool {
        flowState.currentScreen != OnboardingFlowState.firstScreen
            && flowState.currentScreen != OnboardingFlowState.lastScreen
    }

    private var progressLabel: String {
        Copy.onboarding.progressAccessibilityLabel(
            screen: flowState.currentScreen,
            total: OnboardingFlowState.lastScreen
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsChrome {
                header
                    .transition(.opacity)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            if !showsChrome {
                // The header is gone; its "Step N of 8" element is not. 1pt, invisible, no layout.
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(progressLabel)
            }
        }
        // Visual pass 2: the flow sits in the shared aurora room (drifting arcade light, paused
        // off-screen, still under Reduce Motion), warming as the charge builds.
        .background {
            ZanoAuroraBackground(state: .progress(flowState.progressFraction))
                .ignoresSafeArea()
        }
        // A soft tick each time the star takes on charge (forward only; Back is silent).
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: flowState.currentScreen) { oldValue, newValue in
            newValue > oldValue
        }
    }

    /// [back 44pt][charge meter: one power cell per step, ending in the buddy]. Visual pass 2 (2026-10-03):
    /// the thin progress line became the charge meter (`OnboardingPlayKit.swift`), which carries
    /// the same "Step N of 8" accessibility element the UI tests wait on.
    private var header: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Button {
                flowState.goBack()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(Theme.Typography.icon(.medium, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .accessibilityLabel(Copy.onboarding.backButtonAccessibilityLabel)

            OnboardingChargeMeter(
                step: flowState.currentScreen,
                total: OnboardingFlowState.lastScreen,
                accessibilityText: progressLabel
            )
            .padding(.trailing, Theme.Spacing.md)
        }
        .frame(height: Theme.Metrics.minTapTarget)
    }
}

// MARK: - OnboardingKit (shared by the steps)

/// The small design toolkit the steps share: only what `Core/UI` does not already provide. A
/// caseless enum used purely as a namespace so the names can't collide with anything a neighbouring
/// screen defines. Everything here is built from `Theme` tokens and Core components.
enum OnboardingKit {
    static let progressBarHeight: CGFloat = 6
    /// The header star: small enough to sit in the 44pt row, big enough to read as the mark.
    static let headerStarHeight: CGFloat = 24

    // MARK: Ambient

    /// The whole-flow backdrop: near-black, a pool of deep navy (`lockedAmbient`) falling from above,
    /// and ZANO Blue light that grows in as `progress` (0...1) advances, from the top-right corner
    /// and, late in the flow, rising from the floor. Only layer opacities change, eased once per
    /// step; nothing loops, so it is the same under Reduce Motion (just a shorter fade).
    /// Pass 3 (restraint): every layer at roughly half its pass-2 strength, so the room reads as ink.
    struct Ambient: View {
        let progress: Double

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var p: Double { min(1, max(0, progress)) }

        var body: some View {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack {
                    Theme.Colors.background
                    RadialGradient(
                        colors: [Theme.Colors.lockedAmbient, Theme.Colors.lockedAmbient.opacity(0)],
                        center: UnitPoint(x: 0.35, y: -0.08),
                        startRadius: 0,
                        endRadius: width * 1.3
                    )
                    .opacity(0.25 + 0.15 * p)
                    RadialGradient(
                        colors: [Theme.Colors.accent.opacity(0.11), Theme.Colors.accent.opacity(0)],
                        center: UnitPoint(x: 0.95, y: 0.0),
                        startRadius: 0,
                        endRadius: width * 1.05
                    )
                    .opacity(0.15 + 0.85 * p)
                    RadialGradient(
                        colors: [Theme.Colors.accent.opacity(0.06), Theme.Colors.accent.opacity(0)],
                        center: .bottom,
                        startRadius: 0,
                        endRadius: width * 0.95
                    )
                    .opacity(p * p)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.9), value: p)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A soft blue bloom behind a hero star: the star's light spilling onto the page. Static
    /// gradient; callers change only its opacity.
    struct StarBloom: View {
        var diameter: CGFloat = 360

        var body: some View {
            RadialGradient(
                colors: [
                    Theme.Colors.accent.opacity(0.32),
                    Theme.Colors.accent.opacity(0.10),
                    Theme.Colors.accent.opacity(0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The glyph for each coach voice, shared by the plan ticket's footer and the Finish setup
    /// coach-voice sheet (same vocabulary `CosmeticsShopView` already uses for coach packs).
    static func icon(for voice: CoachVoice) -> String {
        switch voice {
        case .hype: "megaphone.fill"
        case .toughLove: "flame.fill"
        case .chill: "leaf.fill"
        case .data: "chart.bar.fill"
        }
    }

    // MARK: Glow

    /// A static radial wash behind a "moment" screen — the flat `#0A0A0B` rectangles the audits
    /// called out. This is `HeroGlow` with an anchor (`HeroGlow` only washes down from the top;
    /// the wake-up reclaim wants one rising from the bottom and the commitment ring one behind its
    /// centre). Static on purpose (never animate blur or glow radius: Reduce Motion guidance).
    /// `tint` is a semantic color (accent = earned only, danger = loss, white = a neutral moment such
    /// as the commitment ring), never decoration.
    struct Glow: View {
        var tint: Color = Theme.Colors.accent
        var opacity: Double = 0.12
        var anchor: UnitPoint = .top

        var body: some View {
            RadialGradient(
                colors: [tint.opacity(opacity), tint.opacity(opacity * 0.4), tint.opacity(0)],
                center: anchor,
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Type

    /// Small sentence-case label (`Theme.Typography.Style.eyebrow`; no caps or tracking since the
    /// 2026-09-24 premium pass).
    struct Eyebrow: View {
        let text: String
        var color: Color = Theme.Colors.muted

        var body: some View {
            Text(text)
                .zanoText(.eyebrow)
                .foregroundStyle(color)
        }
    }

    /// The hero headline tier (`Theme.Typography.Style.display`: Large Title, rounded bold,
    /// -0.4 tracking). Scales with Dynamic Type up to the first accessibility size, then holds so a
    /// two-line headline can't push the CTA off a small phone.
    struct DisplayTitle: View {
        let text: String
        var alignment: TextAlignment = .center

        var body: some View {
            Text(text)
                .zanoText(.display)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .onboardingEntrance()
        }
    }

    /// The display numeral for the emotional peaks (the wake-up math, the first streak). One tier
    /// above `Theme.Typography.numeralHero` (72pt): these are the loudest thing on their screens
    /// and there is no second number competing for the ring. Same face as the numeral tokens
    /// (`Theme.Typography.numeral(size:weight:)`), scales with Dynamic Type and shrinks rather
    /// than clips.
    struct HeroNumeral: View {
        enum Tier: Sendable { case hero, large }

        let text: String
        var color: Color = Theme.Colors.text
        var tier: Tier = .hero

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 96
        @ScaledMetric(relativeTo: .largeTitle) private var largeSize: CGFloat = 64

        var body: some View {
            Text(text)
                .font(Theme.Typography.numeral(size: min(tier == .hero ? heroSize : largeSize, 140), weight: .heavy))
                .tracking(-1.5)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
        }
    }

    // MARK: Layout

    /// Content centered vertically when it fits, scrolling when it doesn't (large Dynamic Type,
    /// small phones), instead of a fixed `Spacer` stack that clips.
    struct CenteredScroll<Content: View>: View {
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
}

/// A screen's title (or question block) springs up into place once when it appears: a short rise
/// and fade on `springCelebration`. One-shot, never gates input; nothing under Reduce Motion.
private struct OnboardingEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isShown: Bool { appeared || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : Theme.Spacing.md)
            .scaleEffect(isShown ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !reduceMotion, !appeared else { return }
                withAnimation(Theme.Motion.springCelebration.delay(0.06)) { appeared = true }
            }
    }
}

extension View {
    /// The shared one-shot spring entrance for an onboarding title/question (see
    /// `OnboardingEntrance`).
    func onboardingEntrance() -> some View {
        modifier(OnboardingEntrance())
    }

    /// Pins `bar` to the bottom of the screen as the onboarding action bar — Core's
    /// `zanoActionBar` (`StickyActionBar`: 16pt gutters, a background fade instead of a blurred
    /// material strip) with the bar's views stacked `Theme.Spacing.xs` apart. One position and one
    /// width for every onboarding CTA (better-layout 4.3, 7.5).
    func onboardingKitActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let stacked = VStack(spacing: Theme.Spacing.xs) { bar() }
        return zanoActionBar { stacked }
    }
}

// MARK: - Shared helpers (used by Screen10PlanReveal and Screen14FirstWin)

/// Fetch-or-create the device's one local `User` row (per `Models/User.swift`'s own doc comment:
/// exactly one exists locally, the signed-in-or-anonymous owner of this device). Onboarding is the
/// natural place this row first comes into existence — everything before Screen 10/11 only mutates
/// `flowState`, never SwiftData, so this is the first point in the flow that actually needs a real
/// `User` to attach a `Goal`/`LockSet` to. Idempotent: returns the existing row (refreshing its
/// `coachVoice`) on every call after the first.
///
/// `internal`, not `private`, so `Screen10PlanReveal.swift` and `Screen14FirstWin.swift` can share it rather than each re-fetching/re-creating independently
/// (CLAUDE.md: "never duplicate the same logic in two places").
@MainActor
func onboardingResolveOrCreateUser(coachVoice: CoachVoice, in context: ModelContext) throws -> User {
    var descriptor = FetchDescriptor<User>()
    descriptor.fetchLimit = 1
    if let existing = try context.fetch(descriptor).first {
        existing.coachVoice = coachVoice
        return existing
    }
    let user = User(coachVoice: coachVoice)
    context.insert(user)
    try context.save()
    return user
}

#Preview {
    OnboardingContainerView()
        .modelContainer(for: User.self, inMemory: true)
}
