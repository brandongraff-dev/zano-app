import Testing
import Foundation
@testable import Core

@Suite("Family Link")
struct FamilyTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test("an unopened proof can be opened once, an opened one cannot")
    func proofClock() {
        let fresh = FamilyProofRecord(id: UUID(), taskId: UUID(), firstOpenedAt: nil, expiresAt: now.addingTimeInterval(3_600))
        #expect(FamilyProofClock.canOpen(fresh, now: now))
        let opened = FamilyProofRecord(id: UUID(), taskId: UUID(), firstOpenedAt: now, expiresAt: now.addingTimeInterval(600))
        #expect(!FamilyProofClock.canOpen(opened, now: now))
        #expect(FamilyProofClock.state(of: opened, now: now) == .opened(deletedAt: now.addingTimeInterval(600)))
        #expect(FamilyProofClock.state(of: opened, now: now.addingTimeInterval(601)) == .gone)
    }

    @Test("deletion times: 10 minutes after the open, 24 hours if never opened")
    func deletionTimes() {
        #expect(FamilyProofClock.deletionTime(openedAt: now) == now.addingTimeInterval(600))
        #expect(FamilyProofClock.deletionTime(uploadedAt: now) == now.addingTimeInterval(86_400))
    }

    @Test("Postgres timestamps with micro-seconds decode")
    func dates() throws {
        let json = #"{"id":"\#(UUID())","parent_id":"\#(UUID())","teen_id":null,"invite_code":"ABCD2345","status":"invited","created_at":"2026-10-05T22:00:00.123456+00:00","accepted_at":null}"#
        let link = try FamilyJSON.decoder.decode(FamilyLink.self, from: Data(json.utf8))
        #expect(link.inviteCode == "ABCD2345")
        #expect(link.status == .invited)
        #expect(link.createdAt != nil)
        let plain = #"{"id":"\#(UUID())","parent_id":"\#(UUID())","teen_id":null,"invite_code":"X","status":"active","created_at":"2026-10-05T22:00:00+00:00","accepted_at":null}"#
        #expect(try FamilyJSON.decoder.decode(FamilyLink.self, from: Data(plain.utf8)).createdAt != nil)
    }

    @Test("the Family tasks goal is done only when everything due today is approved")
    func taskGoal() {
        let link = UUID()
        func task(_ status: FamilyTaskStatus) -> FamilyTask {
            FamilyTask(id: UUID(), linkId: link, title: "t", dueAt: now, status: status)
        }
        #expect(!FamilyTaskGoal.isTodayDone(tasks: [], now: now, calendar: utc))
        #expect(FamilyTaskGoal.isTodayDone(tasks: [task(.approved)], now: now, calendar: utc))
        #expect(!FamilyTaskGoal.isTodayDone(tasks: [task(.approved), task(.submitted)], now: now, calendar: utc))
        let tomorrow = FamilyTask(id: UUID(), linkId: link, title: "t", dueAt: now.addingTimeInterval(86_400), status: .open)
        #expect(FamilyTaskGoal.isTodayDone(tasks: [task(.approved), tomorrow], now: now, calendar: utc))
    }

    @Test("errors map to calm copy")
    func errors() {
        #expect(Copy.family.error(FamilyLinkError.server(code: "invalid_invite")) == Copy.family.invalidInvite)
        #expect(Copy.family.error(FamilyLinkError.gone) == Copy.family.alreadyOpened)
        #expect(Copy.family.error(FamilyLinkError.http(status: 500)) == Copy.family.genericError)
    }
}
