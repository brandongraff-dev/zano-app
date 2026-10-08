// BodyMeters.swift
// Core / UI / Components / GoalMeters
//
// The body meters: workout (a barbell), steps (footprints), stretch (a resistance band) and cold
// shower / sauna (a thermometer). See ZanoGoalMeter.swift for the family.

import SwiftUI

// MARK: - Workout: barbell

/// A barbell with five plate slots a side. Plate pairs load from the middle out, biggest first.
struct BarbellMeter: View {
    let progress: Double
    let color: Color

    private let plates = 5

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let plateW = max(4, min(9, w * 0.055))
            let gap: CGFloat = 2
            let collarW: CGFloat = 4
            let step = plateW + gap
            // Half the grip: whatever is left once both sides' plates and collars fit.
            let grip = max(6, w / 2 - (CGFloat(plates) * step + collarW + 6))
            ZStack {
                // The bar, end to end.
                Capsule()
                    .fill(Theme.Colors.textSecondary.opacity(0.7))
                    .frame(height: max(3, h * 0.13))
                // Knurled grip in the middle.
                Capsule()
                    .fill(Theme.Colors.textSecondary)
                    .frame(width: max(0, 2 * grip - 4), height: max(4, h * 0.2))
                ForEach(0..<plates, id: \.self) { index in
                    let fill = MeterItemRow<EmptyView>.fill(index: index, count: plates, progress: progress)
                    let plateH = h * (1 - CGFloat(index) * 0.11)
                    let x = w / 2 - grip - CGFloat(index) * step - plateW / 2
                    plate(fill: fill, width: plateW, height: plateH)
                        .position(x: x, y: h / 2)
                    plate(fill: fill, width: plateW, height: plateH)
                        .position(x: w - x, y: h / 2)
                }
                // Collars just outside the last plate slot.
                let collarX = w / 2 - grip - CGFloat(plates) * step - collarW / 2
                ForEach([collarX, w - collarX], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.Colors.textSecondary)
                        .frame(width: collarW, height: h * 0.36)
                        .position(x: x, y: h / 2)
                }
            }
        }
    }

    private func plate(fill: Double, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return MeterReveal(fill: fill, axis: .vertical) {
            shape.meterGhost(color, lineWidth: 1.2)
        } filled: {
            shape.meterGloss(color)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Steps: footprints

/// Eight footprints walking to the right, left and right feet alternating.
struct FootprintsMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        MeterItemRow(count: 8, progress: progress, spacing: 2) { index, fill in
            let isLeft = index.isMultiple(of: 2)
            GeometryReader { proxy in
                MeterReveal(fill: fill) {
                    FootprintShape().fill(color.opacity(0.22))
                } filled: {
                    FootprintShape().meterGloss(color)
                }
                .frame(width: proxy.size.width, height: proxy.size.height * 0.5)
                .scaleEffect(x: 1, y: isLeft ? 1 : -1)
                .offset(y: proxy.size.height * (isLeft ? 0.02 : 0.48))
            }
        }
    }
}

/// A footprint pointing right: the sole, the heel and four toes.
struct FootprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        // Heel.
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY + h * 0.3, width: w * 0.34, height: h * 0.5))
        // Ball of the foot.
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.26, y: rect.minY + h * 0.22, width: w * 0.46, height: h * 0.66))
        // Toes, biggest at the top.
        let toes: [(x: CGFloat, y: CGFloat, d: CGFloat)] = [(0.74, 0.12, 0.26), (0.84, 0.36, 0.2), (0.84, 0.58, 0.18), (0.76, 0.78, 0.16)]
        for toe in toes {
            let d = min(w, h) * toe.d * 1.6
            path.addEllipse(in: CGRect(x: rect.minX + w * toe.x, y: rect.minY + h * toe.y, width: d, height: d))
        }
        return path
    }
}

// MARK: - Stretch: resistance band

/// A resistance band pulled from a handle on the left toward a target on the right. It gets
/// longer and thinner as it stretches.
struct StretchBandMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let handleW: CGFloat = 8
            let minBand = w * 0.18
            let bandEnd = handleW + minBand + (w - 2 * handleW - minBand) * progress
            let thickness = 9 - 5 * progress
            ZStack(alignment: .leading) {
                // Where the band has to reach.
                Capsule()
                    .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))
                    .frame(width: w - handleW, height: 6)
                    .offset(x: handleW / 2)
                // The band.
                Capsule()
                    .meterGloss(color.opacity(0.85))
                    .frame(width: max(0, bandEnd - handleW / 2), height: thickness)
                    .offset(x: handleW / 2)
                handle(height: h * 0.8)
                handle(height: h * 0.8)
                    .offset(x: bandEnd - handleW / 2)
                // The target post.
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(progress >= 1 ? 1 : 0.4))
                    .frame(width: 2, height: h)
                    .offset(x: w - 2)
            }
            .frame(height: h)
        }
    }

    private func handle(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .meterGloss(color)
            .frame(width: 8, height: height)
    }
}

// MARK: - Cold shower / sauna: thermometer

/// A thermometer on its side: the bulb on the left, the tube filling to the right, a snowflake at
/// the end that lights up when it's done.
struct ThermometerMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let bulb = h * 0.82
            let flake = h * 0.8
            let tubeH = h * 0.38
            let tubeW = max(0, w - bulb - flake - 4)
            HStack(spacing: 0) {
                Circle()
                    .meterGloss(progress > 0 ? color : color.opacity(0.3))
                    .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
                    .frame(width: bulb, height: bulb)
                ZStack(alignment: .leading) {
                    Capsule().meterGhost(color, lineWidth: 1.3)
                    Capsule()
                        .meterGloss(color)
                        .frame(width: max(progress > 0 ? tubeH : 0, tubeW * progress))
                    // Tick marks.
                    HStack(spacing: 0) {
                        ForEach(1..<5, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: tubeH * 0.45)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: tubeW, height: tubeH)
                .offset(x: -2)
                Image(systemName: "snowflake")
                    .font(.system(size: flake * 0.75, weight: .heavy))
                    .foregroundStyle(color.opacity(progress >= 1 ? 1 : 0.4))
                    .frame(width: flake + 4)
            }
            .frame(width: w, height: h)
        }
    }
}
