import Foundation
import SwiftData

/// One row per user: the Retention module's streak state. A streak counts days with at least
/// one *earned* unlock (docs/spec.md §5.6, §8) and is designed to feel protective rather than
/// fragile — freezes, Never Miss Twice, and Comeback moments all read/write this row via
/// `StreakEngine` (`Core/Sources/Core/Retention/StreakEngine.swift`), which is the sole owner
/// of mutating it.
///
/// Mirrors `streaks` in `backend/supabase/migrations/0001_init.sql` field-for-field
/// (docs/spec.md §13):
/// ```sql
/// create table streaks (
///     user_id uuid primary key references users(id) on delete cascade,
///     current integer not null default 0,
///     best integer not null default 0,
///     freezes_left integer not null default 1,
///     last_earned_date date,
///     never_miss_twice_armed boolean not null default false
/// );
/// ```
/// Unlike `LockSet`/`LockSession`/`TimeBank`, this table's primary key *is* `user_id` — there
/// is no separate `id` column — so `userID` plays that role here too.
@Model
public final class Streak {
    /// Matches `streaks.user_id uuid primary key`. Exactly one `Streak` row exists per user.
    @Attribute(.unique) public var userID: UUID

    /// Matches `streaks.current integer not null default 0`. Consecutive days (allowing for
    /// freezes/Never-Miss-Twice forgiveness, spec §8 rule 3) with an earned unlock.
    public var current: Int

    /// Matches `streaks.best integer not null default 0`. All-time high for `current`.
    public var best: Int

    /// Matches `streaks.freezes_left integer not null default 1`. Free tier grants 1/week,
    /// Pro grants 3 (spec §21) — that replenishment policy lives in `StreakEngine`, not here.
    public var freezesLeft: Int

    /// Matches `streaks.last_earned_date date` (nullable — `nil` before the user's first
    /// earned unlock, i.e. before onboarding's first-win moment sets `current` to 1, spec §7).
    public var lastEarnedDate: Date?

    /// Matches `streaks.never_miss_twice_armed boolean not null default false`. Spec §5.6:
    /// a single miss arms this flag instead of breaking the streak outright; a second
    /// *consecutive* miss while armed is what actually breaks it, and an earned unlock before
    /// that disarms it and triggers the Comeback moment.
    public var neverMissTwiceArmed: Bool

    public init(
        userID: UUID,
        current: Int = 0,
        best: Int = 0,
        freezesLeft: Int = 1,
        lastEarnedDate: Date? = nil,
        neverMissTwiceArmed: Bool = false
    ) {
        self.userID = userID
        self.current = current
        self.best = best
        self.freezesLeft = freezesLeft
        self.lastEarnedDate = lastEarnedDate
        self.neverMissTwiceArmed = neverMissTwiceArmed
    }
}
