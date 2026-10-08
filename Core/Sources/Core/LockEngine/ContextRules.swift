// ContextRules.swift
// Core / LockEngine
//
// Smart unlock rules (session 19, 2026-10-05; docs/spec.md §5.26): "keep my work apps open from 9 to
// 5 on weekdays, even while a lock is running." A rule names a lock set (the apps to keep open) and a
// weekly window. While a rule is active those apps are taken out of every shield ZANO applies.
//
// How it is wired: `ManagedSettingsStore.applyZanoShield` is the one place the app and the
// `ZANOMonitor` extension both shield apps, so it subtracts the active rules' apps there and both
// honour them. DeviceActivity daily schedules wake the monitor when a rule starts or ends so a lock
// that is already running is re-applied then (`ScheduledLockMonitor.contextRulesBoundary`).
//
// What this can't do (iOS): ManagedSettings works per app, category and web domain. It can't allow one
// contact in Messages or one chat in an app, only the app as a whole.
//
// Rules only ever loosen a lock; they never add apps to one, never end a lock, and never touch the
// emergency unlock. Three rules at most, to stay inside Apple's cap on monitored activities
// (believed 20, UNVERIFIED).

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import os

// MARK: - Rule

public struct ContextRule: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// The lock set whose apps stay open while the rule is active.
    public var lockSetID: UUID
    /// `Calendar` numbering: 1 = Sunday ... 7 = Saturday.
    public var weekdays: Set<Int>
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isEnabled: Bool

    public static let minimumWindowMinutes = LockSchedule.minimumWindowMinutes
    public static let maxRules = 3
    public static let workdays: Set<Int> = [2, 3, 4, 5, 6]

    public init(
        id: UUID = UUID(), name: String, lockSetID: UUID, weekdays: Set<Int> = ContextRule.workdays,
        startMinuteOfDay: Int = 9 * 60, endMinuteOfDay: Int = 17 * 60, isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.lockSetID = lockSetID
        self.weekdays = weekdays
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.isEnabled = isEnabled
    }

    /// A rule needs a weekday, times inside one day, and a window of at least 15 minutes (a
    /// DeviceActivity interval can't be shorter, spec §27).
    public var isValid: Bool {
        !weekdays.isEmpty
            && weekdays.isSubset(of: LockSchedule.allWeekdays)
            && (0..<LockSchedule.minutesPerDay).contains(startMinuteOfDay)
            && (0...LockSchedule.endOfDayMinute).contains(endMinuteOfDay)
            && endMinuteOfDay - startMinuteOfDay >= Self.minimumWindowMinutes
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, isValid, weekdays.contains(calendar.component(.weekday, from: date)) else { return false }
        let minute = LockSchedule.minuteOfDay(date, calendar: calendar)
        return minute >= startMinuteOfDay && minute < endMinuteOfDay
    }
}

// MARK: - Store

public enum ContextRuleStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let key = "contextRules.rules.v1"

    public static var rules: [ContextRule] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([ContextRule].self, from: data)) ?? []
        }
        set {
            let limited = Array(newValue.prefix(ContextRule.maxRules))
            if let data = try? JSONEncoder().encode(limited) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}

// MARK: - Active exemptions

/// The apps, categories and web domains kept open right now. Not `Sendable`: Apple's token sets aren't.
public struct ContextExemptTokens {
    public var applications: Set<ApplicationToken> = []
    public var categories: Set<ActivityCategoryToken> = []
    public var webDomains: Set<WebDomainToken> = []

    public var isEmpty: Bool { applications.isEmpty && categories.isEmpty && webDomains.isEmpty }
}

public enum ContextRules {
    /// Everything the rules active at `now` keep open. Reads the lock sets' mirrored selections from the
    /// App Group, so it is safe inside the monitor extension (no SwiftData).
    public static func exemptTokens(now: Date, calendar: Calendar = .current) -> ContextExemptTokens {
        var result = ContextExemptTokens()
        for rule in ContextRuleStore.rules where rule.isActive(at: now, calendar: calendar) {
            guard let blob = LockEngineSharedState.lockSetSelectionData(for: rule.lockSetID),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
            else { continue }
            result.applications.formUnion(selection.applicationTokens)
            result.categories.formUnion(selection.categoryTokens)
            result.webDomains.formUnion(selection.webDomainTokens)
        }
        return result
    }
}

