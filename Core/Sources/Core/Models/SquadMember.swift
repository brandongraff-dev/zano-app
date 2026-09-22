import Foundation
import SwiftData

/// Mirrors the `squad_members` join table field-for-field (docs/spec.md §13 Data Model;
/// backend/supabase/migrations/0001_init.sql).
///
/// Membership row linking a user to a squad, with a role. Remote Postgres uses the composite
/// primary key `(squad_id, user_id)` and no separate `id` column — this model matches that
/// shape rather than inventing a local-only identifier.
///
/// SwiftData on iOS 17 has no first-class composite-unique model attribute, so the
/// `(squadID, userID)` uniqueness the remote `primary key (squad_id, user_id)` guarantees must
/// be enforced by whichever service layer inserts these (Session 11, squad join/leave flow)
/// checking for an existing row first — mirroring the remote constraint, not re-declaring it
/// here.
@Model
public final class SquadMember {
    /// `squad_members.squad_id` — half of the composite primary key.
    public var squadID: UUID

    /// `squad_members.user_id` — half of the composite primary key.
    public var userID: UUID

    /// `squad_members.role` — `'owner' | 'member'`, defaults to `'member'`.
    public var role: SquadRole

    public init(
        squadID: UUID,
        userID: UUID,
        role: SquadRole = .member
    ) {
        self.squadID = squadID
        self.userID = userID
        self.role = role
    }
}

/// Mirrors the `squad_members.role` check constraint (`role in ('owner', 'member')`).
public enum SquadRole: String, Codable, Sendable {
    case owner
    case member
}
