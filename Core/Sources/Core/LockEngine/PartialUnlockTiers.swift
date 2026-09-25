// Core/Sources/Core/LockEngine/PartialUnlockTiers.swift
//
// docs/spec.md §2 (The Core Loop → "Unlock"): "Partial unlocks are possible ('finish 2 of 3
// goals to unlock messaging apps, all 3 for TikTok')."
// docs/spec.md §4 (v2 feature list): "Partial unlock tiers (messaging vs social vs games)."
//
// Not part of this task's SYSTEM CONTRACTS block — only `LockEngineManager`,
// `FocusSessionVerifier`, `GymVerifier`, `TimeBankEngine`, `StreakEngine`, `AdaptiveGoalEngine`,
// and the three LiveActivity attribute structs have an orchestrator-fixed public shape. This
// file's public API is this session's own design: given a `LockSet` (read exactly as
// `Models/LockSet.swift`, owned by another agent, already declares it) and the set of goal ids
// completed so far, compute which tier(s) of that lock's apps are unlocked.
//
// Persistence (Wave 2E): `PartialUnlockTierStore` below keeps each lock set's ladder as a Codable
// blob in the App Group, keyed by `LockSet.id`. Device-local on purpose: tiers carry FamilyControls
// tokens, which never leave the device (spec §13, §24), and spec §13 has no tiers table, so no
// SwiftData/Supabase migration. `TierEditorView` (App/ZANO/Features/LockSetup) writes it;
// `LockEngineManager.evaluateUnlockEligibility` reads it and lifts reached tiers' apps.
//
// The evaluation itself stays pure: no SwiftData, no ManagedSettings side effects. It hands back a
// `FamilyActivitySelection` `LockEngineManager` (which owns the `ManagedSettingsStore`) applies.

import Foundation
import FamilyControls

// MARK: - PartialUnlockTier

/// One rung of a partial-unlock ladder for a `LockSet` (docs/spec.md §2, §4): once at least
/// `requiredCompletedGoalCount` of the active lock's required goals are verified/complete,
/// `selection` becomes safe to remove from the shield — even while the rest of the `LockSet`
/// stays locked.
///
/// Thresholds are a *count*, not a fixed set of specific goal identities — spec §2's example
/// ("finish 2 of 3 goals to unlock messaging apps") reads as "any 2 of the 3", not "these
/// particular 2" — so `PartialUnlockTiers.evaluate` only ever looks at
/// `completedGoalIDs.count` against this value, never at which goals they are.
public struct PartialUnlockTier: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID

    /// User-facing label for this tier (e.g. "Messaging", "Social", "Games" — spec §2's/§4's
    /// examples). This is a short key/name a settings list row can show as-is; a *shield*
    /// sentence built from it ("Messaging unlocks after 2 more goals") is composed copy and still
    /// belongs in `Core/Sources/Core/Copy`, per CLAUDE.md's "no hardcoded UI strings" rule — this
    /// type never hardcodes app/tier names itself, callers supply them.
    public var name: String

    /// How many of the active lock's required goals must be verified/complete to reach this
    /// tier. Spec §2's example is a two-step ladder ("2 of 3" then "all 3"), but nothing here
    /// limits a `LockSet` to exactly two tiers.
    public var requiredCompletedGoalCount: Int

    /// JSON-encoded `FamilyActivitySelection` unlocked once this tier is reached — the same
    /// encoding convention `Models/LockSet.swift` documents for `appTokensBlob`
    /// (`try JSONEncoder().encode(selection)`), and, like that property, device-local only:
    /// FamilyControls tokens never leave the device (spec §13, §24) and this type is never handed
    /// to the Sync outbox as-is.
    public var selectionBlob: Data

    public init(
        id: UUID = UUID(),
        name: String,
        requiredCompletedGoalCount: Int,
        selection: FamilyActivitySelection
    ) throws {
        self.id = id
        self.name = name
        self.requiredCompletedGoalCount = max(0, requiredCompletedGoalCount)
        self.selectionBlob = try JSONEncoder().encode(selection)
    }

    /// Decodes `selectionBlob` back into a `FamilyActivitySelection`. `nil` if it doesn't decode
    /// (a corrupted/foreign blob) — callers should treat that the same as "this tier unlocks
    /// nothing" rather than crashing, mirroring `LockEngineManager.invalidAppTokensBlob`'s
    /// handling of the analogous case on `LockSet.appTokensBlob`.
    public var selection: FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionBlob)
    }
}

