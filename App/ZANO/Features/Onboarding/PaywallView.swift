// PaywallView.swift
// App / Features / Onboarding
//
// Screen 12 of 14 in the onboarding flow (docs/spec.md §7.12), directly after Commitment: a HARD
// paywall (decision 2026-09-23) — free trial (7 days) with a reminder before it ends. Annual is the
// default. There is no free path. It is also shown standalone by `ContentView` when a subscription
// lapses. Spec §21's copy rules: a clear dated trial timeline (today / reminder / charge date), a
// visible restore link, no dark patterns. (No social-proof block: the app has no real testimonials
// or counts yet, and a fabricated one is a ship risk.)
//
// Layout (2026-09-24, from the trial-timeline paywall the user supplied as the reference): the
// whole decision on one screen, in this order —
//
//   hero        the full-charge `ZanoLivingMark` over a `StarBloom` (what "earned" looks like).
//   headline    "Start your 7-day free trial." / "Earn your phone back." (the second line in the
//               earned accent: it is the promise). Without a trial on the selected plan the first
//               line reads "Subscribe to continue."
//   timeline    Today → Reminder in 5 days → Billing starts in 7 days, as icon nodes on one thick
//               track: the trial stretch in the accent, the paid stretch grey. The nodes step down
//               in weight (Today is the blue disc; reminder and billing are grey discs). The
//               billing row carries the real calendar date.
//   plans       Monthly and Annual side by side; annual pre-selected with a "7 days free" pill.
//   CTA block   "✓ No payment due now", one white button, the full terms paragraph, then Terms ·
//               Privacy · Restore purchases (spec §24).
//
// `context`: `.onboarding` (screen 12) or `.lapsed` (the app shell, after a subscription or trial
// ran out). Lapsed swaps the first headline line for "Welcome back." and sends no onboarding
// analytics and never advances the onboarding flow.
//
// State lives in `PaywallViewModel` (Core); this view is presentation only and mutates
// `OnboardingFlowState` only through `advance()`. Loading shows skeleton tiles at the real sizes; a
// failed load is a calm card with "Try again" and Restore, never a disabled button under an error.
// CI screenshots use `PaywallDemo` (DEBUG only) because the Simulator has no StoreKit products.
//
// Carried from earlier passes: `SwiftUI.ProgressView()` (bare `ProgressView` is this module's
// Progress tab), Terms/Privacy links App Review expects, every animation gated on Reduce Motion.
// The Terms link is Apple's standard EULA and Privacy is a placeholder: both need final URLs before
// submission.

import SwiftUI
import Core

/// Screen 12 of 14 (spec §7.12) — the hard paywall. Presents RevenueCat offerings via
/// `PaywallViewModel` with the annual plan selected (spec §21). The only ways forward are to start
/// the trial, subscribe, or restore an existing purchase.
struct PaywallView: View {
    /// Where the paywall is shown. Changes the first headline line and whether onboarding
    /// analytics and `flowState.advance()` run.
    enum Context: Sendable, Equatable {
        /// Screen 12 of onboarding.
        case onboarding
        /// Shown by the app shell after a subscription or trial lapsed.
        case lapsed
    }

    @Bindable var flowState: OnboardingFlowState
    let context: Context
    /// `.task` below overwrites `viewModel.coachVoice` with `flowState.coachVoice` before loading.
    @State private var viewModel = PaywallViewModel()
    @State private var hasRevealed = false
    /// When the screen opened; the timeline's dates count forward from it.
    @State private var openedAt = Date.now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// The plan tiles' minimum height; they grow with Dynamic Type.
    private static let tileMinHeight: CGFloat = 96
    private static let heroMarkHeight: CGFloat = 64

    init(flowState: OnboardingFlowState, context: Context = .onboarding) {
        self.flowState = flowState
        self.context = context
    }

    private var isOnboarding: Bool { context == .onboarding }

    private var isRevealed: Bool { reduceMotion || hasRevealed }

    private var hasLoadFailed: Bool {
        if case .failed = viewModel.loadState { true } else { false }
    }

