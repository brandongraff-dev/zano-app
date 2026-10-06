// Core/Tests/CoreTests/MindfulPassTests.swift
//
// docs/spec.md §5.23. `MindfulPass` is pure computation (no FamilyControls/ManagedSettings), so
// every test here is a plain value test.

import Foundation
import Testing
@testable import Core

@Suite("MindfulPass")
struct MindfulPassTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func firstPassUsesBasePauseAndFullCap() {
        let decision = MindfulPass.evaluate(grantsToday: 0)
        #expect(decision == .granted(pauseSeconds: 10, passMinutes: 15, passesLeftAfter: 4))
    }

    @Test func pauseEscalatesWithEachPassUsedToday() {
        #expect(MindfulPass.evaluate(grantsToday: 1) == .granted(pauseSeconds: 15, passMinutes: 15, passesLeftAfter: 3))
        #expect(MindfulPass.evaluate(grantsToday: 2) == .granted(pauseSeconds: 20, passMinutes: 15, passesLeftAfter: 2))
        #expect(MindfulPass.evaluate(grantsToday: 4) == .granted(pauseSeconds: 30, passMinutes: 15, passesLeftAfter: 0))
    }

    @Test func capReachedAtAndAboveCap() {
        #expect(MindfulPass.evaluate(grantsToday: 5) == .capReached)
        #expect(MindfulPass.evaluate(grantsToday: 99) == .capReached)
    }

    @Test func pauseNeverExceedsMax() {
        let policy = MindfulPassPolicy(dailyPassCap: 20, basePauseSeconds: 10, pauseStepSeconds: 20, maxPauseSeconds: 45)
        #expect(MindfulPass.evaluate(policy: policy, grantsToday: 10)
            == .granted(pauseSeconds: 45, passMinutes: 15, passesLeftAfter: 9))
    }

    @Test func negativeGrantCountIsTreatedAsZero() {
        #expect(MindfulPass.evaluate(grantsToday: -3) == MindfulPass.evaluate(grantsToday: 0))
    }

    @Test func zeroCapMeansNoPassesEver() {
        let policy = MindfulPassPolicy(dailyPassCap: 0)
        #expect(MindfulPass.evaluate(policy: policy, grantsToday: 0) == .capReached)
    }

    @Test func grantsTodayCountsOnlySameCalendarDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let earlierToday = now.addingTimeInterval(-60)
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(MindfulPass.grantsToday(in: [earlierToday, yesterday, now], now: now, calendar: calendar) == 2)
    }

    @Test func prunedToTodayDropsOlderGrants() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(MindfulPass.prunedToToday([yesterday, now], now: now, calendar: calendar) == [now])
    }
}
