import Foundation
import SwiftData

/// Mirrors the `squads` table field-for-field (docs/spec.md §13 Data Model;
/// backend/supabase/migrations/0001_init.sql).
///
/// A squad is a small accountability group users join to see each other's goal rings, run
/// duels, and chase badges together — see spec §11 (Session 11, `feat/social`). Local
/// (SwiftData) and remote (Postgres) share this shape per §13; sync code (Session 7,
/// `Core/Sources/Core/Sync`) reconciles rows by `id`.
///
/// Foreign keys (`createdBy`) are stored as raw `UUID`s rather than SwiftData
/// `@Relationship`s: `users` is a different module's model, the remote Postgres row is the
/// real source of truth, and RLS in 0001_init.sql already governs write access
/// (`squads_owner_write` / `squads_owner_update`) — this model only needs to carry the id.
@Model
public final class Squad {
    /// `squads.id` — primary key.
    @Attribute(.unique) public var id: UUID

    /// `squads.name` — display name chosen at creation.
    public var name: String

    /// `squads.created_by` — the user who created the squad. Only the creator may write/update
    /// squad metadata remotely (see `squads_owner_write` / `squads_owner_update` policies in
    /// 0001_init.sql).
    public var createdBy: UUID

    /// `squads.invite_code` — unique, shareable code used to join this squad. Enforced unique
    /// locally; the remote Postgres `unique not null` constraint is the real source of truth.
    @Attribute(.unique) public var inviteCode: String

    public init(
        id: UUID = UUID(),
        name: String,
        createdBy: UUID,
        inviteCode: String
    ) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.inviteCode = inviteCode
    }
}
