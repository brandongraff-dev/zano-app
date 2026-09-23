// PaywallViewModel.swift
// Core / Monetization
//
// docs/spec.md §21 (Monetization & Paywall) and §7 screen 13 ("Paywall — Free trial (7 days)
// with 'we'll remind you 2 days before it ends.' Annual highlighted. Clear 'Continue with
// limited free' option below (1 goal, 1 lock set)."), plus §16 P5's mockup (three benefit rows,
// annual card highlighted with its monthly-equivalent + trial note, a smaller monthly option, a
// "Continue with limited free" text link). This is the screen-scoped state `App/ZANO/Features/
// Onboarding/PaywallView.swift` (this same task, App target) binds to — it owns loading
// offerings, plan selection, driving a purchase/restore through `RevenueCatManager`, and reading
// "the plan they built" (spec §21 "Paywall copy rules: ...show the plan they built") back out of
// the already-persisted `Goal`/`LockSet` rows onboarding's Plan Reveal screen (spec §7.10, a
// sibling session's file) wrote before this screen is ever shown.
//
// Not a SYSTEM CONTRACTS type for this batch — `RevenueCatManager`, `FocusSessionVerifier`,
// `GymVerifier`, etc. have orchestrator-fixed shapes; `PaywallViewModel` does not, so its exact
// surface is this file's own design, built to what `PaywallView` (this task's other owned file)
// actually needs.

import Foundation
import Observation
import SwiftData
import os

// MARK: - State

/// Loading state for `fetchOfferings()` via `RevenueCatManager`.
public enum PaywallLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// State for an in-flight or completed purchase/restore action.
public enum PaywallPurchaseState: Equatable, Sendable {
    case idle
    case purchasing
    case restoring
    /// A purchase or restore completed and granted the Pro entitlement.
    case succeeded
    /// The user dismissed the purchase sheet (spec §21 "no dark patterns" — a normal outcome,
    /// not an error to alarm anyone with; `PaywallView` should treat this the same as `.idle`
    /// for its UI, just distinguishable for analytics).
    case cancelled
    case failed(String)
}

/// A snapshot of the plan the user already built earlier in onboarding (spec §21 "show the plan
/// they built"), read from real, already-persisted `Goal`/`LockSet` rows — never re-derived from
/// onboarding's transient in-memory answers, and never invented copy. Empty/`nil` fields simply
/// mean Plan Reveal (spec §7.10) hasn't run yet (or this paywall is reached outside onboarding,
/// e.g. a future Settings "Upgrade" entry point) — `PaywallView` is expected to hide this section
/// entirely rather than show a broken-looking empty state in that case.
public struct BuiltPlanSummary: Sendable, Equatable {
    /// Titles of the user's active goals (`Goal.title`, `Core/Sources/Core/Models/Goal.swift`),
    /// in whatever order the store returns them.
    public let goalTitles: [String]
    /// The user's default `LockSet.name`, if one exists yet.
    public let lockSetName: String?

    public init(goalTitles: [String], lockSetName: String?) {
        self.goalTitles = goalTitles
        self.lockSetName = lockSetName
    }
}

// MARK: - PaywallViewModel

/// Screen-scoped `@Observable` state for the Paywall (spec §7 screen 13). Not a `.shared`
/// singleton — `PaywallView` (or whatever presents it) owns one instance, the same way SwiftUI/
/// `@Observable` view models are conventionally scoped in this codebase (contrast with the
/// SYSTEM CONTRACTS engines' `static let shared` — those are process-wide, this is per-screen).
///
/// `@MainActor`: every stored/published property here drives SwiftUI directly, and this type
/// calls `RevenueCatManager` (itself `@MainActor`) and touches a `ModelContext` — matching the
/// same reasoning `LockEngineManager`/`FocusSessionVerifier` document for their own `@MainActor`
/// choice (`Core/Sources/Core/LockEngine/LockEngineManager.swift`).
@MainActor
@Observable
public final class PaywallViewModel {

    // MARK: Published state

    public private(set) var loadState: PaywallLoadState = .idle
    public private(set) var packages: [SubscriptionPackage] = []
    /// The currently selected package's `SubscriptionPackage.id`. Defaults to the annual package
    /// once `loadOfferings()` succeeds (spec §21/§16 P5: "annual highlighted"); falls back to
    /// whichever package is first if no annual package exists in this offering.
    public var selectedPackageID: String?
    public private(set) var purchaseState: PaywallPurchaseState = .idle
    /// Best-effort Pro state for this screen's own UI (e.g. swapping the CTA to "You're Pro" if
    /// this screen is somehow reached by an already-subscribed user). Seeded from the local
    /// `User.planTier` mirror on `load()` — see that method's doc comment for why this reads
    /// SwiftData rather than calling `RevenueCatManager.isProSubscriber()` here.
    public private(set) var isProSubscriber = false
    public private(set) var builtPlan: BuiltPlanSummary?
    /// The voice to render any coach-voice-flavored copy in (spec §5.13). Defaults to the
    /// App-Group-mirrored value (`SharedDefaults.coachVoice`) so this view model works standalone
    /// (e.g. a future Settings "Upgrade" entry point), but `PaywallView` — reached from inside
    /// onboarding, where the user's Q6 answer lives in `OnboardingFlowState.coachVoice` and may
    /// not have been persisted to `SharedDefaults` yet — overrides this via `init(coachVoice:)`
    /// with that in-memory answer instead, which is always current for a fresh onboarding user.
    public var coachVoice: CoachVoice

