// ContextRulesCopy.swift
// Core / Copy
//
// Display copy for the smart unlock rules (session 19; docs/spec.md §5.26). Plain and functional,
// like the other settings explainers.

import Foundation

extension Copy {
    public enum contextRules {
        public static let rowLabel = "Smart unlock rules"
        public static let screenTitle = "Unlock rules"
        public static let intro = "Keep the apps you need open at the times you need them, even while a lock is running. Everything else stays locked."
        public static let limitsNote = "An iPhone can open or close a whole app, not a single chat or contact."
        public static let emergencyNote = "Rules only ever open more apps. The emergency unlock works exactly as before."
        public static let emptyState = "No rules yet. Add one for work apps, school apps, or anything you need during certain hours."
        public static let addButton = "Add a rule"
        public static let maxReached = "That's the maximum of 3 rules."

        // Editor
        public static let editorTitleNew = "New rule"
        public static let editorTitleEdit = "Edit rule"
        public static let nameLabel = "Name"
        public static let namePlaceholder = "Work apps"
        public static let appsLabel = "Apps to keep open"
        public static let noLockSets = "Make a lock with the apps you want open first (Lock tab), then pick it here."
        public static let daysLabel = "Days"
        public static let fromLabel = "From"
        public static let toLabel = "To"
        public static let enabledLabel = "On"
        public static let saveButton = "Save"
        public static let cancelButton = "Cancel"
        public static let deleteButton = "Delete rule"
        public static let invalidTimes = "The end needs to be at least 15 minutes after the start."
        public static let invalidDays = "Pick at least one day."

        public static func summary(_ rule: ContextRule, appsName: String, calendar: Calendar = .current) -> String {
            let days: String
            if rule.weekdays == ContextRule.workdays {
                days = "Weekdays"
            } else if rule.weekdays == LockSchedule.allWeekdays {
                days = "Every day"
            } else {
                days = rule.weekdays.sorted().map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
            }
            return "\(appsName) open \(days), \(time(rule.startMinuteOfDay)) \u{2013} \(time(rule.endMinuteOfDay))"
        }

        public static func time(_ minuteOfDay: Int) -> String {
            let date = Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
            return date.formatted(.dateTime.hour().minute())
        }

        // Learned suggestion
        public static let suggestionTitle = "Keep some apps open then?"
        public static func suggestionBody(_ suggestion: ContextRuleSuggestion, calendar: Calendar = .current) -> String {
            let day = calendar.weekdaySymbols[suggestion.weekday - 1]
            return "You ended a lock early \(suggestion.occurrences) \(day)s around \(time(suggestion.startMinuteOfDay)). A rule can keep the apps you need open then instead."
        }
        public static let suggestionYes = "Make a rule"
        public static let suggestionNo = "Not now"
    }
}
