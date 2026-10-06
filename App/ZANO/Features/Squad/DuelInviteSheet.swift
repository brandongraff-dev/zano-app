// DuelInviteSheet.swift
// App / ZANO / Features / Squad
//
// "Start a duel" (docs/spec.md §5.7): the solo "Beat last week" duel, always available and
// offline, plus a head-to-head challenge per squadmate. A challenge is a `.pending` duel the
// opponent must accept on their phone, which only the backend can relay, so while squads aren't
// live the challenge buttons are disabled and say why.

import SwiftUI
import Core

struct DuelInviteSheet: View {
    let model: SquadHomeModel

    @Environment(\.dismiss) private var dismiss
    @State private var showSolo = false
    @State private var workingOn: UUID?
    @State private var message: String?
    @State private var sentTick = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(Copy.squad.inviteSheetBody)
                        .zanoText(.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button { showSolo = true } label: { soloOption }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("squad.soloDuel")

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SquadSectionLabel(text: Copy.squad.friendsSectionTitle)
                        if model.otherMembers.isEmpty {
                            Text(model.backendConnected ? Copy.squad.noSquadmates : Copy.squad.challengeOffline)
                                .zanoText(.caption)
                                .foregroundStyle(Theme.Colors.muted)
                                .padding(Theme.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .zanoCard()
                        } else {
                            ForEach(model.otherMembers) { member in
                                friendRow(member)
                            }
                            if !model.backendConnected {
                                Text(Copy.squad.challengeOffline)
                                    .zanoText(.caption)
                                    .foregroundStyle(Theme.Colors.muted)
                            }
                        }
                    }

                    if let message {
                        Text(message)
                            .zanoText(.captionEmphasized)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .transition(.opacity)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle(Copy.squad.inviteSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.squad.cancel) { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showSolo) { SoloDuelView() }
            .sensoryFeedback(.success, trigger: sentTick)
        }
        .presentationDragIndicator(.visible)
    }

    private var soloOption: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            IconBadge(systemName: "figure.run", tint: Theme.Colors.accent)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(Copy.squad.soloOptionTitle)
                        .zanoText(.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.squad.worksOffline)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                Text(Copy.squad.soloOptionBody)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(tint: Theme.Colors.accent)
        .accessibilityElement(children: .combine)
    }

    private func friendRow(_ member: SquadMemberRow) -> some View {
        let alreadyDueling = model.duels.contains { duel in
            (duel.status == .pending || duel.status == .active) && (duel.aUser == member.userID || duel.bUser == member.userID)
        }
        let enabled = model.backendConnected && !alreadyDueling && workingOn == nil
        return HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "person", tint: Theme.Colors.textSecondary, size: .small)
            Text(member.name)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)
            Spacer(minLength: Theme.Spacing.xs)
            Button {
                challenge(member)
            } label: {
                Group {
                    if workingOn == member.userID {
                        SwiftUI.ProgressView().controlSize(.small)
                    } else {
                        Text(alreadyDueling ? Copy.squad.activeStatus : Copy.squad.challengeButton)
                            .font(Theme.Typography.captionEmphasized)
                    }
                }
                .foregroundStyle(enabled ? Theme.Colors.onAccent : Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 34)
                .background(Capsule(style: .continuous).fill(enabled ? Theme.Colors.accentFill : Theme.Colors.surface2))
                .frame(minHeight: Theme.Metrics.minTapTarget)
            }
            .buttonStyle(.pressable(scale: 0.94))
            .disabled(!enabled)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .zanoCard()
    }

    private func challenge(_ member: SquadMemberRow) {
        workingOn = member.userID
        Task { @MainActor in
            do {
                try await model.challenge(member.userID)
                message = Copy.squad.challengeSent
                sentTick += 1
            } catch {
                message = SquadHomeModel.message(for: error)
            }
            workingOn = nil
        }
    }
}
