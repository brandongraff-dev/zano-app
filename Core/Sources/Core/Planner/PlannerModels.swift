// PlannerModels.swift
// Core / Planner
//
// The Planner (session 27, docs/spec.md §5.30): a calendar and a short task list in one place, in the
// layout people already know from the iOS Calendar and Reminders apps. Tasks are ZANO's own, kept on
// this device; calendar events are read from the iPhone's calendars and never copied or uploaded.

import Foundation

/// A task the person adds ("Send the invoice", "Read chapter 4").
public struct PlannerTask: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var notes: String
    /// When it is due. `nil` = no date (shows under "Anytime").
    public var due: Date?
    /// `true` = `due` carries a time of day; `false` = only the day matters.
    public var hasTime: Bool
    public var remind: Bool
    public var isDone: Bool
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(), title: String, notes: String = "", due: Date? = nil, hasTime: Bool = false,
        remind: Bool = false, isDone: Bool = false, completedAt: Date? = nil, createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.hasTime = hasTime
        self.remind = remind
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}

/// A calendar event, copied just far enough to draw it. Not stored.
public struct PlannerEvent: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarTitle: String
    /// The calendar's own colour, as 0xRRGGBB.
    public var colorRGB: UInt32

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarTitle: String = "", colorRGB: UInt32 = 0x4F8CFF) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.colorRGB = colorRGB
    }
}

public struct PlannerSettings: Codable, Sendable, Equatable {
    /// A "starts soon" notification for calendar events.
    public var eventAlerts: Bool
    /// Minutes before an event the alert fires.
    public var eventAlertLeadMinutes: Int
    /// A new task starts with "Remind me" on.
    public var remindByDefault: Bool

    public init(eventAlerts: Bool = false, eventAlertLeadMinutes: Int = 10, remindByDefault: Bool = true) {
        self.eventAlerts = eventAlerts
        self.eventAlertLeadMinutes = eventAlertLeadMinutes
        self.remindByDefault = remindByDefault
    }
}

/// One day of the agenda.
public struct PlannerDayAgenda: Equatable, Sendable {
    public var allDay: [PlannerEvent]
    /// Timed events and timed tasks, earliest first.
    public var timed: [Item]
    /// Tasks for the day with no time of day.
    public var anytimeTasks: [PlannerTask]
    /// Open tasks due before this day (only filled for today).
    public var overdue: [PlannerTask]

    public enum Item: Equatable, Sendable, Identifiable {
        case event(PlannerEvent)
        case task(PlannerTask)

        public var id: String {
            switch self {
            case .event(let e): return "e-" + e.id
            case .task(let t): return "t-" + t.id.uuidString
            }
        }

        public var sortDate: Date {
            switch self {
            case .event(let e): return e.start
            case .task(let t): return t.due ?? .distantFuture
            }
        }
    }

    public var isEmpty: Bool { allDay.isEmpty && timed.isEmpty && anytimeTasks.isEmpty && overdue.isEmpty }
}

/// The two small marks under a day number in the month grid.
public struct PlannerDayMarkers: Equatable, Sendable {
    public var hasEvents: Bool
    public var hasOpenTasks: Bool
    public init(hasEvents: Bool = false, hasOpenTasks: Bool = false) {
        self.hasEvents = hasEvents
        self.hasOpenTasks = hasOpenTasks
    }
}
