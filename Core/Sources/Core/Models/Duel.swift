import Foundation
import SwiftData

/// Mirrors the `duels` table field-for-field (docs/spec.md §13 Data Model;
/// backend/supabase/migrations/0001_init.sql).
///
/// A head-to-head goal-completion contest between two users over a date range — see spec §11
/// (Session 11, `feat/social`). Both participants can read/update remotely (`duels_participant`
/// policy in 0001_init.sql); this is additive/competitive scoring only, never a restrictive
/// goal (CLAUDE.md "no restrictive goals" rule doesn't apply to duel scoring itself, but the
/// points a duel awards must only ever come from additive goal completions).
@Model
public final class Duel {
    /// `duels.id` — primary key.
    @Attribute(.unique) public var id: UUID

    /// `duels.a_user` — first participant.
    public var aUser: UUID

    /// `duels.b_user` — second participant.
    public var bUser: UUID

    /// `duels.start_date` — Postgres `date` (no time component); stored as the calendar day's
    /// midnight in the user's local timezone by whichever code constructs this.
    public var startDate: Date

    /// `duels.end_date` — see `startDate` re: calendar-day semantics.
    public var endDate: Date

    /// `duels.a_points` — running score for `aUser`.
    public var aPoints: Int

    /// `duels.b_points` — running score for `bUser`.
    public var bPoints: Int

    /// `duels.status`.
    public var status: DuelStatus

    public init(
        id: UUID = UUID(),
        aUser: UUID,
        bUser: UUID,
        startDate: Date,
        endDate: Date,
        aPoints: Int = 0,
        bPoints: Int = 0,
        status: DuelStatus = .pending
    ) {
        self.id = id
        self.aUser = aUser
        self.bUser = bUser
        self.startDate = startDate
        self.endDate = endDate
        self.aPoints = aPoints
        self.bPoints = bPoints
        self.status = status
    }
}

/// Mirrors the `duels.status` check constraint
/// (`status in ('pending', 'active', 'complete', 'declined')`).
public enum DuelStatus: String, Codable, Sendable {
    case pending
    case active
    case complete
    case declined
}
