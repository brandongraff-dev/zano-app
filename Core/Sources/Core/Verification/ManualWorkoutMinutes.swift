// ManualWorkoutMinutes.swift
// Core / Verification
//
// Session 42 (log workout minutes by hand). docs/spec.md §3: both workout rows also accept minutes
// typed in by hand as Tier C ("honesty + friction": a hold to confirm), so a workout goal never needs a
// saved gym, location, Apple Health or Strava. §9.8: an entry by hand is shown as "logged by hand",
// never questioned.
//
// The rule, kept pure so `ManualWorkoutMinutesTests` covers it:
//   - Tracked workouts (Apple Health + the Strava link) are merged with `WorkoutDedupe.merge`, so one
//     workout that arrived twice counts once.
//   - With no minutes by hand, nothing changes: one tracked workout has to reach the target on its own
//     (the Tier A rule `HomeWorkoutQueryState.checkToday` already applies).
//   - Once any minutes are logged by hand, the day's total counts: every deduped tracked workout plus
//     every entry by hand. Entries add up across the day and have no daily cap (unlike the gym's one
//     honor check-in a day, which stays as it is).
//
// How an entry is stored: a verified `.log` `GoalEvent` with `source: .manual` (or `.siri`/`.widget`
// when it came from there), `value: nil`, and the minutes in `meta["loggedMinutes"]` with
// `meta["tier"] = "C"`. `value` stays nil on purpose: workout goals store a weekly count as their
// target ("3 workouts"), and `GoalDayProgress` would add minutes to that count and call 5 minutes done.
// When the day's total reaches the target, `HomeWorkoutQueryState` writes one verified `.complete` with
// `source: .manual`, `meta["tier"] = "C"` and `meta["manualMinutesTotal"]`.

import Foundation

public enum ManualWorkoutMinutes {
    /// Quick picks on the "Log minutes" sheet.
    public static let quickPicks = [15, 20, 30, 45, 60]
    /// The stepper's step, and the rounding for the suggested amount.
    public static let step = 5
    /// One entry's bounds. A long day is logged as more than one entry.
    public static let range = 5...240

    /// `meta` key holding one entry's minutes.
    public static let loggedMinutesMetaKey = "loggedMinutes"
    /// `meta` key on the completion written from the day's total (marks it as minutes by hand).
    public static let totalMetaKey = "manualMinutesTotal"

    /// Clamps a picked amount to `range`.
    public static func clamped(_ minutes: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, minutes))
    }

    /// Whether `event` is one counted entry of minutes logged by hand.
    public static func isEntry(_ event: GoalEvent) -> Bool {
        entryMinutes(event) != nil
    }

    /// The minutes of one counted entry, else `nil`.
    public static func entryMinutes(_ event: GoalEvent) -> Int? {
        guard event.verified, event.kind == .log, case .object(let fields) = event.meta,
              case .number(let minutes)? = fields[loggedMinutesMetaKey], minutes > 0
        else { return nil }
        return Int(minutes.rounded())
    }

    /// Whether `event` is a completion written from minutes logged by hand.
    public static func isCompletion(_ event: GoalEvent) -> Bool {
        completionTotalMinutes(event) != nil
    }

    /// The day's total minutes recorded on a completion written from minutes by hand, else `nil`.
    public static func completionTotalMinutes(_ event: GoalEvent) -> Int? {
        guard event.kind == .complete, case .object(let fields) = event.meta,
              case .number(let total)? = fields[totalMetaKey]
        else { return nil }
        return Int(total.rounded())
    }

    /// Today's minutes by hand, from the goal's events for the day (callers filter goal and day).
    public static func loggedMinutes(in events: [GoalEvent]) -> Int {
        events.compactMap(entryMinutes).reduce(0, +)
    }

    /// Tracked minutes (Health + Strava, deduped), longest single workout and the sum.
    public struct Tracked: Sendable, Equatable {
        public let longestMinutes: Int
        public let totalMinutes: Int

        public init(longestMinutes: Int, totalMinutes: Int) {
            let longest = max(0, longestMinutes)
            self.longestMinutes = longest
            self.totalMinutes = max(longest, totalMinutes)
        }

        public static let zero = Tracked(longestMinutes: 0, totalMinutes: 0)

        /// Merges Health and Strava with `WorkoutDedupe` (Health wins), then measures.
        public init(health: [WorkoutCandidate], strava: [WorkoutCandidate]) {
            let merged = WorkoutDedupe.merge(health: health, strava: strava)
            let longest = merged.map(\.activeSeconds).max() ?? 0
            let total = merged.map(\.activeSeconds).reduce(0, +)
            self.init(longestMinutes: Int(longest / 60), totalMinutes: Int(total / 60))
        }
    }

    /// The day's workout minutes as the goal sees them: the longest tracked workout while nothing was
    /// logged by hand (the single-workout rule), else every tracked minute plus every minute by hand.
    public static func progressMinutes(tracked: Tracked, manualMinutes: Int) -> Int {
        manualMinutes > 0 ? tracked.totalMinutes + manualMinutes : tracked.longestMinutes
    }

    /// Whether minutes by hand (with whatever was tracked) complete the goal. `false` with no minutes
    /// by hand: then the Tier A path decides, unchanged.
    public static func completesWithManual(tracked: Tracked, manualMinutes: Int, requiredMinutes: Int) -> Bool {
        manualMinutes > 0 && tracked.totalMinutes + manualMinutes >= max(1, requiredMinutes)
    }

    /// The sheet's starting amount: what's left of the target, rounded up to `step`, inside `range`.
    /// Nothing left (or no target) starts at 30.
    public static func suggestedMinutes(requiredMinutes: Int, progressMinutes: Int) -> Int {
        let left = requiredMinutes - progressMinutes
        guard left > 0 else { return 30 }
        let rounded = ((left + step - 1) / step) * step
        return clamped(rounded)
    }
}

/// Result of `HomeWorkoutVerifier.logManualMinutes(goalID:minutes:source:)`.
public enum ManualWorkoutLogResult: Sendable, Equatable {
    /// Logged; today's total is `totalMinutes` of `requiredMinutes`, not there yet.
    case logged(totalMinutes: Int, requiredMinutes: Int)
    /// Logged, and today's total reached the target: the goal is done.
    case completed(totalMinutes: Int)
    /// Logged on a day the goal was already done (the minutes still show in today's total).
    case loggedAfterDone(totalMinutes: Int)
}
