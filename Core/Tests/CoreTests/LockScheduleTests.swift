// Core/Tests/CoreTests/LockScheduleTests.swift
//
// Wave 2E: scheduled locks (docs/spec.md §2 "Schedule (e.g., 7:00 AM daily)", §27 "minimum interval
// of 15 minutes") and partial-unlock tier persistence (§2, §4 v2). Pure math only — nothing here
// touches DeviceActivityCenter or ManagedSettings (those need a device, spec §27). Dates use a
// fixed Gregorian/UTC calendar so the suite is deterministic wherever it runs.

import Foundation
import FamilyControls
import Testing
@testable import Core

private enum ScheduleFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-01-14 is a Wednesday (weekday 4).
    static func date(day: Int = 14, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }
}

@Suite("LockSchedule — validation, windows, next start")
struct LockScheduleTests {
    private let lockSetID = UUID()

    @Test func defaultScheduleIsSevenAMEveryDayUntilGoalsDone() {
        let schedule = LockSchedule(lockSetID: lockSetID)
        #expect(schedule.isValid)
        #expect(schedule.startMinuteOfDay == 420)
        #expect(schedule.isUntilGoalsDone)
        #expect(schedule.effectiveEndMinuteOfDay == LockSchedule.endOfDayMinute)
        #expect(schedule.weekdays == LockSchedule.allWeekdays)
    }

    @Test func validationRejectsBadWindows() {
        #expect(LockSchedule(lockSetID: lockSetID, weekdays: []).validate() == .noWeekdays)
        #expect(LockSchedule(lockSetID: lockSetID, weekdays: [8]).validate() == .noWeekdays)
        #expect(LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 1_440).validate() == .startOutOfRange)
        #expect(LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 540, endMinuteOfDay: 550).validate() == .windowTooShort)
        #expect(LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 540, endMinuteOfDay: 480).validate() == .windowTooShort)
        #expect(LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 540, endMinuteOfDay: 1_500).validate() == .endOutOfRange)
        // Exactly 15 minutes is the DeviceActivity minimum (spec §27) — allowed.
        #expect(LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 540, endMinuteOfDay: 555).isValid)
        // "Until goals are done" needs 15 minutes before 23:59 too.
        #expect(LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 1_430).validate() == .windowTooShort)
    }

    @Test func nextStartIsLaterTodayOrTheNextMatchingDay() {
        let cal = ScheduleFixture.calendar
        let daily = LockSchedule(lockSetID: lockSetID)
        #expect(daily.nextStart(after: ScheduleFixture.date(hour: 6), calendar: cal) == ScheduleFixture.date(hour: 7))
        #expect(daily.nextStart(after: ScheduleFixture.date(hour: 7), calendar: cal) == ScheduleFixture.date(day: 15, hour: 7))

        // Mondays only (weekday 2): from Wednesday the 14th, next is Monday the 19th.
        let mondays = LockSchedule(lockSetID: lockSetID, weekdays: [2])
        #expect(mondays.nextStart(after: ScheduleFixture.date(hour: 6), calendar: cal) == ScheduleFixture.date(day: 19, hour: 7))

        var disabled = daily
        disabled.isEnabled = false
        #expect(disabled.nextStart(after: ScheduleFixture.date(hour: 6), calendar: cal) == nil)
    }

    @Test func isActiveCoversTheWindowOnMatchingDaysOnly() {
        let cal = ScheduleFixture.calendar
        let workBlock = LockSchedule(lockSetID: lockSetID, weekdays: [4], startMinuteOfDay: 540, endMinuteOfDay: 720)
        #expect(workBlock.isActive(at: ScheduleFixture.date(hour: 9), calendar: cal))
        #expect(workBlock.isActive(at: ScheduleFixture.date(hour: 11, minute: 59), calendar: cal))
        #expect(!workBlock.isActive(at: ScheduleFixture.date(hour: 12), calendar: cal))
        #expect(!workBlock.isActive(at: ScheduleFixture.date(hour: 8, minute: 59), calendar: cal))
        #expect(!workBlock.isActive(at: ScheduleFixture.date(day: 15, hour: 10), calendar: cal))
    }

    @Test func everyDayRegistersOneDailyWindow() throws {
        let windows = LockSchedule(lockSetID: lockSetID, startMinuteOfDay: 450).deviceActivityWindows
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.weekday == nil)
        #expect(window.startHour == 7 && window.startMinute == 30)
        // Until goals are done → 23:59:59.
        #expect(window.endHour == 23 && window.endMinute == 59 && window.endSecond == 59)
    }

    @Test func weekdaySubsetRegistersOneWeeklyWindowPerDay() {
        let schedule = LockSchedule(lockSetID: lockSetID, weekdays: [6, 2, 4], startMinuteOfDay: 540, endMinuteOfDay: 1_020)
        let windows = schedule.deviceActivityWindows
        #expect(windows.map(\.weekday) == [2, 4, 6])
        #expect(windows.allSatisfy { $0.endHour == 17 && $0.endMinute == 0 && $0.endSecond == 0 })
        #expect(windows.first?.startComponents.weekday == 2)
        #expect(windows.first?.endComponents.weekday == 2)
    }

    @Test func invalidScheduleRegistersNothing() {
        #expect(LockSchedule(lockSetID: lockSetID, weekdays: []).deviceActivityWindows.isEmpty)
    }

    @Test func activityNamesRoundTripToTheirLockSet() {
        let daily = LockScheduleActivity.rawName(lockSetID: lockSetID, weekday: nil)
        let weekly = LockScheduleActivity.rawName(lockSetID: lockSetID, weekday: 3)
        #expect(daily != weekly)
        #expect(LockScheduleActivity.lockSetID(fromRawName: daily) == lockSetID)
        #expect(LockScheduleActivity.lockSetID(fromRawName: weekly) == lockSetID)
        #expect(LockScheduleActivity.lockSetID(fromRawName: LockScheduleActivity.spendRawName) == nil)
        #expect(LockScheduleActivity.lockSetID(fromRawName: "com.zano.app.bedtimeGate") == nil)
        #expect(LockScheduleActivity.lockSetID(fromRawName: "com.zano.app.lock.\(UUID().uuidString)") == nil)
    }

    @Test func schedulesCodableRoundTrip() throws {
        let schedule = LockSchedule(
            lockSetID: lockSetID,
            weekdays: [1, 7],
            startMinuteOfDay: 600,
            endMinuteOfDay: 900,
            mode: .earn,
            requiredGoalIDs: [UUID()]
        )
        let decoded = try JSONDecoder().decode(LockSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(decoded == schedule)
    }
}

