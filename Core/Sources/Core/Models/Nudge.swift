import Foundation
import SwiftData

/// One instance of the per-user nudge bandit (spec §9.3) firing a specific "arm" — a tone × timing
/// slot × format combination — at the user. `delivered` / `actedWithin3h` close the loop so the
/// bandit can learn: reward = the targeted goal completed within 3 hours of the nudge.
///
/// Mirrors the Supabase `nudges` table (`backend/supabase/migrations/0001_init.sql`) field-for-field.
@Model
public final class Nudge {
    /// Mirrors `nudges.id`.
    @Attribute(.unique) public var id: UUID

    /// Mirrors `nudges.user_id`.
    public var userID: UUID

    /// Mirrors `nudges.ts` — when this nudge was selected/sent.
    public var ts: Date

    /// Mirrors `nudges.arm` (jsonb) — the bandit arm that was pulled. See `NudgeArm`.
    public var arm: NudgeArm

    /// Mirrors `nudges.delivered` — true once the push/widget/shield copy actually reached the
    /// user, as opposed to being selected but suppressed (e.g. by the 2/day cap, spec §9.3).
    public var delivered: Bool

    /// Mirrors `nudges.acted_within_3h` — nil until the 3-hour attribution window has closed, then
    /// true/false depending on whether the targeted goal was completed within it. This is the
    /// bandit's reward signal (spec §9.3).
    public var actedWithin3h: Bool?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        ts: Date = Date(),
        arm: NudgeArm,
        delivered: Bool = false,
        actedWithin3h: Bool? = nil
    ) {
        self.id = id
        self.userID = userID
        self.ts = ts
        self.arm = arm
        self.delivered = delivered
        self.actedWithin3h = actedWithin3h
    }
}

/// The jsonb payload stored in `nudges.arm` — one combination out of the nudge optimizer's arm
/// space (spec §9.3): tone (4) × timing slot (4) × format (3), 48 arms total. Per-user contextual
/// bandit with population prior picks among these.
public struct NudgeArm: Codable, Hashable, Sendable {
    public var tone: NudgeTone
    public var timingSlot: NudgeTimingSlot
    public var format: NudgeFormat

    public init(tone: NudgeTone, timingSlot: NudgeTimingSlot, format: NudgeFormat) {
        self.tone = tone
        self.timingSlot = timingSlot
        self.format = format
    }
}

/// The 4 coach tones the nudge optimizer can pick from (spec §9.3). Raw values intentionally match
/// the 4 values of the `users.coach_voice` check constraint (spec §5.13), but this is kept as its
/// own type scoped to the nudge arm payload rather than reused from wherever the `User` model's
/// coach-voice type lives, since that model is owned by a different build session/agent and isn't
/// visible from this file.
public enum NudgeTone: String, Codable, Hashable, Sendable, CaseIterable {
    case hype
    case toughLove = "tough_love"
    case chill
    case data
}

/// The 4 timing slots the nudge optimizer can pick from (spec §9.3).
public enum NudgeTimingSlot: String, Codable, Hashable, Sendable, CaseIterable {
    case morning
    case preGymWindow = "pre_gym_window"
    case afternoon4pm = "afternoon_4pm"
    case evening
}

/// The 3 delivery formats the nudge optimizer can pick from (spec §9.3).
public enum NudgeFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case push
    case widgetCopy = "widget_copy"
    case shieldCopy = "shield_copy"
}
