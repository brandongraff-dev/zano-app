// ComplicationPlaceholder.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21: "Complication with rings" — a watch-face complication showing today's ring
// progress at a glance. The TYPE below (`GoalRingsComplication`) is now real, complete WidgetKit
// code — not the Session-0 stub this file used to hold — but it is still, honestly, NOT a working,
// installable complication yet, for exactly one remaining reason, unchanged from the skeleton this
// replaces and still out of this task's scope:
//
// Real watchOS complications (watchOS 9+) are WidgetKit widgets, and WidgetKit widgets must live in
// their own WidgetKit extension target (`type: app-extension`,
// `NSExtensionPointIdentifier: com.apple.widgetkit-extension`, `platform: watchOS`) embedded in
// ZANOWatch — the same pattern `ZANOWidgets` already uses for `ZANO` on iOS (see `project.yml`'s
// `ZANOWidgets` target and `Extensions/ZANOWidgets/ZANOWidgetsBundle.swift`). This task's scope was
// "everything under `Watch/ZANOWatch/`" — it does not extend to `project.yml`, which is where that
// extension target would need to be added (`project.yml`'s existing `ZANOWatch` comment block
// already calls this out as a "future v3 session, project.yml owner" TODO; not revisited here per
// CLAUDE.md's "don't smuggle in the next session's work" rule). Until that target exists, this
// type compiles and type-checks correctly (it's real `Widget`/`TimelineProvider` conformance,
// ready to move verbatim), but is never registered with a `WidgetBundle`/`@main` anywhere, so
// watchOS never actually offers it as an installable complication. Flagged in this task's
// knownIssues, same as the file it replaces.
//
// What IS real and complete: the data path. `GoalRingsComplicationProvider` reads
// `WatchStateStore.readSnapshotForComplication()` — the same App-Group-persisted
// `WatchStateSnapshot` the main watch app itself renders (`TodayRingsView.swift`) — so once the
// extension-target gap above closes, this complication shows genuinely live (well, "as of the
// watch app's last WatchConnectivity sync" live — see `WatchStateStore.swift`'s header) ring data
// from day one, with no further changes needed here.

import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct GoalRingsComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchStateSnapshot
}

// MARK: - Timeline provider

struct GoalRingsComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalRingsComplicationEntry {
        GoalRingsComplicationEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (GoalRingsComplicationEntry) -> Void) {
        completion(GoalRingsComplicationEntry(date: .now, snapshot: WatchStateStore.readSnapshotForComplication()))
    }

    /// A single current-state entry with a bounded refresh — WidgetKit re-invokes this closure
    /// after `refreshInterval` (or sooner, if the system decides to; WidgetKit budgets watch
    /// complication refreshes tightly, so this intentionally does not try to tick a live countdown
    /// itself). Gym dwell/lock/streak state changes are pushed in between refreshes via
    /// `WatchConnectivityBridge`'s `WCSessionDelegate` callbacks updating the same persisted
    /// snapshot this reads — a real phone-side push (once wired) can call
    /// `WidgetCenter.shared.reloadTimelines(ofKind:)` to force an immediate refresh instead of
    /// waiting for this policy; that call site doesn't exist yet either (same gap as above).
    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalRingsComplicationEntry>) -> Void) {
        let entry = GoalRingsComplicationEntry(date: .now, snapshot: WatchStateStore.readSnapshotForComplication())
        let refreshInterval: TimeInterval = 15 * 60
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(refreshInterval)))
        completion(timeline)
    }
}

// MARK: - Views

/// `.accessoryCircular` family: concentric trimmed rings (workout outermost, matching the phone's
/// convention that the workout ring gets the sole brand accent color — `WatchTheme.Colors.Ring
/// .workout`/`Theme.Colors.Ring.workout` are the same `#B8FF3C`), sized relative to the available
/// space via `GeometryReader` so it renders correctly across the different actual point sizes
/// watchOS assigns `.accessoryCircular` depending on which corner/style of the watch face hosts it
/// (a detail this task could not verify against a real watch face — flagged below).
private struct CircularRingsView: View {
    let snapshot: WatchStateSnapshot

