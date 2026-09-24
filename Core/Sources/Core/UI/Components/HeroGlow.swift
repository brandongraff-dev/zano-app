// HeroGlow.swift
// Core / UI / Components
//
// The hero and "moment" screens — the shield, the unlock celebration, the alarm, onboarding's hook,
// wake-up and plan reveal — are the ones spec §16 describes in the most emotional language
// ("a burst of particles", "dark, calm, motivating"), and they were all a flat `#0A0A0B` rectangle
// with an icon on it (docs/design/better-ui-findings.md DEP-06, 2026-ios-trends.md §3.3.C).
//
// A `HeroGlow` is a single, faint, static radial wash of one hue from the top of the screen. No new
// hex: the tint is always an existing token (ZANO Blue `accent` for earned/unlock, navy
// `lockedAmbient` for the shield, a phase tint for the alarm). It is *not* animated — no looping blur/depth motion, which HIG asks
// apps to avoid under Reduce Motion — and it sits behind content, never over it.

import SwiftUI

/// A faint static radial wash of `tint` fading from the top-center of its container.
public struct HeroGlow: View {
    private let tint: Color
    private let intensity: Double

    /// - Parameters:
    ///   - tint: The hue. `Theme.Colors.accent` for earned/unlock, `.lockedAmbient` for the shield,
    ///     `.warning`/`.danger` for alarm phases. Defaults to the accent.
    ///   - intensity: Peak opacity at the top. Defaults to 0.16 — visible on an OLED at 30%
    ///     brightness without tinting the text above it.
    public init(tint: Color = Theme.Colors.accent, intensity: Double = 0.16) {
        self.tint = tint
        self.intensity = intensity
    }

    public var body: some View {
        RadialGradient(
            colors: [tint.opacity(intensity), tint.opacity(intensity * 0.4), tint.opacity(0)],
            center: .top,
            startRadius: 0,
            endRadius: 380
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The standard ZANO screen backdrop: `Theme.Colors.background` filling the safe area, with an
    /// optional `HeroGlow` of `glow`. Replaces `.background(Theme.Colors.background.ignoresSafeArea())`
    /// on screens that want a hero wash.
    public func zanoBackdrop(glow: Color? = nil, intensity: Double = 0.16) -> some View {
        background {
            ZStack(alignment: .top) {
                Theme.Colors.background
                if let glow {
                    HeroGlow(tint: glow, intensity: intensity)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// The state-driven ambient light behind a whole screen ("light is earned",
    /// premium-ui-plan.md §4). Two soft pools falling from above the top corners, so the page has
    /// a direction of light instead of a flat fill:
    ///
    ///  * `.locked` — cool, dim steel (`lockedAmbient`) with a faint trace of `danger`: quiet, a
    ///    little cold.
    ///  * `.progress(fraction)` — the cool light warms toward the accent as goals complete.
    ///  * `.earned` — the accent at its fullest: the one bright screen state.
    ///  * `.neutral` — a barely-there cool pool, for screens with no lock state.
    ///
    /// Static: a function of state, never animated on its own (a looping glow on the most-seen
    /// screens is motion nobody asked for). Callers pass `.neutral` under Reduce Transparency.
    public func zanoAmbient(_ state: ZanoAmbientState) -> some View {
        background {
            ZanoAmbientBackdrop(state: state)
                .ignoresSafeArea()
        }
    }
}

public enum ZanoAmbientState: Equatable, Sendable {
    case neutral
    case locked
    case progress(Double)
    case earned
}

private struct ZanoAmbientBackdrop: View {
    let state: ZanoAmbientState

    private var primary: (color: Color, strength: Double) {
        switch state {
        case .neutral:
            (Theme.Colors.lockedAmbient, 0.10)
        case .locked:
            (Theme.Colors.lockedAmbient, 0.24)
        case .progress(let fraction):
            fraction >= 0.5
                ? (Theme.Colors.accent, 0.06 + 0.08 * fraction)
                : (Theme.Colors.lockedAmbient, 0.24 - 0.12 * fraction)
        case .earned:
            (Theme.Colors.accent, 0.20)
        }
    }

    private var secondary: (color: Color, strength: Double) {
        switch state {
        case .neutral: (Theme.Colors.lockedAmbient, 0.04)
        case .locked: (Theme.Colors.danger, 0.07)
        case .progress(let fraction): (Theme.Colors.accent, 0.04 + 0.08 * fraction)
        case .earned: (Theme.Colors.accent, 0.10)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Theme.Colors.background
                RadialGradient(
                    colors: [primary.color.opacity(primary.strength), primary.color.opacity(0)],
                    center: UnitPoint(x: 0.15, y: -0.05),
                    startRadius: 0,
                    endRadius: width * 1.25
                )
                RadialGradient(
                    colors: [secondary.color.opacity(secondary.strength), secondary.color.opacity(0)],
                    center: UnitPoint(x: 1.0, y: 0.05),
                    startRadius: 0,
                    endRadius: width * 0.95
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("HeroGlow") {
    VStack {
        Text("Earned.")
            .font(Theme.Typography.display)
            .foregroundStyle(Theme.Colors.text)
            .padding(.top, Theme.Spacing.xl)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .zanoBackdrop(glow: Theme.Colors.accent)
    .preferredColorScheme(.dark)
}
