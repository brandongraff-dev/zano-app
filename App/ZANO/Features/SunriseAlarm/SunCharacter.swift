// SunCharacter.swift
// App / Features / SunriseAlarm
//
// docs/spec.md §5.10 (Sunrise Alarm). The retro striped sun (`RetroSun`) with a face that reacts to
// what is happening: asleep on the setup screen, yawning -> alarmed -> frantic as an alarm goes
// unanswered, grumpy / disappointed after a snooze, hopeful while the tag is being scanned, worried
// during the escape-hatch hold, beaming on a verified dismiss, sad when the emergency exit is used.
//
// Decoration only: the face never carries information the rest of the screen doesn't (the phase
// chip, the headline and the controls say it all), so it is hidden from VoiceOver and never sits over
// a control. Reduce Motion: every mood is a still face; the callers' shake/breathe is gated on it.
//
// Local to this feature on purpose (CLAUDE.md: no shared abstraction until a second feature needs
// one). The star buddy in `ZanoMascot.swift` is a different character with its own four moods.

import SwiftUI
import Core

enum SunMood: Equatable, CaseIterable {
    case asleep
    case yawning
    case alarmed
    case frantic
    case grumpy
    case disappointed
    case hopeful
    case beaming
    case worried
    case sad

    /// Gradient stops, top to bottom. Calm moods use the app's sun -> ember -> pink; tense moods run
    /// hotter, let-down moods go muted.
    var colors: [Color] {
        switch self {
        case .asleep, .yawning, .hopeful:
            [Theme.Colors.Ring.sunriseAlarm, Theme.Colors.ember, Theme.Colors.Ring.creatine]
        case .beaming:
            [SunMood.hex(0xFFE066), SunMood.hex(0xFFA040), Theme.Colors.Ring.creatine]
        case .alarmed:
            [Theme.Colors.warning, SunMood.hex(0xFF7A2D), SunMood.hex(0xFF5C7A)]
        case .frantic:
            [SunMood.hex(0xFF6A4A), Theme.Colors.danger, SunMood.hex(0xC2307A)]
        case .grumpy:
            [SunMood.hex(0xE0A840), SunMood.hex(0xC9703A), SunMood.hex(0xA8507A)]
        case .disappointed, .worried:
            [SunMood.hex(0xB79A56), SunMood.hex(0x9A6A48), SunMood.hex(0x7E4C6E)]
        case .sad:
            [SunMood.hex(0x8F8A9A), SunMood.hex(0x7A6E86), SunMood.hex(0x5E4F78)]
        }
    }

    /// The phase's urgency as a tint for the glow and chip when no phase is driving (setup, overlay).
    var glow: Color { colors[1] }

    fileprivate static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The sun disc with its mood's colours and face. `pulse` is the caller's existing alarm pulse
/// (`isPulsing`); it drives a small shake on the tense moods and a slow breath on the sleepy ones.
/// Pass `animated: false` (Reduce Motion) for a still face.
struct SunCharacter: View {
    let mood: SunMood
    var pulse: Bool = false
    var animated: Bool = true
    /// The faint disc behind the sun. Off where the sun is clipped to a horizon: the disc is wider
    /// than the sun, so the clip left it with flat vertical edges.
    var halo: Bool = true

    var body: some View {
        ZStack {
            if halo {
                Circle()
                    .fill(mood.glow.opacity(0.18))
                    .scaleEffect(1.12)
            }

            RetroSun(tint: mood.colors[0], colors: mood.colors)

            SunFace(mood: mood)
                .id(mood)
                .transition(.opacity)
        }
        .rotationEffect(.degrees(animated ? shake : 0))
        .scaleEffect(animated ? breath : 1)
        .animation(animated ? Animation.easeInOut(duration: 0.4) : nil, value: mood)
        .accessibilityHidden(true)
    }

    private var shake: Double {
        switch mood {
        case .frantic: pulse ? 4 : -4
        case .alarmed: pulse ? 2 : -2
        default: 0
        }
    }

    private var breath: CGFloat {
        switch mood {
        case .asleep: pulse ? 1.02 : 0.98
        default: 1
        }
    }
}

/// The face, drawn in a 200 x 200 space scaled to the view. Features live in the solid upper half;
/// the sun's slits start at y = 104, so nothing is cut by them.
private struct SunFace: View {
    let mood: SunMood

