// Core/Tests/CoreTests/NudgeSchedulerTests.swift
//
// Covers `NudgeScheduler.plan(_:)` (Core/Sources/Core/Social/NudgeScheduler.swift): the pure
// decision of which proactive nudges to schedule. docs/spec.md §8 rule 7 (2/day cap) and §9.3.
// No UNUserNotificationCenter and no store: every input is a plain value, on a fixed GMT
// Gregorian calendar so DST and the machine's time zone can't move the times.

import Testing
import Foundation
@testable import Core

private let gmt: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
}()

/// 2026-09-27 is a Sunday; 2026-09-28 a Monday.
private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    gmt.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

/// Monday morning, before every nudge time, with every kind eligible today.
private func mondayInputs(
    now: Date = date(28, 7),
    preferences: NudgePreferences = NudgePreferences(),
    healthPaused: Bool = false,
    deliveredToday: Int = 0,
    protein: NudgeScheduleInputs.Protein? = .init(logged: 100, target: 150),
    streak: Int = 5,
    openGoals: Int = 2
) -> NudgeScheduleInputs {
    NudgeScheduleInputs(
        now: now,
        calendar: gmt,
        preferences: preferences,
        healthPaused: healthPaused,
        deliveredByDay: [gmt.startOfDay(for: now): deliveredToday],
        dailyGoalCount: 3,
        protein: protein,
        streak: streak,
        openGoalsToday: openGoals
    )
}

private func kinds(_ planned: [PlannedNudge], on day: Int) -> Set<NudgeKind> {
    Set(planned.filter { gmt.component(.day, from: $0.fireDate) == day }.map(\.kind))
}

@Suite("NudgeScheduler.plan — spec §8 rule 7 cap, quiet hours, health pause")
struct NudgeSchedulerTests {

    @Test("never more than 2 per day, even with 4 candidates on one day")
    func capOfTwoPerDay() {
        // Sunday 07:00: morning 08:00, protein 18:30, recap 19:00, streak 20:00 all qualify.
        let planned = NudgeScheduler.plan(mondayInputs(now: date(27, 7)))
        let byDay = Dictionary(grouping: planned) { gmt.startOfDay(for: $0.fireDate) }
        #expect(byDay.values.allSatisfy { $0.count <= NudgeSender.dailyCap })
        #expect(kinds(planned, on: 27) == [.streakAtRisk, .proteinLastMile])
    }

    @Test("capped day keeps streakAtRisk > proteinLastMile > morningPlan > weeklyRecap")
    func priorityWhenCapped() {
        // One already delivered today: only the top candidate fits.
        let planned = NudgeScheduler.plan(mondayInputs(now: date(27, 7), deliveredToday: 1))
        #expect(kinds(planned, on: 27) == [.streakAtRisk])

        // No streak or protein: morning beats recap.
        let quieter = NudgeScheduler.plan(mondayInputs(now: date(27, 7), deliveredToday: 1, protein: nil, streak: 0))
        #expect(kinds(quieter, on: 27) == [.morningPlan])

        // Cap already reached today: nothing today.
        let full = NudgeScheduler.plan(mondayInputs(now: date(27, 7), deliveredToday: 2))
        #expect(kinds(full, on: 27).isEmpty)
    }

    @Test("output is sorted by fire date and every fire date is in the future")
    func sortedAndFuture() {
        let now = date(28, 7)
        let planned = NudgeScheduler.plan(mondayInputs(now: now))
        #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
        #expect(planned.allSatisfy { $0.fireDate > now })
    }

    @Test("Monday: morning is dropped by the cap, recap goes to Sunday at 19:00")
    func mondayPlan() {
        let planned = NudgeScheduler.plan(mondayInputs())
        #expect(kinds(planned, on: 28) == [.streakAtRisk, .proteinLastMile])
        #expect(planned.first { $0.kind == .streakAtRisk }?.fireDate == date(28, 20))
        #expect(planned.first { $0.kind == .proteinLastMile }?.fireDate == date(28, 18, 30))
        #expect(planned.first { $0.kind == .weeklyRecap }?.fireDate == gmt.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 19)))
    }

    @Test("nudges off: nothing is scheduled")
    func nudgesOff() {
        #expect(NudgeScheduler.plan(mondayInputs(preferences: NudgePreferences(enabled: false))).isEmpty)
    }

    @Test("health pause: nothing is scheduled")
    func healthPause() {
        #expect(NudgeScheduler.plan(mondayInputs(healthPaused: true)).isEmpty)
    }

