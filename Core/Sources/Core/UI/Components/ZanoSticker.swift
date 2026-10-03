// ZanoSticker.swift
// Core / UI / Components
//
// Pass 2 "playful" (docs/design/visual-direction-v2.md, "Pass 2: playful"): the sticker language.
// A sticker is a chunky, rounded chip that looks printed on thick vinyl: a fill (solid goal colour,
// or a tinted glass wash), a bright highlight across its top half, a soft shade inside its bottom
// edge, and a little drop of coloured light under it. Icon-only stickers are decoration, so they get
// a white die-cut rim and may sit at a playful angle (`tilt`). A sticker with words never rotates:
// the API ignores `tilt` whenever `text` is set, because a tilted label is harder to read.
//
//   * `.filled`: solid `color`, ink label (`Theme.Colors.onFill`, 5.3:1 on ZANO Blue and higher on
//     every goal colour). For the one thing in a group that is "yours" (done, selected, earned).
//   * `.tinted`: the colour's wash on glass, a colour glyph, a `text` label. Quieter; for the rest.
//
// SF Symbols render `.hierarchical` and bounce (`symbolEffect(.bounce)`) each time `bounceTrigger`
// changes. Reduce Motion: no bounce. Dynamic Type: text styles, so the sticker grows with the text.
// Icon-only stickers are hidden from VoiceOver (decoration); a text sticker reads its text.
//
// `ZanoSparkleShape` (the four-point sparkle) lives here too: the mascot's sparks, the charge burst
// and the confetti all draw it.

import SwiftUI

public struct ZanoSticker: View {

    public enum Style: Sendable {
        /// Solid colour, ink label. The loud one.
        case filled
        /// The colour's wash on glass, a colour glyph and a light label.
        case tinted
    }