    /// The trial on the selected plan, if any. The headline, timeline and CTA all follow it, so
    /// choosing monthly (no trial) never shows a trial promise.
    private var selectedTrialDays: Int? {
        guard let days = viewModel.selectedPackage?.introductoryTrialDays, days > 0 else { return nil }
        return days
    }

    // `body` is split into stages so the type checker stays fast.
    private var layout: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    headline
                        .padding(.top, Theme.Spacing.xs)
                        .paywallReveal(index: 0, isShown: isRevealed, reduceMotion: reduceMotion)

                    Spacer(minLength: Theme.Spacing.md)

                    middle
                        .paywallReveal(index: 1, isShown: isRevealed, reduceMotion: reduceMotion)

                    Spacer(minLength: Theme.Spacing.md)

                    decision
                        .paywallReveal(index: 2, isShown: isRevealed, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .zanoAmbient(.neutral)
        .preferredColorScheme(.dark)
    }

    private var withFeedback: some View {
        layout
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
                #if DEBUG
                // CI screenshots: the Simulator has no StoreKit products, so show the real layout
                // with the spec's §21 price points instead of only ever photographing the error.
                if ScreenshotMode.screen != nil {
                    viewModel.loadDemoOfferings(PaywallDemo.packages)
                    return
                }
                #endif
                await viewModel.load()
            }
            .onAppear {
                #if DEBUG
                // UI tests and CI have no RevenueCat products to buy. Compiled out of release builds.
                if isOnboarding, UserDefaults.standard.bool(forKey: "ZANOSkipPaywall") { flowState.advance() }
                #endif
                hasRevealed = true
                if isOnboarding {
                    Analytics.shared.capture(
                        event: "onboarding_screen_viewed",
                        properties: ["screen": "paywall", "screen_number": 12]
                    )
                }
            }
            .onChange(of: viewModel.purchaseState) { _, newValue in
                if newValue == .succeeded {
                    // Re-read the entitlement so a lapsed-subscription paywall (ContentView) dismisses.
                    Task { await EntitlementGate.shared.refresh() }
                    if isOnboarding { flowState.advance() }
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
        VStack(spacing: Theme.Spacing.sm) {
            hero
            headlineText
        }
    }

    /// The fully charged star over its blue bloom: what the user is paying to earn. The bloom is a
    /// background, so it never adds height.
    private var hero: some View {
        ZanoLivingMark(charge: 1, height: Self.heroMarkHeight)
            .background {
                OnboardingKit.StarBloom(diameter: Self.heroMarkHeight * 3.5)
            }
            .accessibilityHidden(true)
    }

    private var firstHeadlineLine: String {
        switch context {
        case .lapsed:
            Copy.paywall.lapsedHeadline
        case .onboarding:
            selectedTrialDays.map { Copy.paywall.trialHeadline(days: $0) } ?? Copy.paywall.subscribeHeadline
        }
    }

    private var headlineText: some View {
        VStack(spacing: 2) {
            Text(firstHeadlineLine)
                .foregroundStyle(Theme.Colors.text)
                .contentTransition(.opacity)
            Text(Copy.paywall.headline)
                .foregroundStyle(Theme.Colors.accent)
        }
        .font(Theme.Typography.display)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Middle: the trial timeline (or, without a trial, what billing looks like)

    @ViewBuilder
    private var middle: some View {
        if let trialDays = selectedTrialDays, let package = viewModel.selectedPackage {
            PaywallTrialTimeline(
                startDate: openedAt,
                trialDays: trialDays,
                reminderDaysBefore: PaywallViewModel.trialReminderDaysBefore,
                priceLine: priceLine(for: package)
            )
            .transition(.opacity)
        } else if viewModel.loadState == .loaded, viewModel.selectedPackage != nil {
            PaywallTrialTimeline(
                startDate: openedAt,
                trialDays: 0,
                reminderDaysBefore: PaywallViewModel.trialReminderDaysBefore,
                priceLine: viewModel.selectedPackage.map { priceLine(for: $0) } ?? ""
            )
            .transition(.opacity)
        } else {
            // Loading or failed: the same track, so the page doesn't jump when plans land.
            PaywallTrialTimeline(
                startDate: openedAt,
                trialDays: 7,
                reminderDaysBefore: PaywallViewModel.trialReminderDaysBefore,
                priceLine: ""
            )
            .redacted(reason: viewModel.loadState == .loading || viewModel.loadState == .idle ? .placeholder : [])
            .opacity(hasLoadFailed ? 0.35 : 1)
        }
    }

    // MARK: - Decision: plans, CTA, terms, links

    @ViewBuilder
    private var decision: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch viewModel.loadState {
            case .idle, .loading:
                plansPlaceholder
            case .failed:
                plansFailure
            case .loaded:
                planTiles
            }

            VStack(spacing: Theme.Spacing.sm) {
                if hasLoadFailed {
                    PrimaryButton(title: Copy.paywall.retryButtonLabel, systemImage: "arrow.clockwise") {
                        Task { await viewModel.loadOfferings() }
                    }
                } else {
                    reassurance
                    ctaButton
                    termsParagraph
                }
                legalRow
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    /// Monthly and annual side by side, annual on the right and pre-selected (the reference's
    /// order: the eye ends on the recommended plan). Anything else the offering adds follows, two
    /// to a row. Each row is an `HStack` fixed to its tallest tile, so a pair is always one height
    /// however Dynamic Type grows either tile.
    private var planTiles: some View {
        let annual = viewModel.packages.filter { $0.period == .annual }
        let monthly = viewModel.packages.filter { $0.period == .monthly }
        let rest = viewModel.packages.filter { $0.period != .annual && $0.period != .monthly }
        let ordered = monthly + annual + rest
        let rows = stride(from: 0, to: ordered.count, by: 2).map { Array(ordered[$0..<min($0 + 2, ordered.count)]) }
        return VStack(spacing: Theme.Spacing.lg) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(row) { package in
                        planTile(for: package)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func planTile(for package: SubscriptionPackage) -> some View {
        PaywallPlanTile(
            title: planTitle(for: package),
            price: package.priceString,
            priceSuffix: package.period == .monthly ? Copy.paywall.perMonthSuffix : nil,
            detail: package.period == .annual ? package.pricePerMonthString : nil,
            pill: package.introductoryTrialDays.flatMap { $0 > 0 ? Copy.paywall.trialPill(days: $0) : nil },
            isSelected: viewModel.selectedPackageID == package.id,
            action: { viewModel.selectPackage(id: package.id) }
        )
        .frame(maxWidth: .infinity, minHeight: Self.tileMinHeight, maxHeight: .infinity)
    }

    private var plansPlaceholder: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<2, id: \.self) { _ in
                Color.clear
                    .frame(height: Self.tileMinHeight)
                    .zanoCard(radius: Theme.Radius.medium)
            }
        }
        .overlay {
            SwiftUI.ProgressView()
                .tint(Theme.Colors.muted)
        }
        .padding(.top, Theme.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.paywall.loadingPlansLabel)
    }

    /// A designed state, not a dead end: what happened in one line; "Try again" and Restore below.
    private var plansFailure: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "wifi.exclamationmark", tint: Theme.Colors.textSecondary, size: .medium)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.paywallTimeline.plansLoadFailedTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.paywallTimeline.plansLoadFailedDetail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
    }