    @Test("a kind switched off is never scheduled, and frees its slot")
    func kindOff() {
        let prefs = NudgePreferences(disabledKinds: [.streakAtRisk])
        let planned = NudgeScheduler.plan(mondayInputs(preferences: prefs))
        #expect(!planned.contains { $0.kind == .streakAtRisk })
        #expect(kinds(planned, on: 28) == [.proteinLastMile, .morningPlan])
    }

    @Test("quiet hours drop tonight's nudges instead of moving them to tomorrow")
    func quietHoursDropEvening() {
        let prefs = NudgePreferences(quietHoursEnabled: true, quietStartMinutes: 18 * 60, quietEndMinutes: 23 * 60)
        let planned = NudgeScheduler.plan(mondayInputs(preferences: prefs))
        #expect(!planned.contains { $0.kind == .streakAtRisk || $0.kind == .proteinLastMile })
    }

    @Test("quiet hours move the morning plan to the end of quiet hours")
    func quietHoursShiftMorning() {
        let prefs = NudgePreferences(quietHoursEnabled: true, quietStartMinutes: 22 * 60, quietEndMinutes: 9 * 60)
        let planned = NudgeScheduler.plan(mondayInputs(now: date(28, 6), preferences: prefs, protein: nil, streak: 0))
        #expect(planned.first { $0.kind == .morningPlan }?.fireDate == date(28, 9))
    }

    @Test("the morning plan is dropped when quiet hours run past noon")
    func quietHoursDropLateMorning() {
        let prefs = NudgePreferences(quietHoursEnabled: true, quietStartMinutes: 6 * 60, quietEndMinutes: 13 * 60)
        let planned = NudgeScheduler.plan(mondayInputs(now: date(28, 5), preferences: prefs, protein: nil, streak: 0))
        #expect(!planned.contains { $0.kind == .morningPlan })
    }

    @Test("protein last mile: only between 40% and done")
    func proteinThreshold() {
        func hasProtein(_ protein: NudgeScheduleInputs.Protein?) -> Bool {
            NudgeScheduler.plan(mondayInputs(protein: protein, streak: 0)).contains { $0.kind == .proteinLastMile }
        }
        #expect(!hasProtein(nil))
        #expect(!hasProtein(.init(logged: 45, target: 150)))            // 30%
        #expect(hasProtein(.init(logged: 60, target: 150)))             // 40%
        #expect(hasProtein(.init(logged: 140, target: 150)))
        #expect(!hasProtein(.init(logged: 150, target: 150)))           // done
        #expect(!hasProtein(.init(logged: 90, target: 150, isComplete: true)))
        #expect(NudgeScheduleInputs.Protein(logged: 110.2, target: 150).amountToGo == 40)
    }

    @Test("streak at risk: only with a streak and an open goal")
    func streakAtRiskNeedsOpenGoals() {
        func hasStreak(streak: Int, open: Int) -> Bool {
            NudgeScheduler.plan(mondayInputs(protein: nil, streak: streak, openGoals: open)).contains { $0.kind == .streakAtRisk }
        }
        #expect(hasStreak(streak: 3, open: 2))
        #expect(!hasStreak(streak: 3, open: 0))
        #expect(!hasStreak(streak: 0, open: 2))
    }

    @Test("after 20:00 tonight's nudges are gone and the morning plan rolls to tomorrow")
    func lateEvening() {
        let planned = NudgeScheduler.plan(mondayInputs(now: date(28, 21)))
        #expect(!planned.contains { $0.kind == .streakAtRisk || $0.kind == .proteinLastMile })
        #expect(planned.first { $0.kind == .morningPlan }?.fireDate == date(29, 8))
    }

    @Test("no daily goals: no morning plan")
    func noGoalsNoMorningPlan() {
        var inputs = mondayInputs(protein: nil, streak: 0, openGoals: 0)
        inputs.dailyGoalCount = 0
        #expect(!NudgeScheduler.plan(inputs).contains { $0.kind == .morningPlan })
    }

    @Test("copy is additive: protein says what's left to go")
    func proteinCopyIsAdditive() {
        for tone in NudgeTone.allCases {
            let copy = Copy.nudges.proteinLastMile(tone: tone, amountToGo: 40, unit: "g")
            #expect((copy.title + copy.body).contains("40g"))
            #expect((copy.title + copy.body).contains("to go") || (copy.title + copy.body).contains("remaining"))
        }
    }

    @Test("notification identifiers round-trip the Nudge row id")
    func identifierRoundTrip() {
        let id = UUID()
        #expect(NudgeScheduler.nudgeID(fromIdentifier: "\(NudgeScheduler.identifierPrefix)morning_plan.\(id.uuidString)") == id)
    }
}
