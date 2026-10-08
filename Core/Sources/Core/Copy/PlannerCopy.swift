// PlannerCopy.swift
// Core / Copy
//
// Display copy for the Planner (session 27; docs/spec.md §5.30). Plain and short, the way Apple's own
// Calendar and Reminders talk.

import Foundation

extension Copy {
    public enum planner {
        // Entry points
        public static let screenTitle = "Calendar"
        public static let openLabel = "Open calendar"
        public static let todayCardTitle = "Due today"
        public static let todayCardOpen = "See all"

        // Navigation
        public static let todayButton = "Today"
        public static let addMenuLabel = "Add"
        public static let newTask = "New task"
        public static let newEvent = "New event"
        public static let previousMonth = "Previous month"
        public static let nextMonth = "Next month"

        // Agenda
        public static let allDay = "All-day"
        public static let overdue = "Overdue"
        public static let anytime = "Anytime"
        public static let nothingPlanned = "Nothing planned"
        public static let nothingPlannedDetail = "Add a task, or enjoy the open day."
        public static let untitledEvent = "Untitled event"

        // Calendar access
        public static let accessTitle = "Show your calendar here"
        public static let accessDetail = "Meetings and events from your iPhone's calendars appear next to your tasks. They stay on this iPhone."
        public static let accessButton = "Show my calendar"
        public static let deniedDetail = "Calendar access is off. You can turn it on in the Settings app."
        public static let openSettings = "Open Settings"

        // Task editor
        public static let editTask = "Edit task"
        public static let titlePlaceholder = "Title"
        public static let notesPlaceholder = "Notes"
        public static let dateToggle = "Date"
        public static let timeToggle = "Time"
        public static let remindToggle = "Remind me"
        public static let remindFooterOff = "Turn on notifications in the Settings app to get reminders."
        public static let save = "Save"
        public static let cancel = "Cancel"
        public static let delete = "Delete task"
        public static let done = "Done"

        // Settings
        public static let settingsRow = "Calendar & reminders"
        public static let settingsTitle = "Reminders"
        public static let eventAlertsToggle = "Alert before events"
        public static let eventAlertsFooter = "A notification shortly before each event on your calendars. ZANO checks your calendar when you open it, so an event added while the app is closed is picked up the next time you open ZANO."
        public static let leadLabel = "Alert"
        public static let remindByDefault = "Remind me by default for new tasks"

        // Sharing
        public static let shareDayButton = "Share this day"
        public static let shareTaskButton = "Share task"
        public static let householdMenuItem = "Household tasks"

        public static func shareDue(day: String, time: String) -> String { "Due \(day) at \(time)" }
        public static func shareDueDay(day: String) -> String { "Due \(day)" }

        // Events with "who can see this" (session 46)
        public static let editEvent = "Edit event"
        public static let eventDetailTitle = "Event"
        public static let allDayToggle = "All-day"
        public static let startsLabel = "Starts"
        public static let endsLabel = "Ends"
        public static let whoCanSee = "Who can see this"
        public static let onlyMe = "Only me"
        public static let onlyMeNote = "Only you. It stays on this iPhone and is never uploaded."
        public static let onlyMeCalendarTitle = "Only you"
        public static let choosePeople = "Choose people"
        public static let choosePeopleNote = "Only the people you pick, and you, can see it."
        public static let pickSomeone = "Pick at least one person."
        public static let deleteEvent = "Delete event"
        public static let useAppleEditor = "Add to my iPhone calendar instead"
        public static let appleEditorNote = "For repeats, invitees and alerts set by the Calendar app, use your iPhone calendar."
        public static let readOnlyNote = "Only the person who added it can change it."
        public static let titleMissing = "Give it a title."
        public static let titleTooLong = "Keep the title under 120 characters."
        public static let endsBeforeStart = "The end is before the start."
        public static let addedByYou = "Added by you"
        public static let eventNotesLabel = "Notes"
        public static let visibilityLabel = "Who can see it"

        public static func everyoneIn(_ household: String) -> String { "Everyone in \(household)" }
        public static func everyoneNote(_ household: String) -> String {
            "Everyone in \(household) sees it in their ZANO calendar."
        }
        public static func addedBy(_ name: String) -> String { "Added by \(name)" }
        /// "You, Sam and Alex".
        public static func visibleTo(_ names: [String]) -> String {
            let all = ["You"] + names
            guard all.count > 1 else { return "You" }
            return all.dropLast().joined(separator: ", ") + " and " + (all.last ?? "")
        }

        // Calendar filter (session 46)
        public static let filterMenuLabel = "Calendars"
        public static let filterFamily = "Family calendar"
        public static let filterDevice = "iPhone calendars"

        // Accessibility (session 46): the small mark on an event row.
        public static let a11yOnlyMe = "Only you can see this"
        public static let a11yEveryone = "Shared with your household"
        public static func a11yWith(_ names: [String]) -> String { "Shared with " + names.joined(separator: ", ") }

        // Notifications
        public static let taskNotificationTitle = "Reminder"

        public static func eventNotificationTitle(minutes: Int) -> String {
            minutes == 1 ? "Starts in 1 minute" : "Starts in \(minutes) minutes"
        }

        public static func eventNotificationBody(title: String, start: Date) -> String {
            let time = start.formatted(date: .omitted, time: .shortened)
            let name = title.isEmpty ? untitledEvent : title
            return "\(name) at \(time)"
        }

        public static func leadOption(_ minutes: Int) -> String {
            minutes == 60 ? "1 hour before" : "\(minutes) minutes before"
        }

        public static func dueCount(_ count: Int) -> String {
            count == 1 ? "1 task due" : "\(count) tasks due"
        }

        public static func accessibilityDay(_ date: Date, events: Int, tasks: Int) -> String {
            var parts = [date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
            if events > 0 { parts.append(events == 1 ? "1 event" : "\(events) events") }
            if tasks > 0 { parts.append(tasks == 1 ? "1 task" : "\(tasks) tasks") }
            return parts.joined(separator: ", ")
        }
    }
}
