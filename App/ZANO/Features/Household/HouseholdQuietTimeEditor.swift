// HouseholdQuietTimeEditor.swift
// App / ZANO / Features / Household
//
// Add or edit a household screen-free time (session 44; docs/spec.md §5.31): a name, a start and end time (an
// end earlier than the start runs past midnight, like "Bedtime 10 pm – 7 am") and the days it starts on. Saving
// shares the window with the household; it locks nobody by itself, each person joins on their own phone.
// A plain grouped form, like the task editor.

import SwiftUI
import Core

struct HouseholdQuietTimeEditor: View {
    let householdID: UUID
    let existing: HouseholdQuietTime?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = Self.time(18 * 60)
    @State private var end = Self.time(19 * 60)
    @State private var days: Set<Int> = LockSchedule.allWeekdays
    @State private var message: String?
    @State private var isSaving = false

    private var startMinute: Int { LockSchedule.minuteOfDayForUI(start) }
    private var endMinute: Int { LockSchedule.minuteOfDayForUI(end) }

    private var draft: HouseholdQuietTime {
        HouseholdQuietTime(
            id: existing?.id ?? UUID(), householdId: householdID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            startMinute: startMinute, endMinute: endMinute, weekdays: days.sorted()
        )
    }

    /// Days in the calendar's own week order (Monday first where that's the custom).
    private var dayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.household.quietNamePlaceholder, text: $name)
                }
                Section {
                    DatePicker(Copy.household.quietStarts, selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker(Copy.household.quietEnds, selection: $end, displayedComponents: .hourAndMinute)
                } footer: {
                    if endMinute < startMinute { Text(Copy.household.quietOvernightNote) }
                }
                Section {
                    HStack(spacing: Theme.Spacing.xxs) {
                        ForEach(dayOrder, id: \.self) { day in
                            dayButton(day)
                        }
                    }
                } header: {
                    Text(Copy.household.quietDays)
                } footer: {
                    if let message { Text(message) }
                }
                if let existing {
                    Section {
                        Button(Copy.household.quietDelete, role: .destructive) { Task { await delete(existing) } }
                    } footer: {
                        Text(Copy.household.quietDeleteNote)
                    }
                }
            }
            .navigationTitle(existing == nil ? Copy.household.quietNew : Copy.household.quietEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Copy.household.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.household.quietSave) { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: load)
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(.dark)
    }

    private func dayButton(_ day: Int) -> some View {
        let on = days.contains(day)
        return Button {
            if on { days.remove(day) } else { days.insert(day) }
        } label: {
            Text(Copy.household.dayLetter(day))
                .font(Theme.Typography.captionEmphasized)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                .foregroundStyle(on ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                .background(Circle().fill(on ? Theme.Colors.accent : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.household.dayName(day))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() {
        guard let existing else { return }
        name = existing.name
        start = Self.time(existing.startMinute)
        end = Self.time(existing.endMinute)
        days = existing.weekdaySet
    }

    private func save() async {
        let window = draft
        if let problem = window.validate() {
            message = Copy.household.quietValidation(problem)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let existing {
                try await HouseholdClient.shared.updateQuietTime(
                    id: existing.id, name: window.name, startMinute: window.startMinute,
                    endMinute: window.endMinute, weekdays: window.weekdays
                )
            } else {
                _ = try await HouseholdClient.shared.createQuietTime(
                    householdID: householdID, name: window.name, startMinute: window.startMinute,
                    endMinute: window.endMinute, weekdays: window.weekdays
                )
            }
            onSaved()
            dismiss()
        } catch {
            message = Copy.household.error(error)
        }
    }

    private func delete(_ window: HouseholdQuietTime) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await HouseholdClient.shared.deleteQuietTime(id: window.id)
            onSaved()
            dismiss()
        } catch {
            message = Copy.household.error(error)
        }
    }

    private static func time(_ minute: Int) -> Date {
        let day = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
    }
}
