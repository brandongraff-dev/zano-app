// StreakComplication.swift
// Watch/ZANOWatchComplications
//
// docs/spec.md §5.21 ("complication with rings"): the streak on the watch face, around a ring of
// today's goal progress, in all four accessory families watchOS offers.
//
// Data: `ComplicationSnapshot.load()` (the watch App Group, written by the watch app whenever the
// phone syncs). The watch app asks WidgetKit to reload this kind when the streak, level or rings
// change (`WatchStateStore.apply`); the 30-minute policy below is only a safety net. A second
// entry at local midnight empties today's ring without waiting for the phone.
//
// API notes (watchOS 10 SDK; checked against Apple's WidgetKit docs, not compiled here):
// `.accessoryCorner` is watchOS-only; `.widgetLabel` is the corner's curved label;
// `.accessoryCircularCapacity` and `AccessoryWidgetBackground` exist on watchOS 9+;
// `.containerBackground(_:for:)` is required for widgets from watchOS 10.

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct StreakComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot

    var todayProgress: Double { snapshot.todayProgress(at: date) }
}

struct StreakComplicationProvider: TimelineProvider {
    typealias Entry = StreakComplicationEntry

    func placeholder(in context: Context) -> StreakComplicationEntry {
        StreakComplicationEntry(date: .now, snapshot: .galleryPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakComplicationEntry) -> Void) {
        let snapshot = context.isPreview ? ComplicationSnapshot.galleryPreview : ComplicationSnapshot.load()
        completion(StreakComplicationEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakComplicationEntry>) -> Void) {
        let now = Date.now
        let snapshot = ComplicationSnapshot.load()
        var entries = [StreakComplicationEntry(date: now, snapshot: snapshot)]
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(StreakComplicationEntry(date: midnight, snapshot: snapshot))
        }
        let refresh = now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Widget

struct StreakComplication: Widget {
    let kind = WatchAppGroup.streakComplicationKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakComplicationProvider()) { entry in
            StreakComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(Copy.watchComplication.displayName)
        .description(Copy.watchComplication.description)
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Views

/// The two colours the complication uses, hand-copied like everything in `WatchTheme.swift`
/// (which this target doesn't compile). On tinted faces watchOS recolours them; the parts marked
/// `.widgetAccentable()` take the face's accent.
private enum ComplicationColors {
    /// `WatchTheme.Buddy.ember` (#FF8A3D), the streak flame.
    static let flame = Color(red: 1.0, green: 0x8A / 255.0, blue: 0x3D / 255.0)
    /// `WatchTheme.Colors.accent` (#5B8DEF), today's ring.
    static let accent = Color(red: 0x5B / 255.0, green: 0x8D / 255.0, blue: 0xEF / 255.0)
}

struct StreakComplicationView: View {
    let entry: StreakComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: ComplicationSnapshot { entry.snapshot }
    private var streak: Int { max(0, snapshot.currentStreak) }
    private var streakNumber: String {
        snapshot.hasSynced ? "\(streak)" : Copy.watchComplication.noStreakNumber
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            circular
        }
    }

    // Streak number under a flame, inside a capacity ring of today's progress.
    private var circular: some View {
        Gauge(value: entry.todayProgress) {
            Text(Copy.watchComplication.today)
        } currentValueLabel: {
            VStack(spacing: -1) {
                flame(size: 10)
                Text(streakNumber)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(ComplicationColors.accent)
    }

    // Flame in the corner, "12 days" along the bezel.
    private var corner: some View {
        ZStack {
            AccessoryWidgetBackground()
            flame(size: 20)
        }
        .widgetLabel {
            Text(snapshot.hasSynced
                 ? Copy.watchComplication.streakCorner(streak)
                 : Copy.watchComplication.notSyncedInline)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                flame(size: 14)
                Text(snapshot.hasSynced
                     ? Copy.watchComplication.streak(streak)
                     : Copy.watchComplication.notSynced)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if snapshot.hasSynced {
                HStack(spacing: 6) {
                    Text(Copy.watchComplication.today)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    ProgressView(value: entry.todayProgress)
                        .tint(ComplicationColors.accent)
                        .widgetAccentable()
                }
                if let level = snapshot.level {
                    Text(Copy.watchComplication.buddyLevel(max(1, level)))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // One line of text plus an optional image; watchOS renders the rest of the styling.
    private var inline: some View {
        Label(
            snapshot.hasSynced
                ? Copy.watchComplication.streak(streak)
                : Copy.watchComplication.notSyncedInline,
            systemImage: "flame.fill"
        )
    }

    private func flame(size: CGFloat) -> some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(ComplicationColors.flame)
            .widgetAccentable()
    }

    private var accessibilityText: String {
        guard snapshot.hasSynced else { return Copy.watchComplication.notSynced }
        let percent = Int((entry.todayProgress * 100).rounded())
        return Copy.watchComplication.accessibility(streak: streak, todayPercent: percent)
    }
}
