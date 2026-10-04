// HomeView.swift
// Watch/ZANOWatch
//
// The first page (session 13b): the buddy with its level, today's goal rings, then the start
// actions (focus, lock, emergency unlock). One scrolling page; the Digital Crown scrolls it and
// keeps going into the next page (the weekly boss) once it reaches the bottom.

import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.md) {
                BuddyHeroView()
                TodayRingsView()
                StartActionsView()
            }
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .padding(.vertical, WatchTheme.Spacing.sm)
        }
        .background(WatchTheme.Colors.background)
        .navigationTitle(Copy.watch.todayTitle)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(WatchStateStore.shared)
    .environment(WatchConnectivityBridge.shared)
}
