// HouseholdCopy.swift
// Core / Copy
//
// Display copy for Household, the shared task list (session 28; docs/spec.md §5.31). Plain, calm, like the
// rest of the Planner. Nothing here is a goal and nothing locks anything.

import Foundation

extension Copy {
    public enum household {
        public static let rowLabel = "Household"
        public static let screenTitle = "Household"
        public static let intro = "A shared task list for the people you live or work with. Everyone sees the same list. Anyone can leave at any time."
        public static let notAvailable = "Household isn't available right now."
        public static let you = "You"

        // Start
        public static let createTitle = "Start a household"
        public static let joinTitle = "Join with a code"
        public static let householdNamePlaceholder = "Name (for example, Home)"
        public static let yourNamePlaceholder = "Your name in this household"
        public static let codePlaceholder = "Invite code"
        public static let createButton = "Create household"
        public static let joinButton = "Join"
        public static let privacyNote = "People in a household see its tasks, who they're given to and who finished them, and the calendar events you share with them. Nothing else about you."

        // Invite
        public static let inviteTitle = "Invite code"
        public static let inviteShare = "Share code"
        public static let inviteNewCode = "Make a new code"
        public static let inviteNote = "Anyone with the code can join. Make a new code to stop an old one working."

        public static func inviteMessage(code: String, name: String) -> String {
            "Join \(name) on ZANO with this code: \(code)"
        }

        // Board
        public static let mine = "Assigned to you"
        public static let unassigned = "Not taken yet"
        public static let others = "Everyone else"
        public static let doneRecently = "Done lately"
        public static let nothingYet = "No tasks yet"
        public static let nothingYetDetail = "Add the first one."
        public static let membersTitle = "People"

        // New task
        public static let newTask = "New task"
        public static let titlePlaceholder = "Title"
        public static let notesPlaceholder = "Notes"
        public static let dateToggle = "Date"
        public static let assignLabel = "Assign to"
        public static let nobody = "Nobody yet"
        public static let add = "Add"
        public static let cancel = "Cancel"
        public static let leave = "Leave this household"
        public static let leaveNote = "Leaving takes you out of the list. Tasks given to you become unassigned. Nothing else changes."
        public static let delete = "Delete"
        public static let refreshing = "Updating…"

        public static func doneBy(_ name: String) -> String { "Done by \(name)" }
        public static func assignedTo(_ name: String) -> String { "For \(name)" }
        public static func memberCount(_ count: Int) -> String { count == 1 ? "1 person" : "\(count) people" }

        // Screen-free times (session 44): shared windows each person can join for their own phone.
        public static let quietTitle = "Screen-free times"
        public static let quietIntro = "Times your household puts phones down together, like dinner or bedtime. Join the ones you want and ZANO locks your own apps during them, on your phone only. Nobody can lock anyone else's phone, you can leave any time, and emergency unlock works as always."
        public static let quietEmpty = "No screen-free times yet. Add one, like dinner."
        public static let quietAdd = "Add a screen-free time"
        public static let quietNew = "New screen-free time"
        public static let quietEdit = "Edit screen-free time"
        public static let quietNamePlaceholder = "Name (for example, Dinner)"
        public static let quietStarts = "Starts"
        public static let quietEnds = "Ends"
        public static let quietDays = "Days"
        public static let quietSave = "Save"
        public static let quietDelete = "Delete this time"
        public static let quietDeleteNote = "Deleting it stops the lock on every phone that joined, the next time each one opens ZANO."
        public static let quietOvernightNote = "Ends the next morning."
        public static let quietJoin = "Join"
        public static let quietAppsLabel = "Apps to lock"
        public static let quietDefaultApps = "My default lock set"
        public static let quietJoinedNote = "You're in. Your apps lock during this time, with no goals to earn. Leave any time."
        public static let quietStartsNextTime = "This one is already under way, so your lock starts next time."
        public static let quietTooMany = "You've joined as many screen-free times as this phone can schedule. Leave one to join this."
        public static let quietPrivacyNote = "Your household sees each time's name and hours. Whether you join, and which apps lock, stays on your phone."
        public static let quietTooShort = "Make it at least 15 minutes."
        public static let quietNoDays = "Pick at least one day."
        public static let quietNameMissing = "Give it a name."
        public static let quietTooManyInHousehold = "This household already has 20 screen-free times."

