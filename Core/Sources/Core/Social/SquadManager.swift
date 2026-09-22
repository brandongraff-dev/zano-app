// Core/Sources/Core/Social/SquadManager.swift
//
// docs/spec.md §5.7 Squads & Duels — the Squad half:
//   "Squad (2–8): shared weekly ring; each member's daily rings visible; one-tap 'nudge' that
//   sends a push with the sender's face; squad streak freezes are shared (one member's freeze
//   protects everyone once/week)."
// Also docs/spec.md §13 (Data Model — `squads`, `squad_members`) and §11 (Architecture —
// "local-first... unlock must be instant and offline").
//
// This file has no fixed public shape in the orchestrator's SYSTEM CONTRACTS block (unlike
// `LockEngineManager`/`GymVerifier`/etc.), so its API is designed here to satisfy this task and
// spec §5.7 exactly, following the same conventions those contract-fixed files already establish
// (actor-owned `ModelContext` against the shared App Group store, `Sendable` snapshot structs
// returned instead of live `@Model` instances, `LocalizedError` diagnostics kept out of
// `Core/Sources/Core/Copy` the same way `LockEngineError`/`NudgeSenderError` are — see those
// files' header comments for the identical reasoning).
//
// Ownership: `Squad`/`SquadMember` (Core/Sources/Core/Models, Session 1) are reused verbatim —
// every field name below matches those files exactly, nothing is redeclared or duplicated.
// `Nudge`/`NudgeArm`/`NudgeTone`/`NudgeTimingSlot`/`NudgeFormat` (also Session 1's Models) are
// reused the same way for `sendNudge`. `SyncEngine.shared.enqueue` (Core/Sources/Core/Sync,
// another session) is called exactly per its own documented contract to queue changes for the
// backend; this file never talks to the network directly (CLAUDE.md: "Extensions do no
// networking... Backend: Supabase... never put secrets in the app").
//
// Known architectural gap (see this task's `knownIssues` in the structured report): local-first
// storage only ever holds the signed-in device's own `Goal`/`GoalEvent`/`DailyPlan` graph
// (`Models/User.swift`'s doc comment is explicit about this). A squad's *other* members' goal
// completions, therefore, cannot be computed on-device from data that will simply never exist
// locally — that data only ever lives in the other members' own devices and, once synced, in
// Postgres. Doing "shared weekly ring aggregation" for real requires a backend view/RPC this
// session cannot build (no such endpoint exists yet under `backend/supabase/functions` — the only
// ones are `meal-vision`, `revenuecat-webhook`, `sync`, `weekly-recap`) and a Sync *pull* path
// (`SyncEngine.pullAndMerge()` is today's documented TODO no-op). Rather than fake that data or
// silently omit squadmates, `weeklyRingBoard(squadID:weekContaining:)` computes the signed-in
// user's own week for real from local data, and exposes a `SquadRingSource` protocol seam — the
// exact same pattern `SyncEngine.SyncBackend` already establishes for "no real networking yet,
// here is where the real implementation plugs in" — so a future backend/Sync session can supply
// squadmates' real weekly rings without this file changing shape. The same honesty applies to
// `joinSquad(inviteCode:)`'s `SquadDirectory` seam (resolving another user's invite code to a
// squad also needs a backend lookup this session cannot build) and to the shared-freeze tracking
// below (a squad-wide "who used it this week" fact is itself something only the backend can see
// across every member's device — this file provides the local half: recording/consulting the
// rule for the signed-in device, and queuing the fact for sync).

import Foundation
import SwiftData
import os

// MARK: - Errors

