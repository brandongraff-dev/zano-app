// SquadHomeView.swift
// App / ZANO / Features / Squad
//
// The Squad tab root (docs/spec.md §5.7 Squads & Duels, §4 v3 "Squads (2–8 friends): see each
// other's rings, nudge, weekly squad streak", §5.4 Ghost Mode for the solo duel). Hosted by
// `ContentView` inside its own `NavigationStack`, so this view has none.
//
// States:
//   - no squad → a hero explaining squads, with "Create a squad" / "Join with a code". When the
//     backend isn't live, a calm "Squads go live soon" card says what works now (reserving a code)
//     and what doesn't (friends joining).
//   - in a squad → the squad's weekly ring, `SquadRingBoard` (members' rings, stars, streaks, lock
//     state, nudges), the shared freeze, the invite code, and the duels list.
//   - "Beat last week" is always available: it only reads this phone's own history.

import SwiftUI
import UIKit
import Core

/// Where the Squad tab can push.
enum SquadRoute: Hashable {
    case soloDuel
    case duel(UUID)
}

struct SquadHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SquadHomeModel()
    @State private var sheet: CreateJoinSquadSheet.Mode?
    @State private var joinPrefill = ""
    @State private var showDuelInvite = false
    @State private var confirmLeave = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                statusRow
                if model.phase == .loading {
                    loadingPlaceholder
                } else if let squad = model.squad {
                    squadContent(squad)
                } else {
                    noSquadContent
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: model.phase)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: model.squad)
        }
        .zanoAmbient(model.squad == nil ? .neutral : .progress(model.squadWeekFraction))
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.squad.screenTitle)
        .toolbar { toolbarContent }
        .navigationDestination(for: SquadRoute.self) { route in
            switch route {
            case .soloDuel:
                SoloDuelView()
            case .duel(let id):
                if let duel = model.duels.first(where: { $0.id == id }), let me = model.myUserID {
                    DuelView(
                        duel: duel,
                        myUserID: me,
                        opponentName: model.name(for: duel.aUser == me ? duel.bUser : duel.aUser),
                        backendConnected: model.backendConnected
                    )
                }
            }
        }
        .task {
            await model.load()
            consumeDeepLinkJoinCode()
        }
        .refreshable { await model.load() }
        .onAppear { Analytics.shared.capture(event: "squad_viewed") }
        .onChange(of: router.pendingSquadJoinCode) { _, _ in consumeDeepLinkJoinCode() }
        .sheet(item: $sheet) { mode in
            CreateJoinSquadSheet(model: model, initialMode: mode, prefilledCode: joinPrefill)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showDuelInvite) {
            DuelInviteSheet(model: model)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog(Copy.squad.leaveConfirmTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(Copy.squad.leaveConfirmButton, role: .destructive) {
                Task {
                    do { try await model.leaveSquad() } catch { errorMessage = SquadHomeModel.message(for: error) }
                }
            }
            Button(Copy.squad.cancel, role: .cancel) {}
        } message: {
            Text(Copy.squad.leaveConfirmMessage)
        }
        .alert(Copy.squad.errorGeneric, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(Copy.squad.done, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func consumeDeepLinkJoinCode() {
        guard let code = router.consumeSquadJoinCode() else { return }
        joinPrefill = code
        sheet = .join
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if model.squad != nil {
                Menu {
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Label(Copy.squad.leaveSquad, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(Theme.Typography.icon(.medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel(Copy.squad.menuAccessibility)
            }
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack {
            if model.backendConnected {
                ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.squad.liveStatus)
            } else {
                ZanoStatusCapsule(dotColor: Theme.Colors.warning, text: Copy.squad.offlineStatus)
            }
            Spacer(minLength: 0)
        }
    }

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(Theme.Colors.surface)
            .frame(height: 260)
            .redacted(reason: .placeholder)
    }

    // MARK: - No squad

    @ViewBuilder
    private var noSquadContent: some View {
        hero
        if !model.backendConnected {
            offlineCard
        }
        duelsSection
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Copy.squad.heroEyebrow)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(Copy.squad.heroTitle)
                        .zanoText(.titleLarge)
                        .foregroundStyle(Theme.Colors.text)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: Theme.Spacing.sm)
                heroRings
            }
            Text(Copy.squad.heroBody)
                .zanoText(.paragraph)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                heroPoint("circle.hexagongrid", Copy.squad.heroPointRings)
                heroPoint("hand.wave", Copy.squad.heroPointNudge)
                heroPoint("flag.2.crossed", Copy.squad.heroPointDuel)
                heroPoint("snowflake", Copy.squad.heroPointFreeze)
            }
            .padding(.vertical, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                PrimaryButton(title: Copy.squad.createSquadButton, systemImage: "plus") {
                    sheet = .create
                }
                .accessibilityIdentifier("squad.create")
                PrimaryButton(title: Copy.squad.joinWithCodeButton, systemImage: "number", style: .secondary) {
                    joinPrefill = ""
                    sheet = .join
                }
                .accessibilityIdentifier("squad.join")
            }
        }
        .padding(Theme.Spacing.lg)
        .zanoHero(tint: Theme.Colors.accent)
    }

    /// Three overlapping rings: a squad at a glance, before there is one.
    private var heroRings: some View {
        ZStack {
            GoalRing(progress: 0.82, color: Theme.Colors.Ring.workout, size: .custom(44))
                .offset(x: -18, y: 8)
            GoalRing(progress: 0.55, color: Theme.Colors.Ring.protein, size: .custom(44))
                .offset(x: 18, y: 8)
            GoalRing(progress: 1, color: Theme.Colors.accent, size: .custom(44))
                .offset(y: -14)
        }
        .frame(width: 84, height: 76)
        .accessibilityHidden(true)
    }

    private func heroPoint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .zanoText(.body)
                .foregroundStyle(Theme.Colors.text)
        }
    }

    private var offlineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityHidden(true)
                Text(Copy.squad.offlineTitle)
                    .zanoText(.headline)
                    .foregroundStyle(Theme.Colors.text)
            }
            Text(Copy.squad.offlineBody)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let code = model.pendingJoinCode {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.squad.offlinePendingJoin(code))
                        .zanoText(.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.xs)
                    Button(Copy.squad.clearPendingJoin) { model.clearPendingJoin() }
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(Theme.Spacing.sm)
                .zanoWell()
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(tint: Theme.Colors.warning)
    }

    // MARK: - In a squad

    @ViewBuilder
    private func squadContent(_ squad: SquadSnapshot) -> some View {
        squadHeader(squad)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SquadSectionLabel(text: Copy.squad.boardSectionTitle)
            SquadRingBoard(
                rows: model.rows,
                weekStart: model.weekStart,
                backendConnected: model.backendConnected,
                onNudge: { row in await model.nudge(row) }
            )
            if model.otherMembers.isEmpty {
                aloneCard
            }
        }
        freezeCard
        inviteCard(squad)
        duelsSection
    }

    private func squadHeader(_ squad: SquadSnapshot) -> some View {
        let percent = Int((model.squadWeekFraction * 100).rounded())
        return HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(model.style.emoji)
                        .font(.system(size: 28))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(model.style.color.opacity(0.18)))
                        .overlay(Circle().strokeBorder(model.style.color.opacity(0.5), lineWidth: 1))
                        .accessibilityHidden(true)
                }
                Text(squad.name)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.squad.weeklyRingCaption(members: model.rows.count))
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            Spacer(minLength: Theme.Spacing.sm)
            VStack(spacing: Theme.Spacing.xs) {
                GoalRing(
                    progress: model.squadWeekFraction,
                    color: model.style.color,
                    size: .custom(104),
                    center: .text(Copy.squad.weeklyRingValue(percent: percent)),
                    label: Copy.squad.weeklyRingAccessibility(percent)
                )
                Text(Copy.squad.weeklyRingTitle)
                    .zanoText(.captionEmphasized)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .zanoHero(tint: model.style.color, active: model.squadWeekFraction >= 1)
    }

    private var aloneCard: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "person.badge.plus", size: .small)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.squad.aloneTitle)
                    .zanoText(.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(model.backendConnected ? Copy.squad.aloneBody : Copy.squad.offlineRingsNote)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private var freezeCard: some View {
        let usedBy = model.freeze.map { model.name(for: $0.usedByUserID) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SquadSectionLabel(text: Copy.squad.freezeSectionTitle)
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "snowflake", tint: Theme.Colors.Ring.water, size: .small)
                Text(usedBy.map(Copy.squad.freezeUsed(by:)) ?? Copy.squad.freezeAvailable)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .zanoCard()
        }
    }

    private func inviteCard(_ squad: SquadSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SquadSectionLabel(text: Copy.squad.inviteSectionTitle)
            SquadInviteCodeCard(squad: squad, backendConnected: model.backendConnected)
        }
    }

    // MARK: - Duels

    private var duelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SquadSectionLabel(text: Copy.squad.duelsSectionTitle)
                Spacer()
                Button {
                    showDuelInvite = true
                } label: {
                    Label(Copy.squad.newDuelButton, systemImage: "plus")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                }
                .buttonStyle(.pressable(scale: 0.96))
                .accessibilityIdentifier("squad.newDuel")
            }

            NavigationLink(value: SquadRoute.soloDuel) {
                soloDuelRow
            }
            .buttonStyle(.pressable)

            ForEach(model.duels) { duel in
                NavigationLink(value: SquadRoute.duel(duel.id)) {
                    friendDuelRow(duel)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var soloDuelRow: some View {
        let this = model.solo?.thisWeekPoints ?? 0
        let last = model.solo?.lastWeekPointsToDate ?? 0
        return HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "figure.run", tint: Theme.Colors.accent, size: .small)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.squad.soloDuelRowTitle)
                    .zanoText(.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.squad.soloDuelRowSubtitle(this: this, last: last))
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Copy.squad.worksOffline)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(1)
            Image(systemName: "chevron.forward")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(tint: this > last ? Theme.Colors.accent : nil)
        .accessibilityElement(children: .combine)
    }

    private func friendDuelRow(_ duel: DuelSnapshot) -> some View {
        let me = model.myUserID
        let isA = duel.aUser == me
        let mine = isA ? duel.aPoints : duel.bPoints
        let theirs = isA ? duel.bPoints : duel.aPoints
        let opponent = model.name(for: isA ? duel.bUser : duel.aUser)
        let status: String = switch duel.status {
        case .pending: Copy.squad.pendingStatus
        case .active: Copy.squad.activeStatus
        case .complete, .declined: Copy.squad.completeStatus
        }
        return HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "flag.2.crossed", tint: duel.status == .active ? Theme.Colors.accent : Theme.Colors.muted, size: .small)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.squad.friendDuelRowTitle(name: opponent))
                    .zanoText(.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(status)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if duel.status != .pending {
                Text(Copy.squad.scoreLine(me: mine, them: theirs))
                    .font(Theme.Typography.numeralSmall())
                    .foregroundStyle(Theme.Colors.text)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.forward")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(tint: duel.status == .active ? Theme.Colors.accent : nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared pieces

/// The small label above a section card (same treatment as Progress's section labels).
struct SquadSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .zanoText(.eyebrow)
            .foregroundStyle(Theme.Colors.muted)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The invite code, big and copyable, with a share link (`zano://squad/join/CODE` plus plain
/// instructions for anyone whose phone doesn't open the link).
struct SquadInviteCodeCard: View {
    let squad: SquadSnapshot
    let backendConnected: Bool
    @State private var copiedTick = 0
    @State private var showCopied = false

    private var link: String { "zano://squad/join/\(squad.inviteCode)" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.squad.inviteCodeLabel)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                    Text(squad.inviteCode)
                        .font(Theme.Typography.numeral(size: 34, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(Theme.Colors.text)
                        .textSelection(.enabled)
                        .accessibilityLabel(squad.inviteCode.map { String($0) }.joined(separator: " "))
                }
                Spacer(minLength: Theme.Spacing.sm)
                Button {
                    UIPasteboard.general.string = squad.inviteCode
                    copiedTick += 1
                    showCopied = true
                } label: {
                    Label(showCopied ? Copy.squad.copiedCode : Copy.squad.copyCode,
                          systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                        .zanoGlass()
                }
                .buttonStyle(.pressable(scale: 0.96))
                .sensoryFeedback(.success, trigger: copiedTick)
            }

            ShareLink(
                item: Copy.squad.shareMessage(squadName: squad.name, code: squad.inviteCode, link: link),
                subject: Text(Copy.squad.sharePreviewTitle(squadName: squad.name)),
                preview: SharePreview(Copy.squad.sharePreviewTitle(squadName: squad.name))
            ) {
                Label(Copy.squad.shareInvite, systemImage: "square.and.arrow.up")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metrics.primaryButtonHeight)
                    .background(Capsule(style: .continuous).fill(Theme.Colors.accentFill))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("squad.shareInvite")

            if !backendConnected {
                Text(Copy.squad.inviteOfflineNote)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
        .task(id: copiedTick) {
            guard copiedTick > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            showCopied = false
        }
    }
}

#Preview {
    NavigationStack { SquadHomeView() }
        .environment(AppRouter.shared)
}
