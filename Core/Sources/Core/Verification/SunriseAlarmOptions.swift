// SunriseAlarmOptions.swift
// Core / Verification
//
// docs/spec.md §5.10 (Sunrise Alarm). The three choices the iOS Clock app's alarm editor offers and
// this alarm now has too: which days it repeats (`RepeatDays`), which sound it plays
// (`AlarmSoundChoice`), and a plain backup alarm after it (`SunriseAlarmManager.Settings.
// backupAlarmEnabled`). Pure value types, no UI and no scheduling, so they are unit-testable.

import Foundation

/// The wake-up sounds. Each is a short synthesized tone bundled with the app
/// (`App/ZANO/Sounds/alarm-<id>.wav`, under 30 seconds, linear PCM, so it is valid both as a local
/// notification sound and as an in-app preview). The volume rises over the clip, so every sound
/// wakes you gently and then insistently.
public enum AlarmSoundChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case daybreak
    case chimes
    case marimba
    case pulse
    case bells
    case ripple

    public var id: String { rawValue }

    /// The bundled file's name, with extension (what `UNNotificationSoundName` and `Bundle` want).
    public var fileName: String { "alarm-\(rawValue).wav" }

    /// The name without extension, for `Bundle.url(forResource:withExtension:)`.
    public var resourceName: String { "alarm-\(rawValue)" }
}

/// Weekday selection, using `Calendar` weekday numbers (1 = Sunday ... 7 = Saturday), the same as
/// `Calendar.component(.weekday, from:)`. An empty set means "Never": the alarm rings once, at the
/// next wake time, and then switches itself off, exactly as the Clock app's alarm does.
public enum RepeatDays {
    public static let everyDay: Set<Int> = Set(1...7)
    public static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public static let weekends: Set<Int> = [1, 7]

    /// The summary shown on the Repeat row: "Never", "Every day", "Weekdays", "Weekends", or the
    /// short day names in week order ("Mon, Wed, Fri"), the way the Clock app writes it.
    public static func summary(_ days: Set<Int>, calendar: Calendar = .current) -> String {
        let valid = days.intersection(everyDay)
        if valid.isEmpty { return Copy.sunriseAlarm.repeatNever }
        if valid == everyDay { return Copy.sunriseAlarm.repeatEveryDay }
        if valid == weekdays { return Copy.sunriseAlarm.repeatWeekdays }
        if valid == weekends { return Copy.sunriseAlarm.repeatWeekends }
        let symbols = calendar.shortWeekdaySymbols
        // Week order starts at the calendar's first weekday (Monday in much of Europe).
        let ordered = (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
        return ordered
            .filter { valid.contains($0) }
            .map { symbols[$0 - 1] }
            .joined(separator: ", ")
    }

    /// The full weekday name for the Repeat screen's rows ("Every Monday").
    public static func rowTitle(weekday: Int, calendar: Calendar = .current) -> String {
        let names = calendar.weekdaySymbols
        guard (1...7).contains(weekday) else { return "" }
        return Copy.sunriseAlarm.repeatRowTitle(weekdayName: names[weekday - 1])
    }

    /// Weekday numbers in the order the Repeat screen lists them (the calendar's first weekday first).
    public static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
    }
}
