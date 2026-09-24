// PaywallView.swift
// App / Features / Onboarding
//
// Screen 12 of 14 in the onboarding flow (docs/spec.md §7.12), directly after Commitment: a HARD
// paywall (decision 2026-09-23) — free trial (7 days) with "we'll remind you 2 days before it
// ends." Annual highlighted. There is no free path. Copy rules are spec §21's: benefits in the
// user's words, the plan they built, a dated trial timeline, a visible restore link, no dark
// patterns. It is also shown standalone by `ContentView` when a subscription lapses. (There is
// no social-proof block: the app has no real testimonials or counts yet, and a fabricated one is a
// ship risk — `Copy.onboarding.socialProofQuotes`' own header says the same.)
//
// State lives in `PaywallViewModel` (`Core/Sources/Core/Monetization/PaywallViewModel.swift`); this
// view is presentation only. It reads (never writes) `flowState.coachVoice` to seed the view model's
// voice, and mutates `OnboardingFlowState` only through `advance()`, per that file's navigation
// contract.
//
// Premium pass (2026-09-24, docs/design/premium-ui-plan.md: "light is earned", Spotify chrome, Nike
// type; spec §16 P5). Buying is not an earned state, so the page is achromatic: the only color on it
// is the user's own goal colors in the plan they built. Top to bottom:
//
//   headline    "Earn your phone back" in the condensed display tier, one quiet line under it.
//   your plan   the page's one hero surface (`zanoHero`): the lock set they named and their goals as
//               chips in the goals' own glyphs and ring colors — the object they built on screen 10.
//   benefits    three rows, each a real `IconBadge` with a one-line detail in the user's terms.
//   plans       Core's `PaywallCard`: annual as the hero layout with "Best value" and a "7 days free"
//               pill, monthly compact. Selection is the app-wide white selection with a haptic tick.
//   timeline    Today / Day 5 reminder / Day 7 billing, each with its real calendar date.
//   pinned bar  the terms line, the one CTA (a white `PrimaryButton`), Restore / Terms / Privacy at
//               44pt. Dynamic Type is held at xxxLarge inside the bar so it cannot swallow the screen.
//
// Every state is designed: loading shows skeletons at the real cards' sizes; a failed load (no
// network, no StoreKit products — which is also what CI screenshots show) is a calm card with an
// icon and one line of explanation, the pinned CTA becomes "Try again", and Restore stays. A
// disabled "Subscribe" never sits under an error.
//
// Carried from earlier passes: `SwiftUI.ProgressView()` (bare `ProgressView` is this module's
// Progress tab), `Copy.paywallTimeline.perMonthAndTrialLine` to avoid "$3.33/mo/mo", the auto-renew
// note and Terms/Privacy links App Review expects (spec §24), and every animation gated on Reduce
// Motion.
//
// Unverified without a device: layout at 375pt and at AX sizes, `Layout`-based chip wrapping, and
// the fold position on a 393x852 phone. The Terms link is Apple's standard EULA and the Privacy link
// is the same placeholder `SettingsView` uses — both need real URLs before submission.

import SwiftUI
import Core

