// FocusLockCalendarSource.swift
// Core / FocusLock
//
// Reads the next days of calendar events for the focus lock (docs/spec.md §5.24) and turns them into
// `FocusCalendarEvent`s. EventKit, on this device only. It never asks for access on its own: the
// Settings screen calls `requestAccess()` when the user turns the feature on (the Info.plist usage
// string is already in `project.yml`).
//
// UNVERIFIED (no Mac, CLAUDE.md rule 5): the EventKit calls here mirror `CalendarAwareness`, which
// compiles in CI; `EKEvent.availability`, `attendees` and `EKParticipant.isCurrentUser` /
// `participantStatus` are used from memory of the iOS 17 API and have not run on a device.

import Foundation
import EventKit

@MainActor
public final class FocusLockCalendarSource {
    public static let shared = FocusLockCalendarSource()

    private init() {}

    public nonisolated static func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    public nonisolated static var hasAccess: Bool { authorizationStatus() == .fullAccess }

    /// Shows the system Calendar prompt. Only the Settings toggle calls this.
    @discardableResult
    public func requestAccess() async -> Bool {
        // A fresh store, not a shared one: an `EKEventStore` isn't `Sendable`, so a stored one can't be
        // sent across the await. Access is per app, so any store sees the answer.
        let store = EKEventStore()
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The user's calendars, for the "which calendars" list. Empty without access.
    public func calendars() -> [(id: String, title: String)] {
        guard Self.hasAccess else { return [] }
        return EKEventStore().calendars(for: .event).map { ($0.calendarIdentifier, $0.title) }
    }

    /// Events starting between `start` and `end`. Empty without access.
    public func events(from start: Date, to end: Date) -> [FocusCalendarEvent] {
        guard Self.hasAccess else { return [] }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.convert)
    }

    private static func convert(_ event: EKEvent) -> FocusCalendarEvent? {
        guard event.status != .canceled else { return nil }
        let attendees = event.attendees ?? []
        // An event the user declined is not their meeting.
        if attendees.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) { return nil }
        let busy: Bool
        switch event.availability {
        case .free: busy = false
        case .busy, .tentative, .unavailable, .notSupported: busy = true
        @unknown default: busy = true
        }
        return FocusCalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isBusy: busy,
            hasOtherAttendees: attendees.contains { !$0.isCurrentUser }
        )
    }
}
