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
        let float = animated ? sin(t * 2 * .pi / 6) * height * 0.025 : 0
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

/// The living star with today's screen time under it, Opal-style: "2h 34m", "SCREEN TIME TODAY",
/// then how charged the star is. Sized for Today's hero. This is the view the `ZANOReport`
/// extension draws for the `.zanoMark` context, so its type must stay concrete.
public struct ScreenTimeChargeView: View {
    private let charge: Double
    private let total: TimeInterval?
    private let height: CGFloat

    public init(summary: ScreenTimeSummary, height: CGFloat = 120) {
        self.charge = summary.charge
        self.total = summary.total
        self.height = height
    }

    /// Before Screen Time access: an uncharged star and a hint instead of numbers.
    public init(height: CGFloat = 120) {
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
                .padding(.bottom, height * 0.26)
            if let total {
                Text(Copy.screenTime.duration(total))
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.text)
                    .contentTransition(.numericText())
                    // `2h 30m` is read as letters; speak it as words.
                    .accessibilityLabel(Copy.screenTime.spokenDuration(total))
                Text(Copy.screenTime.totalLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.top, 2)
                Text(Copy.screenTime.chargeLine(percent: percent))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(charge >= 0.35 ? Theme.Colors.accent : Theme.Colors.muted)
                    .padding(.top, Theme.Spacing.xs)
                    // The star above already speaks the charge (`chargeSpoken`).
                    .accessibilityHidden(true)
            } else {
                Text(Copy.screenTime.chargeHint)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, height * 0.28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
