import Testing
import Foundation
@testable import Core

@Suite("Planner — month grid, agenda, markers, reminders", .serialized)
struct PlannerTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1 // Sunday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Month grid

    @Test func octoberTwentyTwentySixIsFiveFullWeeks() {
        // Oct 1, 2026 is a Thursday; Oct 31 is a Saturday. Sunday-first: Sep 27 ... Oct 31.
        let weeks = PlannerAgenda.weeks(for: date(2026, 10, 15), calendar: calendar)
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.first?.first == date(2026, 9, 27))
        #expect(weeks.last?.last == date(2026, 10, 31))
    }

    @Test func aMonthCanNeedSixRows() {
        // Aug 2026: starts on a Saturday and has 31 days, so Sunday-first needs six rows.
        let weeks = PlannerAgenda.weeks(for: date(2026, 8, 10), calendar: calendar)
        #expect(weeks.count == 6)
    }

    @Test func weekdayInitialsFollowTheFirstWeekday() {
        var monday = calendar
        monday.firstWeekday = 2
        #expect(PlannerAgenda.weekdayInitials(calendar: calendar).count == 7)
        #expect(PlannerAgenda.weekdayInitials(calendar: monday) != PlannerAgenda.weekdayInitials(calendar: calendar))
    }

    // MARK: Agenda

    @Test func agendaSortsTimedEventsAndTasksTogether() {
        let day = date(2026, 10, 6)
        let events = [
            PlannerEvent(id: "b", title: "Lunch", start: date(2026, 10, 6, 12), end: date(2026, 10, 6, 13), isAllDay: false),
            PlannerEvent(id: "a", title: "Standup", start: date(2026, 10, 6, 9), end: date(2026, 10, 6, 9, 15), isAllDay: false),
            PlannerEvent(id: "c", title: "Holiday", start: date(2026, 10, 6), end: date(2026, 10, 6, 23, 59), isAllDay: true),
        ]
        let tasks = [
            PlannerTask(title: "Call", due: date(2026, 10, 6, 10, 30), hasTime: true),
            PlannerTask(title: "Anytime thing", due: date(2026, 10, 6), hasTime: false),
        ]
        let agenda = PlannerAgenda.agenda(for: day, events: events, tasks: tasks, now: date(2026, 10, 6, 8), calendar: calendar)
        #expect(agenda.allDay.map(\.title) == ["Holiday"])
        #expect(agenda.timed.map(\.id).count == 3)
        #expect(agenda.timed.map(\.sortDate) == [date(2026, 10, 6, 9), date(2026, 10, 6, 10, 30), date(2026, 10, 6, 12)])
        #expect(agenda.anytimeTasks.map(\.title) == ["Anytime thing"])
    }

    @Test func multiDayEventShowsOnEveryDayItCovers() {
        let trip = PlannerEvent(id: "t", title: "Trip", start: date(2026, 10, 6), end: date(2026, 10, 8, 23, 59), isAllDay: true)
        for d in [6, 7, 8] {
            #expect(PlannerAgenda.events(on: date(2026, 10, d, 12), in: [trip], calendar: calendar).count == 1)
        }
        #expect(PlannerAgenda.events(on: date(2026, 10, 9), in: [trip], calendar: calendar).isEmpty)
        #expect(PlannerAgenda.events(on: date(2026, 10, 5), in: [trip], calendar: calendar).isEmpty)
    }

    @Test func overdueOnlyShowsOnTodayAndOnlyOpenTasks() {
        let old = PlannerTask(title: "Old", due: date(2026, 10, 3))
        let doneOld = PlannerTask(title: "Done", due: date(2026, 10, 3), isDone: true)
        let now = date(2026, 10, 6, 8)
        let today = PlannerAgenda.agenda(for: date(2026, 10, 6), events: [], tasks: [old, doneOld], now: now, calendar: calendar)
        #expect(today.overdue.map(\.title) == ["Old"])
        let tomorrow = PlannerAgenda.agenda(for: date(2026, 10, 7), events: [], tasks: [old], now: now, calendar: calendar)
        #expect(tomorrow.overdue.isEmpty)
        #expect(tomorrow.isEmpty)
    }

    @Test func markersShowEventsAndOpenTasksOnly() {
        let events = [PlannerEvent(id: "e", title: "E", start: date(2026, 10, 6, 9), end: date(2026, 10, 6, 10), isAllDay: false)]
        let tasks = [
            PlannerTask(title: "Open", due: date(2026, 10, 7)),
            PlannerTask(title: "Done", due: date(2026, 10, 8), isDone: true),
        ]
        let days = [date(2026, 10, 6), date(2026, 10, 7), date(2026, 10, 8)]
        let m = PlannerAgenda.markers(for: days, events: events, tasks: tasks, calendar: calendar)
        #expect(m[days[0]] == PlannerDayMarkers(hasEvents: true, hasOpenTasks: false))
        #expect(m[days[1]] == PlannerDayMarkers(hasEvents: false, hasOpenTasks: true))
        #expect(m[days[2]] == PlannerDayMarkers())
    }

    @Test func dueNowIncludesOverdueAndToday() {
        let now = date(2026, 10, 6, 8)
        let tasks = [
            PlannerTask(title: "Yesterday", due: date(2026, 10, 5)),
            PlannerTask(title: "Today", due: date(2026, 10, 6)),
            PlannerTask(title: "Tomorrow", due: date(2026, 10, 7)),
            PlannerTask(title: "Done", due: date(2026, 10, 6), isDone: true),
            PlannerTask(title: "No date"),
        ]
        #expect(PlannerAgenda.dueNow(tasks: tasks, now: now, calendar: calendar).map(\.title) == ["Yesterday", "Today"])
    }

    // MARK: Reminders

    @Test func timedTaskRemindsAtItsTimeAndDayOnlyAtNine() {
        let now = date(2026, 10, 6, 7)
        let timed = PlannerTask(title: "Call", due: date(2026, 10, 6, 14, 30), hasTime: true, remind: true)
        let dayOnly = PlannerTask(title: "Invoice", due: date(2026, 10, 7), hasTime: false, remind: true)
        let off = PlannerTask(title: "Quiet", due: date(2026, 10, 7), remind: false)
        let plan = PlannerReminders.plan(tasks: [dayOnly, timed, off], events: [], settings: PlannerSettings(), now: now, calendar: calendar)
        #expect(plan.map(\.fireDate) == [date(2026, 10, 6, 14, 30), date(2026, 10, 7, 9)])
        #expect(plan.map(\.body) == ["Call", "Invoice"])
    }

    @Test func pastAndDoneTasksAreNotScheduled() {
        let now = date(2026, 10, 6, 12)
        let past = PlannerTask(title: "Past", due: date(2026, 10, 6, 9), hasTime: true, remind: true)
        let done = PlannerTask(title: "Done", due: date(2026, 10, 7, 9), hasTime: true, remind: true, isDone: true)
        #expect(PlannerReminders.plan(tasks: [past, done], events: [], settings: PlannerSettings(), now: now, calendar: calendar).isEmpty)
    }

    @Test func eventAlertsOnlyWhenTurnedOnAndOnlyTimedEventsInTheHorizon() {
        let now = date(2026, 10, 6, 8)
        let soon = PlannerEvent(id: "s", title: "Review", start: date(2026, 10, 6, 10), end: date(2026, 10, 6, 11), isAllDay: false)
        let allDay = PlannerEvent(id: "d", title: "Holiday", start: date(2026, 10, 6), end: date(2026, 10, 6, 23, 59), isAllDay: true)
        let far = PlannerEvent(id: "f", title: "Far", start: date(2026, 10, 12, 10), end: date(2026, 10, 12, 11), isAllDay: false)
        let off = PlannerReminders.plan(tasks: [], events: [soon], settings: PlannerSettings(eventAlerts: false), now: now, calendar: calendar)
        #expect(off.isEmpty)
        let on = PlannerReminders.plan(tasks: [], events: [soon, allDay, far], settings: PlannerSettings(eventAlerts: true, eventAlertLeadMinutes: 10), now: now, calendar: calendar)
        #expect(on.count == 1)
        #expect(on.first?.fireDate == date(2026, 10, 6, 9, 50))
    }

    @Test func neverMoreThanTheCap() {
        let now = date(2026, 10, 6, 7)
        let tasks = (0..<80).map { PlannerTask(title: "T\($0)", due: date(2026, 10, 7, 8, 0).addingTimeInterval(Double($0) * 60), hasTime: true, remind: true) }
        let plan = PlannerReminders.plan(tasks: tasks, events: [], settings: PlannerSettings(), now: now, calendar: calendar)
        #expect(plan.count == PlannerReminders.maxScheduled)
        #expect(plan.first?.body == "T0")
    }

    // MARK: Store

    @Test func doneTasksExpireButOpenOnesStay() {
        let now = date(2026, 10, 6)
        let oldDone = PlannerTask(title: "Old", isDone: true, completedAt: now.addingTimeInterval(-40 * 86_400))
        let freshDone = PlannerTask(title: "Fresh", isDone: true, completedAt: now.addingTimeInterval(-2 * 86_400))
        let open = PlannerTask(title: "Open", createdAt: now.addingTimeInterval(-90 * 86_400))
        let kept = PlannerStore.prune([oldDone, freshDone, open], now: now)
        #expect(kept.map(\.title) == ["Fresh", "Open"])
    }
}
