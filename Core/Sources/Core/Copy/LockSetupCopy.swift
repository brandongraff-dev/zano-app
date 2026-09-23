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
        public static let screenTitle = "Lock Sets"
        public static let newLockSetButtonLabel = "New Lock Set"

        public static let emptyStateTitle = "No lock sets yet"
        public static let emptyStateMessage = "Create a lock set to choose which apps get shielded."

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
            if appCount > 0 { parts.append("\(appCount) app\(appCount == 1 ? "" : "s")") }
            if categoryCount > 0 { parts.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies")") }
            if webDomainCount > 0 { parts.append("\(webDomainCount) site\(webDomainCount == 1 ? "" : "s")") }
            return parts.joined(separator: ", ")
        }

        public static let saveErrorTitle = "Couldn't save"

        public static let newLockSetTitle = "New Lock Set"
        public static let editLockSetTitle = "Edit Lock Set"
        public static let nameFieldLabel = "Name"
        public static let nameFieldPlaceholder = "e.g. Social, Games, All"
        public static let saveButtonLabel = "Save"

        public static let selectAppsButtonLabel = "Apps & Categories"
        public static let appPickerFooter = "Choose the apps, categories, and websites this lock set shields."

        public static let authorizationErrorTitle = "Couldn't request access"
        public static let authorizationErrorMessage = "Something went wrong requesting Screen Time access. Try again."
        public static let authorizationDeniedTitle = "Screen Time access needed"
        public static let authorizationDeniedMessage =
            "ZANO needs Screen Time access to shield apps. Enable it in Settings > Screen Time > ZANO."
    }
}
