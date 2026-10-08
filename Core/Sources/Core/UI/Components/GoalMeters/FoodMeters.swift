// FoodMeters.swift
// Core / UI / Components / GoalMeters
//
// The food and drink meters: protein (a protein bar), water (glasses), creatine (scoops) and meal
// prep (containers). See ZanoGoalMeter.swift for the family.

import SwiftUI

// MARK: - Protein: the bar is a protein bar
//
// Moved from Fuel (session 33) in session 34.

/// Fixed food colours for the chocolate. Not goal hues (the wrapper carries the protein hue), so
/// they stay the same in light and dark: chocolate is brown on any canvas.
private enum ProteinChocolate {
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
public struct ZanoProteinBar: View {
    private let progress: Double
    private let color: Color
    private let crumbs: Int
    private let chunks: Int
    private let height: CGFloat

    /// - Parameters:
    ///   - progress: 0...1.
    ///   - color: The wrapper's colour (the protein ring colour).
    ///   - crumbs: Bump to throw crumbs off the bite (once per log).
    ///   - chunks: Chocolate squares in the bar. 10 on Fuel, 8 on a goal tile.
    ///   - height: Bar height.
    public init(progress: Double, color: Color, crumbs: Int = 0, chunks: Int = 10, height: CGFloat = 40) {
        self.progress = progress
        self.color = color
        self.crumbs = crumbs
        self.chunks = chunks
        self.height = height
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isComplete: Bool { clamped >= 1 }
    private var radius: CGFloat { height * 0.26 }

    public var body: some View {
        // Room for the wrapper's crimped ends on both sides.
        let crimp: CGFloat = 7
        HStack(spacing: 0) {
            ProteinCrimpShape(pointsRight: false)
                .fill(color.opacity(0.45))
                .frame(width: crimp, height: height * 0.8)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    wrapper
                    chocolate
                        .mask { ProteinBiteMask(fraction: clamped, minWidth: height * 0.7) }
                        .shadow(color: isComplete ? color.opacity(0.7) : .clear, radius: 8)
                    crumbBurst(width: proxy.size.width)
                }
            }
            ProteinCrimpShape(pointsRight: true)
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
            .fill(ProteinChocolate.dark)
            .overlay {
                HStack(spacing: 3) {
                    ForEach(0..<chunks, id: \.self) { _ in
                        ProteinChocolateChunk(radius: radius * 0.6)
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
                    ProteinCrumb(index: index, trigger: crumbs)
                }
            }
            .position(x: edge, y: height / 2)
            .allowsHitTesting(false)
        }
    }
}

/// One moulded chocolate square.
private struct ProteinChocolateChunk: View {
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(LinearGradient(
                colors: [ProteinChocolate.light, ProteinChocolate.mid],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay(
                shape
                    .inset(by: 3)
                    .fill(ProteinChocolate.mid)
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
private struct ProteinCrumb: View {
    let index: Int
    let trigger: Int

    var body: some View {
        // Fan the three crumbs out: up-right, right, down-right.
        let dx: Double = [10, 16, 9][index]
        let rise: Double = [-16, -8, -2][index]
        let size: CGFloat = [5, 4, 3.5][index]
        RoundedRectangle(cornerRadius: 1.2)
            .fill(ProteinChocolate.crumb)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: ProteinCrumbFrame(), trigger: trigger) { crumb, frame in
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

private struct ProteinCrumbFrame {
    var opacity: Double = 0
    var x: Double = 0
    var y: Double = 0
    var spin: Double = 0
}

/// The eaten-so-far region of the bar: everything left of `fraction`, with two round bites out of
/// the leading edge. Full (or empty) bars have no bite. Animatable, so the bite slides with a log.
struct ProteinBiteMask: Shape {
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
struct ProteinCrimpShape: Shape {
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

// MARK: - Water: glasses

/// Eight glasses that fill with water, one after another.
struct WaterGlassesMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        MeterItemRow(count: 8, progress: progress, spacing: 4) { _, fill in
            ZStack {
                GlassShape().meterGhost(color, lineWidth: 1.3)
                // The water: a level that rises inside the glass, with a lighter surface line.
                GeometryReader { proxy in
                    let h = proxy.size.height * fill
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ZStack(alignment: .top) {
                            Rectangle().fill(color)
                            Rectangle().fill(Color.white.opacity(0.45)).frame(height: fill > 0 ? 2 : 0)
                        }
                        .frame(height: h)
                    }
                }
                .clipShape(GlassShape())
                // Glass glint.
                GlassShape()
                    .stroke(color.opacity(fill > 0 ? 0.9 : 0), lineWidth: 1.3)
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 2)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 3)
            }
        }
    }
}

/// A tumbler: wider at the rim than at the base.
struct GlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.maxY - 2), control: CGPoint(x: rect.midX, y: rect.maxY + 1))
        path.closeSubpath()
        return path
    }
}

// MARK: - Creatine: scoops

/// Five scoops; each fills with a mound of powder.
struct ScoopsMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        MeterItemRow(count: 5, progress: progress, spacing: 6) { _, fill in
            MeterReveal(fill: fill) {
                ScoopShape().meterGhost(color, lineWidth: 1.3)
            } filled: {
                ZStack {
                    ScoopShape().meterGloss(color)
                    // The powder mound on top of the bowl.
                    GeometryReader { proxy in
                        Ellipse()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 0.28)
                            .position(x: proxy.size.width * 0.32, y: proxy.size.height * 0.42)
                    }
                }
            }
        }
    }
}

/// A measuring scoop: a round bowl on the left, a handle out to the right.
struct ScoopShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bowlW = rect.width * 0.64
        let bowlTop = rect.minY + rect.height * 0.42
        let bowlH = rect.height * 0.5
        path.move(to: CGPoint(x: rect.minX, y: bowlTop))
        path.addQuadCurve(to: CGPoint(x: rect.minX + bowlW, y: bowlTop),
                          control: CGPoint(x: rect.minX + bowlW / 2, y: bowlTop + bowlH * 2))
        // Handle.
        let handleH = rect.height * 0.14
        path.addLine(to: CGPoint(x: rect.maxX, y: bowlTop - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: bowlTop - rect.height * 0.12 + handleH))
        path.addLine(to: CGPoint(x: rect.minX + bowlW - 1, y: bowlTop + handleH))
        path.addLine(to: CGPoint(x: rect.minX + bowlW, y: bowlTop))
        path.closeSubpath()
        return path
    }
}

// MARK: - Meal prep: containers

/// Four meal-prep containers, each packed with a main and two sides.
struct MealPrepMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        MeterItemRow(count: 4, progress: progress, spacing: 5) { _, fill in
            let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
            MeterReveal(fill: fill) {
                box.meterGhost(color)
            } filled: {
                ZStack {
                    box.meterGloss(color.opacity(0.35))
                    // Compartments: one big, two small.
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).meterGloss(color)
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).meterGloss(color.opacity(0.75))
                            RoundedRectangle(cornerRadius: 3, style: .continuous).meterGloss(color.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(3)
                    box.strokeBorder(color, lineWidth: 1.5)
                }
            }
        }
    }
}
