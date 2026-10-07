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
        public static let privacyNote = "People in a household see its tasks, who they're given to and who finished them. Nothing else about you."

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

        // Errors
        public static let genericError = "That didn't work. Try again in a moment."
        public static let invalidInvite = "That code isn't valid."
        public static let full = "That household is full (8 people)."
        public static let tooMany = "You're already in the most households you can join."

        public static func error(_ error: Error) -> String {
            switch error as? FamilyLinkError {
            case .server(let code) where code == "invalid_invite": return invalidInvite
            case .server(let code) where code == "household_full": return full
            case .server(let code) where code == "too_many_households": return tooMany
            case .notConfigured: return notAvailable
            default: return genericError
            }
        }
    }
}