// MARK: - PartialUnlockEvaluation

/// Result of evaluating a `LockSet`'s partial-unlock ladder against a set of completed goal ids.
///
/// `@unchecked Sendable`, not plain `Sendable`: this struct carries live `FamilyActivitySelection`
/// values (not just their `Data` encoding, unlike `PartialUnlockTier`), and whether Apple's SDK
/// marks `FamilyActivitySelection`/`ApplicationToken`/`ActivityCategoryToken`/`WebDomainToken`
/// as `Sendable` is not something this environment can verify without a compiler (no Mac/Swift
/// toolchain — flagged in this task's knownIssues). All four are immutable-after-construction
/// value types holding opaque, Codable/Hashable token data, so sharing them across isolation
/// domains is safe in practice regardless of how the SDK annotates them; `@unchecked` only
/// papers over an unverified *annotation*, not an actual data race. Re-verify with a real Swift 6
/// build and drop `@unchecked` if the plain conformance compiles on its own.
public struct PartialUnlockEvaluation: @unchecked Sendable {
    /// Every tier reached (`requiredCompletedGoalCount <= completedGoalIDs.count`), ordered from
    /// loosest (lowest `requiredCompletedGoalCount`) to strictest.
    public let unlockedTiers: [PartialUnlockTier]

    /// Every tier not yet reached, same ordering.
    public let lockedTiers: [PartialUnlockTier]

    /// The union of every unlocked tier's `selection` — apps/categories/domains that are safe to
    /// remove from the shield right now.
    public let unlockedSelection: FamilyActivitySelection

    /// `lockSet`'s full saved selection minus `unlockedSelection` — everything that should still
    /// be shielded at this evaluation. `nil` only when `lockSet.appTokensBlob` is missing or
    /// doesn't decode (mirrors `LockEngineManager.invalidAppTokensBlob` handling elsewhere) —
    /// callers must treat `nil` as "unknown, leave the current shield alone", never as "nothing
    /// left to lock" (CLAUDE.md: never trap the user, but also never accidentally unlock
    /// everything on a decode failure either).
    public let remainingLockedSelection: FamilyActivitySelection?

    /// The strictest tier reached so far — spec §2's "all 3" tier once every required goal is
    /// done, or the "2 of 3" tier partway there. `nil` if no tier has been reached yet.
    public var highestUnlockedTier: PartialUnlockTier? { unlockedTiers.last }
}

// MARK: - PartialUnlockTiers

/// Pure computation over a `LockSet`'s partial-unlock ladder (docs/spec.md §2, §4). Stateless by
/// design — no `shared` singleton, no SwiftData/ManagedSettings access — because every input
/// (`LockSet`, its tiers, and which goals are done) is already in the caller's hands (typically
/// `LockEngineManager`, which owns both the actual `ManagedSettingsStore` and
/// `LockSession.requiredGoalIDs`), and a pure function needs no actor hop to be safe to call from
/// any isolation domain under Swift 6 strict concurrency.
public enum PartialUnlockTiers {

    /// Computes which of `tiers` are unlocked for `lockSet` given `completedGoalIDs`.
    ///
    /// - Parameters:
    ///   - lockSet: The `LockSet` these tiers belong to. Used for `lockSet.appTokensBlob` when
    ///     computing `remainingLockedSelection`; validating that `tiers` actually belongs to this
    ///     particular `LockSet` is left to whatever assembles `tiers` (see file header's TODO —
    ///     there is no persisted, `lockSet.id`-keyed tier storage yet to validate against).
    ///   - tiers: This `LockSet`'s partial-unlock ladder. An empty array means "no partial
    ///     unlocks configured" — every result comes back empty/fully-locked, which is exactly
    ///     right for a plain full-or-nothing `LockSet` that was never given a ladder.
    ///   - completedGoalIDs: Ids of goals verified/complete so far for the active lock (e.g. the
    ///     subset of `LockSession.requiredGoalIDs` a caller has already confirmed verified). Only
    ///     `.count` is used — see `PartialUnlockTier.requiredCompletedGoalCount`'s doc comment on
    ///     why thresholds are counts, not specific goal identities.
    public static func evaluate(
        lockSet: LockSet,
        tiers: [PartialUnlockTier],
        completedGoalIDs: Set<UUID>
    ) -> PartialUnlockEvaluation {
        let sortedTiers = tiers.sorted { $0.requiredCompletedGoalCount < $1.requiredCompletedGoalCount }
        let completedCount = completedGoalIDs.count

        var unlocked: [PartialUnlockTier] = []
        var locked: [PartialUnlockTier] = []
        for tier in sortedTiers {
            if tier.requiredCompletedGoalCount <= completedCount {
                unlocked.append(tier)
            } else {
                locked.append(tier)
            }
        }

        var unlockedSelection = FamilyActivitySelection()
        for tier in unlocked {
            guard let selection = tier.selection else { continue }
            unlockedSelection.applicationTokens.formUnion(selection.applicationTokens)
            unlockedSelection.categoryTokens.formUnion(selection.categoryTokens)
            unlockedSelection.webDomainTokens.formUnion(selection.webDomainTokens)
        }

        var remainingLocked: FamilyActivitySelection?
        if let blob = lockSet.appTokensBlob,
           let fullSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob) {
            var remaining = fullSelection
            remaining.applicationTokens.subtract(unlockedSelection.applicationTokens)
            remaining.categoryTokens.subtract(unlockedSelection.categoryTokens)
            remaining.webDomainTokens.subtract(unlockedSelection.webDomainTokens)
            remainingLocked = remaining
        }

