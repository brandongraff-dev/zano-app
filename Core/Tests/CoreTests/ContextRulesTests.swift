// ContextRulesTests.swift
// Core / Tests / CoreTests
//
// Coverage for the smart unlock rules (session 19; docs/spec.md §5.26): when a rule is active, what
// makes one invalid, the cap of three, the "you keep ending locks early about now" suggestion, and
// the activity names (which must not collide with focus windows or lock schedules). The shield
// subtraction itself needs real FamilyControls tokens (device only), so it is not unit-tested here.
// `ContextRuleStore` reads the App Group defaults (no test seam): its test saves and restores them.

import Testing
import Foundation
@testable import Core

@Suite("Smart unlock rules — windows, validity, suggestion, naming", .serialized)
struct ContextRulesTests {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A date on the given weekday (2 = Monday ... 6 = Friday, 1 = Sunday) at hour:minute, `week` weeks
    /// after Sunday 6 September 2026 (negative weeks go back).
    private static func date(weekday: Int, hour: Int, minute: Int = 0, week: Int = 0) -> Date {
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: (weekday - 1) + week * 7, to: sunday)!
    }

    private let setID = UUID()

    // MARK: Active window

    @Test func aWeekdayRuleIsActiveInsideItsHoursOnly() {
        let rule = ContextRule(name: "Work", lockSetID: setID)
        #expect(rule.isActive(at: Self.date(weekday: 3, hour: 10), calendar: Self.calendar))
        #expect(rule.isActive(at: Self.date(weekday: 3, hour: 9), calendar: Self.calendar), "the start is included")
        #expect(!rule.isActive(at: Self.date(weekday: 3, hour: 17), calendar: Self.calendar), "the end is not")
        #expect(!rule.isActive(at: Self.date(weekday: 3, hour: 8, minute: 59), calendar: Self.calendar))
        #expect(!rule.isActive(at: Self.date(weekday: 1, hour: 10), calendar: Self.calendar), "Sunday isn't a weekday")
    }

    @Test func aTurnedOffOrInvalidRuleIsNeverActive() {
        var off = ContextRule(name: "Work", lockSetID: setID)
        off.isEnabled = false
        #expect(!off.isActive(at: Self.date(weekday: 3, hour: 10), calendar: Self.calendar))
        let backwards = ContextRule(name: "Work", lockSetID: setID, startMinuteOfDay: 17 * 60, endMinuteOfDay: 9 * 60)
        #expect(!backwards.isValid)
        #expect(!backwards.isActive(at: Self.date(weekday: 3, hour: 10), calendar: Self.calendar))
    }

    @Test func validityNeedsDaysAndFifteenMinutes() {
        #expect(ContextRule(name: "x", lockSetID: setID).isValid)
        #expect(!ContextRule(name: "x", lockSetID: setID, weekdays: []).isValid)
        #expect(!ContextRule(name: "x", lockSetID: setID, weekdays: [8]).isValid)
        #expect(!ContextRule(name: "x", lockSetID: setID, startMinuteOfDay: 600, endMinuteOfDay: 610).isValid)
        #expect(ContextRule(name: "x", lockSetID: setID, startMinuteOfDay: 600, endMinuteOfDay: 615).isValid)
        #expect(!ContextRule(name: "x", lockSetID: setID, startMinuteOfDay: 600, endMinuteOfDay: 1_440).isValid)
    }

    // MARK: Store

    @Test func theStoreKeepsAtMostThreeRules() {
        let saved = ContextRuleStore.rules
        defer { ContextRuleStore.rules = saved }
        ContextRuleStore.rules = (0..<5).map { ContextRule(name: "Rule \($0)", lockSetID: setID) }
        #expect(ContextRuleStore.rules.count == ContextRule.maxRules)
        #expect(ContextRuleStore.rules.first?.name == "Rule 0")
        ContextRuleStore.rules = []
        #expect(ContextRuleStore.rules.isEmpty)
    }

    // MARK: Learned suggestion

    @Test func threeTuesdayUnlocksAroundTheSameTimeSuggestARule() {
        let now = Self.date(weekday: 6, hour: 12, week: 3)
        let times = [
            Self.date(weekday: 3, hour: 9, minute: 5, week: 0),
            Self.date(weekday: 3, hour: 9, minute: 40, week: 1),
            Self.date(weekday: 3, hour: 10, minute: 10, week: 2),
        ]
        let suggestion = ContextRuleSuggester.suggestion(emergencyUnlockTimes: times, now: now, calendar: Self.calendar)
        #expect(suggestion?.weekday == 3)
        #expect(suggestion?.occurrences == 3)
        #expect(suggestion?.startMinuteOfDay == 9 * 60)
        #expect((suggestion?.endMinuteOfDay ?? 0) >= 11 * 60, "the window covers the last unlock")
    }

    @Test func spreadOutOrOldUnlocksSuggestNothing() {
        let now = Self.date(weekday: 6, hour: 12, week: 3)
        let spread = [
            Self.date(weekday: 3, hour: 7, week: 0), Self.date(weekday: 3, hour: 12, week: 1), Self.date(weekday: 3, hour: 20, week: 2),
        ]
        #expect(ContextRuleSuggester.suggestion(emergencyUnlockTimes: spread, now: now, calendar: Self.calendar) == nil)
        let otherDays = [
            Self.date(weekday: 2, hour: 9, week: 0), Self.date(weekday: 3, hour: 9, week: 1), Self.date(weekday: 4, hour: 9, week: 2),
        ]
        #expect(ContextRuleSuggester.suggestion(emergencyUnlockTimes: otherDays, now: now, calendar: Self.calendar) == nil)
        let old = [
            Self.date(weekday: 3, hour: 9, week: -8), Self.date(weekday: 3, hour: 9, week: -9), Self.date(weekday: 3, hour: 9, week: -10),
        ]
        #expect(ContextRuleSuggester.suggestion(emergencyUnlockTimes: old, now: now, calendar: Self.calendar) == nil)
        #expect(ContextRuleSuggester.suggestion(emergencyUnlockTimes: [], now: now, calendar: Self.calendar) == nil)
    }

    // MARK: Naming

    @Test func contextActivityNamesDoNotCollideWithOtherActivities() {
        let raw = ContextRuleActivity.rawName(ruleID: setID)
        #expect(ContextRuleActivity.isContextActivity(raw))
        #expect(!FocusLockActivity.isFocusActivity(raw))
        #expect(LockScheduleActivity.lockSetID(fromRawName: raw) == nil)
        #expect(!ContextRuleActivity.isContextActivity("com.zano.app.spend"))
        #expect(!ContextRuleActivity.isContextActivity(FocusLockActivity.rawName(windowID: "abc")))
    }

    @Test func noRulesKeepNothingOpen() {
        let saved = ContextRuleStore.rules
        defer { ContextRuleStore.rules = saved }
        ContextRuleStore.rules = []
        #expect(ContextRules.exemptTokens(now: .now).isEmpty)
    }
}
