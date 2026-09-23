// SharePoster.swift
// App / Features / Share
//
// The exportable artwork and shared chrome for `WeeklyRecapShareView` and `LockedOutMomentView`.
// Design wave 2026-09-23.
//
// WHY THIS EXISTS. Both share screens used to render through `Core`'s `ShareCard`. Reading that
// path, three independent audits (`docs/design/better-ui-findings.md` BRK-03/04, `better-layout-
// findings.md` H4/8.1, `typography-color-findings.md` T1, `composition-audit.md` offender 6) found
// the same defects, none fixable from a Feature file while `ShareCard` is used as-is:
//
//   1. Export != preview. `ShareCard.renderImage` lays the card out at 1080 x 1920 *points* at
//      scale 1, but every type token is a fixed point size (22pt title, 17pt stats, 44pt rings). The
//      shared PNG has its text at ~2% of image width versus ~7% in the on-screen preview: what the
//      user approved is not what they post.
//   2. The ring strip is fixed-size (`GoalRing(.small)`, 44pt each), so 5+ rings overflow a 320pt
//      card and are cut by the card's clip. The P7 mock's 7 rings need 380pt.
//   3. No hero. The most-shared artefact in the product had no number larger than 22pt: three lines
//      of text on a gradient whose top edge equals the page background.
//   4. `ShareCard` bakes a rounded `clipShape` into the exported image, so the PNG has transparent
//      corners that Instagram and iMessage flatten to black or white.
//
// So the two screens render their own posters, designed once at a fixed 360 x 640pt logical canvas
// and exported at scale 3 (= 1080 x 1920 px). The on-screen preview is *the same view* scaled to
// fit, so preview and export match by construction. `ShareCard` is untouched and still serves
// `PreviewCatalog`; nothing here edits it.
//
// DESIGN. Opaque, one accent (spec section 15: a share card must be recognizable as ZANO's),
// content kept out of the top ~14% and bottom ~15% of the canvas (the Stories UI overlays those
// bands: `docs/design/better-ui-findings.md` BRK-03), a static radial accent glow behind the hero
// (spec section 16 "subtle inner glow"), and a single hero element per poster:
//
//   * Weekly recap: TIME RECLAIMED is the hero numeral (competitive-research 3.8: it is the number
//     people screenshot), with the goal rings below it sized from the available width so any goal
//     count fits, and goals completed / best day beneath.
//   * Locked out: the spec's own line ("My phone won't let me open TikTok until I hit the gym.") is
//     the hero, set as display type over a lock medallion, with the attempt count as a stat pill.
//
// TYPE. Poster type is fixed-canvas artwork rasterized to an image, so it must NOT follow the user's
// Dynamic Type setting: on screen it would scale while the exported PNG (rendered in a default
// environment) would not, and preview != export again. `PosterChassis` therefore pins
// `.dynamicTypeSize(.large)` on the whole poster. The hero digits use `Theme.Typography.numeral(size:)`
// (the same rounded, monospaced numeral face as the rest of the app) at a poster-only 96pt, which is
// deliberately larger than `Theme.Typography.numeralHero` (72pt, sized for a phone screen).
//
// No animation lives in a poster (an animation can be mid-flight when `ImageRenderer` rasterizes it).
// The screens' own entrance/transition animations stay in the two view files, each gated on
// `accessibilityReduceMotion`.
//
// NOT VERIFIED (no Mac/Simulator in this environment): every size here is layout arithmetic on the
// 360 x 640 canvas. In particular the hero numeral's fit for long durations relies on
// `minimumScaleFactor`, and `ImageRenderer`'s output for `RadialGradient` + `shadow` (expected to
// render faithfully; materials are deliberately not used).

import SwiftUI
import UIKit
import Core

// MARK: - Metrics and type

enum PosterMetrics {
    /// Logical canvas. 9:16.
    static let canvas = CGSize(width: 360, height: 640)
    /// 360 x 3 = 1080 px wide, 640 x 3 = 1920 px tall.
    static let exportScale: CGFloat = 3
    /// Stories overlays its own UI on roughly the outer 13% of a 9:16 frame (250px of 1920).
    static let safeTop: CGFloat = canvas.height * 0.14
    static let safeBottom: CGFloat = canvas.height * 0.15
    /// Width available to poster content between the `Theme.Spacing.lg` gutters.
    static let contentWidth: CGFloat = canvas.width - 2 * Theme.Spacing.lg
}

