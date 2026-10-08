// LockedOutAttemptTracker.swift
// Core / LockEngine
//
// docs/spec.md §5.16 Locked-Out Moment: "When a user tries to open a blocked app 3+ times in an
// hour, the shield shows a special 'Locked Out' card with a 'Share this' option."
//
// Writer: `ShieldConfigurationExtension` (ZANOShieldConfig) calls `recordAttempt(appName:)` each
// time the system asks it for a shield — the only "the user just opened a blocked app" signal iOS
// gives. Readers: the app (Today's locked-out card, the Lock tab). Lives in Core so both the
// extension and the app can reach it.
//
// Extension budget (spec §11, §27): one App Group defaults read and one write per call, no
// SwiftData, no networking. Only a display-name string is ever stored, never an
// `ApplicationToken` (spec §24: tokens never leave the device, and never need to be persisted here).

import Foundation

public enum LockedOutAttemptTracker {

    /// spec §5.16: "3+ times in an hour."
    public static let threshold = 3
    /// spec §5.16: "in an hour."
    public static let window: TimeInterval = 3600
    /// Attempts older than this are dropped on every write, so the stored list stays tiny.
    static let retention: TimeInterval = 86_400
    /// The system can render the shield more than once for one attempt (e.g. returning to the
    /// app switcher and back). Renders this close together count once.
    static let sameAttemptInterval: TimeInterval = 10

    /// Same rationale and annotation as `SharedDefaults.defaults`: documented thread-safe, not yet
    /// marked `Sendable` by the SDK.
    nonisolated(unsafe) private static let suite: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        /// `["times": [TimeInterval since 1970], "app": String]` — one key so a record is one write.
        static let state = "shared.lockedOut.attempts"
        static let times = "times"
        static let app = "app"
    }

    // MARK: - Writing (shield configuration extension)

    /// Records one attempt to open a blocked app. `appName` is the localized display name when the
    /// shield has one (`Application.localizedDisplayName`, `WebDomain.domain`); `nil` keeps the
    /// previous name.
    public static func recordAttempt(appName: String?, at date: Date = .now) {
        recordAttempt(appName: appName, at: date, defaults: suite)
    }

    static func recordAttempt(appName: String?, at date: Date, defaults: UserDefaults) {
        let state = defaults.dictionary(forKey: Keys.state) ?? [:]
        let now = date.timeIntervalSince1970
        var times = (state[Keys.times] as? [Double] ?? []).filter { now - $0 < retention && $0 <= now }
        // A re-render of the same attempt only refreshes the name.
        if times.last.map({ now - $0 >= sameAttemptInterval }) ?? true {
            times.append(now)
        }
        var updated: [String: Any] = [Keys.times: times]
        if let name = appName ?? state[Keys.app] as? String {
            updated[Keys.app] = name
        }
        defaults.set(updated, forKey: Keys.state)
    }

    // MARK: - Reading (app)

    /// Attempts in the trailing hour (spec §5.16's window).
    public static func attemptsInLastHour(asOf date: Date = .now) -> Int {
        attemptsInLastHour(asOf: date, defaults: suite)
    }

    static func attemptsInLastHour(asOf date: Date, defaults: UserDefaults) -> Int {
        let now = date.timeIntervalSince1970
        return storedTimes(defaults).filter { now - $0 < window && $0 <= now }.count
    }

    /// `true` once the trailing hour holds ``threshold`` or more attempts.
    public static func hasReachedThreshold(asOf date: Date = .now) -> Bool {
        attemptsInLastHour(asOf: date) >= threshold
    }

    /// Display name of the most recent attempt's app, when it was within the trailing hour.
    public static func lastAttemptAppName(asOf date: Date = .now) -> String? {
        lastAttemptAppName(asOf: date, defaults: suite)
    }

    static func lastAttemptAppName(asOf date: Date, defaults: UserDefaults) -> String? {
        guard let last = storedTimes(defaults).last,
              date.timeIntervalSince1970 - last < window
        else { return nil }
        return defaults.dictionary(forKey: Keys.state)?[Keys.app] as? String
    }

    private static func storedTimes(_ defaults: UserDefaults) -> [Double] {
        defaults.dictionary(forKey: Keys.state)?[Keys.times] as? [Double] ?? []
    }
}
