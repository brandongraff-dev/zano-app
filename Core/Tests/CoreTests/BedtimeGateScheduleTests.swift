// Core/Tests/CoreTests/BedtimeGateScheduleTests.swift
//
// Session 38: the Bedtime Gate's night window (docs/spec.md §5.10, §27 "minimum interval of 15
// minutes ... can be delayed"). Pure math only: nothing here touches DeviceActivityCenter or
// ManagedSettings (those need a device, spec §27). Fixed calendars keep it deterministic.

import Foundation
import Testing
@testable import Core

private enum NightFixture {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// January 2026 in UTC. The 14th is a Wednesday (weekday 4).
    static func date(day: Int = 14, hour: Int, minute: Int = 0, second: Int = 0, calendar: Calendar = utc, month: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// 22:30 to 06:30, the defaults of the shared Sunrise/Bedtime settings row.
    static let usual = BedtimeGateSchedule(bedtimeMinute: 22 * 60 + 30, wakeMinute: 6 * 60 + 30)
}

@Suite("Bedtime Gate — night window")
struct BedtimeGateScheduleTests {

    // MARK: Crossing midnight

    @Test func usualNightCrossesMidnightAndRegistersOneDailyWindow() throws {
        let schedule = NightFixture.usual
        #expect(schedule.crossesMidnight)
        #expect(schedule.durationMinutes == 8 * 60)
        #expect(schedule.endMinute == 6 * 60 + 30)

        let windows = schedule.deviceActivityWindows
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.startWeekday == nil && window.endWeekday == nil)
        #expect(window.startComponents.hour == 22 && window.startComponents.minute == 30)
        #expect(window.endComponents.hour == 6 && window.endComponents.minute == 30)
        #expect(window.activityRawName == BedtimeGateActivity.dailyRawName)
    }

    @Test func nightContainsLateEveningAndSmallHoursButNotTheDay() throws {
        let cal = NightFixture.utc
        let schedule = NightFixture.usual
        let expectedStart = NightFixture.date(hour: 22, minute: 30)
        let expectedEnd = NightFixture.date(day: 15, hour: 6, minute: 30)

        let evening = try #require(schedule.night(containing: NightFixture.date(hour: 23), calendar: cal))
        #expect(evening.start == expectedStart && evening.end == expectedEnd)

        // 03:00 on the 15th belongs to the night that started on the 14th.
        let smallHours = try #require(schedule.night(containing: NightFixture.date(day: 15, hour: 3), calendar: cal))
        #expect(smallHours.start == expectedStart)

        #expect(schedule.night(containing: expectedStart, calendar: cal) != nil, "bedtime itself is inside")
        #expect(schedule.night(containing: expectedEnd, calendar: cal) == nil, "wake time itself is outside")
        #expect(schedule.night(containing: NightFixture.date(hour: 22, minute: 29), calendar: cal) == nil)
        #expect(schedule.night(containing: NightFixture.date(hour: 12), calendar: cal) == nil)
    }

    @Test func afterMidnightBedtimeIsASameDayNight() throws {
        let cal = NightFixture.utc
        let schedule = BedtimeGateSchedule(bedtimeMinute: 30, wakeMinute: 7 * 60)
        #expect(!schedule.crossesMidnight)
        let night = try #require(schedule.night(containing: NightFixture.date(day: 15, hour: 3), calendar: cal))
        #expect(night.start == NightFixture.date(day: 15, hour: 0, minute: 30))
        #expect(night.end == NightFixture.date(day: 15, hour: 7))
    }

    @Test func windowIsNeverShorterThanTheDeviceActivityMinimum() {
        // Wake equal to bedtime would otherwise be 0 (or a 24-hour lock).
        let same = BedtimeGateSchedule(bedtimeMinute: 22 * 60, wakeMinute: 22 * 60)
        #expect(same.durationMinutes == BedtimeGateSchedule.minimumWindowMinutes)
        #expect(same.endMinute == 22 * 60 + 15)

        let tooClose = BedtimeGateSchedule(bedtimeMinute: 23 * 60 + 50, wakeMinute: 23 * 60 + 55)
        #expect(tooClose.durationMinutes == 15)
        #expect(tooClose.endMinute == 5, "pushed past midnight to 00:05")
        #expect(tooClose.crossesMidnight)
    }

