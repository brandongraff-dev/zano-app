// Core/Tests/CoreTests/TimeBankWidgetTests.swift
//
// Session 35 (Time Bank widget): the pure pieces behind the widget. `TimeBankGlance`
// (Core/Sources/Core/LockEngine/TimeBankGlance.swift) normalizes the App Group mirrors and picks
// the next goal that earns minutes; `WidgetCopy`'s Time Bank strings and the two new
// `SharedDefaults` mirrors. The widget views themselves live in the extension and need a
// Simulator/device Home Screen to check.

import Foundation
import Testing
@testable import Core

@Suite("TimeBankGlance")
struct TimeBankGlanceTests {
    @Test("passes consistent mirrors through unchanged")
    func consistentMirrors() {
        let bank = TimeBankGlance(balanceMinutes: 35, earnedTodayMinutes: 60, spentTodayMinutes: 25, isLocked: true, nextEarn: nil)
        #expect(bank.balanceMinutes == 35)
        #expect(bank.earnedTodayMinutes == 60)
        #expect(bank.spentTodayMinutes == 25)
    }

    @Test("a stale mirror (from before midnight) reads as an empty bank")
    func staleMirrorIsEmpty() {
        let bank = TimeBankGlance(
            balanceMinutes: 35, earnedTodayMinutes: 60, spentTodayMinutes: 25,
            mirrorIsForToday: false, isLocked: true, nextEarn: nil
        )
        #expect(bank.balanceMinutes == 0)
        #expect(bank.earnedTodayMinutes == 0)
        #expect(bank.spentTodayMinutes == 0)
        #expect(bank.fractionLeft == 0)
        #expect(!bank.canSpend)
    }

    @Test("a pre-session-35 store (balance but no earned/spent mirrors) shows earned = balance")
    func missingEarnedMirrorIsRaisedToBalance() {
        let bank = TimeBankGlance(balanceMinutes: 35, earnedTodayMinutes: 0, spentTodayMinutes: 0, isLocked: false, nextEarn: nil)
        #expect(bank.earnedTodayMinutes == 35)
        #expect(bank.fractionLeft == 1)
    }

    @Test("negative mirror values clamp to zero")
    func negativesClamp() {
        let bank = TimeBankGlance(balanceMinutes: -5, earnedTodayMinutes: -1, spentTodayMinutes: -3, isLocked: false, nextEarn: nil)
        #expect(bank.balanceMinutes == 0)
        #expect(bank.earnedTodayMinutes == 0)
        #expect(bank.spentTodayMinutes == 0)
    }

    @Test("fractionLeft is balance over earned, and 0 when nothing was earned")
    func fractionLeft() {
        let half = TimeBankGlance(balanceMinutes: 45, earnedTodayMinutes: 90, spentTodayMinutes: 45, isLocked: true, nextEarn: nil)
        #expect(half.fractionLeft == 0.5)
        let empty = TimeBankGlance(balanceMinutes: 0, earnedTodayMinutes: 0, spentTodayMinutes: 0, isLocked: true, nextEarn: nil)
        #expect(empty.fractionLeft == 0)
    }

    @Test("canSpend needs both a lock and minutes in the bank")
    func canSpend() {
        #expect(TimeBankGlance(balanceMinutes: 10, earnedTodayMinutes: 10, spentTodayMinutes: 0, isLocked: true, nextEarn: nil).canSpend)
        #expect(!TimeBankGlance(balanceMinutes: 10, earnedTodayMinutes: 10, spentTodayMinutes: 0, isLocked: false, nextEarn: nil).canSpend)
        #expect(!TimeBankGlance(balanceMinutes: 0, earnedTodayMinutes: 10, spentTodayMinutes: 10, isLocked: true, nextEarn: nil).canSpend)
    }

