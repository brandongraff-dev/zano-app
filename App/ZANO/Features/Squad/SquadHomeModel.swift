// SquadHomeModel.swift
// App / ZANO / Features / Squad
//
// The Squad tab's state (docs/spec.md §5.7 Squads & Duels, §5.4 Ghost Mode for the solo duel).
// Everything is read from the Core engines (`SquadManager`, `DuelManager`, `StreakEngine`); this
// file owns no rules of its own beyond turning their errors into `Copy.squad` messages.
//
// Offline behaviour (the squad backend isn't live yet): `SquadManager.isBackendConnected` is
// `false` until a real `SquadDirectory` is configured. While it is:
//   - creating a squad still works (it is a local row + a queued sync), which "reserves" the code;
//   - joining someone else's code can't resolve, so the code is saved here and retried on the next
//     load once the backend is connected;
//   - nudges are written and queued (never claimed as delivered);
//   - head-to-head duels are not offered; "Beat last week" always works.

import Foundation
import Observation
import SwiftUI
import Core

// MARK: - Squad style (emblem + color, local only)

/// The emblem and color picked when creating a squad. `Squad` (Core model) has no columns for
/// these and the backend schema doesn't either, so they are a per-device preference.
struct SquadStyle: Codable, Equatable, Sendable {
    var emoji: String
    var colorIndex: Int

    static let emojis = ["🔥", "⚡️", "🏋️", "🌅", "🐺", "🚀", "🎯", "🧊"]
    static let palette: [Color] = [
        Theme.Colors.accent,
        Theme.Colors.Ring.workout,
        Theme.Colors.Ring.protein,
        Theme.Colors.Ring.focus,
        Theme.Colors.Ring.water,
        Theme.Colors.Ring.steps,
        Theme.Colors.Ring.sunriseAlarm,
        Theme.Colors.Ring.creatine,
    ]
    static let `default` = SquadStyle(emoji: "🔥", colorIndex: 0)

    var color: Color { Self.palette[max(0, min(colorIndex, Self.palette.count - 1))] }

    private static func key(_ squadID: UUID) -> String { "zano.squad.style.\(squadID.uuidString)" }

    static func load(for squadID: UUID) -> SquadStyle {
        guard let data = UserDefaults.standard.data(forKey: key(squadID)),
              let style = try? JSONDecoder().decode(SquadStyle.self, from: data)
        else { return .default }
        return style
    }

    static func save(_ style: SquadStyle, for squadID: UUID) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        UserDefaults.standard.set(data, forKey: key(squadID))
    }
}

// MARK: - Member row data

struct SquadMemberRow: Identifiable, Equatable, Sendable {
    let userID: UUID
    let name: String
    let isMe: Bool
    let isOwner: Bool
    /// 7 days, Monday first; empty when the member's rings haven't synced.
    let days: [SquadMemberRingDay]
    let dataAvailable: Bool
    /// `nil` when unknown (another member, no backend).
    let streak: Int?
    /// `nil` when unknown.
    let isLocked: Bool?
    let nudgesLeft: Int

    var id: UUID { userID }
    var fullDays: Int { days.filter { $0.totalGoals > 0 && $0.completedGoals >= $0.totalGoals }.count }
    var weekFraction: Double {
        let total = days.reduce(0) { $0 + $1.totalGoals }
        guard total > 0 else { return 0 }
        return Double(days.reduce(0) { $0 + min($1.completedGoals, $1.totalGoals) }) / Double(total)
    }
}

// MARK: - Model

@MainActor
@Observable
final class SquadHomeModel {
    enum Phase: Equatable { case loading, ready }

    enum JoinOutcome: Equatable {
        case joined(SquadSnapshot)
        /// Backend not live: the code is saved and retried later.
        case savedForLater(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var backendConnected = false
    private(set) var liveRings = false
    private(set) var myUserID: UUID?
    private(set) var squad: SquadSnapshot?
    private(set) var style: SquadStyle = .default
    private(set) var rows: [SquadMemberRow] = []
    private(set) var weekStart: Date = .now
    private(set) var freeze: SquadSharedFreezeStatus?
    private(set) var duels: [DuelSnapshot] = []
    private(set) var solo: SoloWeekDuel?
    private(set) var soloPrevious: SoloWeekDuel?
    private(set) var pendingJoinCode: String?

    private static let pendingJoinKey = "zano.squad.pendingJoinCode.v1"

    init() {
        pendingJoinCode = UserDefaults.standard.string(forKey: Self.pendingJoinKey)
    }

    var otherMembers: [SquadMemberRow] { rows.filter { !$0.isMe } }

    /// Shared weekly ring (spec §5.7): the average of every member whose rings are known.
    var squadWeekFraction: Double {
        let known = rows.filter(\.dataAvailable)
        guard !known.isEmpty else { return 0 }
        return known.reduce(0) { $0 + $1.weekFraction } / Double(known.count)
    }

    func name(for userID: UUID) -> String {
        rows.first(where: { $0.userID == userID })?.name ?? Copy.squad.memberName(index: 1)
    }

    // MARK: Load

    func load() async {
        let squads = SquadManager.shared
        let duelManager = DuelManager.shared

        backendConnected = await squads.isBackendConnected
        liveRings = await squads.hasLiveSquadmateRings
        let me = await squads.currentUserID()
        myUserID = me

        if backendConnected, let code = pendingJoinCode {
            if (try? await squads.joinSquad(inviteCode: code)) != nil { setPendingJoinCode(nil) }
        }

        let mine = (try? await squads.mySquads()) ?? []
        let current = mine.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }.first
        squad = current

        if let current {
            style = SquadStyle.load(for: current.id)
            await loadBoard(squadID: current.id, me: me)
        } else {
            rows = []
            freeze = nil
        }

        _ = try? await duelManager.refreshStatuses()
        if let me {
            let all = (try? await duelManager.duels(involving: me)) ?? []
            for duel in all where duel.status == .active {
                _ = try? await duelManager.recomputeLocalPoints(duelID: duel.id)
            }
            duels = (try? await duelManager.duels(involving: me)) ?? all
        } else {
            duels = []
        }

        let currentSolo = await duelManager.soloWeekDuel()
        solo = currentSolo
        if let currentSolo {
            soloPrevious = await duelManager.soloWeekDuel(asOf: currentSolo.weekStart.addingTimeInterval(-60))
        }

        phase = .ready
    }