    @Test func callbacksAllowForSmallTimingSlop() throws {
        let cal = NightFixture.utc
        let schedule = NightFixture.usual
        // A start callback a minute early still finds tonight.
        let early = try #require(schedule.night(forStartCallbackAt: NightFixture.date(hour: 22, minute: 29), calendar: cal))
        #expect(early.start == NightFixture.date(hour: 22, minute: 30))

        // Wake-time ends: on time, slightly early, and later all count as over.
        #expect(schedule.isNightOver(at: NightFixture.date(day: 15, hour: 6, minute: 30), calendar: cal))
        #expect(schedule.isNightOver(at: NightFixture.date(day: 15, hour: 6, minute: 29), calendar: cal))
        #expect(schedule.isNightOver(at: NightFixture.date(day: 15, hour: 9), calendar: cal))
        // A stray end in the middle of the night (re-registration) is not.
        #expect(!schedule.isNightOver(at: NightFixture.date(day: 15, hour: 2), calendar: cal))
        #expect(!schedule.isNightOver(at: NightFixture.date(hour: 23), calendar: cal))
    }

    // MARK: DST (wall-clock times, like DeviceActivity's DateComponents)

    @Test func springForwardNightIsAnHourShorter() throws {
        let cal = NightFixture.newYork
        // US clocks go forward at 02:00 on Sunday 2026-03-08.
        let start = NightFixture.date(day: 7, hour: 23, calendar: cal, month: 3)
        let night = try #require(NightFixture.usual.night(containing: start, calendar: cal))
        #expect(night.start == NightFixture.date(day: 7, hour: 22, minute: 30, calendar: cal, month: 3))
        #expect(night.end == NightFixture.date(day: 8, hour: 6, minute: 30, calendar: cal, month: 3))
        #expect(night.duration == 7 * 3_600)
        // 04:00 that morning is still inside it.
        #expect(NightFixture.usual.night(containing: NightFixture.date(day: 8, hour: 4, calendar: cal, month: 3), calendar: cal)?.start == night.start)
    }

    @Test func fallBackNightIsAnHourLonger() throws {
        let cal = NightFixture.newYork
        // US clocks go back at 02:00 on Sunday 2026-11-01.
        let start = NightFixture.date(day: 31, hour: 23, calendar: cal, month: 10)
        let night = try #require(NightFixture.usual.night(containing: start, calendar: cal))
        #expect(night.end == NightFixture.date(day: 1, hour: 6, minute: 30, calendar: cal, month: 11))
        #expect(night.duration == 9 * 3_600)
    }

