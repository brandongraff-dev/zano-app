// Screen13Paywall.swift
// App / Features / Onboarding
//
// SUPERSEDED — kept on disk, fully working, as delivered per this session's literal task
// assignment ("a paywall placeholder screen with a clear extension point for the real RevenueCat
// wiring"), but **not wired into the flow**. While this session was in progress, a separate
// "Monetization/Paywall" task this same batch independently built a full, real `PaywallView.swift`
// (this same directory) backed by `Core/Sources/Core/Monetization/PaywallViewModel.swift` — real
// RevenueCat offerings, purchase/restore, a `PaywallCard` component, `Copy.paywall.*` — strictly
// more complete than this placeholder. `OnboardingContainerView.swift` (this session's own file)
// routes its screen-13 case to `PaywallView`, not this file — see that file's header for the full
// note. Left here rather than deleted so the orchestrator can compare/reconcile; not dead-stub
// code, just dead-*wiring* — every line below still compiles and runs standalone (see `#Preview`).
//
// Owned by: this session's task (Screens 9-14 + OnboardingContainerView). See
// `Screen9WakeUp.swift`'s header for the full `Copy.onboarding.*` / `OnboardingFlowState` assumed
// API this file depends on.
//
// docs/spec.md §7.13 "Paywall": 'Free trial (7 days) with "we'll remind you 2 days before it
// ends." Annual highlighted. Clear "Continue with limited free" option below (1 goal, 1 lock
// set).' Prices/periods are docs/spec.md §21's own test values ("$6.99/mo, $39.99/yr (highlight),
// $59.99 lifetime (test only)") — this is a **placeholder**, not real StoreKit/RevenueCat
// integration (see the extension point below).
//
// RevenueCat extension point: `docs/dependencies.md`/`docs/PROGRESS.md` list the RevenueCat SPM
// package as not yet added to `project.yml` (needed starting this session per §17 Session 6), and
// there is no Core `Monetization`/`Purchases` module in this batch's SYSTEM CONTRACTS for this
// file to call into. This mirrors the exact pattern `App/ZANO/ZANOApp.swift` already established
// for PostHog/Sentry: every call that would touch the real SDK is guarded by
// `#if canImport(RevenueCat)` so this file compiles and runs today (falling through to "continue
// as if the free trial started" — never a dead end) and starts actually purchasing the moment a
// future session adds the package and a `PurchasesManager`-style wrapper. `selectedPlan`'s
// `productIdentifier` is exactly the string a `Purchases.shared.purchase(package:)` call would key
// off of once that wrapper exists — TODO(cross-module, future Monetization session).
//
// `Never sell unlocks, streak restores, or anything that lets money bypass the goal` (spec §21) —
// this screen only ever gates *convenience* (goal/lock-set limits, adaptive plan, Earn Mode,
// protein photo AI, recaps, squads/duels, extra freezes, cosmetics per spec §21's Free/Pro split),
// never a verified goal completion or an unlock itself.

import SwiftUI
import Core
import os

#if canImport(RevenueCat)
import RevenueCat
#endif

@MainActor
struct Screen13Paywall: View {
    @Bindable var flowState: OnboardingFlowState

    @State private var selectedPlan: PaywallPlan = .annual
    @State private var isPurchasing = false

    private static let logger = Logger(subsystem: "com.zano.app", category: "OnboardingPaywall")

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(PaywallPlan.allCases) { plan in
                        planCard(plan)
                    }
                }

                Text(Copy.onboarding.paywallTrialReminder)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)

                PrimaryButton(
                    title: Copy.onboarding.paywallCTAButton,
                    isEnabled: !isPurchasing
                ) {
                    startTrial()
                }

                VStack(spacing: Theme.Spacing.xxs) {
                    Button {
                        continueWithFreeTier()
                    } label: {
                        Text(Copy.onboarding.paywallContinueFreeButton)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.text)
                            .underline()
                    }
                    .buttonStyle(.plain)

                    Text(Copy.onboarding.paywallFreeTierDetail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }

                Text(Copy.onboarding.paywallAutoRenewDisclaimer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Theme.Spacing.lg)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(Copy.onboarding.paywallHeadline)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
            Text(Copy.onboarding.paywallSubtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let isSelected = plan == selectedPlan
        return Button {
            withAnimation(Theme.Motion.springStandard) { selectedPlan = plan }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.muted)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Text(plan.label)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.background)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accent, in: Capsule())
                        }
                    }
                    if let subtext = plan.subtext {
                        Text(subtext)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }

                Spacer(minLength: 0)

                Text(plan.priceText)
                    .font(Theme.Typography.numeralSmall())
                    .foregroundStyle(Theme.Colors.text)
            }
            .padding(Theme.Spacing.md)
            .background(
                isSelected ? Theme.Colors.surface2 : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startTrial() {
        guard !isPurchasing else { return }
        isPurchasing = true
        Analytics.shared.capture(
            event: "onboarding_paywall_trial_started",
            properties: ["product": selectedPlan.productIdentifier]
        )

        #if canImport(RevenueCat)
        // TODO(cross-module, future Monetization session — see file header): replace with a real
        // `Purchases.shared.purchase(package:)` call once a `PurchasesManager` wrapper exists,
        // mirroring `Analytics`/`CrashReporting`'s own `#if canImport` no-op-until-linked pattern.
        Self.logger.notice("RevenueCat SDK present but no PurchasesManager wired yet; advancing without a real purchase.")
        #endif

        isPurchasing = false
        flowState.advance()
    }

    private func continueWithFreeTier() {
        Analytics.shared.capture(event: "onboarding_paywall_continue_free")
        flowState.advance()
    }
}

/// Spec §21's three price-test points. `productIdentifier` stands in for the real App Store
/// Connect product id a `PurchasesManager` would resolve once RevenueCat is wired (see file
/// header) — file-scoped since nothing outside this screen needs it.
private enum PaywallPlan: String, CaseIterable, Identifiable {
    case monthly
    case annual
    case lifetime

    var id: String { rawValue }

    var productIdentifier: String {
        switch self {
        case .monthly: "com.zano.app.pro.monthly"
        case .annual: "com.zano.app.pro.annual"
        case .lifetime: "com.zano.app.pro.lifetime"
        }
    }

    var label: String {
        switch self {
        case .monthly: Copy.onboarding.paywallMonthlyLabel
        case .annual: Copy.onboarding.paywallAnnualLabel
        case .lifetime: Copy.onboarding.paywallLifetimeLabel
        }
    }

    var badge: String? {
        self == .annual ? Copy.onboarding.paywallAnnualBadge : nil
    }

    /// Spec §21 test prices, shown as placeholder text until real localized `StoreKit`/RevenueCat
    /// pricing replaces it (see file header) — not `Copy` module content, since these are specific
    /// product-price data points, not personality-driven UX copy.
    var priceText: String {
        switch self {
        case .monthly: "$6.99/mo"
        case .annual: "$39.99/yr"
        case .lifetime: "$59.99"
        }
    }

    var subtext: String? {
        switch self {
        case .monthly: nil
        case .annual: Copy.onboarding.paywallPriceSuffix(period: "yr")
        case .lifetime: Copy.onboarding.paywallPriceSuffix(period: "once")
        }
    }
}

#Preview {
    let flowState = OnboardingFlowState()
    return OnboardingScaffold(flowState: flowState) {
        Screen13Paywall(flowState: flowState)
    }
}
