// Core/Sources/Core/Social/DuelManager.swift
//
// docs/spec.md §5.7 Squads & Duels — the Duel half:
//   "Duel: 7-day head-to-head, points per verified goal, loser's shield shows the winner's chosen
//   taunt for a day (opt-in, keep it friendly)."
// Also docs/spec.md §13 (Data Model — `duels`) and CLAUDE.md: "No restrictive goals ever...
// Additive goals only" — a duel's points can only ever come from real, verified additive-goal
// completions (`GoalEvent.kind == .complete` / `.planB`, `verified == true`); this file never
// scores a miss, a lower value, or anything restrictive as a point.
//
// This file has no fixed public shape in the orchestrator's SYSTEM CONTRACTS block, so its API is
// designed here to satisfy this task and spec §5.7, following `SquadManager.swift`'s (this same
// session's sibling file) and `LockEngineManager`/`GymVerifier`'s established conventions —
// actor-owned `ModelContext`, `Sendable` snapshot structs returned instead of live `@Model`
// instances, `LocalizedError` diagnostics kept out of `Core/Sources/Core/Copy`.
//
// `Duel` (Core/Sources/Core/Models/Duel.swift, Session 1) and its `DuelStatus` enum are reused
// verbatim — every field/case name below matches that file exactly.
//
// Known architectural gap (see this task's `knownIssues`): exactly the same one `SquadManager`'s
// header comment documents for squad ring aggregation, applied to a duel's two sides. This
// device's local store only ever holds the signed-in user's own `GoalEvent` rows
// (`Models/User.swift`'s doc comment), so `recomputeLocalPoints(duelID:)` can only ever compute
// the *signed-in* participant's `aPoints`/`bPoints` for real — the opponent's true point count is
// whatever the backend last synced down into the local `Duel.aPoints`/`bPoints` mirror (no pull
// path exists yet — `SyncEngine.pullAndMerge()` is today's documented TODO no-op — so today that
// mirror is simply whatever this method itself last wrote). This is the honest, real
// implementation of "my side of the tally" rather than a stub, with every call site documented
// exactly where the other side's truth actually has to come from.

import Foundation
import SwiftData
import os

// MARK: - Errors

/// Errors `DuelManager` throws itself, as opposed to errors bubbled up from SwiftData. Kept as
/// plain, developer-facing diagnostics — mirroring `LockEngineError`/`SquadManagerError`'s
/// documented convention — never routed through `Core/Sources/Core/Copy`.
public enum DuelManagerError: Error, Sendable, LocalizedError {
    /// No local `User` row exists yet to attribute this action to.
    case noSignedInUser
    /// No local `Duel` exists with this id.
    case duelNotFound(UUID)
    /// `userID` is neither `aUser` nor `bUser` on this duel.
    case notAParticipant(duelID: UUID, userID: UUID)
    /// `respond(duelID:userID:accept:)` was called on a duel not currently `.pending`.
    case invalidStatusTransition(from: DuelStatus, to: DuelStatus)
    /// `createDuel(challengerID:opponentID:)` was called with the same id twice.
    case cannotDuelSelf
    /// `Calendar.date(byAdding:to:)` failed to compute the 7-day end date — practically
    /// unreachable, but never silently produce a `Duel` with a nonsensical range.
    case invalidDateRange

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser:
            "No local User row exists yet."
        case .duelNotFound(let id):
            "No Duel found with id \(id)."
        case .notAParticipant(let duelID, let userID):
            "\(userID) is not a participant in duel \(duelID)."
        case .invalidStatusTransition(let from, let to):
            "Cannot transition duel from \(from.rawValue) to \(to.rawValue)."
        case .cannotDuelSelf:
            "A user cannot duel themselves."
        case .invalidDateRange:
            "Could not compute a valid 7-day duel date range."
        }
    }
}

// MARK: - Sendable snapshot

