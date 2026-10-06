// SeasonBadgeRow.swift
// App / Features / Progress
//
// docs/spec.md §5.9 ("Seasons (quarterly) reset rank with a 'season badge' kept forever") and
// §5.17 (badges live in the Trophy Case). Wave 3J.
//
// A strip of season-related badges: first an empty socket for the season in progress (what there
// is to earn, spec §8 rule 2), then every banked `season_*` badge (kept forever) and this season's
// `monthly_challenge_*` badges, newest first. Badges come from the caller's `@Query`, so a badge
// banked by `SeasonsAndRanks` shows up without a reload.

import SwiftUI
import SwiftData
import Core

struct SeasonBadgeRow: View {
    /// All badges, any order. Filtered here to season and monthly-challenge keys.
    let badges: [Badge]
    let season: SeasonsAndRanks.Season
    /// The live rank, shown on the in-progress socket.
    let currentRank: SeasonsAndRanks.Rank

    private static let discDiameter: CGFloat = 48
    private static let tileWidth: CGFloat = 84

    private var seasonBadges: [Badge] {
        badges
            .filter { badge in
                if badge.key.hasPrefix("season_") { return true }
                if badge.key.hasPrefix("monthly_challenge_") {
                    return badge.earnedAt >= season.startDate && badge.earnedAt < season.endDate
                }
                return false
            }
            .sorted { $0.earnedAt > $1.earnedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Playful pass (2026-10-03): the "finish a season to keep its badge" caption moved
            // into this info button.
            HStack(spacing: Theme.Spacing.xs) {
                Text(Copy.progress.seasonBadgesTitle)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                ZanoInfoButton(Copy.progress.seasonBadgesEmpty, accessibilityLabel: Copy.progress.seasonBadgesInfoAccessibilityLabel)
            }
            .padding(.leading, Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    tile(
                        title: Copy.progress.seasonBadgeInProgressTitle,
                        subtitle: Copy.progress.rankName(currentRank),
                        isEarned: false,
                        systemImage: RankCard.glyph(for: currentRank)
                    )
                    ForEach(seasonBadges, id: \.id) { badge in
                        tile(
                            title: Self.title(for: badge.key),
                            subtitle: Copy.badges.earnedOnLabel(date: badge.earnedAt),
                            isEarned: true,
                            systemImage: Self.glyph(for: badge.key)
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }

        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .zanoCard(radius: Theme.Radius.medium)
    }

    private func tile(title: String, subtitle: String, isEarned: Bool, systemImage: String) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            TrophyBadgeDisc(isEarned: isEarned, systemImage: systemImage, diameter: Self.discDiameter)
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(isEarned ? Theme.Colors.text : Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(1)
        }
        .frame(width: Self.tileWidth)
        .accessibilityElement(children: .combine)
    }

    private static func title(for key: String) -> String {
        Copy.progress.seasonBadgeTitle(forKey: key) ?? Copy.badges.title(forKey: key)
    }

    private static func glyph(for key: String) -> String {
        let parts = key.split(separator: "_")
        if parts.count == 3, parts[0] == "season", let rank = SeasonsAndRanks.Rank(rawValue: String(parts[2])) {
            return RankCard.glyph(for: rank)
        }
        return "calendar.badge.checkmark"
    }
}
