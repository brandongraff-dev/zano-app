// TrialSummary.swift
// Core / Monetization
//
// "What your trial earned you" (growth research #5, 2026-10-02): two days before the trial's first
// charge, the reminder notification and an in-app card show the user's own numbers from the trial —
// earned unlocks, gym visits, hours locked in, best streak. Hard paywalls refund more; a concrete
// record of what the week was worth is the honest counterweight (no countdowns, no guilt, spec §21).
//
// Built from the same plain-value snapshot the milestone engine uses (`MilestoneSnapshot`,
// `Retention/Milestones.swift`), so the numbers always agree with the milestone cards. The pure
// `make(...)` is what the tests exercise; `current(...)` reads the store.

import Foundation

public struct TrialSummary: Sendable, Equatable {
    /// Locks that ended `.earned` inside the window.
    public let earnedUnlocks: Int
    /// Distinct days with a verified gym goal inside the window.
    public let gymVisits: Int
    /// Whole hours apps were locked inside the window (overlaps merged, clipped to the window).
    public let hoursLockedIn: Int
    /// Longest run of consecutive days with an earned unlock inside the window.
    public let bestStreak: Int

    public init(earnedUnlocks: Int, gymVisits: Int, hoursLockedIn: Int, bestStreak: Int) {
        self.earnedUnlocks = earnedUnlocks
        self.gymVisits = gymVisits
        self.hoursLockedIn = hoursLockedIn
        self.bestStreak = bestStreak
    }

    /// Nothing earned yet. The card and notification then offer the smallest next step instead of
    /// a row of zeros (spec §8: never show an empty scoreboard).
    public var hasWins: Bool {
        earnedUnlocks > 0 || gymVisits > 0 || hoursLockedIn > 0
    }

    public static let empty = TrialSummary(earnedUnlocks: 0, gymVisits: 0, hoursLockedIn: 0, bestStreak: 0)

    /// The summary of `snapshot` between `since` and `now`.
    public nonisolated static func make(
        snapshot: MilestoneSnapshot,
        since: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> TrialSummary {
        guard now > since else { return .empty }
        let window = DateInterval(start: since, end: now)
        let earned = snapshot.earnedUnlockDates.filter { window.contains($0) }
        let gymDays = Set(snapshot.gymCompletionDates.filter { window.contains($0) }.map { calendar.startOfDay(for: $0) })
        let clipped = snapshot.lockIntervals.compactMap { $0.intersection(with: window) }
        let hours = Int(MilestoneEngine.lockedSeconds(clipped) / 3600)
        return TrialSummary(
            earnedUnlocks: earned.count,
            gymVisits: gymDays.count,
            hoursLockedIn: hours,
            bestStreak: MilestoneEngine.longestRun(of: earned, calendar: calendar)
        )
    }

    /// The summary of the local store between `since` and `now`.
    @MainActor
    public static func current(since: Date, now: Date = .now) -> TrialSummary {
        let snapshot = MilestoneEngine.shared.makeSnapshot(now: now, includeAllGoalEvents: true)
        return make(snapshot: snapshot, since: since, now: now)
    }
}
