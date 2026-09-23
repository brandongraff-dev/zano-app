// ZANOLockScreenWidget.swift
// Extensions/ZANOWidgets/LockScreenWidget
//
// Lock Screen widgets — docs/spec.md §6:
//   Circular:    protein ring / water ring / streak
//   Rectangular: "2 goals left · TikTok locked · 14🔥"
//   Inline:      "Locked until workout"
//
// One `Widget` covering all three accessory families (`.accessoryCircular`,
// `.accessoryRectangular`, `.accessoryInline`), available since iOS 16 — no gating needed against
// this project's iOS 17 minimum (project.yml).
//
// The circular family is user-configurable (spec lists 3 different things it can show — protein
// ring / water ring / streak — which is exactly what `WidgetConfigurationIntent` +
// `AppIntentConfiguration` exists for: a user picks the stat via the widget's own Edit Widget UI,
// no app launch needed). This configuration intent lives entirely in this extension (display
// config only, no user *action* — CLAUDE.md's "every user action is an App Intent in Core" is
// about actions like logging/locking, not which stat a widget renders).
//
// Rectangular substitutes the app name from spec's example line ("TikTok locked") for the active
// `LockSet.name` ("Distractions locked"): a shielded app's real name/icon can only be rendered via
// FamilyControls' privacy-preserving `Label(_:)` over a decoded `ApplicationToken`, which needs
// the `com.apple.developer.family-controls` entitlement + a `FamilyControls` import — neither of
// which this extension target currently has (project.yml, not owned by this task). Flagged in
// this task's knownIssues; `LockSet.name` is real data this widget can already show without that
// entitlement change.

import AppIntents
import Core
import SwiftUI
import WidgetKit

// MARK: - Configuration

enum ZANOCircularMetric: String, AppEnum {
    case protein
    case water
    case streak

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource(stringLiteral: WidgetCopy.lockScreenConfigTitle))
    }

    static var caseDisplayRepresentations: [ZANOCircularMetric: DisplayRepresentation] = [
        .protein: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: WidgetCopy.metricProtein)),
        .water: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: WidgetCopy.metricWater)),
        .streak: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: WidgetCopy.metricStreak))
    ]
}

struct ZANOLockScreenMetricIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Stat"
    static var description = IntentDescription(
        LocalizedStringResource(stringLiteral: WidgetCopy.lockScreenConfigDescription)
    )

    @Parameter(title: "Stat", default: .streak)
    var metric: ZANOCircularMetric

    init() {
        self.metric = .streak
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
        ZANOLockScreenEntry(date: .now, snapshot: .placeholder, metric: .streak)
    }

    func snapshot(for configuration: ZANOLockScreenMetricIntent, in context: Context) async -> ZANOLockScreenEntry {
        ZANOLockScreenEntry(date: .now, snapshot: .placeholder, metric: configuration.metric)
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
        .description(Text(WidgetCopy.lockScreenConfigDescription))
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
        case .protein:
            ring(for: snapshot.protein, systemImage: "fork.knife")
        case .water:
            ring(for: snapshot.water, systemImage: "drop.fill")
        case .streak:
            streakGauge
        }
    }

    // Switches on `metric` (already known at every call site above) rather than re-deriving the
    // icon from `progress.title == "Protein"` — a string-equality check against `title`, which is
    // permanently the hardcoded English literal "Protein" today (see `ZANOWidgetSnapshot.swift`).
    // The moment that title is localized for real, the old check would silently break: every
    // non-English locale's protein ring would render the water icon instead. See
    // `docs/design/ui-stress-test-findings.md` §2.3.
    private func ring(for progress: ZANORingProgress, systemImage: String) -> some View {
        Gauge(value: progress.fraction) {
            Image(systemName: systemImage)
        } currentValueLabel: {
            Text(Self.intText(progress.current))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var streakGauge: some View {
        VStack(spacing: 0) {
            Text("🔥")
                .font(.system(size: 14))
            Text("\(snapshot.currentStreak)")
                .font(.system(.body, design: .rounded, weight: .bold))
                // `.accessoryCircular` is one of the smallest possible widget surfaces, and a
                // streak count is unbounded — matches the Home Widget's own
                // `ZANOGoalRingView`/`.minimumScaleFactor(0.7)` precedent for the same reason. See
                // `docs/design/ui-stress-test-findings.md` §3.7.
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .widgetAccentable()
    }

    private static func intText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.0f", value)
    }
}

// MARK: - Rectangular

private struct ZANOLockScreenRectangularView: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.isLocked
                ? WidgetCopy.lockedStatus(lockSetName: snapshot.lockSetName)
                : WidgetCopy.noActiveLock)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 4) {
                if snapshot.isLocked {
                    Text(WidgetCopy.goalsRemaining(snapshot.goalsRemainingForActiveLock))
                }
                Text("·")
                Text(WidgetCopy.streak(snapshot.currentStreak))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
    ZANOLockScreenEntry(date: .now, snapshot: .placeholder, metric: .streak)
}

#Preview(as: .accessoryRectangular) {
    ZANOLockScreenWidget()
} timeline: {
    ZANOLockScreenEntry(date: .now, snapshot: .placeholder, metric: .streak)
}

#Preview(as: .accessoryInline) {
    ZANOLockScreenWidget()
} timeline: {
    ZANOLockScreenEntry(date: .now, snapshot: .placeholder, metric: .streak)
}
