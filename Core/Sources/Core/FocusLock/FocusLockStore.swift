// FocusLockStore.swift
// Core / FocusLock
//
// App Group state for the work-hours focus lock (docs/spec.md §5.24), the same small-JSON-in-
// UserDefaults approach `LockEngineSharedState` uses so the `ZANOMonitor` extension can read it
// without opening SwiftData: the user's settings, the learning memory, the windows armed with
// DeviceActivity, and the proposals waiting for a yes or no. Device-local, never synced.

import Foundation

public enum FocusLockStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let settings = "focusLock.settings.v1"
        static let memory = "focusLock.memory.v1"
        static let armed = "focusLock.armedWindows.v1"
        static let proposals = "focusLock.pendingProposals.v1"
        static let answers = "focusLock.answers.v1"
    }

    public static var settings: FocusLockSettings {
        get { read(FocusLockSettings.self, key: Keys.settings) ?? FocusLockSettings() }
        set { write(newValue, key: Keys.settings) }
    }

    public static var memory: FocusLockPatternMemory {
        get { read(FocusLockPatternMemory.self, key: Keys.memory) ?? FocusLockPatternMemory() }
        set { write(newValue, key: Keys.memory) }
    }

    /// Windows registered with DeviceActivity (the monitor looks its lock up here).
    public static var armedWindows: [FocusLockWindow] {
        get { read([FocusLockWindow].self, key: Keys.armed) ?? [] }
        set { write(newValue, key: Keys.armed) }
    }

    /// Windows waiting for the user's yes or no.
    public static var pendingProposals: [FocusLockProposal] {
        get { read([FocusLockProposal].self, key: Keys.proposals) ?? [] }
        set { write(newValue, key: Keys.proposals) }
    }

    /// The user's yes (`true`) or no (`false`) per window id, so a window is never asked about twice.
    public static var answers: [String: Bool] {
        get { read([String: Bool].self, key: Keys.answers) ?? [:] }
        set { write(newValue, key: Keys.answers) }
    }

    public static func armedWindow(forActivityRawName raw: String) -> FocusLockWindow? {
        guard let id = FocusLockActivity.windowID(fromRawName: raw) else { return nil }
        return armedWindows.first { $0.id == id }
    }

    /// The focus window running at `date`, if any (for "Locked until 3:00 pm").
    public static func activeWindow(at date: Date) -> FocusLockWindow? {
        armedWindows.first { $0.start <= date && date < $0.end }
    }

    /// Records that a focus lock ended early by emergency unlock: counts as a "no" for that event.
    public static func recordEndedEarly(activityRawName raw: String) {
        guard let window = armedWindow(forActivityRawName: raw) else { return }
        var learned = memory
        learned.recordDecline(window.patternKey)
        memory = learned
    }

    /// Clears everything (Settings: turn the feature off and forget what it learned).
    public static func resetAll() {
        for key in [Keys.settings, Keys.memory, Keys.armed, Keys.proposals, Keys.answers] { defaults.removeObject(forKey: key) }
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

/// `DeviceActivityName` raw strings for focus windows. Their own prefix, so saving a lock schedule
/// (which stops every activity under its lock set's prefix) never touches them.
public enum FocusLockActivity {
    public static let prefix = "com.zano.app.focus."

    public static func rawName(windowID: String) -> String { prefix + windowID }

    public static func windowID(fromRawName raw: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let id = String(raw.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    public static func isFocusActivity(_ raw: String) -> Bool { windowID(fromRawName: raw) != nil }
}
