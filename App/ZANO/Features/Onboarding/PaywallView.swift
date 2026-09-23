// PaywallView.swift
// App / Features / Onboarding
//
// Owned by: this task (Monetization/Paywall). Do not edit from another session — see CLAUDE.md
// "Stay strictly inside your assigned file list." This is screen 13 of 14 in the onboarding flow
// (docs/spec.md §7.13): "Paywall — Free trial (7 days) with 'we'll remind you 2 days before it
// ends.' Annual highlighted. Clear 'Continue with limited free' option below (1 goal, 1 lock
// set)." Layout follows §16's P5 mockup: headline, three benefit rows with icons, an annual plan
// card highlighted with its price + monthly-equivalent + trial note, a smaller monthly option,
// a trial-reminder note, and a "Continue with limited free" text link. Copy rules are spec §21's:
// "benefits in the user's words from onboarding; show the plan they built; social proof; clear
// free path; no dark patterns."
//
// State lives in `PaywallViewModel` (`Core/Sources/Core/Monetization/PaywallViewModel.swift`,
// this same task's other owned file) — this view is presentation only.
//
// Onboarding flow integration: `OnboardingFlowState` (`App/ZANO/Features/Onboarding/
// OnboardingFlowState.swift`) is owned by the sibling "screens 1-8" session, not this task, but
// its header comment names this file's screen 13 as a slot every sibling screen integrates with
// the same way — `@Bindable var flowState: OnboardingFlowState`, mutating only
// `flowState.currentScreen` via `flowState.advance()`/`.goBack()`, per that file's own navigation
// contract. This screen additionally reads (never writes) `flowState.coachVoice` — the Q6 answer
// (spec §7.8) — to seed `PaywallViewModel`'s voice before `User.coachVoice`/`SharedDefaults.
// coachVoice` are necessarily populated yet at this point in a fresh onboarding run (see
// `PaywallViewModel.coachVoice`'s own doc comment). This file never mutates `OnboardingFlowState`
// itself beyond calling its existing `advance()`.
//
// ASSUMED API — this task's owned files do not include `Core/Sources/Core/Copy` or
// `Core/Sources/Core/UI`'s component catalog (spec §15 names both as other sessions' build
// targets), so — following the exact same cross-session pattern already merged into this repo
// (`App/ZANO/Features/LockSetup/LockSetupView.swift`'s `Copy.lockSetup`/`LockSetManager`
// assumptions; `App/ZANO/Features/Onboarding/Screen3MainGoal.swift`'s `Copy.onboarding`/
// `OnboardingQuestion` assumptions) — this file calls things that don't exist on disk yet:
//
// 1. `Copy.paywall.*` / `Copy.common.ok` — plain string (or small formatting-function) members on
//    the `Copy` namespace (`Core/Sources/Core/Copy`). Full key list this file uses:
//      common: ok  (already assumed elsewhere — reused, not redefined)
//      paywall: headline, benefitUnlimitedGoalsTitle, benefitAdaptivePlanTitle,
//        benefitSquadsDuelsTitle, yourPlanSectionTitle, lockSetSummary(name: String) -> String,
//        annualBadgeLabel, annualPriceLine(price: String) -> String,
//        monthlyPriceLine(price: String) -> String,
//        annualDetailLine(perMonth: String, trialDays: Int) -> String,
//        trialDaysLabel(_ days: Int) -> String, trialReminderNote(daysBefore: Int) -> String,
//        annualPlanTitle, monthlyPlanTitle, weeklyPlanTitle, lifetimePlanTitle,
//        startTrialButtonLabel(trialDays: Int) -> String, subscribeButtonLabel,
//        restorePurchasesButtonLabel, continueWithLimitedFreeLink, retryButtonLabel, errorTitle.
//    `headline` is spec-verbatim (§16 P5: "Earn your phone back"); the rest is this task's
//    authored copy (spec gives subjects, e.g. "three benefit rows with icons... Unlimited goals &
//    lock sets, Adaptive plan that learns you, Squads & duels", not exact final wording beyond
//    those three phrases, which the three `benefit*Title` keys reproduce verbatim) — free to
//    revise once a copy owner exists; nothing here depends on exact wording, only that the keys
//    exist and return non-empty strings.
//
// 2. `PaywallCard` (spec §15's "Core components (build first, in Core/UI)" list names it by
//    name, with no defined initializer — same situation as `OnboardingQuestion`/`PrimaryButton`
//    were for the screens-1-8 session). Assumed shape, kept as simple as the mockup needs:
//      struct PaywallCard: View {
//          init(
//              title: String,           // "Annual" / "Monthly" — plan name, this file's own copy
//              priceLine: String,       // e.g. "$39.99/yr" — already fully composed
//              detailLine: String?,     // e.g. "$3.33/mo · 7 days free" — already fully composed
//              badgeLabel: String?,     // e.g. "BEST VALUE" — nil for the non-highlighted plan
//              isHighlighted: Bool,     // true for the annual card (spec §16 P5: "highlighted")
//              isSelected: Bool,        // drives selection chrome (border/checkmark)
//              action: @escaping () -> Void
//          )
//      }
//    `title`/`priceLine`/`detailLine`/`badgeLabel` are fully pre-composed strings from
//    `Copy.paywall.*` (see key list above) rather than raw parts (a price `Decimal`, a plan enum,
//    etc.), so `PaywallCard` itself never needs to know about `SubscriptionPackage` or compose
//    copy — it stays a pure display component, matching every other `Core/UI/Components` file's
//    existing "all text is caller-supplied" convention (see e.g. `GoalRow.swift`'s header note).
//
// `PrimaryButton` and `GoalRow` are **not** assumed here — both already exist for real in
// `Core/Sources/Core/UI/Components` (this task read them before writing this file) and are used
// with their actual shipped signatures below: `init(title: String, systemImage: String? = nil,
// style: Style = .standard, isEnabled: Bool = true, action: @escaping () -> Void)` — a **labeled**
// `title:` parameter.
//
// RESOLVED (repo-wide Copy/API sweep, 2026-09-22): this note originally flagged that
// `Screen1Hook.swift`/`Screen3MainGoal.swift`/`Screen5PhoneTime.swift` called `PrimaryButton`
// positionally (`PrimaryButton(Copy...., ...)`), matching a guessed unlabeled-first-parameter
// shape from before the real component existed, which would not have compiled against the real,
// labeled initializer above. Re-checked by this sweep: all three call sites now pass `title:`
// explicitly and match the real signature — already fixed (by another session, between this
// note's original writing and this sweep), not by this change.

