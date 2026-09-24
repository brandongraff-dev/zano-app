// RecapStoryPages.swift
// App / ZANO / Features / Share
//
// The pages of the weekly recap story (`WeeklyRecapShareView`): full-screen, one idea and one big
// number per page, like a year-in-review story but for a week. Spec section 5.14 (Weekly Report
// Card) lists what the recap shows: rings for the week, best day, time reclaimed, streak, rank
// movement. Every page here draws only from `RecapStoryData`, which the container derives from the
// `Recap` it already receives. No new data sources.
//
// Composition: each page has its own layout (centered star, bottom-left numeral, centered arc,
// split highs/lows, concentric rings, poster). The backdrop is one shared near-black canvas whose
// big soft blue/navy glow moves to a different spot per page, so page changes feel like one
// continuous surface. Entrances are springs staggered by element; Reduce Motion gets fades only,
// and the living star holds still on its own (`ZanoLivingMark` handles that).

import SwiftUI
import Core

// MARK: - Data

/// Everything the story shows, derived once from `Recap` + the caller's goal titles.
struct RecapStoryData {
    struct Ring: Identifiable {
        let id: UUID
        let title: String
        let progress: Double

        var percent: Int { Int((min(1, max(0, progress)) * 100).rounded()) }
    }

    let weekTitle: String
    let dateRange: String
    let timeReclaimedMinutes: Int
    let goalsCompleted: Int
    let goalsPlanned: Int
    let streak: Int
    let rankMovement: Int?
    let bestDay: String?
    /// Sorted by title for a stable order.
    let rings: [Ring]
    /// The Weekly Recap Writer's one-line insight, if it has run.
    let insight: String?

    /// Share of planned goals completed, 0...1. Drives the intro star's charge and page 3's arc.
    var completion: Double {
        guard goalsPlanned > 0 else { return goalsCompleted > 0 ? 1 : 0 }
        return min(1, Double(goalsCompleted) / Double(goalsPlanned))
    }

    /// The goal that pushed back hardest: the lowest unclosed ring, when there are at least two
    /// goals to compare. `RecapStats` has no per-weekday data, so there is no honest "worst day";
    /// this is the closest real signal.
    var toughest: Ring? {
        guard rings.count >= 2 else { return nil }
        return rings.filter { $0.progress < 1 }.min { $0.progress < $1.progress }
    }

    var closedRings: Int { rings.filter { $0.progress >= 1 }.count }
}

// MARK: - Pages

enum RecapStoryPage: Hashable {
    case intro, time, goals, days, rings, share

    /// Where the page's glow sits and how it is tinted. The backdrop animates between these.
    var glow: StoryGlow {
        switch self {
        case .intro: StoryGlow(center: UnitPoint(x: 0.5, y: 0.34), color: Theme.Colors.accent, intensity: 0.34)
        case .time: StoryGlow(center: UnitPoint(x: 0.95, y: 0.12), color: Theme.Colors.accent, intensity: 0.40)
        case .goals: StoryGlow(center: UnitPoint(x: 0.5, y: 0.5), color: Theme.Colors.accentDim, intensity: 0.75)
        case .days: StoryGlow(center: UnitPoint(x: 0.05, y: 0.22), color: Theme.Colors.accent, intensity: 0.30)
        case .rings: StoryGlow(center: UnitPoint(x: 0.5, y: 0.42), color: Theme.Colors.lockedAmbient, intensity: 0.95)
        case .share: StoryGlow(center: UnitPoint(x: 0.2, y: 0.85), color: Theme.Colors.accent, intensity: 0.26)
        }
    }
}

struct StoryGlow: Equatable {
    let center: UnitPoint
    let color: Color
    let intensity: Double
}

// MARK: - Backdrop

/// Near-black with one big soft glow and a faint navy counter-glow. The glow is a positioned circle
/// (not a `RadialGradient` center), so moving it between pages animates.
struct StoryBackdrop: View {
    let glow: StoryGlow

