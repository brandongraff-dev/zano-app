// ZanoSurface.swift
// Core / UI / Components
//
// The one card recipe. Before this file, 31 call sites in 20 files hand-inlined
// `.background(Theme.Colors.surface, in: RoundedRectangle(...))` — a flat fill 1.08:1 off the page,
// with no edge, no depth and no single place to change either (docs/design/better-ui-findings.md
// DEP-02, composition-audit.md S-2). Spec §16's own style paragraph asks for "subtle inner glow on
// active elements, crisp 1px hairline dividers"; the flat fills could deliver neither.
//
// The recipe, and why it is built this way:
//
//   * A 1px *top-lit* gradient edge (`Theme.Colors.edgeGradient`, white 14% → 6%), not a drop shadow. Drop shadows are
//     invisible on near-black; a highlight rim is what dark design systems use for depth, and it
//     is the same idea iOS's own glass chrome now uses (lighter specular rim, darker interior), so
//     opaque ZANO cards and system chrome read as one family without ZANO cards becoming glass —
//     Apple is explicit that glass belongs to the navigation layer, not the content layer.
//   * Increase Contrast doubles the edge (`colorSchemeContrast`), for free.
//   * An optional hue wash (`tint`) that fades from the top-leading corner — locked = danger,
//     unlocked = accent — so a state reads from across the room, not from a 17pt label.
//   * A *static* glow (`active`) for earned states only. Never animated: HIG asks apps to avoid
//     animating depth/blur changes under Reduce Motion, and a pulsing glow would be looping motion
//     on the most-seen screens.

import SwiftUI

extension View {

    /// Wraps the view in a ZANO card: `fill` (default `surface`) in a continuous rounded rect of
    /// `radius`, a 1px top-lit edge, and — optionally — a `tint` wash and an `active` glow.
    ///
    /// Pad the content *before* calling this (`.padding(Theme.Spacing.md).zanoCard()`), exactly as
    /// the `.background(...)` recipe it replaces was used.
    ///
    /// - Parameters:
    ///   - radius: Corner radius. `Theme.Radius.medium` for standard cards, `.large` for hero
    ///     surfaces, `.small` for compact rows. Nested surfaces: see `Theme.Radius`.
    ///   - tint: A hue wash fading from the top-leading corner (10% of `tint`, 18% when `active`).
    ///   - active: Adds a static outer glow in `tint` (accent when `tint` is `nil`) and strengthens
    ///     the wash. Reserve for *earned/unlocked* surfaces — the glow is the reward.
    ///   - fill: Base fill. Defaults to `Theme.Colors.surface`.
    public func zanoCard(
        radius: CGFloat = Theme.Radius.medium,
        tint: Color? = nil,
        active: Bool = false,
        fill: Color = Theme.Colors.surface
    ) -> some View {
        modifier(ZanoSurface(radius: radius, fill: fill, tint: tint, active: active, showsEdge: true))
    }

    /// A recessed well *inside* a card: `surface2`, no edge, no glow. For nested content (an
    /// insight box, a stat cell, an input field) that should sit in the card, not on it.
    public func zanoWell(radius: CGFloat = Theme.Radius.small) -> some View {
        modifier(ZanoSurface(radius: radius, fill: Theme.Colors.surface2, tint: nil, active: false, showsEdge: false))
    }

    /// The top depth level: one per screen, for the thing the screen exists to show (Today's lock
    /// state, a paywall's plan). It catches more light than a card (a `surfaceHero` → `surface`
    /// gradient), sits on a soft drop shadow that reads against the ambient backdrop, and carries
    /// the same optional state wash and earned glow as `zanoCard`.
    ///
    /// Depth levels (premium-ui-plan.md Phase 2): `zanoBackdrop` (ambient) → `zanoHero` →
    /// `zanoCard` → `zanoWell` (recessed).
    public func zanoHero(
        radius: CGFloat = Theme.Radius.large,
        tint: Color? = nil,
        active: Bool = false
    ) -> some View {
        modifier(ZanoSurface(radius: radius, fill: Theme.Colors.surface, tint: tint, active: active, showsEdge: true, elevated: true))
    }
}

struct ZanoSurface: ViewModifier {
    let radius: CGFloat
    let fill: Color
    let tint: Color?
    let active: Bool
    let showsEdge: Bool
    var elevated: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                ZStack {
                    if elevated {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.surfaceHero, fill],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
                            .shadow(color: glowColor, radius: 24)
                    } else {
                        shape
                            .fill(fill)
                            .shadow(color: glowColor, radius: 18)
                    }
                    if let tint {
                        shape.fill(wash(tint))
                    }
                }
            }
            .overlay {
                if showsEdge {
                    shape
                        .strokeBorder(
                            Theme.Colors.edgeGradient(increasedContrast: contrast == .increased),
                            lineWidth: Theme.Metrics.edgeWidth
                        )
                        // The edge is paint, not a control: it must never swallow a tap meant for
                        // the button inside the card.
                        .allowsHitTesting(false)
                }
            }
    }

    private func wash(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(active ? 0.18 : 0.10), tint.opacity(0)],
            startPoint: .topLeading,
            endPoint: UnitPoint(x: 0.8, y: 0.8)
        )
    }

    private var glowColor: Color {
        guard active else { return .clear }
        return (tint ?? Theme.Colors.accent).opacity(0.22)
    }
}

#Preview("zanoCard") {
    VStack(spacing: Theme.Spacing.md) {
        Text("Standard card")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .zanoCard()

        Text("Locked (danger wash)")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .zanoCard(tint: Theme.Colors.danger)

        Text("Earned (active glow)")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .zanoCard(radius: Theme.Radius.large, tint: Theme.Colors.accent, active: true)
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
