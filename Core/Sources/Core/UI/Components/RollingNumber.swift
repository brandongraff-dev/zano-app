// RollingNumber.swift
// Core / UI / Components
//
// Pass 2 "playful" (docs/design/visual-direction-v2.md, "Pass 2: playful"): a whole number that rolls
// like an arcade score when it changes. `contentTransition(.numericText(value:))` rolls the digits
// up when the value grows and down when it shrinks; `Theme.Motion.numberRoll` supplies the spring.
//
// For a bare count (a tile's "72", a streak, a coin total). A caller-composed string with units
// ("72/150g", "2h 10m") is still `NumeralText`'s job, which rolls too.
//
// Dynamic Type: the size scales with the Title text style, clamped at 1.35× so a 72pt score does not
// burst its container. Reduce Motion: the number swaps without rolling.

import SwiftUI

public struct RollingNumber: View {

    public enum Face: Sendable {
        /// SF Pro Expanded black: the arcade score (`Theme.Typography.score`).
        case score
        /// SF Pro Rounded heavy: friendly counters (tiles, chips, coins).
        case rounded
    }

    private let value: Int
    private let size: CGFloat
    private let face: Face
    private let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    /// - Parameters:
    ///   - value: The number shown.
    ///   - size: Point size at the default text size. Defaults to 34.
    ///   - face: `.score` (expanded black) or `.rounded` (default).
    ///   - color: Defaults to `text`.
    public init(_ value: Int, size: CGFloat = 34, face: Face = .rounded, color: Color = Theme.Colors.text) {
        self.value = value
        self.size = size
        self.face = face
        self.color = color
    }

    public var body: some View {
        Text(value, format: .number)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(value)))
            .animation(reduceMotion ? nil : Theme.Motion.numberRoll, value: value)
    }

    private var font: Font {
        let pointSize = size * min(scale, 1.35)
        switch face {
        case .score: return Theme.Typography.score(size: pointSize)
        case .rounded: return .system(size: pointSize, weight: .heavy, design: .rounded).monospacedDigit()
        }
    }
}

#Preview("RollingNumber") {
    struct Demo: View {
        @State private var value = 2
        var body: some View {
            VStack(spacing: Theme.Spacing.md) {
                RollingNumber(value, size: 88, face: .score)
                RollingNumber(value * 25, size: 28, color: Theme.Colors.Ring.protein)
                Button("Bump") { value += 1 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zanoAmbient(.neutral)
        }
    }
    return Demo().preferredColorScheme(.dark)
}
