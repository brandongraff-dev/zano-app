// FinishTrialBanner.swift
// App / ZANO / Features / Paywall
//
// The soft "Finish starting your trial" banner (audit M2, 2026-10-02). Shown while the user is in
// the app on the paywall's grace period (`SubscriptionGate.hasPendingTrialStart`: plans couldn't
// load during onboarding, so they continued without a trial). One quiet row, no countdown styling,
// no guilt; tapping it opens the paywall in a sheet (`PaywallView(context: .grace)`), which
// dismisses itself once the trial starts. Draws nothing otherwise, so a host can place it
// unconditionally.
//
// Placement (hosts are owned elsewhere): Today, top of the scroll content; Settings, above the plan
// card. One line each: `FinishTrialBanner()`.

import SwiftUI
import Core

struct FinishTrialBanner: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPending = false
    @State private var daysLeft = 0
    @State private var isPaywallPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if isPending {
                banner
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            reload()
        }
        .sheet(isPresented: $isPaywallPresented, onDismiss: reload) {
            PaywallView(flowState: OnboardingFlowState(), context: .grace)
                .overlay(alignment: .topTrailing) {
                    Button(Copy.paywall.closeButtonLabel) { isPaywallPresented = false }
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minWidth: Theme.Metrics.minTapTarget, minHeight: Theme.Metrics.minTapTarget)
                        .padding(.trailing, Theme.Spacing.sm)
                }
        }
    }

    private var banner: some View {
        Button {
            Analytics.shared.capture(event: "finish_trial_banner_tapped", properties: ["days_left": daysLeft])
            isPaywallPresented = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(Theme.Typography.icon(.small, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.accentWash, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.paywall.finishTrialBannerTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.paywall.finishTrialBannerDetail(daysLeft: daysLeft))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .zanoCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.paywall.finishTrialBannerSpoken)
    }

    private func reload() {
        isPending = SubscriptionGate.hasPendingTrialStart()
        daysLeft = SubscriptionGate.graceDaysLeft()
    }
}

#Preview {
    FinishTrialBanner()
        .padding()
        .background(Theme.Colors.background)
}
