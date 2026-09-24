// OnboardingContainerView.swift
// App / Features / Onboarding
//
// docs/spec.md §7 (Onboarding Flow, screen by screen) lists all 14 screens; §17 Session 6
// (`feat/onboarding`) owns "Onboarding (14 screens) + permission priming + RevenueCat paywall +
// first-win flow" as one unit. This file is the single root that wires every screen into one
// sequential flow, plus the shared chrome and the small design toolkit (`OnboardingKit`, below)
// that screens 8-14 build on.
//
// `OnboardingFlowState` (`OnboardingFlowState.swift`, read here, never edited) is the shared state:
// `currentScreen` (1...14), the Q1-Q6 answers, `advance()`/`goBack()`, `progressFraction`,
// `recordCommitment(at:)`. Every screen takes `@Bindable var flowState: OnboardingFlowState` and
// advances itself via `flowState.advance()`; this container never drives navigation from the
// outside beyond the back button.
//
// Design pass (docs/design/*, 2026-09-23 — better-ui, better-layout, typography-color,
// composition-audit, competitive-research, 2026-ios-trends), applied to this file:
//   - One header row instead of two: [back 44pt][progress bar]. Saves ~48pt per screen
//     (better-layout 7.6) and the back target is 44pt (better-ui HIT-01).
//   - The header is hidden on screen 1 (the full-bleed hook, spec §7.1) and on screen 14 (the live
//     first-win lock: a Back there used to return to the paywall mid-session — better-layout 7.6).
//     The "Step N of 14" accessibility element is NOT hidden with it: on those two screens it is
//     kept as a 1pt invisible marker, so VoiceOver still announces where the user is and the UI-test
//     harness (`ZANOUITests`, which detects onboarding and waits on steps 1 and 14 through that
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
// Order note (decision 2026-09-23): the hard paywall is screen 12, directly after Commitment, so
// nothing sits between the peak and the payment ask; notification priming is screen 13. The file
// `Screen12PermissionPriming.swift` keeps its name but is now the 13th screen.

import SwiftUI
import SwiftData
import Core

/// Root of the 14-screen onboarding flow (docs/spec.md §7). Owns the one shared
/// `OnboardingFlowState` for the whole flow and renders whichever screen
/// `flowState.currentScreen` names, wrapped in `OnboardingScaffold`'s chrome.
///
/// Expected to be hosted by whatever decides onboarding should show at all (e.g. `ContentView`,
/// or a future "has this device finished onboarding?" gate) — that decision, and what happens
/// after `onFinished` fires, belong to that caller, not this file.
@MainActor
struct OnboardingContainerView: View {
    /// Called once, after Screen 14's widget-add prompt is dismissed. Defaults to a no-op so this
    /// view compiles and behaves standalone (e.g. in `#Preview`).
    var onFinished: () -> Void = {}

    @State private var flowState: OnboardingFlowState

    /// `initialScreen` exists so the CI screenshot gallery (`ScreenshotGallery.swift`) can photograph
    /// any of the 14 screens directly; every real caller leaves it at the first screen.
    init(onFinished: @escaping () -> Void = {}, initialScreen: Int = OnboardingFlowState.firstScreen) {
        self.onFinished = onFinished
        let state = OnboardingFlowState()
        state.currentScreen = initialScreen
        _flowState = State(initialValue: state)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScaffold(flowState: flowState) {
            screen(for: flowState.currentScreen)
                .id(flowState.currentScreen)
                .transition(screenTransition)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springStandard,
            value: flowState.currentScreen
        )
    }

