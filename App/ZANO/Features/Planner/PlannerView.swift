// PlannerView.swift
// App / ZANO / Features / Planner
//
// The calendar (session 27; docs/spec.md §5.30), laid out like the iOS Calendar: the month and year at the
// top with the days of the week under it, a month grid where today wears the accent colour, the selected day
// a filled circle and a small dot marks a day with an event or an open task, and the chosen day's agenda
// below with a time column and a coloured bar per item. Swipe the grid, or use the arrows, to change month.
// Tasks live here too (ZANO's own, on the device); events are read from the iPhone's calendars.
// All wording is `Copy.planner`.
//
// Session 46: the grid and agenda merge three sources (`PlannerAgenda.merge`): the iPhone's calendars, private
// "Only me" ZANO events (on this device), and the family calendar (household events, only while Household is
// live). ZANO events carry a small mark (a lock for only me, people for shared) and open the editor when they
// are this person's own, or a read-only sheet ("Added by Sam") when they aren't. A Calendars menu hides the family
// calendar or the iPhone's calendars.

import SwiftUI
import Core

struct PlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let calendar = Calendar.current

    @State private var month: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selected: Date = Calendar.current.startOfDay(for: .now)
    @State private var tasks: [PlannerTask] = PlannerStore.tasks
    /// The iPhone's own calendars (EventKit), for the visible month.
    @State private var deviceEvents: [PlannerEvent] = []
    @State private var hasAccess = PlannerCalendarSource.hasAccess
    @State private var isDenied = PlannerCalendarSource.isDenied
    @State private var taskTarget: TaskTarget?
    @State private var showEventEditor = false
    // Session 46: private ZANO events and the family calendar (App Group caches, refreshed on open).
    @State private var privateEvents: [PlannerPrivateEvent] = PlannerStore.privateEvents
    @State private var householdEvents: [HouseholdEvent] = HouseholdEventStore.events
    @State private var household: Household? = HouseholdEventStore.household
    @State private var members: [HouseholdMember] = HouseholdEventStore.members
    @State private var me: UUID? = HouseholdEventStore.me
    @State private var filter = PlannerStore.calendarFilter
    @State private var eventTarget: EventTarget?
    @State private var detailEvent: PlannerEvent?
    /// Set by the ZANO editor's "Add to my iPhone calendar instead"; Apple's editor opens once that sheet is gone.
    @State private var openAppleEditorAfterDismiss = false

    private struct TaskTarget: Identifiable {
        let id = UUID()
        var task: PlannerTask?
        var day: Date
    }

    private struct EventTarget: Identifiable {
        let id = UUID()
        var existing: PlannerZanoEventEditor.Existing?
        var day: Date
    }

    /// The family calendar shows only while Household is live and this person is in a household.
    private var isFamilyLive: Bool { HouseholdAvailability.isLive && household != nil }

    private var events: [PlannerEvent] {
        PlannerAgenda.merge(
            device: deviceEvents, privateEvents: privateEvents, household: householdEvents, me: me,
            householdName: household?.name ?? "", filter: filter, includeHousehold: isFamilyLive
        )
    }

    private var weeks: [[Date]] { PlannerAgenda.weeks(for: month, calendar: calendar) }

    private var agenda: PlannerDayAgenda {
        PlannerAgenda.agenda(for: selected, events: events, tasks: tasks, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                weekdayRow
                monthGrid
                Divider().padding(.top, Theme.Spacing.xs)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        dayHeader
                        if !hasAccess { accessCard }
                        agendaContent
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                }
            }
            .zanoBackdrop()
            .navigationTitle(Copy.planner.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.planner.done) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { taskTarget = TaskTarget(task: nil, day: selected) } label: {
                            Label(Copy.planner.newTask, systemImage: "checkmark.circle")
                        }
                        Button { eventTarget = EventTarget(existing: nil, day: selected) } label: {
                            Label(Copy.planner.newEvent, systemImage: "calendar.badge.plus")
                        }
                        ShareLink(item: PlannerShare.text(for: agenda, day: selected)) {
                            Label(Copy.planner.shareDayButton, systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Copy.planner.addMenuLabel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isFamilyLive || hasAccess {
                        Menu {
                            if isFamilyLive {
                                Toggle(Copy.planner.filterFamily, isOn: filterBinding(\.showsFamily))
                            }
                            if hasAccess {
                                Toggle(Copy.planner.filterDevice, isOn: filterBinding(\.showsDeviceCalendars))
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(Copy.planner.filterMenuLabel)
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .task(id: month) { loadEvents() }
        .task { await refreshFamilyCalendar() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshAccess()
                loadEvents()
                Task { await refreshFamilyCalendar() }
            }
        }
        .sheet(item: $taskTarget) { target in
            PlannerTaskEditor(task: target.task, day: target.day) { reloadTasks() }
        }
        .sheet(item: $eventTarget, onDismiss: {
            guard openAppleEditorAfterDismiss else { return }
            openAppleEditorAfterDismiss = false
            Task { await startNewEvent() }
        }) { target in
            PlannerZanoEventEditor(
                existing: target.existing, day: target.day, household: isFamilyLive ? household : nil,
                members: members, me: me,
                onSaved: { reloadZanoEvents() },
                onUseAppleEditor: target.existing == nil ? { openAppleEditorAfterDismiss = true } : nil
            )
        }
        .sheet(item: $detailEvent) { event in
            PlannerEventDetailView(event: event, members: members, me: me, householdName: household?.name ?? "")
        }
        .sheet(isPresented: $showEventEditor) {
            PlannerEventEditor(day: selected) {
                showEventEditor = false
                loadEvents()
                Task { await PlannerReminders.refresh() }
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: selected)
        .preferredColorScheme(.dark)
    }

    // MARK: Month header and grid

    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(month.formatted(.dateTime.month(.wide))).foregroundStyle(Theme.Colors.text)
                + Text(" " + month.formatted(.dateTime.year())).foregroundStyle(Theme.Colors.accent))
                .font(Theme.Typography.title)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(Copy.planner.todayButton) { goToToday() }
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
                .frame(minHeight: Theme.Metrics.minTapTarget)
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .accessibilityLabel(Copy.planner.previousMonth)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .accessibilityLabel(Copy.planner.nextMonth)
        }
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(PlannerAgenda.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        // Merged once per render, not once per day cell.
        let all = events
        let marks = PlannerAgenda.markers(for: weeks.flatMap { $0 }, events: all, tasks: tasks, calendar: calendar)
        return VStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in dayCell(day, events: all, markers: marks) }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shiftMonth(value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private func dayCell(_ day: Date, events: [PlannerEvent], markers: [Date: PlannerDayMarkers]) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let mark = markers[calendar.startOfDay(for: day)] ?? PlannerDayMarkers()
        return Button {
            select(day)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(.body, design: .rounded, weight: isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? Theme.Colors.onFill
                            : isToday ? Theme.Colors.accent
                            : inMonth ? Theme.Colors.text : Theme.Colors.muted
                    )
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isSelected ? (isToday ? Theme.Colors.accent : Theme.Colors.text) : .clear))
                // Only the dots a day has, so one dot sits exactly under the number (never a hidden twin
                // beside it pushing it off-centre). The row keeps its height so the weeks don't jump.
                HStack(spacing: 3) {
                    if mark.hasEvents { Circle().fill(Theme.Colors.muted).frame(width: 5, height: 5) }
                    if mark.hasOpenTasks { Circle().fill(Theme.Colors.accent).frame(width: 5, height: 5) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.planner.accessibilityDay(
            day,
            events: PlannerAgenda.events(on: day, in: events, calendar: calendar).count,
            tasks: tasks.filter { !$0.isDone && ($0.due.map { calendar.isDate($0, inSameDayAs: day) } ?? false) }.count
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Agenda

    private var dayHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(selected.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CalSprite(calPose, size: 40)
        }
    }

    /// Cal's mood for the chosen day: worried with overdue work, asleep with nothing planned, delighted
    /// when every task is ticked, calm otherwise.
    private var calPose: CalPose {
        let agenda = self.agenda
        if !agenda.overdue.isEmpty { return .alarm }
        if agenda.isEmpty { return .sleepy }
        let open = agenda.anytimeTasks.filter { !$0.isDone }.count
            + agenda.timed.filter { item in
                if case .task(let task) = item { return !task.isDone }
                return false
            }.count
        let hasTasks = !agenda.anytimeTasks.isEmpty || agenda.timed.contains { item in
            if case .task = item { return true }
            return false
        }
        return hasTasks && open == 0 ? .happy : .idle
    }

    @ViewBuilder
    private var agendaContent: some View {
        let agenda = self.agenda
        if agenda.isEmpty {
            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.planner.nothingPlanned)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(Copy.planner.nothingPlannedDetail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        } else {
            if !agenda.overdue.isEmpty {
                section(Copy.planner.overdue, tint: Theme.Colors.danger) {
                    ForEach(agenda.overdue) { taskRow($0, showsDate: true) }
                }
            }
            if !agenda.allDay.isEmpty {
                section(Copy.planner.allDay) {
                    ForEach(agenda.allDay) { event in
                        tappable(event) {
                            HStack(spacing: Theme.Spacing.sm) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(rgb: event.colorRGB)).frame(width: 4, height: 24)
                                Text(event.title.isEmpty ? Copy.planner.untitledEvent : event.title)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.text)
                                Spacer(minLength: 0)
                                eventMark(event)
                            }
                            .frame(minHeight: event.origin.isZanoEvent ? Theme.Metrics.minTapTarget : nil)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(PlannerEventOwnership.accessibilityValue(event.origin, members: members, me: me))
                    }
                }
            }
            if !agenda.timed.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(agenda.timed) { item in
                        switch item {
                        case .event(let event): eventRow(event)
                        case .task(let task): taskRow(task, showsDate: false)
                        }
                    }
                }
            }
            if !agenda.anytimeTasks.isEmpty {
                section(Copy.planner.anytime) {
                    ForEach(agenda.anytimeTasks) { taskRow($0, showsDate: false) }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, tint: Color = Theme.Colors.muted, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func eventRow(_ event: PlannerEvent) -> some View {
        let subtitle = PlannerEventOwnership.subtitle(event, members: members, me: me)
        return tappable(event) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                timeColumn(start: event.start, end: event.end)
                RoundedRectangle(cornerRadius: 2).fill(Color(rgb: event.colorRGB)).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? Copy.planner.untitledEvent : event.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                Spacer(minLength: 0)
                eventMark(event)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(PlannerEventOwnership.accessibilityValue(event.origin, members: members, me: me))
    }

    /// Session 46: a ZANO event opens (the editor for mine, a read-only sheet for someone else's); an iPhone
    /// calendar event stays as it was (the Calendar app edits it).
    @ViewBuilder
    private func tappable<Content: View>(_ event: PlannerEvent, @ViewBuilder content: () -> Content) -> some View {
        if event.origin.isZanoEvent {
            Button { open(event) } label: {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    /// The small owner/visibility mark: a lock for "Only me", people and the creator's buddy for a shared event
    /// (session 47 added the buddy). Decorative; the row's accessibility value says the same in words.
    @ViewBuilder
    private func eventMark(_ event: PlannerEvent) -> some View {
        if let glyph = PlannerEventOwnership.glyph(event.origin) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: glyph)
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                    .foregroundStyle(Theme.Colors.muted)
                if case .household(_, let createdBy, _, _) = event.origin {
                    HouseholdMemberBuddy(
                        member: members.first { $0.userId == createdBy },
                        isMe: createdBy != nil && createdBy == me, size: 32
                    )
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func taskRow(_ task: PlannerTask, showsDate: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Button { toggle(task) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(task.isDone ? Theme.Colors.accent : Theme.Colors.muted)
                    .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(task.isDone ? Copy.planner.done : "")
            Button { taskTarget = TaskTarget(task: task, day: selected) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(task.isDone ? Theme.Colors.muted : Theme.Colors.text)
                        .strikethrough(task.isDone)
                        .multilineTextAlignment(.leading)
                    if showsDate, let due = task.due {
                        Text(due.formatted(.dateTime.month(.abbreviated).day()))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.danger)
                    } else if task.hasTime, let due = task.due {
                        // Tasks keep their checkbox at the left edge like Reminders; the time sits under the title.
                        Text(due.formatted(date: .omitted, time: .shortened))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: Theme.Metrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func timeColumn(start: Date, end: Date?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(start.formatted(date: .omitted, time: .shortened))
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
            if let end {
                Text(end.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(width: 64, alignment: .trailing)
    }

    // MARK: Calendar access

    @ViewBuilder
    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.planner.accessTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(isDenied ? Copy.planner.deniedDetail : Copy.planner.accessDetail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            if isDenied {
                PrimaryButton(title: Copy.planner.openSettings, style: .secondary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else {
                PrimaryButton(title: Copy.planner.accessButton, systemImage: "calendar") {
                    Task { await requestAccess() }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Actions

    private func select(_ day: Date) {
        selected = calendar.startOfDay(for: day)
        if !calendar.isDate(day, equalTo: month, toGranularity: .month) {
            month = calendar.startOfMonth(for: day)
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(reduceMotion ? nil : .snappy) {
            month = calendar.startOfMonth(for: next)
            // Keep the same day number selected, like the iOS Calendar, clamped to the month.
            let day = calendar.component(.day, from: selected)
            let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<29
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(day, range.upperBound - 1)
            selected = calendar.date(from: parts).map { calendar.startOfDay(for: $0) } ?? month
        }
    }

    private func goToToday() {
        withAnimation(reduceMotion ? nil : .snappy) {
            month = calendar.startOfMonth(for: .now)
            selected = calendar.startOfDay(for: .now)
        }
    }

    private func toggle(_ task: PlannerTask) {
        PlannerStore.toggleDone(id: task.id)
        reloadTasks()
    }

    private func reloadTasks() {
        tasks = PlannerStore.tasks
        Task { await PlannerReminders.refresh() }
    }

    private func refreshAccess() {
        hasAccess = PlannerCalendarSource.hasAccess
        isDenied = PlannerCalendarSource.isDenied
    }

    private func loadEvents() {
        refreshAccess()
        guard hasAccess, let first = weeks.first?.first, let last = weeks.last?.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last)
        else {
            deviceEvents = []
            return
        }
        deviceEvents = PlannerCalendarSource.events(from: first, to: end)
    }

    // MARK: Family calendar and private events (session 46)

    private func reloadZanoEvents() {
        privateEvents = PlannerStore.privateEvents
        householdEvents = HouseholdEventStore.events
        household = HouseholdEventStore.household
        members = HouseholdEventStore.members
        me = HouseholdEventStore.me
    }

    /// Fetches the family calendar into the App Group cache (nothing when Household isn't live), then redraws.
    private func refreshFamilyCalendar() async {
        if await HouseholdEventStore.refresh() {
            await PlannerReminders.refresh()
        }
        reloadZanoEvents()
    }

    private func open(_ event: PlannerEvent) {
        switch event.origin {
        case .device:
            return
        case .onlyMe(let id):
            guard let found = privateEvents.first(where: { $0.id == id }) else { return }
            eventTarget = EventTarget(existing: .onlyMe(found), day: selected)
        case .household(let id, _, _, _):
            if PlannerEventOwnership.isEditable(event.origin, me: me), let found = householdEvents.first(where: { $0.id == id }) {
                eventTarget = EventTarget(existing: .household(found), day: selected)
            } else {
                detailEvent = event
            }
        }
    }

    private func filterBinding(_ keyPath: WritableKeyPath<PlannerCalendarFilter, Bool>) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: keyPath] },
            set: { on in
                filter[keyPath: keyPath] = on
                PlannerStore.calendarFilter = filter
                Task { await PlannerReminders.refresh() }
            }
        )
    }

    private func requestAccess() async {
        _ = await FocusLockCalendarSource.shared.requestAccess()
        refreshAccess()
        loadEvents()
        await PlannerReminders.refresh()
    }

    private func startNewEvent() async {
        if !hasAccess { await requestAccess() }
        if hasAccess { showEventEditor = true }
    }
}

// MARK: - Helpers

extension Calendar {
    /// The first instant of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}

extension Color {
    /// A colour from 0xRRGGBB (a calendar's own colour).
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
