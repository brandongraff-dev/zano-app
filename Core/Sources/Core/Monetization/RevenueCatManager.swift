// RevenueCatManager.swift
// Core / Monetization
//
// docs/spec.md §21 (Monetization & Paywall): Free/Pro tiers, price tests (monthly $6.99, annual
// $39.99 highlighted, lifetime $59.99 test-only), a 7-day trial with a pre-expiry reminder, and
// the hard rule "Never sell: unlocks, streak restores, or anything that lets money bypass the
// goal." This file is the **only** place in ZANO that talks to the RevenueCat SDK —
// `PaywallViewModel` (this same directory) and every other call site go through
// `RevenueCatManager.shared` and its SDK-agnostic value types below, never `import RevenueCat`
// themselves. That mirrors `Core/Sources/Core/Analytics/Analytics.swift`'s PostHog wrapper for
// the same two reasons: the provider can be swapped/mocked later without hunting down call
// sites, and exactly one file has to reason about the SDK not being linked yet.
//
// docs/dependencies.md lists RevenueCat (https://github.com/RevenueCat/purchases-ios) as "Add
// in: Session 6" and it is **not yet added** to `project.yml` as of this task — per that file's
// own instructions, dependency versions are resolved via Xcode's "Add Package Dependency" on a
// Mac, never hand-pinned here. Every call into the `RevenueCat` module below is therefore
// guarded by `#if canImport(RevenueCat)`, exactly like `Analytics.swift`/`CrashReporting.swift`
// guard `PostHog`/`Sentry`: this file compiles cleanly today (package absent — no Mac/Swift
// toolchain exists in this session to verify that compile either, but the guard is the same
// proven pattern already merged into this repo) and starts actually calling RevenueCat the
// moment the package is added to `project.yml` — no code change required here. Flagged again in
// this task's knownIssues, as instructed.
//
// API surface below (Purchases.configure/offerings()/purchase(package:)/restorePurchases()/
// customerInfo(), Offerings.current, Offering.availablePackages, Package.identifier/packageType/
// storeProduct, PackageType cases, StoreProduct.localizedPriceString/price/subscriptionPeriod/
// introductoryDiscount/priceFormatter, SubscriptionPeriod.value/unit/numberOfUnitsAs(unit:),
// StoreProductDiscount.paymentMode/subscriptionPeriod, CustomerInfo.entitlements,
// EntitlementInfos.all, EntitlementInfo.isActive) was checked against the RevenueCat/
// purchases-ios `main` branch source on GitHub during this task — these are real, verified
// method/type names, not guessed from memory. What could **not** be verified without a Swift
// compiler in this environment: that these calls actually compile together end-to-end, that
// `PurchaseResultData`'s field names/labels are used correctly at every call site below, and
// that no newer/older SDK version renamed something since the snapshot this task read. Flagged
// plainly in knownIssues rather than presented as certain, per this task's instructions.

import Foundation
import os

#if canImport(RevenueCat)
import RevenueCat
#endif

// MARK: - Errors

/// Errors `RevenueCatManager` throws itself, plus a passthrough case for whatever RevenueCat/
/// StoreKit throws that this file has no compiler to verify a typed mapping against (see file
/// header). Kept as plain, developer-facing diagnostics — mirrors the `LockEngineError`/
/// `FocusSessionVerifierError` convention already in this codebase (`Core/Sources/Core/
/// LockEngine/LockEngineManager.swift`, `Core/Sources/Core/Verification/
/// FocusSessionVerifier.swift`) — not routed through `Core/Sources/Core/Copy`: whatever
/// user-facing message `PaywallViewModel`/`PaywallView` choose to show for one of these belongs
/// in `Copy`, per CLAUDE.md, not here.
public enum RevenueCatManagerError: Error, Sendable, Equatable, LocalizedError {
    /// RevenueCat isn't linked yet (`#if canImport(RevenueCat)` compiled out — see file header)
    /// or `configure(apiKey:)` hasn't been called/hasn't run yet (e.g. an empty API key, matching
    /// `Analytics.setup(apiKey:)`'s same "not configured yet" convention).
    case notConfigured
    /// `Offerings.current` was `nil` — no offering configured in the RevenueCat dashboard yet, or
    /// none targeted at this user/placement.
    case noCurrentOffering
    /// `purchase(_:)` was called with a `SubscriptionPackage` whose `id` isn't one this manager's
    /// most recent `fetchOfferings()` result returned (stale UI state, or offerings changed
    /// server-side between fetch and tap).
    case packageNotFound(String)
    /// The purchase sheet was dismissed/cancelled by the user (`PurchaseResultData.userCancelled
    /// == true`). Deliberately its own case, not folded into `.underlying`: spec §21 "no dark
    /// patterns" — a cancelled purchase is a normal outcome `PaywallViewModel` should return to
    /// idle for, not an error alert to alarm the user with.
    case purchaseCancelled
    /// Wraps whatever RevenueCat/StoreKit itself threw, stringified.
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "In-app purchases are not available right now."
        case .noCurrentOffering:
            "No subscription plans are configured right now."
        case .packageNotFound(let id):
            "Plan \(id) is no longer available — try refreshing."
        case .purchaseCancelled:
            "Purchase cancelled."
        case .underlying(let message):
            message
        }
    }
}

