import Foundation
import SwiftData

/// Mirrors the `badges` table field-for-field (docs/spec.md §13 Data Model;
/// backend/supabase/migrations/0001_init.sql).
///
/// An earned achievement (e.g. a streak milestone or a "Comeback" badge after using a streak
/// freeze — spec §8/§11). `key` is a stable, non-user-facing identifier; the display copy for
/// each key lives in `Core/Sources/Core/Copy` per CLAUDE.md's "no hardcoded UI strings" rule —
/// this model never stores display text itself.
///
/// Remote Postgres enforces `unique (user_id, key)` — one of each badge per user. SwiftData on
/// iOS 17 has no composite-unique model attribute, so whichever engine awards badges (streak /
/// retention work, Session 9/11) must check for an existing `(userID, key)` row before
/// inserting, mirroring rather than re-declaring that constraint here.
@Model
public final class Badge {
    /// `badges.id` — primary key.
    @Attribute(.unique) public var id: UUID

    /// `badges.user_id`.
    public var userID: UUID

    /// `badges.key` — stable badge identifier (e.g. `"comeback"`, `"streak_14"`), looked up in
    /// `Core/Sources/Core/Copy` for its display title/description.
    public var key: String

    /// `badges.earned_at`.
    public var earnedAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        key: String,
        earnedAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.key = key
        self.earnedAt = earnedAt
    }
}
