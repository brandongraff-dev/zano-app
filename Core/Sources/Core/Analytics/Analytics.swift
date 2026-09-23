import Foundation

#if canImport(PostHog)
import PostHog
#endif

/// Thin, app-wide wrapper around PostHog.
///
/// Every call site in ZANO should go through `Analytics.shared` rather than touching
/// `PostHogSDK` directly, so the provider can be swapped later without hunting down call sites,
/// and so this file remains the one place that has to reason about the SDK not being linked yet.
///
/// docs/spec.md §23 ("Instrument from day one"): every screen view, every intent, every unlock
/// kind, and every shield impression (count only, aggregated on device) should eventually flow
/// through `capture(event:properties:)`. Wiring those individual call sites belongs to the
/// session that owns each surface (Lock Engine, Intents catalog, Shield extensions, screens) —
/// this file only provides the wrapper and the app-launch `setup` hook.
///
/// The feature-flag methods below (`featureFlag(key:)`, `featureFlagVariant(key:)`,
/// `isFeatureEnabled(key:)`, `reloadFeatureFlags()`) are this same "thin wrapper" story applied to
/// PostHog's experiments/feature-flags product rather than its events product. `ExperimentFlags.swift`
/// (same directory) is the one place that turns spec §23's "First 10 experiments" list into named,
/// typed flags built on top of these methods — call sites should reach for
/// `ExperimentFlags.<name>.resolve()`, not these raw string-keyed methods directly.
///
/// - Important: The PostHog SPM package is **not yet added** to `project.yml`
///   (see `docs/dependencies.md` — planned for Session 1). Every call into `PostHogSDK` below is
///   compiled only when `PostHog` can actually be imported, so this file — and any code that
///   calls it — builds cleanly both before and after the package is added. Until then, every
///   method below is a documented no-op; nothing here throws or crashes for its absence.
public final class Analytics: Sendable {
    public static let shared = Analytics()

    private init() {}

    /// Starts the PostHog SDK. Call once, as early as possible during app launch
    /// (see `ZANOApp.init`).
    ///
    /// - Parameters:
    ///   - apiKey: PostHog project API key. An empty value is treated as "not configured yet"
    ///     and skips setup entirely — no PostHog account exists yet (`docs/PROGRESS.md`).
    ///   - host: PostHog ingestion host. Defaults to PostHog Cloud (US).
    public func setup(apiKey: String, host: URL = URL(string: "https://us.i.posthog.com")!) {
        guard !apiKey.isEmpty else { return }
        #if canImport(PostHog)
        let config = PostHogConfig(apiKey: apiKey, host: host.absoluteString)
        PostHogSDK.shared.setup(config)
        #endif
    }

    /// Records a product event.
    ///
    /// Safe to call before `setup(apiKey:host:)` has run, or when PostHog isn't linked yet —
    /// the event is simply dropped rather than queued or thrown.
    ///
    /// - Parameters:
    ///   - event: A snake_case event name, e.g. `"unlock_earned"`, `"goal_completed"`,
    ///     `"shield_impression"`.
    ///   - properties: Event properties. Per spec §23/§24, these must stay on-device-aggregate
    ///     data only — never pass raw FamilyControls app tokens, precise location, or HealthKit
    ///     payloads here.
    public func capture(event: String, properties: [String: Any] = [:]) {
        #if canImport(PostHog)
        PostHogSDK.shared.capture(event, properties: properties)
        #endif
    }

    /// Associates all subsequent events with `userID`.
    ///
    /// Call once the user has a stable local identifier (see the Session 1 Store). Pass an
    /// opaque local ID, never an email address or other directly-identifying value
    /// (spec §23/§24).
    public func identify(userID: String) {
        #if canImport(PostHog)
        PostHogSDK.shared.identify(userID)
        #endif
    }

    // MARK: - Feature flags / experiments

    /// The raw value of a PostHog feature flag: `true`/`false` for a simple on/off flag, or the
    /// active variant's raw string key (e.g. `"after_plan"`) for a multivariate flag. `nil` before
    /// PostHog's flags have loaded for this device, before `setup(apiKey:host:)` has run, or when
    /// PostHog isn't linked at all (`#if canImport(PostHog)` false, same guard as every method
    /// above).
    ///
    /// `nil` here means "unknown, not yet resolved" — it is deliberately *not* coerced to
    /// `false`/"off", because a flag still loading and a flag genuinely turned off are different
    /// states and collapsing them would flicker every cold start to the off/control arm before
    /// the network round trip finishes. `ExperimentFlags.swift` (this same module) is built on
    /// top of this exact `nil` to fall back to each experiment's own hardcoded default instead.
    ///
    /// - Parameter key: The PostHog feature flag key, e.g. `"paywall_placement"`.
    public func featureFlag(key: String) -> Any? {
        #if canImport(PostHog)
        return PostHogSDK.shared.getFeatureFlag(key)
        #else
        return nil
        #endif
    }

    /// `featureFlag(key:)` narrowed to a multivariate flag's variant key.
    ///
    /// Returns the raw `String` variant (e.g. `"after_first_win"`), or `nil` when the flag hasn't
    /// resolved yet, PostHog isn't linked, or the flag is a plain boolean rather than a
    /// multivariate one (use `isFeatureEnabled(key:)` for those). This is the primitive
    /// `ExperimentFlag.resolve()` (`ExperimentFlags.swift`) reads through — nothing else in Core
    /// should need to call it directly.
    ///
    /// - Parameter key: The PostHog feature flag key.
    public func featureFlagVariant(key: String) -> String? {
        switch featureFlag(key: key) {
        case let variant as String:
            variant
        case let enabled as Bool:
            enabled ? "true" : "false"
        default:
            nil
        }
    }

    /// Whether a boolean PostHog feature flag is enabled.
    ///
    /// Returns `false` before the flag has loaded, before `setup(apiKey:host:)` has run, or when
    /// PostHog isn't linked — unlike `featureFlag(key:)`/`featureFlagVariant(key:)`, this collapses
    /// "not yet resolved" into `false`, which is only safe for callers that are fine defaulting to
    /// the control/off arm for the brief window before flags load. `ExperimentFlags.swift`'s
    /// on/off experiments still go through `featureFlagVariant(key:)` instead, so they get their
    /// own explicit default rather than always defaulting to `false`.
    ///
    /// - Parameter key: The PostHog feature flag key.
    public func isFeatureEnabled(key: String) -> Bool {
        #if canImport(PostHog)
        return PostHogSDK.shared.isFeatureEnabled(key)
        #else
        return false
        #endif
    }

    /// Forces a fresh feature-flag fetch from PostHog.
    ///
    /// Call after `identify(userID:)` so a newly-identified user is re-evaluated against their own
    /// flag assignments instead of the anonymous-device ones PostHog cached before sign-in.
    /// No-op when PostHog isn't linked.
    public func reloadFeatureFlags() {
        #if canImport(PostHog)
        PostHogSDK.shared.reloadFeatureFlags()
        #endif
    }
}
