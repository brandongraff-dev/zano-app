// HouseholdQuietTimes.swift
// Core / Household
//
// Household screen-free times (session 44, docs/spec.md §5.31): windows a household agrees on, like "Dinner
// 18:00-19:00 every day" or "Bedtime 22:00-07:00 school nights". The window itself is shared
// (`backend/supabase/migrations/0009_household_quiet_times.sql`); joining it is not. Each member decides on
// their own phone, the choice stays in this phone's App Group, and only this phone's own lock sets are used.
// Nobody can put a lock on anyone else's phone.
//
// The window math reuses `BedtimeGateSchedule` (session 38), which already handles a start-to-end window that
// crosses midnight, weekly windows whose end falls on the next weekday, late or early DeviceActivity callbacks,
// and stray end callbacks. A screen-free time is the same shape: a start minute, an end minute, start days.
//
// Everything here is nonisolated and reads only App Group `UserDefaults`, so the `ZANOMonitor` extension can
// call it (spec §11/§27). The pure parts are unit tested in `HouseholdQuietTimeTests`.

import Foundation

// MARK: - Model

/// One shared screen-free window. Mirrors a `household_quiet_times` row (snake_case on the wire,
/// `FamilyJSON.decoder`).
public struct HouseholdQuietTime: Codable, Sendable, Identifiable, Equatable, Hashable {
    public static let nameMaxLength = 40

    public let id: UUID
    public let householdId: UUID
    public var name: String
    /// Minutes after local midnight, 0...1439.
    public var startMinute: Int
    /// Minutes after local midnight. Earlier than `startMinute` = ends the next day.
    public var endMinute: Int
    /// Days the window starts on (1 = Sunday ... 7 = Saturday).
    public var weekdays: [Int]
    public let createdBy: UUID?
    public let updatedAt: Date?

    public init(
        id: UUID = UUID(), householdId: UUID, name: String, startMinute: Int, endMinute: Int,
        weekdays: [Int], createdBy: UUID? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdays = weekdays
        self.createdBy = createdBy
        self.updatedAt = updatedAt
    }

    public var weekdaySet: Set<Int> { Set(weekdays).intersection(LockSchedule.allWeekdays) }

    /// The same night math the Bedtime Gate uses (start = "bedtime", end = "wake", days = "nights").
    public var schedule: BedtimeGateSchedule {
        BedtimeGateSchedule(bedtimeMinute: startMinute, wakeMinute: endMinute, nights: weekdaySet)
    }

    /// Length in minutes, wrapping past midnight (0 when start == end).
    public var rawDurationMinutes: Int {
        ((endMinute - startMinute) % LockSchedule.minutesPerDay + LockSchedule.minutesPerDay) % LockSchedule.minutesPerDay
    }

    public var crossesMidnight: Bool { endMinute < startMinute }

    public enum ValidationError: Error, Sendable, Equatable {
        case emptyName
        case nameTooLong
        case noDays
        case timeOutOfRange
        /// Under the 15-minute DeviceActivity minimum (spec §27), including start == end.
        case tooShort
    }

    /// The same rules as the table's checks in 0009.
    public func validate() -> ValidationError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .emptyName }
        if trimmed.count > Self.nameMaxLength { return .nameTooLong }
        if weekdaySet.isEmpty { return .noDays }
        let range = 0..<LockSchedule.minutesPerDay
        guard range.contains(startMinute), range.contains(endMinute) else { return .timeOutOfRange }
        if rawDurationMinutes < LockSchedule.minimumWindowMinutes { return .tooShort }
        return nil
    }

    public var isValid: Bool { validate() == nil }

    /// The occurrence `date` falls in (`start <= date < end`), including one that started yesterday evening.
    public func occurrence(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isValid else { return nil }
        return schedule.night(containing: date, calendar: calendar)
    }

    /// The first occurrence that starts strictly after `date` (within the next 8 days).
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isValid else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let occurrence = schedule.night(startingOn: day, calendar: calendar)
            else { continue }
            if occurrence.start > date { return occurrence }
        }
        return nil
    }

    /// The DeviceActivity registrations this window needs (one daily, or one weekly per day).
    public var deviceActivityWindows: [BedtimeGateWindow] {
        guard isValid else { return [] }
        return schedule.deviceActivityWindows
    }

    /// Changes whenever the registrations would.
    var registrationSignature: String {
        "\(id.uuidString):\(startMinute)-\(endMinute)-" + weekdaySet.sorted().map(String.init).joined(separator: ",")
    }
}

/// This phone's choice to join one window. Never leaves the device.
public struct HouseholdQuietTimeOptIn: Codable, Sendable, Equatable {
    public var windowID: UUID
    /// One of this phone's own lock sets; `nil` = the default lock set at the time the window starts.
    public var lockSetID: UUID?
    public var joinedAt: Date

