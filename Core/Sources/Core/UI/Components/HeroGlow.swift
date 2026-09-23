// HeroGlow.swift
// Core / UI / Components
//
// The hero and "moment" screens — the shield, the unlock celebration, the alarm, onboarding's hook,
// wake-up and plan reveal — are the ones spec §16 describes in the most emotional language
// ("acid-green particles", "dark, calm, motivating"), and they were all a flat `#0A0A0B` rectangle
// with an icon on it (docs/design/better-ui-findings.md DEP-06, 2026-ios-trends.md §3.3.C).
//
// A `HeroGlow` is a single, faint, static radial wash of one hue from the top of the screen. No new
// hex: the tint is always an existing token (accent for earned/unlock, danger for the shield, a
// phase tint for the alarm). It is *not* animated — no looping blur/depth motion, which HIG asks
// apps to avoid under Reduce Motion — and it sits behind content, never over it.

import SwiftUI

/// A faint static radial wash of `tint` fading from the top-center of its container.
public struct HeroGlow: View {
    private let tint: Color
    private let intensity: Double

    /// - Parameters:
    ///   - tint: The hue. `Theme.Colors.accent` for earned/unlock, `.danger` for the shield,
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
