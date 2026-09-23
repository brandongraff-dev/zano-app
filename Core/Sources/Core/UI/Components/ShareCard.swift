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
//
// Design-quality pass (docs/design/{better-ui BRK-03/04 DEP-04,typography-color T1,composition-audit
// #6,better-layout 8.1/8.2}):
//
//   * Preview == export, by construction. The card was laid out at whatever size it was given, with
//     fixed-point type (22pt title, 17pt stats, 44pt rings): rendered at 1080x1920 *points* its text
//     was ~2% of the image width against ~7% in the 320pt preview the user approved — the shared
//     PNG looked nothing like the preview, with microscopic text. It is now designed once on a
//     360x640pt canvas and *scaled* to fit whatever it is given, so any size/scale pair renders the
//     same picture. `renderImage` defaults to 360x640 at 3x (= 1080x1920 px).
//   * No baked-in rounded corners. The export used to `clipShape` a 28pt radius into the PNG, so
//     the image had transparent corners that Instagram and iMessage flatten to black or white. Only
//     the on-screen preview clips (and draws an edge); the export is a full-bleed rectangle.
//   * The ring strip fits. Fixed 44pt rings overflowed from the fifth (seven need 380pt in a 256pt
//     card). Rings are laid out in rows of up to seven on the canvas's own width, and wrap.
//   * There is a hero. The stat line is split on its separators and set as big numerals (44pt digits,
//     small unit) with the label beside each — the "chunky numerals" the spec asks for — under a
//     display-size title, over a static accent glow instead of a background -> surface gradient whose
//     top edge equalled the page (1.08:1, invisible, and prone to banding at 1080x1920).
//   * Content stays out of the Stories UI bands: the top and bottom ~11% of the canvas are margin,
//     and the wordmark sits at the bottom of the safe area, trailing (the P7 "small logo bottom
//     right"), not in the reply-bar zone.
//   * Deterministic: forced Dynamic Type `.large` and dark scheme, opaque fills only (no materials,
//     which `ImageRenderer` does not reproduce faithfully), no animation.

import SwiftUI
import UIKit
import Foundation

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
    /// however many are supplied (wrapping past seven, capped at fourteen).
    public let dayRings: [ShareCardDayRing]
    /// Fully-composed stat line, e.g. `"4 workouts · 1,020g protein · 6h 40m time reclaimed"`. Split
    /// on `·`, `•` and `|` into stat rows (numeral first, label beside it); a line with no
    /// separator is one row.
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
/// via `.aspectRatio(_:contentMode: .fit)`; for export, `renderImage` gives it a concrete size
/// first since `ImageRenderer` needs a resolved frame. Either way the *same* 360x640pt layout is
/// scaled, so what the user previews is what they post.
public struct ShareCard: View {

    /// The card's own design canvas (9:16). 360 x 3 = 1080 px wide, 640 x 3 = 1920 px tall.
    private static let canvas = CGSize(width: 360, height: 640)
    /// Stories overlays its own UI on roughly the outer 13% of a 9:16 frame (250px of 1920); content
    /// stays inside an 11% margin top and bottom.
    private static let safeInset = canvas.height * 0.11
    /// Width available to content between the `Theme.Spacing.lg` gutters.
    private static let contentWidth = canvas.width - 2 * Theme.Spacing.lg
    /// Most rings per row, and most rows.
    private static let ringsPerRow = 7
    private static let maxRingRows = 2
    private static let maxStats = 3
    private static let ringGap = Theme.Spacing.xs
    private static let maxRingDiameter: CGFloat = 44

    private let content: ShareCardContent
    /// `true` for the on-screen preview (rounded clip + edge); `false` for the export, which must be
    /// a full-bleed rectangle with no transparent corners.
    private let clipsToCard: Bool

    public init(content: ShareCardContent) {
        self.init(content: content, clipsToCard: true)
    }

    fileprivate init(content: ShareCardContent, clipsToCard: Bool) {
        self.content = content
        self.clipsToCard = clipsToCard
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.canvas.width
            poster
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .modifier(PreviewChrome(isEnabled: clipsToCard))
        // One image to VoiceOver: its texts read top to bottom as a single element.
        .accessibilityElement(children: .combine)
    }

    // MARK: - Poster

