// FamilyRewards.swift
// Core / Family
//
// Parent reward minutes (session 45; docs/spec.md §5.23 Family Link, §5.2 Time Bank). A parent on an active
// link sends their teen bonus Time Bank minutes with an optional short note ("+30 min, nice work on the
// homework"). The teen claims it in the app and the minutes land in today's Time Bank, where they expire at
// midnight like every other Time Bank minute.
//
// Mirrors `backend/supabase/migrations/0010_family_rewards.sql`. The server enforces the caps and the "only the
// parent sends, only the teen claims, a left link voids" rules; `FamilyRewardRules` mirrors the same numbers
// so the app can grey out chips early and is unit-tested without a server.
//
// Never a punishment path: minutes are only ever added. There is no way for a parent to take minutes back.
//
// "From family" is kept apart from "earned by goals": the deposit goes into the same per-day `TimeBank` row
// (so it spends and expires exactly like other minutes), and `FamilyRewardLedger` records how much of that
// day's total came from family, so screens can say so honestly and nothing counts it as a goal win.

import Foundation

// MARK: - Wire type

public struct FamilyReward: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let linkId: UUID
    public let fromUser: UUID
    public let toUser: UUID
    public let minutes: Int
    public let note: String?
    public let createdAt: Date?
    public let claimedAt: Date?
    public let voidedAt: Date?

    public init(
        id: UUID, linkId: UUID, fromUser: UUID, toUser: UUID, minutes: Int, note: String? = nil,
        createdAt: Date? = nil, claimedAt: Date? = nil, voidedAt: Date? = nil
    ) {
        self.id = id
        self.linkId = linkId
        self.fromUser = fromUser
        self.toUser = toUser
        self.minutes = minutes
        self.note = note
        self.createdAt = createdAt
        self.claimedAt = claimedAt
        self.voidedAt = voidedAt
    }
}

// MARK: - Rules (mirrors 0010_family_rewards.sql)

public enum FamilyRewardRules {
    /// The chips the parent picks from.
    public static let chipMinutes = [10, 15, 30, 60]
    /// Server check: one reward is at most this many minutes.
    public static let maxMinutesPerReward = 120
    /// Server trigger: at most this many minutes per link in any rolling 24 hours.
    public static let maxMinutesPerDay = 240
    public static let dailyWindow: TimeInterval = 24 * 3_600
    /// Server check: the note is at most this many characters.
    public static let noteMaxLength = 80

