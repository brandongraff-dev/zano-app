// Core/Sources/Core/Verification/BedtimeGateSchedule.swift
//
// Session 38. The Bedtime Gate's night window (docs/spec.md §5.10 "Lock auto-arms at the user's set
// bedtime"; §2 "Schedule (e.g., ... 10:30 PM bedtime)"; §27 "DeviceActivity schedules have a
// minimum interval of 15 minutes and can be delayed"), and the App Group state the app and the
// `ZANOMonitor` extension share for it.
//
// A night runs from bedtime to wake time (`SunriseAlarmManager.Settings.bedtime`/`wakeTime`, the one
// settings row both setup screens share). It usually crosses midnight. Nights are keyed by the
// weekday bedtime falls on, the same numbering `LockSchedule` uses (1 = Sunday ... 7 = Saturday).
//
// Everything here is nonisolated and reads only App Group `UserDefaults`, so the monitor extension
// can call it (no SwiftData, no networking, spec §11/§27). The pure math is unit-tested in
// `BedtimeGateScheduleTests`.

import Foundation

// MARK: - DeviceActivity names

/// Stable `DeviceActivityName`s for the Bedtime Gate. Every night on: one daily registration under
/// the original name (`com.zano.app.bedtimeGate`, so an install that registered it before session 38
/// is replaced in place). Some nights off: one weekly registration per night, `<name>.d<weekday>`.
public enum BedtimeGateActivity {
    public static let dailyRawName = "com.zano.app.bedtimeGate"

    public static func rawName(nightWeekday: Int?) -> String {
        guard let nightWeekday else { return dailyRawName }
        return dailyRawName + ".d\(nightWeekday)"
    }

    public static func isBedtimeActivity(_ raw: String) -> Bool {
        raw == dailyRawName || raw.hasPrefix(dailyRawName + ".d")
    }
}

// MARK: - BedtimeGateSchedule

/// The nightly bedtime-to-wake window. Pure: times are minutes after local midnight, and every date
/// computation goes through the `Calendar` it is handed, so DST nights come out by wall-clock time
/// (a 22:30-06:30 night is 7 hours on the spring-forward night and 9 on the fall-back one), which is
/// also how DeviceActivity reads `DateComponents`.
public struct BedtimeGateSchedule: Sendable, Equatable {
    public static let minutesPerDay = LockSchedule.minutesPerDay
    /// Spec §27: a DeviceActivity window can't be shorter.
    public static let minimumWindowMinutes = LockSchedule.minimumWindowMinutes
    public static let everyNight: Set<Int> = LockSchedule.allWeekdays
    /// DeviceActivity callbacks can land early or late (spec §27). Same allowance as `SpendWindow`.
    public static let callbackTolerance: TimeInterval = SpendWindow.endTolerance

    public var bedtimeMinute: Int
    public var wakeMinute: Int
    /// Weekdays whose night the gate runs (the day bedtime falls on). Empty = no nights.
    public var nights: Set<Int>

    public init(bedtimeMinute: Int, wakeMinute: Int, nights: Set<Int> = BedtimeGateSchedule.everyNight) {
        self.bedtimeMinute = Self.clampedMinute(bedtimeMinute)
        self.wakeMinute = Self.clampedMinute(wakeMinute)
        self.nights = nights.intersection(LockSchedule.allWeekdays)
    }

    public init(bedtime: Date, wakeTime: Date, nights: Set<Int> = BedtimeGateSchedule.everyNight, calendar: Calendar = .current) {
        self.init(
            bedtimeMinute: LockSchedule.minuteOfDay(bedtime, calendar: calendar),
            wakeMinute: LockSchedule.minuteOfDay(wakeTime, calendar: calendar),
            nights: nights
        )
    }

    /// Bedtime to wake in minutes, at least the 15-minute DeviceActivity minimum. A wake time equal to
    /// bedtime, or under 15 minutes after it, gives the minimum rather than a 24-hour lock.
    public var durationMinutes: Int {
        let raw = ((wakeMinute - bedtimeMinute) % Self.minutesPerDay + Self.minutesPerDay) % Self.minutesPerDay
        return max(raw, Self.minimumWindowMinutes)
    }

    /// Where the window ends, minutes after midnight (wake time, unless the minimum pushed it later).
    public var endMinute: Int { (bedtimeMinute + durationMinutes) % Self.minutesPerDay }

    /// Whether the window ends on the next calendar day.
    public var crossesMidnight: Bool { bedtimeMinute + durationMinutes >= Self.minutesPerDay }

    public var runsEveryNight: Bool { nights == Self.everyNight }

    // MARK: DeviceActivity registrations

    /// One daily repeating window when every night is on, otherwise one weekly window per night (the
    /// end lands on the following weekday when the night crosses midnight). No nights, no windows.
    public var deviceActivityWindows: [BedtimeGateWindow] {
        guard !nights.isEmpty else { return [] }
        let start = bedtimeMinute
        let end = endMinute
        let crosses = crossesMidnight
        let days: [Int?] = runsEveryNight ? [nil] : nights.sorted().map { Optional($0) }
        return days.map { weekday in
            BedtimeGateWindow(
                startWeekday: weekday,
                endWeekday: weekday.map { crosses ? Self.weekday(after: $0) : $0 },
                startHour: start / 60,
                startMinute: start % 60,
                endHour: end / 60,
                endMinute: end % 60
            )
        }
    }

    /// Changes whenever the registrations would; stored after registering so a foreground sync only
    /// re-registers when something actually changed (or the registrations were lost).
    public var registrationSignature: String {
        "\(bedtimeMinute)-\(endMinute)-" + nights.sorted().map(String.init).joined(separator: ",")
    }

