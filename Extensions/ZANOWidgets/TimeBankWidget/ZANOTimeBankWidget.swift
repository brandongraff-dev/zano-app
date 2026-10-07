// ZANOTimeBankWidget.swift
// Extensions/ZANOWidgets/TimeBankWidget
//
// The Time Bank widget (session 35, docs/spec.md §5.2 Earn Rate, §6 widgets): its whole job is
// "you've earned 20 min" at a glance, the daily hook.
//   Small:       the buddy over the big minutes number ("35 min left"), and the next goal that
//                adds minutes ("Gym +90 min"). StandBy: buddy and a bigger number only.
//   Medium:      buddy on the left; Time Bank label + lock status, the big number, "Earned 60 ·
//                spent 25", the draining bar, the next-earn hint and one button.
//   Circular:    a capacity ring of today's earnings still in the bank, minutes in the middle.
//   Rectangular: "Time Bank · 35 min", a linear capacity gauge, the next-earn hint.
//   Inline:      "35 min left".
//
// The button (medium): while apps are locked and there are minutes, "Spend" opens the Lock tab
// (`zano://timebank`), where `LockStatusView` already spends/borrows minutes. Spending can't run
// here: it lifts shields, which needs the app's Family Controls entitlement (spec §27). Otherwise
// it's Core's existing `OpenTodayIntent` ("Earn more" / "Open ZANO"). No new intents.
//
// Data: `ZANOWidgetDataStore.loadSnapshot()` (App Group reads only, no networking, spec §11/§27);
// the numbers are normalized by Core's `TimeBankGlance`. `TimeBankEngine` reloads widget timelines
// on every earn/spend/refund (`WidgetRefresh.reloadAll()`), and the timeline also refreshes at
// local midnight, when unspent minutes expire.

import AppIntents
import Core
import SwiftUI
import WidgetKit

struct ZANOTimeBankEntry: TimelineEntry {
    let date: Date
    let snapshot: ZANOWidgetSnapshot
}

struct ZANOTimeBankProvider: TimelineProvider {
    typealias Entry = ZANOTimeBankEntry

    func placeholder(in context: Context) -> ZANOTimeBankEntry {
        ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ZANOTimeBankEntry) -> Void) {
        if context.isPreview {
            completion(ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview))
            return
        }
        // Synchronous App Group read; no Task (WidgetKit's `completion` isn't Sendable).
        completion(ZANOTimeBankEntry(date: .now, snapshot: ZANOWidgetDataStore.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZANOTimeBankEntry>) -> Void) {
        let now = Date.now
        let entry = ZANOTimeBankEntry(date: now, snapshot: ZANOWidgetDataStore.loadSnapshot())
        // Earn/spend reload the timeline themselves; this is the safety net, pulled in to local
        // midnight so expired minutes never linger on the Home Screen.
        let safetyNet = now.addingTimeInterval(15 * 60)
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? safetyNet
        completion(Timeline(entries: [entry], policy: .after(min(safetyNet, midnight))))
    }
}

struct ZANOTimeBankWidget: Widget {
    let kind = WidgetRefresh.timeBankWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZANOTimeBankProvider()) { entry in
            ZANOTimeBankEntryView(entry: entry)
                .widgetURL(ZANOWidgetLink.timeBank)
        }
        .configurationDisplayName(Text(WidgetCopy.timeBankTitle))
        .description(Text(WidgetCopy.timeBankWidgetDescription))
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

private extension ZANOWidgetSnapshot {
    var timeBank: TimeBankGlance {
        TimeBankGlance(
            balanceMinutes: earnedMinutesRemainingToday,
            earnedTodayMinutes: timeBankEarnedToday,
            spentTodayMinutes: timeBankSpentToday,
            isLocked: isLocked,
            nextEarn: timeBankNextEarn
        )
    }
}

struct ZANOTimeBankEntryView: View {
    let entry: ZANOTimeBankEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let bank = entry.snapshot.timeBank
        switch family {
        case .accessoryCircular:
            ZANOTimeBankCircularView(bank: bank)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            ZANOTimeBankRectangularView(bank: bank)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            ZANOTimeBankInlineView(bank: bank)
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            ZANOTimeBankMediumView(snapshot: entry.snapshot, bank: bank)
                .zanoAppAppearance()
                .containerBackground(for: .widget) {
                    ZANOWidgetBackground(glowCenter: UnitPoint(x: 0.2, y: 0.5), charge: bank.fractionLeft)
                }
        default:
            ZANOTimeBankSmallView(snapshot: entry.snapshot, bank: bank)
                .zanoAppAppearance()
                .containerBackground(for: .widget) {
                    ZANOWidgetBackground(glowCenter: UnitPoint(x: 0.5, y: 0.35), charge: bank.fractionLeft, glowRadius: 90)
                }
        }
    }
}

// MARK: - Shared pieces

/// "Gym +90 min", or "All goals banked today" / "Finish a goal to earn minutes".
private func nextEarnHint(_ bank: TimeBankGlance) -> String {
    if let next = bank.nextEarn {
        return WidgetCopy.timeBankNextEarn(title: next.title, minutes: next.minutes)
    }
    return bank.earnedTodayMinutes > 0 ? WidgetCopy.timeBankAllEarned : WidgetCopy.timeBankEmptyHint
}

/// The big "35" with "min left" / "min earned" beside it.
private struct ZANOTimeBankNumeral: View {
    let bank: TimeBankGlance
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(bank.balanceMinutes)")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ZANOWidgetColor.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(WidgetCopy.timeBankUnit(spentMinutes: bank.spentTodayMinutes))
                .font(.system(size: max(11, size * 0.36), weight: .medium))
                .foregroundStyle(ZANOWidgetColor.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.timeBankAccessibility(
            balance: bank.balanceMinutes,
            earned: bank.earnedTodayMinutes,
            spent: bank.spentTodayMinutes
        ))
    }
}

