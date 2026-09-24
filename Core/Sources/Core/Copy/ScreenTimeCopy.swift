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
        public static let accessTitle = "See your screen time here"
        public static let accessDetail = "Allow Screen Time access and your ZANO star charges with every hour you spend off your phone. Usage, pickups and time in locked apps never leave your phone."
        public static let accessButton = "Allow access"
        /// Under the living star on Today: how charged it is.
        public static func chargeLine(percent: Int) -> String { "Charged \(percent)% · time off your phone" }
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

        /// Hour-axis labels on the chart: `6 AM`, `2 PM`.
        public static func hourLabel(_ hour: Int) -> String {
            let h = hour % 12 == 0 ? 12 : hour % 12
            return "\(h) \(hour < 12 ? "AM" : "PM")"
        }
    }
}
