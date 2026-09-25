// ManualCheckInSheet.swift
// App / ZANO / Features / GymSetup
//
// spec §24 "Location: … Provide a manual check-in fallback." and §3's verification philosophy
// ("Tier C goals are allowed because the point is friction and accountability, not
// surveillance"). An honest Tier C check-in for the gym goal: it says plainly that it counts and
// that it's flagged as manual, the friction is a hold (`PrimaryButton(.holdToCommit)`, like
// Tier C's "10-sec hold" friction elsewhere), and it's limited to one a day.
//
// The write goes through `GymVerifier.recordManualCheckIn(gymID:)` — a verified `.complete`
// `GoalEvent` with `source: .manual` and `meta: {"tier": "C"}`, then
// `GoalCompletionCoordinator.goalEventRecorded(goalID:)` — so there is one write path for it
// (an App Intent or NFC action can call the same method).

import SwiftUI
import SwiftData
import Core

public struct ManualCheckInSheet: View {
    private let gymID: UUID?
    private let onRecorded: () -> Void

    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query private var todaysEvents: [GoalEvent]
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var outcome: GymManualCheckInResult?
    @State private var successTick = 0

    /// - Parameters:
    ///   - gymID: The gym being checked into, recorded in the event's `meta` (optional).
    ///   - onRecorded: Called once after a successful check-in, before the sheet closes itself.
    public init(gymID: UUID? = nil, onRecorded: @escaping () -> Void = {}) {
        self.gymID = gymID
        self.onRecorded = onRecorded
        let startOfDay = Calendar.current.startOfDay(for: .now)
        _todaysEvents = Query(filter: #Predicate<GoalEvent> { $0.ts >= startOfDay })
    }

    private var gymGoal: Goal? {
        activeGoals.filter { $0.type == .workoutGym }.max { $0.createdAt < $1.createdAt }
    }

    /// Why the hold isn't offered, if it isn't — checked up front so nobody holds for 2 s to be
    /// told no. `GymVerifier` re-checks on write.
    private var blocker: String? {
        guard let goalID = gymGoal?.id else { return Copy.gym.manualNoGoal }
        let todays = todaysEvents.filter { $0.goal?.id == goalID && $0.kind == .complete }
        if todays.contains(where: { $0.source == .manual }) { return Copy.gym.manualUsedToday }
        if todays.contains(where: \.verified) { return Copy.gym.manualAlreadyComplete }
        return nil
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    IconBadge(systemName: "hand.raised.fill", tint: Theme.Colors.warning, size: .large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.md)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(Copy.gym.manualHeadline)
                            .zanoText(.titleLarge)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Copy.gym.manualMessage)
                            .zanoText(.paragraph)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        ZanoStatusCapsule(dotColor: Theme.Colors.warning, text: Copy.gym.manualTierBadge)
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Image(systemName: "1.circle")
                            .font(Theme.Typography.icon(.small))
                            .foregroundStyle(Theme.Colors.muted)
                            .accessibilityHidden(true)
                        Text(Copy.gym.manualRule)
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .zanoActionBar { actionBar }
            .zanoBackdrop()
            .navigationTitle(Copy.gym.manualTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: successTick)
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let message = failureMessage ?? blocker {
                Text(message)
                    .zanoText(.captionEmphasized)
                    .foregroundStyle(blocker == nil ? Theme.Colors.danger : Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if blocker == nil {
                PrimaryButton(
                    title: Copy.gym.manualHoldButton,
                    systemImage: "hand.raised.fill",
                    style: .holdToCommit,
                    isEnabled: !isSaving
                ) {
                    Task { await commit() }
                }
            } else {
                PrimaryButton(title: Copy.gym.doneButton, style: .secondary) { dismiss() }
            }
        }
    }

    private var failureMessage: String? {
        outcome == .failed ? Copy.gym.manualFailed : nil
    }

    private func commit() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let result = await GymVerifier.shared.recordManualCheckIn(gymID: gymID)
        outcome = result
        guard result == .recorded else { return }
        successTick += 1
        onRecorded()
        // Let the haptic land and the hold's settle finish before the sheet goes.
        try? await Task.sleep(for: .milliseconds(450))
        dismiss()
    }
}