    @Test func registrationsAreWallClockSoDSTDoesNotChangeThem() {
        // Same components whatever the time zone or season: iOS applies them in local time.
        #expect(NightFixture.usual.registrationSignature == BedtimeGateSchedule(
            bedtime: NightFixture.date(day: 7, hour: 22, minute: 30, calendar: NightFixture.newYork, month: 3),
            wakeTime: NightFixture.date(day: 8, hour: 6, minute: 30, calendar: NightFixture.newYork, month: 3),
            calendar: NightFixture.newYork
        ).registrationSignature)
    }

    // MARK: Nights that are off

    @Test func someNightsOffRegistersOneWeeklyWindowPerNightEndingTheNextDay() {
        // Monday and Tuesday nights, plus Saturday (whose night ends on Sunday, weekday 1).
        let schedule = BedtimeGateSchedule(bedtimeMinute: 22 * 60 + 30, wakeMinute: 6 * 60 + 30, nights: [2, 3, 7])
        let windows = schedule.deviceActivityWindows
        #expect(windows.map(\.startWeekday) == [2, 3, 7])
        #expect(windows.map(\.endWeekday) == [3, 4, 1])
        #expect(windows.map(\.activityRawName) == [
            "com.zano.app.bedtimeGate.d2", "com.zano.app.bedtimeGate.d3", "com.zano.app.bedtimeGate.d7",
        ])
        #expect(windows.allSatisfy { $0.startComponents.weekday == $0.startWeekday && $0.endComponents.weekday == $0.endWeekday })
    }

    @Test func sameDayNightKeepsItsWeekdayAtTheEnd() {
        let schedule = BedtimeGateSchedule(bedtimeMinute: 30, wakeMinute: 7 * 60, nights: [4])
        #expect(schedule.deviceActivityWindows.first?.endWeekday == 4)
    }

    @Test func nightsThatAreOffContainNothing() {
        let cal = NightFixture.utc
        // Tuesday nights only (weekday 3). The 13th is a Tuesday, the 14th a Wednesday.
        let schedule = BedtimeGateSchedule(bedtimeMinute: 22 * 60 + 30, wakeMinute: 6 * 60 + 30, nights: [3])
        #expect(schedule.night(containing: NightFixture.date(day: 13, hour: 23), calendar: cal) != nil)
        // 02:00 Wednesday belongs to Tuesday's night: on.
        #expect(schedule.night(containing: NightFixture.date(day: 14, hour: 2), calendar: cal) != nil)
        // Wednesday evening and 02:00 Thursday belong to Wednesday's night: off.
        #expect(schedule.night(containing: NightFixture.date(day: 14, hour: 23), calendar: cal) == nil)
        #expect(schedule.night(containing: NightFixture.date(day: 15, hour: 2), calendar: cal) == nil)
        #expect(schedule.night(startingOn: NightFixture.date(day: 14, hour: 0), calendar: cal) == nil)
        #expect(schedule.activityRawName(forNightStartingAt: NightFixture.date(day: 13, hour: 22, minute: 30), calendar: cal)
            == "com.zano.app.bedtimeGate.d3")
    }

    @Test func noNightsMeansNoWindowsAndNoNights() {
        let schedule = BedtimeGateSchedule(bedtimeMinute: 22 * 60 + 30, wakeMinute: 6 * 60 + 30, nights: [])
        #expect(schedule.deviceActivityWindows.isEmpty)
        #expect(schedule.night(containing: NightFixture.date(hour: 23), calendar: NightFixture.utc) == nil)
        // Out-of-range weekdays are dropped rather than registered.
        #expect(BedtimeGateSchedule(bedtimeMinute: 0, wakeMinute: 60, nights: [0, 8]).nights.isEmpty)
    }

    @Test func signatureChangesWithTimesAndNights() {
        let base = NightFixture.usual
        #expect(base.registrationSignature != BedtimeGateSchedule(bedtimeMinute: 22 * 60, wakeMinute: 6 * 60 + 30).registrationSignature)
        #expect(base.registrationSignature != BedtimeGateSchedule(bedtimeMinute: 22 * 60 + 30, wakeMinute: 7 * 60).registrationSignature)
        #expect(base.registrationSignature != BedtimeGateSchedule(bedtimeMinute: 22 * 60 + 30, wakeMinute: 6 * 60 + 30, nights: [2]).registrationSignature)
    }

    // MARK: Names and settings

    @Test func activityNamesAreRecognisedAndDistinctFromOtherLocks() {
        #expect(BedtimeGateActivity.isBedtimeActivity("com.zano.app.bedtimeGate"))
        #expect(BedtimeGateActivity.isBedtimeActivity(BedtimeGateActivity.rawName(nightWeekday: 5)))
        #expect(!BedtimeGateActivity.isBedtimeActivity("com.zano.app.schedule.\(UUID().uuidString)"))
        #expect(!BedtimeGateActivity.isBedtimeActivity("com.zano.app.focus.abc"))
        #expect(!BedtimeGateActivity.isBedtimeActivity("com.zano.app.bedtimeGateX"))
        #expect(LockScheduleActivity.lockSetID(fromRawName: BedtimeGateActivity.rawName(nightWeekday: 2)) == nil)
        #expect(NightFixture.usual.activityRawName(forNightStartingAt: NightFixture.date(hour: 22, minute: 30)) == BedtimeGateActivity.dailyRawName)
    }

    @Test func advancedSettingsSavedBeforeNightsExistedStillLoad() throws {
        let lockSetID = UUID()
        let legacy = #"{"lockSetID":"\#(lockSetID.uuidString)","mode":"full"}"#
        let decoded = try JSONDecoder().decode(BedtimeGateAdvancedSettings.self, from: Data(legacy.utf8))
        #expect(decoded.lockSetID == lockSetID)
        #expect(decoded.nights == BedtimeGateSchedule.everyNight)

        var settings = BedtimeGateAdvancedSettings(nights: [2, 3])
        settings.mode = .earn
        let roundTrip = try JSONDecoder().decode(BedtimeGateAdvancedSettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip == settings)
    }

    @Test func oneDecisionPerNight() {
        BedtimeGateSharedState.resetNightRecords()
        defer { BedtimeGateSharedState.resetNightRecords() }
        let cal = NightFixture.utc
        let tonight = NightFixture.date(hour: 22, minute: 30)
        #expect(!BedtimeGateSharedState.hasArmed(nightStartingAt: tonight, calendar: cal))
        BedtimeGateSharedState.markArmed(nightStartingAt: tonight)
        #expect(BedtimeGateSharedState.hasArmed(nightStartingAt: tonight, calendar: cal))
        // Tomorrow night is a new decision.
        #expect(!BedtimeGateSharedState.hasArmed(nightStartingAt: NightFixture.date(day: 15, hour: 22, minute: 30), calendar: cal))
    }
}
