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
// PASS 2 (2026-10-03, "make it more playful"): posters are collectibles now. Each has a hue
// (`PosterHue`), the background is an arcade room (hue blobs, a sunburst, a halftone field, a few
// fixed confetti sprinkles), the eyebrow is a tilted sticker pill and the hero sits on a die-cut
// sticker (white rim, hard offset shadow, slight tilt). Goal rings use the goal palette. The
// one-accent rule for share cards is retired for posters on the founder's call ("more playful");
// the wordmark and the star in the footer keep them recognisably ZANO's. Still no materials and no
// animation in a poster, and the star stays the static `ZanoMark`.
//
// PASS 3 (2026-10-03, restraint): posters stay bold, but the room keeps at most two decorative
// layers over the ink: one hue blob (top-right) and the sunburst. The partner blob, the halftone
// field and the confetti sprinkles are gone.
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
    /// The die-cut white rim around a sticker.
    static let stickerRim: CGFloat = 4
}

enum PosterType {
    /// The hero's digits: the arcade score face at a poster-only size.
    static let heroNumeral = Theme.Typography.score(size: 84)
    /// The hero's unit letters ("h", "m"): same face, a fraction of the digit size.
    static let heroUnit = Theme.Typography.score(size: 34, weight: .heavy)
    /// Display type for the locked-out headline.
    static let display = Font.system(size: 28, weight: .heavy, design: .rounded)
    /// A sticker label (eyebrow pills, chips).
    static let sticker = Font.system(size: 15, weight: .heavy, design: .rounded)
}

/// A poster's colour: every poster is a collectible in its own hue (pass 2, 2026-10-03). `ink` is
/// the text colour that reads on a solid fill of the hue.
enum PosterHue: CaseIterable, Sendable {
    case blue, ember, volt, pink, sun, violet, sky

    var color: Color {
        switch self {
        case .blue: Theme.Colors.accent
        case .ember: Theme.Colors.ember
        case .volt: Theme.Colors.Ring.workout
        case .pink: Theme.Colors.Ring.creatine
        case .sun: Theme.Colors.Ring.sunriseAlarm
        case .violet: Theme.Colors.Ring.focus
        case .sky: Theme.Colors.Ring.water
        }
    }

    /// The second colour of the hue's gradient and its background blob.
    var partner: Color {
        switch self {
        case .blue: Theme.Colors.Aurora.violet
        case .ember: Theme.Colors.Ring.creatine
        case .volt: Theme.Colors.Ring.steps
        case .pink: Theme.Colors.Aurora.violet
        case .sun: Theme.Colors.ember
        case .violet: Theme.Colors.accent
        case .sky: Theme.Colors.accent
        }
    }

    /// Text on a solid fill of `color`: ink on the light hues, white on the deep ones.
    var ink: Color {
        switch self {
        case .blue, .violet: Color.white
        case .ember, .volt, .pink, .sun, .sky: Theme.Colors.backgroundDeep
        }
    }

    /// The milestone burst's confetti: this hue first, then the rest of the goal palette.
    var sprinkles: [Color] {
        [color, partner, Theme.Colors.Ring.sunriseAlarm, Theme.Colors.Ring.water, Theme.Colors.Ring.creatine, Theme.Colors.Ring.workout]
    }
}

// MARK: - Chassis

/// The shared canvas: the arcade room (ink, one hue blob and a sunburst of rays from the top-right;
/// pass 3 caps the room at two decorative layers), the eyebrow as a tilted sticker pill at
/// the top of the safe area, the content between flexible spacers, and the wordmark at the bottom of
/// the safe area. Fixed 360 x 640, opaque, unclipped by any rounded shape.
struct PosterChassis<Content: View>: View {
    let eyebrow: String
    let footerLabel: String?
    let hue: PosterHue
    private let content: Content

