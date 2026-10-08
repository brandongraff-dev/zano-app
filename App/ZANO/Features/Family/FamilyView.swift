// FamilyView.swift
// App / ZANO / Features / Family
//
// The Family page (session 47; docs/spec.md §5.31): everything family in one place, under the family portrait.
//   1. The portrait (`FamilyPortraitView`): everyone as their buddy; tap one for their card. Alone, or with no
//      household yet: just my buddy and "Invite your family" (the join code, or the way to start one).
//   2. Family plan: "Shared with you by your family" or "Shared with your family", Manage Family Sharing.
//   3. Coming up: the next family-calendar events (session 46) and the next screen-free time (session 44).
//   4. Chores: open household tasks for me or nobody yet, tick to finish (session 28).
//   5. Family Link (session 23/45): send minutes (parent), minutes from family (teen), or set up.
//   6. Household: the members, "Change my name", and the full Household screen for tasks, screen-free times,
//      the invite code and leaving. That screen is reused through navigation, never copied here.
// Shown only when `FamilyHubAvailability` says so (Household live, or a family plan); each section shows only when
// it can work. Data comes from the App Group caches first, then the server. Wording: `Copy.familyHub`.

import SwiftUI
import Core

@MainActor
@Observable
final class FamilyHubModel {
    var household: Household?
    var members: [HouseholdMember]
    var me: UUID?
    var tasks: [HouseholdTask]
    var events: [HouseholdEvent]
    var quietWindows: [HouseholdQuietTime]
    var optIns: [HouseholdQuietTimeOptIn]
    var familyLink: FamilyLink?
    var familyLinkMe: UUID?
    var rewards: [FamilyReward]
    var entitlement: ProEntitlementInfo?
    var message: String?
    /// The CI screenshot: demo data, nothing fetched.
    let isPreview: Bool

    init(
        household: Household? = HouseholdEventStore.household,
        members: [HouseholdMember] = HouseholdEventStore.members,
        me: UUID? = HouseholdEventStore.me,
        tasks: [HouseholdTask] = [],
        events: [HouseholdEvent] = HouseholdEventStore.events,
        quietWindows: [HouseholdQuietTime] = HouseholdQuietTimeStore.windows,
        optIns: [HouseholdQuietTimeOptIn] = HouseholdQuietTimeStore.optIns,
        familyLink: FamilyLink? = nil,
        rewards: [FamilyReward] = [],
        entitlement: ProEntitlementInfo? = RevenueCatManager.shared.lastProEntitlement,
        isPreview: Bool = false
    ) {
        self.household = household
        self.members = members
        self.me = me
        self.tasks = tasks
        self.events = events
        self.quietWindows = quietWindows
        self.optIns = optIns
        self.familyLink = familyLink
        self.rewards = rewards
        self.entitlement = entitlement
        self.isPreview = isPreview
    }

    var isOwner: Bool { household != nil && household?.ownerId == me }

    func load() async {
        guard !isPreview else { return }
        if entitlement == nil {
            _ = await RevenueCatManager.shared.entitlementCheck()
            entitlement = RevenueCatManager.shared.lastProEntitlement
        }
        guard HouseholdAvailability.isLive else { return }
        await loadHousehold()
        await loadFamilyLink()
    }

    func loadHousehold() async {
        guard !isPreview, await HouseholdClient.shared.isConfigured else { return }
        await HouseholdEventStore.refresh()
        household = HouseholdEventStore.household
        members = HouseholdEventStore.members
        me = HouseholdEventStore.me
        events = HouseholdEventStore.events
        guard let household else {
            tasks = []
            return
        }
        do {
            tasks = try await HouseholdClient.shared.tasks(householdID: household.id)
        } catch {
            message = Copy.household.error(error)
        }
        if let fresh = try? await HouseholdClient.shared.quietTimes(householdID: household.id) {
            await HouseholdQuietTimeScheduler.shared.apply(fresh)
        }
        quietWindows = HouseholdQuietTimeStore.windows
        optIns = HouseholdQuietTimeStore.optIns
        // My row shows another buddy than mine (new household, or changed on another phone): send it.
        let myRow = members.first { $0.userId == me }
        let buddy = Buddy.stored
        if HouseholdBuddySync.needsSync(member: myRow, buddy: buddy, outfit: BuddyOutfit.stored(for: buddy)) {
            await HouseholdBuddySync.syncIfNeeded(force: true)
        }
    }

