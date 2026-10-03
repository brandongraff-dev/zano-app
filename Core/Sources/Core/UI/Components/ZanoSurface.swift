// ZanoSurface.swift
// Core / UI / Components
//
// The one card recipe. Before this file, 31 call sites in 20 files hand-inlined
// `.background(Theme.Colors.surface, in: RoundedRectangle(...))` — a flat fill 1.08:1 off the page,
// with no edge, no depth and no single place to change either (docs/design/better-ui-findings.md
// DEP-02, composition-audit.md S-2). Spec §16's own style paragraph asks for "subtle inner glow on
// active elements, crisp 1px hairline dividers"; the flat fills could deliver neither.
//
// v2 (2026-10-02, docs/design/visual-direction-v2.md §3 "Glass"): the card is now *glass* — a white
// frost sheen over the aurora canvas, a 1px specular rim (`Theme.Colors.glassEdge`), a soft inner
// shade along the bottom, and the same optional tint wash and earned glow. No real blur: the canvas
// behind is already soft, so a material would cost a render pass and look the same. `zanoHero` is the
// raised level (brighter frost, a drop shadow, radius `hero`). Reduce Transparency: opaque `surface`.
// A caller-supplied non-default `fill` stays a solid colour. The notes below describe the pass before.
//
// Pass 3 (restraint, 2026-10-03): the `tint` wash is a FLAT tint (one colour, 8% / 12% active) instead
// of a corner-fading gradient; an `active` card gets a thin solid rim in its tint instead of a glow.
// Only `zanoHero` may glow (one glow per screen). The glass sheen and specular rim are unchanged.
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
    ///   - tint: A flat hue tint over the glass (8% of `tint`, 12% when `active`).
    ///   - active: Adds a thin solid rim in `tint` (accent when `tint` is `nil`) and strengthens
    ///     the tint (on `zanoHero`, a static glow instead). Reserve for *earned/unlocked* surfaces.
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
        modifier(ZanoWell(radius: radius))
    }

    /// The top depth level: one per screen, for the thing the screen exists to show (Today's lock
    /// state, a paywall's plan). It catches more light than a card (a `surfaceHero` → `surface`
    /// gradient), sits on a soft drop shadow that reads against the ambient backdrop, and carries
    /// the same optional state wash and earned glow as `zanoCard`.
    ///
    /// Depth levels (premium-ui-plan.md Phase 2): `zanoBackdrop` (ambient) → `zanoHero` →
    /// `zanoCard` → `zanoWell` (recessed).
    public func zanoHero(
        radius: CGFloat = Theme.Radius.hero,
        tint: Color? = nil,
        active: Bool = false
    ) -> some View {
        modifier(ZanoSurface(radius: radius, fill: Theme.Colors.surface, tint: tint, active: active, showsEdge: true, elevated: true))
    }
}

/// A recessed well: a faint white wash inside glass (solid `surface2` under Reduce Transparency).
struct ZanoWell: ViewModifier {
    let radius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(
            reduceTransparency ? AnyShapeStyle(Theme.Colors.surface2) : AnyShapeStyle(Color.white.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The default fill means "glass"; any other fill a caller passes is honoured as a solid colour
    /// (with the same glass edge), so explicit fills keep working.
    private var isGlass: Bool { fill == Theme.Colors.surface && !reduceTransparency }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                ZStack {
                    base(shape)
                    if let tint {
                        shape.fill(wash(tint))
                    }
                    if isGlass && showsEdge {
                        // Inner shade along the bottom edge: the glass has thickness.
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.clear, Theme.Colors.glassInnerShade],
                                    startPoint: .center,
                                    endPoint: .bottom
                                ),
                                lineWidth: 6
                            )
                            .blur(radius: 4)
                            .clipShape(shape)
                    }
                }
            }
            .overlay {
                if showsEdge {
                    shape
                        .strokeBorder(edge, lineWidth: Theme.Metrics.edgeWidth)
                        // The edge is paint, not a control: it must never swallow a tap meant for
                        // the button inside the card.
                        .allowsHitTesting(false)
                    if active && !elevated {
                        // Pass 3: an earned card says so with a thin solid rim, not a glow.
                        shape
                            .strokeBorder((tint ?? Theme.Colors.accent).opacity(0.6), lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
            }
    }

    @ViewBuilder
    private func base(_ shape: RoundedRectangle) -> some View {
        if isGlass {
            shape
                .fill(
                    LinearGradient(
                        colors: elevated
                            ? [Theme.Colors.glassRaisedTop, Theme.Colors.glassRaisedBottom]
                            : [Theme.Colors.glassFillTop, Theme.Colors.glassFillBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: elevated ? Theme.Colors.shadow.opacity(0.6) : .clear, radius: 30, y: 18)
                .shadow(color: glowColor, radius: 28)
        } else if elevated {
            shape
                .fill(LinearGradient(colors: [Theme.Colors.surfaceHero, solidFill], startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.Colors.shadow, radius: 28, y: 18)
                .shadow(color: glowColor, radius: 24)
        } else {
            shape
                .fill(solidFill)
        }
    }

    /// Under Reduce Transparency the glass becomes the opaque `surface` it stands in for.
    private var solidFill: Color { fill }

    private var edge: LinearGradient {
        if contrast == .increased { return Theme.Colors.glassEdgeIncreased }
        return showsEdge && (isGlass || elevated) ? Theme.Colors.glassEdge : Theme.Colors.edgeGradient()
    }

    /// Pass 3: one flat tint, no fade.
    private func wash(_ tint: Color) -> Color {
        tint.opacity(active ? 0.12 : 0.08)
    }

    /// The hero's earned glow. Cards never glow (pass 3: one glow per screen).
    private var glowColor: Color {
        guard active, elevated else { return .clear }
        return (tint ?? Theme.Colors.accent).opacity(0.3)
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
