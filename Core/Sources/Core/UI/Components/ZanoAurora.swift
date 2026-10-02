// ZanoAurora.swift
// Core / UI / Components
//
// The canvas of visual direction v2 (docs/design/visual-direction-v2.md §3, "The canvas: aurora"):
// an indigo-ink room with three soft coloured lights drifting slowly in it. Glass only reads as glass
// when there is colour behind it; the old flat near-black gave every translucent surface nothing to
// show, so cards looked like grey boxes.
//
//   * Ink gradient: `background` at the top to `backgroundDeep` at the bottom, so the tab bar and
//     pinned action bars sit on the darkest part of the screen.
//   * Three radial lights: ZANO Blue top-left, violet top-right, ember low-left. Their strengths come
//     from `ZanoAmbientState`: cool and dim while locked, warming as goals complete, brightest when
//     the day is earned (the only state that lights ember).
//   * Drift: each light orbits a few percent of the screen over 20–30 s, redrawn at
//     `Theme.Motion.auroraFrameInterval` (12 fps; the lights move a fraction of a point per frame).
//     Paused when the scene is not active and when the screen is a hidden kept-alive tab
//     (`zanoAmbientIsLive`, set by the tab container). Reduce Motion: one still frame.
//     Reduce Transparency: the ink gradient only.
//
// Decorative: no hit testing, hidden from accessibility.

import SwiftUI

// MARK: - Environment

private struct ZanoAmbientIsLiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `false` while the view is in a kept-alive but hidden tab: the aurora stops redrawing. The tab
    /// container sets it; everything else leaves the default (`true`).
    public var zanoAmbientIsLive: Bool {
        get { self[ZanoAmbientIsLiveKey.self] }
        set { self[ZanoAmbientIsLiveKey.self] = newValue }
    }
}

// MARK: - View

/// The full-screen v2 canvas. Use it through `.zanoAmbient(_:)` / `.zanoBackdrop(...)` rather than
/// directly, so every screen gets the same light.
public struct ZanoAuroraBackground: View {
    private let state: ZanoAmbientState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.zanoAmbientIsLive) private var isLive

    public init(state: ZanoAmbientState = .neutral) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.background, Theme.Colors.background, Theme.Colors.backgroundDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            if !reduceTransparency {
                if reduceMotion {
                    lights(time: 0)
                } else {
                    TimelineView(.animation(
                        minimumInterval: Theme.Motion.auroraFrameInterval,
                        paused: scenePhase != .active || !isLive
                    )) { context in
                        lights(time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lights(time t: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let mood = AuroraMood(state)
            ZStack {
                light(Theme.Colors.Aurora.blue, strength: mood.blue, size: size,
                      center: drift(base: CGPoint(x: 0.12, y: 0.06), t: t, period: 23, phase: 0), radius: 0.95)
                light(Theme.Colors.Aurora.violet, strength: mood.violet, size: size,
                      center: drift(base: CGPoint(x: 0.92, y: 0.2), t: t, period: 29, phase: 1.7), radius: 0.85)
                light(Theme.Colors.Aurora.ember, strength: mood.ember, size: size,
                      center: drift(base: CGPoint(x: 0.18, y: 0.6), t: t, period: 26, phase: 3.1), radius: 0.75)
            }
        }
    }

    /// A slow Lissajous orbit around `base`, ±5% of the screen.
    private func drift(base: CGPoint, t: Double, period: Double, phase: Double) -> UnitPoint {
        let a = (t / period) * 2 * .pi + phase
        return UnitPoint(x: base.x + 0.05 * sin(a), y: base.y + 0.035 * cos(a * 0.8))
    }

    private func light(_ color: Color, strength: Double, size: CGSize, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(strength), color.opacity(strength * 0.35), color.opacity(0)],
            center: center,
            startRadius: 0,
            endRadius: max(size.width, 1) * radius
        )
        .opacity(strength > 0.001 ? 1 : 0)
    }
}

/// How bright each light is for a state. Locked rooms are cool and dim; progress warms them; an
/// earned day is the brightest and the only one with ember.
private struct AuroraMood {
    let blue: Double
    let violet: Double
    let ember: Double

    init(_ state: ZanoAmbientState) {
        let levels = Self.levels(for: state)
        blue = levels.blue
        violet = levels.violet
        ember = levels.ember
    }

    private static func levels(for state: ZanoAmbientState) -> (blue: Double, violet: Double, ember: Double) {
        switch state {
        case .neutral:
            return (0.26, 0.20, 0)
        case .locked:
            return (0.16, 0.24, 0)
        case .progress(let fraction):
            let f = min(1, max(0, fraction))
            return (0.18 + 0.14 * f, 0.22, 0.06 * f)
        case .earned:
            return (0.36, 0.20, 0.14)
        }
    }
}

#Preview("Aurora") {
    VStack(spacing: Theme.Spacing.md) {
        Text("2")
            .font(Theme.Typography.score(size: 96))
            .foregroundStyle(Theme.Colors.text)
        Text("goals to unlock")
            .font(Theme.Typography.title)
            .foregroundStyle(Theme.Colors.text)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ZanoAuroraBackground(state: .progress(0.5)).ignoresSafeArea())
    .preferredColorScheme(.dark)
}