    var body: some View {
        GeometryReader { proxy in
            let size = max(proxy.size.width, proxy.size.height) * 1.1
            ZStack {
                Theme.Colors.background

                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.Colors.lockedAmbient.opacity(0.55), Theme.Colors.lockedAmbient.opacity(0)],
                        center: .center, startRadius: 0, endRadius: size * 0.4
                    ))
                    .frame(width: size * 0.8, height: size * 0.8)
                    .position(x: proxy.size.width * (1 - glow.center.x), y: proxy.size.height * (1.05 - glow.center.y))

                Circle()
                    .fill(RadialGradient(
                        colors: [glow.color.opacity(glow.intensity), glow.color.opacity(0)],
                        center: .center, startRadius: 0, endRadius: size * 0.5
                    ))
                    .frame(width: size, height: size)
                    .position(x: proxy.size.width * glow.center.x, y: proxy.size.height * glow.center.y)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Progress segments

/// Story-style segments across the top: done pages full, the current one filling, later ones empty.
struct StoryProgressSegments: View {
    let count: Int
    let index: Int
    /// 0...1 fill of the current segment.
    let progress: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(0 ..< count, id: \.self) { i in
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.Colors.track)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.Colors.text)
                                .frame(width: proxy.size.width * fill(for: i))
                        }
                }
                .frame(height: 3)
            }
        }
        .animation(.linear(duration: 0.05), value: progress)
        .accessibilityHidden(true)
    }

    private func fill(for i: Int) -> Double {
        if i < index { return 1 }
        if i > index { return 0 }
        return min(1, max(0, progress))
    }
}

// MARK: - Entrance

/// Staggered spring entrance: rises and settles in. Reduce Motion: a short fade, no movement.
private struct StoryReveal: ViewModifier {
    let appeared: Bool
    let delay: Double
    let distance: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : distance)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.94)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2).delay(delay * 0.3)
                    : .spring(response: 0.6, dampingFraction: 0.78).delay(delay),
                value: appeared
            )
    }
}

private extension View {
    func storyReveal(_ appeared: Bool, delay: Double = 0, distance: CGFloat = 28) -> some View {
        modifier(StoryReveal(appeared: appeared, delay: delay, distance: distance))
    }
}

/// The small uppercase accent label at the top of each page.
private struct StoryEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.captionEmphasized)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private enum StoryType {
    /// The biggest number on any page. Compressed heavy (numeral >= 60pt goes compressed).
    static let giant = Theme.Typography.numeral(size: 190, weight: .heavy)
    static let big = Theme.Typography.numeral(size: 120, weight: .heavy)
    static let dayName = Font.system(size: 76, weight: .heavy).width(.compressed)
}

// MARK: 1. Intro

struct RecapIntroPage: View {
    let data: RecapStoryData
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            ZanoLivingMark(charge: max(0.25, data.completion), height: 150)
                .storyReveal(appeared, delay: 0, distance: 0)
                .padding(.bottom, Theme.Spacing.md)

            VStack(spacing: Theme.Spacing.sm) {
                StoryEyebrow(text: data.weekTitle)
                    .storyReveal(appeared, delay: 0.15)
                Text(Copy.share.storyIntroHeadline)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .storyReveal(appeared, delay: 0.25)
                Text(data.dateRange)
                    .font(Theme.Typography.numeral(size: 28, weight: .bold))
                    .foregroundStyle(Theme.Colors.metallic)
                    .storyReveal(appeared, delay: 0.35)
                Text(Copy.share.storyIntroSubline)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .storyReveal(appeared, delay: 0.45)
            }

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.xxs) {
                Text(Copy.share.storyTapHint)
                Image(systemName: "chevron.right")
            }
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.muted)
            .storyReveal(appeared, delay: 0.8, distance: 8)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }
}

// MARK: 2. Time reclaimed

struct RecapTimePage: View {
    let data: RecapStoryData
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var minutes: Int { data.timeReclaimedMinutes }

