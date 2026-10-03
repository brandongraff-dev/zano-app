// ProgressArcade.swift
// App / Features / Progress / Components
//
// Playful pass (2026-10-03, docs/design/visual-direction-v2.md, second pass on Progress). Screen-local
// pieces that make Progress read like an arcade's high-score wall instead of a stats page:
//
//   - `ProgressCandyBars`   the hero's 7-day chart: each earned day is a pill in its own candy
//                           colour (the goal-ring palette) that bounces up once when it appears.
//   - `ProgressStickerCell` one streak-calendar day as a sticker: earned days are ember stickers
//                           with a flame, slightly tilted like they were slapped on by hand.
//   - `RankMedal`           the rank as a collectible: a faceted hexagon medal in the tier's colour.
//   - `ProgressTrophyShelf` the Trophy Case entry as a shelf with badges standing on it.
//
// The shared design system (Core/UI) is owned by a parallel pass, so nothing here edits it. All
// motion runs once, in reply to the screen appearing or data changing, and is off under Reduce
// Motion.

import SwiftUI
import Core

// MARK: - Sticker tilts
//
// Pass 3 (restraint): the per-weekday candy palette is gone; earned week pills are one accent colour.

enum ProgressCandy {
    /// Hand-placed sticker tilts (degrees), cycled by cell index.
    static let tilts: [Double] = [-3, 2, -1.5, 3, -2.5, 1.5, -2]

    static func tilt(for index: Int) -> Double {
        tilts[((index % tilts.count) + tilts.count) % tilts.count]
    }
}

// MARK: - Hero chart

/// One bar in the hero's chart. Built by `ProgressView` from its `LockSession` rows.
struct ProgressCandyBar: Identifiable, Equatable {
    let id: Date
    let minutes: Int
    let isToday: Bool
    let isEarned: Bool
    let initial: String
    /// `Calendar.component(.weekday) - 1`, for the candy colour.
    let weekdayIndex: Int
}

/// Seven pills, oldest to today. Heights are linear in minutes against the busiest day; a zero day
/// is a small dot on the baseline. Earned days are their candy colour, other days the grey track.
/// The bars spring up from the baseline once, staggered, the first time the chart appears.
struct ProgressCandyBars: View {
    let bars: [ProgressCandyBar]
    let accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private let maxHeight: CGFloat = 76
    private let minHeight: CGFloat = 14
    private let zeroHeight: CGFloat = 8

    private var maxMinutes: Int { max(bars.map(\.minutes).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                column(bar, index: index)
            }
        }
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func height(for bar: ProgressCandyBar) -> CGFloat {
        guard bar.minutes > 0 else { return zeroHeight }
        let fraction = CGFloat(bar.minutes) / CGFloat(maxMinutes)
        return max(minHeight, fraction * maxHeight)
    }

    /// Pass 3 (restraint): every earned pill is the one accent colour (no per-weekday candy hues).
    private func fill(for bar: ProgressCandyBar) -> Color {
        bar.isEarned && bar.minutes > 0 ? Theme.Colors.accent : Theme.Colors.track
    }