    init(eyebrow: String, footerLabel: String?, hue: PosterHue = .blue, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.footerLabel = footerLabel
        self.hue = hue
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PosterRoom(hue: hue)

            VStack(alignment: .leading, spacing: 0) {
                PosterStickerPill(text: eyebrow, hue: hue)
                    .rotationEffect(.degrees(-4), anchor: .leading)

                Spacer(minLength: Theme.Spacing.md)
                content
                Spacer(minLength: Theme.Spacing.md)

                if let footerLabel {
                    HStack(spacing: Theme.Spacing.xs) {
                        // The real wordmark (docs/brand/brand-kit.md), not the name typed in a font.
                        ZanoWordmark(height: 12)
                            .accessibilityLabel(footerLabel)
                        Spacer(minLength: 0)
                        ZanoMark(height: 14, style: .brand)
                            .accessibilityHidden(true)
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

/// The poster's background artwork. Static (no animation, no material), so it rasterizes exactly.
private struct PosterRoom: View {
    let hue: PosterHue

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.background, Theme.Colors.backgroundDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [hue.color.opacity(0.45), hue.color.opacity(0)],
                center: UnitPoint(x: 0.85, y: 0.12),
                startRadius: 0,
                endRadius: PosterMetrics.canvas.width * 0.95
            )
            PosterRays()
                .fill(hue.color.opacity(0.10))
                .frame(width: 1100, height: 1100)
                .position(x: PosterMetrics.canvas.width * 0.85, y: PosterMetrics.canvas.height * 0.12)
        }
        .frame(width: PosterMetrics.canvas.width, height: PosterMetrics.canvas.height)
        .accessibilityHidden(true)
    }
}

/// Twenty thin wedges radiating from the centre of its frame.
private struct PosterRays: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let count = 20
        let step = 2 * Double.pi / Double(count)
        for index in 0..<count {
            let angle = Double(index) * step
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(angle - step * 0.25)),
                                     y: center.y + radius * CGFloat(sin(angle - step * 0.25))))
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(angle + step * 0.25)),
                                     y: center.y + radius * CGFloat(sin(angle + step * 0.25))))
            path.closeSubpath()
        }
        return path
    }
}

/// A pill sticker: solid hue, ink text, a white die-cut rim and a hard drop shadow.
struct PosterStickerPill: View {
    let text: String
    let hue: PosterHue
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))
            }
            Text(text)
                .font(PosterType.sticker)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(hue.ink)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs - 1)
        .background(hue.color, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2.5))
        .shadow(color: Color.black.opacity(0.45), radius: 0, x: 2, y: 3)
    }
}

extension View {
    /// Turns the content into a die-cut sticker: `fill` behind it, a thick white rim, a hard offset
    /// shadow (printed, not glowing), and a slight tilt.
    func posterSticker<Fill: ShapeStyle>(_ fill: Fill, radius: CGFloat = Theme.Radius.medium, tilt: Double = -2) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Color.white, lineWidth: PosterMetrics.stickerRim))
            .shadow(color: Color.black.opacity(0.5), radius: 0, x: 4, y: 6)
            .rotationEffect(.degrees(tilt))
    }
}

// MARK: - Weekly recap poster

struct PosterRingData: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let progress: Double
}

/// Weekly recap poster (docs/spec.md §5.14, §16 P7). Hero: the reclaimed-time value (or the
/// goals-completed count when nothing was reclaimed, so a zero never becomes the hero) on a hue
/// sticker; the goal rings below it in the goal palette.
struct RecapPoster: View {
    let title: String
    let heroValue: String
    let heroCaption: String
    let rings: [PosterRingData]
    let statLine: String?
    let highlightLine: String?
    let footerLabel: String?
    var hue: PosterHue = .sky

