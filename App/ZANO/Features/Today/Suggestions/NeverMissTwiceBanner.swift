// NeverMissTwiceBanner.swift
// App / ZANO / Features / Today / Suggestions
//
// docs/spec.md 5.6 Never Miss Twice: "A miss doesn't kill a streak. A second consecutive miss
// does." Shown the day after a miss while a streak is still alive: the easiest open goal as the
// one action (it runs that goal's row action), and this week's freezes as a quiet chip. Warning
// tint, never red (red is emergency only).

import SwiftUI
import Core

struct NeverMissTwiceBanner: View {
    let state: NeverMissTwiceState
    let isBusy: Bool
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SuggestionCard(
            icon: "flame.fill",
            tint: Theme.Colors.warning,
            title: Copy.today.neverMissTwiceTitle,
            detail: Copy.today.neverMissTwiceDetail(goal: state.goalTitle),
            actionTitle: state.goalTitle.map(Copy.today.startWithGoal),
            isBusy: isBusy,
            onAction: onAction,
            onDismiss: onDismiss
        ) {
            SuggestionChip(text: Copy.today.freezesLeft(state.freezesLeft), tint: Theme.Colors.textSecondary)
        }
    }
}
