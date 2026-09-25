// Core/Sources/Core/Retention/VariableReward.swift
//
// docs/spec.md §8 rule 4 ("Variable reward at the unlock. 1 in ~6 unlocks triggers a surprise
// (badge, coin bonus, milestone animation, coach voice line). Keep it tasteful.") and §5.17
// (coins and badges live in the existing `Coin` / `Badge` models).
//
// How it works:
//   - `GoalCompletionCoordinator` calls `roll(sessionID:at:)` once, right after a lock ends as
//     `.earned`. Nothing else rolls: emergency unlocks, Time Bank spends and onboarding never do.
//   - Whether an unlock is a surprise, and which one, is a pure function of the lock session's id
//     (`outcome(for:)`, FNV-1a over the UUID string). Same session, same answer, in any process,
//     so tests can pin it and a second call can never re-roll a miss into a win.
//   - A surprise is applied once. The grant is written to an App Group ledger *before* it is
//     applied, so a repeat call (a second process, a retry) finds it and returns it without paying
//     twice. The app, intents and widgets share that ledger.
//   - The celebration reads the newest unrevealed grant (`consumePendingReveal(now:)`) at the
//     moment it reveals it, so the reveal doesn't race the roll.
//
// Kinds, all from the spec's list: bonus coins (credited to `Coin.balance`), a one-time "Lucky
// Unlock" badge (a `Badge` row; falls back to coins once it's already earned), and a coach voice
// line (copy only, nothing persisted beyond the ledger). "Milestone animation" is the reveal
// itself. Cosmetic grants are deliberately not a kind: `CosmeticsStore` owns ownership state and
// has no grant API (see the session report).
//
// Never sells or grants power: nothing here touches locks, streaks, freezes or the Time Bank.

import Foundation
import SwiftData
import os

/// One surprise granted on one earned unlock. `Codable` so it lives in the App Group ledger.
public struct VariableRewardGrant: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case bonusCoins
        case badge
        case coachLine
    }

    /// The lock session this surprise was rolled for.
    public let id: UUID
    public let kind: Kind
    /// Coins credited. `0` unless `kind == .bonusCoins`.
    public let coins: Int
    /// The `Badge.key` awarded. `nil` unless `kind == .badge`.
    public let badgeKey: String?
    /// Which coach line to show (`Copy.celebration.surpriseCoachLine(voice:index:)`). `nil` unless
    /// `kind == .coachLine`.
    public let coachLineIndex: Int?
    public let grantedAt: Date

    public init(id: UUID, kind: Kind, coins: Int = 0, badgeKey: String? = nil, coachLineIndex: Int? = nil, grantedAt: Date) {
        self.id = id
        self.kind = kind
        self.coins = coins
        self.badgeKey = badgeKey
        self.coachLineIndex = coachLineIndex
        self.grantedAt = grantedAt
    }
}

/// The pure part of a roll: what (if anything) a session would win, before any state is checked.
public enum VariableRewardOutcome: Sendable, Equatable {
    case bonusCoins(Int)
    case badge
    case coachLine(Int)
}

@MainActor
public final class VariableReward {
    public static let shared = VariableReward()

    /// "1 in ~6" (spec §8 rule 4).
    public nonisolated static let odds: UInt64 = 6
    /// Bonus sizes. Cosmetics cost 200-450 coins (`CosmeticsStore.catalog`), so a surprise is a
    /// nudge toward one, never a purchase on its own.
    public nonisolated static let bonusCoinAmounts = [25, 50, 75]
    /// The one-time surprise badge. Its title comes from `Copy.badges.title(forKey:)`'s fallback
    /// ("Lucky Unlock").
    public nonisolated static let surpriseBadgeKey = "lucky_unlock"
    /// How many coach lines each voice has (`Copy.celebration.surpriseCoachLine`).
    public nonisolated static let coachLineCount = 3
    /// A grant older than this is never revealed late on some unrelated celebration.
    public nonisolated static let revealWindow: TimeInterval = 10 * 60
    /// Ledger entries kept (older ones are pruned on each write).
    static let ledgerLimit = 40

