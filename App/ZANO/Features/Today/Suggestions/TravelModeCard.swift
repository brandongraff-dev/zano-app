// TravelModeCard.swift
// App / ZANO / Features / Today / Suggestions
//
// docs/spec.md 5.18 Travel mode ("auto-suggested when the phone is in a new city: goals shift to
// walking/steps/focus, gym optional") and 9.7 (new city detection). Three variants:
//   - suggested: `TravelMode` has a pending new-city suggestion; accept it.
//   - active: a trip is running; "I'm home". The gym is optional: every lock start (Today, the Lock
//     tab, schedules) and a lock already running skip it (`TravelMode.requiredGoalIDs`), and any
//     Apple Health workout of its minutes completes it (`HomeWorkoutVerifier.checkToday`).
//   - manual: nothing detected, a gym goal still open; the user can say "I'm traveling".

import SwiftUI
import Core

struct TravelModeCard: View {
    let variant: TravelCardVariant
    let city: String?
    let isBusy: Bool
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SuggestionCard(
            icon: variant == .active ? "airplane.circle.fill" : "airplane",
            tint: Theme.Colors.accent,
            title: title,
            detail: variant == .active ? Copy.today.travelActiveDetail : Copy.today.travelDetail,
            actionTitle: actionTitle,
            isBusy: isBusy,
            onAction: onAction,
            onDismiss: onDismiss
        )
    }

    private var title: String {
        switch variant {
        case .suggested: Copy.today.travelSuggestTitle
        case .active: Copy.today.travelActiveTitle(city: city)
        case .manual: Copy.today.travelManualTitle
        }
    }

    private var actionTitle: String {
        switch variant {
        case .suggested: Copy.today.travelSuggestAction
        case .active: Copy.today.travelActiveAction
        case .manual: Copy.today.travelManualAction
        }
    }
}
