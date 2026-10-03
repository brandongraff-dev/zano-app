// ZanoMascot.swift
// Core / UI / Components
//
// Pass 2 "playful" (docs/design/visual-direction-v2.md, "Pass 2: playful"): the ZANO star is a
// character. It has no face; it acts through its body: tilt, squash and stretch, glow, and sparks
// that orbit it. Four moods, one per state of the day:
//
//   * `.sleepy`  — locked and nothing done yet: droops 12° to the side, breathes slowly (a gentle
//                  vertical squash), sits a little low and dim, two faint bubbles drift up.
//   * `.idle`    — nothing at stake (no lock, nothing done): upright, a slow sway.
//   * `.perky`   — some goals done: hops in place with squash-and-stretch, and a spark in each done
//                  goal's colour orbits it. The star literally collects your colours.
//   * `.charged` — everything done: a bright glow, a faster hop, a happy wiggle every few seconds and
//                  a full ring of sparks.
//
// Plus two one-shot beats, each fired by bumping an `Int`:
//
//   * `jump`  — a goal completed: crouch, leap, stretch at the apex, squash on landing, settle.
//   * `spin`  — the star was poked: a little wind-up, then one full turn.
//
// Why a modifier and not only a `ZanoLivingMark` parameter: on a device Today's star is drawn by the
// `ZANOReport` extension (screen time is only readable there, spec §27), in another process that
// knows nothing about goals. The mood motion therefore wraps whatever star view the app has (the
// report view, or `ZanoLivingMark` itself) from the outside; transforms and the sparks/glow layer
// apply the same either way. `ZanoLivingMark(mood:)` additionally dims/brightens its own metal when
// it is drawn in-process.
//
// Reduce Motion: no hop, wiggle, jump or spin; the mood still shows as a still pose (the sleepy tilt
// and dimness, the glow, sparks parked in place). Everything pauses when the scene is not active.
// Decorative: the sparks and glow are hidden from VoiceOver and never take touches.

import SwiftUI

/// The star's mood. Derive it with `init(done:total:isLocked:)` so every screen agrees.
public enum ZanoMascotMood: Sendable, Equatable, CaseIterable {
    case sleepy
    case idle
    case perky
    case charged

    /// - Parameters:
    ///   - done: Goals done (of the ones that matter on this screen: the lock's required goals while
    ///     locked, otherwise today's goals).
    ///   - total: How many goals that is.
    ///   - isLocked: A lock is running. Only a locked star with nothing done is sleepy; an unlocked
    ///     one with nothing done is just idle.
    public init(done: Int, total: Int, isLocked: Bool) {
        if total <= 0 {
            self = .idle
        } else if done >= total {
            self = .charged
        } else if done <= 0 {
            self = isLocked ? .sleepy : .idle
        } else {
            self = .perky
        }
    }

    /// How bright the star's own glow is in this mood (multiplies `ZanoLivingMark`'s glow).
    var glowFactor: Double {
        switch self {
        case .sleepy: 0.45
        case .idle: 0.8
        case .perky: 1.0
        case .charged: 1.35
        }
    }
}

extension View {
    /// Makes this view (the star) act out `mood`, jump when `jump` changes and spin when `spin`
    /// changes. See the file header.
    ///
    /// - Parameters:
    ///   - mood: The standing mood.
    ///   - jump: Bump on a goal completion.
    ///   - spin: Bump when the star is tapped.
    ///   - sparkColors: The orbiting sparks' colours (the done goals' colours). Empty uses
    ///     `Theme.Colors.confetti`.
    ///   - size: The star's height in points (scales the hop, the orbit and the glow).
    ///   - showsGlow: Draw the mood's halo behind the star. Defaults to `true`.
    ///   - glowColor: The halo's colour. `nil` (the default) picks it from the mood; a buddy hero
    ///     passes its buddy's signature colour (the per-buddy theme, 2026-10-03).
    public func zanoMascot(
        mood: ZanoMascotMood,
        jump: Int = 0,
        spin: Int = 0,
        sparkColors: [Color] = [],
        size: CGFloat,
        showsGlow: Bool = true,
        glowColor: Color? = nil
    ) -> some View {
        modifier(ZanoMascotModifier(
            mood: mood,
            jump: jump,
            spin: spin,
            sparkColors: sparkColors.isEmpty ? Theme.Colors.confetti : sparkColors,
            size: size,
            showsGlow: showsGlow,
            glowTint: glowColor
        ))
    }
}

// MARK: - Modifier

private struct JumpPose: Sendable {
    var y: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
}

