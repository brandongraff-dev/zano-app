// HouseholdTaskEditor.swift
// App / ZANO / Features / Household
//
// "New task" for the shared list (session 28; docs/spec.md §5.31): a title, notes, an optional date and time,
// and who it is for (nobody yet, you, or anyone in the household). A plain grouped form, like Reminders.

import SwiftUI
import Core

struct HouseholdTaskEditor: View {
    let householdID: UUID
    let members: [HouseholdMember]
    let me: UUID?
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDate = false
    @State private var date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var assignee: UUID?
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.household.titlePlaceholder, text: $title)
                    TextField(Copy.household.notesPlaceholder, text: $notes, axis: .vertical).lineLimit(1...4)
                }
                Section {
                    Toggle(Copy.household.dateToggle, isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("", selection: $date).datePickerStyle(.graphical).labelsHidden()
                    }
                }
                Section {
                    Picker(Copy.household.assignLabel, selection: $assignee) {
                        Text(Copy.household.nobody).tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.userId == me ? Copy.household.you : member.displayName).tag(UUID?.some(member.userId))
                        }
                    }
                } footer: {
                    if let message { Text(message) }
                }
            }
            .navigationTitle(Copy.household.newTask)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Copy.household.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.household.add) { Task { await add() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(.dark)
    }

    private func add() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await HouseholdClient.shared.createTask(
                householdID: householdID, title: title.trimmingCharacters(in: .whitespaces),
                notes: notes, dueAt: hasDate ? date : nil, assignee: assignee
            )
            onAdded()
            dismiss()
        } catch {
            message = Copy.household.error(error)
        }
    }
}