    /// The activity a night starting at `nightStart` is registered under.
    public func activityRawName(forNightStartingAt nightStart: Date, calendar: Calendar = .current) -> String {
        BedtimeGateActivity.rawName(nightWeekday: runsEveryNight ? nil : calendar.component(.weekday, from: nightStart))
    }

    // MARK: Nights as dates

    /// The night that starts on `day`'s calendar date, or `nil` if that night is off.
    public func night(startingOn day: Date, calendar: Calendar = .current) -> DateInterval? {
        guard nights.contains(calendar.component(.weekday, from: day)) else { return nil }
        let startDay = calendar.startOfDay(for: day)
        guard
            let start = LockSchedule.date(on: startDay, minuteOfDay: bedtimeMinute, calendar: calendar),
            let endDay = calendar.date(byAdding: .day, value: crossesMidnight ? 1 : 0, to: startDay),
            let end = LockSchedule.date(on: endDay, minuteOfDay: endMinute, calendar: calendar),
            end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The night `date` falls in (`start <= date < end`): tonight's, or for an after-midnight date,
    /// the one that started yesterday evening. `nil` outside every night, or on a night that's off.
    public func night(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let night = night(startingOn: day, calendar: calendar)
            else { continue }
            if night.start <= date && date < night.end { return night }
        }
        return nil
    }

    /// The night a DeviceActivity start callback at `date` belongs to, allowing for a callback that
    /// lands a little before bedtime (spec §27).
    public func night(forStartCallbackAt date: Date, calendar: Calendar = .current) -> DateInterval? {
        night(containing: date, calendar: calendar)
            ?? night(containing: date.addingTimeInterval(Self.callbackTolerance), calendar: calendar)
    }

    /// Whether `date` is past the end of the night it was in, allowing for an early end callback. A
    /// stray end (e.g. iOS ending the interval because the schedule was re-registered mid-night) is
    /// not "over": the night still contains `date`.
    public func isNightOver(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let night = night(containing: date.addingTimeInterval(Self.callbackTolerance), calendar: calendar) else { return true }
        // Inside a night that started after `date` = the next night is about to start; this one is over.
        return night.start > date
    }

    // MARK: Helpers

    static func weekday(after weekday: Int) -> Int { weekday % 7 + 1 }

    private static func clampedMinute(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

/// One `DeviceActivitySchedule` worth of a `BedtimeGateSchedule`.
public struct BedtimeGateWindow: Sendable, Hashable {
    /// `nil` = every night (daily repeat); otherwise the weekly repeat's start weekday.
    public let startWeekday: Int?
    /// The weekly repeat's end weekday: the next day when the night crosses midnight.
    public let endWeekday: Int?
    public let startHour: Int
    public let startMinute: Int
    public let endHour: Int
    public let endMinute: Int

    public var activityRawName: String { BedtimeGateActivity.rawName(nightWeekday: startWeekday) }

    public var startComponents: DateComponents {
        DateComponents(hour: startHour, minute: startMinute, second: 0, weekday: startWeekday)
    }

    public var endComponents: DateComponents {
        DateComponents(hour: endHour, minute: endMinute, second: 0, weekday: endWeekday)
    }
}

// MARK: - BedtimeGateSharedState

/// The Bedtime Gate's App Group state, readable from the app and from `ZANOMonitor`. Cheap
/// `UserDefaults` reads only. Keys predate session 38 where they existed (`advancedSettings`,
/// `lastArmedDay`), so saved values carry over.
public enum BedtimeGateSharedState {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let advancedSettings = "core.bedtimeGate.advancedSettings.v1"
        /// Before session 38 this held the time the lock was armed; now it holds the start of the
        /// night that was armed. Both fall on the same calendar day for a pre-midnight bedtime.
        static let lastArmedNight = "core.bedtimeGate.lastArmedDay.v1"
        static let registrationSignature = "core.bedtimeGate.registrationSignature.v1"
    }

    public static var advancedSettings: BedtimeGateAdvancedSettings {
        get {
            guard let data = defaults.data(forKey: Keys.advancedSettings),
                  let decoded = try? JSONDecoder().decode(BedtimeGateAdvancedSettings.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Keys.advancedSettings)
        }
    }

    /// Tonight's schedule, or `nil` when the gate is off: never set up (so nobody who never opened the
    /// setup screens gets a 22:30 lock from the defaults), or switched off.
    public static func currentSchedule() -> BedtimeGateSchedule? {
        guard let settings = SunriseAlarmManager.storedSettings(), settings.enabled else { return nil }
        return BedtimeGateSchedule(bedtime: settings.bedtime, wakeTime: settings.wakeTime, nights: advancedSettings.nights)
    }

    // One bedtime decision per night

    /// Whether the night starting at `nightStart` was already armed (by the monitor or the app), or
    /// passed over because another lock was running. Either way the gate leaves that night alone, so a
    /// late callback or the foreground catch-up never re-arms after an emergency unlock.
    public static func hasArmed(nightStartingAt nightStart: Date, calendar: Calendar = .current) -> Bool {
        guard let stored = defaults.object(forKey: Keys.lastArmedNight) as? Date else { return false }
        return calendar.isDate(stored, inSameDayAs: nightStart)
    }

    public static func markArmed(nightStartingAt nightStart: Date) {
        defaults.set(nightStart, forKey: Keys.lastArmedNight)
    }

    static var registrationSignature: String? {
        get { defaults.string(forKey: Keys.registrationSignature) }
        set { defaults.set(newValue, forKey: Keys.registrationSignature) }
    }

    /// Test-only reset of the per-night and registration records (settings are left alone).
    static func resetNightRecords() {
        defaults.removeObject(forKey: Keys.lastArmedNight)
        defaults.removeObject(forKey: Keys.registrationSignature)
    }
}