/// Errors `SquadManager` throws itself, as opposed to errors bubbled up from SwiftData. Kept as
/// plain, developer-facing diagnostics — mirroring `LockEngineError`'s and `NudgeSenderError`'s
/// documented convention — never routed through `Core/Sources/Core/Copy`, since nothing here is
/// copy meant to be shown verbatim to the user. Whatever user-facing message a Squad UI chooses
/// for one of these belongs in `Copy`, per CLAUDE.md.
public enum SquadManagerError: Error, Sendable, LocalizedError {
    /// No local `User` row exists yet to attribute this action to.
    case noSignedInUser
    /// `createSquad(name:)` was called with an empty/whitespace-only name.
    case invalidName
    /// `joinSquad(inviteCode:)` was called with an empty/whitespace-only code.
    case invalidInviteCode
    /// No local `Squad` exists with this id.
    case squadNotFound(UUID)
    /// Neither the local store nor the configured `SquadDirectory` could resolve this invite
    /// code to a squad. See this file's header comment re: the join-across-devices gap.
    case squadNotFoundForInviteCode(String)
    /// `joinSquad` would push a squad's membership above spec §5.7's "Squad (2–8)" cap.
    case squadFull(squadID: UUID, maxSize: Int)
    /// The caller is not a member of this squad.
    case notAMember(squadID: UUID)
    /// `generateUniqueInviteCode()` could not find a free code after repeated attempts —
    /// practically unreachable at this alphabet/length, but never silently loop forever.
    case inviteCodeGenerationFailed
    /// `sendNudge(squadID:from:to:)`'s sender is not a member of `squadID`.
    case senderNotAMember(squadID: UUID, userID: UUID)
    /// `sendNudge(squadID:from:to:)`'s recipient is not a member of `squadID`.
    case recipientNotAMember(squadID: UUID, userID: UUID)
    /// A user cannot nudge themselves.
    case cannotNudgeSelf
    /// The same sender→recipient nudge was sent again before `SquadManager.nudgeCooldown`
    /// elapsed — an accidental-double-tap guard, not part of spec §8 rule 7's 2/day bandit cap
    /// (that cap belongs to `NudgeSender`, which this file deliberately does not call — see
    /// `sendNudge`'s doc comment).
    case nudgeCooldownActive(retryAfter: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser:
            "No local User row exists yet."
        case .invalidName:
            "Squad name cannot be empty."
        case .invalidInviteCode:
            "Invite code cannot be empty."
        case .squadNotFound(let id):
            "No Squad found with id \(id)."
        case .squadNotFoundForInviteCode(let code):
            "No squad found for invite code \"\(code)\"."
        case .squadFull(let squadID, let maxSize):
            "Squad \(squadID) already has \(maxSize) members."
        case .notAMember(let squadID):
            "Not a member of squad \(squadID)."
        case .inviteCodeGenerationFailed:
            "Could not generate a unique invite code."
        case .senderNotAMember(let squadID, let userID):
            "\(userID) is not a member of squad \(squadID) and cannot send a nudge there."
        case .recipientNotAMember(let squadID, let userID):
            "\(userID) is not a member of squad \(squadID) and cannot be nudged there."
        case .cannotNudgeSelf:
            "Cannot nudge yourself."
        case .nudgeCooldownActive(let retryAfter):
            "Already nudged this person recently — try again in \(Int(retryAfter))s."
        }
    }
}

// MARK: - Sendable snapshots

/// A `Sendable` value copy of a `Squad` row, returned by every public `SquadManager` API instead
/// of the live `@Model` instance — matching `LockEngineManager`/`GymVerifier`'s established
/// pattern of never handing a non-`Sendable` SwiftData model across this actor's async boundary
/// (those files return `UUID`s/primitives/value-type `ContentState`s for the same reason).
public struct SquadSnapshot: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let createdBy: UUID
    public let inviteCode: String

    public init(id: UUID, name: String, createdBy: UUID, inviteCode: String) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.inviteCode = inviteCode
    }
}

/// A `Sendable` value copy of a `SquadMember` row. `id` stands in for the composite
/// `(squadID, userID)` primary key `Models/SquadMember.swift` documents Postgres using — there is
/// no independent single-column id to mirror.
public struct SquadMemberSnapshot: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { "\(squadID.uuidString)/\(userID.uuidString)" }
    public let squadID: UUID
    public let userID: UUID
    public let role: SquadRole

    public init(squadID: UUID, userID: UUID, role: SquadRole) {
        self.squadID = squadID
        self.userID = userID
        self.role = role
    }
}

// MARK: - Weekly ring aggregation (spec §5.7: "shared weekly ring; each member's daily rings visible")

/// One day's ring completion for one squad member — the same concept the Weekly Report Card
/// (spec §5.14, §16 image-gen prompt P7: "7 columns of daily rings") renders for a single user,
/// scoped here to a squad roster.
public struct SquadMemberRingDay: Sendable, Equatable, Hashable, Codable {
    /// Local midnight for this day (`Calendar.startOfDay`).
    public let date: Date
    /// How many of `totalGoals` had a verified completion (`GoalEvent.kind` of `.complete`,
    /// `.planB`, or `.freeze`, `verified == true`) on this day.
    public let completedGoals: Int
    /// The goal count this day's ring is measured against — the distinct goals with a
    /// `DailyPlan` for this date, or (if none were planned) every currently-active `Goal`.
    public let totalGoals: Int

    public init(date: Date, completedGoals: Int, totalGoals: Int) {
        self.date = date
        self.completedGoals = completedGoals
        self.totalGoals = totalGoals
    }

    /// `0...1`. `0` (not `1`/vacuously-complete) when `totalGoals == 0` — an empty ring, not a
    /// full one, matching `RingCluster`/`GoalRing`'s (Core/Sources/Core/UI) convention that a
    /// not-configured ring shows empty rather than lying about completion.
    public var fraction: Double {
        totalGoals > 0 ? Double(completedGoals) / Double(totalGoals) : 0
    }
}

