// FuelGameMeters.swift
// App / Features / Fuel / Components
//
// Playful pass (2026-10-03, docs/design/visual-direction-v2.md, second pass on Fuel). The founder
// asked for Fuel to feel like "filling up a game meter". The pieces live here, inside the Fuel
// feature folder, because the shared design system (Core/UI) is owned by a parallel pass:
//
//   - `FuelProteinBar`    protein as a real protein bar: chocolate chunks fill a candy wrapper, with a
//                         bite out of the leading edge and crumbs on each log (2026-10-08).
//   - `FuelWaterTank`     water as a bottle of liquid with a cap and bubbles; it sloshes once per log.
//   - `FuelPopBadge`      the glossy tilted glyph tile used by the card headers and the rows below.
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

// MARK: - Protein: the bar is a protein bar

/// Fixed food colours for the chocolate. Not goal hues (the wrapper carries the protein hue), so
/// they stay the same in light and dark: chocolate is brown on any canvas.
private enum FuelChocolate {
    static let light = Color(red: 0.62, green: 0.38, blue: 0.22)
    static let mid = Color(red: 0.45, green: 0.26, blue: 0.14)
    static let dark = Color(red: 0.30, green: 0.16, blue: 0.08)
    static let crumb = Color(red: 0.52, green: 0.31, blue: 0.17)
}

/// Protein as an actual protein bar (2026-10-08, the founder asked for the meter to "look like
/// food"). A candy wrapper in the protein hue holds ten dashed ghost squares; each log fills
/// chocolate chunks in from the left, and the leading edge has a bite taken out of it. Crumbs fly
/// off the bite on every log. Complete = the whole bar, no bite, with a warm glow.
/// Decorative: the card speaks the value.
struct FuelProteinBar: View {
    let progress: Double
    let color: Color
    /// Bump to throw crumbs off the bite (once per log).
    var crumbs: Int = 0
    var chunks = 10
    var height: CGFloat = 40

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isComplete: Bool { clamped >= 1 }
    private var radius: CGFloat { height * 0.26 }

    var body: some View {
        // Room for the wrapper's crimped ends on both sides.
        let crimp: CGFloat = 7
        HStack(spacing: 0) {
            FuelCrimpShape(pointsRight: false)
                .fill(color.opacity(0.45))
                .frame(width: crimp, height: height * 0.8)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    wrapper
                    chocolate
                        .mask { FuelBiteMask(fraction: clamped, minWidth: height * 0.7) }
                        .shadow(color: isComplete ? color.opacity(0.7) : .clear, radius: 8)
                    crumbBurst(width: proxy.size.width)
                }
            }
            FuelCrimpShape(pointsRight: true)
                .fill(color.opacity(0.45))
                .frame(width: crimp, height: height * 0.8)
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: clamped)
        .accessibilityHidden(true)
    }

    /// The empty wrapper: the protein hue, a glossy band and one dashed ghost square per chunk.
    private var wrapper: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(color.opacity(0.16))
            .overlay {
                HStack(spacing: 3) {
                    ForEach(0..<chunks, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: radius * 0.6, style: .continuous)
                            .strokeBorder(color.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
                .padding(4)
            }
            .overlay(shape.strokeBorder(color.opacity(0.5), lineWidth: 1.5))
    }

    /// Ten chocolate chunks, each with a lit top bevel and a dark lower lip so it reads as a moulded
    /// square rather than a flat segment.
    private var chocolate: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(FuelChocolate.dark)
            .overlay {
                HStack(spacing: 3) {
                    ForEach(0..<chunks, id: \.self) { _ in
                        FuelChocolateChunk(radius: radius * 0.6)
                    }
                }
                .padding(4)
            }
    }

    /// Three crumbs that hop off the bite and fall. Off under Reduce Motion and at 0 / 100%.
    @ViewBuilder
    private func crumbBurst(width: CGFloat) -> some View {
        if !reduceMotion && clamped > 0 && !isComplete {
            let edge = max(width * clamped, height * 0.7)
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    FuelCrumb(index: index, trigger: crumbs)
                }
            }
            .position(x: edge, y: height / 2)
            .allowsHitTesting(false)
        }
    }
}

/// One moulded chocolate square.
private struct FuelChocolateChunk: View {
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(LinearGradient(
                colors: [FuelChocolate.light, FuelChocolate.mid],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay(
                shape
                    .inset(by: 3)
                    .fill(FuelChocolate.mid)
                    .overlay(
                        shape.inset(by: 3)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 2)
                    .padding(.horizontal, 5)
                    .padding(.top, 1.5)
            }
    }
}

/// A crumb that pops out of the bite and drops, once per `trigger` change.
private struct FuelCrumb: View {
    let index: Int
    let trigger: Int

