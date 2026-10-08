import Testing
import Foundation
@testable import Core

@Suite("Household screen-free times — window math, opt-ins, reminders (session 44)", .serialized)
struct HouseholdQuietTimeTests {
    private let home = UUID()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// 2026-10-07 is a Wednesday (weekday 4).
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func window(_ name: String = "Dinner", start: Int, end: Int, days: [Int] = [1, 2, 3, 4, 5, 6, 7]) -> HouseholdQuietTime {
        HouseholdQuietTime(householdId: home, name: name, startMinute: start, endMinute: end, weekdays: days)
    }

    // MARK: Validation

    @Test func validation() {
        #expect(window(start: 18 * 60, end: 19 * 60).validate() == nil)
        #expect(window(start: 22 * 60, end: 7 * 60).validate() == nil)
        #expect(window(start: 18 * 60, end: 18 * 60 + 10).validate() == .tooShort)
        #expect(window(start: 18 * 60, end: 18 * 60).validate() == .tooShort)
        #expect(window(start: 18 * 60, end: 19 * 60, days: []).validate() == .noDays)
        #expect(window("  ", start: 18 * 60, end: 19 * 60).validate() == .emptyName)
        #expect(window(start: 1_440, end: 60).validate() == .timeOutOfRange)
        // Crossing midnight with only 15 minutes still counts.
        #expect(window(start: 23 * 60 + 50, end: 5).validate() == nil)
    }

    // MARK: Window math

    @Test func dinnerOccurrence() {
        let dinner = window(start: 18 * 60, end: 19 * 60)
        let inside = dinner.occurrence(containing: date(7, 18, 30), calendar: calendar)
        #expect(inside == DateInterval(start: date(7, 18), end: date(7, 19)))
        #expect(dinner.occurrence(containing: date(7, 19), calendar: calendar) == nil)
        #expect(dinner.nextOccurrence(after: date(7, 19), calendar: calendar)?.start == date(8, 18))
    }

    @Test func bedtimeCrossesMidnightOnSchoolNights() {
        // Sunday to Thursday nights, 22:00-07:00.
        let bedtime = window("Bedtime", start: 22 * 60, end: 7 * 60, days: [1, 2, 3, 4, 5])
        #expect(bedtime.crossesMidnight)
        // Wednesday 23:00 and Thursday 06:00 are both inside Wednesday's night.
        let wednesdayNight = DateInterval(start: date(7, 22), end: date(8, 7))
        #expect(bedtime.occurrence(containing: date(7, 23), calendar: calendar) == wednesdayNight)
        #expect(bedtime.occurrence(containing: date(8, 6), calendar: calendar) == wednesdayNight)
        // Friday night (weekday 6) is off, so Saturday 02:00 is free.
        #expect(bedtime.occurrence(containing: date(10, 2), calendar: calendar) == nil)
        // After Thursday's night, the next one starts Sunday.
        #expect(bedtime.nextOccurrence(after: date(9, 8), calendar: calendar)?.start == date(11, 22))
    }

    @Test func registrationsEndOnTheNextDayWhenCrossingMidnight() {
        let every = window(start: 22 * 60, end: 7 * 60)
        #expect(every.deviceActivityWindows.count == 1)
        #expect(every.deviceActivityWindows.first?.startWeekday == nil)

        let some = window(start: 22 * 60, end: 7 * 60, days: [5, 7])
        let slots = some.deviceActivityWindows
        #expect(slots.map(\.startWeekday) == [5, 7])
        #expect(slots.map(\.endWeekday) == [6, 1])
        #expect(slots.first?.endHour == 7)
    }

