// PlannerZanoEventEditor.swift
// App / ZANO / Features / Planner
//
// "New event" with "Who can see this" (session 46; docs/spec.md §5.30 / §5.31), in a plain grouped form like the
// Calendar app's: a title and notes, All-day, Starts and Ends, then who it's for.
//   - Only me: saved on this iPhone (`PlannerStore.privateEvents`), never uploaded. Works offline, signed out,
//     and without calendar access. Always offered.
//   - Everyone in <household> / Choose people: saved to the family calendar (`HouseholdClient`), shown only while
//     Household is live. Row-level security on the server decides who can read it.
// Also edits and deletes this person's own ZANO events; changing "Only me" to shared (or back) moves the event.
// "Add to my iPhone calendar instead" hands over to Apple's editor (`PlannerEventEditor`) for repeats and invitees.
// Wording: `Copy.planner` / `Copy.household`.

import SwiftUI
import Core

struct PlannerZanoEventEditor: View {
    enum Existing {
        case onlyMe(PlannerPrivateEvent)
        case household(HouseholdEvent)
    }

    let existing: Existing?
    let day: Date
    /// `nil` when Household isn't live or the person isn't in one: only "Only me" is offered.
    let household: Household?
    let members: [HouseholdMember]
    let me: UUID?
    let onSaved: () -> Void
    /// New events only: close this sheet and open Apple's event editor instead.
    let onUseAppleEditor: (() -> Void)?

    private enum Choice: Hashable { case onlyMe, household, people }

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var choice: Choice
    @State private var picked: Set<UUID>
    @State private var message: String?
    @State private var isSaving = false

    init(
        existing: Existing?, day: Date, household: Household?, members: [HouseholdMember], me: UUID?,
        onSaved: @escaping () -> Void, onUseAppleEditor: (() -> Void)? = nil
    ) {
        self.existing = existing
        self.day = day
        self.household = household
        self.members = members
        self.me = me
        self.onSaved = onSaved
        self.onUseAppleEditor = onUseAppleEditor
        let defaultStart = Self.defaultStart(for: day)
        switch existing {
        case .onlyMe(let event):
            _title = State(initialValue: event.title)
            _notes = State(initialValue: event.notes)
            _allDay = State(initialValue: event.isAllDay)
            _start = State(initialValue: event.start)
            _end = State(initialValue: event.end)
            _choice = State(initialValue: .onlyMe)
            _picked = State(initialValue: [])
        case .household(let event):
            _title = State(initialValue: event.title)
            _notes = State(initialValue: event.notes)
            _allDay = State(initialValue: event.allDay)
            _start = State(initialValue: event.startsAt)
            _end = State(initialValue: event.endsAt)
            _choice = State(initialValue: event.visibility == .household ? .household : .people)
            _picked = State(initialValue: Set(event.audience))
        case nil:
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _allDay = State(initialValue: false)
            _start = State(initialValue: defaultStart)
            _end = State(initialValue: defaultStart.addingTimeInterval(3_600))
            _choice = State(initialValue: .onlyMe)
            _picked = State(initialValue: [])
        }
    }

