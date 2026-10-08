import Testing
import Foundation
@testable import Core

@Suite("Family page — availability, portrait, lists, buddy sync")
struct FamilyHubTests {
    private let home = UUID()
    private let me = UUID()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func member(_ name: String, id: UUID = UUID(), joined: Double? = nil, buddy: Buddy? = nil, outfit: BuddyOutfit? = nil) -> HouseholdMember {
        HouseholdMember(
            householdId: home, userId: id, displayName: name, joinedAt: joined.map { now.addingTimeInterval($0) },
            buddy: buddy?.rawValue, outfit: outfit
        )
    }

    private func entitlement(_ ownership: SubscriptionOwnership, active: Bool = true) -> ProEntitlementInfo {
        ProEntitlementInfo(isActive: active, isTrial: false, expirationDate: nil, willRenew: true, ownership: ownership)
    }

    // MARK: Availability

    @Test func visibleWhenHouseholdIsLive() {
        #expect(FamilyHubAvailability.isVisible(householdLive: true, entitlement: nil, familySharingEnabled: false))
    }

    @Test func visibleForAFamilySharedPlanWithoutHousehold() {
        #expect(FamilyHubAvailability.isVisible(householdLive: false, entitlement: entitlement(.familyShared), familySharingEnabled: false))
    }

    @Test func theBuyerSeesItOnlyOnceFamilySharingIsOn() {
        #expect(!FamilyHubAvailability.isVisible(householdLive: false, entitlement: entitlement(.purchased), familySharingEnabled: false))
        #expect(FamilyHubAvailability.isVisible(householdLive: false, entitlement: entitlement(.purchased), familySharingEnabled: true))
    }

    @Test func hiddenWithNoHouseholdAndNoFamilyPlan() {
        #expect(!FamilyHubAvailability.isVisible(householdLive: false, entitlement: nil, familySharingEnabled: true))
        #expect(!FamilyHubAvailability.isVisible(householdLive: false, entitlement: entitlement(.familyShared, active: false), familySharingEnabled: true))
    }

    @Test func planStatusWording() {
        #expect(FamilyHubAvailability.planStatus(entitlement: entitlement(.familyShared), familySharingEnabled: false) == .sharedWithYou)
        #expect(FamilyHubAvailability.planStatus(entitlement: entitlement(.purchased), familySharingEnabled: true) == .sharingWithFamily)
        #expect(FamilyHubAvailability.planStatus(entitlement: entitlement(.purchased), familySharingEnabled: false) == .yours)
        #expect(FamilyHubAvailability.planStatus(entitlement: nil, familySharingEnabled: true) == .noPlan)
    }

    // MARK: Portrait

    @Test func everyoneStandsInJoinOrder() {
        let list = [member("Late", joined: 300), member("First", joined: 0), member("Unknown"), member("Middle", joined: 100)]
        #expect(FamilyPortrait.ordered(list).map(\.displayName) == ["First", "Middle", "Late", "Unknown"])
    }

    @Test func upToFourStandInOneRow() {
        let four = (0..<4).map { member("M\($0)", joined: Double($0)) }
        #expect(FamilyPortrait.rows(four).map(\.count) == [4])
        #expect(FamilyPortrait.rows([]).isEmpty)
    }

    @Test func aBigFamilyStandsInTwoRowsBackRowFirst() {
        let seven = (0..<7).map { member("M\($0)", joined: Double($0)) }
        let rows = FamilyPortrait.rows(seven)
        #expect(rows.map(\.count) == [3, 4])
        #expect(rows[0].first?.displayName == "M0")
        #expect(rows[1].last?.displayName == "M6")
    }

    @Test func spritesShrinkAsTheFamilyGrows() {
        #expect(FamilyPortrait.spriteSize(count: 1) == 96)
        #expect(FamilyPortrait.spriteSize(count: 3) == 80)
        #expect(FamilyPortrait.spriteSize(count: 4) == 64)
        #expect(FamilyPortrait.spriteSize(count: 6) == 64)
        #expect(FamilyPortrait.spriteSize(count: 6, isBackRow: true) == 48)
    }

    @Test func eventsSharedWithCountsOnlyMineThatTheyCanSee() {
        let sam = UUID(), alex = UUID()
        let start = now.addingTimeInterval(3_600)
        let events = [
            HouseholdEvent(householdId: home, createdBy: me, title: "Everyone", startsAt: start, endsAt: start),
            HouseholdEvent(householdId: home, createdBy: me, title: "Sam only", startsAt: start, endsAt: start, visibility: .members, audience: [sam]),
            HouseholdEvent(householdId: home, createdBy: me, title: "Alex only", startsAt: start, endsAt: start, visibility: .members, audience: [alex]),
            HouseholdEvent(householdId: home, createdBy: sam, title: "Sam's", startsAt: start, endsAt: start),
        ]
        #expect(FamilyPortrait.eventsSharedWith(sam, events: events, me: me) == 2)
        #expect(FamilyPortrait.eventsSharedWith(me, events: events, me: me) == 0)
    }

