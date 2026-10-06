// SleepStore.swift
// Core / Sleep
//
// App Group state for the sleep wind-down (docs/spec.md §5.25): the settings, and the last 120 nights.
// Small JSON in UserDefaults, the same approach as `FocusLockStore`. Device-local, never synced.

import Foundation

public enum SleepStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let settings = "sleep.settings.v1"
        static let nights = "sleep.nights.v1"
        static let skippedCheckIn = "sleep.skippedCheckInNight.v1"
    }

    public static let maxNights = 120

    public static var settings: SleepSettings {
        get { read(SleepSettings.self, key: Keys.settings) ?? SleepSettings() }
        set { write(newValue, key: Keys.settings) }
    }

    /// Oldest first.
    public static var nights: [SleepNight] {
        get { read([SleepNight].self, key: Keys.nights) ?? [] }
        set { write(Array(newValue.sorted { $0.id < $1.id }.suffix(maxNights)), key: Keys.nights) }
    }

    /// The night whose check-in was skipped, so the card doesn't come back the same morning.
    public static var skippedCheckInNight: String? {
        get { defaults.string(forKey: Keys.skippedCheckIn) }
        set { defaults.set(newValue, forKey: Keys.skippedCheckIn) }
    }

    /// Adds `night`, or replaces the stored night with the same id.
    public static func upsert(_ night: SleepNight) {
        var all = nights
        if let index = all.firstIndex(where: { $0.id == night.id }) {
            all[index] = night
        } else {
            all.append(night)
        }
        nights = all
    }

    public static func night(id: String) -> SleepNight? {
        nights.first { $0.id == id }
    }

    /// Settings > Sleep > "Delete my sleep notes".
    public static func resetAll() {
        for key in [Keys.settings, Keys.nights, Keys.skippedCheckIn] { defaults.removeObject(forKey: key) }
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