// MARK: - Learning: a rule worth suggesting

/// Spots a habit in how the person ends locks early, and offers a rule that would make that unnecessary.
/// Pure, so it is unit-tested.
///
/// Three emergency unlocks on the same weekday inside a two-hour span, within the last six weeks,
/// suggest "keep some apps open on that weekday around then". It only ever suggests: the person
/// chooses which apps, and nothing changes until they save.
public struct ContextRuleSuggestion: Sendable, Equatable {
    public var weekday: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var occurrences: Int
}

public enum ContextRuleSuggester {
    public static let minOccurrences = 3
    public static let lookbackDays = 42
    public static let spanMinutes = 120

    public static func suggestion(emergencyUnlockTimes: [Date], now: Date, calendar: Calendar = .current) -> ContextRuleSuggestion? {
        let since = now.addingTimeInterval(-TimeInterval(lookbackDays * 86_400))
        let recent = emergencyUnlockTimes.filter { $0 >= since && $0 <= now }
        var byWeekday: [Int: [Int]] = [:]
        for time in recent {
            byWeekday[calendar.component(.weekday, from: time), default: []].append(LockSchedule.minuteOfDay(time, calendar: calendar))
        }
        var best: ContextRuleSuggestion?
        for (weekday, minutes) in byWeekday {
            let sorted = minutes.sorted()
            // The biggest group of unlocks that fit inside one two-hour span.
            for (index, first) in sorted.enumerated() {
                let group = sorted[index...].filter { $0 - first <= spanMinutes }
                guard group.count >= minOccurrences, group.count > (best?.occurrences ?? 0) else { continue }
                let start = (first / 60) * 60
                let end = min(LockSchedule.endOfDayMinute, max(start + 60, ((group.last ?? first) / 60 + 1) * 60))
                best = ContextRuleSuggestion(weekday: weekday, startMinuteOfDay: start, endMinuteOfDay: end, occurrences: group.count)
            }
        }
        return best
    }
}

// MARK: - DeviceActivity wake-ups

public enum ContextRuleActivity {
    public static let prefix = "com.zano.app.context."

    public static func rawName(ruleID: UUID) -> String { prefix + ruleID.uuidString }
    public static func isContextActivity(_ raw: String) -> Bool { raw.hasPrefix(prefix) }
}

/// Registers one daily DeviceActivity window per enabled rule, so the monitor wakes when a rule starts
/// or ends and can re-apply a lock that is already running.
@MainActor
public final class ContextRuleScheduler {
    public static let shared = ContextRuleScheduler()

    private let activityCenter: DeviceActivityCenter
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "ContextRuleScheduler")

    init(activityCenter: DeviceActivityCenter = DeviceActivityCenter()) {
        self.activityCenter = activityCenter
    }

    /// Saves `rules` and registers their windows. Rules apply to the next shield straight away.
    public func save(_ rules: [ContextRule]) {
        ContextRuleStore.rules = rules.filter(\.isValid)
        sync()
        reapplyRunningLock()
    }

    public func sync() {
        let existing = activityCenter.activities.filter { ContextRuleActivity.isContextActivity($0.rawValue) }
        if !existing.isEmpty { activityCenter.stopMonitoring(existing) }
        for rule in ContextRuleStore.rules where rule.isEnabled && rule.isValid {
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: rule.startMinuteOfDay / 60, minute: rule.startMinuteOfDay % 60),
                intervalEnd: DateComponents(hour: rule.endMinuteOfDay / 60, minute: rule.endMinuteOfDay % 60, second: rule.endMinuteOfDay == LockSchedule.endOfDayMinute ? 59 : 0),
                repeats: true
            )
            do {
                try activityCenter.startMonitoring(DeviceActivityName(ContextRuleActivity.rawName(ruleID: rule.id)), during: schedule)
            } catch {
                logger.error("Registering a context rule failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A rule that starts "now" should free its apps now, not at the next boundary.
    private func reapplyRunningLock() {
        LockEngineManager.shared.reapplyIntendedShield()
    }
}