    var body: some View {
        // Fan the three crumbs out: up-right, right, down-right.
        let dx: Double = [10, 16, 9][index]
        let rise: Double = [-16, -8, -2][index]
        let size: CGFloat = [5, 4, 3.5][index]
        RoundedRectangle(cornerRadius: 1.2)
            .fill(FuelChocolate.crumb)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: FuelCrumbFrame(), trigger: trigger) { crumb, frame in
                crumb
                    .rotationEffect(.degrees(frame.spin))
                    .offset(x: frame.x, y: frame.y)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.02)
                    LinearKeyframe(1, duration: 0.45)
                    LinearKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: 0.02)
                    LinearKeyframe(dx, duration: 0.65)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: 0.02)
                    CubicKeyframe(rise, duration: 0.2)
                    CubicKeyframe(18, duration: 0.45)
                }
                KeyframeTrack(\.spin) {
                    LinearKeyframe(0, duration: 0.02)
                    LinearKeyframe(200, duration: 0.65)
                }
            }
    }
}

private struct FuelCrumbFrame {
    var opacity: Double = 0
    var x: Double = 0
    var y: Double = 0
    var spin: Double = 0
}

/// The eaten-so-far region of the bar: everything left of `fraction`, with two round bites out of
/// the leading edge. Full (or empty) bars have no bite. Animatable, so the bite slides with a log.
struct FuelBiteMask: Shape {
    var fraction: Double
    /// Once anything is logged, at least this much shows, so 3 g never reads as zero.
    var minWidth: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        guard fraction < 1 else { return Path(rect) }
        let edge = min(max(rect.width * fraction, minWidth), rect.width)
        let h = rect.height
        // Two bites: a big one high, a smaller one low, overlapping like teeth marks.
        let bites: [(cy: CGFloat, r: CGFloat)] = [(h * 0.34, h * 0.30), (h * 0.76, h * 0.24)]
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: edge, y: rect.minY))
        var y: CGFloat = 0
        while y <= h {
            var depth: CGFloat = 0
            for bite in bites where abs(y - bite.cy) < bite.r {
                depth = max(depth, (bite.r * bite.r - (y - bite.cy) * (y - bite.cy)).squareRoot())
            }
            path.addLine(to: CGPoint(x: edge - depth, y: rect.minY + y))
            y += 1
        }
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The crimped end of a candy wrapper: a sawtooth edge pointing away from the bar.
struct FuelCrimpShape: Shape {
    let pointsRight: Bool
    var teeth = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.height / CGFloat(teeth)
        let inner = pointsRight ? rect.minX : rect.maxX
        let outer = pointsRight ? rect.maxX : rect.minX
        path.move(to: CGPoint(x: inner, y: rect.minY))
        for tooth in 0..<teeth {
            let top = rect.minY + CGFloat(tooth) * step
            path.addLine(to: CGPoint(x: outer, y: top + step / 2))
            path.addLine(to: CGPoint(x: inner, y: top + step))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Pop badge

/// A goal glyph that pops (2026-10-08): a glossy tilted tile in the goal's hue, white glyph, white
/// sticker rim, a coloured drop glow and a small sparkle. Shared by the meter headers and the rows
/// below them so the whole Fuel screen speaks one icon language. Grows with Dynamic Type (capped
/// at 1.4x, the same cap as `IconBadge`). Decorative: callers label the row.
struct FuelPopBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 46
    var tilt: Double = -6
    var sparkle = true
    /// Bump to bounce the glyph.
    var bounce: Int = 0

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
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
            bubbles
            // Pass 3 (restraint): a flat glass rim.
            shape.strokeBorder(Theme.Colors.text.opacity(0.25), lineWidth: 2)
            // Glass glint down the left side.
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 5)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        // The bottle cap (2026-10-08): the tank reads as a water bottle.
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    )
                    .frame(width: 30, height: 9)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.55))
                    .frame(width: 22, height: 4)
            }
            .offset(y: -13)
        }
        .padding(.top, 13)
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

    /// A few bubbles resting in the water, riding up with the level.
    private var bubbles: some View {
        GeometryReader { proxy in
            let spots: [(x: Double, y: Double, d: CGFloat)] = [(0.34, 0.25, 7), (0.56, 0.55, 5), (0.42, 0.8, 4)]
            ForEach(spots.indices, id: \.self) { index in
                let spot = spots[index]
                Circle()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.2)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .frame(width: spot.d, height: spot.d)
                    .position(
                        x: proxy.size.width * spot.x,
                        y: proxy.size.height * (1 - level * (1 - spot.y))
                    )
                    .opacity(level > 0.15 ? 1 : 0)
            }
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
