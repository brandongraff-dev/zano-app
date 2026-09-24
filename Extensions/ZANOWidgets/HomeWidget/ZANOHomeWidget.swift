// ZANOHomeWidget.swift
// Extensions/ZANOWidgets/HomeWidget
//
// Home Screen widget, built around the charged star (the ZANO mark filling with silver as goals
// get done — see `ZANOChargedStar` in Support/ZANOWidgetComponents.swift):
//   Small:  the star centred, "2 goals left" / "Unlocked" under it, streak flame in the corner.
//   Medium: star on the left; lock status, the big number of goals left, and one capsule row per
//           goal in its ring color, each with its quick-log button.
//   Large:  the medium layout's header, the goal rows with amounts, Time Bank, next lock time,
//           and "Start lock" when nothing is locked.
//
// The star's charge is goal progress (`ZANOWidgetCharge`): widgets can't read Screen Time.
//
// One `Widget`/`TimelineProvider` for all three families; the entry view switches on
// `@Environment(\.widgetFamily)` and sets the matching container background (the glow sits
// behind wherever the star is).
//
// Buttons run real App Intents via `Button(intent:)` (interactive widgets, iOS 17+; spec §27):
// Core's `LogProteinIntent` / `LogWaterIntent` / `StartFocusIntent` with the quantities printed
// on the chips, and this extension's `ZANOStartLockIntent` (Support/ZANOWidgetIntents.swift).
// No new intents.

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
        ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ZANOHomeWidgetEntry) -> Void) {
        if context.isPreview {
            completion(ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview))
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
        }
        .configurationDisplayName(Text(WidgetCopy.appName))
        .description(Text(WidgetCopy.widgetDescription))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ZANOHomeWidgetEntryView: View {
    let entry: ZANOHomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let charge = entry.snapshot.charge
        switch family {
        case .systemMedium:
            ZANOHomeMediumView(snapshot: entry.snapshot, charge: charge)
                .containerBackground(for: .widget) {
                    ZANOWidgetBackground(glowCenter: UnitPoint(x: 0.2, y: 0.5), charge: charge.fraction)
                }
        case .systemLarge:
            ZANOHomeLargeView(snapshot: entry.snapshot, charge: charge)
                .containerBackground(for: .widget) {
                    ZANOWidgetBackground(glowCenter: UnitPoint(x: 0.18, y: 0.12), charge: charge.fraction)
                }
        default:
            ZANOHomeSmallView(snapshot: entry.snapshot, charge: charge)
                .containerBackground(for: .widget) {
                    ZANOWidgetBackground(glowCenter: UnitPoint(x: 0.5, y: 0.4), charge: charge.fraction, glowRadius: 90)
                }
        }
    }
}

// MARK: - Shared pieces

/// "2 goals left" / "All goals done" / "Unlocked".
private func headline(for charge: ZANOWidgetCharge) -> String {
    guard charge.isLocked else { return WidgetCopy.noActiveLock }
    return charge.remaining > 0 ? WidgetCopy.goalsRemaining(charge.remaining) : WidgetCopy.allGoalsDone
}

/// The big number of goals left (locked), or "Unlocked" in the same weight.
private struct ZANOBigCountView: View {
    let charge: ZANOWidgetCharge
    var size: CGFloat = 34