/// Screen 12 of 14 (spec §7.12) — the hard paywall. Presents RevenueCat offerings via
/// `PaywallViewModel` and defaults to the annual plan selected (spec §21 "annual highlighted").
/// The only ways forward are to start the trial, subscribe, or restore an existing purchase; when
/// plans fail to load it says so plainly and offers "Try again" and "Restore purchases".
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

    /// Nominal plan-card heights, for the loading skeleton (so the page doesn't jump when the
    /// offerings land): a hero card with its trial pill, and a compact row.
    private static let heroCardHeight: CGFloat = 124
    private static let compactCardHeight: CGFloat = 64

    init(flowState: OnboardingFlowState) {
        self.flowState = flowState
    }

    /// Reduce Motion shows every block in place from the first frame.
    private var isRevealed: Bool {
        reduceMotion || hasRevealed
    }

    private var hasLoadFailed: Bool {
        if case .failed = viewModel.loadState { true } else { false }
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
        .zanoAmbient(.neutral)
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
            #if DEBUG
            // UI tests and CI have no RevenueCat products to buy. Compiled out of every release build.
            if UserDefaults.standard.bool(forKey: "ZANOSkipPaywall") { flowState.advance() }
            #endif
            hasRevealed = true
            Analytics.shared.capture(
                event: "onboarding_screen_viewed",
                properties: ["screen": "paywall", "screen_number": 12]
            )
        }
        .onChange(of: viewModel.purchaseState) { _, newValue in
            if newValue == .succeeded {
                // Re-read the entitlement so a lapsed-subscription paywall (ContentView) dismisses.
                Task { await EntitlementGate.shared.refresh() }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.paywall.headline)
                .zanoText(.display)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.paywall.subheadline)
                .zanoText(.paragraph)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - "The plan they built" (spec §21 copy rule)

    /// The page's hero: the lock set's name, and each goal as a chip with its own glyph and ring
    /// color. Hidden entirely when Plan Reveal never ran (`viewModel.builtPlan == nil`).
    private func planRecap(_ plan: BuiltPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "lock.fill", tint: Theme.Colors.text, size: .medium)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.paywall.yourPlanSectionTitle)
                        .zanoText(.eyebrow)
                        .foregroundStyle(Theme.Colors.muted)
                    if let lockSetName = plan.lockSetName {
                        Text(Copy.paywall.lockSetSummary(name: lockSetName))
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            PaywallChipFlow(spacing: Theme.Spacing.xs) {
                ForEach(Array(plan.goalTitles.enumerated()), id: \.offset) { _, title in
                    goalChip(title: title)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .zanoHero()
        .accessibilityElement(children: .combine)
    }

    private func goalChip(title: String) -> some View {
        let goalType = PaywallGoalGlyph.goalType(forTitle: title)
        let color = goalType.map { Theme.Colors.Ring.color(for: $0) } ?? Theme.Colors.muted
        let symbol = goalType.map { PaywallGoalGlyph.symbol(for: $0) } ?? "target"

        return HStack(spacing: Theme.Spacing.xs) {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            benefitRow(
                icon: "infinity",
                title: Copy.paywall.benefitUnlimitedGoalsTitle,
                detail: Copy.paywall.benefitUnlimitedGoalsDetail
            )
            benefitRow(
                icon: "chart.line.uptrend.xyaxis",
                title: Copy.paywall.benefitAdaptivePlanTitle,
                detail: Copy.paywall.benefitAdaptivePlanDetail
            )
            benefitRow(
                icon: "person.2.fill",
                title: Copy.paywall.benefitSquadsDuelsTitle,
                detail: Copy.paywall.benefitSquadsDuelsDetail
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xxs)
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: icon, tint: Theme.Colors.text, size: .medium)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs / 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

        case .failed:
            plansFailure
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
                .frame(height: Self.heroCardHeight)
                .zanoCard(radius: Theme.Radius.large)
            Color.clear
                .frame(height: Self.compactCardHeight)
                .zanoCard(radius: Theme.Radius.medium)
        }
        .overlay {
            SwiftUI.ProgressView()
                .tint(Theme.Colors.muted)
        }
        .accessibilityHidden(true)
    }

    /// A designed state, not a dead end: what happened in one line, and the way forward is the
    /// pinned "Try again" (with Restore beside it). The raw StoreKit message is not shown — it is
    /// developer text ("In-app purchases are not available right now") and says nothing about what
    /// to do.
    private var plansFailure: some View {
        VStack(spacing: Theme.Spacing.md) {
            IconBadge(systemName: "wifi.exclamationmark", tint: Theme.Colors.textSecondary, size: .medium)

            VStack(spacing: Theme.Spacing.xxs) {
                Text(Copy.paywallTimeline.plansLoadFailedTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.paywallTimeline.plansLoadFailedDetail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.md)
        .zanoCard(radius: Theme.Radius.large)
        .accessibilityElement(children: .combine)
    }

    private var planCards: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(orderedPackages) { package in
                let isAnnual = package.period == .annual
                PaywallCard(
                    title: planTitle(for: package),
                    priceLine: priceLine(for: package),
                    detailLine: detailLine(for: package, isHighlighted: isAnnual),
                    badgeLabel: isAnnual ? Copy.paywall.annualBadgeLabel : nil,
                    trialLabel: isAnnual ? package.introductoryTrialDays.map { Copy.paywall.trialBadgeLabel(trialDays: $0) } : nil,
                    isHighlighted: isAnnual,
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
    /// second "/mo" ("$3.33/mo/mo · 7 days free"). The highlighted card shows its trial as its own
    /// pill, so its detail line is the per-month price alone.
    private func detailLine(for package: SubscriptionPackage, isHighlighted: Bool) -> String? {
        let trialDays = isHighlighted ? nil : package.introductoryTrialDays
        if let perMonth = package.pricePerMonthString, let trialDays {
            return Copy.paywallTimeline.perMonthAndTrialLine(perMonth: perMonth, trialDays: trialDays)
        }
        if let perMonth = package.pricePerMonthString {
            return perMonth
        }
        if let trialDays {
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

    // MARK: - Pinned bar: terms, CTA, legal (spec §7.12, §21, §24)

    private var pinnedBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if hasLoadFailed {
                // Plans didn't load: the one action that can help is retrying. No disabled
                // "Subscribe" under an error.
                PrimaryButton(title: Copy.paywall.retryButtonLabel, systemImage: "arrow.clockwise") {
                    Task { await viewModel.loadOfferings() }
                }
            } else {
                termsLine
                ctaButton
            }
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
                // The default (white) `PrimaryButton` capsule with a spinner in it, so the button
                // doesn't change color mid-purchase.
                Capsule()
                    .fill(Theme.Colors.interactive)
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
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.textSecondary)
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

// MARK: - Trial timeline

/// Today / reminder / billing, each with its trial day and real calendar date ("Day 5 · Sep 29"):
/// the day number is the structure, the date removes the ambiguity, and together they make "we'll
/// remind you 2 days before" a checkable promise (competitive-research §3.6). Static — no motion
/// at all — so it needs no Reduce Motion handling. The reminder node is skipped when the trial is
/// too short to have one.
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
        /// Days after today; 0 is today, which reads "Today" instead of a day and date.
        let day: Int
        let isNow: Bool
    }

    private func date(addingDays days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? startDate
    }

    private var nodes: [Node] {
        var result: [Node] = [
            Node(
                id: 0,
                symbol: "lock.open.fill",
                title: Copy.paywallTimeline.timelineStartTitle,
                detail: Copy.paywallTimeline.timelineStartDetail,
                day: 0,
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
                    day: trialDays - reminderDaysBefore,
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
                day: trialDays,
                isNow: false
            )
        )
        return result
    }

    var body: some View {
        let all = nodes
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(Copy.paywallTimeline.timelineHeading)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)

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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(node.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        Spacer(minLength: Theme.Spacing.xs)
                        whenLabel(node)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(node.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        whenLabel(node)
                    }
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
            // "Now" is a solid white disc: the timeline is chrome, not an earned state.
            .background(node.isNow ? Theme.Colors.interactive : Theme.Colors.surface2, in: Circle())
            .overlay {
                if !node.isNow {
                    Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                }
            }
            .accessibilityHidden(true)
    }

    /// "Today", or "Day 5 · Sep 29": the trial day in `text`, the calendar date quieter.
    @ViewBuilder
    private func whenLabel(_ node: Node) -> some View {
        if node.isNow {
            Text(Copy.paywallTimeline.timelineToday)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
        } else {
            HStack(spacing: Theme.Spacing.xxs) {
                Text(Copy.paywallTimeline.timelineDayLabel(node.day))
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.text)
                Text(date(addingDays: node.day), format: .dateTime.month(.abbreviated).day())
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
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
