// CelebrationBurst.swift
// Core / UI / Components
//
// A lightweight, self-contained particle/confetti burst, per docs/spec.md §16's P3 mockup ("burst
// of acid-green particles") and §8 rule 4 (variable reward: "1 in ~6 unlocks triggers a surprise
// [...] Keep it tasteful"). Pure SwiftUI — no external animation library: `docs/dependencies.md`
// lists Lottie as planned for "Session 5 or 9 (first celebration animation)" but it is not yet
// added to `project.yml`, so this file cannot depend on it (per this task's brief). Every
// particle's motion is derived from a single animated `progress` value rather than a per-particle
// timer, matching `GoalRing.swift`'s own "one animated value drives every dependent visual
// property" approach (same directory) — cheap, and composes for free with SwiftUI's built-in
// animation interpolation instead of needing a `TimelineView`/`Canvas` frame loop.
//
// Used by `App/ZANO/Features/Celebration/UnlockCelebrationView.swift` (this task's other owned
// file) behind the "Earned." headline; also reusable anywhere else a tasteful, non-blocking
// celebratory accent is wanted (a streak milestone, a badge reveal) without a second particle
// implementation.

import SwiftUI

/// A short-lived burst of confetti-style particles radiating from the view's center, built
/// entirely from `Theme` tokens (this file is a Design System *consumer*; it never redefines a
/// token — see `Theme.swift`'s own file-header note). Purely decorative — see `body` for why it's
/// hidden from accessibility and never intercepts touches.
public struct CelebrationBurst: View {

    /// A single particle's randomly-seeded trajectory. Recomputed by `fire()` on every trigger
    /// (see `body`), never inside `init` — regenerating particles on every `init` would reshuffle
    /// their positions on every SwiftUI re-render of the parent (which happens far more often than
    /// an actual new burst), not just when a fresh burst should actually fire.
    private struct Particle: Identifiable, Sendable {
        enum Kind: CaseIterable, Sendable { case circle, strip, square }

        let id: Int
        /// Direction of travel from the burst's center, in radians.
        let angle: Double
        /// Final travel distance in points.
        let distance: CGFloat
        let size: CGFloat
        /// Final rotation in degrees.
        let rotation: Double
        let kind: Kind
        let colorIndex: Int
        /// Staggers how "far along" each particle is at a given `progress` (0...1) without a real
        /// per-particle timer — see `localProgress(for:)`.
        let speed: Double
        /// Extra downward drift applied as `progress` advances, layered on top of the outward
        /// radial travel for a light "gravity" feel.
        let fallBias: CGFloat
    }

    private let particleCount: Int
    private let colors: [Color]
    /// Incrementing this (matching `PrimaryButton`'s own `hapticTick`/`commitTick` convention,
    /// same directory) fires a fresh burst while this view stays on screen. The burst also always
    /// fires once on first appear, regardless of this value's starting point.
    private let trigger: Int

    @State private var particles: [Particle] = []
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - trigger: Change this value to fire another burst without the view disappearing and
    ///     reappearing (e.g. a second surprise moment layered later in the same screen).
    ///   - colors: Particle fill colors, sampled per-particle. Defaults to a single-color burst in
    ///     `Theme.Colors.accent` — spec §16 P3's "burst of acid-green particles". Pass more than
    ///     one color for an occasion that wants a slightly richer mix; empty input falls back to
    ///     the same accent default rather than rendering invisible particles.
    ///   - particleCount: How many particles per burst. Defaults to 28 — enough to read as a
    ///     "burst" without tipping into clutter (spec §8 rule 4: "Keep it tasteful").
    public init(trigger: Int, colors: [Color] = [Theme.Colors.accent], particleCount: Int = 28) {
        self.trigger = trigger
        self.colors = colors.isEmpty ? [Theme.Colors.accent] : colors
        self.particleCount = max(0, particleCount)
    }

