// PlannerCalendarSource.swift
// Core / Planner
//
// Reads calendar events for the Planner screens and the "starts soon" alerts (docs/spec.md §5.30). EventKit,
// on this device only: events are drawn and dropped, never stored or sent anywhere. Access is asked for
// only from the Planner's own "Show my calendar" button (or the Focus lock switch); the Info.plist usage
// string says what is read.
//
// UNVERIFIED on a device (no Mac): the calls mirror `FocusLockCalendarSource`, which compiles in CI.

import Foundation
import EventKit
import CoreGraphics

public enum PlannerCalendarSource {
    public nonisolated static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// `true` once the person has said no (only the Settings app can change it).
    public nonisolated static var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Events touching `start..<end`, earliest first. Empty without access. A fresh store per call: an
    /// `EKEventStore` isn't `Sendable`.
    public nonisolated static func events(from start: Date, to end: Date) -> [PlannerEvent] {
        guard hasAccess else { return [] }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map(convert)
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    private nonisolated static func convert(_ event: EKEvent) -> PlannerEvent {
        PlannerEvent(
            id: (event.eventIdentifier ?? UUID().uuidString) + "@" + String(Int(event.startDate.timeIntervalSince1970)),
            title: (event.title?.isEmpty == false ? event.title : nil) ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar?.title ?? "",
            colorRGB: rgb(of: event.calendar?.cgColor)
        )
    }

    /// 0xRRGGBB in sRGB; a calm blue if the colour can't be read.
    nonisolated static func rgb(of color: CGColor?) -> UInt32 {
        let fallback: UInt32 = 0x4F8CFF
        guard let color,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3
        else { return fallback }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c[0]) << 16 | byte(c[1]) << 8 | byte(c[2])
    }
}
