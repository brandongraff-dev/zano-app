// ZanoLivingMark.swift
// Core / UI / Components
//
// The ZANO star as a living object, the way Opal's gem is (the founder's reference, 2026-09-24):
// Today's hero and the Screen time section draw it, and it *charges with time off your phone*.
//
//   * Charge (0...1) is `ScreenTimeSummary.charge`: the share of today's waking hours not spent on
//     the phone. The star's brushed silver fills left to right along the swoosh; the uncharged part
//     stays dark graphite.
//   * Low charge: dim, a slow cold pulse. High charge: bright metal, a light sweep across it every
//     few seconds, a glow that breathes. Always: a slow float and a slight turn, like a gem.
//   * Reduce Motion: the same charge, perfectly still.
//
// Because real screen-time numbers exist only inside the `ZANOReport` extension (spec §27), Today
// embeds `ScreenTimeChargeView` through `DeviceActivityReport(.zanoMark, ...)`; the extension
// computes the summary and draws this view. CI screenshots draw it from demo data.

import SwiftUI

public struct ZanoLivingMark: View {
    private let charge: Double
    private let height: CGFloat
    private let accessibilityValueText: String?
    private let mood: ZanoMascotMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - charge: 0...1, clamped.
    ///   - height: the star's height in points; width follows (1.56 × height).
    ///   - accessibilityValue: What the star *means* here, spoken after the brand name (e.g.
    ///     `Copy.screenTime.chargeSpoken(percent:)`). `nil` (the default) hides the star from
    ///     VoiceOver: most screens use it as decoration beside copy that already says the thing.
    ///   - mood: Pass 2: how the star feels (`ZanoMascotMood`). In-process it dims a sleepy star,
    ///     slows its bob and brightens a charged one; the body language (hop, wiggle, sparks, jump,
    ///     spin) is `.zanoMascot(mood:...)`, applied around the star. Defaults to `.idle`, which
    ///     draws exactly what the star drew before pass 2.
    public init(charge: Double, height: CGFloat = 120, accessibilityValue: String? = nil, mood: ZanoMascotMood = .idle) {
        self.charge = min(1, max(0, charge))
        self.height = height
        self.accessibilityValueText = accessibilityValue
        self.mood = mood
    }

    private var width: CGFloat { height * ZanoMark.aspectRatio }