    private var poster: some View {
        ZStack(alignment: .topLeading) {
            Theme.Colors.background

            // A static accent glow behind the hero (spec §16: "subtle inner glow"). A radial wash
            // rather than the old background -> surface gradient, which was 1.08:1 end to end.
            RadialGradient(
                colors: [Theme.Colors.accent.opacity(0.24), Theme.Colors.accent.opacity(0)],
                center: UnitPoint(x: 0.15, y: 0.22),
                startRadius: 0,
                endRadius: Self.canvas.width * 1.15
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // This card's export path (`renderImage`) gives it a fixed frame with no scroll
                // fallback — text that grows past the frame is silently cut off, not truncated with
                // an ellipsis. Every string below is capped with an explicit `lineLimit` so a long
                // caller-composed sentence (a long app name, a long localized line) degrades to a
                // visible "…" instead of vanishing off the canvas. See
                // `docs/design/ui-stress-test-findings.md` §3.5.
                // Up to four lines: the locked-out card's title is a whole sentence ("My phone won't
                // let me open TikTok until I hit the gym.", 54 characters), and it is the hero.
                Text(content.title)
                    .zanoText(.display)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)

                if !content.dayRings.isEmpty {
                    ringStrip
                }

                Spacer(minLength: 0)

                statRows

                if let highlightLine = content.highlightLine {
                    highlightPill(highlightLine)
                }

                if let footerLabel = content.footerLabel {
                    HStack(spacing: Theme.Spacing.xs) {
                        Spacer(minLength: 0)
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: Theme.Spacing.xs, height: Theme.Spacing.xs)
                        Text(footerLabel)
                            .font(Theme.Typography.headline)
                            .tracking(2)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Self.safeInset)
            .padding(.bottom, Self.safeInset)
            .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        // A rectangle, never a rounded rect: the export must not carry transparent corners.
        .clipped()
        // A share image is an artifact, not UI: it must not change with the user's text size.
        .dynamicTypeSize(.large)
    }

    // MARK: - Ring strip

    private var ringRows: [[ShareCardDayRing]] {
        let capped = Array(content.dayRings.prefix(Self.ringsPerRow * Self.maxRingRows))
        return stride(from: 0, to: capped.count, by: Self.ringsPerRow).map { start in
            Array(capped[start ..< min(start + Self.ringsPerRow, capped.count)])
        }
    }

    private var ringStrip: some View {
        // One column count for every row, so a short last row stays on the rows above's grid.
        let columns = min(Self.ringsPerRow, max(1, content.dayRings.count))
        let cellWidth = (Self.contentWidth - CGFloat(columns - 1) * Self.ringGap) / CGFloat(columns)
        let diameter = min(Self.maxRingDiameter, cellWidth)

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(ringRows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Self.ringGap) {
                    ForEach(row) { day in
                        VStack(spacing: Theme.Spacing.xxs) {
                            GoalRing(progress: day.progress, color: Theme.Colors.accent, size: .custom(diameter))
                            Text(day.label)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: cellWidth)
                    }
                    ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                        Color.clear.frame(width: cellWidth, height: 1)
                    }
                }
            }
        }
    }

    // MARK: - Stats

    /// The stat line split into its pieces ("4 workouts", "1,020g protein", "6h 40m time reclaimed").
    private var statPieces: [String] {
        content.statLine
            .split(whereSeparator: { $0 == "·" || $0 == "•" || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(Self.maxStats)
            .map { $0 }
    }

    private var statRows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(statPieces.enumerated()), id: \.offset) { _, piece in
                statRow(piece)
            }
        }
    }

    /// A stat as a big numeral with its label beside it on the baseline. A piece with no numeric
    /// lead is shown as a plain line instead of the same words twice.
    @ViewBuilder
    private func statRow(_ piece: String) -> some View {
        if NumeralText.hasNumeral(piece) {
            let rest = NumeralText.remainder(of: piece)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                NumeralText(piece, size: .large, remainder: .hidden)
                    .fixedSize()
                if !rest.isEmpty {
                    Text(rest)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        } else {
            Text(piece)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
        }
    }

    private func highlightPill(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "star.fill")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        // 28pt on a ~34pt-tall pill clamps to a full capsule.
        .zanoCard(radius: Theme.Radius.large)
    }
}

/// The on-screen-only card chrome: a large-radius clip with a top-lit edge. The export skips it.
private struct PreviewChrome: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                        .strokeBorder(Theme.Colors.edgeGradient(), lineWidth: Theme.Metrics.edgeWidth)
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}

extension ShareCard {
    /// Renders `content` to a fixed-size, exportable `UIImage` via `ImageRenderer` (iOS 16+), per
    /// this task's brief. Must be called on the main actor — `ImageRenderer` drives SwiftUI's
    /// rendering pipeline, same as any other view render.
    ///
    /// The card scales its 360x640 layout to fit `size`, so any `size`/`scale` pair yields the same
    /// picture — only the pixel count changes.
    ///
    /// - Parameters:
    ///   - content: The card's data.
    ///   - size: Layout size in points. Defaults to 360x640 (9:16), the card's design canvas.
    ///   - scale: Render scale applied on top of `size`. Defaults to `3`, so the default yields a
    ///     1080x1920px image — a 9:16 frame matching common share-image dimensions (Instagram/TikTok
    ///     Stories).
    /// - Returns: The rendered image, or `nil` if `ImageRenderer` couldn't produce one.
    @MainActor
    public static func renderImage(
        content: ShareCardContent,
        size: CGSize = CGSize(width: 360, height: 640),
        scale: CGFloat = 3
    ) -> UIImage? {
        let card = ShareCard(content: content, clipsToCard: false)
            .frame(width: size.width, height: size.height)
            // An export made while the system is in Light mode must not pick up any light-mode
            // resolution of an adaptive color.
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        return renderer.uiImage
    }
}

#Preview("ShareCard") {
    ShareCard(
        content: ShareCardContent(
            title: "Week 6 · Rank Gold",
            dayRings: [
                ShareCardDayRing(label: "Mon", progress: 1.0),
                ShareCardDayRing(label: "Tue", progress: 1.0),
                ShareCardDayRing(label: "Wed", progress: 0.6),
                ShareCardDayRing(label: "Thu", progress: 1.0),
                ShareCardDayRing(label: "Fri", progress: 0.3),
                ShareCardDayRing(label: "Sat", progress: 0.0),
                ShareCardDayRing(label: "Sun", progress: 0.8)
            ],
            statLine: "4 workouts · 1,020g protein · 6h 40m time reclaimed",
            highlightLine: "Best day: Thursday",
            footerLabel: "ZANO"
        )
    )
    .frame(width: 300)
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