/// A `Sendable` value copy of a `Duel` row, returned by every public `DuelManager` API instead of
/// the live `@Model` instance — matching `SquadManager.SquadSnapshot`'s identical reasoning (see
/// that file's doc comment).
public struct DuelSnapshot: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let aUser: UUID
    public let bUser: UUID
    public let startDate: Date
    public let endDate: Date
    public let aPoints: Int
    public let bPoints: Int
    public let status: DuelStatus

    public init(id: UUID, aUser: UUID, bUser: UUID, startDate: Date, endDate: Date, aPoints: Int, bPoints: Int, status: DuelStatus) {
        self.id = id
        self.aUser = aUser
        self.bUser = bUser
        self.startDate = startDate
        self.endDate = endDate
        self.aPoints = aPoints
        self.bPoints = bPoints
        self.status = status
    }

    /// The winning side's user id — `nil` while `status != .complete`, or on an exact tie.
    public var winner: UUID? {
        guard status == .complete, aPoints != bPoints else { return nil }
        return aPoints > bPoints ? aUser : bUser
    }
}

// MARK: - DuelManager

/// The sole owner of local `Duel` rows: creation, accept/decline, the 7-day lifecycle, and this
/// device's half of the point tally (spec §5.7). A plain `actor`, matching `SquadManager`'s and
/// `SyncEngine`'s identical convention — see `SquadManager`'s type doc comment for the reasoning.
public actor DuelManager {
    public static let shared = DuelManager()

    /// docs/spec.md §5.7: "Duel: 7-day head-to-head".
    public static let durationDays = 7

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "DuelManager")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container — every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
    }

    // MARK: - Create / respond (status transitions: pending → active | declined)

    /// Creates a new 7-day duel between `challengerID` and `opponentID`, starting at `startDate`'s
    /// local calendar day. Status begins `.pending` (spec §5.7's implicit invite step — a duel
    /// isn't live until `respond` accepts it) with both point totals at zero.
    @discardableResult
    public func createDuel(challengerID: UUID, opponentID: UUID, startDate: Date = .now) async throws -> DuelSnapshot {
        guard challengerID != opponentID else { throw DuelManagerError.cannotDuelSelf }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        guard let end = calendar.date(byAdding: .day, value: Self.durationDays, to: start) else {
            throw DuelManagerError.invalidDateRange
        }

        let duel = Duel(aUser: challengerID, bUser: opponentID, startDate: start, endDate: end, aPoints: 0, bPoints: 0, status: .pending)
        context.insert(duel)
        try context.save()

        try? await enqueueSync(entityName: "Duel", entityID: duel.id, payload: DuelSyncPayload(duel: duel))
        Analytics.shared.capture(event: "duel_created", properties: ["duel_id": duel.id.uuidString])
        logger.notice("Created duel \(duel.id.uuidString, privacy: .public), pending response.")
        return snapshot(of: duel)
    }

    /// Transitions a `.pending` duel to `.active` (accepted) or `.declined`. `userID` must be one
    /// of the duel's two participants — spec §13's `duels_participant` RLS policy governs who may
    /// do this remotely; this mirrors the same rule locally rather than trusting an arbitrary id.
    @discardableResult
    public func respond(duelID: UUID, userID: UUID, accept: Bool) async throws -> DuelSnapshot {
        guard let duel = try fetchDuel(id: duelID) else { throw DuelManagerError.duelNotFound(duelID) }
        guard duel.aUser == userID || duel.bUser == userID else {
            throw DuelManagerError.notAParticipant(duelID: duelID, userID: userID)
        }
        let target: DuelStatus = accept ? .active : .declined
        guard duel.status == .pending else {
            throw DuelManagerError.invalidStatusTransition(from: duel.status, to: target)
        }

        duel.status = target
        try context.save()

        try? await enqueueSync(entityName: "Duel", entityID: duel.id, payload: DuelSyncPayload(duel: duel))
        Analytics.shared.capture(
            event: accept ? "duel_accepted" : "duel_declined",
            properties: ["duel_id": duelID.uuidString]
        )
        return snapshot(of: duel)
    }

    // MARK: - Lifecycle (status transition: active → complete)

    /// Marks every local `.active` duel whose `endDate` has passed as `.complete` (spec §5.7's
    /// 7-day timer expiring). Idempotent and cheap to call frequently (app launch, a background
    /// refresh, or right before rendering a Duel screen).
    ///
    /// Filters `status` in plain Swift after an `endDate`-only `#Predicate` fetch, mirroring
    /// `LockEngineManager.isGoalVerified`'s documented tradeoff re: enum equality inside
    /// `#Predicate` on an unverified SDK.
    @discardableResult
    public func refreshStatuses(asOf date: Date = .now) async throws -> [DuelSnapshot] {
        let candidates = try context.fetch(FetchDescriptor<Duel>(predicate: #Predicate<Duel> { $0.endDate <= date }))
        let expiring = candidates.filter { $0.status == .active }
        guard !expiring.isEmpty else { return [] }

        for duel in expiring {
            duel.status = .complete
        }
        try context.save()

        var results: [DuelSnapshot] = []
        for duel in expiring {
            try? await enqueueSync(entityName: "Duel", entityID: duel.id, payload: DuelSyncPayload(duel: duel))
            Analytics.shared.capture(event: "duel_completed", properties: ["duel_id": duel.id.uuidString])
            results.append(snapshot(of: duel))
        }
        return results
    }

    // MARK: - Point tally (spec §5.7: "points per verified goal")

    /// Recomputes and persists the signed-in participant's point total on `duelID` from this
    /// device's local `GoalEvent` history: one point per verified goal completion
    /// (`kind == .complete` or `.planB` — both are genuine, verified completions, just at
    /// different difficulty; `.freeze`/`.miss`/`.log`/`.verify` never score, and neither Plan B
    /// nor anything else here is ever a restrictive/negative point, per CLAUDE.md's additive-goals
    /// rule) logged within `[duel.startDate, min(duel.endDate, now)]`. Only ever touches whichever
    /// side (`aPoints`/`bPoints`) belongs to the signed-in user — see this file's header comment
    /// for why the opponent's side cannot be computed here.
    ///
    /// A no-op (returns the duel unchanged) if the duel isn't `.active`/`.complete` yet, or if the
    /// signed-in user isn't one of its two participants.
    @discardableResult
    public func recomputeLocalPoints(duelID: UUID) async throws -> DuelSnapshot {
        guard let duel = try fetchDuel(id: duelID) else { throw DuelManagerError.duelNotFound(duelID) }
        guard duel.status == .active || duel.status == .complete else { return snapshot(of: duel) }
        guard let currentUserID = try? fetchCurrentUser().id,
              duel.aUser == currentUserID || duel.bUser == currentUserID
        else { return snapshot(of: duel) }

        let windowEnd = min(duel.endDate, .now)
        let points = try countVerifiedGoalPoints(userID: currentUserID, from: duel.startDate, to: windowEnd)

        if duel.aUser == currentUserID {
            duel.aPoints = points
        } else {
            duel.bPoints = points
        }
        try context.save()

        try? await enqueueSync(entityName: "Duel", entityID: duel.id, payload: DuelSyncPayload(duel: duel))
        return snapshot(of: duel)
    }

    /// Live-increment hook: call this immediately after writing a new verified `GoalEvent` for
    /// `userID` (LockEngine/Verification/Intents territory, none of which this file owns) so any
    /// of that user's active duels reflect the point right away instead of waiting for a full
    /// `recomputeLocalPoints` rescan.
    ///
    /// TODO(cross-module — Verification/LockEngine/Intents sessions): nothing calls this yet.
    /// The genuine integration point is wherever a verified `.complete`/`.planB` `GoalEvent` is
    /// written (e.g. `FocusSessionVerifier.endSession`, `GymVerifier`-driven completion, the
    /// `LogProteinIntent`/`LogWaterIntent`/etc. App Intents) — that code should call
    /// `DuelManager.shared.applyVerifiedGoalEvent(userID:verifiedAt:)` right after. Until then,
    /// `recomputeLocalPoints(duelID:)` above is the complete, correct, if less immediate, way to
    /// keep a duel's local side accurate (e.g. called when a Duel screen appears).
    public func applyVerifiedGoalEvent(userID: UUID, verifiedAt date: Date = .now) async {
        guard let duels = try? fetchActiveDuels(involving: userID) else { return }
        let applicable = duels.filter { date >= $0.startDate && date < $0.endDate }
        guard !applicable.isEmpty else { return }

        for duel in applicable {
            if duel.aUser == userID {
                duel.aPoints += 1
            } else if duel.bUser == userID {
                duel.bPoints += 1
            }
        }
        try? context.save()

        for duel in applicable {
            try? await enqueueSync(entityName: "Duel", entityID: duel.id, payload: DuelSyncPayload(duel: duel))
        }
    }

    // MARK: - Introspection

    public func activeDuels(involving userID: UUID) async throws -> [DuelSnapshot] {
        try fetchActiveDuels(involving: userID).map { self.snapshot(of: $0) }
    }

    public func duel(id: UUID) async throws -> DuelSnapshot? {
        try fetchDuel(id: id).map { self.snapshot(of: $0) }
    }

    // MARK: - SwiftData

    private func fetchDuel(id: UUID) throws -> Duel? {
        var descriptor = FetchDescriptor<Duel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Small expected result set per user (a handful of concurrent duels at most), so an
    /// unfiltered fetch + in-memory filter is preferable to risking enum/relationship equality
    /// inside `#Predicate` on an unverified SDK — same reasoning as `refreshStatuses`.
    private func fetchActiveDuels(involving userID: UUID) throws -> [Duel] {
        try context.fetch(FetchDescriptor<Duel>()).filter {
            $0.status == .active && ($0.aUser == userID || $0.bUser == userID)
        }
    }

    /// This device's local store holds exactly one `User` row (see `Models/User.swift`'s doc
    /// comment), so the first (only) one is always the right one.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw DuelManagerError.noSignedInUser
        }
        return user
    }

    /// Mirrors `LockEngineManager.isGoalVerified(goalID:coveringDayOf:)`'s documented tradeoff:
    /// fetches by the `#Predicate`-safe fields only (`verified`, `ts`), then filters the
    /// optional-relationship (`event.user?.id`) and enum (`event.kind`) comparisons in plain
    /// Swift.
    private func countVerifiedGoalPoints(userID: UUID, from start: Date, to end: Date) throws -> Int {
        guard end > start else { return 0 }
        let events = try context.fetch(
            FetchDescriptor<GoalEvent>(predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= start && $0.ts < end })
        )
        return events.filter { event in
            event.user?.id == userID && (event.kind == .complete || event.kind == .planB)
        }.count
    }

    private func snapshot(of duel: Duel) -> DuelSnapshot {
        DuelSnapshot(
            id: duel.id,
            aUser: duel.aUser,
            bUser: duel.bUser,
            startDate: duel.startDate,
            endDate: duel.endDate,
            aPoints: duel.aPoints,
            bPoints: duel.bPoints,
            status: duel.status
        )
    }

    // MARK: - Sync

    private func enqueueSync<Payload: Encodable & Sendable>(entityName: String, entityID: UUID, payload: Payload) async throws {
        try await SyncEngine.shared.enqueue(entityName: entityName, entityID: entityID, payload: payload)
    }
}

// MARK: - Sync payload

private struct DuelSyncPayload: Codable, Sendable {
    let id: UUID
    let aUser: UUID
    let bUser: UUID
    let startDate: Date
    let endDate: Date
    let aPoints: Int
    let bPoints: Int
    let status: DuelStatus

    init(duel: Duel) {
        id = duel.id
        aUser = duel.aUser
        bUser = duel.bUser
        startDate = duel.startDate
        endDate = duel.endDate
        aPoints = duel.aPoints
        bPoints = duel.bPoints
        status = duel.status
    }
}
