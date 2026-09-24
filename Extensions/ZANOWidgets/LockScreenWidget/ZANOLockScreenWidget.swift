// ZANOLockScreenWidget.swift
// Extensions/ZANOWidgets/LockScreenWidget
//
// Lock Screen widgets, built around the ZANO star and goal progress (never Screen Time — widgets
// can't read it; see `ZANOWidgetCharge` in Support/ZANOWidgetComponents.swift):
//   Circular:    the star glyph inside an `.accessoryCircularCapacity` gauge of goals done
//                (default), or the older protein / water / streak stats, picked in Edit Widget.
//   Rectangular: "2 goals to unlock" beside the star, a one-segment-per-goal bar, and the lock
//                set + streak.
//   Inline:      "Locked · 2 goals left" / "Unlocked".
//
// One `Widget` covering all three accessory families (iOS 16+, below this project's iOS 17
// minimum). Accessory widgets render in vibrant (or accented) mode, so everything here is drawn
// in `.primary` with translucency for the "not yet" parts, and the earned parts are
// `.widgetAccentable()`.
//
// The circular stat is a `WidgetConfigurationIntent` that lives in this extension (display config
// only, not a user action). Shielded apps' real names/icons need FamilyControls' `Label(_:)` and
// the family-controls entitlement, which this target doesn't have, so the lock set's name stands
// in for them.

import AppIntents
import Core
import SwiftUI
import WidgetKit

// MARK: - Configuration

enum ZANOCircularMetric: String, AppEnum {
    case goals
    case protein
    case water
    case streak

    // EXCEPTION to "user-facing copy lives in Core/Copy": the AppIntents build-time metadata
    // extractor (appintentsmetadataprocessor) evaluates these declarations statically and rejects
    // anything that is not a string literal ("LocalizedStringResource must be initialized directly
    // ... or a String literal"). Keep these in sync with WidgetCopy.lockScreenConfigTitle /
    // metricGoals / metricProtein / metricWater / metricStreak by hand.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "ZANO Stat")
    }

    static let caseDisplayRepresentations: [ZANOCircularMetric: DisplayRepresentation] = [
        .goals: DisplayRepresentation(title: "Goals"),
        .protein: DisplayRepresentation(title: "Protein"),
        .water: DisplayRepresentation(title: "Water"),
        .streak: DisplayRepresentation(title: "Streak")
    ]
}

struct ZANOLockScreenMetricIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Stat"
    // Literal for the same metadata-extractor reason as above (WidgetCopy.lockScreenConfigDescription).
    static let description = IntentDescription("Choose which stat this Lock Screen widget shows.")

    @Parameter(title: "Stat", default: .goals)
    var metric: ZANOCircularMetric

    init() {
        self.metric = .goals
    }

    init(metric: ZANOCircularMetric) {
        self.metric = metric
    }
}

// MARK: - Entry + Provider

struct ZANOLockScreenEntry: TimelineEntry {
    let date: Date
    let snapshot: ZANOWidgetSnapshot
    let metric: ZANOCircularMetric
}

struct ZANOLockScreenProvider: AppIntentTimelineProvider {
    typealias Entry = ZANOLockScreenEntry
    typealias Intent = ZANOLockScreenMetricIntent

    func placeholder(in context: Context) -> ZANOLockScreenEntry {
        ZANOLockScreenEntry(date: .now, snapshot: .galleryPreview, metric: .goals)
    }

    func snapshot(for configuration: ZANOLockScreenMetricIntent, in context: Context) async -> ZANOLockScreenEntry {
        ZANOLockScreenEntry(date: .now, snapshot: .galleryPreview, metric: configuration.metric)
    }

    func timeline(
        for configuration: ZANOLockScreenMetricIntent,
        in context: Context
    ) async -> Timeline<ZANOLockScreenEntry> {
        let snapshot = ZANOWidgetDataStore.loadSnapshot()
        let entry = ZANOLockScreenEntry(date: .now, snapshot: snapshot, metric: configuration.metric)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? Date.now.addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

// MARK: - Widget

struct ZANOLockScreenWidget: Widget {
    let kind = "com.zano.app.widget.lockscreen"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ZANOLockScreenMetricIntent.self,
            provider: ZANOLockScreenProvider()
        ) { entry in
            ZANOLockScreenEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(Text(WidgetCopy.appName))
        .description(Text(WidgetCopy.widgetDescription))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ZANOLockScreenEntryView: View {
    let entry: ZANOLockScreenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            ZANOLockScreenRectangularView(snapshot: entry.snapshot)
        case .accessoryInline:
            ZANOLockScreenInlineView(snapshot: entry.snapshot)
        default:
            ZANOLockScreenCircularView(snapshot: entry.snapshot, metric: entry.metric)
        }
    }
}

// MARK: - Circular

private struct ZANOLockScreenCircularView: View {
    let snapshot: ZANOWidgetSnapshot
    let metric: ZANOCircularMetric

