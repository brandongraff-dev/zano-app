// FamilyRewardPresenter.swift
// App / ZANO / Features / Family
//
// The teen's side of parent reward minutes (session 45; docs/spec.md §5.23, §5.2). On every foreground it
// looks for rewards a linked parent sent and hasn't been added yet, and shows them one at a time as a small
// celebratory card: the buddy, the parent's note, "+30 min for your Time Bank". "Add to my Time Bank" claims
// it on the server and deposits it as minutes from family (`FamilyRewardClaim`), which expire at midnight
// like every other Time Bank minute. "Later" just closes the card; it comes back next time.
//
// Does nothing at all unless Family Link is live (`FamilyLinkAvailability.isLive`: backend keys AND signed
// in) and the client is configured, and never on a parent's device (the card is only for rewards addressed to
// the signed-in person). Never over the alarm, the unlock celebration or a milestone moment.
//
// Hooks (applied by the shell):
//   - `.zanoFamilyRewards()` on `MainTabView`.
//   - `FamilyRewardPresenter.shared.check()` on every foreground.

import SwiftUI
import os
import Core

@MainActor
@Observable
final class FamilyRewardPresenter {
    static let shared = FamilyRewardPresenter()

    /// The reward on the card, `nil` when there is none.
    private(set) var pending: FamilyReward?
    /// Set once the minutes are in the bank: the card shows "+30 min added" and a Done button.
    private(set) var addedMinutes: Int?
    private(set) var message: String?
    private(set) var isWorking = false

    @ObservationIgnored private var link: FamilyLink?
    @ObservationIgnored private var queue: [FamilyReward] = []
    /// "Later" on these this session: not shown again until the next launch.
    @ObservationIgnored private var skipped: Set<UUID> = []
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.zano.app", category: "FamilyRewardPresenter")

    /// Fetches unclaimed rewards for the signed-in teen. Cheap and silent: any failure just shows nothing.
    func check() async {
        guard ScreenshotMode.screen == nil, FamilyLinkAvailability.isLive, AppRouter.shared.hasCompletedOnboarding else { return }
        guard pending == nil, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let client = FamilyLinkClient.shared
        guard await client.isConfigured, let me = await client.currentUserID() else { return }
        do {
            guard let active = try await client.links().first(where: { $0.status == .active && $0.teenId == me }) else { return }
            let rewards = try await client.rewards(linkID: active.id)
            link = active
            queue = FamilyRewardRules.claimable(rewards, link: active, teenID: me)
                .filter { !skipped.contains($0.id) && !FamilyRewardLedger.hasDeposited($0.id) }
            advance()
        } catch {
            logger.info("Family reward check failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// What the card should show right now, or `nil` while anything outranks it.
    func presentable(router: AppRouter) -> FamilyReward? {
        guard let pending,
              router.unlockCelebration == nil,
              !router.isAlarmRingingPresented,
              MilestonePresenter.shared.presentableMilestone(router: router) == nil else { return nil }
        return pending
    }

    func claim() async {
        guard let reward = pending, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let result = try await FamilyRewardClaim.claimAndDeposit(reward, link: link) { id in
                try await FamilyLinkClient.shared.claimReward(rewardID: id)
            }
            switch result {
            case .deposited(let minutes):
                addedMinutes = minutes
            case .alreadyDeposited:
                message = Copy.family.rewardAlreadyAdded
            }
        } catch {
            message = Copy.family.error(error)
        }
    }

    /// "Later", or closing the card after a void/duplicate: move on without claiming.
    func later() {
        if let pending, addedMinutes == nil { skipped.insert(pending.id) }
        advance()
    }

    /// "Done" after the minutes were added, or SwiftUI dismissing the sheet.
    func close() {
        if addedMinutes == nil, let pending { skipped.insert(pending.id) }
        advance()
    }

    private func advance() {
        addedMinutes = nil
        message = nil
        pending = queue.isEmpty ? nil : queue.removeFirst()
    }
}

// MARK: - Presentation

extension View {
    /// Presents the teen's reward card (`FamilyRewardPresenter`). Apply once, on the tab UI.
    func zanoFamilyRewards() -> some View {
        modifier(FamilyRewardsModifier())
    }
}

private struct FamilyRewardsModifier: ViewModifier {
    func body(content: Content) -> some View {
        let presenter = FamilyRewardPresenter.shared
        let item = presenter.presentable(router: AppRouter.shared)
        content
            .sheet(item: Binding<FamilyReward?>(
                get: { item },
                // A swipe-down closes the card that was showing. After Done/Later the presenter has already
                // moved on, so a late `nil` write must not skip the next reward.
                set: { newValue in
                    if newValue == nil, let shown = item, presenter.pending?.id == shown.id { presenter.close() }
                }
            )) { reward in
                FamilyRewardCardView(reward: reward, presenter: presenter)
                    .presentationDetents([.medium])
            }
    }
}

/// The celebratory card: the buddy, the parent's note, the minutes. One VoiceOver element for the message.
struct FamilyRewardCardView: View {
    let reward: FamilyReward
    let presenter: FamilyRewardPresenter

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            StoredBuddySprite(pose: presenter.addedMinutes == nil ? .idle : .ecstatic, size: 96)
            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.family.rewardCardTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                Text(presenter.addedMinutes.map { Copy.family.rewardAdded($0) } ?? Copy.family.rewardWaiting(reward.minutes))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                if let note = reward.note, !note.isEmpty {
                    // Plain text only: shown verbatim, never as Markdown or a link.
                    Text(verbatim: "\u{201C}\(note)\u{201D}")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Text(presenter.message ?? Copy.family.rewardCardExpiry)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if presenter.addedMinutes != nil || presenter.message != nil {
                PrimaryButton(title: Copy.common.done) { presenter.close() }
            } else {
                PrimaryButton(title: Copy.family.rewardCardClaim, systemImage: "plus.circle.fill", isEnabled: !presenter.isWorking) {
                    Task { await presenter.claim() }
                }
                PrimaryButton(title: Copy.family.rewardCardLater, style: .secondary) { presenter.later() }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}
