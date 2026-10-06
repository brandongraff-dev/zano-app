// ZanoSurface.swift
// Core / UI / Components
//
// The one card recipe. Before this file, 31 call sites in 20 files hand-inlined
// `.background(Theme.Colors.surface, in: RoundedRectangle(...))` — a flat fill 1.08:1 off the page,
// with no edge, no depth and no single place to change either (docs/design/better-ui-findings.md
// DEP-02, composition-audit.md S-2). Spec §16's own style paragraph asks for "subtle inner glow on
// active elements, crisp 1px hairline dividers"; the flat fills could deliver neither.
//
// The recipe, and why it is built this way (revised 2026-10-06, Apple-native pass —
// docs/sessions/14-apple-native-surfaces.md):
//
//   * A flat `surface` (`#1C1C1E`) on true black, exactly like a system inset-grouped cell. No
//     outline and no drop shadow by default: the earlier 1px top-lit edge on *every* card, plus
//     tinted washes and outer glows, were the main things that made ZANO read as a generated
//     dashboard rather than an iOS app.
//   * Increase Contrast restores the 1px edge (`colorSchemeContrast`), for free.
//   * No tinted washes, ever (2026-10-06, second pass): the olive/brown gradients on earned and
//     warning cards read as the old UI. `tint` and `active` are accepted for source compatibility
//     and ignored; a card's state is carried by its content (an accent numeral, a glyph).
//   * No glow. Ever. Depth comes from the surface step, not from light bleeding off the card.

import SwiftUI

extension View {

    /// Wraps the view in a ZANO card: `fill` (default `surface`) in a continuous rounded rect of
    /// `radius` and — on an `active` card only — a soft `tint` wash.
    ///
    /// Pad the content *before* calling this (`.padding(Theme.Spacing.md).zanoCard()`), exactly as
    /// the `.background(...)` recipe it replaces was used.
    ///
    /// - Parameters:
    ///   - radius: Corner radius. `Theme.Radius.medium` for standard cards, `.large` for hero
    ///     surfaces, `.small` for compact rows. Nested surfaces: see `Theme.Radius`.
    ///   - tint: The hue of the `active` wash (accent when `nil`). Ignored on a resting card.
    ///   - active: Draws a 14% `tint` wash fading from the top-leading corner. Reserve for
    ///     *earned/unlocked* surfaces (the colour arriving is the reward) and for the rare
    ///     `warning` card that needs the user's attention.
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
}

extension View {

    /// Floating chrome — a pinned status capsule, a bar that hovers over scrolling content — drawn
    /// the way the system draws its own: Liquid Glass on iOS 26, `.ultraThinMaterial` before it.
    /// Content cards stay opaque `zanoCard`s: Apple reserves glass for the layer that floats above
    /// content, never for the content itself.
    public func zanoGlass<S: Shape>(in shape: S) -> some View {
        modifier(ZanoGlass(shape: shape))
    }
}

extension View {

    /// The backdrop for a partial-height sheet: the system's own Liquid Glass sheet on iOS 26 (by
    /// leaving the background alone), `.regularMaterial` before it. Apply to the sheet's root and
    /// do not paint an opaque background inside it, or the material never shows.
    public func zanoSheetBackground() -> some View {
        modifier(ZanoSheetBackground())
    }
}

struct ZanoSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.presentationBackground(.regularMaterial)
        }
    }
}

struct ZanoGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        // `glassEffect` exists only in the iOS 26 SDK (Swift 6.2 / Xcode 26). CI's Xcode is older,
        // so the call is compiled out there and every build gets the material — the same
        // compile-time guard the AlarmKit code uses (`#if canImport(AlarmKit)`).
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

struct ZanoSurface: ViewModifier {
    let radius: CGFloat
    let fill: Color
    let tint: Color?
    let active: Bool
    let showsEdge: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                shape.fill(fill)
            }
            .overlay {
                if showsEdge && contrast == .increased {
                    shape
                        .strokeBorder(
                            Theme.Colors.edgeGradient(increasedContrast: true),
                            lineWidth: Theme.Metrics.edgeWidth
                        )
                        // The edge is paint, not a control: it must never swallow a tap meant for
                        // the button inside the card.
                        .allowsHitTesting(false)
                }
            }
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

        Text("Tint without active (plain)")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .zanoCard(tint: Theme.Colors.danger)

        Text("Earned (active wash)")
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