    /// "6.7" (hours, one decimal, trailing ".0" dropped) or "45" (minutes).
    private var value: String {
        guard minutes >= 60 else { return "\(minutes)" }
        return (Double(minutes) / 60).formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // A huge, faint star as texture, bleeding off the top-right edge.
            ZanoMarkShape()
                .fill(Theme.Colors.accent.opacity(0.07), style: FillStyle(eoFill: true))
                .frame(width: 340 * ZanoMark.aspectRatio, height: 340)
                .offset(x: 150, y: -40)
                .rotationEffect(.degrees(appeared && !reduceMotion ? -8 : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 1.6), value: appeared)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                StoryEyebrow(text: Copy.progress.timeReclaimedTitle)
                    .storyReveal(appeared)

                Spacer(minLength: Theme.Spacing.lg)

                if minutes > 0 {
                    Text(appeared || reduceMotion ? value : "0")
                        .font(StoryType.giant)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .shadow(color: Theme.Colors.accent.opacity(0.55), radius: 40)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .spring(response: 1.0, dampingFraction: 0.9).delay(0.2), value: appeared)
                        .storyReveal(appeared, delay: 0.1, distance: 60)
                    Text(Copy.share.storyTimeUnit(minutes: minutes))
                        .font(Theme.Typography.numeral(size: 44, weight: .bold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.top, -Theme.Spacing.md)
                        .storyReveal(appeared, delay: 0.3)
                    Text(Copy.share.storyTimeCaption)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.md)
                        .storyReveal(appeared, delay: 0.45)
                } else {
                    Text(Copy.share.storyTimeEmptyHeadline)
                        .font(Theme.Typography.display)
                        .foregroundStyle(Theme.Colors.text)
                        .storyReveal(appeared, delay: 0.1)
                    Text(Copy.share.storyTimeEmptyCaption)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, Theme.Spacing.sm)
                        .storyReveal(appeared, delay: 0.25)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
        .onAppear { appeared = true }
    }
}

// MARK: 3. Goals earned + streak

struct RecapGoalsPage: View {
    let data: RecapStoryData
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            StoryEyebrow(text: Copy.share.storyGoalsEyebrow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .storyReveal(appeared)

            Spacer(minLength: 0)

            if data.goalsCompleted > 0 {
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.track, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: appeared || reduceMotion ? data.completion : 0)
                        .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.Colors.accent.opacity(0.6), radius: 16)
                        .animation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(0.25), value: appeared)

                    VStack(spacing: 0) {
                        Text(appeared || reduceMotion ? "\(data.goalsCompleted)" : "0")
                            .font(StoryType.big)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .spring(response: 1.0, dampingFraction: 0.9).delay(0.2), value: appeared)
                        Text(Copy.share.storyGoalsCaption(planned: data.goalsPlanned))
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    .padding(Theme.Spacing.xl)
                }
                .frame(width: 270, height: 270)
                .storyReveal(appeared, delay: 0.1, distance: 0)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    Text(Copy.share.storyGoalsEmptyHeadline)
                        .font(Theme.Typography.display)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.share.storyGoalsEmptyCaption)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                .storyReveal(appeared, delay: 0.1)
            }

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.sm) {
                if data.streak > 0 {
                    chip(icon: "flame.fill", text: Copy.share.storyStreakLine(days: data.streak))
                }
                if let rank = data.rankMovement, rank > 0 {
                    chip(icon: "arrow.up.right", text: Copy.share.storyRankUpLine(places: rank))
                }
            }
            .storyReveal(appeared, delay: 0.55)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
            Text(text)
                .foregroundStyle(Theme.Colors.text)
        }
        .font(Theme.Typography.headline)
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface.opacity(0.8), in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth) }
    }
}

// MARK: 4. Best day + toughest goal

struct RecapDaysPage: View {
    let data: RecapStoryData
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StoryEyebrow(text: Copy.share.storyDaysEyebrow)
                .storyReveal(appeared)

            Spacer(minLength: Theme.Spacing.lg)

            if let bestDay = data.bestDay {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Label(Copy.share.storyBestDayTitle, systemImage: "sun.max.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(bestDay)
                        .font(StoryType.dayName)
                        .foregroundStyle(Theme.Colors.metallic)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 30)
                    Text(Copy.share.storyBestDayCaption)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .storyReveal(appeared, delay: 0.1, distance: 40)
            }

