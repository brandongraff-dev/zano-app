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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - charge: 0...1, clamped.
    ///   - height: the star's height in points; width follows (1.56 × height).
    ///   - accessibilityValue: What the star *means* here, spoken after the brand name (e.g.
    ///     `Copy.screenTime.chargeSpoken(percent:)`). `nil` (the default) hides the star from
    ///     VoiceOver: most screens use it as decoration beside copy that already says the thing.
    public init(charge: Double, height: CGFloat = 120, accessibilityValue: String? = nil) {
        self.charge = min(1, max(0, charge))
        self.height = height
        self.accessibilityValueText = accessibilityValue
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
        let bobPhase = t * 2 * .pi / Theme.Motion.idleBobPeriod
        let float = animated ? sin(bobPhase) * height * 0.045 : 0
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
            .opacity((0.18 + 0.62 * charge) * (0.7 + 0.3 * breathe))

            // Uncharged metal.
            ZanoMarkShape()
                .fill(Self.graphite, style: FillStyle(eoFill: true))
                .overlay(
                    ZanoMarkShape()
                        .stroke(Color.white.opacity(0.10 + 0.06 * breathe), lineWidth: 0.75)
                )

            // Charged metal, filled left to right with a soft leading edge.
            ZanoMarkShape()
                .fill(Theme.Colors.metallic, style: FillStyle(eoFill: true))
                .mask(chargeMask)

            // The light sweep, only over the charged part.
            if charge > 0.05 {
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


    /// The star's uncharged metal: dark graphite, a step above `surface2`.
    private static var graphite: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.11), Color.white.opacity(0.035)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The living star with today's charge under it. Sized for Today's hero. This is the view the
/// `ZANOReport` extension draws for the `.zanoMark` context, so its type must stay concrete.
///
/// v2 (visual direction v2): one quiet row of glass chips under the star — the charge and the day's
/// screen time — instead of a 44pt total, a tracked all-caps label and a middle-dot sentence, so the
/// screen's real hero (the goal count) is the only big number on Today.
public struct ScreenTimeChargeView: View {
    private let charge: Double
    private let total: TimeInterval?
    private let height: CGFloat

    public init(summary: ScreenTimeSummary, height: CGFloat = 150) {
        self.charge = summary.charge
        self.total = summary.total
        self.height = height
    }

    /// Before Screen Time access: an uncharged star and a hint instead of numbers.
    public init(height: CGFloat = 150) {
        self.charge = 0
        self.total = nil
        self.height = height
    }

    private var percent: Int { Int((charge * 100).rounded()) }

    public var body: some View {
        VStack(spacing: 0) {
            // Before access there is no charge to speak, so the star stays decorative and the
            // hint below carries the meaning.
            ZanoLivingMark(
                charge: charge,
                height: height,
                accessibilityValue: total == nil ? nil : Copy.screenTime.chargeSpoken(percent: percent)
            )
            .padding(.bottom, height * 0.3)
            if let total {
                HStack(spacing: Theme.Spacing.xs) {
                    ZanoGlassChip(
                        Copy.today.heroStarCharge(percent: percent),
                        systemImage: "bolt.fill",
                        tint: charge >= 0.35 ? Theme.Colors.accent : Theme.Colors.muted
                    )
                    // The star above already speaks the charge (`chargeSpoken`).
                    .accessibilityHidden(true)
                    ZanoGlassChip(Copy.screenTime.duration(total), systemImage: "iphone", tint: Theme.Colors.muted)
                        .contentTransition(.numericText())
                        .accessibilityElement(children: .ignore)
                        // `2h 30m` is read as letters; speak it as words, with what it is.
                        .accessibilityLabel(Copy.screenTime.totalLabel)
                        .accessibilityValue(Copy.screenTime.spokenDuration(total))
                }
            } else {
                Text(Copy.screenTime.chargeHint)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, height * 0.3)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Charge burst

extension View {
    /// The star's "charge" moment (visual direction v2): each time `trigger` changes, the content
    /// pops (scale 1 → 1.1 → 1 on `Theme.Motion.springPop`-like keyframes) and a ring of `color`
    /// light expands out of it and fades. For an earned beat only (a goal completing). Reduce Motion:
    /// nothing moves.
    public func zanoChargeBurst(trigger: Int, color: Color = Theme.Colors.accent) -> some View {
        modifier(ZanoChargeBurst(trigger: trigger, color: color))
    }
}

private struct ZanoChargeBurst: ViewModifier {
    let trigger: Int
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.1, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                }
                .overlay {
                    Circle()
                        .strokeBorder(color, lineWidth: 3)
                        .keyframeAnimator(initialValue: 0.0, trigger: trigger) { ring, progress in
                            ring
                                .scaleEffect(0.4 + 1.2 * progress)
                                .opacity(progress > 0 && progress < 1 ? (1 - progress) * 0.9 : 0)
                                .blur(radius: 1 + 3 * progress)
                        } keyframes: { _ in
                            LinearKeyframe(0.0, duration: 0.001)
                            CubicKeyframe(1.0, duration: 0.75)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }
}
