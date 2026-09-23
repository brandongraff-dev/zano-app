// TodayRingsView.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21: the at-a-glance half of "Complication with rings" — this is the full-screen,
// in-app equivalent shown when someone actually opens the watch app (the complication itself,
// `ComplicationPlaceholder.swift`, renders a smaller version of the same `WatchStateStore`
// snapshot from outside this view hierarchy entirely, in a future WidgetKit extension process).

import Foundation
import SwiftUI

struct TodayRingsView: View {
    @Environment(WatchStateStore.self) private var store
    @Environment(WatchConnectivityBridge.self) private var connectivity

    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.md) {
                if !connectivity.isReachable {
                    ConnectivityBanner()
                }

                ringsGrid

                StreakBadge(streak: store.snapshot.currentStreak)

                if let lock = store.snapshot.activeLock {
                    ActiveLockBadge(lock: lock)
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .padding(.vertical, WatchTheme.Spacing.sm)
        }
        .background(WatchTheme.Colors.background)
        .navigationTitle(Copy.watch.todayTitle)
    }

    private var ringsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: WatchTheme.Spacing.sm
        ) {
            ForEach(store.snapshot.rings) { ring in
                VStack(spacing: WatchTheme.Spacing.xxs) {
                    WatchGoalRing(
                        progress: ring.progress,
                        color: WatchTheme.Colors.Ring.color(for: ring.kind),
                        size: .medium
                    )
                    Text(Copy.watch.ringTitle(for: ring.kind))
                        .font(WatchTheme.Typography.captionEmphasized)
                        .foregroundStyle(WatchTheme.Colors.text)
                    if let valueText = ring.valueText {
                        Text(valueText)
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(WatchTheme.Colors.muted)
                    }
                }
            }
        }
    }
}

private struct ConnectivityBanner: View {
    var body: some View {
        Text(Copy.watch.noConnectionBanner)
            .font(WatchTheme.Typography.caption)
            .foregroundStyle(WatchTheme.Colors.warning)
            .multilineTextAlignment(.center)
            .padding(WatchTheme.Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(WatchTheme.Colors.surface, in: .rect(cornerRadius: 10))
    }
}

private struct StreakBadge: View {
    let streak: Int

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.xxs) {
            Text("🔥")
            Text("\(streak)")
                .font(WatchTheme.Typography.numeralSmall())
                .foregroundStyle(WatchTheme.Colors.text)
            Text(Copy.watch.streakLabel)
                .font(WatchTheme.Typography.caption)
                .foregroundStyle(WatchTheme.Colors.muted)
        }
        .padding(.horizontal, WatchTheme.Spacing.sm)
        .padding(.vertical, WatchTheme.Spacing.xxs)
        .background(WatchTheme.Colors.surface, in: .capsule)
    }
}

private struct ActiveLockBadge: View {
    let lock: WatchActiveLockSnapshot

    var body: some View {
        Text(String(format: Copy.watch.activeLockStatusFormat, lock.goalsRemaining))
            .font(WatchTheme.Typography.caption)
            .foregroundStyle(WatchTheme.Colors.danger)
            .padding(.horizontal, WatchTheme.Spacing.sm)
            .padding(.vertical, WatchTheme.Spacing.xxs)
            .background(WatchTheme.Colors.surface2, in: .capsule)
    }
}

#Preview {
    NavigationStack {
        TodayRingsView()
    }
    .environment(WatchStateStore.shared)
    .environment(WatchConnectivityBridge.shared)
}
