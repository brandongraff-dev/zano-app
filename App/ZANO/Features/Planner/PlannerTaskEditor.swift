// PlannerTaskEditor.swift
// App / ZANO / Features / Planner
//
// Add or edit a task (session 27; docs/spec.md §5.30), in a plain grouped form like Reminders: a title and
// notes, then a Date switch that reveals a calendar, a Time switch under it, and "Remind me". Turning
// "Remind me" on asks for notification permission the first time (the system prompt, once).

import SwiftUI
import Core

struct PlannerTaskEditor: View {
    let task: PlannerTask?
    let day: Date
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var date: Date
    @State private var remind: Bool
    @State private var notificationsBlocked = false

    init(task: PlannerTask?, day: Date, onSave: @escaping () -> Void) {
        self.task = task
        self.day = day
        self.onSave = onSave
        let settings = PlannerStore.settings
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _hasDate = State(initialValue: task == nil ? true : task?.due != nil)
        _hasTime = State(initialValue: task?.hasTime ?? false)
        _date = State(initialValue: task?.due ?? Self.defaultDate(for: day))
        _remind = State(initialValue: task?.remind ?? settings.remindByDefault)
    }

    /// The selected day at the next whole hour, or 9:00 for another day.
    private static func defaultDate(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            let nextHour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
            if calendar.isDate(nextHour, inSameDayAs: now) { return nextHour }
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.planner.titlePlaceholder, text: $title)
                    TextField(Copy.planner.notesPlaceholder, text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Toggle(Copy.planner.dateToggle, isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                        Toggle(Copy.planner.timeToggle, isOn: $hasTime.animation())
                        if hasTime {
                            DatePicker(Copy.planner.timeToggle, selection: $date, displayedComponents: .hourAndMinute)
                        }
                    }
                }
                if hasDate {
                    Section {
                        Toggle(Copy.planner.remindToggle, isOn: $remind)
                            .onChange(of: remind) { _, on in
                                if on { Task { await askForNotifications() } }
                            }
                    } footer: {
                        if notificationsBlocked { Text(Copy.planner.remindFooterOff) }
                    }
                }
                if let task {
                    Section {
                        Button(Copy.planner.delete, role: .destructive) {
                            PlannerStore.delete(id: task.id)
                            onSave()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? Copy.planner.newTask : Copy.planner.editTask)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.planner.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.planner.save) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func save() {
        var saved = task ?? PlannerTask(title: "")
        saved.title = title.trimmingCharacters(in: .whitespaces)
        saved.notes = notes
        saved.due = hasDate ? date : nil
        saved.hasTime = hasDate && hasTime
        saved.remind = hasDate && remind
        PlannerStore.upsert(saved)
        onSave()
        dismiss()
    }

    private func askForNotifications() async {
        let status = await NotificationPermission.requestIfUndetermined()
        notificationsBlocked = status == .denied
    }
}