    var body: some View {
        if charge.isLocked {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(charge.remaining)")
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                    .contentTransition(.numericText())
                Text(WidgetCopy.goalsLeftUnit(charge.remaining))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZANOWidgetColor.textMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.goalsRemaining(charge.remaining))
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetCopy.noActiveLock)
                    .font(.system(size: size * 0.7, weight: .bold, design: .rounded))
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if charge.total > 0 {
                    Text(WidgetCopy.goalsDone(charge.done, of: charge.total))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// The quick-log chip for a goal row, running that goal's existing App Intent.
@ViewBuilder
private func quickLogButton(for goal: ZANOTrackedGoal) -> some View {
    switch goal.kind {
    case .protein:
        Button(intent: LogProteinIntent(grams: 25, source: .widget)) {
            ZANOQuickLogChip(color: goal.color, text: WidgetCopy.logProteinButton)
        }
        .buttonStyle(.plain)
    case .water:
        Button(intent: LogWaterIntent(milliliters: 500, source: .widget)) {
            ZANOQuickLogChip(color: goal.color, text: WidgetCopy.logWaterButton)
        }
        .buttonStyle(.plain)
    case .focus:
        Button(intent: StartFocusIntent(minutes: 25)) {
            ZANOQuickLogChip(color: goal.color, systemImage: "play.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WidgetCopy.startFocusButton)
    }
}

// MARK: - Small

private struct ZANOHomeSmallView: View {
    let snapshot: ZANOWidgetSnapshot
    let charge: ZANOWidgetCharge

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                ZANOChargedStar(charge: charge.fraction, glowRadius: 12)
                    .frame(height: 58)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WidgetCopy.chargeAccessibility(done: charge.done, total: charge.total))
                VStack(spacing: 2) {
                    Text(headline(for: charge))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(ZANOWidgetColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ZANOWidgetColor.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            ZANOStreakFlameView(streak: snapshot.currentStreak)
        }
    }

    /// The lock set's name while locked; "1 of 3 goals" otherwise.
    private var caption: String? {
        if snapshot.isLocked {
            guard let name = snapshot.lockSetName, !name.isEmpty else { return nil }
            return name
        }
        return charge.total > 0 ? WidgetCopy.goalsDone(charge.done, of: charge.total) : nil
    }
}

// MARK: - Medium

private struct ZANOHomeMediumView: View {
    let snapshot: ZANOWidgetSnapshot
    let charge: ZANOWidgetCharge

    var body: some View {
        HStack(spacing: 14) {
            ZANOChargedStar(charge: charge.fraction, glowRadius: 16)
                .frame(width: 104)
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WidgetCopy.chargeAccessibility(done: charge.done, total: charge.total))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ZANOLockStatusLine(snapshot: snapshot)
                    Spacer(minLength: 4)
                    ZANOStreakFlameView(streak: snapshot.currentStreak)
                }
                ZANOBigCountView(charge: charge, size: 30)
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    ForEach(snapshot.displayGoals) { goal in
                        ZANOGoalCapsuleRow(goal: goal) {
                            quickLogButton(for: goal)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Large

private struct ZANOHomeLargeView: View {
    let snapshot: ZANOWidgetSnapshot
    let charge: ZANOWidgetCharge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZANOChargedStar(charge: charge.fraction, glowRadius: 14)
                    .frame(width: 92)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WidgetCopy.chargeAccessibility(done: charge.done, total: charge.total))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ZANOLockStatusLine(snapshot: snapshot)
                        Spacer(minLength: 4)
                        ZANOStreakFlameView(streak: snapshot.currentStreak)
                    }
                    ZANOBigCountView(charge: charge, size: 34)
                }
            }

            Text(WidgetCopy.todaysPlanTitle)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ZANOWidgetColor.textMuted)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                ForEach(snapshot.displayGoals) { goal in
                    ZANOGoalCapsuleRow(goal: goal, showsAmount: true) {
                        quickLogButton(for: goal)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(WidgetCopy.timeBankTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                        .textCase(.uppercase)
                    Spacer()
                    Text(WidgetCopy.minutesRemaining(snapshot.earnedMinutesRemainingToday))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ZANOWidgetColor.textPrimary)
                }
                ZANOTimeBankBarView(remainingMinutes: snapshot.earnedMinutesRemainingToday)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(WidgetCopy.nextLock(snapshot.nextScheduledLockAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ZANOWidgetColor.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !snapshot.isLocked && snapshot.defaultLockSetID != nil {
                    Button(intent: ZANOStartLockIntent(
                        lockSetID: snapshot.defaultLockSetID,
                        requiredGoalIDs: snapshot.todaysActiveGoalIDs
                    )) {
                        Label(WidgetCopy.startLockButton, systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(ZANOWidgetColor.accent))
                    }
                    .buttonStyle(.plain)
                    .widgetAccentable()
                }
            }
        }
    }
}

#Preview(as: .systemSmall) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
}

#Preview(as: .systemMedium) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
}

#Preview(as: .systemLarge) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
}