    @Test func activityNamesRoundTrip() {
        let id = UUID()
        let daily = HouseholdQuietTimeActivity.rawName(windowID: id, weekday: nil)
        let weekly = HouseholdQuietTimeActivity.rawName(windowID: id, weekday: 3)
        #expect(HouseholdQuietTimeActivity.windowID(fromRawName: daily) == id)
        #expect(HouseholdQuietTimeActivity.windowID(fromRawName: weekly) == id)
        #expect(!HouseholdQuietTimeActivity.isQuietTimeActivity(FocusLockActivity.rawName(windowID: "x")))
        #expect(!HouseholdQuietTimeActivity.isQuietTimeActivity(BedtimeGateActivity.dailyRawName))
        #expect(LockScheduleActivity.lockSetID(fromRawName: daily) == nil)
    }

    // MARK: Opt-ins and the registration cap

    @Test func onlyJoinedValidWindowsAreScheduled() {
        let dinner = window(start: 18 * 60, end: 19 * 60)
        let bedtime = window("Bedtime", start: 22 * 60, end: 7 * 60)
        let broken = window("Broken", start: 60, end: 60)
        let optIns = [HouseholdQuietTimeOptIn(windowID: dinner.id), HouseholdQuietTimeOptIn(windowID: broken.id)]
        let joined = HouseholdQuietTimePlanner.joined(windows: [dinner, bedtime, broken], optIns: optIns)
        #expect(joined == [dinner])
    }

    @Test func capKeepsRegistrationsInsideTheLimit() {
        let weekdaysOnly = window("Homework", start: 16 * 60, end: 17 * 60, days: [2, 3, 4, 5, 6]) // 5 registrations
        let daily = window(start: 18 * 60, end: 19 * 60) // 1
        let twoDays = window("Sunday", start: 9 * 60, end: 10 * 60, days: [1, 7]) // 2
        #expect(HouseholdQuietTimePlanner.canJoin(daily, joined: [weekdaysOnly]))
        #expect(!HouseholdQuietTimePlanner.canJoin(twoDays, joined: [weekdaysOnly, daily]))
        #expect(HouseholdQuietTimePlanner.canJoin(daily, joined: [daily]))
        // In order: 5 + 2 fill the 7 slots, so the every-day window that comes last is skipped, not half-registered.
        let scheduled = HouseholdQuietTimePlanner.schedulable([weekdaysOnly, twoDays, daily])
        #expect(scheduled == [weekdaysOnly, twoDays])
        #expect(HouseholdQuietTimePlanner.registrationCount(scheduled) <= HouseholdQuietTimePlanner.maxRegistrations)
    }

    @Test func signatureChangesWithTheWindow() {
        var dinner = window(start: 18 * 60, end: 19 * 60)
        let before = HouseholdQuietTimePlanner.signature([dinner])
        dinner.endMinute = 19 * 60 + 30
        #expect(HouseholdQuietTimePlanner.signature([dinner]) != before)
    }

    @Test func optInsPersistAndDropWithTheirWindow() {
        HouseholdQuietTimeStore.resetAll()
        defer { HouseholdQuietTimeStore.resetAll() }
        let dinner = window(start: 18 * 60, end: 19 * 60)
        let bedtime = window("Bedtime", start: 22 * 60, end: 7 * 60)
        let lockSet = UUID()
        HouseholdQuietTimeStore.replaceWindows([dinner, bedtime])
        HouseholdQuietTimeStore.setOptIn(HouseholdQuietTimeOptIn(windowID: dinner.id, lockSetID: lockSet), for: dinner.id)
        HouseholdQuietTimeStore.setOptIn(HouseholdQuietTimeOptIn(windowID: bedtime.id), for: bedtime.id)
        #expect(HouseholdQuietTimeStore.optIn(for: dinner.id)?.lockSetID == lockSet)
        #expect(HouseholdQuietTimeStore.optIn(for: bedtime.id)?.lockSetID == nil)
        #expect(HouseholdQuietTimeStore.joinedWindow(forActivityRawName: HouseholdQuietTimeActivity.rawName(windowID: dinner.id, weekday: nil)) == dinner)

        // Leaving.
        HouseholdQuietTimeStore.setOptIn(nil, for: bedtime.id)
        #expect(HouseholdQuietTimeStore.optIn(for: bedtime.id) == nil)
        #expect(HouseholdQuietTimeStore.joinedWindow(forActivityRawName: HouseholdQuietTimeActivity.rawName(windowID: bedtime.id, weekday: nil)) == nil)

        // The window is deleted on the server: its join goes too.
        HouseholdQuietTimeStore.replaceWindows([bedtime])
        #expect(HouseholdQuietTimeStore.optIns.isEmpty)
    }

