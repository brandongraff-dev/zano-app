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
// Design: the rank name is the numeral (compressed heavy face) filled with `metallic`, the earned
// metal. The medal disc is the same `TrophyBadgeDisc` the Trophy Case uses (earned = silver). The
// progress to the next rank is a thin accent bar under it, with the four weekly buckets as small
// ticks beside the season line so "consistency" is visible, not just claimed.

import SwiftUI
import Core

struct RankCard: View {
    let status: SeasonsAndRanks.RankStatus
    /// Days until the season ranks for real (`SeasonsAndRanks.placementDaysRemaining`).
    let placementDaysLeft: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var rankSize: CGFloat = 44

    private var consistencyPercent: Int { Int((status.consistency * 100).rounded()) }
    private var progressPercent: Int { Int((status.progressToNextRank * 100).rounded()) }

    private var seasonLastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: status.season.endDate) ?? status.season.endDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                TrophyBadgeDisc(
                    isEarned: !status.isPlacement,
                    systemImage: Self.glyph(for: status.rank),
                    diameter: 56
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.progress.seasonLabel(quarter: status.season.quarter, year: status.season.year))
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)

                    Text(Copy.progress.rankName(status.rank))
                        .font(Theme.Typography.numeral(size: rankSize, weight: .heavy))
                        .foregroundStyle(status.isPlacement ? AnyShapeStyle(Theme.Colors.textSecondary) : AnyShapeStyle(Theme.Colors.metallic))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                WeeklyTicks(values: status.weeklyConsistency)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                progressBar
                Text(progressLine)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(Copy.progress.rankExplainer)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(Copy.progress.seasonEndsLabel(lastDay: seasonLastDay))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.progress.rankConsistencyAccessibility(rank: status.rank, percent: consistencyPercent))
        .accessibilityValue(progressLine)
    }

    private var progressLine: String {
        if status.isPlacement { return Copy.progress.rankPlacementLabel(daysLeft: placementDaysLeft) }
        guard let next = status.nextRank else { return Copy.progress.rankTopLabel }
        return Copy.progress.rankProgressLabel(percent: progressPercent, next: next)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surface2)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: max(6, proxy.size.width * status.progressToNextRank))
                    .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: status.progressToNextRank)
            }
        }
        .frame(height: 6)
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(value >= 1 ? Theme.Colors.accent : Theme.Colors.hairlineStrong)
                    .frame(width: 6, height: 8 + 20 * CGFloat(min(1, max(0, value))))
            }
        }
        .frame(height: 28, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
