// FamilyCopy.swift
// Core / Copy
//
// Display copy for Family Link (session 23; docs/spec.md §5.23). Plain and calm: it is optional,
// the teen consents, the teen sees everything, and the teen can leave.

import Foundation

extension Copy {
    public enum family {
        public static let rowLabel = "Family Link"
        public static let screenTitle = "Family Link"
        public static let intro = "A parent can set tasks, like homework, and a teen hands them in. It is optional, and the teen has to say yes."
        public static let notAvailable = "Family Link isn't available right now."

        // Choosing a side
        public static let imParent = "I'm a parent"
        public static let imTeen = "I have an invite code"
        public static let ageNote = "Teens 13 to 17 can use ZANO alone. Linking is only ever the teen's choice."

        // Parent
        public static let makeInvite = "Make an invite code"
        public static let inviteShare = "Share this code with your teen. It works once."
        public static let waitingForTeen = "Waiting for your teen to accept."
        public static let newTaskTitle = "New task"
        public static let taskPlaceholder = "Finish maths worksheet"
        public static let requiresPhoto = "Ask for a photo"
        public static let addTask = "Add task"
        public static let approve = "Approve"
        public static let askRedo = "Ask to redo"
        public static let openPhoto = "Look at the photo (once)"
        public static let photoOnceNote = "The photo opens one time and is deleted 10 minutes later."
        public static let photoGone = "The photo has been deleted."
        public static let photoClosesAt = "Deleted at"

        // Teen
        public static let codePlaceholder = "Invite code"
        public static let acceptButton = "Accept and link"
        public static let consentNote = "Your parent will see the tasks you hand in, and any photo for one look. You can see everything they see, and you can leave any time."
        public static let handIn = "Hand in"
        public static let pickPhoto = "Choose a photo"
        public static let photoNeeded = "This task needs a photo."
        public static let leave = "Leave Family Link"
        public static let leaveNote = "Leaving ends the link. Nothing else changes."

        // Statuses
        public static let statusOpen = "To do"
        public static let statusSubmitted = "Handed in"
        public static let statusApproved = "Approved"
        public static let statusRedo = "Redo"
        public static let noTasks = "No tasks yet."

        // Errors
        public static let genericError = "That didn't work. Try again in a moment."
        public static let invalidInvite = "That code isn't valid, or it was already used."
        public static let alreadyOpened = "That photo was already opened once, so it's gone."

        public static func status(_ status: FamilyTaskStatus) -> String {
            switch status {
            case .open: return statusOpen
            case .submitted: return statusSubmitted
            case .approved: return statusApproved
            case .redo: return statusRedo
            }
        }

        public static func error(_ error: Error) -> String {
            switch error as? FamilyLinkError {
            case .server(let code) where code == "invalid_invite": return invalidInvite
            case .gone: return alreadyOpened
            case .notConfigured: return notAvailable
            default: return genericError
            }
        }
    }
}