    private func column(_ bar: ProgressCandyBar, index: Int) -> some View {
        let isUp = hasAppeared || reduceMotion
        return VStack(spacing: Theme.Spacing.xxs) {
            Capsule(style: .continuous)
                .fill(fill(for: bar))
                .frame(maxWidth: 26)
                .frame(height: height(for: bar))
                .scaleEffect(x: 1, y: isUp ? 1 : 0.02, anchor: .bottom)
                .animation(
                    reduceMotion ? nil : Animation.spring(response: 0.5, dampingFraction: 0.55).delay(Double(index) * 0.06),
                    value: isUp
                )
                .frame(height: maxHeight, alignment: .bottom)
            Text(bar.initial)
                .font(bar.isToday ? Theme.Typography.captionEmphasized : Theme.Typography.caption)
                .foregroundStyle(bar.isToday ? Theme.Colors.text : Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Streak sticker cell

/// One streak-calendar day. Head = the streak's newest day (a full ember sticker with a flame; pass 3:
/// no glow); earned = an ember-tinted sticker with a flame; today (not yet earned) = a dashed outline;
/// missed = a dim tile; future = a faint dashed outline. Earned stickers are tilted a hair, like
/// they were slapped on by hand. Decorative per cell: the grid speaks one sentence.
struct ProgressStickerCell: View {
    enum Kind { case head, earned, today, missed, future }

    let kind: Kind
    let index: Int

    private var isSticker: Bool { kind == .head || kind == .earned }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        shape
            .fill(fill)
            .overlay { edge(shape) }
            .overlay { glyph }
            .shadow(color: isSticker ? Color.black.opacity(0.3) : .clear, radius: 2, y: 2)
            .rotationEffect(.degrees(isSticker ? ProgressCandy.tilt(for: index) : 0))
            .aspectRatio(1, contentMode: .fit)
    }

    private var fill: Color {
        switch kind {
        case .head: Theme.Colors.ember
        case .earned: Theme.Colors.ember.opacity(0.3)
        case .missed: Theme.Colors.track.opacity(0.6)
        case .today, .future: Color.clear
        }
    }

    @ViewBuilder
    private func edge(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .head:
            shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
        case .earned:
            shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
        case .today:
            shape.strokeBorder(Theme.Colors.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        case .future:
            shape.strokeBorder(Theme.Colors.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        case .missed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .head:
            Image(systemName: "flame.fill")
                .font(Theme.Typography.icon(.xsmall, weight: .bold))
                .foregroundStyle(Theme.Colors.onFill)
        case .earned:
            Image(systemName: "flame.fill")
                .font(Theme.Typography.icon(.xsmall, weight: .bold))
                .foregroundStyle(Theme.Colors.ember)
        case .today, .missed, .future:
            EmptyView()
        }
    }
}

// MARK: - Rank medal

/// The rank as a collectible: a faceted hexagon medal in the tier's colour, an inner bevel ring, the
/// tier glyph in ink and a diagonal glint. During placement week it is an empty dashed socket with
/// the glyph in muted grey (what there is to win). Decorative: the card speaks the rank.
struct RankMedal: View {
    let rank: SeasonsAndRanks.Rank
    let isPlacement: Bool
    var size: CGFloat = 76

    static func color(for rank: SeasonsAndRanks.Rank) -> Color {
        switch rank {
        case .bronze: Theme.Colors.Ring.reading
        case .silver: Theme.Colors.textSecondary
        case .gold: Theme.Colors.Ring.sunriseAlarm
        case .platinum: Theme.Colors.Ring.coldShowerSauna
        case .diamond: Theme.Colors.Ring.stretchMobility
        }
    }

    private var tint: Color { Self.color(for: rank) }

    var body: some View {
        ZStack {
            if isPlacement {
                ProgressHexagon()
                    .fill(Theme.Colors.track.opacity(0.5))
                ProgressHexagon()
                    .stroke(Theme.Colors.hairlineStrong, style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [5, 4]))
            } else {
                ProgressHexagon()
                    .fill(tint)
                ProgressHexagon()
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                ProgressHexagon()
                    .stroke(Theme.Colors.onFill.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .scaleEffect(0.74)
                glint
            }
            Image(systemName: RankCard.glyph(for: rank))
                .font(.system(size: size * 0.32, weight: .black))
                .foregroundStyle(isPlacement ? Theme.Colors.muted : Theme.Colors.onFill)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(isPlacement ? 0 : -6))
        .accessibilityHidden(true)
    }

    private var glint: some View {
        Rectangle()
            .fill(Color.white.opacity(0.28))
            .frame(width: size * 0.16, height: size * 1.4)
            .rotationEffect(.degrees(30))
            .offset(x: -size * 0.16)
            .mask(ProgressHexagon())
    }
}

/// A pointy-top hexagon filling its rect.
struct ProgressHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for corner in 0..<6 {
            let angle = (Double(corner) * 60.0 - 90.0) * Double.pi / 180.0
            let point = CGPoint(
                x: Double(center.x) + Double(radius) * cos(angle),
                y: Double(center.y) + Double(radius) * sin(angle)
            )
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Trophy shelf

/// One badge on the shelf: an earned badge or a milestone not yet earned.
struct ProgressShelfItem: Identifiable {
    let id: String
    let key: String
    let isEarned: Bool
}

/// The Trophy Case entry as a shelf: a header (title, an "earned of total" chip, chevron) and up to
/// four badges standing on a glass plank, earned first. The whole card is the link (the caller wraps
/// it in a `NavigationLink`), so it speaks as one element.
struct ProgressTrophyShelf: View {
    let title: String
    let countText: String
    let items: [ProgressShelfItem]

    private let discDiameter: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            shelf
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium, tint: Theme.Colors.Ring.sunriseAlarm)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ZanoGlassChip(countText, systemImage: "trophy.fill", tint: Theme.Colors.Ring.sunriseAlarm)
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    private var shelf: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                    TrophyBadgeDisc(isEarned: item.isEarned, glyph: .forKey(item.key), diameter: discDiameter)
                        .rotationEffect(.degrees(item.isEarned ? ProgressCandy.tilt(for: index) : 0))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, -4)
            plank
        }
    }

    /// The glass plank the badges stand on: a lit top edge, a soft shadow under it.
    private var plank: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .frame(height: 10)
            .shadow(color: Color.black.opacity(0.45), radius: 6, y: 6)
    }
}