    /// Reminder window spec §7.13 promises: "we'll remind you 2 days before it ends." A single
    /// source of truth so `PaywallView`'s copy and (once built — see knownIssues) any actual
    /// scheduled local notification agree.
    public static let trialReminderDaysBefore = 2

    public var selectedPackage: SubscriptionPackage? {
        packages.first { $0.id == selectedPackageID }
    }

    public var isLoadingOfferings: Bool { loadState == .loading }
    public var isPurchasing: Bool { purchaseState == .purchasing }
    public var isRestoring: Bool { purchaseState == .restoring }
    public var canAttemptPurchase: Bool {
        selectedPackage != nil && !isPurchasing && !isRestoring
    }

    // MARK: Dependencies

    private let revenueCat: RevenueCatManager
    private let modelContainer: ModelContainer
    @ObservationIgnored private lazy var modelContext = ModelContext(modelContainer)
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "PaywallViewModel")

    /// - Parameters:
    ///   - coachVoice: See `coachVoice`'s doc comment. `nil` (the default) reads
    ///     `SharedDefaults.coachVoice` at construction time.
    ///   - modelContainer: Defaults to the shared App Group container. Overridable for previews/
    ///     unit tests (an in-memory container).
    ///   - revenueCat: Defaults to `.shared`. Overridable for tests.
    public init(
        coachVoice: CoachVoice? = nil,
        modelContainer: ModelContainer = .appGroup,
        revenueCat: RevenueCatManager = .shared
    ) {
        self.coachVoice = coachVoice ?? CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice)
        self.modelContainer = modelContainer
        self.revenueCat = revenueCat
    }

    // MARK: - Load

    /// Loads both halves of the screen: the already-built plan (sync, local SwiftData read) and
    /// the RevenueCat offerings (async, network/cache). Call once from `PaywallView`'s `.task`.
    public func load() async {
        loadBuiltPlanAndLocalProStatus()
        await loadOfferings()
    }

    /// Fetches the current offering via `RevenueCatManager.fetchOfferings()` and picks a default
    /// selection. Safe to call again to retry after a `.failed` state.
    public func loadOfferings() async {
        guard loadState != .loading else { return }
        loadState = .loading
        Analytics.shared.capture(event: "paywall_viewed")

        do {
            let offerings = try await revenueCat.fetchOfferings()
            packages = offerings.packages
            if selectedPackageID == nil || !packages.contains(where: { $0.id == selectedPackageID }) {
                selectedPackageID = defaultSelection(in: packages)
            }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
            Analytics.shared.capture(
                event: "paywall_offerings_failed",
                properties: ["reason": error.localizedDescription]
            )
        }
    }

    private func defaultSelection(in packages: [SubscriptionPackage]) -> String? {
        (packages.first { $0.period == .annual } ?? packages.first)?.id
    }

    // MARK: - Selection

    public func selectPackage(id: String) {
        guard packages.contains(where: { $0.id == id }) else { return }
        selectedPackageID = id
    }

    // MARK: - Purchase / Restore

    /// Purchases the currently `selectedPackage`. A no-op if nothing is selected or a
    /// purchase/restore is already in flight (`canAttemptPurchase`).
    public func purchase() async {
        guard let package = selectedPackage, canAttemptPurchase else { return }
        purchaseState = .purchasing
        Analytics.shared.capture(event: "paywall_purchase_started", properties: ["package": package.id])

        do {
            let granted = try await revenueCat.purchase(package)
            if granted {
                markLocallyPro(product: package.productIdentifier)
            }
            isProSubscriber = granted
            purchaseState = .succeeded
            Analytics.shared.capture(
                event: "paywall_purchase_succeeded",
                properties: ["package": package.id, "granted_pro": granted]
            )
        } catch RevenueCatManagerError.purchaseCancelled {
            purchaseState = .cancelled
            Analytics.shared.capture(event: "paywall_purchase_cancelled", properties: ["package": package.id])
        } catch {
            purchaseState = .failed(error.localizedDescription)
            Analytics.shared.capture(
                event: "paywall_purchase_failed",
                properties: ["package": package.id, "reason": error.localizedDescription]
            )
        }
    }

    /// Restores previous purchases (spec §24: "restore purchases visible"). Always reachable,
    /// regardless of `canAttemptPurchase` — a stuck "purchasing" state must never block the one
    /// other path back to a paid account.
    public func restore() async {
        guard !isRestoring else { return }
        purchaseState = .restoring

        do {
            let granted = try await revenueCat.restorePurchases()
            if granted {
                markLocallyPro(product: nil)
            }
            isProSubscriber = granted
            purchaseState = granted ? .succeeded : .idle
            Analytics.shared.capture(event: "paywall_restore_finished", properties: ["granted_pro": granted])
        } catch {
            purchaseState = .failed(error.localizedDescription)
            Analytics.shared.capture(
                event: "paywall_restore_failed",
                properties: ["reason": error.localizedDescription]
            )
        }
    }

    /// Clears a `.failed`/`.cancelled` purchase state back to `.idle` — call after the view has
    /// shown/dismissed whatever alert it renders for that state, mirroring `LockSetupView`'s
    /// alert-dismiss convention (`Core/Sources/Core/../App/ZANO/Features/LockSetup/
    /// LockSetupView.swift`: an alert clears its own backing state on dismiss).
    public func acknowledgePurchaseState() {
        switch purchaseState {
        case .failed, .cancelled:
            purchaseState = .idle
        case .idle, .purchasing, .restoring, .succeeded:
            break
        }
    }

    /// Spec §7.13 / §21: "Continue with limited free" — the Free tier (1 goal, 1 lock set,
    /// manual/NFC lock, basic widget, 1 freeze/week) needs no state change here: `User.planTier`
    /// already defaults to `.free` (`Core/Sources/Core/Models/User.swift`) from whatever screen
    /// created the local `User` row, so this only records the choice for analytics/funnel
    /// tracking (spec §23: "trial start > 25% of completes" implies its inverse — declined —
    /// is worth counting too). `PaywallView` is responsible for advancing the onboarding flow
    /// after calling this.
    public func continueWithLimitedFree() {
        Analytics.shared.capture(event: "paywall_continue_limited_free")
    }

    // MARK: - SwiftData (built plan + local Pro mirror)

    /// Reads the plan built earlier in onboarding (spec §21 "show the plan they built") and
    /// seeds `isProSubscriber` from the local `User.planTier` mirror — a cheap, synchronous local
    /// read used only to decide this screen's own initial UI (e.g. not showing a "Start trial"
    /// CTA to an already-Pro user who somehow lands here again); it is deliberately not a
    /// substitute for `RevenueCatManager.isProSubscriber()`'s network-backed truth anywhere a
    /// real entitlement gate is being enforced.
    private func loadBuiltPlanAndLocalProStatus() {
        guard let user = try? fetchCurrentUser() else {
            builtPlan = nil
            return
        }
        let goalTitles = user.goals.filter(\.active).map(\.title)
        let lockSetName = (try? fetchDefaultLockSet(userID: user.id))?.name
        builtPlan = (goalTitles.isEmpty && lockSetName == nil)
            ? nil
            : BuiltPlanSummary(goalTitles: goalTitles, lockSetName: lockSetName)
        isProSubscriber = user.planTier == .pro
    }

    /// Local-first mirror write after a successful purchase/restore: flips `User.planTier` to
    /// `.pro` and upserts a `Subscription` row immediately, so every other screen that reads
    /// `User.planTier` for gating (spec §21) reflects Pro status instantly rather than waiting on
    /// the RevenueCat → Supabase webhook round trip (spec §11: "the backend never sits between a
    /// user and their unlock" — the same principle extended to Pro gating).
    ///
    /// `Subscription`'s own doc comment (`Core/Sources/Core/Models/Subscription.swift`) describes
    /// it as "last reported by the RevenueCat webhook" — this local write is a best-effort,
    /// same-values mirror ahead of that; Session 7's Sync/webhook path is still the eventual
    /// source of truth and is expected to overwrite this row with server data, not conflict with
    /// it (`rcCustomerID`/`renewsAt` are left `nil` here — this file has no `CustomerInfo` field
    /// beyond entitlement status to fill them from without exposing RevenueCat types outside
    /// `RevenueCatManager`, per that file's header comment). Never throws outward: a local write
    /// failure here must not undo an App Store purchase that already succeeded — see the doc
    /// comment on the call sites in `purchase()`/`restore()` above.
    private func markLocallyPro(product: String?) {
        do {
            guard let user = try fetchCurrentUser() else { return }
            user.planTier = .pro

            let subscription = try fetchOrCreateSubscription(userID: user.id)
            subscription.status = "active"
            if let product {
                subscription.product = product
            }
            try modelContext.save()
        } catch {
            logger.error("markLocallyPro: local SwiftData write failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// This device's local store holds exactly one `User` row (`Core/Sources/Core/Models/
    /// User.swift`'s doc comment), so the first (only) one is always the right one.
    private func fetchCurrentUser() throws -> User? {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchDefaultLockSet(userID: UUID) throws -> LockSet? {
        var descriptor = FetchDescriptor<LockSet>(
            predicate: #Predicate<LockSet> { $0.userID == userID && $0.isDefault == true }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateSubscription(userID: UUID) throws -> Subscription {
        var descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate<Subscription> { $0.userID == userID }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let created = Subscription(userID: userID)
        modelContext.insert(created)
        return created
    }
}
