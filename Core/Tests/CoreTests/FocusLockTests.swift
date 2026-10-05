// FocusLockTests.swift
// Core / Tests / CoreTests
//
// Coverage for the work-hours focus lock (session 17, 2026-10-05; docs/spec.md §5.24): which calendar
// events become lock windows, how back-to-back events join, how the on-device memory learns yes and
// no (two answers settle it), the activity-name round trip (and that it never collides with lock
// schedules), and the saved state. The pure planner and memory need no EventKit or DeviceActivity.
//
// `FocusLockStore` reads the App Group defaults, which have no test seam (see StoreTests.swift): its
// test saves and restores the real values and the suite is `.serialized`.

import Testing
import Foundation
@testable import Core

@Suite("Focus lock — planner, learning memory, naming, state", .serialized)
struct FocusLockTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static func at(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(minutes * 60)) }

    private static func event(
        _ title: String, from start: Int, to end: Int, attendees: Bool = false, busy: Bool = true,
        allDay: Bool = false, calendar: String = "work"
    ) -> FocusCalendarEvent {
        FocusCalendarEvent(
            id: "\(title)-\(start)", calendarID: calendar, title: title, start: at(start), end: at(end),
            isAllDay: allDay, isBusy: busy, hasOtherAttendees: attendees
        )
    }

    private static var on: FocusLockSettings { FocusLockSettings(isEnabled: true) }
    private func plan(_ events: [FocusCalendarEvent], settings: FocusLockSettings = Self.on,
                      memory: FocusLockPatternMemory = FocusLockPatternMemory()) -> [FocusLockProposal] {
        FocusLockPlanner.plan(events: events, settings: settings, memory: memory, now: Self.now)
    }

    // MARK: Which events qualify

    @Test func aMeetingWithOthersBecomesAWindowThatAsks() {
        let result = plan([Self.event("Design review", from: 60, to: 120, attendees: true)])
        #expect(result.count == 1)
        #expect(result[0].decision == .ask)
        #expect(result[0].window.reason == .meeting)
        #expect(result[0].window.minutes == 60)
    }

    @Test func aFocusKeywordQualifiesEvenWithNoAttendees() {
        let result = plan([Self.event("Deep Work: thesis", from: 30, to: 150)])
        #expect(result.first?.window.reason == .focusBlock)
        #expect(plan([Self.event("Dentist", from: 30, to: 90)]).isEmpty, "a personal event with no keyword isn't locked")
    }

    @Test func focusBeatsMeetingWhenBothApply() {
        let result = plan([Self.event("Focus time", from: 60, to: 120, attendees: true)])
        #expect(result.first?.window.reason == .focusBlock)
    }

    @Test func theSwitchesTurnEachKindOff() {
        let meeting = Self.event("Standup", from: 60, to: 90, attendees: true)
        let focus = Self.event("Study", from: 200, to: 260)
        var noMeetings = Self.on
        noMeetings.includeMeetings = false
        #expect(plan([meeting, focus], settings: noMeetings).map(\.window.reason) == [.focusBlock])
        var noFocus = Self.on
        noFocus.includeFocusBlocks = false
        #expect(plan([meeting, focus], settings: noFocus).map(\.window.reason) == [.meeting])
        #expect(plan([meeting, focus], settings: FocusLockSettings(isEnabled: false)).isEmpty)
    }

    @Test func eventsThatCannotOrShouldNotBeLockedAreSkipped() {
        let events = [
            Self.event("Holiday", from: 60, to: 600, attendees: true, allDay: true),
            Self.event("Free slot", from: 60, to: 120, attendees: true, busy: false),
            Self.event("Quick sync", from: 60, to: 70, attendees: true),
            Self.event("All-afternoon workshop", from: 60, to: 60 + 300, attendees: true),
            Self.event("Already started", from: -10, to: 50, attendees: true),
            Self.event("Next week", from: 60 * 24 * 5, to: 60 * 24 * 5 + 60, attendees: true),
        ]
        #expect(plan(events).isEmpty)
    }

    @Test func onlyTheChosenCalendarsAreRead() {
        var settings = Self.on
        settings.calendarIDs = ["work"]
        let events = [
            Self.event("Work meeting", from: 60, to: 120, attendees: true, calendar: "work"),
            Self.event("Book club", from: 200, to: 260, attendees: true, calendar: "home"),
        ]
        #expect(plan(events, settings: settings).map(\.window.title) == ["Work meeting"])
    }

    // MARK: Joining and limits

    @Test func backToBackEventsBecomeOneWindow() {
        let result = plan([
            Self.event("Sync A", from: 60, to: 90, attendees: true),
            Self.event("Sync B", from: 93, to: 150, attendees: true),
        ])
        #expect(result.count == 1)
        #expect(result[0].window.start == Self.at(60))
        #expect(result[0].window.end == Self.at(150))
        #expect(result[0].window.mergedCount == 2)
    }

    @Test func eventsWithARealGapStaySeparate() {
        let result = plan([
            Self.event("Sync A", from: 60, to: 90, attendees: true),
            Self.event("Sync B", from: 120, to: 150, attendees: true),
        ])
        #expect(result.count == 2)
    }

    @Test func aJoinedWindowAsksIfAnyPartAsksAndLocksIfAllDo() {
        var memory = FocusLockPatternMemory()
        let keyA = FocusLockPattern.key(forTitle: "Sync A")
        memory.recordAccept(keyA)
        memory.recordAccept(keyA)
        let events = [
            Self.event("Sync A", from: 60, to: 90, attendees: true),
            Self.event("Sync B", from: 91, to: 120, attendees: true),
        ]
        #expect(plan(events, memory: memory).first?.decision == .ask, "B is still new, so the joined window asks")
        let keyB = FocusLockPattern.key(forTitle: "Sync B")
        memory.recordAccept(keyB)
        memory.recordAccept(keyB)
        #expect(plan(events, memory: memory).first?.decision == .autoLock)
    }

    @Test func atMostEightWindowsSoonestFirst() {
        let events = (0..<12).map { Self.event("Meeting \($0)", from: 60 + $0 * 60, to: 100 + $0 * 60, attendees: true) }
        let result = plan(Array(events.reversed()))
        #expect(result.count == FocusLockSettings.maxWindows)
        #expect(result.map(\.window.start) == result.map(\.window.start).sorted())
        #expect(result.first?.window.title == "Meeting 0")
    }

    // MARK: Learning memory

    @Test func twoYesAnswersLockByItself() {
        var memory = FocusLockPatternMemory()
        #expect(memory.decision(for: "k") == .ask)
        memory.recordAccept("k")
        #expect(memory.decision(for: "k") == .ask)
        memory.recordAccept("k")
        #expect(memory.decision(for: "k") == .autoLock)
    }

    @Test func twoNoAnswersStopAsking() {
        var memory = FocusLockPatternMemory()
        memory.recordDecline("k")
        memory.recordDecline("k")
        #expect(memory.decision(for: "k") == .skip)
        let skipped = plan([Self.event("Weekly 1:1", from: 60, to: 90, attendees: true)],
                           memory: {
                               var m = FocusLockPatternMemory()
                               m.recordDecline(FocusLockPattern.key(forTitle: "Weekly 1:1"))
                               m.recordDecline(FocusLockPattern.key(forTitle: "Weekly 1:1"))
                               return m
                           }())
        #expect(skipped.isEmpty)
    }

    @Test func mixedAnswersKeepAsking() {
        var memory = FocusLockPatternMemory()
        memory.recordAccept("k")
        memory.recordDecline("k")
        #expect(memory.decision(for: "k") == .ask)
        memory.recordAccept("k")
        #expect(memory.decision(for: "k") == .autoLock, "two yes against one no is still a yes")
    }

    @Test func forgettingGoesBackToAsking() {
        var memory = FocusLockPatternMemory()
        memory.recordAccept("k")
        memory.recordAccept("k")
        memory.forget("k")
        #expect(memory.decision(for: "k") == .ask)
    }

    @Test func aPatternKeyIgnoresCaseAndSpacingAndNeverStoresTheTitle() {
        let a = FocusLockPattern.key(forTitle: "Design  Review")
        #expect(a == FocusLockPattern.key(forTitle: "design review"))
        #expect(a == FocusLockPattern.key(forTitle: "  Design Review "))
        #expect(a != FocusLockPattern.key(forTitle: "Design Retro"))
        #expect(!a.contains("design"))
        #expect(FocusLockPattern.key(forTitle: "") == FocusLockPattern.key(forTitle: "   "))
    }

    // MARK: Naming

    @Test func activityNamesRoundTripAndNeverCollideWithLockSchedules() {
        let raw = FocusLockActivity.rawName(windowID: "abc-123")
        #expect(FocusLockActivity.windowID(fromRawName: raw) == "abc-123")
        #expect(FocusLockActivity.isFocusActivity(raw))
        #expect(!FocusLockActivity.isFocusActivity("com.zano.app.spend"))
        #expect(!FocusLockActivity.isFocusActivity(FocusLockActivity.prefix))
        #expect(LockScheduleActivity.lockSetID(fromRawName: raw) == nil, "a lock schedule must never claim a focus window")
        let setID = UUID()
        #expect(!FocusLockActivity.isFocusActivity(LockScheduleActivity.rawName(lockSetID: setID, weekday: 2)))
    }

    @Test func windowIDsAreStablePerEventAndStart() {
        let one = FocusLockPlanner.windowID(patternKey: "k", start: Self.at(60))
        #expect(one == FocusLockPlanner.windowID(patternKey: "k", start: Self.at(60)))
        #expect(one != FocusLockPlanner.windowID(patternKey: "k", start: Self.at(61)))
    }

    // MARK: Saved state

    @Test func storeRoundTripsAndEndingEarlyCountsAsANo() {
        let savedSettings = FocusLockStore.settings
        let savedMemory = FocusLockStore.memory
        let savedArmed = FocusLockStore.armedWindows
        defer {
            FocusLockStore.settings = savedSettings
            FocusLockStore.memory = savedMemory
            FocusLockStore.armedWindows = savedArmed
        }
        let key = FocusLockPattern.key(forTitle: "Standup")
        let window = FocusLockWindow(id: "w1", start: Self.at(60), end: Self.at(90), reason: .meeting, patternKey: key, title: "Standup")
        FocusLockStore.memory = FocusLockPatternMemory()
        FocusLockStore.armedWindows = [window]
        FocusLockStore.settings = FocusLockSettings(isEnabled: true)

        #expect(FocusLockStore.settings.isEnabled)
        #expect(FocusLockStore.armedWindow(forActivityRawName: FocusLockActivity.rawName(windowID: "w1")) == window)
        #expect(FocusLockStore.activeWindow(at: Self.at(70)) == window)
        #expect(FocusLockStore.activeWindow(at: Self.at(100)) == nil)

        FocusLockStore.recordEndedEarly(activityRawName: FocusLockActivity.rawName(windowID: "w1"))
        FocusLockStore.recordEndedEarly(activityRawName: FocusLockActivity.rawName(windowID: "w1"))
        #expect(FocusLockStore.memory.decision(for: key) == .skip, "ending the lock early twice means don't lock for it again")
    }
}
