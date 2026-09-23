// IconBadge.swift
// Core / UI / Components
//
// The "glyph in a tinted disc" that ten-plus screens hand-built with seven different diameters
// (32 / 36 / 40 / 44 / 52 / 60 / 96) and the same `tint.opacity(0.16)` fill — which, on the accent,
// composites to a drab olive rather than a dimmer lime (docs/design/better-ui-findings.md RAD-05,
// DEP-03). One component, three sizes from `Theme.Metrics`, fills from `Theme.Colors.wash(_:)`.
//
// The badge is a circle on purpose: a circle is the capsule case of iOS 26's concentric shapes, so
// it needs no radius token and never fights the corner of the card it sits in.

import SwiftUI

/// A tinted circle holding an SF Symbol. Decorative by default — the text beside it carries the
/// meaning — so it is hidden from VoiceOver.
public struct IconBadge: View {

    /// Diameters from `Theme.Metrics`. The glyph is 45% of the diameter.
    public enum Size: Sendable {
        /// 32pt — list rows, inline chips.
        case small
        /// 44pt — card leaders (lock status, ghost banner, founder card). A full hit-size disc.
        case medium
        /// 96pt — hero moments (shield, permission priming, first win).
        case large

        var baseDiameter: CGFloat {
            switch self {
            case .small: Theme.Metrics.iconBadgeSmall
            case .medium: Theme.Metrics.iconBadgeMedium
            case .large: Theme.Metrics.iconBadgeLarge
            }
        }
    }

    private let systemName: String
    private let tint: Color
    private let size: Size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 1.0 at the default text size. The badge grows with Dynamic Type (a glyph beside scaled text
    /// should not be dwarfed by it), capped at 1.4x so it never outgrows the row it sits in.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// - Parameters:
    ///   - systemName: SF Symbol name (an identifier, not copy).
    ///   - tint: Glyph color; the disc is `Theme.Colors.wash(tint)`. Defaults to the accent.
    ///   - size: `.small`, `.medium` (default) or `.large`.
    public init(systemName: String, tint: Color = Theme.Colors.accent, size: Size = .medium) {
        self.systemName = systemName
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        let resolved = size.baseDiameter * min(scale, 1.4)
        return ZStack {
            Circle()
                .fill(Theme.Colors.wash(tint))
            Image(systemName: systemName)
                .font(.system(size: resolved * 0.45, weight: .semibold))
                .foregroundStyle(tint)
                // Same-family swaps (lock ↔ unlock, flame ↔ snowflake) morph instead of popping
                // (docs/design/better-ui-findings.md MOT-03); Reduce Motion cross-fades.
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        }
        .frame(width: resolved, height: resolved)
        .animation(reduceMotion ? nil : Theme.Motion.iconSwap, value: systemName)
        .animation(reduceMotion ? nil : Theme.Motion.iconSwap, value: tint)
        .accessibilityHidden(true)
    }
}

#Preview("IconBadge") {
    HStack(spacing: Theme.Spacing.lg) {
        IconBadge(systemName: "dumbbell.fill", tint: Theme.Colors.accent, size: .small)
        IconBadge(systemName: "lock.fill", tint: Theme.Colors.danger)
        IconBadge(systemName: "timer", tint: Theme.Colors.Ring.focus)
        IconBadge(systemName: "lock.fill", tint: Theme.Colors.danger, size: .large)
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