    /// The chosen day at the next whole hour (today) or 9:00 (another day), like `PlannerEventEditor`.
    private static func defaultStart(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now), let next = calendar.dateInterval(of: .hour, for: now)?.end,
           calendar.isDate(next, inSameDayAs: now) {
            return next
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    /// Everyone in the household but me, for "Choose people".
    private var others: [HouseholdMember] { members.filter { $0.userId != me } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.planner.titlePlaceholder, text: $title)
                    TextField(Copy.planner.notesPlaceholder, text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Toggle(Copy.planner.allDayToggle, isOn: $allDay.animation())
                    DatePicker(Copy.planner.startsLabel, selection: $start, displayedComponents: allDay ? DatePickerComponents.date : [.date, .hourAndMinute])
                        .id(allDay ? "start-day" : "start-time")
                        .onChange(of: start) { old, new in
                            // Keep the length when the start moves, like the Calendar app.
                            end = end.addingTimeInterval(new.timeIntervalSince(old))
                        }
                    DatePicker(Copy.planner.endsLabel, selection: $end, in: start..., displayedComponents: allDay ? DatePickerComponents.date : [.date, .hourAndMinute])
                        .id(allDay ? "end-day" : "end-time")
                }
                whoCanSeeSection
                if existing == nil, onUseAppleEditor != nil {
                    Section {
                        Button(Copy.planner.useAppleEditor) {
                            dismiss()
                            onUseAppleEditor?()
                        }
                    } footer: {
                        Text(Copy.planner.appleEditorNote)
                    }
                }
                if existing != nil {
                    Section {
                        Button(Copy.planner.deleteEvent, role: .destructive) { Task { await delete() } }
                            .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(existing == nil ? Copy.planner.newEvent : Copy.planner.editEvent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.planner.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.planner.save) { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    // MARK: Who can see this

    @ViewBuilder
    private var whoCanSeeSection: some View {
        Section {
            choiceRow(.onlyMe, title: Copy.planner.onlyMe, systemImage: "lock.fill")
            if let household {
                choiceRow(.household, title: Copy.planner.everyoneIn(household.name), systemImage: "person.2.fill")
                if !others.isEmpty {
                    choiceRow(.people, title: Copy.planner.choosePeople, systemImage: "person.crop.circle.badge.checkmark")
                    if choice == .people { memberChips }
                }
            }
        } header: {
            Text(Copy.planner.whoCanSee)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(footerText)
                if let message {
                    Text(message).foregroundStyle(Theme.Colors.danger)
                }
            }
        }
    }

    private var footerText: String {
        switch choice {
        case .onlyMe: Copy.planner.onlyMeNote
        case .household: Copy.planner.everyoneNote(household?.name ?? "")
        case .people: Copy.planner.choosePeopleNote
        }
    }

    private func choiceRow(_ value: Choice, title: String, systemImage: String) -> some View {
        Button {
            choice = value
            message = nil
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title).foregroundStyle(Theme.Colors.text)
                Spacer(minLength: 0)
                if choice == value {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.icon(.small, weight: .bold))
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }

    /// One chip per other member: their chosen name. Tap to add or remove.
    private var memberChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(others) { member in
                    let isOn = picked.contains(member.userId)
                    Button {
                        if isOn { picked.remove(member.userId) } else { picked.insert(member.userId) }
                        message = nil
                    } label: {
                        Text(member.displayName)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.text)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .frame(minHeight: Theme.Metrics.minTapTarget)
                            .background(Capsule(style: .continuous).fill(isOn ? Theme.Colors.interactiveWash : Color.clear))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(isOn ? Theme.Colors.accent : Theme.Colors.hairline, lineWidth: Theme.Metrics.selectedStroke)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
    }

    // MARK: Save / delete

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let times = PlannerEventTimes.normalized(start: start, end: end, allDay: allDay)
        if let error = PlannerEventTimes.validate(title: trimmed, start: times.start, end: times.end) {
            message = Self.text(for: error)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            switch choice {
            case .onlyMe:
                // Shared → only me: take it off the family calendar first, so a failure leaves no copy behind.
                if case .household(let old) = existing {
                    try await HouseholdClient.shared.deleteEvent(id: old.id)
                    await HouseholdEventStore.refresh()
                }
                var event: PlannerPrivateEvent
                if case .onlyMe(let old) = existing { event = old } else {
                    event = PlannerPrivateEvent(title: trimmed, start: times.start, end: times.end)
                }
                event.title = trimmed
                event.notes = notes
                event.start = times.start
                event.end = times.end
                event.isAllDay = allDay
                PlannerStore.upsertPrivateEvent(event)
            case .household, .people:
                guard let household else { return }
                let visibility: HouseholdEventVisibility = choice == .household ? .household : .members
                var audience: [UUID] = []
                if visibility == .members {
                    switch HouseholdEventRules.normalizedAudience(Array(picked), creator: me, members: members) {
                    case .success(let ids): audience = ids
                    case .failure(.notAMember):
                        message = Copy.household.eventsBadAudience
                        return
                    case .failure:
                        message = Copy.planner.pickSomeone
                        return
                    }
                }
                if case .household(let old) = existing {
                    try await HouseholdClient.shared.updateEvent(
                        id: old.id, title: trimmed, notes: notes, start: times.start, end: times.end, allDay: allDay,
                        visibility: visibility, audience: audience
                    )
                } else {
                    try await HouseholdClient.shared.createEvent(
                        householdID: household.id, title: trimmed, notes: notes, start: times.start, end: times.end,
                        allDay: allDay, visibility: visibility, audience: audience
                    )
                    // Only me → shared: the server copy exists now, so drop the private one.
                    if case .onlyMe(let old) = existing { PlannerStore.deletePrivateEvent(id: old.id) }
                }
                await HouseholdEventStore.refresh()
            }
            await PlannerReminders.refresh()
            onSaved()
            dismiss()
        } catch {
            message = Copy.household.error(error)
        }
    }

    private func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch existing {
            case .onlyMe(let event):
                PlannerStore.deletePrivateEvent(id: event.id)
            case .household(let event):
                try await HouseholdClient.shared.deleteEvent(id: event.id)
                await HouseholdEventStore.refresh()
            case nil:
                return
            }
            await PlannerReminders.refresh()
            onSaved()
            dismiss()
        } catch {
            message = Copy.household.error(error)
        }
    }

    private static func text(for error: PlannerEventTimes.ValidationError) -> String {
        switch error {
        case .emptyTitle: Copy.planner.titleMissing
        case .titleTooLong: Copy.planner.titleTooLong
        case .endsBeforeStart: Copy.planner.endsBeforeStart
        }
    }
}