    var body: some View {
        switch metric {
        case .goals:
            goalsGauge
        case .protein:
            ring(for: snapshot.protein, systemImage: "fork.knife")
        case .water:
            ring(for: snapshot.water, systemImage: "drop.fill")
        case .streak:
            streakGauge
        }
    }

    /// The star glyph in a capacity ring that fills as goals get done.
    private var goalsGauge: some View {
        let charge = snapshot.charge
        return Gauge(value: charge.fraction) {
            Text(WidgetCopy.metricGoals)
        } currentValueLabel: {
            ZanoMarkShape()
                .fill(Color.primary, style: FillStyle(eoFill: true))
                .aspectRatio(ZanoMark.aspectRatio, contentMode: .fit)
                .frame(width: 26)
                .widgetAccentable()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(charge.isLocked
            ? WidgetCopy.goalsToUnlock(charge.remaining)
            : WidgetCopy.chargeAccessibility(done: charge.done, total: charge.total))
    }

    // Switches on `metric` rather than re-deriving the icon from `progress.title`, which breaks
    // the moment titles are localized. See `docs/design/ui-stress-test-findings.md` §2.3.
    private func ring(for progress: ZANORingProgress, systemImage: String) -> some View {
        Gauge(value: progress.fraction) {
            Image(systemName: systemImage)
        } currentValueLabel: {
            Text(Self.intText(progress.current))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var streakGauge: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .widgetAccentable()
                Text("\(snapshot.currentStreak)")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    // The streak count is unbounded and this is one of the smallest widget
                    // surfaces. See `docs/design/ui-stress-test-findings.md` §3.7.
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.streak(snapshot.currentStreak))
    }

    private static func intText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.0f", value)
    }
}

// MARK: - Rectangular

private struct ZANOLockScreenRectangularView: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        let charge = snapshot.charge
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                ZanoMarkShape()
                    .fill(Color.primary, style: FillStyle(eoFill: true))
                    .aspectRatio(ZanoMark.aspectRatio, contentMode: .fit)
                    .frame(width: 18)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(headline(charge))
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ZANOSegmentBar(done: charge.done, total: charge.total)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headline(_ charge: ZANOWidgetCharge) -> String {
        guard charge.isLocked else { return WidgetCopy.noActiveLock }
        return charge.remaining > 0 ? WidgetCopy.goalsToUnlock(charge.remaining) : WidgetCopy.allGoalsDone
    }

    /// "Locked · Social · 14-day streak", or "1 of 3 goals · 14-day streak" when unlocked.
    private var caption: String {
        let charge = snapshot.charge
        let lead = snapshot.isLocked
            ? WidgetCopy.lockStatusLine(lockSetName: snapshot.lockSetName)
            : (charge.total > 0 ? WidgetCopy.goalsDone(charge.done, of: charge.total) : nil)
        return [lead, WidgetCopy.streak(snapshot.currentStreak)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Inline

private struct ZANOLockScreenInlineView: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        Label(
            WidgetCopy.inlineStatus(
                isLocked: snapshot.isLocked,
                goalsRemaining: snapshot.goalsRemainingForActiveLock
            ),
            systemImage: snapshot.isLocked ? "lock.fill" : "lock.open.fill"
        )
    }
}

#Preview(as: .accessoryCircular) {
    ZANOLockScreenWidget()
} timeline: {
    ZANOLockScreenEntry(date: .now, snapshot: .galleryPreview, metric: .goals)
}

#Preview(as: .accessoryRectangular) {
    ZANOLockScreenWidget()
} timeline: {
    ZANOLockScreenEntry(date: .now, snapshot: .galleryPreview, metric: .goals)
}

#Preview(as: .accessoryInline) {
    ZANOLockScreenWidget()
} timeline: {
    ZANOLockScreenEntry(date: .now, snapshot: .galleryPreview, metric: .goals)
}
