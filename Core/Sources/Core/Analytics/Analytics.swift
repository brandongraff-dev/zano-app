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
}
