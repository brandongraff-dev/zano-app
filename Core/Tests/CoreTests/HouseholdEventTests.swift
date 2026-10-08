import Testing
import Foundation
@testable import Core

@Suite("Household calendar — visibility, audience, merge, times")
struct HouseholdEventTests {
    private let me = UUID()
    private let sam = UUID()
    private let alex = UUID()
    private let stranger = UUID()
    private let home = UUID()

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private var members: [HouseholdMember] {
        [me, sam, alex].map { HouseholdMember(householdId: home, userId: $0, displayName: "M") }
    }

    private func event(
        _ title: String, by creator: UUID?, _ visibility: HouseholdEventVisibility = .household,
        audience: [UUID] = [], start: Date? = nil, end: Date? = nil
    ) -> HouseholdEvent {
        let s = start ?? date(2026, 10, 9, 18)
        return HouseholdEvent(
            householdId: home, createdBy: creator, title: title, startsAt: s, endsAt: end ?? s.addingTimeInterval(3_600),
            visibility: visibility, audience: audience
        )
    }

    // MARK: Visibility (the client-side mirror of the SELECT policy)

    @Test func householdWideEventsAreVisibleToEveryMember() {
        #expect(HouseholdEventRules.canSee(event("Dinner", by: sam), me: me))
        #expect(HouseholdEventRules.canSee(event("Dinner", by: sam), me: nil))
    }

    @Test func membersOnlyEventsAreVisibleOnlyToTheCreatorAndTheAudience() {
        let surprise = event("Surprise party", by: sam, .members, audience: [alex])
        #expect(!HouseholdEventRules.canSee(surprise, me: me))
        #expect(HouseholdEventRules.canSee(surprise, me: alex))
        #expect(HouseholdEventRules.canSee(surprise, me: sam))
        #expect(!HouseholdEventRules.canSee(surprise, me: nil))
    }

    @Test func myOwnEventIsVisibleEvenWithAnEmptiedAudience() {
        // Everyone it was shared with left: the server leaves it to the creator only.
        let orphan = event("Lunch", by: me, .members, audience: [])
        #expect(HouseholdEventRules.canSee(orphan, me: me))
        #expect(!HouseholdEventRules.canSee(orphan, me: sam))
    }

    @Test func visibleDropsWhatTheServerShouldNotHaveSent() {
        let list = [
            event("Everyone", by: sam),
            event("Not for me", by: sam, .members, audience: [alex]),
            event("For me", by: alex, .members, audience: [me]),
            event("Mine", by: me, .members, audience: [sam]),
        ]
        #expect(HouseholdEventRules.visible(list, me: me).map(\.title) == ["Everyone", "For me", "Mine"])
    }

    @Test func onlyTheCreatorEdits() {
        let mine = event("Mine", by: me)
        #expect(HouseholdEventRules.canEdit(mine, me: me))
        #expect(!HouseholdEventRules.canEdit(mine, me: sam))
        #expect(!HouseholdEventRules.canEdit(mine, me: nil))
    }

    @Test func anUnknownVisibilityDecodesAsTheNarrowestOne() throws {
        let json = #"{"id":"\#(UUID())","household_id":"\#(home)","created_by":"\#(sam)","title":"X","notes":null,"starts_at":"2026-10-09T18:00:00+00:00","ends_at":"2026-10-09T19:00:00.123456+00:00","all_day":false,"visibility":"everyone_on_earth","audience":["\#(alex)"],"updated_at":null}"#
        let decoded = try FamilyJSON.decoder.decode(HouseholdEvent.self, from: Data(json.utf8))
        #expect(decoded.visibility == .members)
        #expect(decoded.notes == "")
        #expect(!HouseholdEventRules.canSee(decoded, me: me))
    }

    @Test func serverRowsDecode() throws {
        let json = #"[{"id":"\#(UUID())","household_id":"\#(home)","created_by":"\#(me)","title":"Soccer","notes":"Bring water","starts_at":"2026-10-09T18:00:00+00:00","ends_at":"2026-10-09T19:30:00+00:00","all_day":false,"visibility":"members","audience":["\#(sam)"],"created_at":"2026-10-08T10:00:00+00:00","updated_at":"2026-10-08T10:00:00+00:00"}]"#
        let events = try FamilyJSON.decoder.decode([HouseholdEvent].self, from: Data(json.utf8))
        #expect(events.count == 1)
        #expect(events[0].audience == [sam])
        #expect(events[0].visibility == .members)
        #expect(events[0].endsAt.timeIntervalSince(events[0].startsAt) == 5_400)
    }

    // MARK: Audience

    @Test func audienceDropsTheCreatorAndRepeats() {
        let result = HouseholdEventRules.normalizedAudience([sam, me, sam, alex], creator: me, members: members)
        let expected = [sam, alex].sorted { $0.uuidString < $1.uuidString }
        #expect(result == .success(expected))
    }

