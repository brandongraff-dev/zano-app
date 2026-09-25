// HealthPause.swift
// Core / Retention
//
// docs/spec.md §24 Safety: 'Include a "pause for health reasons" option and disordered-eating-safe
// copy.' A pause is a user-chosen break (sick, injured, or stepping back from anything around food
// or the body). While one is active:
//   - no new *scheduled* locks start (`HealthPause.isActive` — the scheduler / `LockEngineManager.
//     startLock` checks it; a lock the user starts by hand is still their choice),
//   - misses on paused days never count and paused days never widen a streak gap (`StreakEngine`
//     asks `wasPaused(on:)` / `pausedDayCount(strictlyBetween:and:)`),
//   - proactive nudges are suppressed (`NudgeSender`).
// Starting a pause while a lock is active releases it with `UnlockKind.manual` — never
// `.emergency`, so no streak penalty (see `startReleasingActiveLock(days:)`).
//
// State lives in the App Group's shared defaults (`SharedDefaults.healthPause*`) so the shield,
// monitor and widget extensions can read it with no SwiftData and no networking (spec §11, §27).
// Past pauses are kept as a short list of closed intervals so a late nightly job recording
// yesterday's miss still knows yesterday was paused.

import Foundation

public enum HealthPause {

    /// The longest timed pause the picker offers (2 weeks). "Until I turn it off" has no limit.
    public static let maxDays = 14

    /// The durations `PauseForHealthView` offers. `days == nil` means "until I turn it off".
    public enum Length: String, CaseIterable, Identifiable, Sendable {
        case threeDays
        case oneWeek
        case twoWeeks
        case untilTurnedOff

        public var id: String { rawValue }

        public var days: Int? {
            switch self {
            case .threeDays: 3
            case .oneWeek: 7
            case .twoWeeks: 14
            case .untilTurnedOff: nil
            }
        }
    }

    /// A closed past pause, `[start, end)`.
    public struct Interval: Codable, Equatable, Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        public func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// Keep the history short: it only has to cover the gaps `StreakEngine` ever looks back over.
    static let historyLimit = 50

    // MARK: - Reading

    /// `true` while a pause is in effect right now. Cheap (two defaults reads) and safe from any
    /// process — the extensions, `LockScheduler` and `LockEngineManager.startLock` call this.
    public static var isActive: Bool { isActive(at: .now) }

    public static func isActive(at date: Date) -> Bool {
        guard SharedDefaults.healthPauseActive, let startedAt = SharedDefaults.healthPauseStartedAt else {
            return false
        }
        guard date >= startedAt else { return false }
        if let endsAt = SharedDefaults.healthPauseEndsAt { return date < endsAt }
        return true
    }

    /// When the current pause started; `nil` when none is active.
    public static var startedAt: Date? {
        isActive ? SharedDefaults.healthPauseStartedAt : nil
    }

    /// When the current timed pause ends on its own. `nil` when no pause is active **or** the
    /// pause runs "until I turn it off" (check `isActive` / `isOpenEnded` to tell them apart).
    public static var endsAt: Date? {
        isActive ? SharedDefaults.healthPauseEndsAt : nil
    }

    /// `true` for an active pause with no end date ("until I turn it off").
    public static var isOpenEnded: Bool {
        isActive && SharedDefaults.healthPauseEndsAt == nil
    }

    /// Whether any part of `day`'s calendar day fell inside a pause — current or past. Generous
    /// on purpose: a pause started at 6 PM covers that whole day's miss.
    public static func wasPaused(on day: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return allIntervals(now: now).contains { $0.start < dayEnd && $0.end > dayStart }
    }

    /// How many calendar days strictly between `from` and `to` (both exclusive) were paused.
    /// `StreakEngine.recordEarnedUnlock` subtracts this from the day gap so a pause never breaks
    /// a streak.
    public static func pausedDayCount(
        strictlyBetween from: Date,
        and to: Date,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        guard var day = calendar.date(byAdding: .day, value: 1, to: start), day < end else { return 0 }
        let intervals = allIntervals(now: now)
        guard !intervals.isEmpty else { return 0 }
        var count = 0
        while day < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            if intervals.contains(where: { $0.start < next && $0.end > day }) { count += 1 }
            day = next
        }
        return count
    }

    // MARK: - Writing

    /// Starts (or replaces) a pause. `days == nil` means "until I turn it off"; otherwise clamped
    /// to `1...maxDays`. Does not touch locks — use `startReleasingActiveLock(days:)` from the UI.
    public static func start(days: Int?, now: Date = .now) {
        archiveCurrent(endingAt: now)
        SharedDefaults.healthPauseStartedAt = now
        if let days {
            let clamped = min(max(days, 1), maxDays)
            SharedDefaults.healthPauseEndsAt = now.addingTimeInterval(TimeInterval(clamped) * 86_400)
        } else {
            SharedDefaults.healthPauseEndsAt = nil
        }
        SharedDefaults.healthPauseActive = true
    }

    /// Ends the pause now ("Resume now"). Safe to call when none is active.
    public static func end(now: Date = .now) {
        archiveCurrent(endingAt: now)
        SharedDefaults.healthPauseActive = false
        SharedDefaults.healthPauseStartedAt = nil
        SharedDefaults.healthPauseEndsAt = nil
    }

    /// Starts a pause and, if a lock is in effect, releases it with `.manual` (no streak penalty —
    /// the penalty only exists on the emergency path in `EmergencyUnlock.swift`). The pause is
    /// recorded even if releasing the lock fails; the lock's own emergency unlock still works.
    /// - Returns: `true` if an active lock was released.
    @MainActor
    @discardableResult
    public static func startReleasingActiveLock(days: Int?) async -> Bool {
        start(days: days)
        guard let sessionID = SharedDefaults.activeLockSessionID else { return false }
        do {
            try await LockEngineManager.shared.endLock(sessionID: sessionID, unlockKind: .manual)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    /// The current pause (if the flag is set) as an interval, plus the archived history.
    private static func allIntervals(now: Date) -> [Interval] {
        var intervals = SharedDefaults.healthPauseHistory
        if SharedDefaults.healthPauseActive, let startedAt = SharedDefaults.healthPauseStartedAt {
            let end = SharedDefaults.healthPauseEndsAt ?? max(now, startedAt)
            if end > startedAt { intervals.append(Interval(start: startedAt, end: end)) }
        }
        return intervals
    }

    /// Moves the current pause (if any) into history, cut off at `endingAt` when it hadn't
    /// already expired on its own.
    private static func archiveCurrent(endingAt now: Date) {
        guard SharedDefaults.healthPauseActive, let startedAt = SharedDefaults.healthPauseStartedAt else { return }
        let plannedEnd = SharedDefaults.healthPauseEndsAt ?? now
        let end = min(plannedEnd, now)
        guard end > startedAt else { return }
        var history = SharedDefaults.healthPauseHistory
        history.append(Interval(start: startedAt, end: end))
        SharedDefaults.healthPauseHistory = Array(history.suffix(historyLimit))
    }
}
