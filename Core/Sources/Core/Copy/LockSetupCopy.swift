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

        // MARK: Lock set rules (editor sheet links — Wave 2E)

        public static let rulesSectionLabel = "Rules"
        public static let rulesSaveFirstHint = "Save this lock set first, then add a schedule or partial unlocks."
        public static let scheduleRowTitle = "Schedule"
        public static let scheduleRowOff = "Off"
        public static let tiersRowTitle = "Partial unlocks"
        public static let tiersRowOff = "Off: everything unlocks together"
        public static func tiersRowSummary(count: Int) -> String {
            count == 1 ? "1 tier" : "\(count) tiers"
        }
        public static let earnModeRowTitle = "Earn Mode & Time Bank"
        public static let earnModeRowDetail = "Default lock mode, minutes per goal, spending."

        // MARK: Schedule editor (spec §2 "Schedule (e.g., 7:00 AM daily)")

        public static let scheduleTitle = "Schedule"
        public static let scheduleEnabledToggle = "Lock on a schedule"
        public static let scheduleEnabledFooter = "The lock starts by itself, even if ZANO is closed. Emergency unlock is always there."
        public static let scheduleDaysLabel = "Days"
        public static let scheduleStartLabel = "Starts at"
        public static let scheduleEndLabel = "Ends"
        public static let scheduleUntilGoalsDone = "When my goals are done"
        public static let scheduleUntilTime = "At a set time"
        public static let scheduleEndTimeLabel = "Ends at"
        public static let scheduleModeLabel = "Lock mode"
        public static let scheduleUntilGoalsFooter = "Apps stay locked until today's goals are done. If they aren't, the lock ends at midnight."
        public static let scheduleUntilTimeFooter = "Apps unlock when your goals are done, or at the end time, whichever comes first."
        public static let scheduleSkipFooter = "If you've already earned your unlock today, the schedule skips that day."
        public static let scheduleRemoveButton = "Remove schedule"
        public static let scheduleErrorNoDays = "Pick at least one day."
        public static let scheduleErrorWindow = "The lock has to last at least 15 minutes and end before midnight."
        public static let scheduleErrorTime = "That time isn't valid."
        public static let scheduleRegistrationFailedMessage = "Your schedule was saved but iOS didn't accept it. Check Screen Time access and try again."
        public static func scheduleSummary(days: String, start: String, end: String?) -> String {
            if let end { return "\(days) · \(start)–\(end)" }
            return "\(days) · \(start) until goals are done"
        }
        public static let everyDay = "Every day"
        public static let weekdaysOnly = "Weekdays"
        public static let weekendsOnly = "Weekends"

        // MARK: Lock modes

        public static let modeFull = "Full"
        public static let modeEarn = "Earn"
        public static let modeFullDetail = "Apps stay locked until your goals are done."
        public static let modeEarnDetail = "Each goal adds minutes to your Time Bank. Spend them to open your apps for a while."

        // MARK: Earn Mode settings (spec §5.2)

        public static let earnModeTitle = "Earn Mode"
        public static let defaultModeLabel = "Default lock mode"
        public static let defaultModeFooter = "Used when you start a lock without picking a mode."
        public static let earnRatesLabel = "Minutes per goal"
        public static let earnRateGym = "Gym session"
        public static let earnRateFocus = "Focus block"
        public static let earnRateProtein = "Protein goal"
        public static func earnRateValue(minutes: Int) -> String { "+\(minutes) min" }
        public static let earnRatesFooter = "Other goals count toward unlocking but don't add minutes. Plan B days add half."
        public static let spendingLabel = "Spending minutes"
        public static let spendingBody = "During an Earn lock, spend minutes from the Lock tab to open your locked apps for that long. They lock again when the time's up."
        public static let expiryBody = "Unused minutes expire at midnight. No saving up."
        public static let fullLockNote = "Full locks can't be bought out with minutes. Emergency unlock always works on both."
        public static let todayBankLabel = "In your bank today"
        public static func todayBankValue(minutes: Int) -> String { "\(minutes) min" }

        // MARK: Partial unlock tiers (spec §2, §4 v2)

        public static let tiersTitle = "Partial unlocks"
        public static let tiersIntro = "Open some apps early. For example, messaging after 1 goal. Everything else unlocks when all your goals are done."
        public static let tierNameLabel = "Tier name"
        public static let tierNamePlaceholder = "e.g. Messaging"
        public static func tierThreshold(goals: Int) -> String {
            goals == 1 ? "Unlocks after 1 goal" : "Unlocks after \(goals) goals"
        }
        public static let tierAppsLabel = "Apps this tier opens"
        public static let tierAddButton = "Add a tier"
        public static let tierRemoveButton = "Remove tier"
        public static let tiersEmpty = "No tiers. Everything unlocks together."
        public static let tierNeedsApps = "Pick at least one app for each tier."
        public static func tierDefaultName(index: Int) -> String { "Tier \(index)" }
    }
}
