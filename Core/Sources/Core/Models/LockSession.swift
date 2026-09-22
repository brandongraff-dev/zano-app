import Foundation
import SwiftData

/// One lock/unlock cycle: apps shielded (per a `LockSet`), a mode, the goals required to earn
/// or end it, and how it eventually ended. `LockEngineManager` (`Core/Sources/Core/LockEngine`)
/// is the sole owner of creating and mutating these rows.
///
/// Mirrors `lock_sessions` in `backend/supabase/migrations/0001_init.sql` field-for-field
/// (docs/spec.md §13):
/// ```sql
/// create table lock_sessions (
///     id uuid primary key default gen_random_uuid(),
///     user_id uuid not null references users(id) on delete cascade,
///     lock_set_id uuid references lock_sets(id) on delete set null,
///     started_at timestamptz not null default now(),
///     ended_at timestamptz,
///     trigger text check (trigger in ('nfc', 'schedule', 'manual', 'auto')),
///     mode text check (mode in ('full', 'earn')),
///     required_goal_ids uuid[] not null default '{}',
///     unlock_kind text check (unlock_kind in ('earned', 'emergency', 'schedule_end', 'manual'))
/// );
/// ```
///
/// `mode`, `trigger`, and `unlockKind` reuse the enums the LockEngine module owns
/// (`Core/Sources/Core/LockEngine/LockEngineManager.swift`: `LockMode`, `LockTrigger`,
/// `UnlockKind` — all `String, Codable`) rather than redeclaring them here, so the engine and
/// this model can never drift apart. Both are declared in the same `Core` module/target, so no
/// import is needed between the two files.
///
/// `lockSetID` and `requiredGoalIDs` are stored as plain `UUID` / `[UUID]`, not SwiftData
/// `@Relationship`s. That's a deliberate choice, not an oversight: it mirrors Postgres's loose
/// foreign keys exactly (including `lock_set_id`'s `on delete set null`, which SwiftData
/// relationship delete rules don't map onto 1:1), it keeps this model safe to hand to the Sync
/// outbox without dragging in a relationship graph, and it means neither `Goal` (owned by the
/// Verification/Models session) nor `LockSet` needs to exist yet for this file to compile.
@Model
public final class LockSession {
    /// Matches `lock_sessions.id uuid primary key`.
    @Attribute(.unique) public var id: UUID

    /// Matches `lock_sessions.user_id uuid not null`.
    public var userID: UUID

    /// Matches `lock_sessions.lock_set_id uuid references lock_sets(id) on delete set null`.
    /// `nil` for an ad-hoc lock with no saved `LockSet` (or after that `LockSet` is deleted).
    public var lockSetID: UUID?

    /// Matches `lock_sessions.started_at timestamptz not null default now()`.
    public var startedAt: Date

    /// Matches `lock_sessions.ended_at timestamptz` (nullable — `nil` while the lock is active).
    public var endedAt: Date?

    /// Matches `lock_sessions.trigger text check (...)`. Nullable in Postgres, mirrored here;
    /// `LockEngineManager.startLock(trigger:)` always supplies one at creation in practice. See
    /// `LockTrigger` in `LockEngine/LockEngineManager.swift`.
    public var trigger: LockTrigger?

    /// Matches `lock_sessions.mode text check (...)`. Nullable in Postgres, mirrored here;
    /// `LockEngineManager.startLock(mode:)` always supplies one at creation in practice. See
    /// `LockMode` in `LockEngine/LockEngineManager.swift`.
    public var mode: LockMode?

    /// Matches `lock_sessions.required_goal_ids uuid[] not null default '{}'`. IDs of the
    /// `Goal` rows that must verify to end this lock in `.earn` mode / unlock early in `.full`
    /// mode (goal ownership belongs to whichever session owns `Models/Goal.swift`).
    public var requiredGoalIDs: [UUID]

    /// Matches `lock_sessions.unlock_kind text check (...)` (nullable — `nil` while active).
    /// See `UnlockKind` in `LockEngine/LockEngineManager.swift`.
    public var unlockKind: UnlockKind?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        lockSetID: UUID? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        trigger: LockTrigger? = nil,
        mode: LockMode? = nil,
        requiredGoalIDs: [UUID] = [],
        unlockKind: UnlockKind? = nil
    ) {
        self.id = id
        self.userID = userID
        self.lockSetID = lockSetID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trigger = trigger
        self.mode = mode
        self.requiredGoalIDs = requiredGoalIDs
        self.unlockKind = unlockKind
    }

    /// A session is active exactly while it has neither an end time nor a recorded unlock
    /// kind. `LockEngineManager.endLock` must set both together so this never disagrees with
    /// the emergency-unlock guarantee (spec §24, CLAUDE.md: every lock keeps a way out).
    public var isActive: Bool { endedAt == nil && unlockKind == nil }
}
