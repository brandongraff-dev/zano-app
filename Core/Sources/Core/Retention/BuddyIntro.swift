// BuddyIntro.swift
// Core / Retention
//
// The first-week buddy intro (founder-approved, 2026-10-04): for the user's first seven days, Today
// shows one short tip from their buddy per day (how the lock works, widgets, charge, XP and gear, the
// weekly boss, Plan B and freezes, emergency unlock). Day 1 is the first day Today shows a tip. A tip
// dismissed with "Got it" stays gone; the next day's tip appears the next day. Missed days are
// skipped, not queued: the intro never piles up homework.

import Foundation

public enum BuddyIntro {
    public static let tipCount = 7
    /// App Group keys: the intro's first day, and the highest tip index dismissed.
    public static let startKey = "shared.buddyIntroStart"
    public static let dismissedKey = "shared.buddyIntroDismissed"

    /// Today's tip index (0...6), or nil when the week is over or today's tip was dismissed.
    /// Starts the intro on first call.
    public static func tipForToday(now: Date = .now, defaults: UserDefaults = SharedDefaults.store, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: now)
        let start: Date
        if let stored = defaults.object(forKey: startKey) as? Date {
            start = calendar.startOfDay(for: stored)
        } else {
            defaults.set(today, forKey: startKey)
            start = today
        }
        let day = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        guard day >= 0, day < tipCount else { return nil }
        let dismissed = defaults.object(forKey: dismissedKey) as? Int ?? -1
        return day > dismissed ? day : nil
    }

    /// "Got it" on tip `index`.
    public static func dismiss(_ index: Int, defaults: UserDefaults = SharedDefaults.store) {
        let dismissed = defaults.object(forKey: dismissedKey) as? Int ?? -1
        defaults.set(max(dismissed, index), forKey: dismissedKey)
    }
}
