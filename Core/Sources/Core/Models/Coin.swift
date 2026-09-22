import Foundation
import SwiftData

/// Mirrors the `coins` table field-for-field (docs/spec.md §13 Data Model;
/// backend/supabase/migrations/0001_init.sql).
///
/// One row per user: the cosmetic-currency balance earned from streaks, badges, and duels
/// (spec §11). `user_id` is the primary key in Postgres — there is no separate `id` column —
/// so this model has exactly one identifying field, matching that shape.
@Model
public final class Coin {
    /// `coins.user_id` — primary key (one balance row per user).
    @Attribute(.unique) public var userID: UUID

    /// `coins.balance`.
    public var balance: Int

    public init(userID: UUID, balance: Int = 0) {
        self.userID = userID
        self.balance = balance
    }
}