struct ZanoMascotModifier: ViewModifier {
    let mood: ZanoMascotMood
    let jump: Int
    let spin: Int
    let sparkColors: [Color]
    let size: CGFloat
    let showsGlow: Bool
    /// Overrides the mood's halo colour (a buddy's signature colour).
    var glowTint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        posed(content)
            .background { aura }
    }

    // MARK: Body language

    @ViewBuilder
    private func posed(_ content: Content) -> some View {
        if reduceMotion {
            content
                .modifier(MascotPose(pose: MascotPose.still(mood: mood, size: size)))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
                content
                    .modifier(MascotPose(pose: MascotPose.at(
                        time: context.date.timeIntervalSinceReferenceDate,
                        mood: mood,
                        size: size
                    )))
            }
            .modifier(MascotJump(trigger: jump, size: size))
            .modifier(MascotSpin(trigger: spin))
        }
    }

    // MARK: Glow and sparks

    @ViewBuilder
    private var aura: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(glowStrength), glowColor.opacity(0)],
                            center: .center,
                            startRadius: size * 0.1,
                            endRadius: size * 1.05
                        )
                    )
                    .frame(width: size * 2.1, height: size * 2.1)
            }
            if reduceMotion {
                MascotSparks(mood: mood, colors: sparkColors, size: size, time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
                    MascotSparks(mood: mood, colors: sparkColors, size: size, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var glowColor: Color {
        if let glowTint { return glowTint }
        return switch mood {
        case .sleepy: Theme.Colors.lockedAmbient
        case .idle: Theme.Colors.Aurora.violet
        case .perky: sparkColors.first ?? Theme.Colors.Aurora.violet
        case .charged: Theme.Colors.accent
        }
    }

    private var glowStrength: Double {
        switch mood {
        case .sleepy: 0.45
        case .idle: 0.22
        case .perky: 0.3
        case .charged: 0.5
        }
    }
}

// MARK: - Continuous pose

/// Where the star is at a moment: lean, squash/stretch, lift and how lit it is.
struct MascotPose: ViewModifier {
    struct Pose: Equatable {
        var tilt: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var lift: CGFloat = 0
        var opacity: Double = 1
    }

    let pose: Pose

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
            .offset(y: -pose.lift)
            .opacity(pose.opacity)
    }

    /// The Reduce Motion pose: the mood as a still.
    static func still(mood: ZanoMascotMood, size: CGFloat) -> Pose {
        switch mood {
        case .sleepy: Pose(tilt: -12, lift: -size * 0.04, opacity: 0.78)
        case .idle, .perky: Pose()
        case .charged: Pose(scaleX: 1.03, scaleY: 1.03)
        }
    }

    static func at(time t: Double, mood: ZanoMascotMood, size: CGFloat) -> Pose {
        switch mood {
        case .sleepy:
            // Slow breathing: a 4.5s vertical squash, a lazy sway around a 12° droop.
            let breath: Double = 0.5 + 0.5 * sin(t * 2 * .pi / 4.5)
            let sway: Double = sin(t * 2 * .pi / 6) * 2
            return Pose(
                tilt: -12 + sway,
                scaleX: CGFloat(1 + 0.015 * breath),
                scaleY: CGFloat(1 - 0.035 * breath),
                lift: -size * 0.04,
                opacity: 0.78
            )
        case .idle:
            return Pose(tilt: sin(t * 2 * .pi / 5) * 3)
        case .perky:
            return hop(time: t, period: Theme.Motion.mascotHopPeriod, height: size * 0.07, tilt: sin(t * 2 * .pi / 3) * 4)
        case .charged:
            var pose = hop(time: t, period: Theme.Motion.mascotHopPeriod * 0.75, height: size * 0.09, tilt: 0)
            // A happy wiggle for the first 0.6s of every period, decaying.
            let w: Double = t.truncatingRemainder(dividingBy: Theme.Motion.mascotWigglePeriod)
            if w < 0.6 {
                let decay: Double = 1 - w / 0.6
                pose.tilt = sin(w / 0.6 * .pi * 4) * 9 * decay
            }
            pose.scaleX *= 1.03
            pose.scaleY *= 1.03
            return pose
        }
    }

    /// One squash-and-stretch hop: up on a sine, stretched on the way up, squashed on landing.
    private static func hop(time t: Double, period: Double, height: CGFloat, tilt: Double) -> Pose {
        let phase: Double = t.truncatingRemainder(dividingBy: period) / period
        let s: Double = sin(phase * .pi)              // 0 on the ground, 1 at the top
        let squash: Double = pow(1 - s, 6)            // only near the landing
        let scaleX = CGFloat(1 - 0.025 * s + 0.06 * squash)
        let scaleY = CGFloat(1 + 0.04 * s - 0.07 * squash)
        return Pose(tilt: tilt, scaleX: scaleX, scaleY: scaleY, lift: height * CGFloat(s), opacity: 1)
    }
}

// MARK: - One-shot beats

/// Crouch, leap, stretch at the apex, squash on landing, settle.
private struct MascotJump: ViewModifier {
    let trigger: Int
    let size: CGFloat

    func body(content: Content) -> some View {
        // Plain values: the keyframe closures are `@Sendable`.
        let leap = size * 0.42
        return content.keyframeAnimator(initialValue: JumpPose(), trigger: trigger) { view, pose in
            view
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                .offset(y: pose.y)
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                CubicKeyframe(0, duration: 0.12)
                SpringKeyframe(-leap, duration: 0.3, spring: .snappy)
                CubicKeyframe(-leap * 0.95, duration: 0.08)
                CubicKeyframe(0, duration: 0.18)
                CubicKeyframe(0, duration: 0.22)
            }
            KeyframeTrack(\.scaleY) {
                CubicKeyframe(0.84, duration: 0.12)
                CubicKeyframe(1.14, duration: 0.16)
                CubicKeyframe(1.0, duration: 0.22)
                CubicKeyframe(0.88, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
            KeyframeTrack(\.scaleX) {
                CubicKeyframe(1.12, duration: 0.12)
                CubicKeyframe(0.9, duration: 0.16)
                CubicKeyframe(1.0, duration: 0.22)
                CubicKeyframe(1.1, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
        }
    }
}

/// A little wind-up, then one full turn that overshoots and settles.
private struct MascotSpin: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
            view.rotationEffect(.degrees(angle))
        } keyframes: { _ in
            CubicKeyframe(-25, duration: 0.14)
            SpringKeyframe(370, duration: 0.42, spring: .snappy)
            SpringKeyframe(360, duration: 0.14, spring: .bouncy)
        }
    }
}

// MARK: - Sparks

/// Sparks orbiting the star on a tilted ellipse (bigger and brighter on the near side), or, for a
/// sleepy star, two faint bubbles drifting up.
private struct MascotSparks: View {
    let mood: ZanoMascotMood
    let colors: [Color]
    let size: CGFloat
    let time: Double

    private var count: Int {
        switch mood {
        case .sleepy: 2
        case .idle: 0
        case .perky: min(max(colors.count, 2), 4)
        case .charged: 6
        }
    }

    private var period: Double { mood == .charged ? 3.2 : 5 }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                if mood == .sleepy {
                    bubble(index)
                } else {
                    spark(index)
                }
            }
        }
        .frame(width: size * 2, height: size * 1.6)
    }

    private func spark(_ index: Int) -> some View {
        let spacing: Double = 2 * .pi / Double(max(count, 1))
        let angle: Double = time * 2 * .pi / period + Double(index) * spacing
        let depth: Double = (sin(angle) + 1) / 2        // 0 far, 1 near
        let boost: Double = mood == .charged ? 1.2 : 1
        let sparkSize = CGFloat((0.09 + 0.06 * depth) * boost) * size
        let x = CGFloat(cos(angle)) * size * 0.95
        let y = CGFloat(sin(angle)) * size * 0.32 + size * 0.1
        let color = colors[index % colors.count]
        return ZanoSparkleShape()
            .fill(color)
            .frame(width: sparkSize, height: sparkSize)
            .shadow(color: color.opacity(0.8), radius: 4)
            .rotationEffect(.radians(angle))
            .opacity(0.45 + 0.55 * depth)
            .offset(x: x, y: y)
    }

    private func bubble(_ index: Int) -> some View {
        let period = 3.6
        let phase: Double = (time / period + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
        let bubbleSize = CGFloat(0.05 + 0.04 * Double(index)) * size
        let fade: Double = time == 0 ? 0.5 : sin(phase * .pi) * 0.7
        let drift = CGFloat(sin(phase * 2 * .pi) * 0.04)
        let x = (CGFloat(0.55 + 0.12 * Double(index)) + drift) * size
        let y = -CGFloat(0.15 + 0.5 * phase) * size
        return Circle()
            .strokeBorder(Theme.Colors.textSecondary.opacity(0.6), lineWidth: 1.5)
            .frame(width: bubbleSize, height: bubbleSize)
            .opacity(fade)
            .offset(x: x, y: y)
    }
}

#Preview("Mascot moods") {
    struct Demo: View {
        @State private var jump = 0
        @State private var spin = 0
        var body: some View {
            VStack(spacing: Theme.Spacing.xl) {
                HStack(spacing: Theme.Spacing.xl) {
                    ForEach(ZanoMascotMood.allCases, id: \.self) { mood in
                        ZanoLivingMark(charge: 0.6, height: 44, mood: mood)
                            .zanoMascot(
                                mood: mood,
                                jump: jump,
                                spin: spin,
                                sparkColors: [Theme.Colors.Ring.protein, Theme.Colors.Ring.workout],
                                size: 44
                            )
                    }
                }
                HStack {
                    Button("Jump") { jump += 1 }
                    Button("Spin") { spin += 1 }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zanoAmbient(.progress(0.5))
        }
    }
    return Demo().preferredColorScheme(.dark)
}
