// Core/Sources/Core/LockEngine/TimeBankGlance.swift
//
// The Time Bank widget's numbers (session 35, docs/spec.md §5.2 Earn Rate, §6 widgets): today's
// balance, what was earned and spent, whether apps are locked, and the next goal that would add
// minutes. Pure value logic so it can be unit tested in CoreTests; the widget extension builds one
// from its App Group snapshot (`ZANOWidgetSnapshot`), never from SwiftData writes or the network.
//
// No daily cap: spec §5.2 defines earn rates and midnight expiry ("no hoarding") but no maximum
// balance, so there is deliberately no cap field here.

import Foundation

public struct TimeBankGlance: Sendable, Equatable {
    /// The unfinished goal that would deposit the most minutes if verified now.
    public struct NextEarn: Sendable, Equatable {
        public let title: String
        public let minutes: Int

        public init(title: String, minutes: Int) {
            self.title = title
            self.minutes = minutes
        }
    }

    /// One of today's active goals, as the widget sees it.
    public struct Candidate: Sendable, Equatable {
        public let title: String
        public let goalType: GoalType
        public let isDoneToday: Bool

        public init(title: String, goalType: GoalType, isDoneToday: Bool) {
            self.title = title
            self.goalType = goalType
            self.isDoneToday = isDoneToday
        }
    }

    /// Minutes still to spend today.
    public let balanceMinutes: Int
    public let earnedTodayMinutes: Int
    public let spentTodayMinutes: Int
    public let isLocked: Bool
    public let nextEarn: NextEarn?

    /// Normalizes the App Group mirrors into a consistent set of numbers:
    /// - nothing negative;
    /// - a stale mirror (written before today's midnight) reads as an empty bank, since minutes
    ///   expire at midnight (spec §5.2);
    /// - a store written before session 35 has a balance but no earned/spent mirrors (they read 0),
    ///   so earned is raised to at least `balance + spent` instead of showing "earned 0, 35 left".
    public init(
        balanceMinutes: Int,
        earnedTodayMinutes: Int,
        spentTodayMinutes: Int,
        mirrorIsForToday: Bool = true,
        isLocked: Bool,
        nextEarn: NextEarn?
    ) {
        let balance = mirrorIsForToday ? max(balanceMinutes, 0) : 0
        let spent = mirrorIsForToday ? max(spentTodayMinutes, 0) : 0
        let earned = mirrorIsForToday ? max(earnedTodayMinutes, 0) : 0
        self.balanceMinutes = balance
        self.spentTodayMinutes = spent
        self.earnedTodayMinutes = max(earned, balance + spent)
        self.isLocked = isLocked
        self.nextEarn = nextEarn
    }

    /// `0...1`: how much of today's earnings is still in the bank (the draining bar). Empty when
    /// nothing has been earned.
    public var fractionLeft: Double {
        guard earnedTodayMinutes > 0 else { return 0 }
        return min(max(Double(balanceMinutes) / Double(earnedTodayMinutes), 0), 1)
    }

    /// `true` while apps are locked and there are minutes to spend on a break.
    public var canSpend: Bool { isLocked && balanceMinutes > 0 }

    /// The unfinished goal with the biggest Earn Mode payoff (`TimeBankEarnRates`), first in
    /// `candidates` order on a tie. `nil` when every goal with a rate is done (or none has one).
    public static func nextEarn(from candidates: [Candidate]) -> NextEarn? {
        var best: NextEarn?
        for candidate in candidates where !candidate.isDoneToday {
            guard let minutes = TimeBankEarnRates.minutes(for: candidate.goalType), minutes > 0 else { continue }
            if best == nil || minutes > (best?.minutes ?? 0) {
                best = NextEarn(title: candidate.title, minutes: minutes)
            }
        }
        return best
    }
}
