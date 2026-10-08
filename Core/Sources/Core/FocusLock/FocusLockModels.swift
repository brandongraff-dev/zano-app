// FocusLockModels.swift
// Core / FocusLock
//
// Work-hours focus lock (session 17, 2026-10-05; docs/spec.md §5.24): distracting apps lock during
// meetings and focus blocks on the user's calendar and open again when the block ends, with no
// goals to earn. This file is the data: what a calendar event looks like to the planner, the user's
// settings, one armed window, and the small on-device memory that learns which events the user wants
// locked.
//
// Privacy (spec §24): calendar data never leaves the device. Event titles are read on the phone to
// spot focus blocks and to say "Lock during 'Design review'?"; the planner never sends them anywhere,
// the learning memory stores only a hash of a title, and nothing here is synced or uploaded.
//
// Learning, in plain words: ask first. After the user says yes twice to the same recurring event,
// ZANO locks for it by itself; after two no's it stops asking. Ending a focus lock early with the
// emergency unlock counts as a no. Every automatic choice can be undone in Settings.

import Foundation

// MARK: - Calendar events (what the planner sees)

/// The few facts about a calendar event the planner needs. Built from EventKit by
/// `FocusLockCalendarSource`; plain data so the planner is testable without EventKit.
public struct FocusCalendarEvent: Codable, Sendable, Hashable {
    public var id: String
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Marked busy (not free or tentative-free): a block of time the user is not available.
    public var isBusy: Bool
    /// Has at least one other attendee: a meeting rather than a personal block.
    public var hasOtherAttendees: Bool

    public init(
        id: String, calendarID: String = "", title: String, start: Date, end: Date,
        isAllDay: Bool = false, isBusy: Bool = true, hasOtherAttendees: Bool = false
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.hasOtherAttendees = hasOtherAttendees
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

// MARK: - Settings

public struct FocusLockSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// The lock set whose apps get shielded. `nil` = the user's default lock set.
    public var lockSetID: UUID?
    /// Lock during busy events that have other people in them.
    public var includeMeetings: Bool
    /// Lock during events whose title contains one of `keywords`.
    public var includeFocusBlocks: Bool
    public var keywords: [String]
    /// Calendars to read. `nil` = every calendar.
    public var calendarIDs: [String]?

    /// DeviceActivity windows are at least 15 minutes (spec §27).
    public static let minMinutes = LockSchedule.minimumWindowMinutes
    /// Longer than this reads as a day-long block, not a meeting: never locked.
    public static let maxMinutes = 240
    /// How far ahead windows are planned.
    public static let horizonHours = 48
    /// Apple caps how many activities one app can monitor (believed 20, UNVERIFIED); schedules, the
    /// Bedtime Gate and Earn Mode spend windows share that budget, so the focus lock takes at most 8.
    public static let maxWindows = 8
    /// Events closer together than this are one window.
    public static let mergeGapMinutes = 5

    public static let defaultKeywords = ["focus", "deep work", "heads down", "study", "exam", "homework"]

    public init(
        isEnabled: Bool = false, lockSetID: UUID? = nil, includeMeetings: Bool = true,
        includeFocusBlocks: Bool = true, keywords: [String] = FocusLockSettings.defaultKeywords,
        calendarIDs: [String]? = nil
    ) {
        self.isEnabled = isEnabled
        self.lockSetID = lockSetID
        self.includeMeetings = includeMeetings
        self.includeFocusBlocks = includeFocusBlocks
        self.keywords = keywords
        self.calendarIDs = calendarIDs
    }
}

// MARK: - Windows and decisions

public enum FocusLockReason: String, Codable, Sendable {
    /// A busy event with other people in it.
    case meeting
    /// An event the user titled as focus time ("Deep work", "Study").
    case focusBlock
}

/// What to do about a window: lock without asking, ask first, or leave it alone.
public enum FocusLockDecision: String, Codable, Sendable {
    case autoLock
    case ask
    case skip
}

/// One planned lock: from `start` to `end`, apps shielded, no goals required.
public struct FocusLockWindow: Codable, Sendable, Hashable, Identifiable {
    /// Stable across refreshes (pattern + start minute), so a window is registered once.
    public var id: String
    public var start: Date
    public var end: Date
    public var reason: FocusLockReason
    /// The recurring-event key the learning memory counts under.
    public var patternKey: String
    /// Shown to the user on this device only ("Design review").
    public var title: String
    /// More than one event was joined into this window.
    public var mergedCount: Int

    public init(id: String, start: Date, end: Date, reason: FocusLockReason, patternKey: String, title: String, mergedCount: Int = 1) {
        self.id = id
        self.start = start
        self.end = end
        self.reason = reason
        self.patternKey = patternKey
        self.title = title
        self.mergedCount = mergedCount
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// A window with what to do about it.
public struct FocusLockProposal: Codable, Sendable, Hashable, Identifiable {
    public var window: FocusLockWindow
    public var decision: FocusLockDecision
    public var id: String { window.id }

    public init(window: FocusLockWindow, decision: FocusLockDecision) {
        self.window = window
        self.decision = decision
    }
}

// MARK: - Learning memory

/// Which recurring events the user wants locked. Keyed by a hash of the event title, never the title.
public struct FocusLockPatternMemory: Codable, Sendable, Equatable {
    public struct Tally: Codable, Sendable, Equatable {
        public var accepts = 0
        public var declines = 0
        public init(accepts: Int = 0, declines: Int = 0) {
            self.accepts = accepts
            self.declines = declines
        }
    }

    public var tallies: [String: Tally]

    /// Two answers the same way settles it.
    public static let strikes = 2

    public init(tallies: [String: Tally] = [:]) { self.tallies = tallies }

    public func decision(for key: String) -> FocusLockDecision {
        let tally = tallies[key] ?? Tally()
        if tally.declines >= Self.strikes && tally.declines > tally.accepts { return .skip }
        if tally.accepts >= Self.strikes && tally.accepts > tally.declines { return .autoLock }
        return .ask
    }

    public mutating func recordAccept(_ key: String) {
        tallies[key, default: Tally()].accepts += 1
    }

    /// A "no", or a focus lock the user ended early with the emergency unlock.
    public mutating func recordDecline(_ key: String) {
        tallies[key, default: Tally()].declines += 1
    }

    /// Back to asking (Settings: "Ask me again").
    public mutating func forget(_ key: String) {
        tallies[key] = nil
    }
}

public enum FocusLockPattern {
    /// A stable key for a recurring event: FNV-1a over the lowercased, whitespace-collapsed title.
    /// (`hashValue` is randomised per launch, so it can't be stored.) The title itself is not kept.
    public static func key(forTitle title: String) -> String {
        let normalised = title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (normalised.isEmpty ? "untitled" : normalised).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