enum PosterType {
    /// The hero's digits. The app's numeral face (rounded, heavy, tabular) at a poster-only size.
    static let heroNumeral = Theme.Typography.numeral(size: 96, weight: .heavy)
    /// The hero's unit letters ("h", "m"): same face, deliberately a fraction of the digit size.
    static let heroUnit = Theme.Typography.numeral(size: 40, weight: .bold)
    /// Display type for the locked-out headline.
    static let display = Font.system(size: 30, weight: .heavy, design: .rounded)
}

// MARK: - Chassis

/// The shared canvas: `background`, one accent glow, the eyebrow at the top of the safe area, the
/// hero content vertically centred between flexible spacers, and the wordmark at the bottom of the
/// safe area. Fixed 360 x 640, unclipped by any rounded shape (no baked-in rounded corners; the
/// on-screen preview clips separately, the export does not).
struct PosterChassis<Content: View>: View {
    let eyebrow: String
    let footerLabel: String?
    private let content: Content

    init(eyebrow: String, footerLabel: String?, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.footerLabel = footerLabel
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Colors.background

            RadialGradient(
                colors: [Theme.Colors.accent.opacity(0.26), Theme.Colors.accent.opacity(0)],
                center: UnitPoint(x: 0.2, y: 0.3),
                startRadius: 0,
                endRadius: PosterMetrics.canvas.width * 1.1
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(Theme.Typography.captionEmphasized)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: Theme.Spacing.lg)
                content
                Spacer(minLength: Theme.Spacing.lg)

                if let footerLabel {
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 8, height: 8)
                        Text(footerLabel)
                            .font(Theme.Typography.headline)
                            .tracking(2)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, PosterMetrics.safeTop)
            .padding(.bottom, PosterMetrics.safeBottom)
        }
        .frame(width: PosterMetrics.canvas.width, height: PosterMetrics.canvas.height)
        .clipped()
        // Pinned to the default text size so the on-screen preview lays out exactly like the export
        // (see the TYPE note in the file header).
        .dynamicTypeSize(.large)
        // The poster is one image to VoiceOver: its texts read top to bottom as a single element.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Weekly recap poster

struct PosterRingData: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let progress: Double
}

/// Weekly recap poster (docs/spec.md §5.14, §16 P7). Hero: the reclaimed-time value (or the
/// goals-completed count when nothing was reclaimed, so a zero never becomes the hero).
struct RecapPoster: View {
    let title: String
    let heroValue: String
    let heroCaption: String
    let rings: [PosterRingData]
    let statLine: String?
    let highlightLine: String?
    let footerLabel: String?

    var body: some View {
        PosterChassis(eyebrow: title, footerLabel: footerLabel) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(heroAttributed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 24)
                    Text(heroCaption)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                }

                if !rings.isEmpty {
                    PosterRingGrid(rings: rings)
                }

                if statLine != nil || highlightLine != nil {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        if let statLine {
                            Text(statLine)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.text)
                                .lineLimit(2)
                        }
                        if let highlightLine {
                            Text(highlightLine)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.muted)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    /// Digits at hero size in accent, everything else (unit letters, spaces) at unit size in muted:
    /// the number is the poster, the unit is a label. Built by character so it works for any
    /// caller-composed duration string ("6h 40m", "45m", "12 of 14 goals") without parsing it.
    private var heroAttributed: AttributedString {
        var result = AttributedString()
        for character in heroValue {
            var piece = AttributedString(String(character))
            if character.isWholeNumber {
                piece.font = PosterType.heroNumeral
                piece.foregroundColor = Theme.Colors.accent
            } else {
                piece.font = PosterType.heroUnit
                piece.foregroundColor = Theme.Colors.muted
            }
            result.append(piece)
        }
        return result
    }
}

/// The goal rings, sized from the content width so any count fits (the old strip used fixed 44pt
/// rings and overflowed at five). Up to five per row; six or more split into balanced rows; capped
/// at ten (two rows of five), which no realistic goal set reaches. Accent-only, per the one-accent
/// rule for share cards. A completed ring gets a static glow.
private struct PosterRingGrid: View {
    let rings: [PosterRingData]

