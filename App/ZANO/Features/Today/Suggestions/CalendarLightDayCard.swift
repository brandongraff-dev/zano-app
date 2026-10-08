// CalendarLightDayCard.swift
// App / ZANO / Features / Today / Suggestions
//
// docs/spec.md 9.7: "Calendar density (opt-in) → suggest lighter goals on packed days." Calendar
// access is asked for here, from the card, only when the user taps "Connect calendar" (never at
// launch; `CalendarAwareness.optIn()` is the only prompt). On a packed day the card offers Plan B
// for today's open goals ("Go lighter today").

import SwiftUI
import Core

struct CalendarLightDayCard: View {
    let variant: CalendarCardVariant
    let isBusy: Bool
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SuggestionCard(
            icon: variant == .ask ? "calendar" : "calendar.badge.clock",
            tint: Theme.Colors.accent,
            title: variant == .ask ? Copy.today.calendarAskTitle : Copy.today.calendarPackedTitle,
            detail: variant == .ask ? Copy.today.calendarAskDetail : Copy.today.calendarPackedDetail,
            actionTitle: variant == .ask ? Copy.today.calendarAskAction : Copy.today.calendarPackedAction,
            isBusy: isBusy,
            onAction: onAction,
            onDismiss: onDismiss
        )
    }
}