    @Test func audienceMustBeHouseholdMembers() {
        #expect(HouseholdEventRules.normalizedAudience([sam, stranger], creator: me, members: members) == .failure(.notAMember))
    }

    @Test func choosePeopleNeedsSomeoneOtherThanMe() {
        #expect(HouseholdEventRules.normalizedAudience([], creator: me, members: members) == .failure(.empty))
        #expect(HouseholdEventRules.normalizedAudience([me], creator: me, members: members) == .failure(.empty))
    }

    @Test func audienceIsCappedAtSevenOthers() {
        let many = (0..<8).map { _ in UUID() }
        let all = many.map { HouseholdMember(householdId: home, userId: $0, displayName: "M") } + members
        #expect(HouseholdEventRules.normalizedAudience(many, creator: me, members: all) == .failure(.tooMany))
    }

    // MARK: Merge

    @Test func mergeCombinesAllThreeSourcesInTimeOrder() {
        let device = [PlannerEvent(id: "d", title: "Standup", start: date(2026, 10, 9, 9), end: date(2026, 10, 9, 9, 15), isAllDay: false)]
        let mine = [PlannerPrivateEvent(title: "Therapy", start: date(2026, 10, 9, 12), end: date(2026, 10, 9, 13))]
        let shared = [event("Soccer", by: sam, start: date(2026, 10, 9, 8))]
        let merged = PlannerAgenda.merge(
            device: device, privateEvents: mine, household: shared, me: me, householdName: "Home",
            filter: PlannerCalendarFilter(), includeHousehold: true
        )
        #expect(merged.map(\.title) == ["Soccer", "Standup", "Therapy"])
        #expect(merged[0].calendarTitle == "Home")
        #expect(merged[1].origin == .device)
        #expect(merged[2].origin == .onlyMe(id: mine[0].id))
        #expect(merged[2].colorRGB == PlannerEvent.onlyMeColorRGB)
        if case .household(_, let createdBy, let visibility, _) = merged[0].origin {
            #expect(createdBy == sam)
            #expect(visibility == .household)
        } else {
            Issue.record("expected a household origin")
        }
    }

    @Test func mergeFiltersOthersPrivateEventsDefensively() {
        let shared = [event("Not for me", by: sam, .members, audience: [alex]), event("Everyone", by: sam)]
        let merged = PlannerAgenda.merge(
            device: [], privateEvents: [], household: shared, me: me, householdName: "Home",
            filter: PlannerCalendarFilter(), includeHousehold: true
        )
        #expect(merged.map(\.title) == ["Everyone"])
    }

    @Test func mergeLeavesTheFamilyCalendarOutWhenHiddenOrNotLive() {
        let shared = [event("Soccer", by: sam)]
        let mine = [PlannerPrivateEvent(title: "Private", start: date(2026, 10, 9, 12), end: date(2026, 10, 9, 13))]
        let notLive = PlannerAgenda.merge(
            device: [], privateEvents: mine, household: shared, me: me, householdName: "",
            filter: PlannerCalendarFilter(), includeHousehold: false
        )
        #expect(notLive.map(\.title) == ["Private"])
        let hidden = PlannerAgenda.merge(
            device: [], privateEvents: mine, household: shared, me: me, householdName: "",
            filter: PlannerCalendarFilter(showsFamily: false), includeHousehold: true
        )
        #expect(hidden.map(\.title) == ["Private"])
    }

    @Test func mergeCanHideTheIPhoneCalendarsButNeverPrivateEvents() {
        let device = [PlannerEvent(id: "d", title: "Standup", start: date(2026, 10, 9, 9), end: date(2026, 10, 9, 10), isAllDay: false)]
        let mine = [PlannerPrivateEvent(title: "Private", start: date(2026, 10, 9, 12), end: date(2026, 10, 9, 13))]
        let merged = PlannerAgenda.merge(
            device: device, privateEvents: mine, household: [], me: me, householdName: "",
            filter: PlannerCalendarFilter(showsFamily: true, showsDeviceCalendars: false), includeHousehold: true
        )
        #expect(merged.map(\.title) == ["Private"])
    }

    @Test func mergedEventsFeedTheAgendaAndMarkers() {
        let mine = [PlannerPrivateEvent(title: "Private", start: date(2026, 10, 9, 12), end: date(2026, 10, 9, 13))]
        let trip = HouseholdEvent(
            householdId: home, createdBy: sam, title: "Trip", startsAt: date(2026, 10, 10), endsAt: date(2026, 10, 11, 23, 59, 59), allDay: true
        )
        let merged = PlannerAgenda.merge(
            device: [], privateEvents: mine, household: [trip], me: me, householdName: "",
            filter: PlannerCalendarFilter(), includeHousehold: true
        )
        let agenda = PlannerAgenda.agenda(for: date(2026, 10, 11), events: merged, tasks: [], now: date(2026, 10, 9), calendar: calendar)
        #expect(agenda.allDay.map(\.title) == ["Trip"])
        let marks = PlannerAgenda.markers(for: [date(2026, 10, 9)], events: merged, tasks: [], calendar: calendar)
        #expect(marks[calendar.startOfDay(for: date(2026, 10, 9))]?.hasEvents == true)
    }

