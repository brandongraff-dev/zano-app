// PlannerEventDetailView.swift
// App / ZANO / Features / Planner
//
// Someone else's family-calendar event (session 46; docs/spec.md §5.30 / §5.31), read only: the title, when,
// the notes, "Added by Sam" and who can see it. Only the person who added an event can change it, so there is
// nothing to edit here. `PlannerEventOwnership` holds the small owner/visibility wording and glyphs the agenda
// rows share with this sheet. Wording: `Copy.planner`.

import SwiftUI
import Core

struct PlannerEventDetailView: View {
    let event: PlannerEvent
    let members: [HouseholdMember]
    let me: UUID?
    let householdName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.title.isEmpty ? Copy.planner.untitledEvent : event.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(PlannerEventOwnership.whenLine(event))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if !event.notes.isEmpty {
                    Section(Copy.planner.eventNotesLabel) {
                        Text(event.notes)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                    }
                }
                Section {
                    if let added = PlannerEventOwnership.creatorLine(event.origin, members: members, me: me) {
                        Label(added, systemImage: "person.fill")
                    }
                    LabeledContent(
                        Copy.planner.visibilityLabel,
                        value: PlannerEventOwnership.visibilityLine(event.origin, members: members, me: me, householdName: householdName)
                    )
                } footer: {
                    Text(Copy.planner.readOnlyNote)
                }
            }
            .navigationTitle(Copy.planner.eventDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.planner.done) { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// The owner/visibility wording and glyphs for one Planner event (session 46). Device calendar events have none.
enum PlannerEventOwnership {
    /// Lock for "Only me", people for anything shared, nothing for the iPhone's calendars.
    static func glyph(_ origin: PlannerEventOrigin) -> String? {
        switch origin {
        case .device: nil
        case .onlyMe: "lock.fill"
        case .household: "person.2.fill"
        }
    }

    /// Whether this person can open the editor for it: their private events and the shared events they added.
    static func isEditable(_ origin: PlannerEventOrigin, me: UUID?) -> Bool {
        switch origin {
        case .device: false
        case .onlyMe: true
        case .household(_, let createdBy, _, _): me != nil && createdBy == me
        }
    }

    /// "Added by Sam" / "Added by you" for a shared event; nil otherwise.
    static func creatorLine(_ origin: PlannerEventOrigin, members: [HouseholdMember], me: UUID?) -> String? {
        guard case .household(_, let createdBy, _, _) = origin else { return nil }
        if let me, createdBy == me { return Copy.planner.addedByYou }
        guard let name = HouseholdBoard.name(for: createdBy, members: members, me: me) else { return nil }
        return Copy.planner.addedBy(name)
    }

    /// "Only you", "Everyone in Home", or "You, Sam and Alex".
    static func visibilityLine(_ origin: PlannerEventOrigin, members: [HouseholdMember], me: UUID?, householdName: String) -> String {
        switch origin {
        case .device:
            return ""
        case .onlyMe:
            return Copy.planner.onlyMeCalendarTitle
        case .household(_, _, .household, _):
            return Copy.planner.everyoneIn(householdName)
        case .household(_, let createdBy, .members, let audience):
            return Copy.planner.visibleTo(otherNames(createdBy: createdBy, audience: audience, members: members, me: me))
        }
    }

    /// The line under an event's title on the agenda: the calendar for an iPhone event, who can see it for
    /// mine, who added it for someone else's.
    static func subtitle(_ event: PlannerEvent, members: [HouseholdMember], me: UUID?) -> String {
        switch event.origin {
        case .device:
            return event.calendarTitle
        case .onlyMe:
            return Copy.planner.onlyMeCalendarTitle
        case .household(_, let createdBy, _, _):
            if let me, createdBy == me {
                return visibilityLine(event.origin, members: members, me: me, householdName: event.calendarTitle)
            }
            return creatorLine(event.origin, members: members, me: me) ?? event.calendarTitle
        }
    }

    /// What VoiceOver adds after the title: who can see it.
    static func accessibilityValue(_ origin: PlannerEventOrigin, members: [HouseholdMember], me: UUID?) -> String {
        switch origin {
        case .device: return ""
        case .onlyMe: return Copy.planner.a11yOnlyMe
        case .household(_, _, .household, _): return Copy.planner.a11yEveryone
        case .household(_, let createdBy, .members, let audience):
            let names = otherNames(createdBy: createdBy, audience: audience, members: members, me: me)
            return names.isEmpty ? Copy.planner.a11yOnlyMe : Copy.planner.a11yWith(names)
        }
    }

    /// "Fri, Oct 9 · 6:00 PM – 7:30 PM" or "Fri, Oct 9 · All-day".
    static func whenLine(_ event: PlannerEvent) -> String {
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if event.isAllDay { return day + " · " + Copy.planner.allDay }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return day + " · " + start + " – " + end
    }

    /// Everyone besides me who can see a members-only event: its creator (if not me) and its audience.
    private static func otherNames(createdBy: UUID?, audience: [UUID], members: [HouseholdMember], me: UUID?) -> [String] {
        var ids: [UUID] = []
        if let createdBy, createdBy != me { ids.append(createdBy) }
        ids += audience.filter { $0 != me && $0 != createdBy }
        return ids.compactMap { id in members.first { $0.userId == id }?.displayName }
    }
}
