// UnlockStarStage.swift
// App / Features / Celebration
//
// The centre-stage artwork of the unlock moment (`UnlockCelebrationView`). Pass 2 (2026-10-03,
// "make it more playful"): the star wins an arcade round.
//
//   charge   the star fills with silver and *leaps*: it rises and stretches as the charge
//            accelerates, like a jump being wound up.
//   flash    at the apex it bursts: a blue bloom, a white specular hit, a shockwave ring, and a
//            jackpot sunburst of rays in the goal colours swings open behind it. The star drops
//            back to its spot with a bounce.
//   rest     a fully charged star on a soft bloom, the rays held still, a ring of marquee bulbs
//            (warm sun dots, like the lights around an arcade cabinet) and one fine blue halo.
//
// Everything is driven by two numbers, `charge` (0...1) and `flash` (0...1). Each effect computes
// its own curve from them, so `UnlockCelebrationView` only advances two numbers per frame from a
// `TimelineView`. The resting frame (`flash == 1`, `charge == 1`) is what Reduce Motion shows and
// what CI screenshots capture; nothing in it moves.
//
// Buddies (2026-10-03): the character on the stage is the user's buddy (`BuddySprite`, `.idle` while
// it winds up, `.happy` from the flash on), not the star; it leaps, bursts and lands exactly as the
// star did. The bloom behind it is the buddy's signature colour (the per-buddy theme); the rest of
// the stage (goal-colour rays, sun marquee, blue shockwave and halo) is unchanged.

import SwiftUI
import Core

struct UnlockStarStage: View {
    /// How wound-up the leap is, 0...1 (it was the star's silver fill).
    let charge: Double
    /// Progress through the flash, 0 (before) ... 1 (settled).
    let flash: Double

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    /// The confetti and ray colours: the goal palette, so the win looks like *your* goals.
    static let goalPalette: [Color] = [
        Theme.Colors.Ring.workout,
        Theme.Colors.Ring.protein,
        Theme.Colors.Ring.focus,
        Theme.Colors.Ring.water,
        Theme.Colors.Ring.creatine,
        Theme.Colors.Ring.sunriseAlarm,
    ]

    var body: some View {
        ZStack {
            rays
            marquee
            shockwave
            star
            specular
        }
        .background { bloom }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Pieces

    private var star: some View {
        BuddySprite(buddy, pose: flash > 0 ? .happy : .idle, size: StageMetrics.starHeight)
            .scaleEffect(x: starStretch.x, y: starStretch.y, anchor: .bottom)
            .offset(y: starLift)
    }

    private var specular: some View {
        RadialGradient(
            colors: [Color.white.opacity(0.95), Color.white.opacity(0.35), Color.white.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: StageMetrics.specularRadius
        )
        .frame(width: StageMetrics.specularRadius * 2, height: StageMetrics.specularRadius * 2)
        .scaleEffect(0.6 + 0.6 * specularIntensity)
        .opacity(specularIntensity)
        .offset(y: starLift)
        .blendMode(.plusLighter)
    }

    private var bloom: some View {
        RadialGradient(
            colors: [
                buddy.color.opacity(0.85),
                buddy.color.opacity(0.30),
                buddy.color.opacity(0),
            ],
            center: .center,
            startRadius: 0,
            endRadius: StageMetrics.bloomRadius
        )
        .frame(width: StageMetrics.bloomRadius * 2, height: StageMetrics.bloomRadius * 2)
        .scaleEffect(0.55 + 0.45 * min(1, flash / 0.35))
        .opacity(bloomIntensity)
    }

    /// The jackpot sunburst: alternating wedges in the goal palette, faded out towards the edge.
    private var rays: some View {
        SunburstRays(count: StageMetrics.rayCount)
            .fill(
                AngularGradient(
                    colors: Self.goalPalette + [Self.goalPalette[0]],
                    center: .center
                )
            )
            .mask {
                RadialGradient(
                    colors: [Color.white, Color.white.opacity(0.5), Color.white.opacity(0)],
                    center: .center,
                    startRadius: StageMetrics.starHeight * 0.3,
                    endRadius: StageMetrics.rayRadius
                )
            }
            .frame(width: StageMetrics.rayRadius * 2, height: StageMetrics.rayRadius * 2)
            .rotationEffect(.degrees(-30 + 30 * easeOut(flash)))
            .scaleEffect(0.3 + 0.7 * easeOut(min(1, flash / 0.4)))
            .opacity(rayOpacity)
            .blendMode(.plusLighter)
    }

    /// Marquee bulbs around the star (a dotted ring in sun) and one fine blue halo outside it.
    private var marquee: some View {
        ZStack {
            Circle()
                .stroke(
                    Theme.Colors.Ring.sunriseAlarm.opacity(0.85),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 15])
                )
                .frame(width: StageMetrics.marqueeDiameter, height: StageMetrics.marqueeDiameter)
                .shadow(color: Theme.Colors.Ring.sunriseAlarm.opacity(0.7), radius: 4)
                .rotationEffect(.degrees(40 * flash))
            Circle()
                .stroke(Theme.Colors.accent.opacity(0.28), lineWidth: 1)
                .frame(width: StageMetrics.haloDiameter, height: StageMetrics.haloDiameter)
        }
        .scaleEffect(0.85 + 0.15 * easeOut(min(1, flash / 0.5)))
        .opacity(haloOpacity)
    }