        return PartialUnlockEvaluation(
            unlockedTiers: unlocked,
            lockedTiers: locked,
            unlockedSelection: unlockedSelection,
            remainingLockedSelection: remainingLocked
        )
    }

    /// The required goals that are no longer remaining — the `completedGoalIDs` input to
    /// `evaluate` from what `LockEngineManager` computes (required ids, still-unverified ids).
    public static func completedGoalIDs(required: [UUID], remaining: Set<UUID>) -> Set<UUID> {
        Set(required).subtracting(remaining)
    }

    /// Convenience for spec §2's literal example ladder — "2 of 3 goals unlocks messaging apps,
    /// all 3 unlocks TikTok" — as a general two-tier shape: one partial tier reached one goal
    /// short of the total, and a full tier reached at the total. For whichever screen offers this
    /// the simple way (a "partial unlock" toggle with two app pickers) instead of a fully custom
    /// N-tier ladder. Not part of any fixed contract — purely additive.
    ///
    /// - Parameter totalRequiredGoals: The active lock's total required-goal count (e.g.
    ///     `LockSession.requiredGoalIDs.count`). `partialTier`'s threshold is `max(0,
    ///     totalRequiredGoals - 1)`.
    public static func twoTierLadder(
        totalRequiredGoals: Int,
        partialTierName: String,
        partialSelection: FamilyActivitySelection,
        fullTierName: String,
        fullSelection: FamilyActivitySelection
    ) throws -> [PartialUnlockTier] {
        let partialThreshold = max(0, totalRequiredGoals - 1)
        return [
            try PartialUnlockTier(
                name: partialTierName,
                requiredCompletedGoalCount: partialThreshold,
                selection: partialSelection
            ),
            try PartialUnlockTier(
                name: fullTierName,
                requiredCompletedGoalCount: totalRequiredGoals,
                selection: fullSelection
            ),
        ]
    }
}

// MARK: - PartialUnlockTierStore

/// Each lock set's tier ladder, in the App Group (see file header). Cheap `UserDefaults` reads.
public enum PartialUnlockTierStore {
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let key = "lockEngine.partialUnlockTiers.v1"

    /// The ladder for `lockSetID`, loosest first. Empty = no partial unlocks (all-or-nothing).
    public static func tiers(for lockSetID: UUID) -> [PartialUnlockTier] {
        (all()[lockSetID.uuidString] ?? []).sorted { $0.requiredCompletedGoalCount < $1.requiredCompletedGoalCount }
    }

    /// Replaces the ladder. Tiers needing 0 goals are dropped — they'd unlock at lock start.
    public static func setTiers(_ tiers: [PartialUnlockTier], for lockSetID: UUID) {
        var everything = all()
        let kept = tiers.filter { $0.requiredCompletedGoalCount >= 1 }
        everything[lockSetID.uuidString] = kept.isEmpty ? nil : kept
        save(everything)
    }

    public static func removeTiers(for lockSetID: UUID) {
        var everything = all()
        everything[lockSetID.uuidString] = nil
        save(everything)
    }

    private static func all() -> [String: [PartialUnlockTier]] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [PartialUnlockTier]].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ value: [String: [PartialUnlockTier]]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
