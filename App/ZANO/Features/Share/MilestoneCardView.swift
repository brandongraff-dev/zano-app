// MilestoneCardView.swift
// App / ZANO / Features / Share
//
// The 9:16 milestone share image. Pass 2 (2026-10-03, "make it more playful"): a collectible. The
// big number sits on a die-cut sticker in the milestone's own hue (streaks are ember, locked hours
// violet, earned unlocks volt, early bird sun, the monthly story sky), with the silver star slapped
// on its corner as a second, round sticker. The unit and the line sit under it on the arcade-room
// background `PosterChassis` draws (`SharePoster.swift`, this folder): a fixed 360 x 640pt canvas
// exported at scale 3 (= 1080 x 1920 px), the on-screen preview being the same view scaled to fit.
// Also used for each page of the monthly story (`MonthlyStoryView`).
//
// No animation lives in the card (an animation can be mid-flight when `ImageRenderer` rasterizes
// it), which is also why the star is the static `ZanoMark`, not `ZanoLivingMark`. The reveal
// animation lives in `MilestoneMomentView`.
//
// Buddies (2026-10-03): the round sticker carries the user's buddy (happy, a still sprite read once
// from `Buddy.stored`, so the render has nothing to wait on) instead of the silver star.
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
    let hue: PosterHue

    init(eyebrow: String, numeral: String, unit: String, line: String, hue: PosterHue = .blue) {
        self.eyebrow = eyebrow
        self.numeral = numeral
        self.unit = unit
        self.line = line
        self.hue = hue
    }

    /// The single card for `milestone` (a monthly story's first page, for `.monthlyStory`).
    init(milestone: Milestone) {
        self.init(
            eyebrow: Copy.milestone.eyebrow(for: milestone),
            numeral: Copy.milestone.numeral(for: milestone),
            unit: Copy.milestone.unit(for: milestone),
            line: Copy.milestone.posterLine(for: milestone),
            hue: Self.hue(for: milestone)
        )
    }

    /// Each kind of milestone collects in its own colour.
    static func hue(for milestone: Milestone) -> PosterHue {
        switch milestone {
        case .streak: .ember
        case .lockedHours: .violet
        case .earnedUnlocks: .volt
        case .earlyBird: .sun
        case .monthlyStory: .sky
        case .yearInReview: .volt
        }
    }
}

/// The poster itself. Fixed 360 x 640; never place it in a resizing layout directly, wrap it in
/// `SharePosterPreview` for on-screen display and hand it to `SharePosterRenderer` for export.
struct MilestoneCardView: View {
    let content: MilestoneCardContent
    /// Read once at init (not `@AppStorage`): the poster is a still render.
    let buddy = Buddy.stored

    var body: some View {
        PosterChassis(eyebrow: content.eyebrow, footerLabel: Copy.share.footerWordmark, hue: content.hue) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                numberSticker
                    .overlay(alignment: .topTrailing) { starSticker.offset(x: 12, y: -34) }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(content.unit)
                        .font(Font.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(content.line)
                        .font(Font.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, Theme.Spacing.xxs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.lg)
        }
    }

    /// The number on a hue sticker: score face, ink on the hue, a hard shadow.
    private var numberSticker: some View {
        Text(content.numeral)
            .font(Theme.Typography.score(size: 136))
            .foregroundStyle(content.hue.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .posterSticker(
                LinearGradient(
                    colors: [content.hue.color, content.hue.partner],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                radius: Theme.Radius.large,
                tilt: -3
            )
    }

    /// The user's buddy on a round ink sticker (the silver star until 2026-10-03). Static artwork,
    /// safe to rasterize.
    private var starSticker: some View {
        ZStack {
            Circle().fill(Theme.Colors.backgroundDeep)
            Circle().strokeBorder(Color.white, lineWidth: PosterMetrics.stickerRim)
            BuddySprite(buddy, pose: .ecstatic, size: 64)
        }
        .frame(width: 84, height: 84)
        .shadow(color: Color.black.opacity(0.5), radius: 0, x: 3, y: 5)
        .rotationEffect(.degrees(14))
        .accessibilityHidden(true)
    }
}

#Preview("Streak") {
    SharePosterPreview(poster: MilestoneCardView(content: MilestoneCardContent(milestone: .streak(days: 30))))
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("Earned unlocks") {
    SharePosterPreview(poster: MilestoneCardView(content: MilestoneCardContent(milestone: .earnedUnlocks(100))))
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
