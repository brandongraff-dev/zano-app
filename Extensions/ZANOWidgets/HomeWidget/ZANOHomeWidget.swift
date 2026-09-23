// ZANOHomeWidget.swift
// Extensions/ZANOWidgets/HomeWidget
//
// Home Screen widget — docs/spec.md §6:
//   Small:  streak + lock status + "Start Lock" button
//   Medium: 3 goal rings + buttons: "+25g", "+500ml", "Start Focus"
//   Large:  Today's plan, Time Bank, next lock time, quick actions
//
// One `Widget`/`TimelineProvider` supporting all three system families (`.systemSmall`,
// `.systemMedium`, `.systemLarge`) — the entry view switches on `@Environment(\.widgetFamily)`,
// the standard WidgetKit pattern for "one widget, three sizes" (all three read the exact same
// `ZANOWidgetSnapshot`).
//
// Buttons run real App Intents via `Button(intent:)` (interactive widgets, iOS 17+ — spec §27:
// "Interactive widgets can only run App Intents; no navigation, and updates need a timeline
// reload after the intent."):
//   - `LogProteinIntent`, `LogWaterIntent`, `StartFocusIntent` — exact CONTRACTS names from this
//     task, called with the exact quantities spec §6 prints on the buttons themselves ("+25g",
//     "+500ml").
//   - `StartLockIntent` — spec §14's catalog intent for the Small widget's "Start Lock" button.
//     Not one of this task's 4 frozen CONTRACTS names, so its initializer below is this session's
//     best-effort guess (mirrors the given `LockEngineManager.startLock` contract exactly) —
//     flagged in this task's decisions/knownIssues for reconciliation with whichever session
//     actually authors Core/Sources/Core/Intents/StartLockIntent.swift.

import AppIntents
import Core
import SwiftUI
import WidgetKit

struct ZANOHomeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ZANOWidgetSnapshot
}

struct ZANOHomeWidgetProvider: TimelineProvider {
    typealias Entry = ZANOHomeWidgetEntry

    func placeholder(in context: Context) -> ZANOHomeWidgetEntry {
        ZANOHomeWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ZANOHomeWidgetEntry) -> Void) {
        if context.isPreview {
            completion(ZANOHomeWidgetEntry(date: .now, snapshot: .placeholder))
            return
        }
        // `loadSnapshot()` is a synchronous App Group read, so no Task is needed (and wrapping
        // WidgetKit's non-Sendable `completion` in one is a Swift 6 data-race error).
        let snapshot = ZANOWidgetDataStore.loadSnapshot()
        completion(ZANOHomeWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZANOHomeWidgetEntry>) -> Void) {
        let snapshot = ZANOWidgetDataStore.loadSnapshot()
        let entry = ZANOHomeWidgetEntry(date: .now, snapshot: snapshot)
        // Goal/lock/Time Bank state only changes when an App Intent runs (which itself
        // triggers a timeline reload, per spec §27) or at most once a minute from natural
        // elapsed-time drift (e.g. "next lock in Nm"), so a 15-minute safety-net refresh
        // (DeviceActivity's own minimum granularity, spec §27) is a reasonable ceiling.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct ZANOHomeWidget: Widget {
    let kind = "com.zano.app.widget.home"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZANOHomeWidgetProvider()) { entry in
            ZANOHomeWidgetEntryView(entry: entry)
                .containerBackground(ZANOWidgetColor.background, for: .widget)
        }
        .configurationDisplayName(Text(WidgetCopy.appName))
        .description(Text(WidgetCopy.todaysPlanTitle))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ZANOHomeWidgetEntryView: View {
    let entry: ZANOHomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            ZANOHomeMediumView(snapshot: entry.snapshot)
        case .systemLarge:
            ZANOHomeLargeView(snapshot: entry.snapshot)
        default:
            ZANOHomeSmallView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Small

private struct ZANOHomeSmallView: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZANOStreakPillView(streak: snapshot.currentStreak)
                Spacer()
                ZANOLockBadgeView(isLocked: snapshot.isLocked)
            }
            Spacer(minLength: 0)
            Text(snapshot.isLocked
                ? WidgetCopy.lockedStatus(lockSetName: snapshot.lockSetName)
                : WidgetCopy.noActiveLock)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ZANOWidgetColor.textPrimary)
                .lineLimit(2)
            if snapshot.isLocked && snapshot.goalsRemainingForActiveLock > 0 {
                Text(WidgetCopy.goalsRemaining(snapshot.goalsRemainingForActiveLock))
                    .font(.caption2)
                    .foregroundStyle(ZANOWidgetColor.textMuted)
            }
            Spacer(minLength: 0)
            Button(intent: ZANOStartLockIntent(
                lockSetID: snapshot.defaultLockSetID,
                requiredGoalIDs: snapshot.todaysActiveGoalIDs
            )) {
                Text(WidgetCopy.startLockButton)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(ZANOWidgetColor.accent)
            .buttonStyle(.borderedProminent)
            .disabled(snapshot.isLocked)
        }
    }
}

