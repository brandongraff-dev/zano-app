// ZanoGoalTile.swift
// Core / UI / Components
//
// Pass 2 "playful" (docs/design/visual-direction-v2.md, "Pass 2: playful"): the goal tile surface.
// Pass 1 washed each goal tile in 14% of its colour, which read as "a grey card with a hint". Here the
// goal's colour is a real presence:
//
//   * the glass is tinted with the colour from the top (22%, 34% once done) instead of a corner wash;
//   * the tile fills up like a glass of juice: a liquid layer of the colour rises from the bottom to
//     `progress`, with a bright "surface line" on top, so progress reads from across the room;
//   * the rim is lit in the colour at the top, so a row of tiles reads as a row of colours;
//   * a done tile glows in its colour (static glow, never pulsing).
//
// Reduce Transparency: the glass becomes the solid `surface`; the colour fill stays (it is paint on
// an opaque card, not translucency). Increase Contrast: the rim is the full colour.
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
    ///   - isDone: A full, brighter tile with a glow in `color`.
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
                .shadow(color: isDone && !reduceTransparency ? color.opacity(0.42) : .clear, radius: 16)
            }
            .overlay {
                shape
                    .strokeBorder(rim, lineWidth: isDone ? 1.5 : Theme.Metrics.edgeWidth)
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
        shape.fill(
            LinearGradient(
                colors: [color.opacity(isDone ? 0.34 : 0.22), color.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// The colour rising from the bottom to `fill`, with a bright surface line on top.
    private var liquid: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * fill
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [color.opacity(isDone ? 0.30 : 0.24), color.opacity(isDone ? 0.18 : 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if fill > 0.001 && fill < 0.999 {
                        Rectangle()
                            .fill(color.opacity(0.75))
                            .frame(height: 2)
                            .blur(radius: 0.5)
                    }
                }
                .frame(height: height)
            }
        }
        .allowsHitTesting(false)
    }

    private var rim: LinearGradient {
        if contrast == .increased {
            return LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            stops: [
                .init(color: color.opacity(isDone ? 0.9 : 0.6), location: 0),
                .init(color: Color.white.opacity(0.06), location: 0.5),
                .init(color: color.opacity(isDone ? 0.45 : 0.18), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
