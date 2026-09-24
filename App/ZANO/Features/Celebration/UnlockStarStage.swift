// UnlockStarStage.swift
// App / Features / Celebration
//
// The centre-stage artwork of the unlock moment (`UnlockCelebrationView`): the living ZANO star
// charging to full, then a flash of blue light blooming out of it, a brief white specular, a blue
// shockwave ring expanding outward, and the star settling in a quiet blue halo.
//
// Everything is driven by two numbers, `charge` (0...1, the star's silver fill) and `flash`
// (0...1, how far through the flash the stage is). Each effect computes its own curve from `flash`
// (rise fast, then decay to a resting value), so the caller only has to advance two numbers per
// frame (`UnlockCelebrationView` does it from a `TimelineView`). Plain animated modifiers would only
// interpolate between two endpoint values, which cannot express "0 -> peak -> 0" for the
// shockwave's opacity.
//
// Resting frame (`flash == 1`, `charge == 1`): a fully charged star, a soft blue bloom behind it
// and three faint concentric halo rings. That is the still the Reduce Motion path shows directly,
// and the frame CI screenshots capture.

import SwiftUI
import Core

struct UnlockStarStage: View {
    /// The star's silver fill, 0...1.
    let charge: Double
    /// Progress through the flash, 0 (before) ... 1 (settled).
    let flash: Double

    var body: some View {
        ZStack {
            haloRings
                .opacity(haloOpacity)

            shockwave

            ZanoLivingMark(charge: charge, height: StageMetrics.starHeight)
                .scaleEffect(starScale)

            // The white specular: a hot, small core of light over the star at the flash's peak.
            RadialGradient(
                colors: [Color.white.opacity(0.95), Color.white.opacity(0.35), Color.white.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: StageMetrics.specularRadius
            )
            .frame(width: StageMetrics.specularRadius * 2, height: StageMetrics.specularRadius * 2)
            .scaleEffect(0.6 + 0.6 * specularIntensity)
            .opacity(specularIntensity)
            .blendMode(.plusLighter)
        }
        .background {
            // The blue bloom. A background so it can be far larger than the stage without
            // affecting layout.
            RadialGradient(
                colors: [
                    Theme.Colors.accent.opacity(0.85),
                    Theme.Colors.accent.opacity(0.30),
                    Theme.Colors.accent.opacity(0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: StageMetrics.bloomRadius
            )
            .frame(width: StageMetrics.bloomRadius * 2, height: StageMetrics.bloomRadius * 2)
            .scaleEffect(0.55 + 0.45 * min(1, flash / 0.35))
            .opacity(bloomIntensity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Curves (all pure functions of `flash`)

    /// Rises to full over the first 20% of the flash, then settles to a resting glow.
    private var bloomIntensity: Double {
        if flash <= 0 { return 0 }
        if flash < 0.2 { return flash / 0.2 }
        return 1 - (1 - StageMetrics.restingBloom) * ((flash - 0.2) / 0.8)
    }

    /// A short white hit: up in the first 12%, gone by 45%.
    private var specularIntensity: Double {
        if flash <= 0 || flash >= 0.45 { return 0 }
        if flash < 0.12 { return flash / 0.12 }
        return 1 - (flash - 0.12) / 0.33
    }

    /// The star swells a touch with the flash and settles back.
    private var starScale: CGFloat {
        guard flash > 0, flash < 0.6 else { return 1 }
        return 1 + 0.08 * CGFloat(sin(flash / 0.6 * .pi))
    }

    /// The halo rings fade in behind the shockwave and stay.
    private var haloOpacity: Double {
        min(1, max(0, (flash - 0.25) / 0.5))
    }

    // MARK: - Pieces

    private var shockwave: some View {
        // Ease-out travel so the ring leaves fast and slows as it fades.
        let travel = 1 - pow(1 - flash, 2.2)
        let opacity: Double = {
            if flash <= 0 || flash >= 1 { return 0 }
            if flash < 0.08 { return flash / 0.08 }
            return 1 - (flash - 0.08) / 0.92
        }()
        return ZStack {
            Circle()
                .stroke(Theme.Colors.accent, lineWidth: StageMetrics.shockLine)
                .blur(radius: 6)
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .frame(width: StageMetrics.shockBase, height: StageMetrics.shockBase)
        .scaleEffect(0.35 + (StageMetrics.shockMaxScale - 0.35) * travel)
        .opacity(opacity)
    }

    private var haloRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Theme.Colors.accent.opacity(0.30 - Double(index) * 0.09),
                        lineWidth: 1
                    )
                    .frame(
                        width: StageMetrics.haloBase + CGFloat(index) * StageMetrics.haloStep,
                        height: StageMetrics.haloBase + CGFloat(index) * StageMetrics.haloStep
                    )
            }
        }
    }
}

/// Sizes for the stage artwork, which has no `Theme.Metrics` home.
enum StageMetrics {
    /// The star's height; width follows `ZanoMark.aspectRatio`.
    static let starHeight: CGFloat = 112
    /// The stage's layout height. The bloom and outer halo may draw past it.
    static let stageHeight: CGFloat = 280
    static let bloomRadius: CGFloat = 190
    /// The bloom's resting intensity once the flash has settled (the still-frame glow).
    static let restingBloom: Double = 0.42
    static let specularRadius: CGFloat = 70
    static let shockBase: CGFloat = 180
    static let shockLine: CGFloat = 3
    static let shockMaxScale: CGFloat = 2.6
    static let haloBase: CGFloat = 200
    static let haloStep: CGFloat = 46
}

#Preview("Stage — resting") {
    UnlockStarStage(charge: 1, flash: 1)
        .frame(height: StageMetrics.stageHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