    func loadFamilyLink() async {
        guard !isPreview, FamilyLinkAvailability.isLive, await FamilyLinkClient.shared.isConfigured else { return }
        guard let link = try? await FamilyLinkClient.shared.links().first(where: { $0.status != .left }) else {
            familyLink = nil
            return
        }
        familyLink = link
        familyLinkMe = await FamilyLinkClient.shared.currentUserID()
        if link.status == .active {
            rewards = (try? await FamilyLinkClient.shared.rewards(linkID: link.id)) ?? []
        }
    }

    func toggle(_ task: HouseholdTask) async {
        guard !isPreview else { return }
        do {
            try await HouseholdClient.shared.setDone(taskID: task.id, done: !task.isDone)
            if let household { tasks = try await HouseholdClient.shared.tasks(householdID: household.id) }
            PlannerStore.sharedAssigned = HouseholdBoard.reminderTasks(from: tasks, me: me)
            await PlannerReminders.refresh()
        } catch {
            message = Copy.household.error(error)
        }
    }

    func rename(to name: String) async {
        guard !isPreview, let household else { return }
        do {
            try await HouseholdClient.shared.rename(householdID: household.id, displayName: name)
            await loadHousehold()
        } catch {
            message = Copy.household.error(error)
        }
    }
}

struct FamilyView: View {
    @State private var model: FamilyHubModel
    @State private var selectedMember: HouseholdMember?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var showPlanner = false

    @Environment(\.openURL) private var openURL

    init(model: FamilyHubModel? = nil) {
        _model = State(initialValue: model ?? FamilyHubModel())
    }