    @Test func oneDecisionPerOccurrence() {
        HouseholdQuietTimeStore.resetAll()
        defer { HouseholdQuietTimeStore.resetAll() }
        let id = UUID()
        #expect(!HouseholdQuietTimeStore.hasDecided(windowID: id, occurrenceStart: date(7, 18)))
        HouseholdQuietTimeStore.markDecided(windowID: id, occurrenceStart: date(7, 18))
        #expect(HouseholdQuietTimeStore.hasDecided(windowID: id, occurrenceStart: date(7, 18)))
        #expect(!HouseholdQuietTimeStore.hasDecided(windowID: id, occurrenceStart: date(8, 18)))
    }

    // MARK: Reminders and Today

    @Test func remindersTenMinutesBeforeEachJoinedStart() {
        let dinner = window(start: 18 * 60, end: 19 * 60)
        let now = date(7, 12)
        let planned = HouseholdQuietTimePlanner.reminders(joined: [dinner], now: now, calendar: calendar)
        #expect(planned.first?.fireDate == date(7, 17, 50))
        #expect(planned.count == 7)
        #expect(Set(planned.map(\.identifier)).count == planned.count)
        #expect(planned.allSatisfy { $0.identifier.hasPrefix(HouseholdQuietTimePlanner.reminderPrefix) })
        // Inside the 10 minutes: today's is skipped, tomorrow's is first.
        let late = HouseholdQuietTimePlanner.reminders(joined: [dinner], now: date(7, 17, 55), calendar: calendar)
        #expect(late.first?.fireDate == date(8, 17, 50))
    }

    @Test func todayStatus() {
        let dinner = window(start: 18 * 60, end: 19 * 60)
        #expect(HouseholdQuietTimePlanner.status(joined: [dinner], now: date(7, 17), calendar: calendar) == nil)
        #expect(HouseholdQuietTimePlanner.status(joined: [dinner], now: date(7, 17, 52), calendar: calendar)
            == .startingSoon(window: dinner, start: date(7, 18)))
        #expect(HouseholdQuietTimePlanner.status(joined: [dinner], now: date(7, 18, 20), calendar: calendar)
            == .running(window: dinner, end: date(7, 19)))
        #expect(HouseholdQuietTimePlanner.status(joined: [], now: date(7, 18, 20), calendar: calendar) == nil)
    }

    @Test func decodesTheServerRow() throws {
        let json = """
        [{"id":"7B0B8C8E-3A0B-4E59-9A47-8F3C2B1D0A11","household_id":"\(home.uuidString)","name":"Dinner",
          "start_minute":1080,"end_minute":1140,"weekdays":[1,2,3,4,5,6,7],
          "created_by":null,"created_at":"2026-10-07T18:00:00.123456+00:00","updated_at":"2026-10-07T18:00:00+00:00"}]
        """
        let rows = try FamilyJSON.decoder.decode([HouseholdQuietTime].self, from: Data(json.utf8))
        #expect(rows.first?.startMinute == 1_080)
        #expect(rows.first?.weekdaySet.count == 7)
        #expect(rows.first?.householdId == home)
    }

    @Test func daysSummaryCopy() {
        #expect(Copy.household.daysSummary([1, 2, 3, 4, 5, 6, 7]) == "Every day")
        #expect(Copy.household.daysSummary([2, 3, 4, 5, 6]) == "Weekdays")
        #expect(Copy.household.daysSummary([1, 2, 3, 4, 5]) == "School nights")
    }
}
