// ContentView.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21 (Apple Watch). Three vertically paged screens (watchOS 10 style: the Digital
// Crown scrolls a page's content, then moves to the next page):
//   - Home: the buddy with its level and XP bar, today's goal rings, and the start actions
//     (focus, lock, emergency unlock).
//   - Boss: this week's Scroll Monster.
//   - Gym: dwell status (with the "verified" haptic) + "Track with HR" wrist workout.
//
// `WatchStateStore`/`WatchConnectivityBridge` are injected as `@Environment` from
// `ZANOWatchApp.swift` rather than referenced as `.shared` inside each view, so every child view
// (and its `#Preview`) gets them the same, ordinary SwiftUI way.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }

            NavigationStack {
                ScrollMonsterView()
            }

            NavigationStack {
                GymDwellView()
            }
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview {
    ContentView()
        .environment(WatchStateStore.shared)
        .environment(WatchConnectivityBridge.shared)
}
