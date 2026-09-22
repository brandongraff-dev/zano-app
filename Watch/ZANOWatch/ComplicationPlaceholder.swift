// ComplicationPlaceholder.swift
// Watch/ZANOWatch
//
// PLACEHOLDER ONLY — this does not compile into a real, installable complication yet.
//
// docs/spec.md §5.21: "Complication with rings" — a watch-face complication showing today's ring
// progress at a glance. Real watchOS complications (watchOS 9+) are WidgetKit widgets, and
// WidgetKit widgets must live in their own WidgetKit extension target (`type: app-extension`,
// `NSExtensionPointIdentifier: com.apple.widgetkit-extension`, `platform: watchOS`) embedded in
// ZANOWatch — the same pattern ZANOWidgets already uses for ZANO on iOS (see project.yml's
// ZANOWidgets target and Extensions/ZANOWidgets/ZANOWidgetsBundle.swift). This task's scope was
// limited to appending the single ZANOWatch *app* target, so no such extension target exists yet
// and this type is never registered with a `WidgetBundle`/`@main` anywhere — it is unreferenced,
// inert source that only sketches the intended shape.
//
// TODO (future v3 session, project.yml owner): add a `ZANOWatchComplication` app-extension target
// (platform: watchOS, embedded in ZANOWatch) to project.yml, move this file there, wrap it in a
// real `@main WidgetBundle`, and replace the static entry with live data (same App Group read
// path as Extensions/ZANOWidgets/Support/ZANOWidgetDataStore, once that's reachable from watchOS
// too — see the "does not depend on Core" note on the ZANOWatch target in project.yml).
//
// Mirrors the TimelineProvider shape already used by
// Extensions/ZANOWidgets/HomeWidget/ZANOHomeWidget.swift for consistency with the rest of the
// codebase, minus any Core/live-data dependency.

import SwiftUI
import WidgetKit

struct ZANOComplicationPlaceholderEntry: TimelineEntry {
    let date: Date
}

struct ZANOComplicationPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZANOComplicationPlaceholderEntry {
        ZANOComplicationPlaceholderEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ZANOComplicationPlaceholderEntry) -> Void
    ) {
        completion(ZANOComplicationPlaceholderEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ZANOComplicationPlaceholderEntry>) -> Void
    ) {
        completion(Timeline(entries: [ZANOComplicationPlaceholderEntry(date: .now)], policy: .never))
    }
}

struct ZANOComplicationPlaceholderView: View {
    let entry: ZANOComplicationPlaceholderEntry

    var body: some View {
        Text("ZANO")
    }
}

/// Not wired to a `WidgetBundle`/`@main` anywhere — see the file header. Kept as a plain `Widget`
/// conformance so it type-checks in isolation once it does get moved into a real extension
/// target.
struct ZANOComplicationPlaceholder: Widget {
    let kind = "com.zano.app.watch.complication.placeholder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZANOComplicationPlaceholderProvider()) { entry in
            ZANOComplicationPlaceholderView(entry: entry)
        }
        .configurationDisplayName("ZANO")
        .description("Placeholder — see file header, not a real complication yet.")
    }
}
