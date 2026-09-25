// MonthlyChallengeCard.swift
// App / Features / Progress
//
// docs/spec.md §5.9 ("Monthly challenges themed to fresh starts: 'January Lock-In,' 'Summer Shred
// Consistency,' 'No-Skip November.'") and §8 rules 2 and 6 (progress is always partly filled;
// fresh-start timing). Wave 3J.
//
// Data: `SeasonsAndRanks.monthlyChallengeProgress(asOf:)`, computed locally. The target is prorated
// to the days elapsed, so on the 3rd the bar measures three days, not thirty. A `GoalRing` carries
// the fraction; completing it lights the card (`active:`), since that glow is reserved for earned.

import SwiftUI
import Core

struct MonthlyChallengeCard: View {
    let progress: SeasonsAndRanks.MonthlyChallengeProgress

    private var title: String {
        Copy.progress.monthlyChallengeTitle(themeKey: progress.challenge.themeKey, month: progress.challenge.month)
    }

    private var daysLeft: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return max(1, calendar.dateComponents([.day], from: today, to: progress.challenge.endDate).day ?? 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            GoalRing(
                progress: progress.progress,
                color: Theme.Colors.accent,
                size: .small,
                center: progress.isComplete ? .icon(systemName: "checkmark") : .icon(systemName: "calendar")
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .zanoText(.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(progress.isComplete
                     ? Copy.progress.monthlyChallengeComplete
                     : Copy.progress.monthlyChallengeProgressLabel(active: progress.activeDays, expected: progress.expectedDays))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(progress.isComplete ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(progress.isComplete ? Copy.progress.monthlyChallengeEndsLabel(daysLeft: daysLeft) : Copy.progress.monthlyChallengeExplainer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if !progress.isComplete {
                Text(Copy.progress.monthlyChallengeEndsLabel(daysLeft: daysLeft))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium, active: progress.isComplete)
        .accessibilityElement(children: .combine)
    }
}