    public init(windowID: UUID, lockSetID: UUID? = nil, joinedAt: Date = .now) {
        self.windowID = windowID
        self.lockSetID = lockSetID
        self.joinedAt = joinedAt
    }
}

// MARK: - DeviceActivity names

/// `com.zano.app.quiet.<window uuid>` (every day) or `...<uuid>.d<weekday>`. Its own prefix, so saving a lock
/// schedule, the focus lock or the Bedtime Gate never touches these registrations.
public enum HouseholdQuietTimeActivity {
    public static let prefix = "com.zano.app.quiet."

    public static func rawName(windowID: UUID, weekday: Int?) -> String {
        let base = prefix + windowID.uuidString
        guard let weekday else { return base }
        return base + ".d\(weekday)"
    }

    public static func windowID(fromRawName raw: String) -> UUID? {
        guard raw.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(prefix.count).prefix(36)))
    }

    public static func isQuietTimeActivity(_ raw: String) -> Bool { windowID(fromRawName: raw) != nil }
}

// MARK: - Planning (pure)

public enum HouseholdQuietTimePlanner {
    /// Registrations all joined windows may use together. Apple caps how many activities one app can monitor
    /// (believed 20, UNVERIFIED) and lock schedules, the Bedtime Gate and the focus lock share that cap.
    public static let maxRegistrations = 7
    /// The heads-up before a joined window starts.
    public static let reminderLeadMinutes = 10
    /// How far ahead reminders are planned (the app re-plans on every open).
    public static let reminderHorizon: TimeInterval = 7 * 86_400
    public static let maxReminders = 14
    public static let reminderPrefix = "household.quiet."

    /// The windows this phone has joined, in a stable order, that are still valid.
    public static func joined(windows: [HouseholdQuietTime], optIns: [HouseholdQuietTimeOptIn]) -> [HouseholdQuietTime] {
        let ids = Set(optIns.map(\.windowID))
        return windows.filter { ids.contains($0.id) && $0.isValid }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public static func registrationCount(_ windows: [HouseholdQuietTime]) -> Int {
        windows.reduce(0) { $0 + $1.deviceActivityWindows.count }
    }

    /// Whether joining `window` keeps every joined window inside `maxRegistrations`.
    public static func canJoin(_ window: HouseholdQuietTime, joined: [HouseholdQuietTime]) -> Bool {
        guard window.isValid else { return false }
        if joined.contains(where: { $0.id == window.id }) { return true }
        return registrationCount(joined) + window.deviceActivityWindows.count <= maxRegistrations
    }

    /// The joined windows that fit inside the cap, in order (a window edited to need more days can push a
    /// later one out; it is skipped, not half-registered).
    public static func schedulable(_ joined: [HouseholdQuietTime]) -> [HouseholdQuietTime] {
        var used = 0
        var result: [HouseholdQuietTime] = []
        for window in joined {
            let needed = window.deviceActivityWindows.count
            guard used + needed <= maxRegistrations else { continue }
            used += needed
            result.append(window)
        }
        return result
    }

    /// One signature for the whole registered set, so a foreground sync only re-registers on a change.
    public static func signature(_ windows: [HouseholdQuietTime]) -> String {
        windows.map(\.registrationSignature).joined(separator: "|")
    }

    /// "Dinner in 10 min" reminders for the next week of joined windows.
    public static func reminders(
        joined: [HouseholdQuietTime], now: Date, calendar: Calendar = .current
    ) -> [PlannedReminder] {
        let lead = TimeInterval(reminderLeadMinutes * 60)
        let horizon = now.addingTimeInterval(reminderHorizon)
        var planned: [PlannedReminder] = []
        for window in joined {
            var cursor = now.addingTimeInterval(lead - 1)
            while let occurrence = window.nextOccurrence(after: cursor, calendar: calendar), occurrence.start <= horizon {
                let fire = occurrence.start.addingTimeInterval(-lead)
                if fire > now {
                    planned.append(PlannedReminder(
                        identifier: reminderPrefix + window.id.uuidString + "." + String(Int(occurrence.start.timeIntervalSince1970)),
                        title: Copy.household.quietReminderTitle(name: window.name, minutes: reminderLeadMinutes),
                        body: Copy.household.quietReminderBody(start: occurrence.start, end: occurrence.end),
                        fireDate: fire
                    ))
                }
                cursor = occurrence.start
            }
        }
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(maxReminders))
    }

    /// What Today shows for joined windows: the one running now, or one starting within the lead time.
    public enum Status: Equatable, Sendable {
        case startingSoon(window: HouseholdQuietTime, start: Date)
        case running(window: HouseholdQuietTime, end: Date)
    }

