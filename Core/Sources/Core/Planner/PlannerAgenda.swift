// PlannerAgenda.swift
// Core / Planner
//
// The pure rules behind the Planner screens (session 27): the month grid, one day's agenda, and the dots.
// No UI, no EventKit, no clock of its own, so each rule is tested.

import Foundation

public enum PlannerAgenda {

    // MARK: Month grid

    /// The weeks to draw for the month containing `month`, every week a full row of seven days that starts on
    /// the calendar's first weekday, with the days of the neighbouring months filling the first and last rows.
    public static func weeks(for month: Date, calendar: Calendar = .current) -> [[Date]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: interval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else { return [] }
        var weeks: [[Date]] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: cursor) }
            weeks.append(week)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// Single-letter weekday headings in the calendar's own order ("M T W T F S S").
    public static func weekdayInitials(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: Day

    /// Events that touch `day`. All-day events end at the last second of their last day in EventKit, so
    /// "overlaps" is `start < end of day` and `end > start of day`.
    public static func events(on day: Date, in events: [PlannerEvent], calendar: Calendar = .current) -> [PlannerEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.start < end && $0.end > start }
    }

    public static func agenda(
        for day: Date, events: [PlannerEvent], tasks: [PlannerTask], now: Date = .now, calendar: Calendar = .current
    ) -> PlannerDayAgenda {
        let todays = Self.events(on: day, in: events, calendar: calendar)
        let allDay = todays.filter(\.isAllDay).sorted { $0.title < $1.title }
        let timedEvents = todays.filter { !$0.isAllDay }

        let dayTasks = tasks.filter { task in
            guard let due = task.due else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
        let timedTasks = dayTasks.filter(\.hasTime)
        let anytime = dayTasks.filter { !$0.hasTime }.sorted(by: Self.taskOrder)

        let items = (timedEvents.map(PlannerDayAgenda.Item.event) + timedTasks.map(PlannerDayAgenda.Item.task))
            .sorted { lhs, rhs in
                lhs.sortDate == rhs.sortDate ? lhs.id < rhs.id : lhs.sortDate < rhs.sortDate
            }

        var overdue: [PlannerTask] = []
        if calendar.isDate(day, inSameDayAs: now) {
            let startOfToday = calendar.startOfDay(for: now)
            overdue = tasks.filter { task in
                guard !task.isDone, let due = task.due else { return false }
                return due < startOfToday
            }.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        }
        return PlannerDayAgenda(allDay: allDay, timed: items, anytimeTasks: anytime, overdue: overdue)
    }

    /// Open tasks first, then by title.
    private static func taskOrder(_ a: PlannerTask, _ b: PlannerTask) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    // MARK: Dots

    /// The marks for each day in `days`, keyed by the start of the day.
    public static func markers(
        for days: [Date], events: [PlannerEvent], tasks: [PlannerTask], calendar: Calendar = .current
    ) -> [Date: PlannerDayMarkers] {
        var result: [Date: PlannerDayMarkers] = [:]
        for day in days {
            let key = calendar.startOfDay(for: day)
            let hasEvents = !Self.events(on: day, in: events, calendar: calendar).isEmpty
            let hasTasks = tasks.contains { task in
                guard !task.isDone, let due = task.due else { return false }
                return calendar.isDate(due, inSameDayAs: day)
            }
            result[key] = PlannerDayMarkers(hasEvents: hasEvents, hasOpenTasks: hasTasks)
        }
        return result
    }

    // MARK: Today's short list

    /// Open tasks due today or earlier, most overdue first (the Today card).
    public static func dueNow(tasks: [PlannerTask], now: Date = .now, calendar: Calendar = .current) -> [PlannerTask] {
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return tasks
            .filter { !$0.isDone && ($0.due.map { $0 < endOfToday } ?? false) }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }
}
