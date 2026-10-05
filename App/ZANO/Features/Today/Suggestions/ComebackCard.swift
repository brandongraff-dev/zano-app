// ComebackCard.swift
// App / ZANO / Features / Today / Suggestions
//
// docs/spec.md 5.18 Comeback mode: "after 5+ days inactive: streak restart with a '3-day comeback'
// mini-challenge at low difficulty; no guilt copy." Before the challenge starts the card offers it
// (`ComebackMode.startChallengeIfEligible`, which lowers the next three days' plans); while it runs
// the card shows the day on a three-step ramp and starts the easiest open goal.

import SwiftUI
import Core

struct ComebackCard: View {
    let state: ComebackState
    let isBusy: Bool
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SuggestionCard(
            icon: "arrow.clockwise",
            tint: Theme.Colors.accent,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            isBusy: isBusy,
            onAction: onAction,
            onDismiss: onDismiss
        ) {
            ComebackRamp(day: state.day ?? 0, total: state.totalDays)
        }
    }

    private var title: String {
        guard let day = state.day else { return Copy.today.comebackStartTitle }
        return Copy.today.comebackDayTitle(day: day, total: state.totalDays)
    }

    private var detail: String {
        guard state.day != nil else { return Copy.today.comebackStartDetail }
        return state.goalID == nil ? Copy.today.comebackDoneToday : Copy.today.comebackDayDetail
    }

    private var actionTitle: String? {
        guard state.day != nil else { return Copy.today.comebackStartAction }
        return state.goalTitle.map(Copy.today.startWithGoal)
    }
}

/// Three capsules: days before today filled, today outlined in the accent, later days on the track.
/// Decorative; the title already says "day 2 of 3".
private struct ComebackRamp: View {
    let day: Int
    let total: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(1...max(1, total), id: \.self) { index in
                Capsule()
                    .fill(index < day ? Theme.Colors.accent : (index == day ? Theme.Colors.accentWash : Theme.Colors.track))
                    .overlay {
                        if index == day {
                            Capsule().strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                        }
                    }
                    .frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}
