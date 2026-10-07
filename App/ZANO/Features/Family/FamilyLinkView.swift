// FamilyLinkView.swift
// App / ZANO / Features / Family
//
// Settings > Family Link (session 23; docs/spec.md §5.23). One screen, two sides: a parent makes an
// invite and sets tasks; a teen accepts (the consent), hands tasks in, and can leave. A proof photo is
// view-once: it is held in memory only while the parent looks at it, never saved, and dropped at its
// deletion time. When there is no backend yet (`FamilyLinkClient.isConfigured` is false) the screen
// says so and does nothing else.

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Core

struct FamilyLinkView: View {
    private enum Side { case parent, teen }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]

    @State private var configured: Bool?
    @State private var side: Side?
    @State private var links: [FamilyLink] = []
    @State private var tasks: [FamilyTask] = []
    @State private var message: String?
    @State private var inviteCode = ""
    @State private var codeInput = ""
    @State private var newTitle = ""
    @State private var newRequiresPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoTaskID: UUID?
    @State private var viewing: (image: UIImage, deletedAt: Date)?

    private var activeLink: FamilyLink? { links.first { $0.status != .left } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.family.intro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if configured == false {
                    note(Copy.family.notAvailable)
                } else if configured == true {
                    content
                }
                if let message { note(message) }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.family.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) { photoSheet }
        .onChange(of: photoItem) { _, item in
            guard let item, let taskID = photoTaskID, let link = activeLink else { return }
            Task { await handIn(taskID: taskID, link: link, item: item) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if activeLink == nil {
            if side == nil {
                PrimaryButton(title: Copy.family.imParent, systemImage: "person.fill") { side = .parent }
                PrimaryButton(title: Copy.family.imTeen, systemImage: "ticket.fill", style: .secondary) { side = .teen }
                note(Copy.family.ageNote)
            } else if side == .parent {
                if inviteCode.isEmpty {
                    PrimaryButton(title: Copy.family.makeInvite, systemImage: "link") { Task { await makeInvite() } }
                } else {
                    Text(inviteCode).font(Theme.Typography.title).textSelection(.enabled)
                    note(Copy.family.inviteShare)
                }
            } else {
                note(Copy.family.consentNote)
                TextField(Copy.family.codePlaceholder, text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                PrimaryButton(title: Copy.family.acceptButton, isEnabled: !codeInput.isEmpty) { Task { await accept() } }
            }
        } else if let link = activeLink {
            if link.status == .invited {
                Text(link.inviteCode).font(Theme.Typography.title).textSelection(.enabled)
                note(Copy.family.waitingForTeen)
            } else {
                taskList(link: link)
                PrimaryButton(title: Copy.family.leave, style: .secondary) { Task { await leave(link) } }
                note(Copy.family.leaveNote)
            }
        }
    }

    @ViewBuilder
    private func taskList(link: FamilyLink) -> some View {
        let isParent = side != .teen
        if isParent {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(Copy.family.newTaskTitle).font(Theme.Typography.headline)
                TextField(Copy.family.taskPlaceholder, text: $newTitle)
                Toggle(Copy.family.requiresPhoto, isOn: $newRequiresPhoto)
                PrimaryButton(title: Copy.family.addTask, isEnabled: !newTitle.isEmpty) { Task { await addTask(link) } }
            }
        }
        if tasks.isEmpty { note(Copy.family.noTasks) }
        ForEach(tasks) { task in
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(task.title).font(Theme.Typography.headline)
                Text(Copy.family.status(task.status)).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.muted)
                if isParent, task.status == .submitted {
                    if task.requiresPhoto {
                        PrimaryButton(title: Copy.family.openPhoto, style: .secondary) { Task { await openPhoto(task) } }
                        note(Copy.family.photoOnceNote)
                    }
                    PrimaryButton(title: Copy.family.approve) { Task { await decide(task, approved: true) } }
                    PrimaryButton(title: Copy.family.askRedo, style: .secondary) { Task { await decide(task, approved: false) } }
                } else if !isParent, task.status == .open || task.status == .redo {
                    if task.requiresPhoto {
                        PhotosPicker(selection: $photoItem, matching: .images) { Text(Copy.family.pickPhoto) }
                            .simultaneousGesture(TapGesture().onEnded { photoTaskID = task.id })
                    } else {
                        PrimaryButton(title: Copy.family.handIn) { Task { await handIn(taskID: task.id, link: link, item: nil) } }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var photoSheet: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let viewing {
                Image(uiImage: viewing.image).resizable().scaledToFit()
                Text("\(Copy.family.photoClosesAt) \(viewing.deletedAt.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.muted)
            }
        }
        .padding()
        .task(id: viewing?.deletedAt) {
            // Drop the picture at its deletion time; it is held in memory only, never saved.
            guard let end = viewing?.deletedAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            viewing = nil
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func load() async {
        let ok = await FamilyLinkClient.shared.isConfigured
        configured = ok
        guard ok else { return }
        await refresh()
    }

    private func refresh() async {
        do {
            links = try await FamilyLinkClient.shared.links()
            if let link = activeLink, link.status == .active {
                tasks = try await FamilyLinkClient.shared.tasks(linkID: link.id)
                if side == nil { side = link.teenId == nil ? .parent : side }
                recordFamilyGoalIfDone()
            }
        } catch { message = Copy.family.error(error) }
    }

    private func run(_ work: () async throws -> Void) async {
        message = nil
        do { try await work() } catch { message = Copy.family.error(error) }
    }

    private func makeInvite() async {
        await run {
            inviteCode = try await FamilyLinkClient.shared.createInvite()
            await refresh()
        }
    }

    private func accept() async {
        await run {
            _ = try await FamilyLinkClient.shared.acceptInvite(code: codeInput.trimmingCharacters(in: .whitespaces).uppercased())
            await refresh()
        }
    }

    private func leave(_ link: FamilyLink) async {
        await run {
            try await FamilyLinkClient.shared.leave(linkID: link.id)
            tasks = []
            side = nil
            await refresh()
        }
    }

    private func addTask(_ link: FamilyLink) async {
        await run {
            _ = try await FamilyLinkClient.shared.createTask(linkID: link.id, title: newTitle, dueAt: nil, requiresPhoto: newRequiresPhoto)
            newTitle = ""
            await refresh()
        }
    }

    private func decide(_ task: FamilyTask, approved: Bool) async {
        await run {
            try await FamilyLinkClient.shared.decideTask(taskID: task.id, approved: approved, note: nil)
            await refresh()
        }
    }

    private func handIn(taskID: UUID, link: FamilyLink, item: PhotosPickerItem?) async {
        await run {
            var jpeg: Data?
            if let item, let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                jpeg = image.jpegData(compressionQuality: 0.6)
            }
            try await FamilyLinkClient.shared.submitTask(taskID: taskID, linkID: link.id, photoJPEG: jpeg)
            photoItem = nil
            photoTaskID = nil
            await refresh()
        }
    }

    private func openPhoto(_ task: FamilyTask) async {
        await run {
            guard let proof = try await FamilyLinkClient.shared.proofs(taskID: task.id).first,
                  FamilyProofClock.canOpen(proof, now: .now) else { throw FamilyLinkError.gone }
            let opened = try await FamilyLinkClient.shared.openProof(proofID: proof.id)
            guard let image = UIImage(data: opened.image) else { throw FamilyLinkError.badResponse }
            viewing = (image, opened.deletedAt)
        }
    }

    /// Approved tasks count toward the "Family tasks" goal, if the person has made one (spec §5.23).
    private func recordFamilyGoalIfDone() {
        guard side == .teen,
              FamilyTaskGoal.isTodayDone(tasks: tasks, now: .now),
              let goal = goals.first(where: { $0.title == FamilyTaskGoal.goalTitle }),
              !goal.events.contains(where: { $0.kind == .complete && Calendar.current.isDateInToday($0.ts) })
        else { return }
        context.insert(GoalEvent(kind: .complete, value: nil, source: .manual, verified: true, user: goal.user, goal: goal))
        try? context.save()
        Task { await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goal.id) }
    }
}
