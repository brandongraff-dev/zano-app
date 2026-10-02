// Core/Sources/Core/LockEngine/ReclaimedOpens.swift
//
// "Reclaimed opens": each time the user taps the shield's "Close app" button instead of waiting it
// out or spending Time Bank minutes (research item 3, docs/design/growth-and-ml-research.md: in
// the one sec study the option to dismiss is what cut opens by 57%, and 36% of attempts were
// abandoned — counting those as wins makes "Time Reclaimed" credible, spec §5.15).
//
// Written by `ShieldActionExtension` (an extension: App Group defaults only, one small dictionary,
// no SwiftData, no networking — spec §27). Read by `WeeklyRecapBuilder` and anything that wants a
// "you closed it N times this week" line. Counts are per local calendar day, kept for 60 days.
// Two shield taps racing can undercount by one; acceptable for a count-only, on-device metric
// (same trade-off as `SharedDefaults.incrementShieldImpressionCount`).

import Foundation

public enum ReclaimedOpens {
    private static let key = "zano.reclaimedOpens.byDay.v1"
    static let retentionDays = 60
    /// A rough, conservative "time back" per close for display copy: one sec's users reopened far
    /// less after closing; we assume a modest 5 minutes per close avoided.
    public static let estimatedMinutesPerClose = 5

    /// Adds one close for `date`'s day. Call from the shield's "Close app" handler.
    public static func recordClose(
        at date: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = SharedDefaults.store
    ) {
        var counts = load(defaults)
        let day = dayKey(date, calendar: calendar)
        counts[day, default: 0] += 1
        if counts.count > retentionDays {
            let keep = counts.keys.sorted().suffix(retentionDays)
            counts = counts.filter { keep.contains($0.key) }
        }
        defaults.set(counts, forKey: key)
    }

    /// Closes on `[start, end)`, by local day.
    public static func count(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = SharedDefaults.store
    ) -> Int {
        let counts = load(defaults)
        var total = 0
        var day = calendar.startOfDay(for: start)
        while day < end {
            total += counts[dayKey(day, calendar: calendar)] ?? 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// Closes in the 7 days ending today (today included).
    public static func countThisWeek(
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = SharedDefaults.store
    ) -> Int {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -7, to: tomorrow) ?? now
        return count(from: start, to: tomorrow, calendar: calendar, defaults: defaults)
    }

    // MARK: Storage

    /// "yyyy-MM-dd" in `calendar`'s time zone; sorts chronologically as a string.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func load(_ defaults: UserDefaults) -> [String: Int] {
        (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }
}