    private static let maxRings = 10
    private static let gap = Theme.Spacing.sm
    private static let maxDiameter: CGFloat = 52

    var body: some View {
        let visible = Array(rings.prefix(Self.maxRings))
        let count = max(visible.count, 1)
        let columns = count <= 5 ? count : Int((Double(count) / 2).rounded(.up))
        let cellWidth = (PosterMetrics.contentWidth - CGFloat(columns - 1) * Self.gap) / CGFloat(columns)
        let diameter = min(Self.maxDiameter, cellWidth)
        let rows: [[PosterRingData]] = stride(from: 0, to: visible.count, by: columns).map { start in
            Array(visible[start ..< min(start + columns, visible.count)])
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(row) { ring in
                        VStack(spacing: Theme.Spacing.xxs) {
                            PosterRing(progress: ring.progress, diameter: diameter)
                            Text(ring.label)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: cellWidth)
                    }
                    // Keeps a short last row aligned to the same column grid as the rows above.
                    ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                        Color.clear.frame(width: cellWidth, height: 1)
                    }
                }
            }
        }
    }
}

private struct PosterRing: View {
    let progress: Double
    let diameter: CGFloat

    private var clamped: Double { min(1, max(0, progress)) }
    private var line: CGFloat { diameter * 0.12 }

    var body: some View {
        ZStack {
            // The neutral track (`Theme.Colors.track`, white at 16%) rather than the accent at 30%:
            // a share card is accent-only, and an accent-tinted empty ring would read as progress.
            Circle()
                .inset(by: line / 2)
                .stroke(Theme.Colors.track, lineWidth: line)

            if clamped > 0 {
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0, to: clamped)
                    .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.Colors.accent.opacity(clamped >= 1 ? 0.4 : 0), radius: 6)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Locked-out poster

/// Locked-Out Moment poster (docs/spec.md §5.16). Hero: the spec's own line as display type over a
/// lock medallion. The attempt count is a stat pill (`one sec`'s finding that showing how often you
/// tried is what changes behavior, `docs/design/competitive-research.md` 3.3).
struct LockedOutPoster: View {
    let eyebrow: String
    let headline: String
    let statLine: String
    let highlightLine: String?
    let footerLabel: String?

    var body: some View {
        PosterChassis(eyebrow: eyebrow, footerLabel: footerLabel) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                medallion

                Text(headline)
                    .font(PosterType.display)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "hand.raised.fill")
                            .font(Theme.Typography.icon(.small))
                            .foregroundStyle(Theme.Colors.accent)
                        Text(statLine)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    // 28pt radius on a ~40pt-tall pill clamps to a full capsule.
                    .zanoCard(radius: Theme.Radius.large)

                    if let highlightLine {
                        Text(highlightLine)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.muted)
                            .lineLimit(2)
                            .padding(.leading, Theme.Spacing.xxs)
                    }
                }
            }
        }
    }

    private var medallion: some View {
        ZStack {
            Circle().fill(Theme.Colors.surface)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.Colors.accent.opacity(0.7), Theme.Colors.accent.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
            // Artwork inside a fixed 96pt medallion (`Theme.Metrics.iconBadgeLarge`): a literal size,
            // not a text-relative icon.
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
        }
        .frame(width: Theme.Metrics.iconBadgeLarge, height: Theme.Metrics.iconBadgeLarge)
        .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 28)
    }
}

// MARK: - Rendering and preview

/// Rasterizes a poster at 360 x 640 logical points, scale 3 (1080 x 1920 px). Main-actor only,
/// like every `ImageRenderer` use. Forces the dark color scheme into the rendered environment so an
/// export made while the system is in Light mode cannot pick up light-mode resolution of any
/// adaptive color.
@MainActor
enum SharePosterRenderer {
    static func image<Poster: View>(of poster: Poster) -> UIImage? {
        let renderer = ImageRenderer(content: poster.environment(\.colorScheme, .dark))
        renderer.scale = PosterMetrics.exportScale
        return renderer.uiImage
    }
}

