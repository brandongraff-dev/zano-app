// ContentView.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21 ("Apple Watch": complication with rings; start focus/lock from the wrist;
// workout detection more reliable with HR; haptic "verified" tap on gym dwell) and §11's
// architecture note that ZANOWatch is v3/speculative — still true at the target-wiring level (no
// WidgetKit extension target yet, no phone-side WatchConnectivity receiver yet; see
// `ComplicationPlaceholder.swift` and `WatchConnectivityBridge.swift`'s header comments), but no
// longer true of this screen: this is real, complete watch UI, not a Session-0 scaffold.
//
// Three tabs, matching the three pieces of spec §5.21 this task owns:
//   - Today: goal rings + streak (the in-app equivalent of the complication).
//   - Actions: start focus / start lock / emergency unlock from the wrist.
//   - Gym: dwell status + "Track with HR" wrist workout.
//
// `WatchStateStore`/`WatchConnectivityBridge` are injected as `@Environment` from
// `ZANOWatchApp.swift` rather than referenced as `.shared` inside each view, so every child view
// (and its `#Preview`) gets them the same, ordinary SwiftUI way — `.shared` is used only at the
// two composition roots (`ZANOWatchApp` and each file's own `#Preview`).

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayRingsView()
            }
            .tabItem { Label(Copy.watch.todayTab, systemImage: "circle.grid.2x2.fill") }

            NavigationStack {
                StartActionsView()
            }
            .tabItem { Label(Copy.watch.actionsTab, systemImage: "lock.fill") }

            NavigationStack {
                GymDwellView()
            }
            .tabItem { Label(Copy.watch.gymTab, systemImage: "figure.strengthtraining.traditional") }
        }
        // No explicit `.tabViewStyle(...)` — watchOS's own default `TabView` style is already a
        // vertically-paged, Digital-Crown/swipe-scrollable stack, which is exactly this screen's
        // intended feel. An explicit style name was deliberately left unset rather than guessed:
        // this task had no watchOS SDK to confirm which `TabViewStyle` case (if any, beyond the
        // cross-platform `.page`) watchOS additionally exposes for this — flagged in knownIssues.
    }
}

#Preview {
    ContentView()
        .environment(WatchStateStore.shared)
        .environment(WatchConnectivityBridge.shared)
}
