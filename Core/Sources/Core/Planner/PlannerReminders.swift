// PlannerReminders.swift
// Core / Planner
//
// Notifications for the Planner (docs/spec.md §5.30): a reminder at a task's time (9:00 for a task with only
// a day), and, if turned on, "starts soon" ahead of calendar events in the next day and a half. `plan` is
// pure and tested; `refresh` asks it what to schedule and replaces what this feature scheduled last time,
// touching no other notification. It runs when the app opens and after every edit, so an event added while
// the app is closed is picked up next time it opens (iOS gives an app no background calendar refresh).

import Foundation

public struct PlannedReminder: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

public enum PlannerReminders {
    /// Well under the 64 pending notifications iOS allows an app, which other features share.
    public static let maxScheduled = 40
    /// A day-only task reminds at this hour.
    public static let dayOnlyHour = 9
    /// How far ahead event alerts are planned.
    public static let eventHorizon: TimeInterval = 36 * 3_600

    public static let taskPrefix = "planner.task."
    public static let eventPrefix = "planner.event."

    public static func plan(
        tasks: [PlannerTask], events: [PlannerEvent], settings: PlannerSettings,
        now: Date = .now, calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []

        for task in tasks where task.remind && !task.isDone {
            guard let due = task.due else { continue }
            let fire: Date
            if task.hasTime {
                fire = due
            } else {
                guard let nine = calendar.date(bySettingHour: dayOnlyHour, minute: 0, second: 0, of: due) else { continue }
                fire = nine
            }
            guard fire > now else { continue }
            planned.append(PlannedReminder(
                identifier: taskPrefix + task.id.uuidString,
                title: Copy.planner.taskNotificationTitle,
                body: task.title,
                fireDate: fire
            ))
        }

        if settings.eventAlerts {
            let lead = TimeInterval(max(1, settings.eventAlertLeadMinutes) * 60)
            for event in events where !event.isAllDay && event.start > now && event.start.timeIntervalSince(now) <= eventHorizon {
                let fire = event.start.addingTimeInterval(-lead)
                guard fire > now else { continue }
                planned.append(PlannedReminder(
                    identifier: eventPrefix + event.id,
                    title: Copy.planner.eventNotificationTitle(minutes: Int(lead / 60)),
                    body: Copy.planner.eventNotificationBody(title: event.title, start: event.start),
                    fireDate: fire
                ))
            }
        }

        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(maxScheduled))
    }

    /// Replaces this feature's pending notifications with the current plan. Returns how many were scheduled.
    @MainActor
    @discardableResult
    public static func refresh(now: Date = .now) async -> Int {
        let settings = PlannerStore.settings
        let device = settings.eventAlerts && PlannerCalendarSource.hasAccess
            ? PlannerCalendarSource.events(from: now, to: now.addingTimeInterval(eventHorizon))
            : []
        // Session 46: private ZANO events and the family calendar follow the same alert rule, locally. Shared
        // events come from the App Group cache (`HouseholdEventStore`), only while Household is live.
        let isLive = HouseholdAvailability.isLive
        let events = settings.eventAlerts ? PlannerAgenda.merge(
            device: device, privateEvents: PlannerStore.privateEvents,
            household: isLive ? HouseholdEventStore.events : [], me: HouseholdEventStore.me, householdName: "",
            filter: PlannerStore.calendarFilter, includeHousehold: isLive
        ) : []
        let plan = plan(tasks: PlannerStore.tasks + PlannerStore.sharedAssigned, events: events, settings: settings, now: now)

        NotificationPermission.cancel(identifiers: PlannerStore.scheduledIdentifiers)
        var scheduled: [String] = []
        for item in plan {
            let ok = await NotificationPermission.scheduleOneShot(
                identifier: item.identifier, title: item.title, body: item.body,
                at: item.fireDate, deepLink: "zano://today", now: now
            )
            if ok { scheduled.append(item.identifier) }
        }
        PlannerStore.scheduledIdentifiers = scheduled
        return scheduled.count
    }
}