    private var isLive: Bool { model.isPreview || HouseholdAvailability.isLive }
    private var household: Household? { isLive ? model.household : nil }
    private var planStatus: FamilyHubAvailability.PlanStatus { FamilyHubAvailability.planStatus(entitlement: model.entitlement) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                FamilyPortraitView(
                    title: household?.name ?? Copy.familyHub.soloTitle,
                    members: household == nil ? [] : model.members,
                    me: model.me
                ) { selectedMember = $0 }
                if household == nil || model.members.count <= 1 { inviteCard }
                if planStatus != .noPlan { planCard }
                if household != nil {
                    comingUpCard
                    choresCard
                }
                if model.isPreview || FamilyLinkAvailability.isLive { familyLinkCard }
                if let household { householdCard(household) }
                if let message = model.message { note(message) }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.familyHub.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(item: $selectedMember) { member in
            FamilyMemberCard(
                member: member,
                isMe: member.userId == model.me,
                isOwner: member.userId == model.household?.ownerId,
                sharedEventCount: FamilyPortrait.eventsSharedWith(member.userId, events: model.events, me: model.me)
            )
        }
        .sheet(isPresented: $showPlanner) { PlannerView() }
        .alert(Copy.familyHub.renameTitle, isPresented: $isRenaming) {
            TextField(Copy.household.yourNamePlaceholder, text: $newName)
            Button(Copy.familyHub.renameSave) {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await model.rename(to: String(name.prefix(30))) }
            }
            Button(Copy.familyHub.cancel, role: .cancel) {}
        }
    }

    // MARK: Invite

    @ViewBuilder
    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.familyHub.inviteTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            if let household {
                note(Copy.familyHub.inviteDetail)
                Text(household.inviteCode)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .textSelection(.enabled)
                ShareLink(item: Copy.household.inviteMessage(code: household.inviteCode, name: household.name)) {
                    Label(Copy.household.inviteShare, systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.headline)
                }
                .frame(minHeight: Theme.Metrics.minTapTarget)
            } else if isLive {
                note(Copy.familyHub.noHouseholdDetail)
                NavigationLink {
                    HouseholdView()
                } label: {
                    Label(Copy.familyHub.startOrJoin, systemImage: "house.fill")
                        .font(Theme.Typography.headline)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                }
            } else {
                // Not signed in: Household can't work, but Apple's family group can.
                note(Copy.familyHub.appleFamilyInvite)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Family plan

    private var planCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(Copy.familyHub.planTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            ZanoStatusCapsule(
                dotColor: Theme.Colors.Ring.steps,
                text: planStatusText,
                systemImage: planStatus == .yours ? "checkmark.seal.fill" : "person.3.fill"
            )
            if planStatus == .sharedWithYou { note(Copy.familyHub.planSharedWithYouNote) }
            note(Copy.familyHub.planExplainer)
            if planStatus == .sharingWithFamily {
                // No public deep link opens Family Sharing in the Settings app; the button opens the App Store's
                // subscriptions page and the note says where Family Sharing lives.
                PrimaryButton(title: Copy.familyHub.manageFamilySharing, systemImage: "arrow.up.right", style: .secondary) {
                    if let url = URL(string: Copy.settings.manageSubscriptionsURLString) { openURL(url) }
                }
                note(Copy.familyHub.manageFamilySharingHow)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    private var planStatusText: String {
        switch planStatus {
        case .sharedWithYou: Copy.familyHub.planSharedWithYou
        case .sharingWithFamily: Copy.familyHub.planSharingWithFamily
        case .yours, .noPlan: Copy.familyHub.planYours
        }
    }

    // MARK: Coming up

    private var comingUpCard: some View {
        let upcoming = HouseholdEventRules.upcoming(model.events, me: model.me, now: .now)
        let quiet = FamilyHubLists.nextQuietTime(windows: model.quietWindows, optIns: model.optIns, now: .now)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(Copy.familyHub.comingUpTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(Copy.familyHub.openCalendar) { showPlanner = true }
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
            }
            if upcoming.isEmpty && quiet == nil { note(Copy.familyHub.comingUpEmpty) }
            ForEach(upcoming) { event in
                HStack(spacing: Theme.Spacing.sm) {
                    HouseholdMemberBuddy(
                        member: model.members.first { $0.userId == event.createdBy },
                        isMe: event.createdBy == model.me, size: 32
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(2)
                        Text(Copy.familyHub.eventLine(event.startsAt, allDay: event.allDay))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: event.visibility == .household ? "person.2.fill" : "person.crop.circle.badge.checkmark")
                        .font(Theme.Typography.icon(.xsmall, weight: .bold))
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
            if let quiet {
                NavigationLink {
                    HouseholdView()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        Text(quiet.isRunning
                             ? Copy.familyHub.quietRunning(name: quiet.window.name, end: quiet.occurrence.end)
                             : Copy.familyHub.quietNext(name: quiet.window.name, start: quiet.occurrence.start))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        ZanoGlassChip(
                            quiet.isJoined ? Copy.familyHub.quietJoined : Copy.familyHub.quietNotJoined,
                            systemImage: quiet.isJoined ? "checkmark" : nil
                        )
                    }
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Chores

    private var choresCard: some View {
        let chores = FamilyHubLists.chores(tasks: model.tasks, me: model.me)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(Copy.familyHub.choresTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink(Copy.familyHub.seeAll) { HouseholdView() }
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
            }
            if chores.isEmpty { note(Copy.familyHub.choresEmpty) }
            ForEach(chores) { task in
                HStack(spacing: Theme.Spacing.sm) {
                    Button { Task { await model.toggle(task) } } label: {
                        Image(systemName: "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.Colors.muted)
                            .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(2)
                        Text(task.assigneeId == nil ? Copy.familyHub.upForGrabs : Copy.familyHub.forYou)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Family Link

    private var familyLinkCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.familyHub.familyLinkTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            if let link = model.familyLink, link.status == .active {
                let isParent = model.familyLinkMe != nil && model.familyLinkMe == link.parentId
                if isParent {
                    navRow(Copy.familyHub.familyLinkParent, systemImage: "gift.fill") { FamilyLinkView() }
                } else {
                    // The teen sees what was sent, and keeps the consent wording: they can see everything, and leave.
                    if model.rewards.isEmpty { note(Copy.familyHub.familyLinkNoRewards) }
                    ForEach(model.rewards.prefix(3)) { reward in
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(Copy.family.rewardChip(reward.minutes))
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.text)
                            if let text = reward.note, !text.isEmpty {
                                Text(text)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text(Copy.family.rewardStatus(reward, link: link))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    note(Copy.family.consentNote)
                    navRow(Copy.familyHub.familyLinkTeen, systemImage: "person.2.fill") { FamilyLinkView() }
                }
            } else {
                note(Copy.family.intro)
                navRow(Copy.familyHub.familyLinkSetUp, systemImage: "link") { FamilyLinkView() }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Household

    private func householdCard(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.familyHub.householdTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(FamilyPortrait.ordered(model.members)) { member in
                let isMe = member.userId == model.me
                HStack(spacing: Theme.Spacing.sm) {
                    HouseholdMemberBuddy(member: member, isMe: isMe, size: 32)
                    Text(isMe ? Copy.familyHub.you : member.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                    if member.userId == household.ownerId {
                        Text(Copy.familyHub.owner)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    Spacer(minLength: 0)
                    if isMe {
                        Button(Copy.familyHub.changeMyName) {
                            newName = member.displayName
                            isRenaming = true
                        }
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .frame(minHeight: Theme.Metrics.minTapTarget)
            }
            navRow(Copy.familyHub.manageHousehold, systemImage: "house.fill") { HouseholdView() }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Pieces

    private func navRow<Destination: View>(_ title: String, systemImage: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