// MARK: - SDK-agnostic value types
//
// `PaywallViewModel`/`PaywallView` (and any future call site — a Settings "Upgrade" screen,
// etc.) build their UI from these, never from RevenueCat's own `Package`/`StoreProduct`/
// `CustomerInfo` types, so only this one file ever needs `import RevenueCat` (see file header).

/// One purchasable plan, mapped from a RevenueCat `Package` by `fetchOfferings()`.
public struct SubscriptionPackage: Sendable, Identifiable, Hashable {
    /// Mirrors RevenueCat's `PackageType` (docs.revenuecat.com convention: `$rc_monthly`,
    /// `$rc_annual`, etc. identifiers on the dashboard), kept as ZANO's own enum so nothing
    /// outside this file needs to know the RevenueCat type exists.
    public enum Period: String, Sendable, Hashable, CaseIterable {
        case weekly, monthly, twoMonth, threeMonth, sixMonth, annual, lifetime, other
    }

    /// RevenueCat `Package.identifier` (e.g. `"$rc_annual"`, or a custom identifier from the
    /// dashboard). Stable key for `purchase(_:)` to resolve the real `Package` back out of
    /// `RevenueCatManager`'s private cache.
    public let id: String
    /// The underlying App Store Connect product identifier (`StoreProduct.productIdentifier`).
    public let productIdentifier: String
    public let period: Period
    /// Localized, store-formatted total price for this package's period (`StoreProduct.
    /// localizedPriceString`, e.g. `"$39.99"`).
    public let priceString: String
    /// For a package longer than one month (annual, 6-/3-/2-month), the equivalent monthly cost,
    /// localized (e.g. `"$3.33/mo"`) — spec §16 P5 mockup shows this alongside the annual price.
    /// `nil` for monthly-or-shorter packages, whose `priceString` already reads as a per-period
    /// rate, and for anything this file couldn't confidently format (see `pricePerMonthString(
    /// for:)` below).
    public let pricePerMonthString: String?
    /// Trial length in days, present when this package carries a free-trial introductory offer
    /// (`StoreProductDiscount.paymentMode == .freeTrial`) — spec §21: "7-day trial... (test
    /// 3-day vs 7-day)". `nil` if this package has no trial.
    public let introductoryTrialDays: Int?

    public init(
        id: String,
        productIdentifier: String,
        period: Period,
        priceString: String,
        pricePerMonthString: String? = nil,
        introductoryTrialDays: Int? = nil
    ) {
        self.id = id
        self.productIdentifier = productIdentifier
        self.period = period
        self.priceString = priceString
        self.pricePerMonthString = pricePerMonthString
        self.introductoryTrialDays = introductoryTrialDays
    }
}

/// Result of `fetchOfferings()`: the current RevenueCat offering's packages, in the order
/// `Offering.availablePackages` returns them (dashboard-configured order).
public struct SubscriptionOfferings: Sendable, Equatable {
    /// `Offering.identifier` (e.g. `"default"`).
    public let offeringIdentifier: String
    public let packages: [SubscriptionPackage]

    public init(offeringIdentifier: String, packages: [SubscriptionPackage]) {
        self.offeringIdentifier = offeringIdentifier
        self.packages = packages
    }
}

