// FamilyHubCopy.swift
// Core / Copy
//
// Display copy for the Family page (session 47; docs/spec.md §5.31): the family portrait, the family plan, what's
// coming up, chores, Family Link and the household. Warm and plain; nothing here locks or ranks anyone.

import Foundation

extension Copy {
    public enum familyHub {
        public static let screenTitle = "Family"
        public static let settingsRow = "Family"
        public static let settingsRowDetail = "Your family, plan, chores and calendar"
        public static let you = "You"
        public static let owner = "Owner"
        public static let soloTitle = "Your family"

        // Portrait
        /// VoiceOver label for one buddy in the portrait: "Sam, Lox".
        public static func memberLabel(name: String, buddy: Buddy) -> String { "\(name), \(Copy.buddy.name(buddy))" }
        public static let memberHint = "Shows what you share with them"
        public static func memberCount(_ count: Int) -> String { count == 1 ? "Just you so far" : "\(count) of you" }

        // Member card
        public static let whatYouShare = "What you share"
        public static let shareChores = "The household's chores, and who finished them"
        public static let shareQuietTimes = "Screen-free times (never who joins them)"
        public static let shareBuddy = "Your buddy and its outfit"
        public static func shareEvents(_ count: Int) -> String {
            count == 1 ? "1 calendar event you added" : "\(count) calendar events you added"
        }
        public static func buddyLine(_ buddy: Buddy) -> String { "\(Copy.buddy.name(buddy)), \(Copy.buddy.kind(buddy))" }
        public static let privateNote = "Nobody in your household sees your goals, locks, screen time or private events."
        public static let close = "Done"

        // Invite
        public static let inviteTitle = "Invite your family"
        public static let inviteDetail = "Share this code. Everyone who joins stands here with their own buddy."
        public static let noHouseholdDetail = "Start a household, or join one with a code, and everyone stands here with their own buddy."
        public static let startOrJoin = "Start or join a household"
        public static let appleFamilyInvite = "Add people to your Apple family group in the Settings app, and they get ZANO Pro too, each with their own buddy."

        // Family plan
        public static let planTitle = "Family plan"
        public static let planSharedWithYou = "Shared with you by your family"
        public static let planSharingWithFamily = "Shared with your family"
        public static let planYours = "Your plan"
        public static let planExplainer = "Apple Family Sharing decides who is in your family group, not ZANO. One plan covers up to 6 people."
        public static let planSharedWithYouNote = "Someone in your family group pays for it and manages it. You don't need your own."
        public static let manageFamilySharing = "Manage Family Sharing"
        public static let manageFamilySharingHow = "To add or remove people, open the Settings app, tap your name, then Family Sharing. This button opens your App Store subscriptions."

        // Coming up
        public static let comingUpTitle = "Coming up"
        public static let comingUpEmpty = "Nothing on the family calendar yet."
        public static let openCalendar = "Calendar"
        public static let quietJoined = "You're in"
        public static let quietNotJoined = "Not joined"
        public static func quietRunning(name: String, end: Date) -> String {
            "\(name) · now, until \(end.formatted(date: .omitted, time: .shortened))"
        }
        public static func quietNext(name: String, start: Date) -> String {
            "\(name) · \(start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        public static func eventLine(_ start: Date, allDay: Bool) -> String {
            allDay
                ? start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                : start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }

        // Chores
        public static let choresTitle = "Chores"
        public static let choresEmpty = "Nothing for you right now."
        public static let seeAll = "See all"
        public static let forYou = "For you"
        public static let upForGrabs = "Up for grabs"

        // Family Link
        public static let familyLinkTitle = "Family Link"
        public static let familyLinkParent = "Send minutes to your teen"
        public static let familyLinkTeen = "Minutes from family"
        public static let familyLinkSetUp = "Link with a parent or teen"
        public static let familyLinkNoRewards = "Nothing yet."

        // Household
        public static let householdTitle = "Household"
        public static let manageHousehold = "Tasks, screen-free times and settings"
        public static let changeMyName = "Change my name"
        public static let renameTitle = "Your name in this household"
        public static let renameSave = "Save"
        public static let cancel = "Cancel"

        // Today card
        public static let todayDetail = "Chores, calendar and screen-free times in one place."
        public static let todayOpen = "Open"
        public static let todayHide = "Hide"
    }
}
