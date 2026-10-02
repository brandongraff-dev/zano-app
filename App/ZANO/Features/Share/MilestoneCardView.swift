// MilestoneCardView.swift
// App / ZANO / Features / Share
//
// The 9:16 milestone share image: dark base, the metallic ZANO star in a blue glow, a giant numeral,
// its unit, one line, and the wordmark. Built on `PosterChassis` (`SharePoster.swift`, this folder):
// a fixed 360 x 640pt canvas exported at scale 3 (= 1080 x 1920 px) by `SharePosterRenderer`, with
// the on-screen preview being the same view scaled to fit, so what the user approves is what they
// post. Also used for each page of the monthly story (`MonthlyStoryView`).
//
// No animation lives in the card (an animation can be mid-flight when `ImageRenderer` rasterizes
// it), which is also why the star is the static `ZanoMark`, not the `TimelineView`-driven
// `ZanoLivingMark`. The reveal animation lives in `MilestoneMomentView`.
//
// Copy: `Copy.milestone.*` (`Core/Sources/Core/Copy/MilestoneCopy.swift`). This file composes no
// user-facing string of its own.

import SwiftUI
import Core

/// The displayable content of one milestone poster, fully caller-composed.
struct MilestoneCardContent: Equatable, Sendable {
    let eyebrow: String
    let numeral: String
    let unit: String
    let line: String

    init(eyebrow: String, numeral: String, unit: String, line: String) {
        self.eyebrow = eyebrow
        self.numeral = numeral
        self.unit = unit
        self.line = line
    }

    /// The single card for `milestone` (a monthly story's first page, for `.monthlyStory`).
    init(milestone: Milestone) {
        self.init(
            eyebrow: Copy.milestone.eyebrow(for: milestone),
            numeral: Copy.milestone.numeral(for: milestone),
            unit: Copy.milestone.unit(for: milestone),
            line: Copy.milestone.posterLine(for: milestone)
        )
    }
}

/// The poster itself. Fixed 360 x 640; never place it in a resizing layout directly, wrap it in
/// `SharePosterPreview` for on-screen display and hand it to `SharePosterRenderer` for export.
struct MilestoneCardView: View {
    let content: MilestoneCardContent

    var body: some View {
        PosterChassis(eyebrow: content.eyebrow, footerLabel: Copy.share.footerWordmark) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                star

                VStack(alignment: .leading, spacing: 0) {
                    Text(content.numeral)
                        .font(Theme.Typography.numeral(size: 132, weight: .heavy))
                        .foregroundStyle(Theme.Colors.metallic)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 24)

                    Text(content.unit)
                        .font(Font.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(content.line)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The brushed-silver star in a soft blue bloom. Static artwork, safe to rasterize.
    private var star: some View {
        ZanoMark(height: 64, style: .brand)
            .background {
                RadialGradient(
                    colors: [Theme.Colors.accent.opacity(0.55), Theme.Colors.accent.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 90
                )
                .frame(width: 180, height: 180)
            }
            .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 18)
            .accessibilityHidden(true)
    }
}

#Preview {
    SharePosterPreview(poster: MilestoneCardView(content: MilestoneCardContent(milestone: .streak(days: 30))))
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