    public enum Size: Sendable {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: Theme.Metrics.stickerSmall
            case .regular: Theme.Metrics.stickerRegular
            case .large: Theme.Metrics.stickerLarge
            }
        }

        var font: Font {
            switch self {
            case .small: .system(.caption, design: .rounded, weight: .bold)
            case .regular: .system(.subheadline, design: .rounded, weight: .bold)
            case .large: .system(.headline, design: .rounded, weight: .heavy)
            }
        }

        /// The glyph of an icon-only sticker, about half its diameter.
        var iconOnlyFont: Font {
            switch self {
            case .small: .system(.caption, weight: .heavy)
            case .regular: .system(.body, weight: .heavy)
            case .large: .system(.title2, weight: .heavy)
            }
        }
    }

    private let text: String?
    private let systemImage: String?
    private let color: Color
    private let style: Style
    private let size: Size
    private let tilt: Double
    private let bounceTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// - Parameters:
    ///   - text: The label. `nil` makes an icon-only (decorative) round sticker.
    ///   - systemImage: An SF Symbol before the text, or the whole sticker when `text` is `nil`.
    ///   - color: The sticker's colour, usually a goal colour (`Theme.Colors.Ring.color(for:)`).
    ///   - style: `.filled` (solid) or `.tinted` (wash on glass). Defaults to `.tinted`.
    ///   - size: `.small` (26pt), `.regular` (34pt) or `.large` (48pt) tall.
    ///   - tilt: Degrees of playful rotation, for icon-only stickers only (ignored with `text`).
    ///   - bounceTrigger: Change it to bounce the glyph (a goal completing, a value changing).
    public init(
        _ text: String? = nil,
        systemImage: String? = nil,
        color: Color = Theme.Colors.accent,
        style: Style = .tinted,
        size: Size = .regular,
        tilt: Double = 0,
        bounceTrigger: Int = 0
    ) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.style = style
        self.size = size
        self.tilt = tilt
        self.bounceTrigger = bounceTrigger
    }

    public var body: some View {
        Group {
            if let text {
                labelSticker(text)
            } else {
                iconSticker
            }
        }
        .accessibilityHidden(text == nil)
    }

    // MARK: Variants

    private func labelSticker(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.xxs + 1) {
            if let systemImage {
                glyph(systemImage)
                    .font(size.font)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(size.font)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .padding(.horizontal, size == .small ? Theme.Spacing.xs + 2 : Theme.Spacing.sm)
        .frame(minHeight: size.height * min(scale, 1.4))
        .background { face(Capsule(style: .continuous)) }
        .accessibilityElement(children: .combine)
    }

    private var iconSticker: some View {
        let diameter = size.height * min(scale, 1.4)
        return glyph(systemImage ?? "sparkle")
            .font(size.iconOnlyFont)
            .frame(width: diameter, height: diameter)
            .background {
                face(Circle())
                    .overlay {
                        // The die-cut rim: icon-only stickers are decoration, so they look peeled-on.
                        Circle().strokeBorder(Theme.Colors.stickerRim.opacity(style == .filled ? 1 : 0.35), lineWidth: 2)
                    }
            }
            .rotationEffect(.degrees(tilt))
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(style == .filled ? Theme.Colors.onFill : color)
            .symbolEffect(.bounce, options: .speed(1.2), value: reduceMotion ? 0 : bounceTrigger)
    }

    private var labelColor: Color {
        style == .filled ? Theme.Colors.onFill : Theme.Colors.text
    }

    // MARK: The vinyl

    /// Fill, top highlight, bottom inner shade, rim, coloured drop shadow.
    private func face<S: InsettableShape>(_ shape: S) -> some View {
        ZStack {
            switch style {
            case .filled:
                shape.fill(color)
            case .tinted:
                if reduceTransparency {
                    shape.fill(Theme.Colors.surface2)
                } else {
                    shape.fill(Theme.Colors.glassFill)
                }
                shape.fill(Theme.Colors.wash(color))
            }
            shape.fill(
                LinearGradient(
                    colors: [Theme.Colors.stickerHighlight.opacity(style == .filled ? 1 : 0.45), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.strokeBorder(
                LinearGradient(colors: [.clear, Theme.Colors.stickerShade], startPoint: .center, endPoint: .bottom),
                lineWidth: 2
            )
            if style == .tinted {
                shape.strokeBorder(color.opacity(0.5), lineWidth: Theme.Metrics.edgeWidth)
            }
        }
        .shadow(color: style == .filled && !reduceTransparency ? color.opacity(0.4) : .clear, radius: 8, y: 3)
    }
}

// MARK: - Sparkle shape

/// A four-point sparkle (the "✦" of the arcade): sharp points, pinched middle. `pinch` is how far in
/// the waist sits, as a fraction of the radius (0.22 by default: a crisp, cartoon sparkle).
public struct ZanoSparkleShape: Shape {
    private let pinch: CGFloat

    public init(pinch: CGFloat = 0.22) {
        self.pinch = pinch
    }

    public func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let wx = rx * pinch
        let wy = ry * pinch
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - ry))
        path.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y), control: CGPoint(x: c.x + wx, y: c.y - wy))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry), control: CGPoint(x: c.x + wx, y: c.y + wy))
        path.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y), control: CGPoint(x: c.x - wx, y: c.y + wy))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry), control: CGPoint(x: c.x - wx, y: c.y - wy))
        path.closeSubpath()
        return path
    }
}

#Preview("Stickers") {
    VStack(spacing: Theme.Spacing.md) {
        HStack(spacing: Theme.Spacing.sm) {
            ZanoSticker(systemImage: "fork.knife", color: Theme.Colors.Ring.protein, style: .filled, size: .large, tilt: -8)
            ZanoSticker(systemImage: "dumbbell.fill", color: Theme.Colors.Ring.workout, size: .large, tilt: 6)
            ZanoSticker(systemImage: "drop.fill", color: Theme.Colors.Ring.water, style: .filled)
        }
        HStack(spacing: Theme.Spacing.sm) {
            ZanoSticker("72%", systemImage: "bolt.fill", color: Theme.Colors.accent, style: .filled, size: .small)
            ZanoSticker("+25g", color: Theme.Colors.Ring.protein)
            ZanoSticker("15 min", systemImage: "hourglass", color: Theme.Colors.Ring.focus)
        }
        ZanoSparkleShape()
            .fill(Theme.Colors.Ring.sunriseAlarm)
            .frame(width: 40, height: 40)
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .zanoAmbient(.progress(0.5))
    .preferredColorScheme(.dark)
}
