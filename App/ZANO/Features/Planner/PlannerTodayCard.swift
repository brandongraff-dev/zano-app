// PlannerTodayCard.swift
// App / ZANO / Features / Planner
//
// "Due today" on Today (session 27; docs/spec.md §5.30): up to three open tasks due today or earlier, each
// with a circle to tick off, and "See all" to open the calendar. Draws nothing when there is nothing due, so
// a person who never adds a task never sees it.

import SwiftUI
import Core

struct PlannerTodayCard: View {
    /// Bumped by Today when the calendar sheet closes, so the card re-reads the list.
    let reloadToken: Int
    let onOpen: () -> Void

    @State private var tasks: [PlannerTask] = PlannerStore.tasks

    private var due: [PlannerTask] { PlannerAgenda.dueNow(tasks: tasks) }

    var body: some View {
        Group {
            if !due.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(Copy.planner.todayCardTitle)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button(Copy.planner.todayCardOpen, action: onOpen)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(minHeight: Theme.Metrics.minTapTarget)
                    }
                    ForEach(due.prefix(3)) { task in
                        HStack(spacing: Theme.Spacing.sm) {
                            Button {
                                PlannerStore.toggleDone(id: task.id)
                                tasks = PlannerStore.tasks
                                Task { await PlannerReminders.refresh() }
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.Colors.muted)
                                    .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(task.title)
                            Text(task.title)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.text)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            if task.hasTime, let time = task.due {
                                Text(time.formatted(date: .omitted, time: .shortened))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.muted)
                            }
                        }
                    }
                    if due.count > 3 {
                        Text(Copy.planner.dueCount(due.count))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                .padding(Theme.Spacing.md)
                .zanoCard(radius: Theme.Radius.medium)
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear { tasks = PlannerStore.tasks }
        .onChange(of: reloadToken) { _, _ in tasks = PlannerStore.tasks }
    }
}