    private let modelContainer: ModelContainer
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "VariableReward")
    static let ledgerKey = "zano.variableReward.ledger.v1"

    /// `internal` so `CoreTests` can pass an in-memory container and a throwaway defaults suite.
    init(modelContainer: ModelContainer = .appGroup, defaults: UserDefaults? = nil) {
        self.modelContainer = modelContainer
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    // MARK: - Pure roll

    /// What `sessionID` wins, or `nil` for the ~5 in 6 that win nothing. Deterministic: depends only
    /// on the UUID's characters, never on a random seed or the process.
    public nonisolated static func outcome(for sessionID: UUID) -> VariableRewardOutcome? {
        let hash = stableHash(sessionID.uuidString)
        guard hash % odds == 0 else { return nil }
        let rest = hash / odds
        let kinds = UInt64(VariableRewardGrant.Kind.allCases.count)
        switch rest % kinds {
        case 0:
            let amounts = bonusCoinAmounts
            return .bonusCoins(amounts[Int((rest / kinds) % UInt64(amounts.count))])
        case 1:
            return .badge
        default:
            return .coachLine(Int((rest / kinds) % UInt64(coachLineCount)))
        }
    }

    /// FNV-1a, 64-bit. `Hasher` is seeded per process, so it can't be used for a stable roll.
    nonisolated static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: - Roll + apply (idempotent)

    /// Rolls the surprise for an earned unlock and applies it once. Returns the grant (the same one
    /// on every repeat call for the same session), or `nil` when this unlock wins nothing.
    @discardableResult
    public func roll(sessionID: UUID, at date: Date = .now) -> VariableRewardGrant? {
        var ledger = loadLedger()
        if let existing = ledger.first(where: { $0.grant.id == sessionID }) {
            return existing.grant
        }
        guard let outcome = Self.outcome(for: sessionID) else { return nil }

        let context = ModelContext(modelContainer)
        let userID = fetchCurrentUserID(in: context)

        let grant: VariableRewardGrant
        switch outcome {
        case .bonusCoins(let amount):
            grant = VariableRewardGrant(id: sessionID, kind: .bonusCoins, coins: amount, grantedAt: date)
        case .badge:
            if let userID, hasBadge(Self.surpriseBadgeKey, userID: userID, in: context) {
                // Already has the one-time badge: the surprise becomes the smallest coin bonus.
                grant = VariableRewardGrant(id: sessionID, kind: .bonusCoins, coins: Self.bonusCoinAmounts[0], grantedAt: date)
            } else {
                grant = VariableRewardGrant(id: sessionID, kind: .badge, badgeKey: Self.surpriseBadgeKey, grantedAt: date)
            }
        case .coachLine(let index):
            grant = VariableRewardGrant(id: sessionID, kind: .coachLine, coachLineIndex: index, grantedAt: date)
        }

        // Claim first, then apply: a crash in between loses one surprise; the other order could
        // pay it twice.
        ledger.append(LedgerEntry(grant: grant, revealed: false))
        saveLedger(ledger)

        apply(grant, userID: userID, in: context)
        Analytics.shared.capture(event: "variable_reward_granted", properties: ["kind": grant.kind.rawValue])
        return grant
    }

    private func apply(_ grant: VariableRewardGrant, userID: UUID?, in context: ModelContext) {
        guard let userID else {
            logger.notice("No local user; surprise \(grant.kind.rawValue, privacy: .public) recorded without payout.")
            return
        }
        switch grant.kind {
        case .bonusCoins:
            var descriptor = FetchDescriptor<Coin>(predicate: #Predicate { $0.userID == userID })
            descriptor.fetchLimit = 1
            if let coin = try? context.fetch(descriptor).first {
                coin.balance += grant.coins
            } else {
                context.insert(Coin(userID: userID, balance: grant.coins))
            }
        case .badge:
            if let key = grant.badgeKey, !hasBadge(key, userID: userID, in: context) {
                context.insert(Badge(userID: userID, key: key, earnedAt: grant.grantedAt))
            }
        case .coachLine:
            return
        }
        do {
            try context.save()
        } catch {
            logger.error("Surprise payout failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Reveal

    /// The newest grant not yet shown, if it was granted within `revealWindow` of `now`. Marks it
    /// revealed, so exactly one celebration shows it.
    public func consumePendingReveal(now: Date = .now) -> VariableRewardGrant? {
        var ledger = loadLedger()
        guard let index = ledger.indices.reversed().first(where: {
            !ledger[$0].revealed && now.timeIntervalSince(ledger[$0].grant.grantedAt) <= Self.revealWindow
        }) else { return nil }
        ledger[index].revealed = true
        saveLedger(ledger)
        return ledger[index].grant
    }

    // MARK: - Ledger

    struct LedgerEntry: Codable, Sendable, Equatable {
        var grant: VariableRewardGrant
        var revealed: Bool
    }

    func loadLedger() -> [LedgerEntry] {
        guard let data = defaults.data(forKey: Self.ledgerKey),
              let entries = try? JSONDecoder().decode([LedgerEntry].self, from: data) else { return [] }
        return entries
    }

    private func saveLedger(_ entries: [LedgerEntry]) {
        let trimmed = Array(entries.suffix(Self.ledgerLimit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: Self.ledgerKey)
    }

    // MARK: - SwiftData

    private func fetchCurrentUserID(in context: ModelContext) -> UUID? {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.id
    }

    private func hasBadge(_ key: String, userID: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Badge>(predicate: #Predicate<Badge> { $0.userID == userID && $0.key == key })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }
}