import SwiftUI
import Core

/// Screen 13 of 14 (spec §7.13) — the paywall. Presents RevenueCat offerings via
/// `PaywallViewModel`, defaults to the annual plan selected (spec §21 "annual highlighted"), and
/// always leaves two ways forward: purchase/start trial, or "Continue with limited free" — never
/// a dead end (spec §21 "no dark patterns", "clear free path").
struct PaywallView: View {
    @Bindable var flowState: OnboardingFlowState
    /// Constructed with every default (including `coachVoice: nil`, which reads
    /// `SharedDefaults.coachVoice`) rather than through a custom `init(flowState:)` — `.task`
    /// below overwrites `viewModel.coachVoice` with `flowState.coachVoice` before calling
    /// `load()`. Deliberately not a custom `View.init`: constructing an `@MainActor`-isolated
    /// `@Observable` type (`PaywallViewModel`) from a `View`'s own `init` relies on global-actor
    /// inference reasoning this task's no-Mac/no-compiler environment can't verify (see
    /// knownIssues); this `@State` default-value form is the same standard, textbook
    /// `@Observable`-with-SwiftUI idiom used throughout Apple's own sample code, so it carries
    /// far less risk either way.
    @State private var viewModel = PaywallViewModel()

    init(flowState: OnboardingFlowState) {
        self.flowState = flowState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                headline
                benefitsSection
                if let builtPlan = viewModel.builtPlan, !builtPlan.goalTitles.isEmpty {
                    builtPlanSection(builtPlan)
                }
                offeringsSection
                ctaSection
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            viewModel.coachVoice = flowState.coachVoice
            await viewModel.load()
        }
        .onChange(of: viewModel.purchaseState) { _, newValue in
            if newValue == .succeeded {
                flowState.advance()
            }
        }
        .alert(
            Copy.paywall.errorTitle,
            isPresented: Binding(
                get: {
                    if case .failed = viewModel.purchaseState { true } else { false }
                },
                set: { isPresented in
                    if !isPresented { viewModel.acknowledgePurchaseState() }
                }
            )
        ) {
            Button(Copy.common.ok, role: .cancel) { viewModel.acknowledgePurchaseState() }
        } message: {
            if case .failed(let message) = viewModel.purchaseState {
                Text(message)
            }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        Text(Copy.paywall.headline)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Benefits (spec §16 P5: three benefit rows with icons)

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            benefitRow(icon: "infinity", title: Copy.paywall.benefitUnlimitedGoalsTitle)
            benefitRow(icon: "brain.head.profile", title: Copy.paywall.benefitAdaptivePlanTitle)
            benefitRow(icon: "person.3.fill", title: Copy.paywall.benefitSquadsDuelsTitle)
        }
    }

    private func benefitRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.Colors.accent.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(width: 32, height: 32)

            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)

            Spacer(minLength: 0)
        }
    }

    // MARK: - "The plan they built" (spec §21 copy rule)

    private func builtPlanSection(_ plan: BuiltPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.paywall.yourPlanSectionTitle)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)

            if let lockSetName = plan.lockSetName {
                Text(Copy.paywall.lockSetSummary(name: lockSetName))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(plan.goalTitles, id: \.self) { title in
                    GoalRow(title: title, icon: "target", color: Theme.Colors.accent, status: .pending)
                }
            }
        }
    }

    // MARK: - Offerings (spec §21, §16 P5: annual highlighted, monthly smaller)

    @ViewBuilder
    private var offeringsSection: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .tint(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)

        case .failed(let message):
            VStack(spacing: Theme.Spacing.sm) {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                Button(Copy.paywall.retryButtonLabel) {
                    Task { await viewModel.loadOfferings() }
                }
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)

        case .loaded:
            planCards
        }
    }

    private var planCards: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(orderedPackages) { package in
                PaywallCard(
                    title: planTitle(for: package),
                    priceLine: priceLine(for: package),
                    detailLine: detailLine(for: package),
                    badgeLabel: package.period == .annual ? Copy.paywall.annualBadgeLabel : nil,
                    isHighlighted: package.period == .annual,
                    isSelected: viewModel.selectedPackageID == package.id,
                    action: { viewModel.selectPackage(id: package.id) }
                )
            }
        }
        .animation(Theme.Motion.springStandard, value: viewModel.selectedPackageID)
    }

    /// Annual first (spec §21/§16 P5: annual is the highlighted, default choice), then monthly,
    /// then whatever else the offering configures (lifetime, etc.) in their original order.
    private var orderedPackages: [SubscriptionPackage] {
        let annual = viewModel.packages.filter { $0.period == .annual }
        let monthly = viewModel.packages.filter { $0.period == .monthly }
        let rest = viewModel.packages.filter { $0.period != .annual && $0.period != .monthly }
        return annual + monthly + rest
    }

    private func planTitle(for package: SubscriptionPackage) -> String {
        switch package.period {
        case .annual: Copy.paywall.annualPlanTitle
        case .monthly: Copy.paywall.monthlyPlanTitle
        case .weekly: Copy.paywall.weeklyPlanTitle
        case .lifetime: Copy.paywall.lifetimePlanTitle
        case .twoMonth, .threeMonth, .sixMonth, .other: package.productIdentifier
        }
    }

    private func priceLine(for package: SubscriptionPackage) -> String {
        switch package.period {
        case .annual: Copy.paywall.annualPriceLine(price: package.priceString)
        case .monthly: Copy.paywall.monthlyPriceLine(price: package.priceString)
        default: package.priceString
        }
    }

    private func detailLine(for package: SubscriptionPackage) -> String? {
        if let perMonth = package.pricePerMonthString, let trialDays = package.introductoryTrialDays {
            return Copy.paywall.annualDetailLine(perMonth: perMonth, trialDays: trialDays)
        }
        if let perMonth = package.pricePerMonthString {
            return perMonth
        }
        if let trialDays = package.introductoryTrialDays {
            return Copy.paywall.trialDaysLabel(trialDays)
        }
        return nil
    }

    // MARK: - CTA / Restore / Continue free (spec §7.13, §21)

    private var ctaSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            trialReminderNote

            ZStack {
                PrimaryButton(
                    title: ctaButtonTitle,
                    isEnabled: viewModel.canAttemptPurchase,
                    action: { Task { await viewModel.purchase() } }
                )
                .opacity(viewModel.isPurchasing ? 0 : 1)

                if viewModel.isPurchasing {
                    ProgressView().tint(Theme.Colors.background)
                }
            }

            restoreButton
            continueWithLimitedFreeLink
        }
    }

    private var ctaButtonTitle: String {
        if let trialDays = viewModel.selectedPackage?.introductoryTrialDays {
            Copy.paywall.startTrialButtonLabel(trialDays: trialDays)
        } else {
            Copy.paywall.subscribeButtonLabel
        }
    }

    @ViewBuilder
    private var trialReminderNote: some View {
        if viewModel.selectedPackage?.introductoryTrialDays != nil {
            Text(Copy.paywall.trialReminderNote(daysBefore: PaywallViewModel.trialReminderDaysBefore))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await viewModel.restore() }
        } label: {
            if viewModel.isRestoring {
                ProgressView().tint(Theme.Colors.muted)
            } else {
                Text(Copy.paywall.restorePurchasesButtonLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRestoring)
    }

    private var continueWithLimitedFreeLink: some View {
        Button {
            viewModel.continueWithLimitedFree()
            flowState.advance()
        } label: {
            Text(Copy.paywall.continueWithLimitedFreeLink)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .underline()
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.xs)
    }
}

#Preview {
    PaywallView(flowState: OnboardingFlowState())
}