    public var body: some View {
        ZStack {
            ForEach(particles) { particle in
                particleShape(particle)
                    .foregroundStyle(colors[particle.colorIndex % colors.count])
                    .frame(width: particleSize(for: particle).width, height: particleSize(for: particle).height)
                    .rotationEffect(.degrees(particle.rotation * Double(localProgress(for: particle))))
                    .opacity(opacity(for: particle))
                    .offset(offset(for: particle))
            }
        }
        // Decorative only — the headline/subline/Time Bank label it accompanies already carry the
        // real information (see `UnlockCelebrationView`), so a screen reader gains nothing from
        // this view and would only hear noise from it.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear { fire() }
        .onChange(of: trigger) { _, _ in fire() }
    }

    // MARK: - Firing

    private func fire() {
        guard particleCount > 0 else { return }
        particles = Self.makeParticles(count: particleCount, colorCount: colors.count)
        progress = 0
        if reduceMotion {
            // Reduce Motion: skip the radial travel entirely (see `offset(for:)`/`localProgress`
            // below) and just cross-fade the particles in and out in place — still a positive
            // "something happened" cue, without the large motion Reduce Motion asks apps to avoid.
            withAnimation(.easeOut(duration: 0.25)) { progress = 1 }
        } else {
            // `Theme.Motion.springCelebration` is this design system's own token for exactly this
            // moment ("unlock bursts, streak milestones, badge reveals... still within
            // `unlockCelebrationMaxDuration`" — Theme.swift's own doc comment). Its response/
            // damping settles well under spec's 1.2s ceiling, leaving room for the headline/Time-
            // Bank/badge choreography `UnlockCelebrationView` layers on top of this burst.
            withAnimation(Theme.Motion.springCelebration) { progress = 1 }
        }
    }

    // MARK: - Per-particle derived state

    private func localProgress(for particle: Particle) -> CGFloat {
        guard !reduceMotion else { return progress }
        return min(1, progress * CGFloat(particle.speed))
    }

    private func offset(for particle: Particle) -> CGSize {
        guard !reduceMotion else { return .zero }
        let p = localProgress(for: particle)
        let travel = particle.distance * p
        return CGSize(
            width: cos(particle.angle) * travel,
            height: sin(particle.angle) * travel + particle.fallBias * p * p
        )
    }

    private func opacity(for particle: Particle) -> Double {
        let p = Double(localProgress(for: particle))
        guard p > 0 else { return 0 }
        // Fade in over the first 15%, hold, fade out over the final third — avoids every particle
        // popping in/out in a hard-edged, mechanical-looking step.
        if p > 0.66 { return max(0, 1 - (p - 0.66) / 0.34) }
        return min(1, p / 0.15)
    }

    private func particleSize(for particle: Particle) -> CGSize {
        switch particle.kind {
        case .circle, .square:
            CGSize(width: particle.size, height: particle.size)
        case .strip:
            // A "confetti strip" reads better as an elongated rectangle than a square dot.
            CGSize(width: particle.size * 1.8, height: particle.size * 0.55)
        }
    }

    @ViewBuilder
    private func particleShape(_ particle: Particle) -> some View {
        switch particle.kind {
        case .circle:
            Circle()
        case .square:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
        case .strip:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
        }
    }

    // MARK: - Random particle generation

    private static func makeParticles(count: Int, colorCount: Int) -> [Particle] {
        (0..<count).map { index in
            Particle(
                id: index,
                angle: Double.random(in: 0..<(2 * .pi)),
                distance: CGFloat.random(in: 60...150),
                size: CGFloat.random(in: 5...11),
                rotation: Double.random(in: -220...220),
                kind: Particle.Kind.allCases.randomElement() ?? .circle,
                colorIndex: colorCount > 0 ? Int.random(in: 0..<colorCount) : 0,
                speed: Double.random(in: 0.72...1.15),
                fallBias: CGFloat.random(in: 10...60)
            )
        }
    }
}

#Preview("CelebrationBurst") {
    CelebrationBurst(trigger: 0)
        .frame(width: 300, height: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
