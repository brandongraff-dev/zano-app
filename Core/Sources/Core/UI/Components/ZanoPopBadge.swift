// ZanoPopBadge.swift
// Core / UI / Components
//
// The glossy goal glyph (session 33 on Fuel, shared app-wide in session 34 after the founder picked
// the glossy direction): a tilted tile in the goal's colour with a white glyph, a white sticker rim,
// a coloured drop glow and an optional sparkle. Use it wherever a goal or action glyph sits in a
// tile or row. `IconBadge` stays for quiet, non-goal glyphs (settings rows, errors, permissions).

import SwiftUI

/// A glossy, tilted glyph tile. Grows with Dynamic Type (capped at 1.4x, the same cap as
/// `IconBadge`). Decorative: callers label the row, so it is hidden from VoiceOver.
public struct ZanoPopBadge: View {
    private let systemImage: String
    private let color: Color
    private let size: CGFloat
    private let tilt: Double
    private let sparkle: Bool
    private let bounce: Int

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// - Parameters:
    ///   - systemImage: SF Symbol name (an identifier, not copy).
    ///   - color: The tile's colour, usually `Theme.Colors.Ring.color(for:)`.
    ///   - size: Side length in points at the default text size. 46 for card headers, 34 for rows.
    ///   - tilt: Degrees of playful rotation.
    ///   - sparkle: A small white sparkle on the top-right corner. Headers only; rows skip it.
    ///   - bounce: Change it to bounce the glyph (a log landed).
    public init(
        systemImage: String,
        color: Color,
        size: CGFloat = 46,
        tilt: Double = -6,
        sparkle: Bool = true,
        bounce: Int = 0
    ) {
        self.systemImage = systemImage
        self.color = color
        self.size = size
        self.tilt = tilt
        self.sparkle = sparkle
        self.bounce = bounce
    }

    public var body: some View {
        let side = size * min(scale, 1.4)
        let shape = RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
        ZStack {
            shape.fill(color)
            // Gloss: a lit top half, a shaded bottom lip.
            shape.fill(LinearGradient(
                colors: [Color.white.opacity(0.38), Color.white.opacity(0), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            ))
            Image(systemName: systemImage)
                .font(.system(size: side * 0.46, weight: .heavy))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.25), radius: 0, y: 1.5)
                .symbolEffect(.bounce, value: bounce)
            shape.strokeBorder(Color.white.opacity(0.9), lineWidth: max(2, side * 0.055))
        }
        .frame(width: side, height: side)
        .shadow(color: color.opacity(0.55), radius: side * 0.16, y: side * 0.08)
        .overlay(alignment: .topTrailing) {
            if sparkle {
                Image(systemName: "sparkle")
                    .font(.system(size: side * 0.3, weight: .black))
                    .foregroundStyle(Color.white)
                    .shadow(color: color, radius: 2)
                    .offset(x: side * 0.16, y: -side * 0.16)
            }
        }
        .rotationEffect(.degrees(tilt))
        .accessibilityHidden(true)
    }
}

#Preview("Pop badges") {
    HStack(spacing: 24) {
        ZanoPopBadge(systemImage: "fork.knife", color: Theme.Colors.Ring.protein)
        ZanoPopBadge(systemImage: "drop.fill", color: Theme.Colors.Ring.water, tilt: 5)
        ZanoPopBadge(systemImage: "refrigerator.fill", color: Theme.Colors.Ring.protein, size: 34, sparkle: false)
    }
    .padding()
}
