// ZANOHomeWidget.swift
// Extensions/ZANOWidgets/HomeWidget
//
// Home Screen widget, built around the charged star (the ZANO mark filling with silver as goals
// get done — see `ZANOChargedStar` in Support/ZANOWidgetComponents.swift):
//   Small:  the star centred over the big "2 goals left" numeral (locked), or "Unlocked" with a
//           "Start lock" button when a default lock set exists; streak flame in the corner.
//           StandBy (no container background): a bigger star and numeral, no button, built to
//           read across a room; night mode's red tint comes from vibrant rendering, where the
//           star drops its blur glow and the earned parts stay `.widgetAccentable()`.
//   Medium: star on the left; lock status, the big number of goals left (or "Unlocked" with
//           "Start lock"), and one capsule row per goal in its ring color, each with its
//           quick-log button.
//   Large:  the medium layout's header, the goal rows with amounts, Time Bank, next lock time,
//           and "Start lock" when nothing is locked.
//
// The star's charge is goal progress (`ZANOWidgetCharge`): widgets can't read Screen Time.
//
// Buddies (2026-10-03): in full-colour rendering the star is replaced by the user's buddy
// (`ZANOWidgetBuddy`), posed by the same goal progress; accented/vibrant rendering (tinted Home
// Screen, StandBy at night) keeps the charged star.
//
// One `Widget`/`TimelineProvider` for all three families; the entry view switches on
// `@Environment(\.widgetFamily)` and sets the matching container background (the glow sits
// behind wherever the star is).
//
// Buttons run real App Intents via `Button(intent:)` (interactive widgets, iOS 17+; spec §27):
// Core's `LogProteinIntent` / `LogWaterIntent` / `StartFocusIntent` with the quantities printed
// on the chips, and Core's `StartLockIntent` (default lock set, all active goals) for "Start lock".
// No new intents. A tap anywhere else opens Today (`widgetURL`).

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
                .widgetURL(ZANOWidgetLink.today)
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
        content
            // Light mode (2026-10-03): follows the Home Screen's appearance, unless the user picked
            // Light or Dark in Settings > Appearance (App Group defaults), so it matches the app.
            .zanoAppAppearance()
    }

    @ViewBuilder
    private var content: some View {
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
@MainActor @ViewBuilder
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

/// "Start lock": Core's `StartLockIntent` with its defaults (the default lock set, every active
/// goal), the same path as the NFC Lock Card and Siri. Only shown while nothing is locked and a
/// default lock set exists, so it can never stack a second lock or fail for want of a set.
private struct ZANOStartLockButton: View {
    var compact: Bool = false

    var body: some View {
        Button(intent: StartLockIntent()) {
            Label(WidgetCopy.startLockButton, systemImage: "lock.fill")
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 5 : 6)
                .background(Capsule().fill(ZANOWidgetColor.accentFill))
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }
}

private extension ZANOWidgetSnapshot {
    var canStartLock: Bool { !isLocked && defaultLockSetID != nil }
}

// MARK: - Small

private struct ZANOHomeSmallView: View {
    let snapshot: ZANOWidgetSnapshot
    let charge: ZANOWidgetCharge

    /// `false` in StandBy (and wherever else the system strips the container background).
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsBackground {
                homeScreen
            } else {
                standBy
            }
            ZANOStreakFlameView(streak: snapshot.currentStreak)
        }
    }

    private var star: some View {
        ZANOWidgetBuddy(charge: charge, size: showsBackground ? (snapshot.canStartLock ? 48 : 64) : 64)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.chargeAccessibility(done: charge.done, total: charge.total))
    }

    private var homeScreen: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            star
            if charge.isLocked && charge.remaining > 0 {
                ZANOGoalsLeftNumeral(remaining: charge.remaining, size: 28)
            } else {
                Text(headline(for: charge))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if snapshot.canStartLock {
                ZANOStartLockButton(compact: true)
            } else if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ZANOWidgetColor.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// StandBy: read from across the room, often in the dark. Star and numeral only.
    private var standBy: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            star
            if charge.isLocked && charge.remaining > 0 {
                ZANOGoalsLeftNumeral(remaining: charge.remaining, size: 40)
            } else {
                Text(headline(for: charge))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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

/// The big "2" with "goals left" beside it — the small widget's (and StandBy's) headline.
private struct ZANOGoalsLeftNumeral: View {
    let remaining: Int
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(remaining)")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ZANOWidgetColor.textPrimary)
                .contentTransition(.numericText())
                .widgetAccentable()
            Text(WidgetCopy.goalsLeftUnit(remaining))
                .font(.system(size: max(11, size * 0.4), weight: .medium))
                .foregroundStyle(ZANOWidgetColor.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.goalsRemaining(remaining))
    }
}

// MARK: - Medium

private struct ZANOHomeMediumView: View {
    let snapshot: ZANOWidgetSnapshot
    let charge: ZANOWidgetCharge

    var body: some View {
        HStack(spacing: 14) {
            ZANOWidgetBuddy(charge: charge, size: 96)
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
                HStack(alignment: .center, spacing: 6) {
                    ZANOBigCountView(charge: charge, size: 30)
                    Spacer(minLength: 0)
                    if snapshot.canStartLock {
                        ZANOStartLockButton(compact: true)
                    }
                }
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
                ZANOWidgetBuddy(charge: charge, size: 96)
                    .frame(width: 96)
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
                if snapshot.canStartLock {
                    ZANOStartLockButton()
                }
            }
        }
    }
}

#Preview(as: .systemSmall) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryUnlocked)
}

#Preview(as: .systemMedium) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryUnlocked)
}

#Preview(as: .systemLarge) {
    ZANOHomeWidget()
} timeline: {
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryPreview)
    ZANOHomeWidgetEntry(date: .now, snapshot: .galleryUnlocked)
}
