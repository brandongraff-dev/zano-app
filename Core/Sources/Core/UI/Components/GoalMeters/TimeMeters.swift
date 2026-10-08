// TimeMeters.swift
// Core / UI / Components / GoalMeters
//
// The time and mind meters: focus (a battery charging), sunrise (the sun coming up), sleep (moon
// phases), reading (book spines) and custom goals (stars). See ZanoGoalMeter.swift for the family.

import SwiftUI

// MARK: - Focus: battery

/// A battery that charges in five cells, with a bolt in the middle once it starts charging.
struct BatteryMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let nubW: CGFloat = 4
            let shell = RoundedRectangle(cornerRadius: h * 0.28, style: .continuous)
            HStack(spacing: 1.5) {
                ZStack {
                    shell.fill(color.opacity(0.10))
                    // Five cells, filling left to right.
                    MeterItemRow(count: 5, progress: progress, spacing: 2) { _, fill in
                        let cell = RoundedRectangle(cornerRadius: h * 0.14, style: .continuous)
                        MeterReveal(fill: fill) {
                            cell.fill(color.opacity(0.12))
                        } filled: {
                            cell.meterGloss(color)
                        }
                    }
                    .padding(3)
                    shell.strokeBorder(color.opacity(0.8), lineWidth: 2)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: h * 0.55, weight: .black))
                        .foregroundStyle(progress > 0 ? Color.white : color.opacity(0.5))
                        .shadow(color: Color.black.opacity(progress > 0 ? 0.3 : 0), radius: 0, y: 1)
                }
                .frame(width: w - nubW - 1.5, height: h)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color.opacity(progress >= 1 ? 1 : 0.6))
                    .frame(width: nubW, height: h * 0.4)
            }
        }
    }
}

// MARK: - Sunrise: the sun coming up

/// The sun rising over the horizon along a dotted arc; the sky warms as it climbs, and rays come
/// out once it's up.
struct SunriseMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let horizon = h * 0.86
            let sunR = h * 0.24
            let rx = w * 0.36
            let ry = horizon - sunR - 1
            // 0 = on the horizon at the left, 1 = top of the arc.
            let angle = Double.pi - Double.pi / 2 * progress
            let sunX = w / 2 + rx * CGFloat(cos(angle))
            let sunY = horizon - ry * CGFloat(sin(angle))
            ZStack(alignment: .topLeading) {
                // Sky.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.06 + 0.16 * progress))
                    .frame(width: w, height: horizon)
                // The path the sun climbs.
                SunArcShape(rx: rx, ry: ry, horizon: horizon)
                    .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1.3, dash: [2, 3]))
                // The sun, clipped at the horizon until it has risen.
                ZStack {
                    if progress >= 1 {
                        ForEach(0..<8, id: \.self) { ray in
                            Capsule()
                                .fill(color)
                                .frame(width: 2, height: sunR * 0.55)
                                .offset(y: -sunR * 1.45)
                                .rotationEffect(.degrees(Double(ray) * 45))
                        }
                    }
                    Circle()
                        .meterGloss(color)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                        .frame(width: sunR * 2, height: sunR * 2)
                }
                .position(x: sunX, y: sunY)
                .mask { Rectangle().frame(width: w, height: horizon).frame(maxHeight: .infinity, alignment: .top) }
                // Horizon.
                Capsule()
                    .fill(color)
                    .frame(width: w, height: 2.5)
                    .offset(y: horizon - 1.25)
            }
        }
    }
}

/// A quarter ellipse from the left end of the horizon up to the top of the arc.
struct SunArcShape: Shape {
    let rx: CGFloat
    let ry: CGFloat
    let horizon: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        var first = true
        for step in 0...24 {
            let angle = Double.pi - Double.pi / 2 * Double(step) / 24
            let point = CGPoint(x: cx + rx * CGFloat(cos(angle)), y: horizon - ry * CGFloat(sin(angle)))
            if first { path.move(to: point); first = false } else { path.addLine(to: point) }
        }
        return path
    }
}

// MARK: - Sleep: moon phases

/// Five moons from a thin crescent to full. Each lights up in turn.
struct MoonPhasesMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        MeterItemRow(count: 5, progress: progress, spacing: 4) { index, fill in
            let lit = Double(index + 1) / 5
            GeometryReader { proxy in
                let d = min(proxy.size.width, proxy.size.height) * 0.86
                ZStack {
                    Circle().meterGhost(color, lineWidth: 1.2)
                    Circle()
                        .meterGloss(color)
                        .mask {
                            // The lit part: the disc minus a shadow disc sliding off to the left.
                            ZStack {
                                Circle()
                                if lit < 1 {
                                    Circle()
                                        .offset(x: -d * CGFloat(lit) * 1.0)
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                        }
                        .opacity(fill)
                }
                .frame(width: d, height: d)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

// MARK: - Reading: book spines

/// Six book spines of different heights; each slides up into place as it's read.
struct BookshelfMeter: View {
    let progress: Double
    let color: Color

    private let heights: [CGFloat] = [0.86, 1, 0.74, 0.94, 0.8, 0.9]
    private let shades: [Double] = [1, 0.72, 0.88, 0.62, 0.95, 0.78]

    var body: some View {
        MeterItemRow(count: heights.count, progress: progress, spacing: 3) { index, fill in
            GeometryReader { proxy in
                let spine = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                MeterReveal(fill: fill, axis: .vertical) {
                    spine.meterGhost(color, lineWidth: 1.2)
                } filled: {
                    ZStack {
                        spine.meterGloss(color.opacity(shades[index]))
                        // Bands near the top and bottom of the spine.
                        VStack {
                            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1.5)
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1.5)
                        }
                        .padding(.vertical, proxy.size.height * 0.16)
                    }
                }
                .frame(height: proxy.size.height * heights[index])
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

// MARK: - Custom: stars

/// Five stars that fill in left to right.
struct StarsMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        MeterItemRow(count: 5, progress: progress, spacing: 4) { _, fill in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                MeterReveal(fill: fill) {
                    Image(systemName: "star")
                        .font(.system(size: side * 0.8, weight: .bold))
                        .foregroundStyle(color.opacity(0.45))
                } filled: {
                    Image(systemName: "star.fill")
                        .font(.system(size: side * 0.8, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: color.opacity(0.4), radius: 2, y: 1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}
