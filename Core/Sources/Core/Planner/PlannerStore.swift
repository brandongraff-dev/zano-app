// PlannerStore.swift
// Core / Planner
//
// App Group state for the Planner (docs/spec.md §5.30): the task list and the settings. Small JSON in
// UserDefaults, the same approach as `FocusLockStore` and `SleepStore`. On this device only, never synced.
// `DeviceDataReset` clears every App Group key, so "erase everything" covers it.

import Foundation

public enum PlannerStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let tasks = "planner.tasks.v1"
        static let settings = "planner.settings.v1"
        static let scheduled = "planner.scheduledReminderIDs.v1"
    }

    /// Done tasks older than this are dropped when the list is saved.
    public static let keepDoneDays = 30
    public static let maxTasks = 500

    public static var tasks: [PlannerTask] {
        get { read([PlannerTask].self, key: Keys.tasks) ?? [] }
        set { write(prune(newValue), key: Keys.tasks) }
    }

    public static var settings: PlannerSettings {
        get { read(PlannerSettings.self, key: Keys.settings) ?? PlannerSettings() }
        set { write(newValue, key: Keys.settings) }
    }

    /// The notification identifiers this feature has scheduled, so they can be replaced.
    public static var scheduledIdentifiers: [String] {
        get { defaults.stringArray(forKey: Keys.scheduled) ?? [] }
        set { defaults.set(newValue, forKey: Keys.scheduled) }
    }

    public static func upsert(_ task: PlannerTask) {
        var all = tasks
        if let index = all.firstIndex(where: { $0.id == task.id }) {
            all[index] = task
        } else {
            all.append(task)
        }
        tasks = all
    }

    public static func delete(id: UUID) {
        tasks = tasks.filter { $0.id != id }
    }

    /// Flips done, stamping when.
    public static func toggleDone(id: UUID, now: Date = .now) {
        var all = tasks
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].isDone.toggle()
        all[index].completedAt = all[index].isDone ? now : nil
        tasks = all
    }

    /// Drops tasks done more than `keepDoneDays` ago and caps the list.
    static func prune(_ list: [PlannerTask], now: Date = .now) -> [PlannerTask] {
        let cutoff = now.addingTimeInterval(-Double(keepDoneDays) * 86_400)
        let kept = list.filter { task in
            guard task.isDone, let done = task.completedAt else { return true }
            return done >= cutoff
        }
        return Array(kept.suffix(maxTasks))
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
