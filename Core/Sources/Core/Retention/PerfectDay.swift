// PerfectDay.swift
// Core / Retention
//
// Perfect days (founder-approved gamification, 2026-10-04): a day where every one of today's goals
// got done. Recorded once per day in the App Group defaults; the run of consecutive perfect days is
// shown on Today with a little buddy victory dance the moment a day turns perfect. Missing a day just
// starts a new run (no penalty, spec §8 rule 9).

import Foundation

public enum PerfectDay {
    public static let storageKey = "shared.perfectDays"

    /// Records `date` as perfect. Returns true the first time for that day.
    @discardableResult
    public static func record(_ date: Date = .now, defaults: UserDefaults = SharedDefaults.store, calendar: Calendar = .current) -> Bool {
        var days = Set(defaults.stringArray(forKey: storageKey) ?? [])
        let key = dayKey(date, calendar: calendar)
        guard !days.contains(key) else { return false }
        days.insert(key)
        // Keep a year of history.
        let kept = days.sorted().suffix(366)
        defaults.set(Array(kept), forKey: storageKey)
        return true
    }

    public static func isPerfect(_ date: Date = .now, defaults: UserDefaults = SharedDefaults.store, calendar: Calendar = .current) -> Bool {
        (defaults.stringArray(forKey: storageKey) ?? []).contains(dayKey(date, calendar: calendar))
    }

    /// Consecutive perfect days ending today (or yesterday, while today is still open).
    public static func streak(asOf date: Date = .now, defaults: UserDefaults = SharedDefaults.store, calendar: Calendar = .current) -> Int {
        let days = Set(defaults.stringArray(forKey: storageKey) ?? [])
        var day = calendar.startOfDay(for: date)
        if !days.contains(dayKey(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(dayKey(day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    public static func total(defaults: UserDefaults = SharedDefaults.store) -> Int {
        (defaults.stringArray(forKey: storageKey) ?? []).count
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
