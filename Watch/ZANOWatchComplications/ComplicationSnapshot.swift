// ComplicationSnapshot.swift
// Watch/ZANOWatchComplications
//
// The handful of fields the complications show, decoded straight from the JSON the watch app
// persists in the watch's App Group (`WatchStateStore.persist`, key `WatchAppGroup.snapshotKey`).
//
// Why a subset instead of compiling the app's `WatchStateSnapshot` here: that type pulls in the
// generated buddy sprite file (~16k lines of pixel data) through its buddy/monster accessors, and
// a complication extension is short-lived and memory-limited. `JSONDecoder` ignores keys a type
// doesn't declare, so this reads the same bytes. The property NAMES below are the contract: they
// must stay identical to `WatchStateSnapshot`'s (`currentStreak`, `rings[].progress`, `level`,
// `levelFraction`, `updatedAt`). Both sides use the default `JSONEncoder`/`JSONDecoder` date
// strategy, so `updatedAt` round-trips.

import Foundation

struct ComplicationSnapshot: Decodable, Sendable, Equatable {
    struct Ring: Decodable, Sendable, Equatable {
        var progress: Double
    }

    var currentStreak: Int
    var rings: [Ring]
    /// Optional on the wire (older phone builds don't send it), same as on the watch app.
    var level: Int?
    var levelFraction: Double?
    /// When the phone built the snapshot; `.distantPast` before the first sync.
    var updatedAt: Date

    /// Before the watch has ever heard from the phone: nothing made up, no streak, empty rings.
    static let empty = ComplicationSnapshot(
        currentStreak: 0,
        rings: [],
        level: nil,
        levelFraction: nil,
        updatedAt: .distantPast
    )

    /// Shown only in the watch face editor's gallery (`context.isPreview`), the same convention
    /// as `ZANOWidgetSnapshot.galleryPreview` on iOS.
    static let galleryPreview = ComplicationSnapshot(
        currentStreak: 12,
        rings: [Ring(progress: 1), Ring(progress: 0.6), Ring(progress: 0.4)],
        level: 4,
        levelFraction: 0.5,
        updatedAt: .now
    )

    var hasSynced: Bool { updatedAt > .distantPast }

    /// Average fill of today's rings, 0...1. Rings are per day, so a snapshot from an earlier
    /// day counts as nothing done yet (the phone hasn't said otherwise) — the timeline has an
    /// entry at midnight for exactly this.
    func todayProgress(at date: Date, calendar: Calendar = .current) -> Double {
        guard hasSynced, !rings.isEmpty, calendar.isDate(updatedAt, inSameDayAs: date) else { return 0 }
        let total = rings.reduce(0.0) { $0 + min(1, max(0, $1.progress)) }
        return total / Double(rings.count)
    }

    /// Reads the last snapshot the watch app persisted. A synchronous App Group read, so the
    /// timeline provider needs no Task (and doesn't capture WidgetKit's completion in one).
    static func load() -> ComplicationSnapshot {
        guard let defaults = UserDefaults(suiteName: WatchAppGroup.identifier),
              let data = defaults.data(forKey: WatchAppGroup.snapshotKey),
              let snapshot = try? JSONDecoder().decode(ComplicationSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