    @Test("nextEarn picks the unfinished goal with the biggest payoff")
    func nextEarnPicksBiggestUnfinished() {
        let next = TimeBankGlance.nextEarn(from: [
            TimeBankGlance.Candidate(title: "Protein", goalType: .protein, isDoneToday: false),
            TimeBankGlance.Candidate(title: "Gym", goalType: .workoutGym, isDoneToday: false),
            TimeBankGlance.Candidate(title: "Focus", goalType: .focusSession, isDoneToday: false)
        ])
        #expect(next == TimeBankGlance.NextEarn(title: "Gym", minutes: TimeBankEarnRates.gymSessionMinutes))
    }

    @Test("nextEarn skips finished goals and goals without an earn rate; ties go to the first")
    func nextEarnSkipsDoneAndUnrated() {
        let next = TimeBankGlance.nextEarn(from: [
            TimeBankGlance.Candidate(title: "Gym", goalType: .workoutGym, isDoneToday: true),
            TimeBankGlance.Candidate(title: "Water", goalType: .water, isDoneToday: false),
            TimeBankGlance.Candidate(title: "Focus", goalType: .focusSession, isDoneToday: false),
            TimeBankGlance.Candidate(title: "Protein", goalType: .protein, isDoneToday: false)
        ])
        #expect(next == TimeBankGlance.NextEarn(title: "Focus", minutes: TimeBankEarnRates.focusBlockMinutes))
    }

    @Test("nextEarn is nil when nothing is left to earn")
    func nextEarnNil() {
        #expect(TimeBankGlance.nextEarn(from: []) == nil)
        #expect(TimeBankGlance.nextEarn(from: [TimeBankGlance.Candidate(title: "Water", goalType: .water, isDoneToday: false)]) == nil)
        #expect(TimeBankGlance.nextEarn(from: [TimeBankGlance.Candidate(title: "Gym", goalType: .workoutGym, isDoneToday: true)]) == nil)
    }
}

@Suite("WidgetCopy — Time Bank")
struct TimeBankWidgetCopyTests {
    @Test("unit says earned until something is spent, then left")
    func unit() {
        #expect(WidgetCopy.timeBankUnit(spentMinutes: 0) == "min earned")
        #expect(WidgetCopy.timeBankUnit(spentMinutes: 5) == "min left")
    }

    @Test("accessibility reads in words")
    func accessibility() {
        #expect(WidgetCopy.timeBankAccessibility(balance: 20, earned: 20, spent: 0) == "20 minutes earned")
        #expect(WidgetCopy.timeBankAccessibility(balance: 1, earned: 1, spent: 0) == "1 minute earned")
        #expect(WidgetCopy.timeBankAccessibility(balance: 0, earned: 0, spent: 0) == "No minutes earned yet")
        #expect(WidgetCopy.timeBankAccessibility(balance: 35, earned: 60, spent: 25)
            == "35 minutes left, 60 earned and 25 spent today")
    }

    @Test("lines and hints")
    func lines() {
        #expect(WidgetCopy.timeBankEarnedSpent(earned: 60, spent: 25) == "Earned 60 · spent 25")
        #expect(WidgetCopy.timeBankEarnedSpent(earned: 60, spent: 0) == "Earned 60")
        #expect(WidgetCopy.timeBankNextEarn(title: "Gym", minutes: 90) == "Gym +90 min")
        #expect(WidgetCopy.timeBankHeadline(balance: 35) == "Time Bank · 35 min")
        #expect(WidgetCopy.timeBankInline(balance: 20, spent: 0) == "20 min earned")
        #expect(WidgetCopy.timeBankInline(balance: 20, spent: 10) == "20 min left")
    }
}

@Suite("SharedDefaults — Time Bank widget mirrors")
struct TimeBankWidgetMirrorTests {
    @Test("earned/spent today round-trip")
    func roundTrip() {
        let earned = SharedDefaults.timeBankEarnedToday
        let spent = SharedDefaults.timeBankSpentToday
        defer {
            SharedDefaults.timeBankEarnedToday = earned
            SharedDefaults.timeBankSpentToday = spent
        }
        SharedDefaults.timeBankEarnedToday = 120
        SharedDefaults.timeBankSpentToday = 15
        #expect(SharedDefaults.timeBankEarnedToday == 120)
        #expect(SharedDefaults.timeBankSpentToday == 15)
    }
}