@Suite("LockEngineSharedState — schedule store", .serialized)
struct LockEngineSharedStateTests {
    @Test func upsertReplacesAndRemoveDeletes() {
        let original = LockEngineSharedState.schedules
        defer { LockEngineSharedState.schedules = original }
        LockEngineSharedState.schedules = []

        let id = UUID()
        LockEngineSharedState.upsert(LockSchedule(lockSetID: id, startMinuteOfDay: 420))
        LockEngineSharedState.upsert(LockSchedule(lockSetID: id, startMinuteOfDay: 480))
        #expect(LockEngineSharedState.schedules.count == 1)
        #expect(LockEngineSharedState.schedule(for: id)?.startMinuteOfDay == 480)

        LockEngineSharedState.removeSchedule(for: id)
        #expect(LockEngineSharedState.schedule(for: id) == nil)
    }

    @Test func nextScheduledStartIsTheEarliestAcrossSchedules() {
        let original = LockEngineSharedState.schedules
        defer { LockEngineSharedState.schedules = original }
        let cal = ScheduleFixture.calendar
        LockEngineSharedState.schedules = [
            LockSchedule(lockSetID: UUID(), startMinuteOfDay: 600),
            LockSchedule(lockSetID: UUID(), startMinuteOfDay: 480),
            LockSchedule(lockSetID: UUID(), isEnabled: false, startMinuteOfDay: 400),
        ]
        #expect(
            LockEngineSharedState.nextScheduledStart(after: ScheduleFixture.date(hour: 6), calendar: cal)
                == ScheduleFixture.date(hour: 8)
        )
    }
}

@Suite("Partial unlock tiers — completed goals + persistence", .serialized)
@MainActor
struct PartialUnlockTierStoreTests {
    @Test func completedGoalIDsAreRequiredMinusRemaining() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(PartialUnlockTiers.completedGoalIDs(required: [a, b, c], remaining: [b]) == [a, c])
        #expect(PartialUnlockTiers.completedGoalIDs(required: [a], remaining: [a]).isEmpty)
        // A stray remaining id never counts as completed.
        #expect(PartialUnlockTiers.completedGoalIDs(required: [a], remaining: [c]) == [a])
    }

    @Test func oneGoalDoneReachesOnlyTheOneGoalTier() throws {
        let lockSet = LockSet(userID: UUID(), name: "All", appTokensBlob: try JSONEncoder().encode(FamilyActivitySelection()))
        let messaging = try PartialUnlockTier(name: "Messaging", requiredCompletedGoalCount: 1, selection: FamilyActivitySelection())
        let social = try PartialUnlockTier(name: "Social", requiredCompletedGoalCount: 2, selection: FamilyActivitySelection())
        let a = UUID(), b = UUID(), c = UUID()
        let completed = PartialUnlockTiers.completedGoalIDs(required: [a, b, c], remaining: [b, c])
        let evaluation = PartialUnlockTiers.evaluate(lockSet: lockSet, tiers: [social, messaging], completedGoalIDs: completed)
        #expect(evaluation.unlockedTiers.map(\.name) == ["Messaging"])
        #expect(evaluation.lockedTiers.map(\.name) == ["Social"])
        #expect(evaluation.remainingLockedSelection != nil)
    }

    @Test func storeRoundTripsSortsAndDropsZeroGoalTiers() throws {
        let lockSetID = UUID()
        defer { PartialUnlockTierStore.removeTiers(for: lockSetID) }
        let later = try PartialUnlockTier(name: "Social", requiredCompletedGoalCount: 2, selection: FamilyActivitySelection())
        let earlier = try PartialUnlockTier(name: "Messaging", requiredCompletedGoalCount: 1, selection: FamilyActivitySelection())
        let free = try PartialUnlockTier(name: "Free", requiredCompletedGoalCount: 0, selection: FamilyActivitySelection())

        PartialUnlockTierStore.setTiers([later, free, earlier], for: lockSetID)
        #expect(PartialUnlockTierStore.tiers(for: lockSetID).map(\.name) == ["Messaging", "Social"])

        PartialUnlockTierStore.setTiers([], for: lockSetID)
        #expect(PartialUnlockTierStore.tiers(for: lockSetID).isEmpty)
    }
}
