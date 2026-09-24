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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - charge: 0...1, clamped.
    ///   - height: the star's height in points; width follows (1.56 × height).
    public init(charge: Double, height: CGFloat = 120) {
        self.charge = min(1, max(0, charge))
        self.height = height
    }

    private var width: CGFloat { height * ZanoMark.aspectRatio }

    public var body: some View {
        Group {
            if reduceMotion {
                star(time: 0, animated: false)
            } else {
                TimelineView(.animation) { context in
                    star(time: context.date.timeIntervalSinceReferenceDate, animated: true)
                }
            }
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 1.2), value: charge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.brand.name)
        .accessibilityValue(Copy.screenTime.chargeLine(percent: Int((charge * 100).rounded())))
    }

    private func star(time t: Double, animated: Bool) -> some View {
        let breathe = animated ? 0.5 + 0.5 * sin(t * 2 * .pi / 4.5) : 0.5
        let float = animated ? sin(t * 2 * .pi / 6) * height * 0.025 : 0
        let turn = animated ? sin(t * 2 * .pi / 9) * 9 : 0
        // The sweep crosses once every 4 s, from off the left edge to off the right.
        let sweep = animated ? (t.truncatingRemainder(dividingBy: 4) / 4) * 1.8 - 0.4 : -1

        return ZStack {
            // Glow: the star's own shape, blurred. Grows and brightens with charge, breathes.
            ZanoMarkShape()
                .fill(glowColor, style: FillStyle(eoFill: true))
                .blur(radius: height * 0.16)
                .opacity((0.12 + 0.6 * charge) * (0.7 + 0.3 * breathe))

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
        .offset(y: float)
    }

    /// Opaque from the left up to `charge`, with a feathered edge.
    private var chargeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: max(0, charge - 0.04)),
                .init(color: .clear, location: min(1, charge + 0.04)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Cold steel when barely charged, pearl when charged.
    private var glowColor: Color {
        charge < 0.35 ? Theme.Colors.lockedAmbient : Theme.Colors.accent
    }

    /// The star's uncharged metal: dark graphite, a step above `surface2`.
    private static var graphite: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The living star plus its one-line caption ("Charged 80%" / "Charges while you're off your
/// phone"), sized for Today's hero. This is the view the `ZANOReport` extension draws for the
/// `.zanoMark` context, so its type must stay concrete.
public struct ScreenTimeChargeView: View {
    private let charge: Double
    private let hasData: Bool
    private let height: CGFloat

    public init(summary: ScreenTimeSummary, height: CGFloat = 120) {
        self.charge = summary.charge
        self.hasData = true
        self.height = height
    }

    /// Before Screen Time access: an uncharged star and a hint instead of a percentage.
    public init(height: CGFloat = 120) {
        self.charge = 0
        self.hasData = false
        self.height = height
    }

    public var body: some View {
        VStack(spacing: height * 0.22) {
            ZanoLivingMark(charge: charge, height: height)
            Text(hasData ? Copy.screenTime.chargeLine(percent: Int((charge * 100).rounded())) : Copy.screenTime.chargeHint)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(hasData && charge >= 0.35 ? Theme.Colors.textSecondary : Theme.Colors.muted)
                .contentTransition(.numericText())
        }
        .padding(.top, height * 0.28)
        .frame(maxWidth: .infinity)
    }
}