// MARK: - RevenueCatManager

/// The sole owner of every call into the RevenueCat SDK (see file header).
///
/// `@MainActor`, matching `LockEngineManager`/`FocusSessionVerifier`'s own documented reasoning
/// (`Core/Sources/Core/LockEngine/LockEngineManager.swift`): every real call site is a SwiftUI
/// view or an `@Observable` view model already on the main actor (`PaywallViewModel`, this same
/// directory), and this keeps the type trivially `Sendable` under Swift 6 strict concurrency with
/// no `Sendable`-conformance gymnastics around the RevenueCat SDK's own reference types.
@MainActor
public final class RevenueCatManager {
    public static let shared = RevenueCatManager()

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "RevenueCatManager")
    private var isConfigured = false

    #if canImport(RevenueCat)
    /// Keyed by `SubscriptionPackage.id`, refreshed on every `fetchOfferings()` call, so
    /// `purchase(_:)` can resolve the real RevenueCat `Package` a caller's SDK-agnostic
    /// `SubscriptionPackage` came from without this type ever exposing `Package` in its public
    /// API (see file header).
    private var packagesByID: [String: Package] = [:]
    #endif

    /// `internal`, not `private`, only so `CoreTests` can exercise the mapping/error-path logic
    /// against an isolated instance; every real call site uses `.shared`.
    init() {}

    // MARK: - Configure

    /// Starts the RevenueCat SDK. Call once, as early as possible during app launch — mirrors
    /// `Analytics.setup(apiKey:host:)`'s exact convention (`Core/Sources/Core/Analytics/
    /// Analytics.swift`): an empty `apiKey` is treated as "not configured yet" and skips setup
    /// entirely, matching that no RevenueCat project exists yet (`docs/PROGRESS.md`). Safe to
    /// call more than once — a second call is a no-op once already configured, since RevenueCat
    /// itself warns against re-configuring a running SDK instance.
    ///
    /// TODO(cross-module integration — `App/ZANO/ZANOApp.swift`; not this task's file to edit
    /// per CLAUDE.md "stay strictly inside your assigned file list"): `ZANOApp.init` currently
    /// calls `Analytics.shared.setup`/`CrashReporting.shared.setup`, each guarded by `#if
    /// canImport(PostHog)`/`#if canImport(Sentry)`, but has no equivalent call to
    /// `RevenueCatManager.shared.configure(apiKey:)` yet. Add one there (guarded the same way
    /// with `#if canImport(RevenueCat)`, reading a `"REVENUECAT_API_KEY"` `Info.plist` value the
    /// way the existing two calls read `POSTHOG_API_KEY`/`SENTRY_DSN`) once RevenueCat is added
    /// to `project.yml` (Session 6, `docs/dependencies.md`) and a RevenueCat project/API key
    /// exist. Until then, every method below simply returns `.notConfigured`/`false` — see each
    /// method's doc comment — so nothing crashes for this being unwired yet.
    ///
    /// - Parameter apiKey: RevenueCat public SDK key (App Store app, from the RevenueCat
    ///   dashboard). Never a secret/private key — this is safe to embed client-side by design.
    public func configure(apiKey: String) {
        guard !apiKey.isEmpty, !isConfigured else { return }
        #if canImport(RevenueCat)
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true
        logger.notice("RevenueCat configured.")
        #endif
    }

    // MARK: - CONTRACTS: fetchOfferings / purchase / restorePurchases / isProSubscriber
    //
    // Exact method names per this task's brief ("wraps `import RevenueCat`... behind
    // fetchOfferings/purchase/restorePurchases/isProSubscriber"). Signatures are this file's own
    // design — `RevenueCatManager` is not one of this batch's predefined SYSTEM CONTRACTS types.

    /// Fetches the current RevenueCat offering and maps it to SDK-agnostic `SubscriptionPackage`
    /// values for `PaywallViewModel` to render (spec §21; spec §16 P5 mockup: an annual package
    /// highlighted, a smaller monthly option).
    ///
    /// - Throws: `.notConfigured` if RevenueCat isn't linked/configured yet, `.noCurrentOffering`
    ///   if the dashboard has no current offering, or `.underlying` for anything the SDK itself
    ///   throws (e.g. no network on first launch with no cached offerings).
    public func fetchOfferings() async throws -> SubscriptionOfferings {
        #if canImport(RevenueCat)
        guard isConfigured else { throw RevenueCatManagerError.notConfigured }

        let offerings: Offerings
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            throw RevenueCatManagerError.underlying(String(describing: error))
        }
        guard let current = offerings.current else {
            throw RevenueCatManagerError.noCurrentOffering
        }

        packagesByID = Dictionary(
            uniqueKeysWithValues: current.availablePackages.map { ($0.identifier, $0) }
        )
        let mapped = current.availablePackages.map(Self.mapPackage)
        logger.notice("Fetched offering \(current.identifier, privacy: .public) with \(mapped.count, privacy: .public) package(s).")
        return SubscriptionOfferings(offeringIdentifier: current.identifier, packages: mapped)
        #else
        throw RevenueCatManagerError.notConfigured
        #endif
    }

    /// Purchases `package` (a value previously returned by `fetchOfferings()`).
    ///
    /// - Returns: `true` if the resulting `CustomerInfo` grants the Pro entitlement (spec §21) —
    ///   i.e. the purchase should be treated as an immediate Pro unlock. Returned rather than
    ///   assumed so a misconfigured entitlement identifier on the RevenueCat dashboard fails safe
    ///   (caller sees "not Pro yet") instead of silently granting access to whatever was
    ///   actually purchased.
    /// - Throws: `.purchaseCancelled` if the user dismissed the purchase sheet (spec §21 "no dark
    ///   patterns" — a normal outcome, not an alarming error; `PaywallViewModel` returns to
    ///   `.idle` for this, not `.failed`), `.packageNotFound` if `package.id` isn't from the last
    ///   `fetchOfferings()`, `.notConfigured`, or `.underlying` for anything StoreKit/RevenueCat
    ///   itself throws (e.g. `.paymentPending`, network failure).
    @discardableResult
    public func purchase(_ package: SubscriptionPackage) async throws -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { throw RevenueCatManagerError.notConfigured }
        guard let rcPackage = packagesByID[package.id] else {
            throw RevenueCatManagerError.packageNotFound(package.id)
        }
        do {
            let result = try await Purchases.shared.purchase(package: rcPackage)
            if result.userCancelled {
                throw RevenueCatManagerError.purchaseCancelled
            }
            let granted = Self.isPro(result.customerInfo)
            logger.notice("Purchased \(package.id, privacy: .public); pro entitlement active=\(granted, privacy: .public).")
            return granted
        } catch let error as RevenueCatManagerError {
            throw error
        } catch {
            throw RevenueCatManagerError.underlying(String(describing: error))
        }
        #else
        throw RevenueCatManagerError.notConfigured
        #endif
    }

    /// Restores previous purchases. App Store rules (and spec §24 "restore purchases visible")
    /// require this to always be reachable from the paywall.
    ///
    /// - Returns: `true` if the restored `CustomerInfo` grants the Pro entitlement.
    /// - Throws: `.notConfigured` or `.underlying`.
    @discardableResult
    public func restorePurchases() async throws -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { throw RevenueCatManagerError.notConfigured }
        do {
            let info = try await Purchases.shared.restorePurchases()
            let granted = Self.isPro(info)
            logger.notice("Restored purchases; pro entitlement active=\(granted, privacy: .public).")
            return granted
        } catch {
            throw RevenueCatManagerError.underlying(String(describing: error))
        }
        #else
        throw RevenueCatManagerError.notConfigured
        #endif
    }

    /// Whether purchases are wired up at all (RevenueCat linked AND an API key supplied). False in
    /// development, CI and any build made before the RevenueCat account exists.
    public var isConfiguredForPurchases: Bool {
        #if canImport(RevenueCat)
        return isConfigured
        #else
        return false
        #endif
    }

    /// Three-way entitlement answer for the hard paywall (`EntitlementGate`). Unlike
    /// `isProSubscriber()`, which folds "couldn't check" into `false`, this keeps the cases apart:
    /// a paying user who is offline, or a build with no RevenueCat key, must never be treated as
    /// "not subscribed" and locked out.
    public func entitlementCheck() async -> EntitlementCheck {
        #if canImport(RevenueCat)
        guard isConfigured else { return .unavailable }
        guard let info = try? await Purchases.shared.customerInfo() else { return .unavailable }
        return Self.isPro(info) ? .entitled : .notEntitled
        #else
        return .unavailable
        #endif
    }

    /// Current Pro entitlement state (spec §21 tiers). Never throws — deliberately, unlike the
    /// three methods above: this is read on ordinary screen loads/gating checks, and a
    /// transient network failure or an unconfigured SDK must degrade to `false` (treated as Free
    /// tier) rather than crash or hang the caller, the same "never trap the user" spirit CLAUDE.md
    /// states for locks. Callers that need to distinguish "genuinely Free" from "couldn't check
    /// right now" for a local-first fallback should cross-check `User.planTier`/`Subscription`
    /// (`Core/Sources/Core/Models`) themselves — `PaywallViewModel` does exactly that; see its own
    /// doc comment.
    public func isProSubscriber() async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { return false }
        guard let info = try? await Purchases.shared.customerInfo() else { return false }
        return Self.isPro(info)
        #else
        return false
        #endif
    }

    // MARK: - Mapping (RevenueCat types -> SDK-agnostic value types)

    #if canImport(RevenueCat)
    /// The RevenueCat entitlement identifier that gates Pro features (spec §21).
    ///
    /// Assumption, not verifiable without RevenueCat dashboard access from this environment:
    /// entitlement identifiers are configured per-project on revenuecat.com, not derivable from
    /// the SDK. `"pro"` mirrors `PlanTier.pro`'s raw value (`Core/Sources/Core/Models/
    /// User.swift`) as the most likely match — whoever sets up the RevenueCat project (Session 6
    /// or 7) must confirm this string matches the dashboard exactly, or every entitlement check
    /// in this file silently reads `false` forever. Flagged in this task's knownIssues.
    static let proEntitlementIdentifier = "pro"

    private static func isPro(_ info: CustomerInfo) -> Bool {
        info.entitlements.all[proEntitlementIdentifier]?.isActive == true
    }

    private static func mapPackage(_ package: Package) -> SubscriptionPackage {
        let product = package.storeProduct
        return SubscriptionPackage(
            id: package.identifier,
            productIdentifier: product.productIdentifier,
            period: period(for: package.packageType),
            priceString: product.localizedPriceString,
            pricePerMonthString: pricePerMonthString(for: product),
            introductoryTrialDays: trialDays(for: product)
        )
    }

    private static func period(for packageType: PackageType) -> SubscriptionPackage.Period {
        switch packageType {
        case .weekly: .weekly
        case .monthly: .monthly
        case .twoMonth: .twoMonth
        case .threeMonth: .threeMonth
        case .sixMonth: .sixMonth
        case .annual: .annual
        case .lifetime: .lifetime
        default: .other // .unknown, .custom
        }
    }

    /// `nil` for a monthly-or-shorter package (its `priceString` already reads as the per-period
    /// rate). For anything longer (annual, six/three/two-month), divides the total price by the
    /// period's length in months.
    ///
    /// Uses `SubscriptionPeriod.numberOfUnitsAs(unit:)` (public API) rather than RevenueCat's own
    /// `pricePerMonth(withTotalPrice:)` helper on the same type — that helper is declared without
    /// `public` in the source this task checked (`Sources/Purchasing/StoreKitAbstractions/
    /// SubscriptionPeriod.swift`), i.e. internal to the RevenueCat module and not callable from
    /// here.
    private static func pricePerMonthString(for product: StoreProduct) -> String? {
        guard let period = product.subscriptionPeriod else { return nil }
        let months = period.numberOfUnitsAs(unit: .month)
        guard months > 1 else { return nil }

        let perMonth = (product.price as NSDecimalNumber)
            .dividing(by: months as NSDecimalNumber) as Decimal
        guard let formatter = product.priceFormatter,
              let formatted = formatter.string(from: NSDecimalNumber(decimal: perMonth))
        else { return nil }
        return "\(formatted)/mo"
    }

    private static func trialDays(for product: StoreProduct) -> Int? {
        guard let discount = product.introductoryDiscount, discount.paymentMode == .freeTrial else {
            return nil
        }
        let days = discount.subscriptionPeriod.numberOfUnitsAs(unit: .day)
        return NSDecimalNumber(decimal: days).intValue
    }
    #endif
}
