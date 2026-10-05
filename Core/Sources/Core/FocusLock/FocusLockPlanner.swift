// FocusLockPlanner.swift
// Core / FocusLock
//
// Pure logic (docs/spec.md §5.24): turns the next two days of calendar events into lock windows,
// each with a decision (lock, ask, or leave alone). No EventKit, no DeviceActivity, no clock: the
// callers pass `now`, so every rule here is unit-tested.
//
// Rules, in order:
//   1. Skip all-day events, events marked free, events outside the chosen calendars, events already
//      under way, events past the planning horizon, and events shorter than 15 minutes (a
//      DeviceActivity window can't be) or longer than 4 hours (a day-long block isn't a meeting).
//   2. An event qualifies if it is a focus block (title has a keyword) or a meeting (other attendees),
//      per the user's switches. Focus beats meeting when both apply.
//   3. The learning memory decides: events the user said no to twice are dropped here.
//   4. Windows less than 5 minutes apart are joined into one, which asks if any part would ask.
//   5. At most 8 windows, soonest first.

import Foundation

public enum FocusLockPlanner {

    public static func plan(
        events: [FocusCalendarEvent],
        settings: FocusLockSettings,
        memory: FocusLockPatternMemory,
        now: Date
    ) -> [FocusLockProposal] {
        guard settings.isEnabled else { return [] }
        let horizon = now.addingTimeInterval(TimeInterval(FocusLockSettings.horizonHours * 3_600))

        var items: [FocusLockProposal] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            guard qualifies(event, settings: settings, now: now, horizon: horizon),
                  let reason = reason(for: event, settings: settings)
            else { continue }
            let key = FocusLockPattern.key(forTitle: event.title)
            let decision = memory.decision(for: key)
            if decision == .skip { continue }
            let window = FocusLockWindow(
                id: windowID(patternKey: key, start: event.start),
                start: event.start,
                end: event.end,
                reason: reason,
                patternKey: key,
                title: event.title
            )
            items.append(FocusLockProposal(window: window, decision: decision))
        }
        return Array(merge(items).prefix(FocusLockSettings.maxWindows))
    }

    // MARK: Rules

    static func qualifies(_ event: FocusCalendarEvent, settings: FocusLockSettings, now: Date, horizon: Date) -> Bool {
        guard !event.isAllDay, event.isBusy else { return false }
        if let allowed = settings.calendarIDs, !allowed.contains(event.calendarID) { return false }
        guard event.start > now, event.start < horizon else { return false }
        return (FocusLockSettings.minMinutes...FocusLockSettings.maxMinutes).contains(event.minutes)
    }

    static func reason(for event: FocusCalendarEvent, settings: FocusLockSettings) -> FocusLockReason? {
        if settings.includeFocusBlocks, matchesKeyword(event.title, keywords: settings.keywords) { return .focusBlock }
        if settings.includeMeetings, event.hasOtherAttendees { return .meeting }
        return nil
    }

    static func matchesKeyword(_ title: String, keywords: [String]) -> Bool {
        let lowered = title.lowercased()
        return keywords.contains { word in
            let trimmed = word.trimmingCharacters(in: .whitespaces).lowercased()
            return !trimmed.isEmpty && lowered.contains(trimmed)
        }
    }

    /// Joins windows that overlap or sit within `mergeGapMinutes` of each other. A joined window
    /// starts with the first, ends with the last, asks if any part asks, and counts as a focus block
    /// if any part is one.
    static func merge(_ items: [FocusLockProposal]) -> [FocusLockProposal] {
        var merged: [FocusLockProposal] = []
        let gap = TimeInterval(FocusLockSettings.mergeGapMinutes * 60)
        for item in items.sorted(by: { $0.window.start < $1.window.start }) {
            guard var last = merged.last, item.window.start.timeIntervalSince(last.window.end) <= gap else {
                merged.append(item)
                continue
            }
            last.window.end = max(last.window.end, item.window.end)
            last.window.mergedCount += item.window.mergedCount
            if item.window.reason == .focusBlock { last.window.reason = .focusBlock }
            if item.decision == .ask { last.decision = .ask }
            merged[merged.count - 1] = last
        }
        return merged
    }

    static func windowID(patternKey: String, start: Date) -> String {
        "\(patternKey)-\(Int(start.timeIntervalSince1970 / 60))"
    }
}
