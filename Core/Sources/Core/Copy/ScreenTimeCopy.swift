// ScreenTimeCopy.swift
// Core / Copy
//
// Strings for the on-device screen-time report (`ScreenTimeSummaryView`, drawn inside the
// `ZANOReport` extension and embedded on Today; spec §5.15, §27).

import Foundation

extension Copy {
    public enum screenTime {
        public static let sectionTitle = "Screen time"
        public static let totalLabel = "Screen time today"
        public static let mostUsed = "Most used"
        public static let lockedApps = "Locked apps"
        public static let pickups = "Pickups"
        public static let legendOther = "Other"
        public static let legendLocked = "Locked apps"
        public static let timeOffline = "Time offline"
        public static func offlineShare(percent: Int) -> String { "\(percent)% of your day so far" }
        public static let noUsageYet = "No screen time yet today."
        /// An app the system reports without a display name.
        public static let unnamedApp = "App"
        public static let accessTitle = "See your screen time here"
        public static let accessDetail = "Allow Screen Time access and your ZANO star charges with every hour you spend off your phone. Usage, pickups and time in locked apps never leave your phone."
        public static let accessButton = "Allow access"
        /// Under the living star on Today: how charged it is.
        public static func chargeLine(percent: Int) -> String { "Star \(percent)% charged · time off your phone" }
        /// Under the star before Screen Time access.
        public static let chargeHint = "Your star charges while you're off your phone"

        /// `2h 30m`, `45m`, `0m`. Minutes are floored; under a minute reads `<1m`.
        public static func duration(_ seconds: TimeInterval) -> String {
            let totalMinutes = Int(seconds / 60)
            if seconds > 0, totalMinutes == 0 { return "<1m" }
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours == 0 { return "\(minutes)m" }
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        /// Hour-axis labels on the chart, in the user's locale: `6 AM` / `2 PM` in a 12-hour locale,
        /// `06` / `14` (or the locale's own hour form) in a 24-hour one.
        public static func hourLabel(_ hour: Int) -> String {
            let calendar = Calendar.current
            let clamped = min(max(hour, 0), 23)
            guard let date = calendar.date(bySettingHour: clamped, minute: 0, second: 0, of: Date()) else {
                return "\(clamped)"
            }
            return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
        }

        /// VoiceOver value for the living star on Today.
        public static func chargeSpoken(percent: Int) -> String {
            "Star \(percent) percent charged from time off your phone"
        }

        /// A duration for VoiceOver, spelled out ("2 hours, 30 minutes") instead of `2h 30m`, which
        /// is read as letters.
        public static func spokenDuration(_ seconds: TimeInterval) -> String {
            Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        }

        /// VoiceOver summary of the hourly chart (the bars themselves are hidden from VoiceOver).
        /// `peakHour` is nil when there is no usage yet.
        public static func chartSummary(peakHour: Int?, peakMinutes: Int, lockedMinutes: Int) -> String {
            let locked = lockedMinutes == 1 ? "1 minute in locked apps" : "\(lockedMinutes) minutes in locked apps"
            guard let peakHour, peakMinutes > 0 else { return "Hourly usage chart. No usage yet. \(locked)." }
            let minutes = peakMinutes == 1 ? "1 minute" : "\(peakMinutes) minutes"
            return "Hourly usage chart. Busiest hour \(hourLabel(peakHour)), \(minutes). \(locked) today."
        }

        /// VoiceOver value for "Most used": the top app names, comma separated.
        public static func mostUsedSpoken(_ names: [String]) -> String {
            names.formatted(.list(type: .and))
        }
    }
}
