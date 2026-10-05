// FamilyModels.swift
// Core / Family
//
// Family Link (session 23, 2026-10-05; docs/spec.md §5.23): an optional, teen-consented link between a
// parent and a 13-17-year-old. The parent sets tasks (homework, chores); the teen hands them in, with a
// photo if the parent wants one; the parent approves or asks for a redo. The proof photo is view-once.
//
// These types mirror `backend/supabase/migrations/0006_family_link.sql` (snake_case on the wire). The
// pure rules, the view-once clock and "is today done", live here so they are unit-tested without a server.

import Foundation

// MARK: - Wire types

public enum FamilyLinkStatus: String, Codable, Sendable {
    case invited, active, left
}

public enum FamilyTaskStatus: String, Codable, Sendable {
    case open, submitted, approved, redo
}

public struct FamilyLink: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let parentId: UUID
    public let teenId: UUID?
    public let inviteCode: String
    public let status: FamilyLinkStatus
    public let createdAt: Date?
    public let acceptedAt: Date?

    public init(id: UUID, parentId: UUID, teenId: UUID?, inviteCode: String, status: FamilyLinkStatus, createdAt: Date? = nil, acceptedAt: Date? = nil) {
        self.id = id
        self.parentId = parentId
        self.teenId = teenId
        self.inviteCode = inviteCode
        self.status = status
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
    }
}

public struct FamilyTask: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let linkId: UUID
    public let title: String
    public let dueAt: Date?
    public let requiresPhoto: Bool
    public let status: FamilyTaskStatus
    public let submittedAt: Date?
    public let decidedAt: Date?
    public let decisionNote: String?

    public init(
        id: UUID, linkId: UUID, title: String, dueAt: Date? = nil, requiresPhoto: Bool = false,
        status: FamilyTaskStatus = .open, submittedAt: Date? = nil, decidedAt: Date? = nil, decisionNote: String? = nil
    ) {
        self.id = id
        self.linkId = linkId
        self.title = title
        self.dueAt = dueAt
        self.requiresPhoto = requiresPhoto
        self.status = status
        self.submittedAt = submittedAt
        self.decidedAt = decidedAt
        self.decisionNote = decisionNote
    }
}

/// The record of a proof photo, never the picture.
public struct FamilyProofRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let taskId: UUID
    public let firstOpenedAt: Date?
    public let expiresAt: Date

    public init(id: UUID, taskId: UUID, firstOpenedAt: Date? = nil, expiresAt: Date) {
        self.id = id
        self.taskId = taskId
        self.firstOpenedAt = firstOpenedAt
        self.expiresAt = expiresAt
    }
}

// MARK: - JSON

public enum FamilyJSON {
    /// Postgres sends `2026-10-05T22:00:00.123456+00:00`; the stock `.iso8601` strategy rejects the
    /// fractional seconds, so try both shapes.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }
            // Postgres can send up to six fractional digits; trim to three and try again.
            if let dot = raw.firstIndex(of: "."), let zone = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                let millis = raw[raw.index(after: dot)..<zone].prefix(3)
                let trimmed = String(raw[..<dot]) + "." + millis + String(raw[zone...])
                if let date = fractional.date(from: trimmed) { return date }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(raw)"))
        }
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - The view-once clock

/// What the parent can do with a proof right now. Mirrors the server rule (docs/spec.md §5.23): one open;
/// deleted 10 minutes after it, 24 hours after upload if never opened.
public enum FamilyProofState: Equatable, Sendable {
    /// Waiting to be opened (once).
    case unopened(deletedAt: Date)
    /// Opened already: it can't be opened again, and is deleted at `deletedAt`.
    case opened(deletedAt: Date)
    /// Deleted, or past its time.
    case gone
}

public enum FamilyProofClock {
    public static let openWindow: TimeInterval = 10 * 60
    public static let unopenedLifetime: TimeInterval = 24 * 3_600

    public static func state(of proof: FamilyProofRecord, now: Date) -> FamilyProofState {
        guard now < proof.expiresAt else { return .gone }
        return proof.firstOpenedAt == nil ? .unopened(deletedAt: proof.expiresAt) : .opened(deletedAt: proof.expiresAt)
    }

    /// Only an unopened, unexpired proof can be opened.
    public static func canOpen(_ proof: FamilyProofRecord, now: Date) -> Bool {
        if case .unopened = state(of: proof, now: now) { return true }
        return false
    }

    /// When a proof opened at `openedAt` is deleted.
    public static func deletionTime(openedAt: Date) -> Date { openedAt.addingTimeInterval(openWindow) }

    /// When an unopened proof uploaded at `uploadedAt` is deleted.
    public static func deletionTime(uploadedAt: Date) -> Date { uploadedAt.addingTimeInterval(unopenedLifetime) }
}

// MARK: - Today's tasks as a goal

public enum FamilyTaskGoal {
    /// The title of the goal that counts a teen's family tasks toward an unlock (spec §5.23): "Family tasks".
    public static let goalTitle = "Family tasks"

    /// Tasks due today (or with no due time and handed in today) that the parent has approved, with nothing
    /// due today still waiting. `false` when there is nothing due today: no tasks, no goal.
    public static func isTodayDone(tasks: [FamilyTask], now: Date, calendar: Calendar = .current) -> Bool {
        let dueToday = tasks.filter { task in
            if let due = task.dueAt { return calendar.isDate(due, inSameDayAs: now) }
            return task.status != .approved || (task.decidedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }
        guard !dueToday.isEmpty else { return false }
        return dueToday.allSatisfy { $0.status == .approved }
    }
}
