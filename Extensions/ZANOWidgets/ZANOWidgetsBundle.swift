import WidgetKit
import SwiftUI

// Real widgets (streak, goal rings, +protein/+water/+creatine buttons, lock-screen widgets) land
// in Session 4 — docs/spec.md §6, §14. This placeholder exists so the target compiles and the
// extension point / App Group wiring can be verified end-to-end before real content is built.
@main
struct ZANOWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ZANOPlaceholderWidget()
    }
}

struct ZANOPlaceholderWidget: Widget {
    let kind: String = "ZANOPlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZANOPlaceholderProvider()) { entry in
            ZANOPlaceholderWidgetView(entry: entry)
        }
        .configurationDisplayName("ZANO")
        .description("Session 4 replaces this with real widgets — see docs/spec.md §6.")
    }
}

struct ZANOPlaceholderEntry: TimelineEntry {
    let date: Date
}

struct ZANOPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZANOPlaceholderEntry {
        ZANOPlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ZANOPlaceholderEntry) -> Void) {
        completion(ZANOPlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZANOPlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [ZANOPlaceholderEntry(date: .now)], policy: .never))
    }
}

struct ZANOPlaceholderWidgetView: View {
    let entry: ZANOPlaceholderEntry

    var body: some View {
        Text("ZANO")
            .font(.headline)
    }
}
