// HouseholdView.swift
// App / ZANO / Features / Household
//
// Household (session 28; docs/spec.md §5.31): a shared task list for the people someone lives or works with.
// Start one or join with a code; then one list with "Assigned to you", "Not taken yet", "Everyone else" and
// "Done lately", a circle to tick anything off, and a sheet to add a task and give it to someone. Hidden
// from the app (`HouseholdAvailability.isLive`) until the backend and sign-in exist. Wording: `Copy.household`.
// Session 44 adds "Screen-free times" (`HouseholdQuietTimesSection`) under the list.

import SwiftUI
import Core

struct HouseholdView: View {
    @State private var configured: Bool?
    @State private var me: UUID?
    @State private var household: Household?
    @State private var members: [HouseholdMember] = []
    @State private var tasks: [HouseholdTask] = []
    /// Session 44: the household's shared screen-free times (joins stay on this phone).
    @State private var quietTimes: [HouseholdQuietTime] = HouseholdQuietTimeStore.windows
    @State private var message: String?
    @State private var isLoading = false
    @State private var showNewTask = false
    @State private var householdName = ""
    @State private var yourName = ""
    @State private var code = ""

    private var sections: HouseholdBoard.Sections { HouseholdBoard.sections(tasks: tasks, me: me) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.household.intro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if configured == false {
                    note(Copy.household.notAvailable)
                } else if configured == true {
                    if let household { board(household) } else { startForms }
                }
                if let message { note(message) }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.household.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showNewTask) {
            if let household {
                HouseholdTaskEditor(householdID: household.id, members: members, me: me) {
                    Task { await refresh() }
                }
            }
        }
    }

    // MARK: Start

    private var startForms: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(Copy.household.createTitle).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.text)
                TextField(Copy.household.householdNamePlaceholder, text: $householdName)
                TextField(Copy.household.yourNamePlaceholder, text: $yourName)
                PrimaryButton(
                    title: Copy.household.createButton,
                    isEnabled: !householdName.trimmingCharacters(in: .whitespaces).isEmpty && !yourName.trimmingCharacters(in: .whitespaces).isEmpty
                ) { Task { await create() } }
            }
            .padding(Theme.Spacing.md)
            .zanoCard()
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(Copy.household.joinTitle).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.text)
                TextField(Copy.household.codePlaceholder, text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField(Copy.household.yourNamePlaceholder, text: $yourName)
                PrimaryButton(
                    title: Copy.household.joinButton, style: .secondary,
                    isEnabled: !code.isEmpty && !yourName.trimmingCharacters(in: .whitespaces).isEmpty
                ) { Task { await join() } }
            }
            .padding(Theme.Spacing.md)
            .zanoCard()
            note(Copy.household.privacyNote)
        }
    }

    // MARK: Board

    @ViewBuilder
    private func board(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(household.name).font(Theme.Typography.title).foregroundStyle(Theme.Colors.text)
            Text(members.map(\.displayName).joined(separator: ", "))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        PrimaryButton(title: Copy.household.newTask, systemImage: "plus") { showNewTask = true }
        if sections.isEmpty {
            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.household.nothingYet).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textSecondary)
                Text(Copy.household.nothingYetDetail).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
        }
        group(Copy.household.mine, sections.mine)
        group(Copy.household.unassigned, sections.unassigned)
        group(Copy.household.others, sections.others)
        group(Copy.household.doneRecently, sections.doneRecently)

        HouseholdQuietTimesSection(
            household: household, me: me, members: members, quietTimes: quietTimes
        ) {
            Task { await refresh() }
        }

        inviteCard(household)
        PrimaryButton(title: Copy.household.leave, style: .secondary) { Task { await leave(household) } }
        note(Copy.household.leaveNote)
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [HouseholdTask]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                ForEach(list) { row($0) }
            }
        }
    }

    private func row(_ task: HouseholdTask) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Button { Task { await toggle(task) } } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(task.isDone ? Theme.Colors.accent : Theme.Colors.muted)
                    .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(task.isDone ? Theme.Colors.muted : Theme.Colors.text)
                    .strikethrough(task.isDone)
                if let line = detailLine(task) {
                    Text(line).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.Metrics.minTapTarget, alignment: .center)
        }
        .contextMenu {
            Button(Copy.household.delete, role: .destructive) { Task { await delete(task) } }
        }
    }

    private func detailLine(_ task: HouseholdTask) -> String? {
        var parts: [String] = []
        if task.isDone, let who = HouseholdBoard.name(for: task.doneBy, members: members, me: me) {
            parts.append(Copy.household.doneBy(who))
        } else if let who = HouseholdBoard.name(for: task.assigneeId, members: members, me: me), task.assigneeId != me {
            parts.append(Copy.household.assignedTo(who))
        }
        if let due = task.dueAt { parts.append(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func inviteCard(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.household.inviteTitle).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.text)
            Text(household.inviteCode).font(Theme.Typography.title).textSelection(.enabled)
            ShareLink(item: Copy.household.inviteMessage(code: household.inviteCode, name: household.name)) {
                Label(Copy.household.inviteShare, systemImage: "square.and.arrow.up")
            }
            if household.ownerId == me {
                Button(Copy.household.inviteNewCode) { Task { await rotate(household) } }
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
            }
            note(Copy.household.inviteNote)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func load() async {
        let ok = await HouseholdClient.shared.isConfigured
        configured = ok
        guard ok else { return }
        me = try? await HouseholdClient.shared.currentUserID()
        await refresh()
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            household = try await HouseholdClient.shared.households().first
            if let household {
                members = try await HouseholdClient.shared.members(householdID: household.id)
                tasks = try await HouseholdClient.shared.tasks(householdID: household.id)
                PlannerStore.sharedAssigned = HouseholdBoard.reminderTasks(from: tasks, me: me)
                // Session 46: keep the family calendar's cache (household, members) in step with this screen.
                HouseholdEventStore.save(household: household, members: members, me: me, events: HouseholdEventStore.events)
                await PlannerReminders.refresh()
                // Separate from the task list so a project without 0009 still shows tasks.
                if let fresh = try? await HouseholdClient.shared.quietTimes(householdID: household.id) {
                    await HouseholdQuietTimeScheduler.shared.apply(fresh)
                    quietTimes = fresh
                }
            } else {
                members = []
                tasks = []
                PlannerStore.sharedAssigned = []
                // Session 46: no household, no family calendar on this phone.
                HouseholdEventStore.resetAll()
                // No household (left, or never joined): nothing to lock for.
                await HouseholdQuietTimeScheduler.shared.apply([])
                quietTimes = []
            }
        } catch {
            message = Copy.household.error(error)
        }
    }

    private func run(_ work: () async throws -> Void) async {
        message = nil
        do { try await work() } catch { message = Copy.household.error(error) }
    }

    private func create() async {
        await run {
            _ = try await HouseholdClient.shared.create(
                name: householdName.trimmingCharacters(in: .whitespaces),
                displayName: yourName.trimmingCharacters(in: .whitespaces)
            )
            await refresh()
        }
    }

    private func join() async {
        await run {
            _ = try await HouseholdClient.shared.join(
                code: code.trimmingCharacters(in: .whitespaces).uppercased(),
                displayName: yourName.trimmingCharacters(in: .whitespaces)
            )
            await refresh()
        }
    }

    private func toggle(_ task: HouseholdTask) async {
        await run {
            try await HouseholdClient.shared.setDone(taskID: task.id, done: !task.isDone)
            await refresh()
        }
    }

    private func delete(_ task: HouseholdTask) async {
        await run {
            try await HouseholdClient.shared.deleteTask(taskID: task.id)
            await refresh()
        }
    }

    private func rotate(_ household: Household) async {
        await run {
            _ = try await HouseholdClient.shared.rotateInvite(householdID: household.id)
            await refresh()
        }
    }

    private func leave(_ household: Household) async {
        await run {
            try await HouseholdClient.shared.leave(householdID: household.id)
            self.household = nil
            await refresh()
        }
    }
}
