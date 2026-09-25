// LockedOutMomentCard.swift
// App / ZANO / Features / Today / Suggestions
//
// docs/spec.md 5.16 Locked-Out Moment. The shield extension can't present anything shareable, so
// the moment surfaces here: once today's blocked-app attempts (`ShieldAttemptTally`) reach
// `LockedOutAttemptTracker.threshold`, this card opens `LockedOutMomentView` to share it.

import SwiftUI
import Core

struct LockedOutMomentCard: View {
    let attempts: Int
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SuggestionCard(
            icon: "hand.raised.fill",
            tint: Theme.Colors.lockedAmbient,
            title: Copy.today.lockedOutCardTitle(attempts: attempts),
            detail: Copy.today.lockedOutCardDetail,
            actionTitle: Copy.today.lockedOutCardAction,
            actionIcon: "square.and.arrow.up",
            onAction: onAction,
            onDismiss: onDismiss
        )
    }
}