    @Test func alertsCoverPrivateAndSharedEventsWithTheSameRule() {
        let now = date(2026, 10, 9, 8)
        let mine = [PlannerPrivateEvent(title: "Private", start: date(2026, 10, 9, 12), end: date(2026, 10, 9, 13))]
        let merged = PlannerAgenda.merge(
            device: [], privateEvents: mine, household: [event("Soccer", by: sam, start: date(2026, 10, 9, 18))],
            me: me, householdName: "", filter: PlannerCalendarFilter(), includeHousehold: true
        )
        let on = PlannerReminders.plan(tasks: [], events: merged, settings: PlannerSettings(eventAlerts: true, eventAlertLeadMinutes: 10), now: now, calendar: calendar)
        #expect(on.count == 2)
        #expect(on.allSatisfy { $0.identifier.hasPrefix(PlannerReminders.eventPrefix) })
        let off = PlannerReminders.plan(tasks: [], events: merged, settings: PlannerSettings(eventAlerts: false), now: now, calendar: calendar)
        #expect(off.isEmpty)
    }

    // MARK: Times

    @Test func allDayRunsFromMidnightToTheLastSecondOfTheLastDay() {
        let times = PlannerEventTimes.normalized(start: date(2026, 10, 9, 15), end: date(2026, 10, 10, 9), allDay: true, calendar: calendar)
        #expect(times.start == date(2026, 10, 9))
        #expect(times.end == date(2026, 10, 10, 23, 59, 59))
        let timed = PlannerEventTimes.normalized(start: date(2026, 10, 9, 15), end: date(2026, 10, 9, 16), allDay: false, calendar: calendar)
        #expect(timed.start == date(2026, 10, 9, 15))
        #expect(timed.end == date(2026, 10, 9, 16))
    }

    @Test func validationCatchesTheUsualMistakes() {
        #expect(PlannerEventTimes.validate(title: "  ", start: date(2026, 10, 9), end: date(2026, 10, 9)) == .emptyTitle)
        #expect(PlannerEventTimes.validate(title: String(repeating: "a", count: 121), start: date(2026, 10, 9), end: date(2026, 10, 9)) == .titleTooLong)
        #expect(PlannerEventTimes.validate(title: "Ok", start: date(2026, 10, 9, 10), end: date(2026, 10, 9, 9)) == .endsBeforeStart)
        #expect(PlannerEventTimes.validate(title: "Ok", start: date(2026, 10, 9, 9), end: date(2026, 10, 9, 10)) == nil)
    }

    @Test func upcomingIsSoonestFirstAndSkipsWhatEnded() {
        let now = date(2026, 10, 9, 12)
        let list = [
            event("Ended", by: sam, start: date(2026, 10, 9, 8)),
            event("Later", by: sam, start: date(2026, 10, 12, 8)),
            event("Under way", by: sam, start: date(2026, 10, 9, 11, 30)),
            event("Hidden", by: sam, .members, audience: [alex], start: date(2026, 10, 10, 8)),
            event("Tomorrow", by: sam, start: date(2026, 10, 10, 9)),
        ]
        #expect(HouseholdEventRules.upcoming(list, me: me, now: now, limit: 3).map(\.title) == ["Under way", "Tomorrow", "Later"])
    }

    @Test func privateEventsPruneLongEndedOnes() {
        let now = date(2026, 10, 9)
        let old = PlannerPrivateEvent(title: "Old", start: date(2026, 6, 1), end: date(2026, 6, 1, 1))
        let recent = PlannerPrivateEvent(title: "Recent", start: date(2026, 10, 1), end: date(2026, 10, 1, 1))
        #expect(PlannerStore.prunePrivateEvents([recent, old], now: now).map(\.title) == ["Recent"])
    }

    @Test func calendarErrorsMapToCalmCopy() {
        #expect(Copy.household.error(FamilyLinkError.server(code: "too_many_events")) == Copy.household.eventsTooMany)
        #expect(Copy.household.error(FamilyLinkError.server(code: "empty_audience")) == Copy.planner.pickSomeone)
        #expect(Copy.household.error(FamilyLinkError.server(code: "bad_audience")) == Copy.household.eventsBadAudience)
    }

    @Test func visibleToReadsNaturally() {
        #expect(Copy.planner.visibleTo([]) == "You")
        #expect(Copy.planner.visibleTo(["Sam"]) == "You and Sam")
        #expect(Copy.planner.visibleTo(["Sam", "Alex"]) == "You, Sam and Alex")
    }
}
