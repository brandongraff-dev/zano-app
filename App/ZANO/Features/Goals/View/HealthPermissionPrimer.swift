// HealthPermissionPrimer.swift
// App / Features / Goals / View
//
// Explains why ZANO reads Apple Health before iOS's own sheet appears (docs/spec.md §3: steps,
// home workouts, and sleep verify automatically; §24: Health data stays on device, read-only).
// Requests only the read types the user's active goals use (`HealthAuthorization.requestRead`).
//
// Health read permission is opaque: iOS never tells an app what was allowed. So "finished" can't
// mean "granted" — the done state says so and shows where to change it. A goal whose data is
// denied just never verifies; the emergency unlock keeps that from ever trapping anyone.
//
// Presented as a sheet (from the goal picker's next step or an editor card). `onFinished` is
// called when the user is done here, whatever they chose.

import SwiftUI
import SwiftData
import Core

struct HealthPermissionPrimer: View {
    let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    private enum Phase: Equatable {
        case intro, requesting, finished, unavailable, failed
    }

    @Query private var goals: [Goal]
    @State private var phase: Phase = HealthAuthorization.isAvailable ? .intro : .unavailable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The active goals' Health-using types; if there are none (primer opened on its own), every
    /// type that uses Health.
    private var requestedTypes: [GoalType] {
        let active = Set(goals.filter(\.active).map(\.type)).filter(HealthAuthorization.usesHealth)
        if !active.isEmpty { return Array(active) }
        return GoalType.allCases.filter(HealthAuthorization.usesHealth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                hero
                content
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xl)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: phase)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { actions }
        .zanoBackdrop(glow: Theme.Colors.accent)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: phase == .finished)
        .onAppear { Analytics.shared.capture(event: "health_primer_viewed") }
    }

    // MARK: - Sections

    private var hero: some View {
        GoalRing(
            progress: phase == .finished ? 1 : 0.72,
            color: Theme.Colors.accent,
            size: .medium,
            center: .icon(systemName: phase == .finished ? "checkmark" : "heart.fill")
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro, .requesting, .failed:
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.goals.healthTitle)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.goals.healthMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                point(systemImage: "eye", text: Copy.goals.healthPointReadOnly)
                point(systemImage: "iphone", text: Copy.goals.healthPointOnDevice)
                point(systemImage: "checklist", text: Copy.goals.healthPointOnlyNeeded)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
            if phase == .failed {
                Text(Copy.goals.healthFailedMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .finished:
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.goals.healthDoneTitle)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.goals.healthDoneMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            howToEnable

        case .unavailable:
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.goals.healthUnavailableTitle)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.goals.healthUnavailableMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var howToEnable: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.goals.healthHowToEnableTitle)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
            Text(Copy.goals.healthHowToEnableSteps)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
        .accessibilityElement(children: .combine)
    }

    private func point(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            switch phase {
            case .intro, .requesting, .failed:
                PrimaryButton(
                    title: phase == .failed ? Copy.goals.healthTryAgainButton : Copy.goals.healthContinueButton,
                    isEnabled: phase != .requesting
                ) {
                    request()
                }
                PrimaryButton(title: Copy.goals.healthNotNowButton, style: .secondary) {
                    Analytics.shared.capture(event: "health_primer_skipped")
                    onFinished()
                }
            case .finished, .unavailable:
                PrimaryButton(title: Copy.common.done) { onFinished() }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - Request

    private func request() {
        phase = .requesting
        let types = requestedTypes
        let stepsGoalIDs = goals.filter { $0.active && $0.type == .steps }.map(\.id)
        Task {
            do {
                try await HealthAuthorization.requestRead(for: types)
                Analytics.shared.capture(
                    event: "health_primer_requested",
                    properties: ["types": types.map(\.rawValue).sorted().joined(separator: ",")]
                )
                for id in stepsGoalIDs {
                    GoalVerificationStarter.startIfReady(goalID: id, type: .steps)
                }
                phase = .finished
            } catch HealthAuthorizationError.unavailable {
                phase = .unavailable
            } catch {
                phase = .failed
            }
        }
    }
}

#Preview {
    HealthPermissionPrimer(onFinished: {})
        .modelContainer(for: [User.self, Goal.self], inMemory: true)
}
