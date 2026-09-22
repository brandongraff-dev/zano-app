import Foundation
import SwiftData

/// Earn Mode's per-day ledger (docs/spec.md §5.2): every verified goal deposits minutes,
/// unlocking a shielded app spends them, and whatever's unused expires at midnight — "no
/// hoarding" is a product rule, not just a UI label, so `TimeBankEngine` (`Core/Sources/Core/
/// LockEngine/TimeBankEngine.swift`) never carries a balance across `date`s. One row exists per
/// `(userID, date)` pair.
///
/// Mirrors `time_bank` in `backend/supabase/migrations/0001_init.sql` field-for-field
/// (docs/spec.md §13):
/// ```sql
/// create table time_bank (
///     id uuid primary key default gen_random_uuid(),
///     user_id uuid not null references users(id) on delete cascade,
///     date date not null,
///     earned_min integer not null default 0,
///     spent_min integer not null default 0,
///     unique (user_id, date)
/// );
/// ```
@Model
public final class TimeBank {
    /// Matches `time_bank.id uuid primary key`.
    @Attribute(.unique) public var id: UUID

    /// Matches `time_bank.user_id uuid not null`.
    public var userID: UUID

    /// Matches `time_bank.date date not null`. Postgres's `date` has no time component;
    /// `Date` is the closest SwiftData attribute type. `TimeBankEngine` is responsible for
    /// normalizing to the user's local calendar day (`users.tz`, spec §13) before calling
    /// `deposit`/`spend` — this property stores whatever `Date` it's given verbatim.
    public var date: Date

    /// Matches `time_bank.earned_min integer not null default 0`.
    public var earnedMin: Int

    /// Matches `time_bank.spent_min integer not null default 0`.
    public var spentMin: Int

    /// Enforces `unique (user_id, date)` from the Postgres schema. SwiftData's composite
    /// uniqueness macro (`#Unique<T>([...])`) requires iOS 18+; this app's deployment target
    /// is iOS 17 (project.yml), so this derived single-column key stands in for it: a
    /// `(userID, date)` pair that collides fails the insert instead of silently duplicating a
    /// day's row. Calendar-day math is done in UTC deliberately, to keep the key a pure
    /// function of its inputs — `TimeBankEngine` must pass the same already-locally-normalized
    /// `date` on every call for a given day, or two `Date`s meant to represent "today" could
    /// key differently. Flagged for verification once `TimeBankEngine` (and the Store's
    /// timezone-normalization convention) exists.
    @Attribute(.unique) public private(set) var dayKey: String

    /// Minutes still available to spend today (`max(0, earnedMin - spentMin)`), i.e. what a
    /// widget or the Dynamic Island earn-meter bar would render. `TimeBankEngine.
    /// remainingMinutes(for:)` is the source of truth across possibly-multiple rows/edge cases;
    /// this is a same-row convenience.
    public var remainingMin: Int { max(0, earnedMin - spentMin) }

    public init(id: UUID = UUID(), userID: UUID, date: Date, earnedMin: Int = 0, spentMin: Int = 0) {
        self.id = id
        self.userID = userID
        self.date = date
        self.earnedMin = earnedMin
        self.spentMin = spentMin
        self.dayKey = Self.makeDayKey(userID: userID, date: date)
    }

    /// Recomputes `dayKey` after changing `userID` or `date` on an existing row. Rows are
    /// created per user per day and neither should normally change post-creation, but this
    /// keeps the unique key honest if something ever does.
    public func refreshDayKey() {
        dayKey = Self.makeDayKey(userID: userID, date: date)
    }

    private static func makeDayKey(userID: UUID, date: Date) -> String {
        var utcCalendar = Calendar(identifier: .gregorian)
        // "UTC" is a guaranteed-valid IANA identifier, so this never fails in practice.
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let c = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return "\(userID.uuidString)_\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
