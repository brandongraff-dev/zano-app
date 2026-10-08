import Testing
import Foundation
@testable import Core

@Suite("Household — board, JWT id, JSON, sharing text")
struct HouseholdTests {
    private let me = UUID()
    private let other = UUID()
    private let home = UUID()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func task(_ title: String, due: Double? = nil, assignee: UUID? = nil, done: Double? = nil, created: Double = 0) -> HouseholdTask {
        HouseholdTask(
            id: UUID(), householdId: home, title: title,
            dueAt: due.map { now.addingTimeInterval($0) }, assigneeId: assignee,
            createdAt: now.addingTimeInterval(created),
            doneBy: done == nil ? nil : other, doneAt: done.map { now.addingTimeInterval($0) }
        )
    }

    @Test func boardGroupsByWhoHasIt() {
        let tasks = [
            task("Mine", assignee: me),
            task("Free"),
            task("Theirs", assignee: other),
            task("Finished", assignee: other, done: -3_600),
            task("Long ago", done: -10 * 86_400),
        ]
        let s = HouseholdBoard.sections(tasks: tasks, me: me, now: now)
        #expect(s.mine.map(\.title) == ["Mine"])
        #expect(s.unassigned.map(\.title) == ["Free"])
        #expect(s.others.map(\.title) == ["Theirs"])
        #expect(s.doneRecently.map(\.title) == ["Finished"])
        #expect(s.openCount == 3)
    }

    @Test func openTasksSortByDueThenAge() {
        let tasks = [
            task("No date old", created: -100),
            task("Later", due: 7_200),
            task("Soon", due: 3_600),
            task("No date new", created: -10),
        ]
        let s = HouseholdBoard.sections(tasks: tasks, me: me, now: now)
        #expect(s.unassigned.map(\.title) == ["Soon", "Later", "No date old", "No date new"])
    }

    @Test func nameForShowsYouAndMembers() {
        let members = [HouseholdMember(householdId: home, userId: other, displayName: "Sam")]
        #expect(HouseholdBoard.name(for: me, members: members, me: me) == Copy.household.you)
        #expect(HouseholdBoard.name(for: other, members: members, me: me) == "Sam")
        #expect(HouseholdBoard.name(for: nil, members: members, me: me) == nil)
    }

    @Test func onlyMyOpenDatedTasksBecomeReminders() {
        let tasks = [
            task("Mine dated", due: 3_600, assignee: me),
            task("Mine undated", assignee: me),
            task("Theirs", due: 3_600, assignee: other),
            task("Mine done", due: 3_600, assignee: me, done: -60),
        ]
        let reminders = HouseholdBoard.reminderTasks(from: tasks, me: me)
        #expect(reminders.map(\.title) == ["Mine dated"])
        #expect(reminders.allSatisfy { $0.remind && $0.hasTime })
    }

    @Test func userIDComesFromTheTokenSubject() {
        let id = UUID()
        func b64(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let token = "\(b64("{\"alg\":\"none\"}")).\(b64("{\"sub\":\"\(id.uuidString)\"}")).sig"
        #expect(HouseholdClient.userID(fromJWT: token) == id)
        #expect(HouseholdClient.userID(fromJWT: "nonsense") == nil)
    }

    @Test func serverRowsDecode() throws {
        let json = #"[{"id":"\#(UUID())","household_id":"\#(home)","title":"Bins","notes":"","due_at":"2026-10-06T22:00:00.123456+00:00","assignee_id":null,"created_by":null,"created_at":"2026-10-05T10:00:00+00:00","done_by":null,"done_at":null}]"#
        let tasks = try FamilyJSON.decoder.decode([HouseholdTask].self, from: Data(json.utf8))
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Bins")
        #expect(tasks[0].dueAt != nil)
        #expect(!tasks[0].isDone)
    }

    @Test func errorsMapToCalmCopy() {
        #expect(Copy.household.error(FamilyLinkError.server(code: "invalid_invite")) == Copy.household.invalidInvite)
        #expect(Copy.household.error(FamilyLinkError.server(code: "household_full")) == Copy.household.full)
        #expect(Copy.household.error(FamilyLinkError.http(status: 500)) == Copy.household.genericError)
    }

    @Test func sharedTextNamesTheTaskAndTheDay() {
        let t = PlannerTask(title: "Send the invoice", notes: "Client A", due: now, hasTime: false)
        let text = PlannerShare.text(for: t)
        #expect(text.hasPrefix("Send the invoice\nDue "))
        #expect(text.hasSuffix("Client A"))
        let agenda = PlannerDayAgenda(allDay: [], timed: [], anytimeTasks: [PlannerTask(title: "Call", isDone: true)], overdue: [])
        #expect(PlannerShare.text(for: agenda, day: now).contains("[x] Call"))
        let empty = PlannerDayAgenda(allDay: [], timed: [], anytimeTasks: [], overdue: [])
        #expect(PlannerShare.text(for: empty, day: now).hasSuffix(Copy.planner.nothingPlanned))
    }

    @Test func plannerRemindsForSharedAssignedTasksToo() {
        let dayStart = Calendar.current.startOfDay(for: now)
        let due = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(10 * 3_600)
        let shared = PlannerTask(title: "Bins", due: due, hasTime: true, remind: true)
        let plan = PlannerReminders.plan(tasks: [shared], events: [], settings: PlannerSettings(), now: now)
        #expect(plan.map(\.body) == ["Bins"])
    }
}
