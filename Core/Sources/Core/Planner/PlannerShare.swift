// PlannerShare.swift
// Core / Planner
//
// Plain-text versions of a task and of a day, for the share sheet (session 28; docs/spec.md §5.31). Works
// today with no account and no server: the person sends it through Messages, Mail or anything else, to
// anyone, on any phone. The wording lives in `Copy.planner`.

import Foundation

public enum PlannerShare {
    /// "Send the invoice\nDue Tue, Oct 6 at 3:00 PM\n\nNotes..."
    public static func text(for task: PlannerTask) -> String {
        var lines = [task.title]
        if let due = task.due {
            let day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            if task.hasTime {
                lines.append(Copy.planner.shareDue(day: day, time: due.formatted(date: .omitted, time: .shortened)))
            } else {
                lines.append(Copy.planner.shareDueDay(day: day))
            }
        }
        if !task.notes.isEmpty { lines.append(""); lines.append(task.notes) }
        return lines.joined(separator: "\n")
    }

    /// The day's plan: a heading, then one line per item in time order.
    public static func text(for agenda: PlannerDayAgenda, day: Date) -> String {
        var lines = [day.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        for event in agenda.allDay { lines.append("• " + (event.title.isEmpty ? Copy.planner.untitledEvent : event.title)) }
        for item in agenda.timed {
            switch item {
            case .event(let event):
                let time = event.start.formatted(date: .omitted, time: .shortened)
                lines.append("• \(time)  " + (event.title.isEmpty ? Copy.planner.untitledEvent : event.title))
            case .task(let task):
                let time = (task.due ?? .now).formatted(date: .omitted, time: .shortened)
                lines.append("• \(time)  [\(task.isDone ? "x" : " ")] \(task.title)")
            }
        }
        for task in agenda.anytimeTasks { lines.append("• [\(task.isDone ? "x" : " ")] \(task.title)") }
        if lines.count == 1 { lines.append(Copy.planner.nothingPlanned) }
        return lines.joined(separator: "\n")
    }
}