/// The capsule label shared by the medium widget's one button (same look as "Start lock").
private struct ZANOTimeBankButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(ZANOWidgetColor.accentFill))
            .widgetAccentable()
    }
}

/// "Spend" (locked, minutes in the bank) → the Lock tab; otherwise Core's `OpenTodayIntent`.
private struct ZANOTimeBankActionButton: View {
    let bank: TimeBankGlance

    var body: some View {
        if bank.canSpend {
            Link(destination: ZANOWidgetLink.timeBank) {
                ZANOTimeBankButtonLabel(title: WidgetCopy.timeBankSpendButton, systemImage: "hourglass")
            }
        } else {
            Button(intent: OpenTodayIntent()) {
                ZANOTimeBankButtonLabel(
                    title: bank.nextEarn == nil ? WidgetCopy.timeBankOpenButton : WidgetCopy.timeBankEarnMoreButton,
                    systemImage: bank.nextEarn == nil ? "arrow.up.forward.app" : "plus.circle.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Lock / unlock glyph for the small widget's corner.
private struct ZANOTimeBankLockGlyph: View {
    let isLocked: Bool

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(ZANOWidgetColor.textMuted)
            .accessibilityLabel(isLocked ? WidgetCopy.controlLockedLabel : WidgetCopy.noActiveLock)
    }
}

// MARK: - Small

private struct ZANOTimeBankSmallView: View {
    let snapshot: ZANOWidgetSnapshot
    let bank: TimeBankGlance

    /// `false` in StandBy (and wherever else the system strips the container background).
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                ZANOWidgetBuddy(charge: snapshot.charge, size: showsBackground ? 48 : 64)
                    .accessibilityHidden(true)
                ZANOTimeBankNumeral(bank: bank, size: showsBackground ? 32 : 42)
                if showsBackground {
                    Text(nextEarnHint(bank))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            if showsBackground {
                ZANOTimeBankLockGlyph(isLocked: bank.isLocked)
            }
        }
    }
}

// MARK: - Medium

private struct ZANOTimeBankMediumView: View {
    let snapshot: ZANOWidgetSnapshot
    let bank: TimeBankGlance

    var body: some View {
        HStack(spacing: 14) {
            ZANOWidgetBuddy(charge: snapshot.charge, size: 96)
                .frame(width: 104)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(WidgetCopy.timeBankTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ZANOLockStatusLine(snapshot: snapshot)
                }
                ZANOTimeBankNumeral(bank: bank, size: 34)
                Text(WidgetCopy.timeBankEarnedSpent(earned: bank.earnedTodayMinutes, spent: bank.spentTodayMinutes))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ZANOWidgetColor.textMuted)
                    .lineLimit(1)
                // The draining bar: today's earnings still in the bank. The numeral above
                // already speaks the balance, so the bar is hidden from VoiceOver.
                ZANOTimeBankBarView(remainingMinutes: bank.balanceMinutes, capMinutes: bank.earnedTodayMinutes)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(nextEarnHint(bank))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ZANOWidgetColor.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    ZANOTimeBankActionButton(bank: bank)
                }
            }
        }
    }
}

// MARK: - Lock Screen

private struct ZANOTimeBankCircularView: View {
    let bank: TimeBankGlance

    var body: some View {
        Gauge(value: bank.fractionLeft) {
            Image(systemName: "hourglass")
        } currentValueLabel: {
            VStack(spacing: -2) {
                Text("\(bank.balanceMinutes)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(WidgetCopy.timeBankMinutesUnit)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.timeBankAccessibility(
            balance: bank.balanceMinutes,
            earned: bank.earnedTodayMinutes,
            spent: bank.spentTodayMinutes
        ))
    }
}

private struct ZANOTimeBankRectangularView: View {
    let bank: TimeBankGlance

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .bold))
                    .widgetAccentable()
                Text(WidgetCopy.timeBankHeadline(balance: bank.balanceMinutes))
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Gauge(value: bank.fractionLeft) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            Text(nextEarnHint(bank))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.timeBankAccessibility(
            balance: bank.balanceMinutes,
            earned: bank.earnedTodayMinutes,
            spent: bank.spentTodayMinutes
        ))
        .accessibilityValue(nextEarnHint(bank))
    }
}

private struct ZANOTimeBankInlineView: View {
    let bank: TimeBankGlance

    var body: some View {
        Label(
            WidgetCopy.timeBankInline(balance: bank.balanceMinutes, spent: bank.spentTodayMinutes),
            systemImage: "hourglass"
        )
        .accessibilityLabel(WidgetCopy.timeBankAccessibility(
            balance: bank.balanceMinutes,
            earned: bank.earnedTodayMinutes,
            spent: bank.spentTodayMinutes
        ))
    }
}

#Preview(as: .systemSmall) {
    ZANOTimeBankWidget()
} timeline: {
    ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview)
    ZANOTimeBankEntry(date: .now, snapshot: .galleryUnlocked)
}

#Preview(as: .systemMedium) {
    ZANOTimeBankWidget()
} timeline: {
    ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview)
    ZANOTimeBankEntry(date: .now, snapshot: .galleryUnlocked)
}

#Preview(as: .accessoryCircular) {
    ZANOTimeBankWidget()
} timeline: {
    ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview)
}

#Preview(as: .accessoryRectangular) {
    ZANOTimeBankWidget()
} timeline: {
    ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview)
}

#Preview(as: .accessoryInline) {
    ZANOTimeBankWidget()
} timeline: {
    ZANOTimeBankEntry(date: .now, snapshot: .galleryPreview)
}