    /// "✓ No payment due now" while a trial is selected; "✓ Cancel anytime" otherwise.
    private var reassurance: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark")
                .font(Theme.Typography.icon(.medium, weight: .heavy))
                .accessibilityHidden(true)
            Text(selectedTrialDays != nil ? Copy.paywall.noPaymentDueNow : Copy.paywall.cancelAnytime)
                .font(Theme.Typography.headline)
        }
        .foregroundStyle(Theme.Colors.text)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
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
                // The same blue capsule (`PrimaryButton`'s accent fill) with a white spinner in it, so
                // the button doesn't change mid-purchase.
                Capsule()
                    .fill(Theme.Colors.accentFill)
                    .frame(height: Theme.Metrics.primaryButtonHeight)
                    .overlay {
                        SwiftUI.ProgressView()
                            .tint(Theme.Colors.onAccent)
                    }
            }
        }
    }

    private var ctaButtonTitle: String {
        if let trialDays = selectedTrialDays {
            Copy.paywall.startTrialButtonLabel(trialDays: trialDays)
        } else {
            Copy.paywall.subscribeButtonLabel
        }
    }

    /// The full terms right under the button that commits to them (App Review's common rejection
    /// cause is a CTA whose terms sit elsewhere).
    @ViewBuilder
    private var termsParagraph: some View {
        if let package = viewModel.selectedPackage {
            Text(Copy.paywall.termsParagraph(
                trialDays: selectedTrialDays,
                price: package.priceString,
                period: package.period
            ))
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
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

    /// Terms · Privacy · Restore purchases: three 44pt targets on one row, stacking on a very large
    /// text size (spec §24: restore purchases visible).
    private var legalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                legalLink(title: Copy.paywall.termsLinkLabel, url: PaywallLegalLinks.terms)
                legalDivider
                legalLink(title: Copy.paywall.privacyLinkLabel, url: PaywallLegalLinks.privacy)
                legalDivider
                restoreButton
            }
            VStack(spacing: 0) {
                legalLink(title: Copy.paywall.termsLinkLabel, url: PaywallLegalLinks.terms)
                legalLink(title: Copy.paywall.privacyLinkLabel, url: PaywallLegalLinks.privacy)
                restoreButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var legalDivider: some View {
        Circle()
            .fill(Theme.Colors.track)
            .frame(width: 3, height: 3)
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

/// The two links App Review expects on a subscription paywall. `terms` is Apple's standard EULA
/// (the correct fallback for an auto-renewable subscription until ZANO publishes its own); `privacy`
/// is the same placeholder `SettingsView` uses. Both need final URLs before submission.
private enum PaywallLegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://zano.app/privacy")!
}

// MARK: - Trial timeline

/// Today → reminder → billing as large icon nodes on one thick vertical track. The trial stretch of
/// the track is the accent at low strength (it's the free, earned-feeling part), the paid stretch
/// after billing is grey. The billing row names the real calendar date, which makes the reminder a
/// checkable promise (spec §21). With `trialDays == 0` (a plan without a trial) it collapses to
/// "Today" and "Billing starts today". Static: no motion.
private struct PaywallTrialTimeline: View {
    let startDate: Date
    let trialDays: Int
    let reminderDaysBefore: Int
    let priceLine: String

    private static let nodeSize: CGFloat = 36
    private static let trackWidth: CGFloat = 10

    private struct Node: Identifiable {
        enum Kind { case today, reminder, billing }
        let id: Int
        let kind: Kind
        let title: String
        let detail: String
    }

    private func date(addingDays days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? startDate
    }

    private var nodes: [Node] {
        var result = [Node(id: 0, kind: .today, title: Copy.paywall.timelineTodayTitle, detail: Copy.paywall.timelineTodayDetail)]
        guard trialDays > 0 else { return result }
        if trialDays > reminderDaysBefore {
            result.append(Node(
                id: 1,
                kind: .reminder,
                title: Copy.paywall.timelineReminderTitle(inDays: trialDays - reminderDaysBefore),
                detail: Copy.paywall.timelineReminderDetail
            ))
        }
        let chargeDate = date(addingDays: trialDays).formatted(date: .abbreviated, time: .omitted)
        result.append(Node(
            id: 2,
            kind: .billing,
            title: Copy.paywall.timelineBillingTitle(inDays: trialDays),
            detail: Copy.paywall.timelineBillingDetail(date: chargeDate)
        ))
        return result
    }

    var body: some View {
        let all = nodes
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.element.id) { index, node in
                row(node, isLast: index == all.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ node: Node, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            nodeGlyph(node)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(node.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(node.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.Spacing.xs)
            // Tight enough that Terms / Privacy / Restore stay on the first screen (spec §24:
            // restore purchases visible) on a 393 × 852 phone, hero included.
            .padding(.bottom, Theme.Spacing.sm)
        }
        // The track segment below this node, behind it: accent while still in the trial, grey for
        // the tail after billing. A background, so it spans the row whatever the text does.
        .background(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Self.trackWidth / 2)
                .fill(node.kind == .billing ? Theme.Colors.track : Theme.Colors.accent.opacity(0.35))
                .frame(width: Self.trackWidth)
                .padding(.leading, (Self.nodeSize - Self.trackWidth) / 2)
                .padding(.top, Self.nodeSize / 2)
                .padding(.bottom, isLast ? 0 : -Self.nodeSize / 2)
        }
    }

    /// The nodes step down in weight along the timeline: today is the blue disc with a white
    /// glyph (the part that is yours now), the reminder a grey disc with a secondary glyph, the
    /// billing date a grey disc with a muted glyph.
    private func nodeGlyph(_ node: Node) -> some View {
        let symbol: String
        let fill: Color
        let glyph: Color
        switch node.kind {
        case .today:
            symbol = "lock.open.fill"
            fill = Theme.Colors.accent
            glyph = Theme.Colors.onAccent
        case .reminder:
            symbol = "bell.fill"
            fill = Theme.Colors.surface2
            glyph = Theme.Colors.textSecondary
        case .billing:
            symbol = "crown.fill"
            fill = Theme.Colors.surface2
            glyph = Theme.Colors.muted
        }
        return Image(systemName: symbol)
            .font(Theme.Typography.icon(.medium, weight: .bold))
            .foregroundStyle(glyph)
            .frame(width: Self.nodeSize, height: Self.nodeSize)
            .background(fill, in: Circle())
            .zIndex(1)
            .accessibilityHidden(true)
    }
}

// MARK: - Plan tile

/// One plan: its name, the price large, an optional per-month line, a radio on the right, and an
/// optional pill ("7 days free") sitting on the top edge. Selected is the blue selection edge
/// (`Metrics.selectedStroke`), the `accentWash` fill and a filled check.
private struct PaywallPlanTile: View {
    let title: String
    let price: String
    let priceSuffix: String?
    let detail: String?
    let pill: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, price: String, priceSuffix: String?, detail: String?, pill: String?, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.price = price
        self.priceSuffix = priceSuffix
        self.detail = detail
        self.pill = pill
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.system(.title2, weight: .heavy).width(.condensed))
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let priceSuffix {
                            Text(priceSuffix)
                                .font(Theme.Typography.unit)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.Colors.interactive : Theme.Colors.hairlineStrong)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .padding(.horizontal, Theme.Spacing.md)
            // Room for the pill on top and for larger text; the tile grows instead of clipping.
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isSelected ? Theme.Colors.accentWash : Theme.Colors.surface, in: shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.interactive : Theme.Colors.hairlineStrong,
                    lineWidth: isSelected ? Theme.Metrics.selectedStroke : Theme.Metrics.edgeWidth
                )
            )
            .overlay(alignment: .top) {
                if let pill {
                    Text(pill)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .lineLimit(1)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        // `accentFill`, not `accent`: white caption text needs the deeper blue.
                        .background(Theme.Colors.accentFill, in: Capsule())
                        .offset(y: -13)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.97))
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Demo offerings (CI screenshots only)

#if DEBUG
/// Spec §21's price points, for the Simulator (no StoreKit products). Never in a release build.
enum PaywallDemo {
    static let packages: [SubscriptionPackage] = [
        SubscriptionPackage(id: "demo_annual", productIdentifier: "zano_pro_annual", period: .annual,
                            priceString: "$39.99", pricePerMonthString: "$3.33/mo", introductoryTrialDays: 7),
        SubscriptionPackage(id: "demo_monthly", productIdentifier: "zano_pro_monthly", period: .monthly,
                            priceString: "$6.99", pricePerMonthString: "$6.99/mo", introductoryTrialDays: nil),
    ]
}
#endif

// MARK: - Staged entrance

private extension View {
    /// One block of the entrance: fades in and rises `Spacing.xs`, ~60ms after the block before it.
    /// Under Reduce Motion the caller passes `isShown: true` from the start, so nothing animates.
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

#Preview("Lapsed") {
    PaywallView(flowState: OnboardingFlowState(), context: .lapsed)
}
