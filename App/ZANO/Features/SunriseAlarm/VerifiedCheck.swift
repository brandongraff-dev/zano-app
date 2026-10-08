// VerifiedCheck.swift
// App / Features / SunriseAlarm
//
// docs/spec.md §5.10 point 4 ("Tapping the tag = alarm off + morning goal verified") and §15
// ("haptics on every verified event"). The "you're up" moment's check mark, drawn the way Apple's own
// confirmations (Apple Pay "Done", Face ID success) are drawn:
//   1. a ring draws itself clockwise from 12 o'clock (ease-in-out, 0.55s),
//   2. the check strokes in inside it (ease-out, 0.32s), starting as the ring closes,
//   3. the whole mark pops once (spring overshoot) and the success haptic fires with it,
//   4. a soft fill of the mark's colour fades in behind it as it lands.
// Total animated time is about 1.1s, inside spec §15's "unlock celebration <= 1.2s".
//
// Reduce Motion: the finished mark appears at once (no draw, no pop). The haptic still fires: it is
// the confirmation the user is waiting for, and it is not motion.

import SwiftUI
import Core

struct VerifiedCheck: View {
    var size: CGFloat = 120
    var color: Color = Theme.Colors.Ring.workout
    var lineWidth: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @State private var fillOpacity: Double = 0
    @State private var scale: CGFloat = 1
    @State private var landed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .opacity(fillOpacity)

            Circle()
                .trim(from: 0, to: ring)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            CheckStroke()
                .trim(from: 0, to: check)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth + 1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .sensoryFeedback(.success, trigger: landed)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            ring = 1
            check = 1
            fillOpacity = 1
            landed = true
            return
        }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.55)) { ring = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) { check = 1 }
        try? await Task.sleep(for: .milliseconds(280))
        landed = true
        withAnimation(.easeOut(duration: 0.3)) { fillOpacity = 1 }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { scale = 1.1 }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { scale = 1 }
    }
}

/// The check's two strokes as one open path, so `trim` draws it as a single continuous line.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
        return path
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        VerifiedCheck()
    }
    .preferredColorScheme(.dark)
}