    var body: some View {
        let mood = mood
        Canvas { ctx, size in
            let scale = size.width / 200
            ctx.scaleBy(x: scale, y: scale)
            FaceArt.draw(mood, in: &ctx)
        }
    }
}

/// The drawing itself, in a plain type so the `Canvas` renderer (not main-actor isolated) can call it.
private enum FaceArt {
    static let ink = Color(red: 0.10, green: 0.07, blue: 0.19)
    private static let blush = Color(red: 1, green: 0.44, blue: 0.68)
    private static let drop = Color(red: 0.5, green: 0.83, blue: 1)

    static func draw(_ mood: SunMood, in ctx: inout GraphicsContext) {
        switch mood {
        case .asleep:
            curve(&ctx, (58, 72), (72, 82), (86, 72), width: 6)
            curve(&ctx, (114, 72), (128, 82), (142, 72), width: 6)
            curve(&ctx, (88, 94), (100, 100), (112, 94), width: 5)
            label(&ctx, "z", at: (150, 40), size: 26)
            label(&ctx, "z", at: (168, 22), size: 18)

        case .yawning:
            curve(&ctx, (58, 70), (72, 60), (86, 70), width: 6)
            curve(&ctx, (114, 70), (128, 60), (142, 70), width: 6)
            ctx.fill(Path(ellipseIn: CGRect(x: 87, y: 86, width: 26, height: 20)), with: .color(FaceArt.ink))
            ctx.fill(Path(ellipseIn: CGRect(x: 93, y: 97, width: 14, height: 8)), with: .color(FaceArt.blush))

        case .alarmed:
            eyes(&ctx, y: 68, radius: 13, pupil: 6, pupilDY: 2)
            line(&ctx, (58, 48), (84, 54), width: 5)
            line(&ctx, (142, 48), (116, 54), width: 5)
            ctx.fill(Path(ellipseIn: CGRect(x: 91, y: 87, width: 18, height: 16)), with: .color(FaceArt.ink))
            sweat(&ctx, at: (164, 56))

        case .frantic:
            eyes(&ctx, y: 66, radius: 15, pupil: 3.5, pupilDY: 0)
            line(&ctx, (56, 42), (84, 52), width: 6)
            line(&ctx, (144, 42), (116, 52), width: 6)
            var zig = Path()
            zig.move(to: CGPoint(x: 72, y: 94))
            for i in 1...8 {
                zig.addLine(to: CGPoint(x: 72 + Double(i) * 7, y: i.isMultiple(of: 2) ? 94 : 86))
            }
            ctx.stroke(zig, with: .color(FaceArt.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            sweat(&ctx, at: (160, 52))
            sweat(&ctx, at: (38, 60))

        case .grumpy:
            line(&ctx, (56, 72), (84, 72), width: 6)
            line(&ctx, (116, 72), (144, 72), width: 6)
            line(&ctx, (54, 56), (84, 64), width: 6)
            line(&ctx, (146, 56), (116, 64), width: 6)
            curve(&ctx, (84, 98), (100, 86), (116, 98), width: 5)
            label(&ctx, "zZ", at: (146, 40), size: 22)

        case .disappointed:
            dots(&ctx, y: 72, radius: 7)
            line(&ctx, (56, 58), (84, 54), width: 5)
            line(&ctx, (144, 58), (116, 54), width: 5)
            line(&ctx, (84, 96), (116, 96), width: 5)

        case .hopeful:
            eyes(&ctx, y: 68, radius: 12, pupil: 6, pupilDY: -6, pupilDX: 2)
            curve(&ctx, (82, 92), (100, 102), (118, 92), width: 5)
            line(&ctx, (52, 50), (46, 42), width: 4, color: .white)
            line(&ctx, (148, 50), (154, 42), width: 4, color: .white)

        case .beaming:
            curve(&ctx, (56, 74), (72, 54), (88, 74), width: 6)
            curve(&ctx, (112, 74), (128, 54), (144, 74), width: 6)
            var mouth = Path()
            mouth.move(to: CGPoint(x: 74, y: 88))
            mouth.addQuadCurve(to: CGPoint(x: 126, y: 88), control: CGPoint(x: 100, y: 114))
            mouth.closeSubpath()
            ctx.fill(mouth, with: .color(FaceArt.ink))
            var tongue = Path()
            tongue.move(to: CGPoint(x: 84, y: 100))
            tongue.addQuadCurve(to: CGPoint(x: 116, y: 100), control: CGPoint(x: 100, y: 110))
            tongue.closeSubpath()
            ctx.fill(tongue, with: .color(FaceArt.blush))
            ctx.fill(Path(ellipseIn: CGRect(x: 45, y: 81, width: 18, height: 18)), with: .color(FaceArt.blush.opacity(0.55)))
            ctx.fill(Path(ellipseIn: CGRect(x: 137, y: 81, width: 18, height: 18)), with: .color(FaceArt.blush.opacity(0.55)))

        case .worried:
            dots(&ctx, y: 72, radius: 8)
            // Inner ends high: anxious, not angry.
            line(&ctx, (56, 62), (84, 52), width: 5)
            line(&ctx, (144, 62), (116, 52), width: 5)
            curve(&ctx, (82, 98), (100, 90), (118, 98), width: 5)
            sweat(&ctx, at: (160, 60))

        case .sad:
            dots(&ctx, y: 74, radius: 7)
            line(&ctx, (56, 66), (84, 58), width: 5)
            line(&ctx, (144, 66), (116, 58), width: 5)
            curve(&ctx, (84, 100), (100, 88), (116, 100), width: 5)
            sweat(&ctx, at: (66, 84))
        }
    }

    // MARK: Primitives

    private static func line(_ ctx: inout GraphicsContext, _ a: (Double, Double), _ b: (Double, Double), width: Double, color: Color = FaceArt.ink) {
        var path = Path()
        path.move(to: CGPoint(x: a.0, y: a.1))
        path.addLine(to: CGPoint(x: b.0, y: b.1))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func curve(_ ctx: inout GraphicsContext, _ a: (Double, Double), _ control: (Double, Double), _ b: (Double, Double), width: Double) {
        var path = Path()
        path.move(to: CGPoint(x: a.0, y: a.1))
        path.addQuadCurve(to: CGPoint(x: b.0, y: b.1), control: CGPoint(x: control.0, y: control.1))
        ctx.stroke(path, with: .color(FaceArt.ink), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func dots(_ ctx: inout GraphicsContext, y: Double, radius: Double) {
        for x in [72.0, 128.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(FaceArt.ink))
        }
    }

    /// White eyes with pupils. `pupilDX` mirrors on the right eye so both look the same way.
    private static func eyes(_ ctx: inout GraphicsContext, y: Double, radius: Double, pupil: Double, pupilDY: Double, pupilDX: Double = 0) {
        for (x, dx) in [(72.0, pupilDX), (128.0, pupilDX)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.white))
            let cx = x + dx
            let cy = y + pupilDY
            ctx.fill(Path(ellipseIn: CGRect(x: cx - pupil, y: cy - pupil, width: pupil * 2, height: pupil * 2)), with: .color(FaceArt.ink))
        }
    }

    private static func sweat(_ ctx: inout GraphicsContext, at p: (Double, Double)) {
        var path = Path()
        path.move(to: CGPoint(x: p.0, y: p.1))
        path.addQuadCurve(to: CGPoint(x: p.0, y: p.1 + 14), control: CGPoint(x: p.0 + 8, y: p.1 + 6))
        path.addQuadCurve(to: CGPoint(x: p.0, y: p.1), control: CGPoint(x: p.0 - 8, y: p.1 + 6))
        ctx.fill(path, with: .color(FaceArt.drop))
    }

    private static func label(_ ctx: inout GraphicsContext, _ text: String, at p: (Double, Double), size: Double) {
        ctx.draw(
            Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.85)),
            at: CGPoint(x: p.0, y: p.1)
        )
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 16) {
            ForEach(SunMood.allCases, id: \.self) { mood in
                SunCharacter(mood: mood, animated: false)
                    .frame(width: 120, height: 120)
            }
        }
        .padding()
    }
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
