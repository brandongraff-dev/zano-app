// FocusLockCopy.swift
// Core / Copy
//
// Display copy for the work-hours focus lock (session 17; docs/spec.md §5.24). Plain and
// functional, not voice-switched: it explains a setting and asks a yes/no, like the Always Allowed
// and Auto-Focus explainers.

import Foundation

extension Copy {
    public enum focusLock {
        public static let rowLabel = "Focus lock"
        public static let rowValueOn = "On"
        public static let screenTitle = "Focus lock"
        public static let intro = "Lock your distracting apps during meetings and focus time, and open them again the moment it ends. No goals to earn."
        public static let toggleLabel = "Lock during my calendar"
        public static let privacyNote = "Your calendar is read on this phone only. Event names never leave it."
        public static let accessOffTitle = "Calendar access is off"
        public static let accessOffMessage = "Allow Calendar in the iPhone Settings app so ZANO can see when you are busy."
        public static let openSettingsButton = "Open Settings"

        public static let whatSectionTitle = "What to lock for"
        public static let meetingsLabel = "Meetings with other people"
        public static let meetingsDetail = "Busy events that have other attendees."
        public static let focusBlocksLabel = "Focus blocks"
        public static func focusBlocksDetail(keywords: [String]) -> String {
            "Events with a word like \(keywords.prefix(3).joined(separator: ", ")) in the title."
        }

        public static let appsSectionTitle = "Apps to lock"
        public static let defaultAppsLabel = "Your default lock"

        public static let askSectionTitle = "Lock for these?"
        public static let askFooter = "Say yes to the same event twice and ZANO locks for it by itself. Say no twice and it stops asking."
        public static func askTitle(eventTitle: String) -> String {
            eventTitle.isEmpty ? "Lock during this event?" : "Lock during \u{201C}\(eventTitle)\u{201D}?"
        }
        public static let yesButton = "Lock it"
        public static let noButton = "Not this one"

        public static let upcomingSectionTitle = "Locked for"
        public static let upcomingEmpty = "Nothing coming up. Meetings and focus blocks on your calendar will show here."
        public static let askAgainButton = "Ask me again"
        public static let emergencyNote = "You can always end a focus lock early with the emergency unlock. Doing that tells ZANO not to lock for that event next time."

        public static func windowLine(start: Date, end: Date) -> String {
            let first = start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            let last = end.formatted(.dateTime.hour().minute())
            return "\(first) \u{2013} \(last)"
        }

        public static func reasonLabel(_ reason: FocusLockReason, mergedCount: Int) -> String {
            if mergedCount > 1 { return "\(mergedCount) back-to-back events" }
            switch reason {
            case .meeting: return "Meeting"
            case .focusBlock: return "Focus block"
            }
        }

        /// The status line while a focus lock is running.
        public static let activeStatus = "Locked \u{00B7} focus time"
        public static func activeUntil(_ end: Date) -> String {
            "Focus lock until \(end.formatted(.dateTime.hour().minute()))"
        }
    }
}