    private func loadBoard(squadID: UUID, me: UUID?) async {
        let squads = SquadManager.shared
        let members = (try? await squads.members(of: squadID)) ?? []
        let board = try? await squads.weeklyRingBoard(squadID: squadID)
        weekStart = board?.weekStart ?? .now
        freeze = await squads.sharedFreezeProtection(squadID: squadID)

        let myStreak = await StreakEngine.shared.currentStreak()
        let locked = SharedDefaults.activeLockSessionID != nil

        // Me first, then everyone else in a stable order so "Squadmate 2" stays the same person.
        let ordered = members.sorted { lhs, rhs in
            if lhs.userID == me { return true }
            if rhs.userID == me { return false }
            return lhs.userID.uuidString < rhs.userID.uuidString
        }
        var built: [SquadMemberRow] = []
        var mateIndex = 0
        for member in ordered {
            let isMe = member.userID == me
            if !isMe { mateIndex += 1 }
            let rings = board?.members.first(where: { $0.userID == member.userID })
            let left = isMe ? 0 : await squads.nudgesRemainingToday(to: member.userID)
            built.append(SquadMemberRow(
                userID: member.userID,
                name: isMe ? Copy.squad.youName : Copy.squad.memberName(index: mateIndex),
                isMe: isMe,
                isOwner: member.role == .owner,
                days: rings?.days ?? [],
                dataAvailable: rings?.dataAvailable ?? false,
                streak: isMe ? myStreak : nil,
                isLocked: isMe ? locked : nil,
                nudgesLeft: left
            ))
        }
        rows = built
    }

    // MARK: Create / join / leave

    @discardableResult
    func createSquad(name: String, style newStyle: SquadStyle) async throws -> SquadSnapshot {
        let created = try await SquadManager.shared.createSquad(name: name)
        SquadStyle.save(newStyle, for: created.id)
        await load()
        return created
    }

    func joinSquad(code rawCode: String) async throws -> JoinOutcome {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else { throw SquadManagerError.invalidInviteCode }
        do {
            let joined = try await SquadManager.shared.joinSquad(inviteCode: code)
            setPendingJoinCode(nil)
            await load()
            return .joined(joined)
        } catch SquadManagerError.squadNotFoundForInviteCode where !backendConnected {
            setPendingJoinCode(code)
            return .savedForLater(code)
        }
    }

    func clearPendingJoin() { setPendingJoinCode(nil) }

    func leaveSquad() async throws {
        guard let squad else { return }
        try await SquadManager.shared.leaveSquad(squadID: squad.id)
        await load()
    }

    private func setPendingJoinCode(_ code: String?) {
        pendingJoinCode = code
        if let code {
            UserDefaults.standard.set(code, forKey: Self.pendingJoinKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingJoinKey)
        }
    }

    // MARK: Nudge

    /// Sends a squad nudge and returns the line to show. Never claims delivery while offline.
    func nudge(_ member: SquadMemberRow) async -> String {
        guard let squad, let me = myUserID else { return Copy.squad.nudgeFailed }
        do {
            try await SquadManager.shared.sendNudge(squadID: squad.id, from: me, to: member.userID)
            let left = await SquadManager.shared.nudgesRemainingToday(to: member.userID)
            rows = rows.map { row in
                guard row.userID == member.userID else { return row }
                return SquadMemberRow(
                    userID: row.userID, name: row.name, isMe: row.isMe, isOwner: row.isOwner, days: row.days,
                    dataAvailable: row.dataAvailable, streak: row.streak, isLocked: row.isLocked, nudgesLeft: left
                )
            }
            return backendConnected ? Copy.squad.nudgeSent : Copy.squad.nudgeQueued
        } catch SquadManagerError.dailyNudgeCapReached {
            return Copy.squad.nudgeCapReached
        } catch SquadManagerError.nudgeCooldownActive {
            return Copy.squad.nudgeCooldown
        } catch {
            return Copy.squad.nudgeFailed
        }
    }

    // MARK: Duels

    /// Challenges a squadmate. Only offered while the backend is connected (they must accept).
    func challenge(_ opponentID: UUID) async throws {
        guard let me = myUserID else { throw SquadManagerError.noSignedInUser }
        try await DuelManager.shared.createDuel(challengerID: me, opponentID: opponentID)
        await load()
    }

    // MARK: Errors → Copy

    static func message(for error: Error) -> String {
        if let error = error as? SquadManagerError {
            switch error {
            case .noSignedInUser: return Copy.squad.errorNoUser
            case .invalidName: return Copy.squad.errorInvalidName
            case .invalidInviteCode: return Copy.squad.errorInvalidCode
            case .squadNotFoundForInviteCode: return Copy.squad.errorCodeNotFound
            case .squadFull: return Copy.squad.errorSquadFull
            default: return Copy.squad.errorGeneric
            }
        }
        if let error = error as? DuelManagerError, case .noSignedInUser = error {
            return Copy.squad.errorNoUser
        }
        return Copy.squad.errorGeneric
    }
}
