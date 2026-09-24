// LockSetupCopy.swift
// Core / Copy
//
// `Copy.lockSetup` — every user-facing string `App/ZANO/Features/LockSetup/{LockSetupView,
// AppPickerView}.swift` call, under the `Copy.<area>.<key>` umbrella this codebase actually uses
// (see `Copy.swift`'s header). This is a reconciliation, not new scope:
// `LockSetupView.swift`'s own "ASSUMED API" header comment already documents this exact key list
// (`screenTitle`, `newLockSetButtonLabel`, ... `authorizationDeniedMessage`) — this file adds the
// umbrella shape those two views already call rather than re-deriving it. Repo-wide sweep
// (2026-09-22): this namespace was referenced across both files but never declared anywhere in
// `Core/Sources/Core/Copy`, which would have failed to compile. Plain, tone-neutral admin-screen
// copy throughout, per that same header comment — no `CoachVoice` parameter threaded through.

import Foundation

extension Copy {
    public enum lockSetup {
        public static let screenTitle = "Lock sets"
        public static let newLockSetButtonLabel = "New lock set"

        public static let emptyStateTitle = "No lock sets yet"
        public static let emptyStateMessage = "Create a lock set to choose which apps get locked."

        public static let deleteButtonLabel = "Delete"
        public static let deleteConfirmTitle = "Delete this lock set?"
        public static func deleteConfirmMessage(name: String) -> String {
            "\"\(name)\" will be removed. This can't be undone."
        }

        public static func defaultToggleAccessibilityLabel(name: String) -> String {
            "Make \"\(name)\" the default lock set"
        }

        public static let noAppsSelected = "No apps selected"
        public static func selectionSummary(appCount: Int, categoryCount: Int, webDomainCount: Int) -> String {
            var parts: [String] = []
            if appCount > 0 { parts.append(appCount == 1 ? "1 app" : "\(appCount) apps") }
            if categoryCount > 0 { parts.append(categoryCount == 1 ? "1 category" : "\(categoryCount) categories") }
            if webDomainCount > 0 { parts.append(webDomainCount == 1 ? "1 website" : "\(webDomainCount) websites") }
            return parts.joined(separator: ", ")
        }

        /// Explains the star on each lock set card.
        public static let defaultStarFooter = "The starred set is your default. It's the one that locks when you don't pick a set, like when a lock starts from an NFC tag."

        public static let saveErrorTitle = "Couldn't save"
        public static let saveErrorMessage = "Your change wasn't saved. Try again."
        public static let deleteLastLockSetMessage = "You need at least one lock set. Create another one before deleting this."
        public static let deleteErrorTitle = "Couldn't delete"

        public static let newLockSetTitle = "New lock set"
        public static let editLockSetTitle = "Edit lock set"
        public static let nameFieldLabel = "Name"
        public static let nameFieldPlaceholder = "e.g. Social, Games, All"
        public static let saveButtonLabel = "Save"

        public static let selectAppsButtonLabel = "Apps & categories"
        public static let appPickerFooter = "Choose the apps, categories, and websites to lock."

        // Plain-language path to the iPhone Settings app (Screen Time lives there; it can be restricted
        // by a parent or an MDM profile, which is the case "Try again" can't fix).
        public static let authorizationErrorTitle = "Couldn't turn on Screen Time access"
        public static let authorizationErrorMessage = "Check your connection and try again."
        public static let authorizationDeniedTitle = "Screen Time access is off"
        public static let authorizationDeniedMessage =
            "Screen Time access wasn't turned on. Try again, or check the iPhone Settings app > Screen Time if it's restricted."
        public static let openSettingsButtonLabel = "Open Settings"
        public static let tryAgainButtonLabel = "Try again"
    }
}
