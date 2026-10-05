// ZanoGoalTile.swift
// Core / UI / Components
//
// Pass 2 "playful" (docs/design/visual-direction-v2.md, "Pass 2: playful"): the goal tile surface.
// Pass 1 washed each goal tile in 14% of its colour, which read as "a grey card with a hint". Here the
// goal's colour is a real presence:
//
//   * the glass is tinted with the colour, flat (14%, 18% once done);
//   * progress fills the tile from the bottom as one flat layer of the colour (10%), no gradient and
//     no bright surface line;
//   * the rim is the glass's own neutral specular edge; only a done tile gets a thin solid rim in
//     its colour (that rim carries meaning). Tiles never glow: one glow per screen, and it is the
//     hero's.
//
// Pass 3 (restraint, 2026-10-03) replaced pass 2's top-lit gradient wash, the "juice" gradient with
// its bright surface line, the coloured gradient rim and the done-glow with the flat rules above.
//
// Reduce Transparency: the glass becomes the solid `surface`; the colour fill stays (it is paint on
// an opaque card, not translucency). Increase Contrast: the done rim is the full colour, the neutral rim doubles.
//
// Text on the tile stays `text`/`textSecondary` (never the goal colour: violet and periwinkle are
// under 4.5:1). Colour is never the only signal: the tile always carries its glyph and words.

import SwiftUI

extension View {
    /// Puts this view on a goal-coloured glass tile (see the file header).
    ///
    /// Pad the content first, like `zanoCard`.
    ///
    /// - Parameters:
    ///   - color: The goal's colour (`Theme.Colors.Ring.color(for:)`).
    ///   - progress: `0...1`, how high the liquid fill stands. `0` hides it.
    ///   - isDone: A full, brighter tile with a thin solid rim in `color`.
    ///   - radius: Corner radius. Defaults to `Theme.Radius.medium`.
    public func zanoGoalTile(
        color: Color,
        progress: Double = 0,
        isDone: Bool = false,
        radius: CGFloat = Theme.Radius.medium
    ) -> some View {
        modifier(ZanoGoalTileSurface(color: color, progress: progress, isDone: isDone, radius: radius))
    }
}

struct ZanoGoalTileSurface: ViewModifier {
    let color: Color
    let progress: Double
    let isDone: Bool
    let radius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var fill: Double { isDone ? 1 : min(1, max(0, progress)) }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                ZStack {
                    base(shape)
                    liquid
                        .clipShape(shape)
                    shape.strokeBorder(
                        LinearGradient(colors: [.clear, Theme.Colors.glassInnerShade], startPoint: .center, endPoint: .bottom),
                        lineWidth: 5
                    )
                    .blur(radius: 3)
                    .clipShape(shape)
                }
            }
            .overlay {
                rimView(shape)
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: fill)
    }

    @ViewBuilder
    private func base(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(Theme.Colors.surface)
        } else {
            shape.fill(
                LinearGradient(
                    colors: [Theme.Colors.glassFillTop, Theme.Colors.glassFillBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        shape.fill(color.opacity(isDone ? 0.18 : 0.14))
    }

    /// The colour rising from the bottom to `fill`: one flat layer, no surface line.
    private var liquid: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(color.opacity(0.10))
                    .frame(height: proxy.size.height * fill)
            }
        }
        .allowsHitTesting(false)
    }

    /// Done: a thin solid rim in the goal colour. Otherwise the glass's neutral specular edge.
    @ViewBuilder
    private func rimView(_ shape: RoundedRectangle) -> some View {
        if isDone {
            shape.strokeBorder(contrast == .increased ? color : color.opacity(0.7), lineWidth: 1.5)
        } else {
            shape.strokeBorder(
                contrast == .increased ? Theme.Colors.glassEdgeIncreased : Theme.Colors.glassEdge,
                lineWidth: Theme.Metrics.edgeWidth
            )
        }
    }
}

#Preview("Goal tiles") {
    HStack(spacing: Theme.Spacing.sm) {
        Text("Protein")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.goalTileMinHeight, alignment: .topLeading)
            .padding(Theme.Spacing.md)
            .zanoGoalTile(color: Theme.Colors.Ring.protein, progress: 0.48)
        Text("Gym")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.goalTileMinHeight, alignment: .topLeading)
            .padding(Theme.Spacing.md)
            .zanoGoalTile(color: Theme.Colors.Ring.workout, isDone: true)
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .zanoAmbient(.progress(0.5))
    .preferredColorScheme(.dark)
}