// MARK: - Medium

private struct ZANOHomeMediumView: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZANOStreakPillView(streak: snapshot.currentStreak)
                Spacer()
                ZANOLockBadgeView(isLocked: snapshot.isLocked)
                Text(snapshot.isLocked
                    ? WidgetCopy.lockedStatus(lockSetName: snapshot.lockSetName)
                    : WidgetCopy.noActiveLock)
                    .font(.caption2)
                    .foregroundStyle(ZANOWidgetColor.textMuted)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                ZANOGoalRingView(progress: snapshot.protein, color: ZANOWidgetColor.ringProtein)
                ZANOGoalRingView(progress: snapshot.water, color: ZANOWidgetColor.ringWater)
                ZANOGoalRingView(progress: snapshot.focus, color: ZANOWidgetColor.ringFocus)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button(intent: LogProteinIntent(grams: 25, source: .widget)) {
                    Text(WidgetCopy.logProteinButton)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                Button(intent: LogWaterIntent(milliliters: 500, source: .widget)) {
                    Text(WidgetCopy.logWaterButton)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                Button(intent: StartFocusIntent(minutes: 25)) {
                    Text(WidgetCopy.startFocusButton)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(ZANOWidgetColor.textPrimary)
        }
    }
}

// MARK: - Large

private struct ZANOHomeLargeView: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZANOStreakPillView(streak: snapshot.currentStreak)
                Spacer()
                ZANOLockBadgeView(isLocked: snapshot.isLocked)
                Text(snapshot.isLocked
                    ? WidgetCopy.lockedStatus(lockSetName: snapshot.lockSetName)
                    : WidgetCopy.noActiveLock)
                    .font(.caption)
                    .foregroundStyle(ZANOWidgetColor.textMuted)
            }

            Text(WidgetCopy.todaysPlanTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(ZANOWidgetColor.textMuted)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ZANOGoalRowView(progress: snapshot.protein, color: ZANOWidgetColor.ringProtein)
                ZANOGoalRowView(progress: snapshot.water, color: ZANOWidgetColor.ringWater)
                ZANOGoalRowView(progress: snapshot.focus, color: ZANOWidgetColor.ringFocus)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(WidgetCopy.timeBankTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                        .textCase(.uppercase)
                    Spacer()
                    Text(WidgetCopy.minutesRemaining(snapshot.earnedMinutesRemainingToday))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ZANOWidgetColor.textPrimary)
                }
                ZANOTimeBankBarView(remainingMinutes: snapshot.earnedMinutesRemainingToday)
            }

            Text(WidgetCopy.nextLock(snapshot.nextScheduledLockAt))
                .font(.caption2)
                .foregroundStyle(ZANOWidgetColor.textMuted)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(intent: LogProteinIntent(grams: 25, source: .widget)) {
                    Text(WidgetCopy.logProteinButton)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                Button(intent: LogWaterIntent(milliliters: 500, source: .widget)) {
                    Text(WidgetCopy.logWaterButton)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                Button(intent: StartFocusIntent(minutes: 25)) {
                    Text(WidgetCopy.startFocusButton)
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(ZANOWidgetColor.textPrimary)
        }
    }
}

#Preview(as: .systemSmall) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .placeholder)
}
