// StravaActivityStore.swift
// Core / Strava
//
// The on-device cache of recent Strava activities (session 40). The home/outdoor workout check reads it
// (`HomeWorkoutVerifier`), `StravaActivitySync` fills it. Main-app `UserDefaults.standard` only: extensions
// never need Strava data, and activities never leave the device again once fetched (docs/spec.md §24).
//
// Keeps two days (yesterday + today) so a late upload of last night's run can still be read, without
// growing forever.

import Foundation

public enum StravaActivityStore {
    static let linkedKey = "zano.strava.linked.v1"
    static let activitiesKey = "zano.strava.activities.v1"
    static let lastFetchKey = "zano.strava.lastFetch.v1"

    /// Every key, for Settings > "Delete all my data".
    public static let allKeys = [linkedKey, activitiesKey, lastFetchKey]

    private static var defaults: UserDefaults { .standard }

    /// Set after a successful connect; cleared on disconnect or when the server says the link is gone.
    public static var isLinked: Bool {
        get { defaults.bool(forKey: linkedKey) }
        set {
            defaults.set(newValue, forKey: linkedKey)
            if !newValue {
                defaults.removeObject(forKey: activitiesKey)
                defaults.removeObject(forKey: lastFetchKey)
            }
        }
    }

    public static var lastFetch: Date? {
        get { defaults.object(forKey: lastFetchKey) as? Date }
        set { defaults.set(newValue, forKey: lastFetchKey) }
    }

    public static var activities: [StravaActivity] {
        guard let data = defaults.data(forKey: activitiesKey) else { return [] }
        return (try? JSONDecoder().decode([StravaActivity].self, from: data)) ?? []
    }

    /// Merges `fetched` into the cache (newer copy of the same id wins) and drops anything that started
    /// before `keepSince`.
    public static func save(_ fetched: [StravaActivity], keepSince: Date) {
        let merged = merge(existing: activities, fetched: fetched, keepSince: keepSince)
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: activitiesKey) }
    }

    /// Pure merge, unit tested.
    static func merge(existing: [StravaActivity], fetched: [StravaActivity], keepSince: Date) -> [StravaActivity] {
        var byID: [String: StravaActivity] = [:]
        for activity in existing { byID[activity.id] = activity }
        for activity in fetched { byID[activity.id] = activity }
        return byID.values
            .filter { $0.startDate >= keepSince }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Cached activities that started inside `window` (same `.strictStartDate` rule as the Health query).
    public static func activities(in window: DateInterval) -> [StravaActivity] {
        guard isLinked else { return [] }
        return activities.filter { $0.startDate >= window.start && $0.startDate <= window.end }
    }
}
