// RankCard.swift
// App / Features / Progress
//
// docs/spec.md §5.9 (Ranks: Bronze → Diamond on 4-week consistency, not volume; quarterly seasons)
// and §8 rules 9-10 (no shame; show what's at stake, never as a threat). Wave 3J.
//
// Everything is computed on this iPhone by `SeasonsAndRanks.currentRank(asOf:)` from local
// `GoalEvent`s — no network, so the card is always live. The caller loads the `RankStatus` and
// passes it in; this view only draws it.
//
// Design (playful pass 2026-10-03, visual direction v2 second pass): the rank is a collectible.
// A faceted hexagon medal in the tier's colour (`RankMedal`, Components/ProgressArcade.swift), the
// rank name beside it in the tier colour, then a chunky meter toward the next tier with the four
// weekly buckets as small pills. The explainer line moved into an info button; the season end is a
// chip. On narrow screens (iPhone SE) and accessibility sizes the footer stacks instead of squeezing.

import SwiftUI
import Core

struct RankCard: View {
    let status: SeasonsAndRanks.RankStatus
    /// Days until the season ranks for real (`SeasonsAndRanks.placementDaysRemaining`).
    let placementDaysLeft: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var rankSize: CGFloat = 34

    private var consistencyPercent: Int { Int((status.consistency * 100).rounded()) }
    private var progressPercent: Int { Int((status.progressToNextRank * 100).rounded()) }
    private var tint: Color { RankMedal.color(for: status.rank) }

    private var seasonLastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: status.season.endDate) ?? status.season.endDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            topRow
            meterRow
            footer
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium, tint: status.isPlacement ? nil : tint)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            RankMedal(rank: status.rank, isPlacement: status.isPlacement)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.progress.seasonLabel(quarter: status.season.quarter, year: status.season.year))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(Copy.progress.rankName(status.rank))
                    .font(.system(size: rankSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(status.isPlacement ? Theme.Colors.textSecondary : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.progress.rankConsistencyAccessibility(rank: status.rank, percent: consistencyPercent))
            .accessibilityValue(progressLine)

            Spacer(minLength: 0)

            ZanoInfoButton(Copy.progress.rankExplainer, accessibilityLabel: Copy.progress.rankInfoAccessibilityLabel)
        }
    }

    private var meterRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            progressBar
            WeeklyTicks(values: status.weeklyConsistency, tint: status.isPlacement ? Theme.Colors.accent : tint)
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                progressText
                Spacer(minLength: Theme.Spacing.xs)
                endsChip
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                progressText
                endsChip
            }
        }
    }

    private var progressText: some View {
        Text(progressLine)
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var endsChip: some View {
        ZanoGlassChip(Copy.progress.seasonEndsLabel(lastDay: seasonLastDay), systemImage: "hourglass", tint: Theme.Colors.muted)
    }

    private var progressLine: String {
        if status.isPlacement { return Copy.progress.rankPlacementLabel(daysLeft: placementDaysLeft) }
        guard let next = status.nextRank else { return Copy.progress.rankTopLabel }
        return Copy.progress.rankProgressLabel(percent: progressPercent, next: next)
    }

    /// A chunky lit tube toward the next tier, in the tier's colour.
    private var progressBar: some View {
        let fill = status.isPlacement ? Theme.Colors.accent : tint
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(fill.opacity(0.18))
                Capsule()
                    .fill(fill)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(height: 3)
                            .padding(.horizontal, 6)
                            .padding(.top, 3)
                    }
                    .frame(width: max(14, proxy.size.width * status.progressToNextRank))
                    .animation(reduceMotion ? nil : Theme.Motion.springPop, value: status.progressToNextRank)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// One medal glyph per tier; the disc's metal (earned) carries the "achieved" meaning.
    static func glyph(for rank: SeasonsAndRanks.Rank) -> String {
        switch rank {
        case .bronze: "shield"
        case .silver: "shield.lefthalf.filled"
        case .gold: "shield.fill"
        case .platinum: "star.fill"
        case .diamond: "diamond.fill"
        }
    }
}

/// Up to four small bars, oldest → newest: this user's own-cadence consistency per week.
private struct WeeklyTicks: View {
    let values: [Double]
    var tint: Color = Theme.Colors.accent

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Capsule(style: .continuous)
                    .fill(value >= 1 ? tint : Theme.Colors.hairlineStrong)
                    .frame(width: 6, height: 8 + 16 * CGFloat(min(1, max(0, value))))
            }
        }
        .frame(height: 24, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