            if data.bestDay != nil, data.toughest != nil {
                Rectangle()
                    .fill(Theme.Colors.hairline)
                    .frame(height: Theme.Metrics.edgeWidth)
                    .padding(.vertical, Theme.Spacing.xl)
                    .storyReveal(appeared, delay: 0.3, distance: 0)
            }

            if let toughest = data.toughest {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().stroke(Theme.Colors.track, lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: appeared || reduceMotion ? toughest.progress : 0)
                            .stroke(Theme.Colors.textSecondary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.5), value: appeared)
                        Text(Copy.share.storyPercent(toughest.percent))
                            .font(Theme.Typography.numeral(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Colors.text)
                    }
                    .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(Copy.share.storyToughestTitle)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(toughest.title)
                            .font(Theme.Typography.titleLarge)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(Copy.share.storyToughestCaption(goal: toughest.title, percent: toughest.percent))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .storyReveal(appeared, delay: 0.4, distance: 40)
            }

            Spacer(minLength: Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appeared = true }
    }
}

// MARK: 5. Rings

struct RecapRingsPage: View {
    let data: RecapStoryData
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxRings = 5
    private static let stroke: CGFloat = 18
    private static let gap: CGFloat = 6
    private static let diameter: CGFloat = 250

    private var visible: [RecapStoryData.Ring] { Array(data.rings.prefix(Self.maxRings)) }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                StoryEyebrow(text: Copy.share.storyRingsEyebrow)
                NumeralText(
                    Copy.share.storyRingsHeadline(closed: data.closedRings, total: data.rings.count),
                    size: .large
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .storyReveal(appeared)

            Spacer(minLength: 0)

            ZStack {
                ForEach(Array(visible.enumerated()), id: \.element.id) { offset, ring in
                    let inset = CGFloat(offset) * (Self.stroke + Self.gap)
                    let size = Self.diameter - 2 * inset
                    ZStack {
                        Circle().stroke(Theme.Colors.track, lineWidth: Self.stroke)
                        Circle()
                            .trim(from: 0, to: appeared || reduceMotion ? min(1, max(0, ring.progress)) : 0)
                            .stroke(Self.style(offset), style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Theme.Colors.accent.opacity(ring.progress >= 1 ? 0.5 : 0), radius: 10)
                            .animation(
                                reduceMotion ? nil : .spring(response: 1.1, dampingFraction: 0.85).delay(0.2 + Double(offset) * 0.12),
                                value: appeared
                            )
                    }
                    .frame(width: size - Self.stroke, height: size - Self.stroke)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .storyReveal(appeared, delay: 0.05, distance: 0)

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { offset, ring in
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle().fill(Self.style(offset)).frame(width: 10, height: 10)
                        Text(ring.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.sm)
                        Text(Copy.share.storyPercent(ring.percent))
                            .font(Theme.Typography.numeral(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .storyReveal(appeared, delay: 0.4 + Double(offset) * 0.06, distance: 12)
                }
            }

            if let insight = data.insight {
                Text(insight)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .storyReveal(appeared, delay: 0.75, distance: 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }

    /// Goals carry only a title here (no `GoalType`), so the per-type ring colors are not
    /// available. Instead the rings alternate ZANO Blue and the metallic silver, stepping down in
    /// strength inward: distinct enough for the legend, still one accent.
    private static func style(_ offset: Int) -> AnyShapeStyle {
        let strength = 1 - Double(offset / 2) * 0.3
        return offset.isMultiple(of: 2)
            ? AnyShapeStyle(Theme.Colors.accent.opacity(strength))
            : AnyShapeStyle(AnyShapeStyle(Theme.Colors.metallic).opacity(strength))
    }
}

// MARK: 6. Share card

struct RecapSharePage<Poster: View>: View {
    let poster: Poster
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                StoryEyebrow(text: Copy.share.storyShareEyebrow)
                Text(Copy.share.storyShareHeadline)
                    .font(Theme.Typography.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .storyReveal(appeared)

            // The exact poster that gets exported, scaled to fit (`SharePoster.swift`).
            SharePosterPreview(poster: poster)
                .scaleEffect(reduceMotion || appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.8).delay(0.1),
                    value: appeared
                )
        }
        .padding(.top, Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }
}