    public static func status(joined: [HouseholdQuietTime], now: Date, calendar: Calendar = .current) -> Status? {
        let running = joined.compactMap { window in
            window.occurrence(containing: now, calendar: calendar).map { (window, $0) }
        }.min { $0.1.end < $1.1.end }
        if let running { return .running(window: running.0, end: running.1.end) }
        let lead = TimeInterval(reminderLeadMinutes * 60)
        let soon = joined.compactMap { window in
            window.nextOccurrence(after: now, calendar: calendar).map { (window, $0) }
        }
        .filter { $0.1.start.timeIntervalSince(now) <= lead }
        .min { $0.1.start < $1.1.start }
        if let soon { return .startingSoon(window: soon.0, start: soon.1.start) }
        return nil
    }
}

// MARK: - App Group state

/// The cache of the household's windows, this phone's opt-ins, and one decision per occurrence. Small JSON in
/// App Group `UserDefaults`, the same approach as `FocusLockStore`, so the monitor can read it.
public enum HouseholdQuietTimeStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let windows = "household.quietTimes.windows.v1"
        static let optIns = "household.quietTimes.optIns.v1"
        static let armed = "household.quietTimes.armedOccurrences.v1"
        static let signature = "household.quietTimes.registrationSignature.v1"
        static let reminders = "household.quietTimes.reminderIDs.v1"
    }

    /// The household's windows as last fetched (shown offline, and read by the monitor).
    public static var windows: [HouseholdQuietTime] {
        get { read([HouseholdQuietTime].self, key: Keys.windows) ?? [] }
        set { write(newValue, key: Keys.windows) }
    }

    /// This phone's joins. Device-local; never sent anywhere.
    public static var optIns: [HouseholdQuietTimeOptIn] {
        get { read([HouseholdQuietTimeOptIn].self, key: Keys.optIns) ?? [] }
        set { write(newValue, key: Keys.optIns) }
    }

    public static func optIn(for windowID: UUID) -> HouseholdQuietTimeOptIn? {
        optIns.first { $0.windowID == windowID }
    }

    public static func setOptIn(_ optIn: HouseholdQuietTimeOptIn?, for windowID: UUID) {
        var all = optIns.filter { $0.windowID != windowID }
        if let optIn { all.append(optIn) }
        optIns = all
    }

    /// Replaces the cache with a fresh fetch and forgets joins for windows that are gone.
    public static func replaceWindows(_ fresh: [HouseholdQuietTime]) {
        windows = fresh
        let live = Set(fresh.map(\.id))
        let kept = optIns.filter { live.contains($0.windowID) }
        if kept.count != optIns.count { optIns = kept }
    }

    public static var joinedWindows: [HouseholdQuietTime] {
        HouseholdQuietTimePlanner.joined(windows: windows, optIns: optIns)
    }

    /// The joined window a DeviceActivity name belongs to, or `nil` (left, deleted, or not a quiet activity).
    public static func joinedWindow(forActivityRawName raw: String) -> HouseholdQuietTime? {
        guard let id = HouseholdQuietTimeActivity.windowID(fromRawName: raw) else { return nil }
        return joinedWindows.first { $0.id == id }
    }

    // One decision per occurrence (like the Bedtime Gate's per-night record): the monitor and the app never
    // arm the same occurrence twice, and nothing re-arms it after an emergency unlock or a re-registration.

    public static func hasDecided(windowID: UUID, occurrenceStart: Date) -> Bool {
        guard let decided = armedOccurrences[windowID.uuidString] else { return false }
        return abs(decided.timeIntervalSince(occurrenceStart)) < 60
    }

    public static func markDecided(windowID: UUID, occurrenceStart: Date) {
        var all = armedOccurrences
        all[windowID.uuidString] = occurrenceStart
        // Keep it small: one entry per window, nothing older than two days.
        let cutoff = occurrenceStart.addingTimeInterval(-2 * 86_400)
        armedOccurrences = all.filter { $0.value >= cutoff }
    }

    private static var armedOccurrences: [String: Date] {
        get { read([String: Date].self, key: Keys.armed) ?? [:] }
        set { write(newValue, key: Keys.armed) }
    }

    static var registrationSignature: String? {
        get { defaults.string(forKey: Keys.signature) }
        set { defaults.set(newValue, forKey: Keys.signature) }
    }

    static var scheduledReminderIDs: [String] {
        get { defaults.stringArray(forKey: Keys.reminders) ?? [] }
        set { defaults.set(newValue, forKey: Keys.reminders) }
    }

    /// Clears everything (sign-out cleanup, tests).
    public static func resetAll() {
        for key in [Keys.windows, Keys.optIns, Keys.armed, Keys.signature, Keys.reminders] { defaults.removeObject(forKey: key) }
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
