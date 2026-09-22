import Foundation
import SwiftData

/// One Sunday-night Weekly Report Card (spec §5.14, §9.6): aggregated stats for the week plus a
/// short LLM-written insight line, rendered as a shareable 9:16 image on device.
///
/// Mirrors the Supabase `recaps` table (`backend/supabase/migrations/0001_init.sql`) field-for-field.
/// Postgres enforces `unique (user_id, week_start)`; SwiftData on this package's iOS 17 deployment
/// target (see `Core/Package.swift`) can't express that composite constraint with the `#Unique`
/// macro, which needs iOS 18+. It's enforced instead by the Sync outbox (Session 7) upserting keyed
/// on `(userID, weekStart)`. `id` below is a local SwiftData identity only — the remote table has
/// its own server-generated `id` that the Sync layer maps to it.
@Model
public final class Recap {
    /// Local SwiftData identity. Distinct from the remote `recaps.id` — see type doc comment.
    @Attribute(.unique) public var id: UUID

    /// Mirrors `recaps.user_id`.
    public var userID: UUID

    /// Mirrors `recaps.week_start` (Postgres `date`, not `timestamptz`) — the first day of the week
    /// this recap covers. Store/read the calendar day only; ignore time-of-day.
    public var weekStart: Date

    /// Mirrors `recaps.text` — the Weekly Recap Writer's (spec §9.6) ≤60-word line: one specific
    /// win, one specific suggestion, no shame, written in the user's coach voice. Nil until the
    /// Sunday 6 PM job has produced a card for this week.
    public var text: String?

    /// Mirrors `recaps.stats` (jsonb). See `RecapStats`.
    public var stats: RecapStats

    /// Mirrors `recaps.image_path` — path to the rendered shareable 9:16 image (App Group container
    /// locally, storage path once synced), once exported. Nil until exported.
    public var imagePath: String?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        weekStart: Date,
        text: String? = nil,
        stats: RecapStats = RecapStats(),
        imagePath: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.weekStart = weekStart
        self.text = text
        self.stats = stats
        self.imagePath = imagePath
    }
}

/// The jsonb payload stored in `recaps.stats`. The column is untyped on the server; this is the
/// shape the app, the recap-card renderer, and the Weekly Recap Writer job (spec §9.6) agree on.
///
/// Extend additively only: new fields must be optional or defaulted, since previously-stored rows
/// won't have them when decoded after a future app update.
public struct RecapStats: Codable, Hashable, Sendable {
    /// Per-goal completion fraction (0...1) for the week, keyed by the goal's `id.uuidString`.
    /// Powers the "rings for the week" summary (spec §5.14).
    public var goalCompletionRings: [String: Double]

    /// Weekday name (e.g. "Tuesday") with the best completion rate this week, if any goal activity
    /// occurred.
    public var bestDay: String?

    /// On-device "Time Reclaimed" for the week, in minutes: hours of blocked-app time avoided
    /// during locks (spec §5.15). Computed on-device — Screen Time data never leaves the device.
    public var timeReclaimedMinutes: Int

    /// Streak length as of the end of the week (see `StreakEngine`, spec §8).
    public var streak: Int

    /// Change in season/leaderboard rank since last week; positive = moved up. Nil before Seasons
    /// (spec §5.9) ships or for users not in a ranked context.
    public var rankMovement: Int?

    /// Total goal-events with `kind == .complete` across the week, for the ring/summary UI.
    public var goalsCompleted: Int

    /// Total goals planned (sum of `daily_plans` rows) across the week.
    public var goalsPlanned: Int

    public init(
        goalCompletionRings: [String: Double] = [:],
        bestDay: String? = nil,
        timeReclaimedMinutes: Int = 0,
        streak: Int = 0,
        rankMovement: Int? = nil,
        goalsCompleted: Int = 0,
        goalsPlanned: Int = 0
    ) {
        self.goalCompletionRings = goalCompletionRings
        self.bestDay = bestDay
        self.timeReclaimedMinutes = timeReclaimedMinutes
        self.streak = streak
        self.rankMovement = rankMovement
        self.goalsCompleted = goalsCompleted
        self.goalsPlanned = goalsPlanned
    }
}
