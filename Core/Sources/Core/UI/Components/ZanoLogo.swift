// ZanoLogo.swift
// Core / UI / Components
//
// The ZANO logo, drawn natively (docs/brand/brand-kit.md). The wordmark is custom compressed letters
// on a 282 × 100 unit grid — the same coordinates as `docs/brand/zano-wordmark.svg`, so the app, the
// app icon, the landing page and the engraved Lock Card are one drawing, not a font approximation.
// The O is the "earned ring": a stadium ring in the one brand accent (spec §15), which also stands
// alone as the brand symbol (`ZanoMark`) where the full wordmark doesn't fit.
//
// Grid (units): Z 0–62, A 72–136, N 146–208, O 218–282; cap height 100; stroke weight 20.

import SwiftUI

/// The full ZANO wordmark. `height` is the cap height in points; width follows (2.82 × height).
public struct ZanoWordmark: View {
    public enum Style: Sendable {
        /// White letters, accent O. The default, on dark surfaces.
        case brand
        /// One color throughout (engraving, a tinted share card, low-emphasis footers).
        case mono(Color)
    }

    private let height: CGFloat
    private let style: Style

    public init(height: CGFloat = 24, style: Style = .brand) {
        self.height = height
        self.style = style
    }

    public static let aspectRatio: CGFloat = 2.82

    private var letterColor: Color {
        switch style {
        case .brand: Theme.Colors.text
        case .mono(let color): color
        }
    }

    private var ringColor: Color {
        switch style {
        case .brand: Theme.Colors.accent
        case .mono(let color): color
        }
    }

    public var body: some View {
        let scale = height / 100
        ZStack {
            ZanoLettersShape()
                .fill(letterColor, style: FillStyle(eoFill: true))
            ZanoRingShape(originX: 218)
                .stroke(ringColor, lineWidth: 20 * scale)
        }
        .frame(width: 282 * scale, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.brand.name)
    }
}

/// The brand symbol: the wordmark's O on its own, the earned ring. For places too small for the
/// wordmark (a notification preview's app icon, a 16pt footer glyph).
public struct ZanoMark: View {
    private let height: CGFloat
    private let color: Color

    public init(height: CGFloat = 24, color: Color = Theme.Colors.accent) {
        self.height = height
        self.color = color
    }

    public var body: some View {
        let scale = height / 100
        ZanoRingShape(originX: 0)
            .stroke(color, lineWidth: 20 * scale)
            .frame(width: 64 * scale, height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.brand.name)
    }
}

// MARK: - Shapes (unit grid → rect)

/// Z, A (with its counter) and N as filled polygons. Fill with `eoFill` so the A's counter cuts out.
struct ZanoLettersShape: Shape {
    private static let z: [(CGFloat, CGFloat)] = [
        (0, 0), (62, 0), (62, 20), (24, 80), (62, 80), (62, 100), (0, 100), (0, 80), (38, 20), (0, 20)
    ]
    private static let aOuter: [(CGFloat, CGFloat)] = [
        (72, 100), (92, 0), (116, 0), (136, 100), (114, 100), (110.6, 82), (97.4, 82), (94, 100)
    ]
    private static let aCounter: [(CGFloat, CGFloat)] = [(100.2, 64), (107.8, 64), (104, 38)]
    private static let n: [(CGFloat, CGFloat)] = [
        (146, 100), (146, 0), (166, 0), (188, 56), (188, 0), (208, 0), (208, 100), (188, 100), (166, 44), (166, 100)
    ]

    func path(in rect: CGRect) -> Path {
        let scale = rect.height / 100
        var path = Path()
        for polygon in [Self.z, Self.aOuter, Self.aCounter, Self.n] {
            guard let first = polygon.first else { continue }
            path.move(to: CGPoint(x: rect.minX + first.0 * scale, y: rect.minY + first.1 * scale))
            for point in polygon.dropFirst() {
                path.addLine(to: CGPoint(x: rect.minX + point.0 * scale, y: rect.minY + point.1 * scale))
            }
            path.closeSubpath()
        }
        return path
    }
}

/// The O: a stadium on its stroke centre line (44 × 80 units, corner radius 22), stroked 20 units
/// wide so its outer edge spans `originX ... originX + 64` and `0 ... 100`.
struct ZanoRingShape: Shape {
    let originX: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = rect.height / 100
        let centreLine = CGRect(
            x: rect.minX + (originX + 10) * scale,
            y: rect.minY + 10 * scale,
            width: 44 * scale,
            height: 80 * scale
        )
        return Path(roundedRect: centreLine, cornerRadius: 22 * scale, style: .circular)
    }
}

#Preview("ZanoWordmark") {
    VStack(spacing: Theme.Spacing.xl) {
        ZanoWordmark(height: 64)
        ZanoWordmark(height: 24)
        ZanoWordmark(height: 18, style: .mono(Theme.Colors.muted))
        ZanoMark(height: 40)
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
