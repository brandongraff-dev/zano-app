// PaywallView.swift
// App / Features / Onboarding
//
// Screen 13 of 14 in the onboarding flow (docs/spec.md §7.13): "Paywall — Free trial (7 days) with
// 'we'll remind you 2 days before it ends.' Annual highlighted. Clear 'Continue with limited free'
// option below (1 goal, 1 lock set)." Copy rules are spec §21's: "benefits in the user's words from
// onboarding; show the plan they built; social proof; clear free path; no dark patterns." (There is
// no social-proof block: the app has no real testimonials or counts yet, and a fabricated one is a
// ship risk — `Copy.onboarding.socialProofQuotes`' own header says the same.)
//
// State lives in `PaywallViewModel` (`Core/Sources/Core/Monetization/PaywallViewModel.swift`); this
// view is presentation only. It reads (never writes) `flowState.coachVoice` to seed the view model's
// voice, and mutates `OnboardingFlowState` only through `advance()`, per that file's navigation
// contract.
//
// DESIGN PASS (docs/design/competitive-research.md §3.6, better-layout-findings 5.6/7.1/6.2,
// composition-audit offender 5, better-ui BRK-01/HIT-02/MOT-02/MOT-08, typography-color C7,
// writing-findings §5.1). This is the highest-revenue-impact screen in the app and it was a plan
// picker: a 30pt headline, three accent-decorated rows, a to-do list of "your plan", two plan cards
// that were the same object at the same size, and — inside the one ScrollView — the purchase button
// and the free path, below the fold for anyone with more than one goal. Now, top to bottom:
//
//   headline    the display tier (`Theme.Typography.Style.display`), not an ad hoc 30pt.
//   your plan   ONE compact card: the lock set the user named, and their goals as chips carrying the
//               goal's own glyph and ring color (the object they built on screen 10, reused; the
//               leaders repeat the user's context before pricing — Runna, Fitbod).
//   benefits    three quiet rows, glyphs in `text` on a neutral disc — accent is for the CTA and the
//               selection, not decoration (typography-color C7).
//   plans       annual is a HERO card (28pt radius, price as a numeral, "Best value", the monthly
//               equivalent and the trial in its detail line); monthly and anything else is a COMPACT
//               card. Selection is an accent edge over the on-hue `accentWash`, drawn inside so it
//               never shifts layout, with a haptic tick. The two were previously identical.
//   timeline    only when the selected plan has a trial: Today / reminder / trial ends, with real
//               calendar dates from `Date` (a date removes the ambiguity of "Day 7"), backing up the
//               spec's "we'll remind you 2 days before" promise.
//   pinned bar  the terms line, the CTA bound to the selection, the free path as a 44pt+ two-line
//               control that says what "free" is, and Restore / Terms / Privacy at 44pt. Nothing
//               that decides the purchase depends on scroll distance any more. Cap: Dynamic Type is
//               held at xxxLarge inside the bar so it cannot swallow the screen.
//
// Fixes carried in the same pass: `ProgressView()` here resolved to the app's Progress *tab* (the
// `ZANO` module declares a `ProgressView` screen), so the loading state, the purchase spinner and
// the restore spinner each mounted that whole screen — now `SwiftUI.ProgressView()`; the annual
// detail line no longer doubles its "/mo" ("$3.33/mo/mo") because it uses
// `Copy.paywallTimeline.perMonthAndTrialLine`; the auto-renew note and Terms/Privacy links that
// App Review expects (spec §24) are wired in from `Copy.paywall`; every animation respects Reduce
// Motion, including the plan-card selection that was ungated.
//
// Unverified without a device: layout at 375pt and at AX sizes, `Layout`-based chip wrapping, and
// the exact fold position on a 393x852 phone (arithmetic says the annual card fits above the
// pinned bar; measure). The Terms link is Apple's standard EULA and the Privacy link is the same
// placeholder `SettingsView` uses — both need real URLs before submission.

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
    /// `load()`. This `@State` default-value form is the standard `@Observable`-with-SwiftUI idiom.
    @State private var viewModel = PaywallViewModel()
    @State private var hasRevealed = false
    /// When the screen opened; the trial timeline's dates count forward from it.
    @State private var openedAt = Date.now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    init(flowState: OnboardingFlowState) {
        self.flowState = flowState
    }

    /// Reduce Motion shows every block in place from the first frame.
    private var isRevealed: Bool {
        reduceMotion || hasRevealed
    }

    // `body` was one ~25-modifier chain, which the Swift type checker gave up on ("unable to
    // type-check this expression in reasonable time"). Split into three stages; behavior is
    // identical.
    private var layout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headline
                    .paywallReveal(index: 0, isShown: isRevealed, reduceMotion: reduceMotion)

                if let builtPlan = viewModel.builtPlan, !builtPlan.goalTitles.isEmpty {
                    planRecap(builtPlan)
                        .paywallReveal(index: 1, isShown: isRevealed, reduceMotion: reduceMotion)
                }

                benefitsSection
                    .paywallReveal(index: 2, isShown: isRevealed, reduceMotion: reduceMotion)

                offeringsSection
                    .paywallReveal(index: 3, isShown: isRevealed, reduceMotion: reduceMotion)

                trialTimeline

                Text(Copy.paywall.autoRenewNote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .zanoBackdrop(glow: Theme.Colors.accent, intensity: 0.10)
        .zanoActionBar {
            pinnedBar
        }
        .preferredColorScheme(.dark)
    }

    private var withFeedback: some View {
        layout
        // A tick when the user changes plan — not when the annual default is first selected on load.
        .sensoryFeedback(.selection, trigger: viewModel.selectedPackageID) { oldValue, newValue in
            oldValue != nil && newValue != nil
        }
        .sensoryFeedback(.success, trigger: viewModel.purchaseState) { _, newValue in
            newValue == .succeeded
        }
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: viewModel.loadState)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: viewModel.selectedPackageID)
    }

    var body: some View {
        withFeedback
        .task {
            viewModel.coachVoice = flowState.coachVoice
            await viewModel.load()
        }
        .onAppear {
            hasRevealed = true
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "paywall", "screen_number": 13]
            )
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
            .zanoText(.display)
            .foregroundStyle(Theme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - "The plan they built" (spec §21 copy rule)

    /// One compact card: the lock set's name, and each goal as a chip with its own glyph and ring
    /// color. Hidden entirely when Plan Reveal never ran (`viewModel.builtPlan == nil`).
    private func planRecap(_ plan: BuiltPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.paywall.yourPlanSectionTitle)
                    .zanoText(.eyebrow)
                    .foregroundStyle(Theme.Colors.muted)

                if let lockSetName = plan.lockSetName {
                    Text(Copy.paywall.lockSetSummary(name: lockSetName))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                }
            }

            PaywallChipFlow(spacing: Theme.Spacing.xs) {
                ForEach(Array(plan.goalTitles.enumerated()), id: \.offset) { _, title in
                    goalChip(title: title)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .zanoCard()
        .accessibilityElement(children: .combine)
    }

    private func goalChip(title: String) -> some View {
        let goalType = PaywallGoalGlyph.goalType(forTitle: title)
        let color = goalType.map { Theme.Colors.Ring.color(for: $0) } ?? Theme.Colors.muted
        let symbol = goalType.map { PaywallGoalGlyph.symbol(for: $0) } ?? "target"

        return HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: symbol)
                .font(Theme.Typography.icon(.xsmall))
                .foregroundStyle(color)
            Text(title)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
    }

    // MARK: - Benefits (spec §16 P5: three benefit rows with icons)

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            benefitRow(icon: "infinity", title: Copy.paywall.benefitUnlimitedGoalsTitle)
            benefitRow(icon: "brain.head.profile", title: Copy.paywall.benefitAdaptivePlanTitle)
            benefitRow(icon: "person.3.fill", title: Copy.paywall.benefitSquadsDuelsTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: icon, tint: Theme.Colors.text, size: .small)

            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Offerings (spec §21, §16 P5: annual highlighted, monthly smaller)

    @ViewBuilder
    private var offeringsSection: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            plansPlaceholder
                .transition(.opacity)

        case .failed(let message):
            plansFailure(message)
                .transition(.opacity)

        case .loaded:
            planCards
                .transition(.opacity)
        }
    }

    /// Two skeleton cards at the real cards' sizes, so the page doesn't jump when the offerings
    /// land, with a spinner over them. (`SwiftUI.ProgressView`: bare `ProgressView` is this
    /// module's Progress screen.)
    private var plansPlaceholder: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Color.clear
                .frame(height: PaywallPlanCard.heroHeight)
                .zanoCard(radius: Theme.Radius.large)
            Color.clear
                .frame(height: PaywallPlanCard.compactHeight)
                .zanoCard(radius: Theme.Radius.medium)
        }
        .overlay {
            SwiftUI.ProgressView()
                .tint(Theme.Colors.accent)
        }
        .accessibilityHidden(true)
    }

    private func plansFailure(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(Copy.paywallTimeline.plansLoadFailedTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: Copy.paywall.retryButtonLabel, style: .secondary) {
                Task { await viewModel.loadOfferings() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private var planCards: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(orderedPackages) { package in
                PaywallPlanCard(
                    emphasis: package.period == .annual ? .hero : .compact,
                    title: planTitle(for: package),
                    priceLine: priceLine(for: package),
                    detailLine: detailLine(for: package),
                    badgeLabel: package.period == .annual ? Copy.paywall.annualBadgeLabel : nil,
                    isSelected: viewModel.selectedPackageID == package.id,
                    action: { viewModel.selectPackage(id: package.id) }
                )
            }
        }
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

    /// `pricePerMonthString` already ends in "/mo" (`SubscriptionPackage`), so this uses
    /// `Copy.paywallTimeline.perMonthAndTrialLine` — `Copy.paywall.annualDetailLine` appends a
    /// second "/mo" ("$3.33/mo/mo · 7 days free").
    private func detailLine(for package: SubscriptionPackage) -> String? {
        if let perMonth = package.pricePerMonthString, let trialDays = package.introductoryTrialDays {
            return Copy.paywallTimeline.perMonthAndTrialLine(perMonth: perMonth, trialDays: trialDays)
        }
        if let perMonth = package.pricePerMonthString {
            return perMonth
        }
        if let trialDays = package.introductoryTrialDays {
            return Copy.paywall.trialDaysLabel(trialDays)
        }
        return nil
    }

    // MARK: - Trial timeline

    /// Only when the loaded, selected plan carries a free trial: without one there is nothing to
    /// promise a date for.
    @ViewBuilder
    private var trialTimeline: some View {
        if viewModel.loadState == .loaded,
           let package = viewModel.selectedPackage,
           let trialDays = package.introductoryTrialDays,
           trialDays > 0 {
            PaywallTrialTimeline(
                startDate: openedAt,
                trialDays: trialDays,
                reminderDaysBefore: PaywallViewModel.trialReminderDaysBefore,
                priceLine: priceLine(for: package)
            )
            .transition(.opacity)
        }
    }

    // MARK: - Pinned bar: terms, CTA, free path, legal (spec §7.13, §21, §24)

    private var pinnedBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            termsLine
            ctaButton
            freePathButton
            legalRow
        }
        // The pinned bar must never eat the screen at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The price and trial terms directly above the button that commits to them — App Review's
    /// common rejection cause is a CTA whose terms sit elsewhere.
    @ViewBuilder
    private var termsLine: some View {
        if let package = viewModel.selectedPackage {
            Text(termsText(for: package))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func termsText(for package: SubscriptionPackage) -> String {
        if let trialDays = package.introductoryTrialDays, trialDays > 0 {
            return Copy.paywallTimeline.trialTermsLine(trialDays: trialDays, priceLine: priceLine(for: package))
        }
        return priceLine(for: package)
    }

    private var ctaButton: some View {
        ZStack {
            PrimaryButton(
                title: ctaButtonTitle,
                isEnabled: viewModel.canAttemptPurchase,
                action: { Task { await viewModel.purchase() } }
            )
            .opacity(viewModel.isPurchasing ? 0 : 1)

            if viewModel.isPurchasing {
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(height: Theme.Metrics.primaryButtonHeight)
                    .overlay {
                        SwiftUI.ProgressView()
                            .tint(Theme.Colors.onFill)
                    }
            }
        }
    }

    private var ctaButtonTitle: String {
        if let trialDays = viewModel.selectedPackage?.introductoryTrialDays {
            Copy.paywall.startTrialButtonLabel(trialDays: trialDays)
        } else {
            Copy.paywall.subscribeButtonLabel
        }
    }

    /// The free path is a real control — 44pt or more, in `text`, not a 13pt grey underline — and
    /// it says what "free" is (spec §21: "1 goal, 1 lock set"), so the choice is an informed one.
    /// It is never gated on `loadState` or `purchaseState`: a reviewer whose sandbox products are
    /// not approved must still get past this screen (spec §21 "no dark patterns").
    private var freePathButton: some View {
        Button {
            viewModel.continueWithLimitedFree()
            flowState.advance()
        } label: {
            VStack(spacing: 0) {
                Text(Copy.paywall.continueWithLimitedFreeLink)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.paywallTimeline.freeTierDetail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// Restore purchases (spec §24: "restore purchases visible"), Terms and Privacy: three 44pt
    /// targets on one row, stacking on a very large text size.
    private var legalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                restoreButton
                legalDivider
                legalLink(title: Copy.paywall.termsLinkLabel, url: PaywallLegalLinks.terms)
                legalDivider
                legalLink(title: Copy.paywall.privacyLinkLabel, url: PaywallLegalLinks.privacy)
            }
            VStack(spacing: 0) {
                restoreButton
                legalLink(title: Copy.paywall.termsLinkLabel, url: PaywallLegalLinks.terms)
                legalLink(title: Copy.paywall.privacyLinkLabel, url: PaywallLegalLinks.privacy)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var legalDivider: some View {
        Circle()
            .fill(Theme.Colors.track)
            .frame(width: Theme.Spacing.xxs - 1, height: Theme.Spacing.xxs - 1)
            .accessibilityHidden(true)
    }

    private var restoreButton: some View {
        Button {
            Task { await viewModel.restore() }
        } label: {
            Group {
                if viewModel.isRestoring {
                    SwiftUI.ProgressView()
                        .tint(Theme.Colors.muted)
                } else {
                    Text(Copy.paywall.restorePurchasesButtonLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.96))
        .disabled(viewModel.isRestoring)
    }

    private func legalLink(title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .frame(minHeight: Theme.Metrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.96))
        .accessibilityAddTraits(.isLink)
    }
}

// MARK: - Legal links

/// The two links App Review expects on a subscription paywall. `terms` is Apple's standard
/// end-user license agreement, the correct fallback for an auto-renewable subscription until ZANO
/// publishes its own; `privacy` is the same placeholder `SettingsView` uses (its
/// `SettingsReferenceData` is file-private, so this cannot share it). Neither is copy — they are
/// destinations — but both need real, final URLs before submission.
private enum PaywallLegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://zano.app/privacy")!
}

// MARK: - Goal glyphs (recap chips)

/// Maps a stored goal title back to its `GoalType` so a recap chip can carry the goal's own glyph
/// and ring color. `BuiltPlanSummary` carries only titles (`Goal.title`), and every onboarding goal
/// is created with `Copy.onboarding.planGoalTitle(for:)` (`Screen10PlanReveal`, `Screen14FirstWin`),
/// so an exact match recovers the type; anything else falls back to a neutral `target` chip.
private enum PaywallGoalGlyph {
    static func goalType(forTitle title: String) -> GoalType? {
        GoalType.allCases.first { Copy.onboarding.planGoalTitle(for: $0) == title }
    }

    static func symbol(for type: GoalType) -> String {
        switch type {
        case .workoutGym: "dumbbell.fill"
        case .workoutHomeOutdoor: "figure.run"
        case .focusSession: "timer"
        case .protein: "fork.knife"
        case .water: "drop.fill"
        case .steps: "figure.walk"
        case .creatine: "pills.fill"
        case .sunriseAlarm: "sunrise.fill"
        case .sleepOnTime: "moon.zzz.fill"
        case .reading: "book.fill"
        case .mealPrep: "cart.fill"
        case .stretchMobility: "figure.flexibility"
        case .coldShowerSauna: "snowflake"
        case .custom: "star.fill"
        }
    }
}

// MARK: - Plan card

/// One selectable plan. Two emphases so the two plans are not the same object (they were): a HERO
/// card for the plan being sold (28pt radius, price as a 28pt numeral, room for a badge and a
/// two-line detail) and a COMPACT card for the alternatives (20pt radius, 17pt numeral).
///
/// Selected = the accent edge (2pt, drawn inside so selecting never shifts layout — it is always in
/// the view tree, faded in) over the on-hue `accentWash`; unselected = `surface` with the shared
/// top-lit edge. Padding is inside the `Button` so the whole card is the hit target and the whole
/// card presses (`PressableStyle`).
private struct PaywallPlanCard: View {
    enum Emphasis {
        case hero
        case compact
    }

    /// Nominal heights (a hero card is ~24pt of vertical padding above and below a 44pt content
    /// row; a compact one ~12pt above and below a 36pt row). Used by the loading skeleton so the
    /// page doesn't jump when the offerings land.
    static let heroHeight: CGFloat = 92
    static let compactHeight: CGFloat = 64

    let emphasis: Emphasis
    let title: String
    let priceLine: String
    let detailLine: String?
    let badgeLabel: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat {
        emphasis == .hero ? Theme.Radius.large : Theme.Radius.medium
    }

    private var verticalPadding: CGFloat {
        emphasis == .hero ? Theme.Spacing.lg : Theme.Spacing.sm
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.muted)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        if let badgeLabel {
                            Text(badgeLabel)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.onFill)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, Theme.Spacing.xxs / 2)
                                .background(Theme.Colors.accent, in: Capsule())
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    if let detailLine {
                        Text(detailLine)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: Theme.Spacing.xs)

                NumeralText(priceLine, size: emphasis == .hero ? .medium : .small)
                    .layoutPriority(1)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(
                radius: radius,
                fill: isSelected ? Theme.Colors.accentWash : Theme.Colors.surface
            )
            .overlay {
                shape
                    .strokeBorder(Theme.Colors.accent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Trial timeline

/// Today / reminder / trial ends, with real calendar dates. A date removes the ambiguity of "Day 7"
/// and is what makes "we'll remind you 2 days before" a checkable promise (competitive-research
/// §3.6: BoldVoice, Cal AI's "no payment due now"). Static — no motion at all — so it needs no
/// Reduce Motion handling. The reminder node is skipped when the trial is too short to have one.
private struct PaywallTrialTimeline: View {
    let startDate: Date
    let trialDays: Int
    let reminderDaysBefore: Int
    let priceLine: String

    private static let nodeSize = Theme.Metrics.iconBadgeSmall

    private struct Node: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
        /// `nil` for the first node, which reads "Today" instead of a date.
        let date: Date?
        let isNow: Bool
    }

    private func date(addingDays days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? startDate
    }

    private var nodes: [Node] {
        var result: [Node] = [
            Node(
                id: 0,
                symbol: "checkmark",
                title: Copy.paywallTimeline.timelineStartTitle,
                detail: Copy.paywallTimeline.timelineStartDetail,
                date: nil,
                isNow: true
            )
        ]
        if trialDays > reminderDaysBefore {
            result.append(
                Node(
                    id: 1,
                    symbol: "bell.fill",
                    title: Copy.paywallTimeline.timelineReminderTitle,
                    detail: Copy.paywall.trialReminderNote(daysBefore: reminderDaysBefore),
                    date: date(addingDays: trialDays - reminderDaysBefore),
                    isNow: false
                )
            )
        }
        result.append(
            Node(
                id: 2,
                symbol: "creditcard.fill",
                title: Copy.paywallTimeline.timelineChargeTitle,
                detail: Copy.paywallTimeline.timelineChargeDetail(priceLine: priceLine),
                date: date(addingDays: trialDays),
                isNow: false
            )
        )
        return result
    }

    var body: some View {
        let all = nodes
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(Copy.paywallTimeline.timelineHeading)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { index, node in
                    row(node, isLast: index == all.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private func row(_ node: Node, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            nodeGlyph(node)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(node.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer(minLength: Theme.Spacing.xs)
                    dateLabel(node)
                }
                Text(node.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Room below the text for the connector to run on to the next node.
            .padding(.bottom, isLast ? 0 : Theme.Spacing.md)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                // The connector: from just under this node's disc to the bottom of the row, on the
                // disc's centre line. A background, so it takes the row's full height whatever the
                // text does.
                Rectangle()
                    .fill(Theme.Colors.track)
                    .frame(width: 2)
                    .padding(.leading, (Self.nodeSize - 2) / 2)
                    .padding(.top, Self.nodeSize)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func nodeGlyph(_ node: Node) -> some View {
        Image(systemName: node.symbol)
            .font(Theme.Typography.icon(.xsmall))
            .foregroundStyle(node.isNow ? Theme.Colors.onFill : Theme.Colors.text)
            .frame(width: Self.nodeSize, height: Self.nodeSize)
            // "Now" is a solid `text` disc, not accent: the accent on this screen belongs to the
            // selected plan, the badge and the one CTA (accent budget, 2026-ios-trends A6).
            .background(node.isNow ? Theme.Colors.text : Theme.Colors.surface2, in: Circle())
            .overlay {
                if !node.isNow {
                    Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dateLabel(_ node: Node) -> some View {
        if let date = node.date {
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
        } else {
            Text(Copy.paywallTimeline.timelineToday)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
        }
    }
}

// MARK: - Chip flow layout

/// A left-aligned wrapping row layout for the recap's goal chips: as many per line as fit, then a
/// new line. (`HStack` would truncate or overflow three long goal names on a 361pt column.) Not
/// RTL-mirrored — `Layout` places in absolute coordinates — so a right-to-left localization would
/// need the layout direction passed in; the app ships English only.
private struct PaywallChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Staged entrance

private extension View {
    /// One block of the paywall's entrance: fades in and rises `Spacing.xs`, ~60ms after the block
    /// before it, on the ease-out curve that reads as "arriving". The whole sequence is about
    /// 0.6s and gates nothing (the pinned bar is on screen from the first frame). Under Reduce
    /// Motion the caller passes `isShown: true` from the start, so nothing animates.
    func paywallReveal(index: Int, isShown: Bool, reduceMotion: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : Theme.Spacing.xs)
            .animation(
                reduceMotion
                    ? nil
                    : .timingCurve(0.2, 0, 0, 1, duration: 0.4).delay(Double(index) * 0.06),
                value: isShown
            )
    }
}

#Preview {
    PaywallView(flowState: OnboardingFlowState())
}