    var body: some View {
        PosterChassis(eyebrow: title, footerLabel: footerLabel, hue: hue) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                heroSticker

                if !rings.isEmpty {
                    PosterRingGrid(rings: rings)
                }

                if statLine != nil || highlightLine != nil {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let statLine {
                            PosterStickerPill(text: statLine, hue: .volt, systemImage: "checkmark")
                                .rotationEffect(.degrees(2), anchor: .leading)
                        }
                        if let highlightLine {
                            PosterStickerPill(text: highlightLine, hue: .sun, systemImage: "star.fill")
                                .rotationEffect(.degrees(-1.5), anchor: .leading)
                        }
                    }
                }
            }
        }
    }

    private var heroSticker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroAttributed)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text(heroCaption)
                .font(Font.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(hue.ink.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Theme.Spacing.md + 2)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .posterSticker(
            LinearGradient(colors: [hue.color, hue.partner], startPoint: .topLeading, endPoint: .bottomTrailing),
            tilt: -2.5
        )
    }

    /// Digits at hero size, everything else (unit letters, spaces) at unit size: the number is the
    /// poster, the unit is a label. Built by character so it works for any caller-composed duration
    /// string ("6h 40m", "45m", "12 of 14 goals") without parsing it.
    private var heroAttributed: AttributedString {
        var result = AttributedString()
        for character in heroValue {
            var piece = AttributedString(String(character))
            if character.isWholeNumber {
                piece.font = PosterType.heroNumeral
                piece.foregroundColor = hue.ink
            } else {
                piece.font = PosterType.heroUnit
                piece.foregroundColor = hue.ink.opacity(0.8)
            }
            result.append(piece)
        }
        return result
    }
}

/// The goal rings, sized from the content width so any count fits. Up to five per row; six or more
/// split into balanced rows; capped at ten. Each ring takes the next goal-palette colour.
private struct PosterRingGrid: View {
    let rings: [PosterRingData]

    private static let maxRings = 10
    private static let gap = Theme.Spacing.sm
    private static let maxDiameter: CGFloat = 52
    private static let palette: [Color] = [
        Theme.Colors.Ring.workout, Theme.Colors.Ring.protein, Theme.Colors.Ring.focus,
        Theme.Colors.Ring.water, Theme.Colors.Ring.creatine, Theme.Colors.Ring.sunriseAlarm,
        Theme.Colors.Ring.steps, Theme.Colors.Ring.mealPrep, Theme.Colors.Ring.stretchMobility,
        Theme.Colors.Ring.sleepOnTime,
    ]

    var body: some View {
        let visible = Array(rings.prefix(Self.maxRings))
        let count = max(visible.count, 1)
        let columns = count <= 5 ? count : Int((Double(count) / 2).rounded(.up))
        let cellWidth = (PosterMetrics.contentWidth - CGFloat(columns - 1) * Self.gap) / CGFloat(columns)
        let diameter = min(Self.maxDiameter, cellWidth)
        // Rows of indices into `visible`; the index also picks the ring's palette colour.
        let rows: [[Int]] = stride(from: 0, to: visible.count, by: columns).map { start in
            Array(start ..< min(start + columns, visible.count))
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(row, id: \.self) { index in
                        VStack(spacing: Theme.Spacing.xxs) {
                            PosterRing(
                                progress: visible[index].progress,
                                diameter: diameter,
                                color: Self.palette[index % Self.palette.count]
                            )
                            Text(visible[index].label)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.textSecondary)
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
}

private struct PosterRing: View {
    let progress: Double
    let diameter: CGFloat
    let color: Color

    private var clamped: Double { min(1, max(0, progress)) }
    private var line: CGFloat { diameter * 0.14 }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: line / 2)
                .stroke(Theme.Colors.Ring.track(for: color), lineWidth: line)

            if clamped > 0 {
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(clamped >= 1 ? 0.55 : 0), radius: 6)
            }
            if clamped >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.3, weight: .black))
                    .foregroundStyle(color)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Locked-out poster

/// Locked-Out Moment poster (docs/spec.md §5.16). Hero: the spec's own line on an ink sticker with
/// a pink "game over" hazard band and a lock sticker slapped on its corner. The attempt count is a
/// pink pill (`one sec`'s finding that showing how often you tried is what changes behavior,
/// `docs/design/competitive-research.md` 3.3); goals left and the streak are two more chips.
struct LockedOutPoster: View {
    let eyebrow: String
    let headline: String
    let statLine: String
    let chips: [String]
    let footerLabel: String?
    var hue: PosterHue = .pink