    private var shockwave: some View {
        let travel = 1 - pow(1 - flash, 2.2)
        return ZStack {
            Circle()
                .stroke(Theme.Colors.accent, lineWidth: StageMetrics.shockLine)
                .blur(radius: 6)
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .frame(width: StageMetrics.shockBase, height: StageMetrics.shockBase)
        .scaleEffect(0.35 + (StageMetrics.shockMaxScale - 0.35) * travel)
        .opacity(shockOpacity)
        .offset(y: starLift)
    }

    // MARK: - Curves (pure functions of `charge` and `flash`)

    /// 0 at the starting charge, 1 at full: how wound-up the leap is.
    private var windUp: Double {
        min(1, max(0, (charge - 0.7) / 0.3))
    }

    /// The star rises with the charge, bursts at the apex, then drops back with a bounce.
    private var starLift: CGFloat {
        if flash <= 0 { return -StageMetrics.leapHeight * CGFloat(windUp) }
        let fall = min(1, flash / 0.55)
        return -StageMetrics.leapHeight * CGFloat(1 - bounce(fall))
    }

    /// A little stretch on the way up, a squash on landing, square at rest.
    private var starStretch: (x: CGFloat, y: CGFloat) {
        if flash <= 0 {
            let s = CGFloat(windUp) * 0.06
            return (1 - s, 1 + s)
        }
        // Squash around the first touchdown (fall progress ~0.36 of 0.55).
        let touch = abs(flash - 0.2)
        guard touch < 0.08 else { return (1, 1) }
        let s = CGFloat(1 - touch / 0.08) * 0.08
        return (1 + s, 1 - s)
    }

    private var bloomIntensity: Double {
        if flash <= 0 { return 0.25 * windUp }
        if flash < 0.2 { return 0.25 + 0.75 * flash / 0.2 }
        return 1 - (1 - StageMetrics.restingBloom) * ((flash - 0.2) / 0.8)
    }

    private var specularIntensity: Double {
        if flash <= 0 || flash >= 0.45 { return 0 }
        if flash < 0.12 { return flash / 0.12 }
        return 1 - (flash - 0.12) / 0.33
    }

    private var rayOpacity: Double {
        if flash <= 0 { return 0 }
        if flash < 0.18 { return flash / 0.18 }
        return 1 - (1 - StageMetrics.restingRays) * min(1, (flash - 0.18) / 0.6)
    }

    private var haloOpacity: Double {
        min(1, max(0, (flash - 0.2) / 0.45))
    }

    private var shockOpacity: Double {
        if flash <= 0 || flash >= 1 { return 0 }
        if flash < 0.08 { return flash / 0.08 }
        return 1 - (flash - 0.08) / 0.92
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - min(1, max(0, t)), 3)
    }

    /// Standard ease-out bounce, 0...1.
    private func bounce(_ t: Double) -> Double {
        let n = 7.5625, d = 2.75
        if t < 1 / d { return n * t * t }
        if t < 2 / d { let u = t - 1.5 / d; return n * u * u + 0.75 }
        if t < 2.5 / d { let u = t - 2.25 / d; return n * u * u + 0.9375 }
        let u = t - 2.625 / d
        return n * u * u + 0.984375
    }
}

/// `count` thin wedges radiating from the centre: the jackpot sunburst.
private struct SunburstRays: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let step = 2 * Double.pi / Double(count)
        let half = step * 0.22
        for index in 0..<count {
            let angle = Double(index) * step
            path.move(to: center)
            path.addLine(to: CGPoint(
                x: center.x + radius * CGFloat(cos(angle - half)),
                y: center.y + radius * CGFloat(sin(angle - half))
            ))
            path.addLine(to: CGPoint(
                x: center.x + radius * CGFloat(cos(angle + half)),
                y: center.y + radius * CGFloat(sin(angle + half))
            ))
            path.closeSubpath()
        }
        return path
    }
}

/// Sizes for the stage artwork, which has no `Theme.Metrics` home.
enum StageMetrics {
    /// The buddy's size (square): 4x its 32px grid, so the pixels stay crisp.
    static let starHeight: CGFloat = 128
    /// The stage's layout height. The bloom and rays may draw past it.
    static let stageHeight: CGFloat = 260
    /// How high the star leaps before it bursts.
    static let leapHeight: CGFloat = 34
    static let bloomRadius: CGFloat = 190
    static let restingBloom: Double = 0.45
    static let specularRadius: CGFloat = 70
    static let shockBase: CGFloat = 180
    static let shockLine: CGFloat = 3
    static let shockMaxScale: CGFloat = 2.6
    static let rayCount = 16
    static let rayRadius: CGFloat = 200
    static let restingRays: Double = 0.35
    static let marqueeDiameter: CGFloat = 220
    static let haloDiameter: CGFloat = 268
}

#Preview("Stage — resting") {
    UnlockStarStage(charge: 1, flash: 1)
        .frame(height: StageMetrics.stageHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("Stage — mid-burst") {
    UnlockStarStage(charge: 1, flash: 0.15)
        .frame(height: StageMetrics.stageHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
