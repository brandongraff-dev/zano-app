// BreakCoach.swift
// Core / Focus
//
// Session 25 (docs/spec.md §5.29): after a verified focus block, a short, kind nudge to rest. Pomodoro
// shape: a 25-minute block earns 5 minutes, a 50-minute block 10, a 90-minute block 15, and every
// fourth block of the day a long 15. What to do in the break rotates through things that help
// (water, stretch, look far away, a short walk). It only ever suggests rest; it never locks, delays
// or blocks anything, and nothing here is a goal.

import Foundation

public enum BreakActivity: String, CaseIterable, Sendable {
    case water, stretch, lookAway, walk
}

public struct BreakSuggestion: Equatable, Sendable {
    public let minutes: Int
    public let activity: BreakActivity
    /// True for the longer break after every fourth block.
    public let isLong: Bool
    /// When the break suggestion stops being shown.
    public let expiresAt: Date
}

public enum BreakCoach {
    /// How long after a block ends the suggestion is shown.
    public static let showWindow: TimeInterval = 15 * 60
    public static let blocksPerLongBreak = 4

    /// A finished, verified focus block.
    public struct Block: Equatable, Sendable {
        public let endedAt: Date
        public let minutes: Double
        public init(endedAt: Date, minutes: Double) {
            self.endedAt = endedAt
            self.minutes = minutes
        }
    }

    /// The suggestion for `blocks` finished today (any order), or `nil` when the latest ended more
    /// than `showWindow` ago, is later than `now`, or a block is running (`isFocusing`).
    public static func suggestion(blocks: [Block], isFocusing: Bool, now: Date, calendar: Calendar = .current) -> BreakSuggestion? {
        guard !isFocusing else { return nil }
        let today = blocks.filter { calendar.isDate($0.endedAt, inSameDayAs: now) && $0.endedAt <= now }
        guard let last = today.max(by: { $0.endedAt < $1.endedAt }),
              now.timeIntervalSince(last.endedAt) <= showWindow
        else { return nil }

        let count = today.count
        let isLong = count % blocksPerLongBreak == 0
        let base: Int
        switch last.minutes {
        case ..<40: base = 5
        case ..<75: base = 10
        default: base = 15
        }
        let activities = BreakActivity.allCases
        return BreakSuggestion(
            minutes: isLong ? max(base, 15) : base,
            activity: activities[(count - 1) % activities.count],
            isLong: isLong,
            expiresAt: last.endedAt.addingTimeInterval(showWindow)
        )
    }
}
