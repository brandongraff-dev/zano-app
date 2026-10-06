// TrialEarnedCard.swift
// App / ZANO / Features / Paywall
//
// "What your trial earned you" (growth research #5, 2026-10-02). Shown from the reminder moment
// (two days before the trial's first charge) until the charge: the user's own numbers from the
// trial — earned unlocks, gym visits, hours locked in, best streak — and the plain billing line.
// With no wins yet it offers the smallest next step instead of a row of zeros. Draws nothing
// outside that window, so a host can place it unconditionally.
//
// Data: `TrialReminder.isInFinalWindow` / `trialEndsAt` / `summary()` (Core). The same numbers go
// into the reminder notification's body.
//
// Placement: Today, under the header and above the Finish setup card (TodayView is owned
// elsewhere; the hook is one line: `TrialEarnedCard()`).

import SwiftUI
import Core

struct TrialEarnedCard: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Hidden for the rest of this trial once dismissed (per device).
    @AppStorage("trialEarnedCard.dismissedForTrialEnd") private var dismissedForTrialEnd: Double = 0

    @State private var summary: TrialSummary?
    @State private var endsAt: Date?

    var body: some View {
        VStack(spacing: 0) {
            if let summary, let endsAt, dismissedForTrialEnd != endsAt.timeIntervalSince1970 {
                card(summary: summary, endsAt: endsAt)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            reload()
        }
    }

    private func reload() {
        guard TrialReminder.isInFinalWindow(), let end = TrialReminder.trialEndsAt else {
            summary = nil
            endsAt = nil
            return
        }
        endsAt = end
        summary = TrialReminder.summary()
        Analytics.shared.capture(event: "trial_summary_card_shown", properties: ["has_wins": summary?.hasWins ?? false])
    }

    private func card(summary: TrialSummary, endsAt: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.trialSummary.cardEyebrow)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(summary.hasWins ? Copy.trialSummary.cardTitle : Copy.trialSummary.noWinsTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Button {
                    dismissedForTrialEnd = endsAt.timeIntervalSince1970
                } label: {
                    Text(Copy.trialSummary.dismissLabel)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(minWidth: Theme.Metrics.minTapTarget, minHeight: Theme.Metrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable(scale: 0.94))
                .accessibilityLabel(Copy.trialSummary.dismissSpoken)
            }

            if summary.hasWins {
                stats(summary)
            } else {
                Text(Copy.trialSummary.noWinsDetail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(Copy.trialSummary.chargeLine(date: endsAt.formatted(date: .abbreviated, time: .omitted)))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private struct Stat: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    private func stats(_ summary: TrialSummary) -> some View {
        let items = [
            Stat(value: "\(summary.earnedUnlocks)", label: Copy.trialSummary.earnedUnlocksLabel),
            Stat(value: "\(summary.gymVisits)", label: Copy.trialSummary.gymVisitsLabel),
            Stat(value: "\(summary.hoursLockedIn)", label: Copy.trialSummary.hoursLockedInLabel),
            Stat(value: Copy.trialSummary.bestStreakValue(summary.bestStreak), label: Copy.trialSummary.bestStreakLabel),
        ]
        return LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: Theme.Spacing.sm
        ) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.value)
                        .font(Theme.Typography.numeralSmall())
                        .foregroundStyle(Theme.Colors.text)
                        .monospacedDigit()
                    Text(item.label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    TrialEarnedCard()
        .padding()
        .background(Theme.Colors.background)
}
