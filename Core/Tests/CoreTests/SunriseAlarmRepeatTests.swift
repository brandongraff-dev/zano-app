// Core/Tests/CoreTests/SunriseAlarmRepeatTests.swift
//
// Session 14: repeat days, sounds and the backup alarm (docs/spec.md §5.10). Covers the pure parts:
// the next ring time for each repeat pattern, the Repeat row's wording, and that a settings row saved
// before these fields existed still decodes (it must keep its wake time, not fall back to defaults).

import Foundation
import Testing
@testable import Core

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

// 2026-10-09 is a Friday; 10 is Saturday, 11 Sunday, 12 Monday.
@Suite("Sunrise Alarm repeat days")
struct SunriseAlarmRepeatTests {
    @Test func everyDayRingsTomorrowWhenTodaysTimeHasPassed() {
        let next = SunriseAlarmManager.nextFireDate(hour: 6, minute: 30, after: date(9, hour: 19), repeatDays: RepeatDays.everyDay, calendar: utc)
        #expect(next == date(10, hour: 6, minute: 30))
    }

    @Test func everyDayRingsLaterTodayWhenTheTimeIsAhead() {
        let next = SunriseAlarmManager.nextFireDate(hour: 6, minute: 30, after: date(9, hour: 5), repeatDays: RepeatDays.everyDay, calendar: utc)
        #expect(next == date(9, hour: 6, minute: 30))
    }

    @Test func weekdaysSkipTheWeekend() {
        let next = SunriseAlarmManager.nextFireDate(hour: 6, minute: 30, after: date(9, hour: 19), repeatDays: RepeatDays.weekdays, calendar: utc)
        #expect(next == date(12, hour: 6, minute: 30))
    }

    @Test func weekendsSkipTheWeek() {
        let next = SunriseAlarmManager.nextFireDate(hour: 6, minute: 30, after: date(7, hour: 12), repeatDays: RepeatDays.weekends, calendar: utc)
        #expect(next == date(10, hour: 6, minute: 30))
    }

    @Test func neverIsJustTheNextOccurrence() {
        let next = SunriseAlarmManager.nextFireDate(hour: 6, minute: 30, after: date(9, hour: 19), repeatDays: [], calendar: utc)
        #expect(next == date(10, hour: 6, minute: 30))
    }

    @Test func aSingleDayRingsOnThatDay() {
        // Wednesday only (weekday 4), asked on a Friday: the following Wednesday, the 14th.
        let next = SunriseAlarmManager.nextFireDate(hour: 7, minute: 0, after: date(9, hour: 19), repeatDays: [4], calendar: utc)
        #expect(next == date(14, hour: 7))
    }

    @Test func summariesReadLikeTheClockApp() {
        #expect(RepeatDays.summary([], calendar: utc) == Copy.sunriseAlarm.repeatNever)
        #expect(RepeatDays.summary(RepeatDays.everyDay, calendar: utc) == Copy.sunriseAlarm.repeatEveryDay)
        #expect(RepeatDays.summary(RepeatDays.weekdays, calendar: utc) == Copy.sunriseAlarm.repeatWeekdays)
        #expect(RepeatDays.summary(RepeatDays.weekends, calendar: utc) == Copy.sunriseAlarm.repeatWeekends)
        #expect(RepeatDays.summary([2, 4], calendar: utc) == "Mon, Wed")
    }

    @Test func weekdaysListStartsOnTheCalendarsFirstDay() {
        #expect(RepeatDays.orderedWeekdays(calendar: utc) == [1, 2, 3, 4, 5, 6, 7])
        var monday = utc
        monday.firstWeekday = 2
        #expect(RepeatDays.orderedWeekdays(calendar: monday) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func settingsSavedBeforeTheNewFieldsStillDecode() throws {
        // A row from before repeat days, sounds and the backup alarm: those keys are absent.
        var original = SunriseAlarmManager.Settings()
        original.wakeTime = date(9, hour: 7, minute: 15)
        original.stepsTarget = 80
        let data = try JSONEncoder().encode(original)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["repeatDays", "sound", "backupAlarmEnabled", "backupMinutes"] { object.removeValue(forKey: key) }
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SunriseAlarmManager.Settings.self, from: legacy)
        #expect(decoded.wakeTime == original.wakeTime)
        #expect(decoded.stepsTarget == 80)
        #expect(decoded.repeatDays == RepeatDays.everyDay)
        #expect(decoded.sound == .daybreak)
        #expect(decoded.backupAlarmEnabled == false)
        #expect(decoded.backupMinutes == 10)
    }

    @Test func newFieldsRoundTrip() throws {
        var settings = SunriseAlarmManager.Settings()
        settings.repeatDays = RepeatDays.weekdays
        settings.sound = .marimba
        settings.backupAlarmEnabled = true
        settings.backupMinutes = 15
        let decoded = try JSONDecoder().decode(SunriseAlarmManager.Settings.self, from: try JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func everySoundHasABundledFileName() {
        for sound in AlarmSoundChoice.allCases {
            #expect(sound.fileName == "alarm-\(sound.rawValue).wav")
        }
    }
}
