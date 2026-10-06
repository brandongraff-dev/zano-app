// TrialValueCard.swift
// App / Features / Today
//
// docs/spec.md §21 "Free trials, done well" (decision 2026-10-06): from the trial's 5th day until
// it ends, Today shows what the trial has earned so far (time reclaimed, streak, goals hit), so the
// reminder two days before the charge lands after the value, not before it. The footer states the
// end date, the price and the cancel path plainly (no countdown, no guilt). When it shows is
// `TrialReminderScheduler.showsValueCard`; the numbers are computed by `TodayView` from its own
// queries and passed in.

import SwiftUI
import Core

struct TrialValueCard: View {
    let reclaimedMinutes: Int
    let streakDays: Int
    let goalsHit: Int
    let endDate: Date
    let priceLine: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "gift")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                Text(Copy.trial.valueCardTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.Spacing.xs)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Theme.Typography.icon(.xsmall))
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(Copy.trial.dismissLabel))
            }

            HStack(spacing: Theme.Spacing.sm) {
                stat(Copy.trial.reclaimedLabel, Copy.trial.duration(minutes: reclaimedMinutes))
                stat(Copy.trial.streakLabel, Copy.trial.streakValue(days: streakDays))
                stat(Copy.trial.goalsHitLabel, "\(goalsHit)")
            }

            Text(Copy.trial.valueCardFooter(
                endDate: endDate.formatted(.dateTime.month(.abbreviated).day()),
                priceLine: priceLine
            ))
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(value)
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .zanoWell()
        .accessibilityElement(children: .combine)
    }
}
