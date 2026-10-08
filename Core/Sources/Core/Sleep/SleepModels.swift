// SleepModels.swift
// Core / Sleep
//
// Sleep wind-down (session 18, 2026-10-05; docs/spec.md §5.25): a one-tap morning check-in ("How
// rested do you feel?"), optionally paired with Apple Health sleep length, that over a few weeks shows
// what actually helped this person and suggests a gentle bedtime change. All of it is stored and
// worked out on the phone; nothing here is synced or uploaded (§24).
//
// Not medical: patterns only, never a diagnosis, and bedtime is only ever suggested, never forced.

import Foundation

/// One night: the evening it began, what was planned, what Health and the phone say happened, and how
/// the person felt the next morning.
public struct SleepNight: Codable, Sendable, Equatable, Identifiable {
    /// The evening the night began, `yyyy-MM-dd` in the device's calendar.
    public var id: String
    /// The Bedtime Gate bedtime that evening, in minutes after midnight (0...1439).
    public var plannedBedtimeMinute: Int
    /// When Health says sleep started, in minutes after midnight. `nil` without Health data.
    public var asleepMinute: Int?
    /// Total time asleep per Health. `nil` without Health data.
    public var sleepMinutes: Int?
    /// `true`: no pickup after bedtime. `false`: picked up. `nil`: unknown (no Bedtime Gate or sleep goal).
    public var keptWindDown: Bool?
    /// The morning answer, 1 (drained) to 5 (great). `nil` until answered.
    public var rating: Int?

    public init(
        id: String, plannedBedtimeMinute: Int, asleepMinute: Int? = nil, sleepMinutes: Int? = nil,
        keptWindDown: Bool? = nil, rating: Int? = nil
    ) {
        self.id = id
        self.plannedBedtimeMinute = plannedBedtimeMinute
        self.asleepMinute = asleepMinute
        self.sleepMinutes = sleepMinutes
        self.keptWindDown = keptWindDown
        self.rating = rating
    }

    /// When the night really started: Health's sleep onset if known, otherwise the planned bedtime.
    public var effectiveBedtimeMinute: Int { asleepMinute ?? plannedBedtimeMinute }

    /// Minutes since 18:00, so a 00:30 bedtime sorts after 23:30 instead of before it.
    public static func eveningOffset(ofMinuteOfDay minute: Int) -> Int {
        (minute - 18 * 60 + 1_440) % 1_440
    }

    public var bedtimeOffset: Int { Self.eveningOffset(ofMinuteOfDay: effectiveBedtimeMinute) }
}

public struct SleepSettings: Codable, Sendable, Equatable {
    /// Ask "How rested do you feel?" each morning.
    public var checkInEnabled: Bool
    /// Read sleep length from Apple Health (asks permission when turned on).
    public var useHealth: Bool

    public init(checkInEnabled: Bool = false, useHealth: Bool = false) {
        self.checkInEnabled = checkInEnabled
        self.useHealth = useHealth
    }
}

// MARK: - Insights

public enum SleepInsightKind: String, Codable, Sendable {
    /// Nights the phone was left alone after bedtime vs nights it was not.
    case windDown
    /// Nights with at least 7 hours asleep vs fewer.
    case duration
    /// Nights with a bedtime within 30 minutes of the usual one vs further out.
    case consistency
}

/// "On nights X you felt A on average, vs B on other nights", with how many nights each side has.
public struct SleepInsight: Sendable, Equatable {
    public var kind: SleepInsightKind
    public var betterAverage: Double
    public var otherAverage: Double
    public var betterNights: Int
    public var otherNights: Int

    public var delta: Double { betterAverage - otherAverage }
}

public struct SleepBedtimeSuggestion: Sendable, Equatable {
    /// Suggested bedtime, minutes after midnight.
    public var bedtimeMinute: Int
    /// Rated nights in the group this suggestion rests on.
    public var basedOnNights: Int
    public var groupAverage: Double
    public var overallAverage: Double
}