    var body: some View {
        PosterChassis(eyebrow: eyebrow, footerLabel: footerLabel, hue: hue) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headlineSticker
                    .overlay(alignment: .topTrailing) { lockSticker.offset(x: 10, y: -30) }
                    .padding(.top, Theme.Spacing.md)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    PosterStickerPill(text: statLine, hue: hue, systemImage: "hand.raised.fill")
                        .rotationEffect(.degrees(1.5), anchor: .leading)
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(PosterType.sticker)
                                .foregroundStyle(Theme.Colors.text)
                                .lineLimit(1)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs - 1)
                                .background(Theme.Colors.surface2, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                        }
                    }
                }
            }
        }
    }

    private var headlineSticker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HazardBand(color: hue.color)
                .frame(height: 14)
            Text(headline)
                .font(PosterType.display)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(5)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.md + 2)
                // The lock sticker sits on this card's top-right corner; keep the words clear of it.
                .padding(.trailing, 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .posterSticker(Theme.Colors.surface, tilt: -2)
    }

    private var lockSticker: some View {
        ZStack {
            Circle().fill(hue.color)
            Circle().strokeBorder(Color.white, lineWidth: PosterMetrics.stickerRim)
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(hue.ink)
        }
        .frame(width: 76, height: 76)
        .shadow(color: Color.black.opacity(0.5), radius: 0, x: 3, y: 5)
        .rotationEffect(.degrees(12))
        .accessibilityHidden(true)
    }
}

/// Diagonal hazard stripes: the "game over" tape across the top of the locked-out sticker.
private struct HazardBand: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.backgroundDeep))
            let stripe: CGFloat = 12
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
                path.addLine(to: CGPoint(x: x + stripe, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(color))
                x += stripe * 2
            }
        }
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
    /// An optional pause/play control drawn just before Close (the recap story's auto-advance).
    struct Playback {
        let isPaused: Bool
        let pauseLabel: String
        let playLabel: String
        let onToggle: () -> Void
    }

    let title: String?
    let dismissLabel: String
    var playback: Playback? = nil
    let onDismiss: () -> Void

    init(title: String?, dismissLabel: String, playback: Playback? = nil, onDismiss: @escaping () -> Void) {
        self.title = title
        self.dismissLabel = dismissLabel
        self.playback = playback
        self.onDismiss = onDismiss
    }

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
            if let playback {
                Button(action: playback.onToggle) {
                    headerDisc(systemImage: playback.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.pressable(scale: 0.92))
                .accessibilityLabel(playback.isPaused ? playback.playLabel : playback.pauseLabel)
            }
            Button(action: onDismiss) {
                headerDisc(systemImage: "xmark")
            }
            .buttonStyle(.pressable(scale: 0.92))
            .padding(.trailing, -Theme.Spacing.xxs)
            .accessibilityLabel(dismissLabel)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    /// A 32pt glass-free disc in a 44pt tappable frame.
    private func headerDisc(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(Theme.Typography.icon(.small, weight: .bold))
            .foregroundStyle(Theme.Colors.text)
            .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
            .background(Theme.Colors.surface2, in: Circle())
            .overlay {
                Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
            }
            .minTapTarget()
    }
}

/// The share action's face. A capsule at least `Theme.Metrics.primaryButtonHeight` tall (it mirrors
/// `PrimaryButton`, which cannot wrap a `ShareLink`: the link must own the tap). Ready is the one
/// blue-filled control on the screen (`accentFill` + `onAccent`, like `PrimaryButton`) (sharing is an action, not an earned state), with the same top-lit edge as `PrimaryButton`; preparing is a
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

    /// `onAccent` (white) on the blue fill, never `onFill`.
    private var foreground: Color {
        switch state {
        case .ready: Theme.Colors.onAccent
        case .preparing: Theme.Colors.muted
        case .failed: Theme.Colors.text
        }
    }

    private var fill: Color {
        switch state {
        // `accentFill`, not `accent`: the fill-safe blue (white on it is 5.27:1), as `PrimaryButton`.
        case .ready: Theme.Colors.accentFill
        case .preparing, .failed: Theme.Colors.surface2
        }
    }

    @ViewBuilder
    private var edge: some View {
        switch state {
        case .ready:
            // Pass 3 (restraint): a flat rim on a solid button.
            Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        case .preparing:
            Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        case .failed:
            Capsule().strokeBorder(Theme.Colors.danger.opacity(0.5), lineWidth: Theme.Metrics.edgeWidth)
        }
    }
}