        public static func quietCreatedBy(_ name: String) -> String { "Added by \(name)" }

        /// "6:00 PM – 7:00 PM · Every day".
        public static func quietWindowLine(startMinute: Int, endMinute: Int, weekdays: Set<Int>, calendar: Calendar = .current) -> String {
            "\(clock(startMinute, calendar: calendar)) – \(clock(endMinute, calendar: calendar)) · \(daysSummary(weekdays, calendar: calendar))"
        }

        /// "Every day", "Weekdays", "Weekends", or the short day names in week order.
        public static func daysSummary(_ weekdays: Set<Int>, calendar: Calendar = .current) -> String {
            if weekdays == [1, 2, 3, 4, 5, 6, 7] { return "Every day" }
            if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
            if weekdays == [1, 7] { return "Weekends" }
            if weekdays == [1, 2, 3, 4, 5] { return "School nights" }
            let symbols = calendar.shortWeekdaySymbols
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            return order.filter { weekdays.contains($0) }.map { symbols[$0 - 1] }.joined(separator: ", ")
        }

        /// One-letter day buttons for the editor, in the calendar's week order.
        public static func dayLetter(_ weekday: Int, calendar: Calendar = .current) -> String {
            calendar.veryShortWeekdaySymbols[weekday - 1]
        }

        public static func dayName(_ weekday: Int, calendar: Calendar = .current) -> String {
            calendar.weekdaySymbols[weekday - 1]
        }

        // The heads-up (notification and Today chip). Positive, together, never a warning.
        public static func quietReminderTitle(name: String, minutes: Int) -> String { "\(name) in \(minutes) min" }
        public static func quietReminderBody(start: Date, end: Date) -> String {
            "Phones down together. Your apps rest from \(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))."
        }
        public static func quietChipSoon(name: String, minutes: Int) -> String { "\(name) in \(max(1, minutes)) min · phones down together" }
        public static func quietChipRunning(name: String, end: Date) -> String {
            "\(name) · phones down until \(end.formatted(date: .omitted, time: .shortened))"
        }

        private static func clock(_ minute: Int, calendar: Calendar) -> String {
            let day = calendar.startOfDay(for: .now)
            let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
            return date.formatted(date: .omitted, time: .shortened)
        }

        public static func quietValidation(_ error: HouseholdQuietTime.ValidationError) -> String {
            switch error {
            case .emptyName, .nameTooLong: quietNameMissing
            case .noDays: quietNoDays
            case .timeOutOfRange, .tooShort: quietTooShort
            }
        }

        // Errors
        public static let genericError = "That didn't work. Try again in a moment."
        public static let invalidInvite = "That code isn't valid."
        public static let full = "That household is full (8 people)."
        public static let tooMany = "You're already in the most households you can join."
        // Family calendar (session 46)
        public static let eventsTooMany = "Your family calendar is full (500 upcoming events). Delete a few first."
        public static let eventsBadAudience = "Someone you picked isn't in this household any more."

        public static func error(_ error: Error) -> String {
            switch error as? FamilyLinkError {
            case .server(let code) where code == "invalid_invite": return invalidInvite
            case .server(let code) where code == "household_full": return full
            case .server(let code) where code == "too_many_households": return tooMany
            case .server(let code) where code == "too_many_quiet_times": return quietTooManyInHousehold
            case .server(let code) where code == "too_many_events": return eventsTooMany
            case .server(let code) where code == "empty_audience": return Copy.planner.pickSomeone
            case .server(let code) where code == "bad_audience": return eventsBadAudience
            case .notConfigured: return notAvailable
            default: return genericError
            }
        }
    }
}
