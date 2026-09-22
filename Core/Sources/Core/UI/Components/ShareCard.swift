// ShareCard.swift
// Core / UI / Components
//
// A 9:16 exportable share image, per docs/spec.md §15's core component list ("ShareCard (9:16
// renderer)") and the P7 mockup in §16 ("9:16 shareable card: 'Week 6 · Rank Gold', 7 columns of
// daily rings, stats '4 workouts · 1,020g protein · 6h 40m time reclaimed', one line 'Best day:
// Thursday', small logo bottom right"). Distinct from `RecapCard` (the in-app weekly summary card)
// because a shareable export has different layout/branding constraints — fixed aspect ratio, no
// interaction, designed to be legible as a standalone image on Instagram/TikTok/iMessage.
//
// `import UIKit` below is a deliberate, narrow exception to CLAUDE.md's "No UIKit unless an Apple
// API requires it": `ImageRenderer.uiImage` (this task's brief: "renders a 9:16 exportable image
// via ImageRenderer") returns Foundation/UIKit's `UIImage`, and that's the practical type every
// share sheet (`ShareLink`, `UIActivityViewController`) and file-save path expects. No other part
// of this file touches UIKit.

import SwiftUI
import UIKit

/// One day's ring in the share card's 7-column week strip.
public struct ShareCardDayRing: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Fully-composed day label, e.g. `"Mon"`.
    public let label: String
    /// Completion fraction, `0...1`.
    public let progress: Double

    public init(id: UUID = UUID(), label: String, progress: Double) {
        self.id = id
        self.label = label
        self.progress = progress
    }
}

/// The data a `ShareCard` renders. A plain, `Sendable` value type so it can cross into the
/// `@MainActor` render call (`ShareCard.renderImage`) without any SwiftData/model dependency.
public struct ShareCardContent: Sendable {
    /// Fully-composed title, e.g. `"Week 6 · Rank Gold"`.
    public let title: String
    /// The week strip — typically 7 entries (Mon–Sun), per the P7 mockup, but this view lays out
    /// however many are supplied.
    public let dayRings: [ShareCardDayRing]
    /// Fully-composed stat line, e.g. `"4 workouts · 1,020g protein · 6h 40m time reclaimed"`.
    public let statLine: String
    /// Fully-composed highlight line, e.g. `"Best day: Thursday"`. Optional.
    public let highlightLine: String?
    /// Fully-composed footer/wordmark text (e.g. the app name), shown small, bottom-trailing per
    /// the P7 mockup ("small logo bottom right"). Optional and caller-composed — this file never
    /// hardcodes a brand string.
    public let footerLabel: String?

    public init(
        title: String,
        dayRings: [ShareCardDayRing],
        statLine: String,
        highlightLine: String? = nil,
        footerLabel: String? = nil
    ) {
        self.title = title
        self.dayRings = dayRings
        self.statLine = statLine
        self.highlightLine = highlightLine
        self.footerLabel = footerLabel
    }
}

/// A fixed 9:16 card suitable for exporting to an image (see `renderImage(content:size:scale:)`)
/// and sharing. On screen (e.g. a "preview before sharing" sheet) it scales to fit its container
/// via `.aspectRatio(_:contentMode: .fit)`; for export, `renderImage` gives it a concrete pixel
/// size first since `ImageRenderer` needs a resolved frame.
public struct ShareCard: View {
    private let content: ShareCardContent

    public init(content: ShareCardContent) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.background, Theme.Colors.surface],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(content.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)

                dayRingsStrip

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(content.statLine)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if let highlightLine = content.highlightLine {
                        Text(highlightLine)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }

                Spacer(minLength: 0)

                if let footerLabel = content.footerLabel {
                    HStack {
                        Spacer(minLength: 0)
                        Text(footerLabel)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
    }

    private var dayRingsStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(content.dayRings) { day in
                VStack(spacing: Theme.Spacing.xxs) {
                    GoalRing(progress: day.progress, color: Theme.Colors.accent, size: .small)
                    Text(day.label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

extension ShareCard {
    /// Renders `content` to a fixed-size, exportable `UIImage` via `ImageRenderer` (iOS 16+), per
    /// this task's brief. Must be called on the main actor — `ImageRenderer` drives SwiftUI's
    /// rendering pipeline, same as any other view render.
    ///
    /// - Parameters:
    ///   - content: The card's data.
    ///   - size: Output size in points. Defaults to 1080×1920 — a 9:16 frame matching common
    ///     share-image dimensions (Instagram/TikTok Stories) — so the default `scale` of `1`
    ///     already yields a 1080×1920px image with no extra multiplication.
    ///   - scale: Render scale applied on top of `size` (e.g. pass `2` for a 2160×3840px export).
    ///     Defaults to `1`.
    /// - Returns: The rendered image, or `nil` if `ImageRenderer` couldn't produce one.
    @MainActor
    public static func renderImage(
        content: ShareCardContent,
        size: CGSize = CGSize(width: 1080, height: 1920),
        scale: CGFloat = 1
    ) -> UIImage? {
        let card = ShareCard(content: content)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        return renderer.uiImage
    }
}