/// The on-screen preview: the exact poster view, scaled to fit the space it is given (never
/// upscaled past 1x), clipped to a large radius with a top-lit edge and a static accent glow. The
/// clip, edge and glow are preview-only; none of them are in the exported image.
struct SharePosterPreview<Poster: View>: View {
    let poster: Poster

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                1,
                proxy.size.width / PosterMetrics.canvas.width,
                proxy.size.height / PosterMetrics.canvas.height
            )
            poster
                .scaleEffect(scale)
                .frame(
                    width: PosterMetrics.canvas.width * scale,
                    height: PosterMetrics.canvas.height * scale
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Theme.Colors.hairlineStrong, Theme.Colors.hairline],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: Theme.Metrics.edgeWidth
                        )
                        .allowsHitTesting(false)
                }
                .shadow(color: Theme.Colors.accent.opacity(0.18), radius: 28)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Shared screen chrome

/// The three states of the share action, shared by both screens (each used to declare its own
/// private copy of this enum).
enum ShareRenderState: Equatable {
    case preparing
    case ready
    case failed
}

/// Screen header: an optional title and a single dismiss control. The dismiss glyph stays a 32pt
/// circle; its tappable frame is 44pt (`HIT-01`: it used to be a bare 22pt glyph). This is the
/// screen's only dismiss: the footer "Close"/"Not now" text buttons that duplicated it were removed
/// (`docs/design/composition-audit.md` offender 6). Pass `title: nil` when the poster already carries
/// the screen's title as its own eyebrow.
struct ShareMomentHeader: View {
    let title: String?
    let dismissLabel: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let title {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(Theme.Typography.icon(.small, weight: .bold))
                    .foregroundStyle(Theme.Colors.text)
                    .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
                    .background(Theme.Colors.surface2, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                    }
                    .minTapTarget()
            }
            .buttonStyle(.pressable(scale: 0.92))
            .padding(.trailing, -Theme.Spacing.xxs)
            .accessibilityLabel(dismissLabel)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }
}

/// The share action's face. A capsule at least `Theme.Metrics.primaryButtonHeight` tall (it mirrors
/// `PrimaryButton`, which cannot wrap a `ShareLink`: the link must own the tap). Ready is the one
/// accent-filled control on the screen, with the same top-lit edge as `PrimaryButton`; preparing is a
/// neutral `surface2` state, not a dimmed accent slab (`docs/design/better-ui-findings.md` MOT-04);
/// failed is a neutral retry with a danger edge, so it does not read as another affirmative "share
/// now". Wrap it in a `Button`/`ShareLink` styled with `.pressable`.
struct ShareActionLabel: View {
    let state: ShareRenderState

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            leading
            Text(title)
                .font(Theme.Typography.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
        .foregroundStyle(foreground)
        .background(fill, in: Capsule())
        .overlay { edge }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var leading: some View {
        switch state {
        case .ready:
            Image(systemName: "square.and.arrow.up")
                .font(Theme.Typography.icon(.medium))
        case .preparing:
            // `SwiftUI.ProgressView` spelled out fully: this module also declares
            // `App/ZANO/Features/Progress/ProgressView.swift`'s `struct ProgressView: View` (the
            // Progress *screen*) at module scope, so an unqualified `ProgressView()` here would
            // silently resolve to that screen instead of the system spinner (both are
            // zero-argument-constructible `View`s, so it compiles with no error and is just wrong).
            SwiftUI.ProgressView()
                .tint(Theme.Colors.muted)
        case .failed:
            Image(systemName: "arrow.clockwise")
                .font(Theme.Typography.icon(.medium))
        }
    }

    private var title: String {
        switch state {
        case .ready: Copy.share.shareButtonTitle
        case .preparing: Copy.share.preparingShareTitle
        case .failed: Copy.share.shareFailedRetryLabel
        }
    }

    /// `onFill` (16.4:1) on the accent fill, never `text` (1.11:1).
    private var foreground: Color {
        switch state {
        case .ready: Theme.Colors.onFill
        case .preparing: Theme.Colors.muted
        case .failed: Theme.Colors.text
        }
    }

    private var fill: Color {
        switch state {
        case .ready: Theme.Colors.accent
        case .preparing, .failed: Theme.Colors.surface2
        }
    }

    @ViewBuilder
    private var edge: some View {
        switch state {
        case .ready:
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [Theme.Colors.specular, Theme.Colors.specular.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: Theme.Metrics.edgeWidth
            )
        case .preparing:
            Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        case .failed:
            Capsule().strokeBorder(Theme.Colors.danger.opacity(0.5), lineWidth: Theme.Metrics.edgeWidth)
        }
    }
}
