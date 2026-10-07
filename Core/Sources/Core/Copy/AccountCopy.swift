// AccountCopy.swift
// Core / Copy
//
// Display copy for the Account section in Settings (session 34): Sign in with Apple, sign out, delete
// account. The section only exists when the build has a backend. Plain and calm: an account is optional,
// everything that locks and unlocks works without one.

import Foundation

extension Copy {
    public enum account {
        public static let sectionTitle = "Account"
        public static let sectionInfo = "An account is optional. It backs up your progress and lets you use Household and Family Link. Locks, goals and unlocking work the same without one."

        // Signed out
        public static let signedOutBody = "Sign in to back up your progress and share with the people you live with."
        public static let signInFailedTitle = "Couldn't sign in"
        public static let signInFailedMessage = "Something went wrong. Check your connection and try again."
        public static let signInOfflineMessage = "You look offline. Try again when you're connected."

        // Signed in
        public static let signedInTitle = "Signed in with Apple"
        public static func signedInAs(_ email: String) -> String { "Signed in as \(email)" }
        public static let signOutRowLabel = "Sign out"
        public static let signOutConfirmTitle = "Sign out?"
        public static let signOutConfirmMessage = "Your goals, locks and history stay on this iPhone. Household and Family Link are hidden until you sign in again."
        public static let signOutConfirmButtonLabel = "Sign out"

        // Delete account (App Store 5.1.1(v))
        public static let deleteRowLabel = "Delete account"
        public static let deleteConfirmTitle = "Delete your account?"
        public static let deleteConfirmMessage = "This deletes your account and everything stored with it on our servers: backups, meal photos, Household and Family Link. It can't be undone. Your data on this iPhone and your subscription aren't affected."
        public static let deleteConfirmButtonLabel = "Delete account"
        public static let deleteDoneTitle = "Your account was deleted"
        public static let deleteDoneMessage = "Everything stored with it on our servers is gone. You're signed out."
        public static let deleteFailedTitle = "Couldn't delete your account"
        public static let deleteFailedMessage = "Nothing was deleted. Check your connection and try again."
    }
}