    /// Plain text only: line breaks and other control characters become spaces, runs of spaces collapse,
    /// the ends are trimmed and the result is cut to `noteMaxLength`. Empty means no note.
    public static func sanitizedNote(_ raw: String) -> String? {
        let flattened = String(raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
        let collapsed = flattened.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let cut = String(collapsed.prefix(noteMaxLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }

    /// Minutes this link has sent in the rolling 24 hours before `now` (voided rewards don't count, like the
    /// server's trigger).
    public static func sentInWindow(_ rewards: [FamilyReward], now: Date) -> Int {
        rewards.reduce(0) { total, reward in
            guard reward.voidedAt == nil, let created = reward.createdAt,
                  created > now.addingTimeInterval(-dailyWindow), created <= now else { return total }
            return total + reward.minutes
        }
    }

    /// Minutes the parent can still send right now.
    public static func remainingAllowance(_ rewards: [FamilyReward], now: Date) -> Int {
        max(0, maxMinutesPerDay - sentInWindow(rewards, now: now))
    }

    /// `true` when `minutes` is a sendable amount, ignoring the daily total.
    public static func isValidAmount(_ minutes: Int) -> Bool {
        (1...maxMinutesPerReward).contains(minutes)
    }

    /// The chips that fit what's left of today's allowance.
    public static func availableChips(_ rewards: [FamilyReward], now: Date) -> [Int] {
        let left = remainingAllowance(rewards, now: now)
        return chipMinutes.filter { $0 <= left }
    }

    /// A reward is void when its link has been left (or the server already voided it). A void reward is
    /// never claimable and never deposits anything.
    public static func isVoid(_ reward: FamilyReward, link: FamilyLink?) -> Bool {
        if reward.voidedAt != nil { return true }
        guard let link, link.id == reward.linkId else { return true }
        return link.status != .active
    }

    /// The rewards waiting for `teenID` to claim on `link`, oldest first.
    public static func claimable(_ rewards: [FamilyReward], link: FamilyLink?, teenID: UUID?) -> [FamilyReward] {
        guard let teenID else { return [] }
        return rewards
            .filter { $0.toUser == teenID && $0.claimedAt == nil && !isVoid($0, link: link) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
}

// MARK: - Local ledger ("from family", and deposit-once)

/// On-device record of the family rewards already deposited (so a reward deposits once, whatever happens
/// with retries or double taps) and how many of each day's Time Bank minutes came from family. Lives in the
/// App Group defaults next to the Time Bank mirrors. Written only by `TimeBankEngine.depositFamilyReward`.
public enum FamilyRewardLedger {
    private static let claimedKey = "zano.familyRewards.depositedIDs.v1"
    private static let minutesKey = "zano.familyRewards.minutesByDay.v1"
    static let retainedIDs = 500
    static let retentionDays = 60

    public static func hasDeposited(_ rewardID: UUID, defaults: UserDefaults = SharedDefaults.store) -> Bool {
        loadIDs(defaults).contains(rewardID.uuidString)
    }

    /// Minutes from family on `date`'s local day.
    public static func minutes(on date: Date, calendar: Calendar = .current, defaults: UserDefaults = SharedDefaults.store) -> Int {
        loadMinutes(defaults)[ReclaimedOpens.dayKey(date, calendar: calendar)] ?? 0
    }

    static func record(
        _ rewardID: UUID, minutes: Int, on date: Date,
        calendar: Calendar = .current, defaults: UserDefaults = SharedDefaults.store
    ) {
        var ids = loadIDs(defaults)
        ids.append(rewardID.uuidString)
        if ids.count > retainedIDs { ids = Array(ids.suffix(retainedIDs)) }
        defaults.set(ids, forKey: claimedKey)

        var byDay = loadMinutes(defaults)
        byDay[ReclaimedOpens.dayKey(date, calendar: calendar), default: 0] += minutes
        if byDay.count > retentionDays {
            let keep = Set(byDay.keys.sorted().suffix(retentionDays))
            byDay = byDay.filter { keep.contains($0.key) }
        }
        defaults.set(byDay, forKey: minutesKey)
    }

    private static func loadIDs(_ defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: claimedKey) ?? []
    }

    private static func loadMinutes(_ defaults: UserDefaults) -> [String: Int] {
        (defaults.dictionary(forKey: minutesKey) as? [String: Int]) ?? [:]
    }
}

/// Outcome of `TimeBankEngine.depositFamilyReward`.
public enum FamilyRewardDepositResult: Sendable, Equatable {
    /// Minutes added to today's Time Bank.
    case deposited(minutes: Int)
    /// This reward was deposited before; nothing was added.
    case alreadyDeposited
}

// MARK: - Claim, then deposit

/// The teen's side: claim on the server, then deposit locally, once. The server call is injected so the
/// rules are tested without a network.
///
/// Order matters: the server claim comes first, so a void reward (link left) never adds a minute. If the
/// server says the reward was already claimed (another device, or a retry after a crash), nothing is
/// deposited. Known edge: if the claim succeeds and the local deposit then fails (no local `User` yet),
/// those minutes are lost rather than doubled; the error is shown and nothing else breaks.
@MainActor
public enum FamilyRewardClaim {
    public static func claimAndDeposit(
        _ reward: FamilyReward,
        link: FamilyLink?,
        engine: TimeBankEngine = .shared,
        now: Date = .now,
        calendar: Calendar = .current,
        ledger defaults: UserDefaults = SharedDefaults.store,
        claim: (UUID) async throws -> Int
    ) async throws -> FamilyRewardDepositResult {
        guard !FamilyRewardRules.isVoid(reward, link: link) else { throw FamilyLinkError.server(code: "void") }
        guard !FamilyRewardLedger.hasDeposited(reward.id, defaults: defaults) else { return .alreadyDeposited }
        let minutes: Int
        do {
            minutes = try await claim(reward.id)
        } catch FamilyLinkError.server(let code) where code == "already_claimed" {
            return .alreadyDeposited
        }
        return try await engine.depositFamilyReward(
            rewardID: reward.id, minutes: minutes, on: now, calendar: calendar, ledger: defaults
        )
    }
}