/// One squad member's full week of daily rings.
public struct SquadMemberWeeklyRings: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID { userID }
    public let userID: UUID
    /// Always 7 entries for a fully-computed week, oldest (Monday) first. May be empty when
    /// `dataAvailable == false` and no cached fallback exists.
    public let days: [SquadMemberRingDay]
    /// `true` when `days` was computed from real data (the signed-in user, always; another
    /// member, only if a `SquadRingSource` was configured and returned something for them).
    /// `false` means "not yet known on this device" — a UI should render this member's rings as
    /// pending sync, never as zero/failed rings (spec §8 rule 9: never shame; an unknown state
    /// must not look like a miss).
    public let dataAvailable: Bool

    public init(userID: UUID, days: [SquadMemberRingDay], dataAvailable: Bool) {
        self.userID = userID
        self.days = days
        self.dataAvailable = dataAvailable
    }
}

/// A full squad's week, ready for a Squad screen to render (spec §5.7, §15 "Squad" screen).
public struct SquadWeeklyRingBoard: Sendable, Equatable, Codable {
    public let squadID: UUID
    /// Local midnight of the week's Monday (ISO-8601 week, locale-independent).
    public let weekStart: Date
    public let members: [SquadMemberWeeklyRings]

    public init(squadID: UUID, weekStart: Date, members: [SquadMemberWeeklyRings]) {
        self.squadID = squadID
        self.weekStart = weekStart
        self.members = members
    }
}

/// Resolves squadmates' weekly rings from wherever they actually live once synced — a real
/// backend read, not this device's local `GoalEvent` table (see this file's header comment).
/// Exactly the seam `SyncEngine.SyncBackend` already establishes for "no real networking yet,
/// here is where the real implementation plugs in": a future backend/Sync session supplies a
/// concrete conformance and calls `SquadManager.shared.configureRingSource(_:)` once, the same
/// way `SyncEngine.shared.setBackend(_:)` is documented to work.
public protocol SquadRingSource: Sendable {
    /// - Parameters:
    ///   - memberUserIDs: every non-local member of the squad being rendered.
    ///   - weekStart: local midnight of that week's Monday.
    /// - Returns: whatever this source could resolve, keyed by `userID`. Members with no entry
    ///   in the result are rendered as `dataAvailable == false`.
    func weeklyRings(for memberUserIDs: [UUID], weekStart: Date) async -> [UUID: SquadMemberWeeklyRings]
}

/// Resolves a squad invite code to the squad it belongs to. The default (`LocalOnlySquadDirectory`)
/// can only ever resolve a code already present in this device's local `Squad` table (e.g. a
/// squad this same device created); resolving a code for a squad that lives only on someone
/// else's device needs a real backend lookup this session cannot build — see this file's header
/// comment. A future backend/Sync session supplies a concrete conformance via
/// `configureDirectory(_:)`.
public protocol SquadDirectory: Sendable {
    /// - Returns: the resolved squad's identity, or `nil` if this source cannot resolve `inviteCode`.
    func resolveSquad(inviteCode: String) async throws -> SquadDirectoryEntry?
}

public struct SquadDirectoryEntry: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let createdBy: UUID

    public init(id: UUID, name: String, createdBy: UUID) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
    }
}

/// Default `SquadDirectory`: always defers to `SquadManager`'s own local `Squad` lookup by
/// invite code, which already runs before this protocol is ever consulted (see `joinSquad`) — so
/// this conformance has nothing further to add and always returns `nil`. Kept as an explicit,
/// documented type (rather than `nil` as the default) so the "no real resolver configured yet"
/// state is visible at every call site, matching `NudgeSender`'s `deliver` no-op default's spirit.
public struct LocalOnlySquadDirectory: SquadDirectory {
    public init() {}
    public func resolveSquad(inviteCode: String) async throws -> SquadDirectoryEntry? { nil }
}

// MARK: - Shared streak freeze (spec §5.7: "one member's freeze protects everyone once/week")

/// Who covered a squad's shared streak freeze for a given ISO week, and when.
public struct SquadSharedFreezeStatus: Sendable, Equatable, Codable {
    public let usedByUserID: UUID
    public let usedAt: Date
    /// `"<ISO year>-W<ISO week>"`, e.g. `"2026-W17"` — see `SquadManager.isoWeekKey(for:)`.
    public let weekKey: String
}

// MARK: - SquadManager

