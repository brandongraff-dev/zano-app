// PlannerEventEditor.swift
// App / ZANO / Features / Planner
//
// "New event": Apple's own event editor (EventKitUI), so adding an event looks and behaves exactly like
// the Calendar app (calendar choice, repeat, invitees, alerts). It writes straight to the iPhone's
// calendar; ZANO keeps nothing. Needs calendar access, which `PlannerView` asks for first.

import SwiftUI
import EventKit
import EventKitUI

struct PlannerEventEditor: UIViewControllerRepresentable {
    let day: Date
    let onFinish: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = context.coordinator.store
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        let start = Self.defaultStart(for: day)
        event.startDate = start
        event.endDate = start.addingTimeInterval(3_600)

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    /// The chosen day at the next whole hour (today) or 9:00 (another day).
    private static func defaultStart(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now), let next = calendar.dateInterval(of: .hour, for: now)?.end,
           calendar.isDate(next, inSameDayAs: now) {
            return next
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    /// UIKit calls the delegate on the main thread, but `EKEventEditViewDelegate` isn't main-actor
    /// isolated, so the method is `nonisolated` and hops to the main actor itself.
    final class Coordinator: NSObject, EKEventEditViewDelegate, @unchecked Sendable {
        /// Kept here so the event's store outlives the editor's setup.
        let store = EKEventStore()
        private let onFinish: @MainActor () -> Void

        init(onFinish: @escaping @MainActor () -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            MainActor.assumeIsolated { onFinish() }
        }
    }
}