    @ViewBuilder
    private func screen(for screenNumber: Int) -> some View {
        switch screenNumber {
        case 1: Screen1Hook(flowState: flowState)
        case 2: Screen2SocialProof(flowState: flowState)
        case 3: Screen3MainGoal(flowState: flowState)
        case 4: Screen4AppSelection(flowState: flowState)
        case 5: Screen5PhoneTime(flowState: flowState)
        case 6: Screen6Workouts(flowState: flowState)
        case 7: Screen7FallOff(flowState: flowState)
        case 8: Screen8CoachVoice(flowState: flowState)
        case 9: Screen9WakeUp(flowState: flowState)
        case 10: Screen10PlanReveal(flowState: flowState)
        case 11: Screen11Commitment(flowState: flowState)
        case 12: PaywallView(flowState: flowState)
        case 13: Screen12PermissionPriming(flowState: flowState)
        default: Screen14FirstWin(flowState: flowState, onFinished: onFinished)
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

/// Consistent back button + progress bar wrapped around screens 2-13, per docs/spec.md §7's
/// framing ("under 3 minutes") — a visible progress bar is what makes a 14-screen flow feel short.
/// `internal` (not `private`) so the per-screen `#Preview`s can wrap themselves in the same chrome.
@MainActor
struct OnboardingScaffold<Content: View>: View {
    @Bindable var flowState: OnboardingFlowState
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Screen 1 is the full-bleed hook and screen 14 is the live first-win lock; both own the whole
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
                // The header is gone; its "Step N of 14" element is not. 1pt, invisible, no layout.
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(progressLabel)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    /// [back 44pt][progress bar]. The back glyph is centered in its 44pt target, which puts the
    /// chevron's visible edge on the same 16pt margin the cards below use; the bar's trailing edge
    /// is on that margin too.
    private var header: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Button {
                flowState.goBack()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .accessibilityLabel(Copy.onboarding.backButtonAccessibilityLabel)

            progressBar
                .padding(.trailing, Theme.Spacing.md)
        }
        .frame(height: Theme.Metrics.minTapTarget)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.track)
                // Progress through setup is chrome, not an earned state, so it is white (decision
                // 2026-09-24: the accent is for earned states only).
                Capsule()
                    .fill(Theme.Colors.interactive)
                    .frame(width: max(0, proxy.size.width * flowState.progressFraction))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill,
                        value: flowState.progressFraction
                    )
            }
        }
        .frame(height: OnboardingKit.progressBarHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressLabel)
    }
}

// MARK: - OnboardingKit (shared by screens 8-14)

/// The small design toolkit screens 8-14 share: only what `Core/UI` does not already provide. A
/// caseless enum used purely as a namespace so the names can't collide with anything a neighbouring
/// screen defines. Everything here is built from `Theme` tokens and Core components.
enum OnboardingKit {
    static let progressBarHeight: CGFloat = 6

    /// The glyph for each coach voice, shared by the voice picker, the plan build beat and the
    /// mock notification (same vocabulary `CosmeticsShopView` already uses for coach packs).
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

extension View {
    /// Pins `bar` to the bottom of the screen as the onboarding action bar — Core's
    /// `zanoActionBar` (`StickyActionBar`: 16pt gutters, a background fade instead of a blurred
    /// material strip) with the bar's views stacked `Theme.Spacing.xs` apart. One position and one
    /// width for every onboarding CTA (better-layout 4.3, 7.5).
    func onboardingKitActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let stacked = VStack(spacing: Theme.Spacing.xs) { bar() }
        return zanoActionBar { stacked }
    }
}

// MARK: - Shared helpers (used by Screen10PlanReveal, Screen11Commitment, Screen14FirstWin)

/// Fetch-or-create the device's one local `User` row (per `Models/User.swift`'s own doc comment:
/// exactly one exists locally, the signed-in-or-anonymous owner of this device). Onboarding is the
/// natural place this row first comes into existence — everything before Screen 10/11 only mutates
/// `flowState`, never SwiftData, so this is the first point in the flow that actually needs a real
/// `User` to attach a `Goal`/`LockSet` to. Idempotent: returns the existing row (refreshing its
/// `coachVoice`) on every call after the first.
///
/// `internal`, not `private`, so `Screen10PlanReveal.swift`, `Screen11Commitment.swift`, and
/// `Screen14FirstWin.swift` can share it rather than each re-fetching/re-creating independently
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
