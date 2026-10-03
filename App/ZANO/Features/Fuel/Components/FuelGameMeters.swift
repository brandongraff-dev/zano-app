// FuelGameMeters.swift
// App / Features / Fuel / Components
//
// Playful pass (2026-10-03, docs/design/visual-direction-v2.md, second pass on Fuel). The founder
// asked for Fuel to feel like "filling up a game meter". The pieces live here, inside the Fuel
// feature folder, because the shared design system (Core/UI) is owned by a parallel pass:
//
//   - `FuelSegmentMeter`  protein as an arcade power bar: chunky segments that fill with each log.
//   - `FuelWaterTank`     water as a glass tank of liquid; the surface sloshes once per log.
//   - `FuelScore`         the count in the score face (SF Pro Expanded black), rolling digits.
//   - `fuelGainBubble`    a "+25 g" that floats up off the number after a log.
//
// Motion is only ever a reply to a log (no idle loops). Every animation is gated on Reduce Motion:
// the tank and meter just show the new level, and the bubble does not appear (VoiceOver already
// hears the Undo toast's "Logged 25 g of protein").

import SwiftUI
import Core

// MARK: - Score numeral

/// The metric's number in the arcade score face, with "/ 150 g" as a quiet suffix. Counts up only
/// (additive goals, spec §24). Rolls with `.numericText` when it changes. The suffix drops under
/// the number when the pair does not fit on one line (iPhone SE, accessibility sizes).
struct FuelScore: View {
    let value: Int
    let suffix: String
    /// Base point size at the default Dynamic Type size.
    var points: CGFloat = 52

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    private var number: some View {
        Text(value.formatted(.number))
            .font(Theme.Typography.score(size: points * min(scale, 1.6)))
            .foregroundStyle(Theme.Colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: Double(value)))
            .animation(reduceMotion ? nil : Theme.Motion.springPop, value: value)
    }

    private var suffixText: some View {
        Text(suffix)
            .font(Theme.Typography.unit)
            .foregroundStyle(Theme.Colors.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                number
                suffixText
            }
            VStack(alignment: .leading, spacing: 0) {
                number
                suffixText
            }
        }
    }
}

// MARK: - Protein: segmented power bar

/// Ten chunky segments in the goal's hue on a dim track of the same hue. The fill grows on a bouncy
/// spring, and a top specular line makes it read as a lit tube rather than a flat progress bar.
/// Past 100% the bar stays full and glows. Decorative: the card speaks the value.
struct FuelSegmentMeter: View {
    let progress: Double
    let color: Color
    var segments = 10
    var height: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: CGFloat { CGFloat(min(max(progress, 0), 1)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
                fill(width: proxy.size.width)
                notches
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: clamped)
        .accessibilityHidden(true)
    }

    private func fill(width: CGFloat) -> some View {
        // A sliver is always visible once anything is logged, so 3 g never reads as zero.
        let fillWidth = clamped > 0 ? max(height, width * clamped) : 0
        return Capsule(style: .continuous)
            // Pass 3 (restraint): one flat fill, no gradient and no gloss strip.
            .fill(color)
            .frame(width: fillWidth)
    }

    /// Ink gaps between segments: the "power bar" look.
    private var notches: some View {
        HStack(spacing: 0) {
            ForEach(1..<segments, id: \.self) { _ in
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Theme.Colors.background.opacity(0.55))
                    .frame(width: 3)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Water: liquid tank

/// A glass tank that fills with water. The surface is a sine wave; each time `slosh` changes the
/// wave rolls and settles (amplitude spikes, then calms), the level rises on a spring. Quarter marks
/// on the side make the level readable at a glance. Decorative: the card speaks the value.
struct FuelWaterTank: View {
    let progress: Double
    let color: Color
    /// Bump to make the surface slosh (once per log).
    let slosh: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0
    @State private var amplitude: Double = 3

    private var level: Double { min(max(progress, 0), 1) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small + 6, style: .continuous)
        ZStack {
            shape.fill(color.opacity(0.10))
            waves
                .clipShape(shape)
            marks
            // Pass 3 (restraint): a flat glass rim.
            shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 2)
            // Glass glint down the left side.
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 5)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: level)
        .onChange(of: slosh) { _, _ in
            guard !reduceMotion else { return }
            amplitude = 9
            withAnimation(.easeOut(duration: 1.4)) {
                phase += .pi * 3
                amplitude = 3
            }
        }
        .accessibilityHidden(true)
    }

    private var waves: some View {
        ZStack {
            FuelWaveShape(level: level, phase: phase + 1.4, amplitude: amplitude * 0.8)
                .fill(color.opacity(0.45))
            FuelWaveShape(level: level, phase: phase, amplitude: amplitude)
                .fill(color.opacity(0.85))
        }
    }

    private var marks: some View {
        GeometryReader { proxy in
            ForEach([0.25, 0.5, 0.75], id: \.self) { mark in
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: mark == 0.5 ? 14 : 9, height: 2)
                    .position(
                        x: proxy.size.width - (mark == 0.5 ? 15 : 12.5),
                        y: proxy.size.height * (1 - mark)
                    )
            }
        }
    }
}

/// Liquid with a sine-wave surface at `level` (0 = empty, 1 = full). Level, phase and amplitude are
/// all animatable, so a log can raise the water and roll the surface in one animation.
struct FuelWaveShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(level, phase), amplitude) }
        set {
            level = newValue.first.first
            phase = newValue.first.second
            amplitude = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        // Full: no wave poking out of the top.
        let amp: Double = level >= 1 ? 0 : amplitude
        let surface = Double(rect.height) * (1 - level)
        let wavelength = max(Double(rect.width) * 0.9, 1)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: Double(rect.minX), y: surface))
        var x = Double(rect.minX)
        let maxX = Double(rect.maxX)
        while x <= maxX {
            let angle: Double = (x / wavelength) * 2 * Double.pi + phase
            let y: Double = surface + amp * sin(angle)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Gain bubble

extension View {
    /// A "+25 g" that floats up off this view and fades, each time `trigger` changes. Off under
    /// Reduce Motion.
    func fuelGainBubble(_ text: String, trigger: Int, color: Color) -> some View {
        modifier(FuelGainBubble(text: text, trigger: trigger, color: color))
    }
}

private struct FuelGainBubble: ViewModifier {
    let text: String
    let trigger: Int
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if !reduceMotion {
                Text(text)
                    .font(Theme.Typography.numeralSmall())
                    .foregroundStyle(Theme.Colors.onFill)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(color, in: Capsule(style: .continuous))
                    .keyframeAnimator(initialValue: FuelBubbleFrame(), trigger: trigger) { bubble, frame in
                        bubble
                            .scaleEffect(frame.scale)
                            .offset(y: frame.offsetY)
                            .opacity(frame.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.08)
                            LinearKeyframe(1, duration: 0.6)
                            LinearKeyframe(0, duration: 0.35)
                        }
                        KeyframeTrack(\.offsetY) {
                            LinearKeyframe(0, duration: 0.01)
                            CubicKeyframe(-34, duration: 1.0)
                        }
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1.15, duration: 0.2, spring: .bouncy)
                            SpringKeyframe(1.0, duration: 0.4, spring: .smooth)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct FuelBubbleFrame {
    var opacity: Double = 0
    var offsetY: Double = 0
    var scale: Double = 0.6
}
