// Screen11Commitment.swift
// App / Features / Onboarding
//
// Owned by: this session's task (Screens 9-14 + OnboardingContainerView). See
// `Screen9WakeUp.swift`'s header for the full `Copy.onboarding.*` / `OnboardingFlowState` assumed
// API this file depends on.
//
// docs/spec.md §7.11 "Commitment": '"Hold to commit" 2-second press with haptics. Records
// committed_at.' Uses `PrimaryButton`'s `.holdToCommit` style exactly as built
// (`Core/Sources/Core/UI/Components/PrimaryButton.swift`: 2-second press, escalating haptics,
// fires `action` once on completion) — this screen supplies no timing/haptics of its own.
//
// `committed_at` has no column in docs/spec.md §13's `users` table. `OnboardingFlowState.swift`
// (sibling-owned, read but never edited) already models it as `private(set) var committedAt: Date?`
// set via `recordCommitment(at:)` — this screen calls that directly (screen 11 is exactly the
// caller its own doc comment names: "screen 11 (onboarding-2) sets it") rather than writing the
// property itself, and additionally logs a durable `Analytics` event (docs/spec.md §23 "instrument
// from day one") alongside it, since a moment-in-time like this has no first-class SwiftData column
// to live in.
//
// This is also the first point in the flow that creates a real, persisted local `User` row (via
// `onboardingResolveOrCreateUser`, `OnboardingContainerView.swift`) — "committing" is the moment
// onboarding's answers stop being scratch state and become the user's actual account, matching
// docs/spec.md §8 rule 11 ("Endowed progress: streak starts at Day 1 after onboarding's first
// win") — that first win (`Screen14FirstWin.swift`) needs a real `User` to attach its `Goal`/
// `LockSet` to, and this is the natural moment to create it, one screen before permission priming
// which requests iOS-level permissions the user has, by this point, actually said yes to.

import SwiftUI
import SwiftData
import Core

@MainActor
struct Screen11Commitment: View {
    @Bindable var flowState: OnboardingFlowState

    @Environment(\.modelContext) private var modelContext
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.onboarding.commitEyebrow)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .textCase(.uppercase)

                Text(Copy.onboarding.commitHeadline)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)

                Text(Copy.onboarding.commitSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Text(recapLine)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.surface2, in: Capsule())

            Spacer(minLength: Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.xs) {
                PrimaryButton(
                    title: Copy.onboarding.commitHoldButtonLabel,
                    style: .holdToCommit
                ) {
                    commit()
                }
                Text(Copy.onboarding.commitHoldHint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .alert(
            "",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in if !isPresented { saveErrorMessage = nil } }
            )
        ) {
            Button(Copy.common.ok, role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var recapLine: String {
        let selection = flowState.selectedApps
        let appCount = selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
        let goalCount = flowState.mainGoal == .allOfIt ? 3 : 1
        return Copy.onboarding.commitRecapLine(goalCount: goalCount, appCount: appCount)
    }

    /// Fires once `PrimaryButton`'s 2-second hold completes. Persists the commitment moment (see
    /// file header) and advances — this never fails the *flow* even if the local save throws
    /// (shown as a dismissible alert instead): a user who has just deliberately held a button for
    /// two seconds to commit should not be stuck on this screen over a SwiftData write error.
    private func commit() {
        flowState.recordCommitment()
        Analytics.shared.capture(
            event: "onboarding_committed",
            properties: ["main_goal": flowState.mainGoal?.rawValue ?? "unspecified"]
        )
        do {
            _ = try onboardingResolveOrCreateUser(coachVoice: flowState.coachVoice, in: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        flowState.advance()
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen11Commitment(flowState: flowState)
    }
    .modelContainer(for: User.self, inMemory: true)
}
