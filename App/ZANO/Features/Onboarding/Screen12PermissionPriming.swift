// Screen12PermissionPriming.swift
// App / Features / Onboarding
//
// Owned by: this session's task (Screens 9-14 + OnboardingContainerView). See
// `Screen9WakeUp.swift`'s header for the full `Copy.onboarding.*` / `OnboardingFlowState` assumed
// API this file depends on.
//
// docs/spec.md §7.12 "Permission priming": 'Notifications (one screen: "We'll only nudge when it
// matters"). Location and Health are requested later, at gym setup, not here.' This file
// deliberately requests ONLY notifications — no `CLLocationManager`/`HKHealthStore` calls belong
// here, matching that line exactly. (Family Controls authorization is Screen 4's job, priming Q2's
// app picker — also not this file's concern.)
//
// `UserNotifications` is a first-party framework, not UIKit, so this stays within CLAUDE.md's
// "No UIKit unless an Apple API requires it."

import SwiftUI
import UserNotifications
import Core

@MainActor
struct Screen12PermissionPriming: View {
    @Bindable var flowState: OnboardingFlowState

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xl)

            ZStack {
                Circle()
                    .fill(Theme.Colors.surface2)
                    .frame(width: 96, height: 96)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.onboarding.permissionEyebrow)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .textCase(.uppercase)

                Text(Copy.onboarding.permissionHeadline)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)

                Text(Copy.onboarding.permissionSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                PrimaryButton(
                    title: Copy.onboarding.permissionAllowButton,
                    isEnabled: !isRequesting
                ) {
                    requestNotificationAuthorization()
                }

                Button {
                    flowState.advance()
                } label: {
                    Text(Copy.onboarding.permissionSkipButton)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    /// Advances the flow regardless of the system prompt's outcome (granted, denied, or already
    /// determined from a previous install): spec §8 rule 12 ("friction is the feature, but only
    /// where the user asked for it") — a denied notification permission is not a lock, so
    /// onboarding must never stall on it. `.badge`/`.sound`/`.alert` cover every nudge format spec
    /// §9.3's Nudge Optimizer can eventually send (push, one of its three delivery `NudgeFormat`s).
    private func requestNotificationAuthorization() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isRequesting = false
            flowState.advance()
        }
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen12PermissionPriming(flowState: flowState)
    }
}