/// The sole owner of local `Squad`/`SquadMember` rows and of squad-scoped nudge/freeze/ring
/// logic (spec §5.7). Declared a plain `actor` — matching `SyncEngine`'s exact convention for a
/// `Core` engine that owns a `ModelContext` and has no reason to be pinned to `@MainActor` (no
/// `ManagedSettingsStore`/`DeviceActivityCenter`-style main-thread-only Apple API is involved
/// here, unlike `LockEngineManager`) — so `static let shared` stays a trivial singleton and every
/// method is safely callable from any isolation domain via `await`.
public actor SquadManager {
    public static let shared = SquadManager()

    /// docs/spec.md §5.7: "Squad (2–8)".
    public static let maxSquadSize = 8

    /// Not spec-mandated — a deliberate, narrow anti-double-tap guard on the *sender* side only
    /// (see `SquadManagerError.nudgeCooldownActive`'s doc comment). Spec §8 rule 7's real 2/day
    /// cap belongs to `NudgeSender` and does not apply here (this file cannot call `NudgeSender`
    /// for a squad nudge — see `sendNudge`'s doc comment for why).
    public static let nudgeCooldown: TimeInterval = 15 * 60

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "SquadManager")

    private var ringSource: SquadRingSource?
    private var directory: SquadDirectory
    /// In-memory only (see `SquadManagerError.nudgeCooldownActive`'s doc comment) — resets on
    /// process relaunch, which is an acceptable cost for a double-tap guard, not a durability
    /// requirement.
    private var lastNudgeSentAt: [NudgePairKey: Date] = [:]

    private struct NudgePairKey: Hashable {
        let squadID: UUID
        let senderID: UUID
        let recipientID: UUID
    }

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container and injected `SquadRingSource`/`SquadDirectory` — every real call
    /// site uses `.shared`. Mirrors `LockEngineManager`/`GymVerifier`/`NudgeSender`'s identical
    /// testability convention.
    init(
        modelContainer: ModelContainer = .appGroup,
        ringSource: SquadRingSource? = nil,
        directory: SquadDirectory = LocalOnlySquadDirectory()
    ) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.ringSource = ringSource
        self.directory = directory
    }

    /// Swaps in a real `SquadRingSource` once a backend/Sync session builds one — the seam this
    /// file's header comment describes. Safe to call at any time; `nil` reverts to "local user
    /// only, squadmates pending sync".
    public func configureRingSource(_ source: SquadRingSource?) {
        self.ringSource = source
    }

    /// Swaps in a real `SquadDirectory` once a backend/Sync session builds one.
    public func configureDirectory(_ directory: SquadDirectory) {
        self.directory = directory
    }

    // MARK: - Create / Join / Leave

    /// Creates a new squad owned by the signed-in user, with a freshly generated unique invite
    /// code, and inserts the creator as its first (`.owner`) member.
    @discardableResult
    public func createSquad(name: String) async throws -> SquadSnapshot {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SquadManagerError.invalidName }

        let user = try fetchCurrentUser()
        let inviteCode = try generateUniqueInviteCode()

        let squad = Squad(name: trimmed, createdBy: user.id, inviteCode: inviteCode)
        context.insert(squad)
        let membership = SquadMember(squadID: squad.id, userID: user.id, role: .owner)
        context.insert(membership)
        try context.save()

        try? await enqueueSync(entityName: "Squad", entityID: squad.id, payload: SquadSyncPayload(squad: squad))
        try? await enqueueSync(
            entityName: "SquadMember",
            entityID: squad.id,
            payload: SquadMemberSyncPayload(squadID: squad.id, userID: user.id, role: .owner)
        )

        Analytics.shared.capture(event: "squad_created", properties: ["squad_id": squad.id.uuidString])
        logger.notice("Created squad \(squad.id.uuidString, privacy: .public) with invite code \(inviteCode, privacy: .public).")
        return SquadSnapshot(id: squad.id, name: squad.name, createdBy: squad.createdBy, inviteCode: squad.inviteCode)
    }

    /// Joins the squad identified by `inviteCode`. Resolution order: (1) a `Squad` row already
    /// present locally with this invite code (covers a squad this device itself created, or one
    /// already pulled down by a prior sync), then (2) the configured `SquadDirectory` (see its
    /// doc comment). Idempotent: re-joining a squad the signed-in user already belongs to just
    /// returns that squad rather than throwing or duplicating the membership row.
    @discardableResult
    public func joinSquad(inviteCode rawCode: String) async throws -> SquadSnapshot {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw SquadManagerError.invalidInviteCode }

        let user = try fetchCurrentUser()

        let squad: Squad
        if let existing = try fetchSquad(inviteCode: code) {
            squad = existing
        } else if let resolved = try await directory.resolveSquad(inviteCode: code) {
            if let mirrored = try fetchSquad(id: resolved.id) {
                squad = mirrored
            } else {
                let created = Squad(id: resolved.id, name: resolved.name, createdBy: resolved.createdBy, inviteCode: code)
                context.insert(created)
                try context.save()
                squad = created
            }
        } else {
            throw SquadManagerError.squadNotFoundForInviteCode(code)
        }

        if try fetchMembership(squadID: squad.id, userID: user.id) != nil {
            return SquadSnapshot(id: squad.id, name: squad.name, createdBy: squad.createdBy, inviteCode: squad.inviteCode)
        }

        let currentSize = try fetchMembers(squadID: squad.id).count
        guard currentSize < Self.maxSquadSize else {
            throw SquadManagerError.squadFull(squadID: squad.id, maxSize: Self.maxSquadSize)
        }

        let membership = SquadMember(squadID: squad.id, userID: user.id, role: .member)
        context.insert(membership)
        try context.save()

        try? await enqueueSync(
            entityName: "SquadMember",
            entityID: squad.id,
            payload: SquadMemberSyncPayload(squadID: squad.id, userID: user.id, role: .member)
        )

        Analytics.shared.capture(event: "squad_joined", properties: ["squad_id": squad.id.uuidString])
        return SquadSnapshot(id: squad.id, name: squad.name, createdBy: squad.createdBy, inviteCode: squad.inviteCode)
    }

    /// Removes the signed-in user's membership. If the leaving member was the `.owner` and other
    /// members remain, ownership transfers to one of them (`SquadMember` carries no
    /// join-timestamp to pick "earliest joined" deterministically — see `Models/SquadMember.swift`
    /// — so the successor is whichever remaining row SwiftData's fetch returns first; documented
    /// simplification, not a silent bug). If no members remain, the now-empty `Squad` row is
    /// deleted too rather than left orphaned forever.
    public func leaveSquad(squadID: UUID) async throws {
        let user = try fetchCurrentUser()
        guard let membership = try fetchMembership(squadID: squadID, userID: user.id) else {
            throw SquadManagerError.notAMember(squadID: squadID)
        }
        let remaining = try fetchMembers(squadID: squadID).filter { $0.userID != user.id }

        context.delete(membership)

        if membership.role == .owner, let successor = remaining.first {
            successor.role = .owner
        }
        var deletedSquad = false
        if remaining.isEmpty, let squad = try fetchSquad(id: squadID) {
            context.delete(squad)
            deletedSquad = true
        }
        try context.save()

        try? await enqueueSync(
            entityName: "SquadMember",
            entityID: squadID,
            payload: SquadMemberLeavePayload(squadID: squadID, userID: user.id, squadDeleted: deletedSquad)
        )
        Analytics.shared.capture(event: "squad_left", properties: ["squad_id": squadID.uuidString])
    }

    // MARK: - Membership introspection

    public func members(of squadID: UUID) async throws -> [SquadMemberSnapshot] {
        try fetchMembers(squadID: squadID).map {
            SquadMemberSnapshot(squadID: $0.squadID, userID: $0.userID, role: $0.role)
        }
    }

    /// Every squad the signed-in user has a local `SquadMember` row for.
    public func mySquads() async throws -> [SquadSnapshot] {
        let user = try fetchCurrentUser()
        let memberships = try fetchMemberships(userID: user.id)
        let squadIDs = Set(memberships.map { $0.squadID })
        guard !squadIDs.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<Squad>())
        return all
            .filter { squadIDs.contains($0.id) }
            .map { SquadSnapshot(id: $0.id, name: $0.name, createdBy: $0.createdBy, inviteCode: $0.inviteCode) }
    }

    // MARK: - Weekly ring aggregation

    /// Builds the squad's weekly ring board (spec §5.7). See this file's header comment for
    /// exactly what "real" means here today: the signed-in user's week is computed live from
    /// local `GoalEvent`/`DailyPlan` data; every other member's week comes from the configured
    /// `SquadRingSource` if one is set, or is marked `dataAvailable: false` otherwise.
    public func weeklyRingBoard(squadID: UUID, weekContaining date: Date = .now) async throws -> SquadWeeklyRingBoard {
        guard try fetchSquad(id: squadID) != nil else { throw SquadManagerError.squadNotFound(squadID) }
        let memberRows = try fetchMembers(squadID: squadID)
        let weekStart = Self.startOfISOWeek(containing: date)
        let currentUserID = try? fetchCurrentUser().id

        var boardMembers: [SquadMemberWeeklyRings] = []
        var remoteMemberIDs: [UUID] = []
        for member in memberRows {
            if let currentUserID, member.userID == currentUserID {
                boardMembers.append(try computeLocalUserWeeklyRings(userID: member.userID, weekStart: weekStart))
            } else {
                remoteMemberIDs.append(member.userID)
            }
        }

        if !remoteMemberIDs.isEmpty, let ringSource {
            let resolved = await ringSource.weeklyRings(for: remoteMemberIDs, weekStart: weekStart)
            for id in remoteMemberIDs {
                boardMembers.append(resolved[id] ?? Self.pendingSyncPlaceholder(userID: id))
            }
        } else {
            for id in remoteMemberIDs {
                boardMembers.append(Self.pendingSyncPlaceholder(userID: id))
            }
        }

        return SquadWeeklyRingBoard(squadID: squadID, weekStart: weekStart, members: boardMembers)
    }

    private static func pendingSyncPlaceholder(userID: UUID) -> SquadMemberWeeklyRings {
        SquadMemberWeeklyRings(userID: userID, days: [], dataAvailable: false)
    }

    private func computeLocalUserWeeklyRings(userID: UUID, weekStart: Date) throws -> SquadMemberWeeklyRings {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current

        var days: [SquadMemberRingDay] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let progress = try dailyRingProgress(dayStart: dayStart, dayEnd: dayEnd)
            days.append(SquadMemberRingDay(date: dayStart, completedGoals: progress.completed, totalGoals: progress.total))
        }
        return SquadMemberWeeklyRings(userID: userID, days: days, dataAvailable: true)
    }

    /// Mirrors `LockEngineManager.isGoalVerified(goalID:coveringDayOf:)`'s documented tradeoff:
    /// only `Bool`/`Date` comparisons are pushed into `#Predicate` (this session has no
    /// Mac/Swift toolchain to compile-verify how SwiftData's `#Predicate` macro handles optional-
    /// relationship chaining or enum equality on this SDK version); everything else is filtered
    /// in plain Swift after the fetch.
    private func dailyRingProgress(dayStart: Date, dayEnd: Date) throws -> (completed: Int, total: Int) {
        let plans = try context.fetch(
            FetchDescriptor<DailyPlan>(predicate: #Predicate<DailyPlan> { $0.date >= dayStart && $0.date < dayEnd })
        )
        var totalGoalIDs = Set(plans.compactMap { $0.goal?.id })
        if totalGoalIDs.isEmpty {
            let activeGoals = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.active == true }))
            totalGoalIDs = Set(activeGoals.map { $0.id })
        }

        let events = try context.fetch(
            FetchDescriptor<GoalEvent>(predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= dayStart && $0.ts < dayEnd })
        )
        let completedGoalIDs = Set(events.compactMap { event -> UUID? in
            guard event.kind == .complete || event.kind == .planB || event.kind == .freeze else { return nil }
            return event.goal?.id
        })

        let completed = totalGoalIDs.isEmpty ? completedGoalIDs.count : completedGoalIDs.intersection(totalGoalIDs).count
        return (completed, totalGoalIDs.count)
    }

    /// Local midnight of `date`'s ISO-8601 week Monday — locale-independent, so "the current
    /// week" always means the same thing regardless of device region settings.
    static func startOfISOWeek(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    // MARK: - Nudge (spec §5.7: "one-tap nudge... writes a Nudge row")

    /// Sends a one-tap squad nudge from `senderID` to `recipientID`, both required to already be
    /// members of `squadID`.
    ///
    /// Deliberately does **not** call `NudgeSender.shared.send(arm:on:deliver:)`
    /// (`Core/Sources/Core/Social/NudgeSender.swift`, a sibling file this session does not own):
    /// `NudgeSender` always attributes the row it writes to `fetchCurrentUser()` — it exists for
    /// the §9.3 bandit's self-directed "the app nudges its own signed-in user" case and has no
    /// parameter for an arbitrary recipient, so it cannot represent "member A nudges member B" at
    /// all. This method writes the `Nudge` row directly instead, with `userID: recipientID` —
    /// consistent with `Nudge.userID`'s actual meaning ("who this nudge is for") for both nudge
    /// kinds — and does not touch `NudgeSender`'s 2/day cap bookkeeping, which is scoped to the
    /// bandit's own delivered-count query for the signed-in user and isn't the right cap for a
    /// nudge aimed at someone else's device anyway (see `SquadManagerError.nudgeCooldownActive`'s
    /// doc comment for the narrower guard this method does apply).
    ///
    /// `arm`/`NudgeArm`'s fields (tone/timing slot/format) carry no sender or squad identity —
    /// see `Models/Nudge.swift` — so that context (needed for the backend to actually relay "a
    /// push with the sender's face", spec §5.7) travels only in the Sync outbox payload below,
    /// not in the durable local `Nudge` row itself. `delivered` is left `false`: this device
    /// cannot itself push a notification to someone else's phone — that's the backend relay this
    /// task cannot build (no `squad_nudges`-style table/columns or edge function exists yet under
    /// `backend/supabase`) — so `false` here means "not yet delivered by anyone", to be flipped
    /// once a real relay lands, not "suppressed" the way `NudgeSender` uses it.
    @discardableResult
    public func sendNudge(
        squadID: UUID,
        from senderID: UUID,
        to recipientID: UUID,
        tone: NudgeTone = .hype,
        on date: Date = .now
    ) async throws -> UUID {
        guard senderID != recipientID else { throw SquadManagerError.cannotNudgeSelf }
        guard try fetchMembership(squadID: squadID, userID: senderID) != nil else {
            throw SquadManagerError.senderNotAMember(squadID: squadID, userID: senderID)
        }
        guard try fetchMembership(squadID: squadID, userID: recipientID) != nil else {
            throw SquadManagerError.recipientNotAMember(squadID: squadID, userID: recipientID)
        }

        let key = NudgePairKey(squadID: squadID, senderID: senderID, recipientID: recipientID)
        if let last = lastNudgeSentAt[key] {
            let elapsed = date.timeIntervalSince(last)
            if elapsed < Self.nudgeCooldown {
                throw SquadManagerError.nudgeCooldownActive(retryAfter: Self.nudgeCooldown - elapsed)
            }
        }

        let nudge = Nudge(
            userID: recipientID,
            ts: date,
            arm: NudgeArm(tone: tone, timingSlot: Self.timingSlot(at: date), format: .push),
            delivered: false
        )
        context.insert(nudge)
        try context.save()
        lastNudgeSentAt[key] = date

        try? await enqueueSync(
            entityName: "Nudge",
            entityID: nudge.id,
            payload: SquadNudgeSyncPayload(nudgeID: nudge.id, squadID: squadID, senderUserID: senderID, recipientUserID: recipientID, ts: date)
        )

        Analytics.shared.capture(event: "squad_nudge_sent", properties: ["squad_id": squadID.uuidString])
        return nudge.id
    }

    private static func timingSlot(at date: Date) -> NudgeTimingSlot {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .morning
        case 11..<16: return .preGymWindow
        case 16..<18: return .afternoon4pm
        default: return .evening
        }
    }

    // MARK: - Shared streak freeze (spec §5.7: "one member's freeze protects everyone once/week")

    /// `true` if no member of `squadID` has claimed the shared freeze for `date`'s ISO week yet.
    public func isSharedFreezeAvailable(squadID: UUID, on date: Date = .now) -> Bool {
        sharedFreezeProtection(squadID: squadID, on: date) == nil
    }

    /// Claims the squad's shared freeze for `date`'s ISO week on `userID`'s behalf — the local
    /// half of spec §5.7's "one member's freeze protects everyone once/week": this device records
    /// and durably persists (App-Group-shared `UserDefaults`, so every extension/process on this
    /// device agrees) that the week is covered, and queues the fact for sync so other members'
    /// devices eventually learn about it too once a backend/Sync pull exists (see this file's
    /// header comment — propagating this *to* other members' devices is that same known gap).
    ///
    /// - Returns: `true` if this call actually claimed the week (no one had yet); `false` if the
    ///   shared freeze was already used by someone this week, so the caller (e.g. whichever
    ///   module later calls `StreakEngine.useFreeze`) knows it must fall back to the user's own
    ///   personal freeze instead.
    @discardableResult
    public func consumeSharedFreeze(squadID: UUID, usedBy userID: UUID, on date: Date = .now) async throws -> Bool {
        guard try fetchMembership(squadID: squadID, userID: userID) != nil else {
            throw SquadManagerError.notAMember(squadID: squadID)
        }
        let week = Self.isoWeekKey(for: date)
        if let existing = loadFreezeState(squadID: squadID), existing.weekKey == week {
            return false
        }
        let state = SquadFreezeState(weekKey: week, usedByUserID: userID, usedAt: date)
        saveFreezeState(state, squadID: squadID)

        try? await enqueueSync(
            entityName: "SquadSharedFreeze",
            entityID: squadID,
            payload: SquadSharedFreezeSyncPayload(squadID: squadID, usedByUserID: userID, weekKey: week, usedAt: date)
        )
        Analytics.shared.capture(event: "squad_shared_freeze_used", properties: ["squad_id": squadID.uuidString])
        return true
    }

    /// Full detail (who covered it, when) for `date`'s ISO week, or `nil` if the squad's shared
    /// freeze is still unclaimed this week.
    public func sharedFreezeProtection(squadID: UUID, on date: Date = .now) -> SquadSharedFreezeStatus? {
        let week = Self.isoWeekKey(for: date)
        guard let state = loadFreezeState(squadID: squadID), state.weekKey == week else { return nil }
        return SquadSharedFreezeStatus(usedByUserID: state.usedByUserID, usedAt: state.usedAt, weekKey: state.weekKey)
    }

    private static func isoWeekKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    /// Deliberately reads/writes the App Group `UserDefaults` suite directly by its identifier
    /// (`AppGroup.identifier`, `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`) rather
    /// than adding a key to `Core/Sources/Core/Store/SharedDefaults.swift` — that file is owned by
    /// a different session, and this state (per-squad, keyed by `squadID`) doesn't fit its
    /// existing flat "one value per key" shape anyway. Still the same durable, cross-process App
    /// Group store `SharedDefaults` itself wraps (spec §11: "shared UserDefaults live here").
    private struct SquadFreezeState: Codable, Sendable {
        var weekKey: String
        var usedByUserID: UUID
        var usedAt: Date
    }

    private var freezeDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private func freezeDefaultsKey(squadID: UUID) -> String {
        "com.zano.app.squad.sharedFreeze.\(squadID.uuidString)"
    }

    private func loadFreezeState(squadID: UUID) -> SquadFreezeState? {
        guard let data = freezeDefaults.data(forKey: freezeDefaultsKey(squadID: squadID)) else { return nil }
        return try? JSONDecoder().decode(SquadFreezeState.self, from: data)
    }

    private func saveFreezeState(_ state: SquadFreezeState, squadID: UUID) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        freezeDefaults.set(data, forKey: freezeDefaultsKey(squadID: squadID))
    }

    // MARK: - SwiftData

    private func fetchSquad(id: UUID) throws -> Squad? {
        var descriptor = FetchDescriptor<Squad>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchSquad(inviteCode: String) throws -> Squad? {
        var descriptor = FetchDescriptor<Squad>(predicate: #Predicate { $0.inviteCode == inviteCode })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMembers(squadID: UUID) throws -> [SquadMember] {
        try context.fetch(FetchDescriptor<SquadMember>(predicate: #Predicate { $0.squadID == squadID }))
    }

    private func fetchMemberships(userID: UUID) throws -> [SquadMember] {
        try context.fetch(FetchDescriptor<SquadMember>(predicate: #Predicate { $0.userID == userID }))
    }

    private func fetchMembership(squadID: UUID, userID: UUID) throws -> SquadMember? {
        var descriptor = FetchDescriptor<SquadMember>(
            predicate: #Predicate<SquadMember> { $0.squadID == squadID && $0.userID == userID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// This device's local store holds exactly one `User` row (see `Models/User.swift`'s doc
    /// comment), so the first (only) one is always the right one.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw SquadManagerError.noSignedInUser
        }
        return user
    }

    // MARK: - Invite codes

    /// Excludes visually-ambiguous characters (`0/O`, `1/I/L`) — this code gets read off one
    /// phone screen and typed into another.
    private static let inviteCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private static let inviteCodeLength = 6

    private func generateUniqueInviteCode() throws -> String {
        for _ in 0..<25 {
            let code = Self.randomInviteCode()
            if try fetchSquad(inviteCode: code) == nil { return code }
        }
        throw SquadManagerError.inviteCodeGenerationFailed
    }

    private static func randomInviteCode() -> String {
        String((0..<inviteCodeLength).compactMap { _ in inviteCodeAlphabet.randomElement() })
    }

    // MARK: - Sync

    private func enqueueSync<Payload: Encodable & Sendable>(entityName: String, entityID: UUID, payload: Payload) async throws {
        try await SyncEngine.shared.enqueue(entityName: entityName, entityID: entityID, payload: payload)
    }
}

// MARK: - Sync payloads

/// `SquadMember` has no independent primary key of its own (composite `(squad_id, user_id)`,
/// `Models/SquadMember.swift`), so these payloads' `squadID`+`userID` pair is the real key a
/// `SyncBackend` should upsert on — `OutboxEvent.entityID` (always the squad's id here, for every
/// membership-scoped event) is only a coarse "which squad did this concern" correlation id, not a
/// unique row identifier.
private struct SquadSyncPayload: Codable, Sendable {
    let id: UUID
    let name: String
    let createdBy: UUID
    let inviteCode: String

    init(squad: Squad) {
        id = squad.id
        name = squad.name
        createdBy = squad.createdBy
        inviteCode = squad.inviteCode
    }
}

private struct SquadMemberSyncPayload: Codable, Sendable {
    let squadID: UUID
    let userID: UUID
    let role: SquadRole
}

private struct SquadMemberLeavePayload: Codable, Sendable {
    let squadID: UUID
    let userID: UUID
    let squadDeleted: Bool
}

/// Carries the sender/squad context `Nudge`/`NudgeArm` themselves have no field for (see
/// `sendNudge`'s doc comment) — the backend relay this task cannot build needs this to actually
/// show "a push with the sender's face" (spec §5.7).
private struct SquadNudgeSyncPayload: Codable, Sendable {
    let nudgeID: UUID
    let squadID: UUID
    let senderUserID: UUID
    let recipientUserID: UUID
    let ts: Date
}

private struct SquadSharedFreezeSyncPayload: Codable, Sendable {
    let squadID: UUID
    let usedByUserID: UUID
    let weekKey: String
    let usedAt: Date
}