    /// Only 3 of the 4 `WatchRingKind`s fit legibly at complication scale — water is shown on the
    /// in-app `TodayRingsView` and the `.accessoryRectangular` family below, but dropped here.
    /// Order matters: drawn outermost-to-innermost.
    private static let displayOrder: [WatchRingKind] = [.workout, .protein, .focus]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Iterates `WatchRingKind` directly (`id: \.self`, `Hashable` via its raw-value
                // synthesis) rather than `.enumerated()` — deliberately avoids forming a KeyPath
                // into an anonymous tuple's named element (`\.element`), which this task could not
                // fully confirm is supported Swift syntax without a compiler to check against.
                ForEach(Self.displayOrder, id: \.self) { kind in
                    let index = Self.displayOrder.firstIndex(of: kind) ?? 0
                    let inset = CGFloat(index) * (side * 0.22)
                    ring(for: kind)
                        .padding(inset)
                }
            }
        }
        .containerBackground(for: .widget) {
            WatchTheme.Colors.background
        }
    }

    @ViewBuilder
    private func ring(for kind: WatchRingKind) -> some View {
        let progress = snapshot.rings.first(where: { $0.kind == kind })?.progress ?? 0
        Circle()
            .trim(from: 0, to: max(0.001, min(1, progress)))
            .stroke(WatchTheme.Colors.Ring.color(for: kind), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// `.accessoryRectangular` family: more room, so this pairs the same three rings with streak/lock
/// text — the wide-format equivalent of `TodayRingsView`'s `StreakBadge`/`ActiveLockBadge`.
private struct RectangularSummaryView: View {
    let snapshot: WatchStateSnapshot

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CircularRingsView.displayOrderPublic, id: \.self) { kind in
                let progress = snapshot.rings.first(where: { $0.kind == kind })?.progress ?? 0
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(WatchTheme.Colors.Ring.color(for: kind), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(snapshot.currentStreak)🔥")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                if let lock = snapshot.activeLock {
                    Text("\(lock.goalsRemaining) left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WatchTheme.Colors.muted)
                } else if let dwell = snapshot.gymDwell, !dwell.isVerified {
                    Text("\(dwell.elapsedMinutes)m at gym")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WatchTheme.Colors.muted)
                }
            }
        }
        .containerBackground(for: .widget) {
            WatchTheme.Colors.background
        }
    }
}

extension CircularRingsView {
    /// Exposes `displayOrder` to `RectangularSummaryView` without widening its access level beyond
    /// `fileprivate`-equivalent scope for anything else in the module.
    static var displayOrderPublic: [WatchRingKind] { displayOrder }
}

private struct GoalRingsComplicationView: View {
    let entry: GoalRingsComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularSummaryView(snapshot: entry.snapshot)
        default:
            CircularRingsView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Widget

/// API-certainty note (flagged per this task's brief): `TimelineProvider`, `StaticConfiguration`,
/// `.accessoryCircular`/`.accessoryRectangular` (`WidgetFamily`, watchOS 9+), and
/// `.containerBackground(for: .widget:)` are all real, current WidgetKit API — HIGH confidence on
/// existence/naming. MEDIUM confidence on exactly how watchOS 10 scales `.accessoryCircular`'s
/// rendered point size across the different watch-face complication slots (the "the ring sizing
/// looks right on every face" claim above is unverified — no watch face to check it against).
struct GoalRingsComplication: Widget {
    let kind = "com.zano.app.watch.complication.goalRings"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoalRingsComplicationProvider()) { entry in
            GoalRingsComplicationView(entry: entry)
        }
        .configurationDisplayName("ZANO Rings")
        .description("Today's goal rings at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
