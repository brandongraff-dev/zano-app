// HouseholdModels.swift
// Core / Household
//
// Household (session 28, docs/spec.md §5.31): a shared task list for the people you live or work with. Types
// mirror `backend/supabase/migrations/0007_household.sql` (snake_case on the wire, decoded with
// `FamilyJSON.decoder`). The grouping rules are pure and unit tested.

import Foundation

/// Whether this build shows Household at all: only when the build has Supabase keys AND the person is
/// signed in (session 34, `AccountStatus`). With no keys it is always `false`, so nobody meets a feature that
/// does nothing. Main-actor and observable: a view reading it updates the moment someone signs in or out.
public enum HouseholdAvailability {
    @MainActor public static var isLive: Bool { AccountStatus.shared.isLive }
}

public struct Household: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let ownerId: UUID
    public let inviteCode: String
    public let createdAt: Date?

    public init(id: UUID, name: String, ownerId: UUID, inviteCode: String, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.inviteCode = inviteCode
        self.createdAt = createdAt
    }
}

public struct HouseholdMember: Codable, Sendable, Identifiable, Equatable {
    public let householdId: UUID
    public let userId: UUID
    public let displayName: String
    public let joinedAt: Date?

    public var id: UUID { userId }

    public init(householdId: UUID, userId: UUID, displayName: String, joinedAt: Date? = nil) {
        self.householdId = householdId
        self.userId = userId
        self.displayName = displayName
        self.joinedAt = joinedAt
    }
}

public struct HouseholdTask: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let householdId: UUID
    public let title: String
    public let notes: String
    public let dueAt: Date?
    public let assigneeId: UUID?
    public let createdBy: UUID?
    public let createdAt: Date?
    public let doneBy: UUID?
    public let doneAt: Date?

    public var isDone: Bool { doneAt != nil }

    public init(
        id: UUID, householdId: UUID, title: String, notes: String = "", dueAt: Date? = nil, assigneeId: UUID? = nil,
        createdBy: UUID? = nil, createdAt: Date? = nil, doneBy: UUID? = nil, doneAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.assigneeId = assigneeId
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.doneBy = doneBy
        self.doneAt = doneAt
    }
}

/// How the shared list is laid out for one person.
public enum HouseholdBoard {
    public struct Sections: Equatable, Sendable {
        /// Open tasks assigned to me.
        public var mine: [HouseholdTask]
        /// Open tasks nobody has taken yet.
        public var unassigned: [HouseholdTask]
        /// Open tasks assigned to someone else.
        public var others: [HouseholdTask]
        /// Finished in the last few days, newest first.
        public var doneRecently: [HouseholdTask]

        public var openCount: Int { mine.count + unassigned.count + others.count }
        public var isEmpty: Bool { openCount == 0 && doneRecently.isEmpty }
    }

    /// How long a finished task stays visible in "Done".
    public static let doneVisibleDays = 3
    public static let doneVisibleMax = 10

    public static func sections(tasks: [HouseholdTask], me: UUID?, now: Date = .now) -> Sections {
        let open = tasks.filter { !$0.isDone }.sorted(by: openOrder)
        let cutoff = now.addingTimeInterval(-Double(doneVisibleDays) * 86_400)
        let done = tasks
            .filter { task in task.doneAt.map { $0 >= cutoff } ?? false }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        return Sections(
            mine: open.filter { $0.assigneeId != nil && $0.assigneeId == me },
            unassigned: open.filter { $0.assigneeId == nil },
            others: open.filter { $0.assigneeId != nil && $0.assigneeId != me },
            doneRecently: Array(done.prefix(doneVisibleMax))
        )
    }

    /// Due soonest first, tasks with no date last, then oldest first.
    private static func openOrder(_ a: HouseholdTask, _ b: HouseholdTask) -> Bool {
        switch (a.dueAt, b.dueAt) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
        }
    }

    /// The name to show for `id`: "You" for me, the member's chosen name, or `nil` for unassigned or unknown.
    public static func name(for id: UUID?, members: [HouseholdMember], me: UUID?) -> String? {
        guard let id else { return nil }
        if id == me { return Copy.household.you }
        return members.first { $0.userId == id }?.displayName
    }

    /// My open tasks that have a date, as local reminders (`PlannerReminders` plans them like any task).
    public static func reminderTasks(from tasks: [HouseholdTask], me: UUID?) -> [PlannerTask] {
        tasks.compactMap { task in
            guard !task.isDone, let me, task.assigneeId == me, let due = task.dueAt else { return nil }
            return PlannerTask(id: task.id, title: task.title, notes: task.notes, due: due, hasTime: true, remind: true)
        }
    }
}
