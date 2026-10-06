// GamificationTests.swift
// Core / Tests / CoreTests
//
// The weekly Scroll Monster (damage, adaptive target, states, art) and perfect days (recording once,
// the run of consecutive days). Founder-approved gamification, 2026-10-04.

import Testing
import Foundation
@testable import Core

@Suite("Gamification — Scroll Monster and perfect days")
struct GamificationTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    // MARK: Scroll Monster

    @Test func damageIsLockedMinutesPlusGoalHits() {
        let week = ScrollMonster.week(containing: date(7), calendar: calendar) // Mon 5 ... Mon 12
        let locked = [
            DateInterval(start: date(6, 9), duration: 2 * 3600),          // 120 min
            DateInterval(start: date(6, 10), duration: 2 * 3600),         // overlaps: +60 min
            DateInterval(start: date(4, 23), duration: 2 * 3600),         // 60 min fall inside (from Mon 00:00)
        ]
        let goals = [date(6), date(8), date(1)]                           // last one is outside the week
        let damage = ScrollMonster.damage(locked: locked, goalCompletions: goals, in: week)
        #expect(damage == 120 + 60 + 60 + 2 * ScrollMonster.goalHit)
    }

    @Test func targetAdaptsWithinBounds() {
        #expect(ScrollMonster.target(lastWeekDamage: nil) == ScrollMonster.defaultTarget)
        #expect(ScrollMonster.target(lastWeekDamage: 0) == ScrollMonster.defaultTarget)
        #expect(ScrollMonster.target(lastWeekDamage: 100) == ScrollMonster.minimumTarget)
        #expect(ScrollMonster.target(lastWeekDamage: 1000) == 1100)
        #expect(ScrollMonster.target(lastWeekDamage: 9000) == ScrollMonster.maximumTarget)
    }

    @Test func stateFollowsHealth() {
        let interval = DateInterval(start: date(5), duration: 7 * 86_400)
        #expect(ScrollMonster.Week(interval: interval, target: 600, damage: 100, daysLeft: 5, variant: 0).state == .healthy)
        #expect(ScrollMonster.Week(interval: interval, target: 600, damage: 300, daysLeft: 5, variant: 0).state == .hurt)
        let beaten = ScrollMonster.Week(interval: interval, target: 600, damage: 650, daysLeft: 2, variant: 0)
        #expect(beaten.state == .defeated)
        #expect(beaten.hp == 0)
        #expect(beaten.isDefeated)
    }

    @Test func daysLeftCountsToday() {
        let week = ScrollMonster.week(containing: date(7), calendar: calendar)
        #expect(ScrollMonster.daysLeft(in: week, now: date(5), calendar: calendar) == 7)
        #expect(ScrollMonster.daysLeft(in: week, now: date(11), calendar: calendar) == 1)
    }

    @Test(arguments: ScrollMonster.State.allCases)
    func everyMonsterIsDrawn(_ state: ScrollMonster.State) {
        for variant in 0..<3 {
            let pixels = ScrollMonster.pixels(state, variant: variant)
            #expect(pixels.rows.count == BuddyPixels.size)
            #expect(pixels.cgImage() != nil)
        }
    }

    // MARK: Perfect days

    @Test func perfectDaysRecordOnceAndRun() throws {
        let defaults = try #require(UserDefaults(suiteName: "GamificationTests.\(UUID().uuidString)"))
        #expect(PerfectDay.streak(asOf: date(10), defaults: defaults, calendar: calendar) == 0)
        #expect(PerfectDay.record(date(8), defaults: defaults, calendar: calendar))
        #expect(!PerfectDay.record(date(8, 20), defaults: defaults, calendar: calendar))
        PerfectDay.record(date(9), defaults: defaults, calendar: calendar)
        // Today (10th) not perfect yet: the run ending yesterday still counts.
        #expect(PerfectDay.streak(asOf: date(10), defaults: defaults, calendar: calendar) == 2)
        PerfectDay.record(date(10), defaults: defaults, calendar: calendar)
        #expect(PerfectDay.streak(asOf: date(10), defaults: defaults, calendar: calendar) == 3)
        // A gap starts a new run.
        #expect(PerfectDay.streak(asOf: date(13), defaults: defaults, calendar: calendar) == 0)
        #expect(PerfectDay.total(defaults: defaults) == 3)
    }
}

@Suite("Buddy intro — one tip a day for the first week")
struct BuddyIntroTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ d: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    @Test func oneTipPerDayForAWeek() throws {
        let defaults = try #require(UserDefaults(suiteName: "BuddyIntroTests.\(UUID().uuidString)"))
        #expect(BuddyIntro.tipForToday(now: day(5), defaults: defaults, calendar: calendar) == 0)
        // Same day, later: still tip 0 until dismissed.
        #expect(BuddyIntro.tipForToday(now: day(5, 20), defaults: defaults, calendar: calendar) == 0)
        BuddyIntro.dismiss(0, defaults: defaults)
        #expect(BuddyIntro.tipForToday(now: day(5, 21), defaults: defaults, calendar: calendar) == nil)
        #expect(BuddyIntro.tipForToday(now: day(6), defaults: defaults, calendar: calendar) == 1)
        // Skipped days are skipped, not queued.
        #expect(BuddyIntro.tipForToday(now: day(9), defaults: defaults, calendar: calendar) == 4)
        #expect(BuddyIntro.tipForToday(now: day(11), defaults: defaults, calendar: calendar) == 6)
        #expect(BuddyIntro.tipForToday(now: day(12), defaults: defaults, calendar: calendar) == nil)
    }
}