    // MARK: Lists

    @Test func choresAreMineThenUpForGrabs() {
        let other = UUID()
        let tasks = [
            HouseholdTask(id: UUID(), householdId: home, title: "Theirs", assigneeId: other),
            HouseholdTask(id: UUID(), householdId: home, title: "Free"),
            HouseholdTask(id: UUID(), householdId: home, title: "Mine", assigneeId: me),
            HouseholdTask(id: UUID(), householdId: home, title: "Done", assigneeId: me, doneBy: me, doneAt: now),
        ]
        #expect(FamilyHubLists.chores(tasks: tasks, me: me, now: now).map(\.title) == ["Mine", "Free"])
    }

    @Test func nextQuietTimePrefersTheOneRunningThenTheSoonest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        let lunch = HouseholdQuietTime(householdId: home, name: "Lunch", startMinute: 11 * 60 + 30, endMinute: 12 * 60 + 30, weekdays: [1, 2, 3, 4, 5, 6, 7])
        let dinner = HouseholdQuietTime(householdId: home, name: "Dinner", startMinute: 18 * 60, endMinute: 19 * 60, weekdays: [1, 2, 3, 4, 5, 6, 7])
        let running = FamilyHubLists.nextQuietTime(windows: [dinner, lunch], optIns: [HouseholdQuietTimeOptIn(windowID: lunch.id)], now: noon, calendar: cal)
        #expect(running?.window.name == "Lunch")
        #expect(running?.isRunning == true)
        #expect(running?.isJoined == true)
        let next = FamilyHubLists.nextQuietTime(windows: [dinner], optIns: [], now: noon, calendar: cal)
        #expect(next?.window.name == "Dinner")
        #expect(next?.isRunning == false)
        #expect(next?.isJoined == false)
        #expect(FamilyHubLists.nextQuietTime(windows: [], optIns: [], now: noon, calendar: cal) == nil)
    }

    // MARK: Buddy on the household row

    @Test func memberBuddyDecodesAndFallsBackToTheDefault() throws {
        let json = #"[{"household_id":"\#(home)","user_id":"\#(me)","display_name":"Alex","joined_at":"2026-10-08T10:00:00+00:00","buddy":"lox","outfit":{"hat":"hatWizard"}},{"household_id":"\#(home)","user_id":"\#(UUID())","display_name":"Sam","joined_at":null,"buddy":null,"outfit":{"hat":"someHatFromTheFuture"}},{"household_id":"\#(home)","user_id":"\#(UUID())","display_name":"Old row"}]"#
        let members = try FamilyJSON.decoder.decode([HouseholdMember].self, from: Data(json.utf8))
        #expect(members.count == 3)
        #expect(members[0].buddyChoice == .lox)
        #expect(members[0].outfit?.hat == .hatWizard)
        #expect(members[1].buddyChoice == .default)
        #expect(members[1].outfit == nil)
        #expect(members[2].buddy == nil)
    }

    @Test func syncIsNeededWhenMyRowDiffers() {
        let outfit = BuddyOutfit(hat: .hatWizard)
        #expect(HouseholdBuddySync.needsSync(member: member("Me", id: me), buddy: .stash, outfit: BuddyOutfit()))
        #expect(HouseholdBuddySync.needsSync(member: member("Me", id: me, buddy: .lox), buddy: .zib, outfit: BuddyOutfit()))
        #expect(HouseholdBuddySync.needsSync(member: member("Me", id: me, buddy: .lox), buddy: .lox, outfit: outfit))
        #expect(!HouseholdBuddySync.needsSync(member: member("Me", id: me, buddy: .lox, outfit: outfit), buddy: .lox, outfit: outfit))
        #expect(!HouseholdBuddySync.needsSync(member: nil, buddy: .lox, outfit: outfit))
    }

    @Test func signatureChangesWithBuddyOrOutfit() {
        let bare = HouseholdBuddySync.signature(buddy: .lox, outfit: BuddyOutfit())
        #expect(bare == HouseholdBuddySync.signature(buddy: .lox, outfit: BuddyOutfit()))
        #expect(bare != HouseholdBuddySync.signature(buddy: .zib, outfit: BuddyOutfit()))
        #expect(bare != HouseholdBuddySync.signature(buddy: .lox, outfit: BuddyOutfit(hat: .hatWizard)))
    }

    @Test func portraitLabelNamesThePersonAndTheirBuddy() {
        #expect(Copy.familyHub.memberLabel(name: "Sam", buddy: .lox) == "Sam, \(Copy.buddy.name(.lox))")
    }
}