    public var body: some View {
        Group {
            if reduceMotion {
                star(time: 0, animated: false)
            } else {
                // 30 fps is plenty for a slow breathe/float and halves the redraw cost; paused
                // whenever the app isn't frontmost.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
                    star(time: context.date.timeIntervalSinceReferenceDate, animated: true)
                }
            }
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 1.2), value: charge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.brand.name)
        .accessibilityValue(accessibilityValueText ?? "")
        .accessibilityHidden(accessibilityValueText == nil)
    }

    private func star(time t: Double, animated: Bool) -> some View {
        let breathe = animated ? 0.5 + 0.5 * sin(t * 2 * .pi / 4.5) : 0.5
        // v2: the mascot bobs — a playful, quicker float with a little lean into each rise.
        // Pass 2: a sleepy star bobs slower and lower; a charged one glows brighter.
        let sleepy = mood == .sleepy
        let bobPhase = t * 2 * .pi / (Theme.Motion.idleBobPeriod * (sleepy ? 1.6 : 1))
        let float = animated ? sin(bobPhase) * height * (sleepy ? 0.02 : 0.045) : 0
        let lean = animated ? cos(bobPhase) * 2.5 : 0
        let turn = animated ? sin(t * 2 * .pi / 9) * 9 : 0
        // The sweep crosses once every 4 s, from off the left edge to off the right.
        let sweep = animated ? (t.truncatingRemainder(dividingBy: 4) / 4) * 1.8 - 0.4 : -1

        return ZStack {
            // Glow: the star's own shape, blurred. Grows and brightens with charge, breathes.
            // Navy fading into blue as the charge rises (no hard switch at a threshold).
            ZStack {
                ZanoMarkShape()
                    .fill(Theme.Colors.lockedAmbient, style: FillStyle(eoFill: true))
                    .opacity(1 - charge)
                ZanoMarkShape()
                    .fill(Theme.Colors.accent, style: FillStyle(eoFill: true))
                    .opacity(charge)
            }
            .blur(radius: height * 0.2)
            .opacity(min(1, (0.18 + 0.62 * charge) * (0.7 + 0.3 * breathe) * mood.glowFactor))

            // Uncharged metal.
            ZanoMarkShape()
                .fill(Self.graphite, style: FillStyle(eoFill: true))
                .overlay(
                    ZanoMarkShape()
                        .stroke(Theme.Colors.markGraphiteEdge.opacity(0.625 + 0.375 * breathe), lineWidth: 0.75)
                )

            // Charged metal, filled left to right with a soft leading edge.
            ZanoMarkShape()
                .fill(Theme.Colors.metallic, style: FillStyle(eoFill: true))
                .mask(chargeMask)

            // The light sweep, only over the charged part.
            if charge > 0.05 && !sleepy {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: max(0, sweep - 0.12)),
                        .init(color: .white.opacity(0.85), location: min(1, max(0, sweep))),
                        .init(color: .white.opacity(0), location: min(1, sweep + 0.12)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
                .opacity(0.35 + 0.4 * charge)
                .mask(ZanoMarkShape().fill(style: FillStyle(eoFill: true)))
                .mask(chargeMask)
            }
        }
        .rotation3DEffect(.degrees(turn), axis: (x: 0.2, y: 1, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(lean))
        .offset(y: float)
    }

    /// Opaque from the left up to `charge`, with a feathered edge.
    private var chargeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: max(0, charge - 0.015)),
                .init(color: .clear, location: min(1, charge + 0.015)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }


    /// The star's uncharged metal: translucent graphite (white over ink in dark mode, ink over
    /// white in light mode, so the empty star is visible in both).
    private static var graphite: LinearGradient {
        LinearGradient(
            colors: [Theme.Colors.markGraphiteTop, Theme.Colors.markGraphiteBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The living star with today's charge stuck on it. Sized for Today's hero. This is the view the
/// `ZANOReport` extension draws for the `.zanoMark` context, so its type must stay concrete.
///
/// v2 (visual direction v2): one quiet row of glass chips under the star.
///
/// Pass 2 (playful, 2026-10-03): the hero is compact now (the star sits beside the score, so the goal
/// tiles start above the fold), so the charge is a small sticker stuck on the star's corner ("72%"
/// with a bolt, filled ZANO Blue once it is worth bragging about) instead of a chip row under it. It
/// moves with the star, which is the point: it is the star's own badge. The day's screen-time total
/// also sits under the star as a quiet sticker. The default height (96) is the compact hero's star, and it is
/// what the report extension draws with (it passes no height), so the app and extension agree.
public struct ScreenTimeChargeView: View {
    private let charge: Double
    private let total: TimeInterval?
    private let height: CGFloat

    public init(summary: ScreenTimeSummary, height: CGFloat = 96) {
        self.charge = summary.charge
        self.total = summary.total
        self.height = height
    }

    /// Before Screen Time access: an uncharged star and a hint instead of numbers.
    public init(height: CGFloat = 96) {
        self.charge = 0
        self.total = nil
        self.height = height
    }

    private var percent: Int { Int((charge * 100).rounded()) }

    public var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // Before access there is no charge to speak, so the star stays decorative and the
            // hint below carries the meaning.
            ZanoLivingMark(
                charge: charge,
                height: height,
                accessibilityValue: total == nil ? nil : Copy.screenTime.chargeSpoken(percent: percent)
            )
            .overlay(alignment: .bottomTrailing) {
                if total != nil {
                    ZanoSticker(
                        Copy.screenTime.chargeSticker(percent: percent),
                        systemImage: "bolt.fill",
                        color: charge >= 0.35 ? Theme.Colors.accent : Theme.Colors.muted,
                        style: charge >= 0.35 ? .filled : .tinted,
                        size: .small
                    )
                    .fixedSize()
                    .offset(x: Theme.Spacing.xxs, y: Theme.Spacing.xs)
                    // The star already speaks the charge (`chargeSpoken`).
                    .accessibilityHidden(true)
                }
            }
            // The founder asked for today's screen-time total right under the star; it stays,
            // as a quiet sticker.
            if let total {
                ZanoSticker(
                    Copy.screenTime.duration(total),
                    systemImage: "iphone",
                    color: Theme.Colors.muted,
                    style: .tinted,
                    size: .small
                )
                .fixedSize()
                .accessibilityLabel(Copy.screenTime.spokenDuration(total))
            }
            if total == nil {
                Text(Copy.screenTime.chargeHint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        // Drawn by the `ZANOReport` extension, which the app's root scheme can't reach: honour an
        // explicit Settings > Appearance choice (light mode, 2026-10-03).
        .zanoAppAppearance()
    }
}

// MARK: - Charge burst

extension View {
    /// The star's "charge" moment (visual direction v2): each time `trigger` changes, the content
    /// pops (scale 1 → 1.12 → 1) and a ring of `color` light expands out of it and fades.
    ///
    /// Pass 2 (playful): eight sparkles fly out with the ring and spin as they go, so a completed
    /// goal throws a little handful of its own colour. For an earned beat only (a goal completing).
    /// Reduce Motion: nothing moves.
    ///
    /// - Parameters:
    ///   - trigger: Bump to fire.
    ///   - color: The ring's and the sparkles' colour. Defaults to the accent.
    ///   - sparks: Throw the sparkles. Defaults to `true`; pass `false` for a ring-only pulse.
    public func zanoChargeBurst(trigger: Int, color: Color = Theme.Colors.accent, sparks: Bool = true) -> some View {
        modifier(ZanoChargeBurst(trigger: trigger, color: color, sparks: sparks))
    }
}

private struct ZanoChargeBurst: ViewModifier {
    let trigger: Int
    let color: Color
    let sparks: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sparkCount = 8

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Plain values: the keyframe content closures are `@Sendable`.
            let color = self.color
            let sparks = self.sparks
            content
                .keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.12, duration: 0.16, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.55, spring: .bouncy)
                }
                .overlay {
                    GeometryReader { proxy in
                        let radius = min(proxy.size.width, proxy.size.height) / 2
                        ZStack {
                            Circle()
                                .strokeBorder(color, lineWidth: 3)
                            if sparks {
                                ForEach(0..<Self.sparkCount, id: \.self) { index in
                                    ZanoSparkleShape()
                                        .fill(index.isMultiple(of: 2) ? color : Color.white)
                                        .frame(width: max(6, radius * 0.22), height: max(6, radius * 0.22))
                                        .modifier(SparkFlight(index: index, count: Self.sparkCount, radius: radius))
                                }
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .keyframeAnimator(initialValue: 0.0, trigger: trigger) { burst, progress in
                            burst
                                .environment(\.zanoBurstProgress, progress)
                                .scaleEffect(0.4 + 1.2 * progress)
                                .opacity(progress > 0 && progress < 1 ? (1 - progress) * 0.95 : 0)
                        } keyframes: { _ in
                            LinearKeyframe(0.0, duration: 0.001)
                            CubicKeyframe(1.0, duration: 0.75)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }
}

/// How far through a charge burst the sparkles are (0...1). Set by the burst's keyframes.
private struct ZanoBurstProgressKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    fileprivate var zanoBurstProgress: Double {
        get { self[ZanoBurstProgressKey.self] }
        set { self[ZanoBurstProgressKey.self] = newValue }
    }
}

/// One sparkle's path out of the burst: straight out along its spoke, spinning, a little further
/// than the ring.
private struct SparkFlight: ViewModifier {
    let index: Int
    let count: Int
    let radius: CGFloat

    @Environment(\.zanoBurstProgress) private var progress

    func body(content: Content) -> some View {
        let angle = Double(index) / Double(count) * 2 * .pi + .pi / 8
        let distance = radius * (0.3 + 0.55 * progress)
        return content
            .rotationEffect(.degrees(progress * 220))
            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
    }
}
