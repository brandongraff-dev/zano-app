import Foundation

#if canImport(Sentry)
import Sentry
#endif

/// Thin, app-wide wrapper around Sentry — same pattern as `Analytics`, for crash/error
/// reporting instead of product events.
///
/// Every call site in ZANO should go through `CrashReporting.shared` rather than touching
/// `SentrySDK` directly.
///
/// - Important: The Sentry SPM package is **not yet added** to `project.yml`
///   (see `docs/dependencies.md` — planned for Session 1). Every call into `SentrySDK` below is
///   compiled only when `Sentry` can actually be imported, so this file — and any code that
///   calls it — builds cleanly both before and after the package is added. Until then, every
///   method below is a documented no-op; nothing here throws or crashes for its absence.
public final class CrashReporting: Sendable {
    public static let shared = CrashReporting()

    private init() {}

    /// Starts the Sentry SDK. Call once, as early as possible during app launch
    /// (see `ZANOApp.init`).
    ///
    /// - Parameter dsn: Sentry DSN. An empty value is treated as "not configured yet" and skips
    ///   setup entirely — no Sentry account exists yet (`docs/PROGRESS.md`).
    public func setup(dsn: String) {
        guard !dsn.isEmpty else { return }
        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.debug = true
            options.environment = "debug"
            #else
            options.environment = "release"
            #endif
            // FamilyControls tokens, precise location, and HealthKit payloads must never reach
            // crash reports (spec §23/§24). Callers of `capture`/`addBreadcrumb` are responsible
            // for keeping the context they pass free of that data; this wrapper does not scrub
            // beyond Sentry's own PII defaults.
            options.sendDefaultPii = false
        }
        #endif
    }

    /// Associates subsequent crash/error reports with `userID`.
    ///
    /// Pass an opaque local identifier, never an email address or other directly-identifying
    /// value (spec §23/§24).
    public func identify(userID: String) {
        #if canImport(Sentry)
        let user = User()
        user.userId = userID
        SentrySDK.setUser(user)
        #endif
    }

    /// Reports a caught error.
    public func capture(error: Error) {
        #if canImport(Sentry)
        SentrySDK.capture(error: error)
        #endif
    }

    /// Reports a freeform message — for invariant violations or unexpected states that aren't
    /// modeled as an `Error`.
    public func capture(message: String) {
        #if canImport(Sentry)
        SentrySDK.capture(message: message)
        #endif
    }

    /// Leaves a breadcrumb for context on the next crash/error report in this session, e.g.
    /// `"lock_started"` / `"lockEngine"` just before a risky call.
    public func addBreadcrumb(message: String, category: String) {
        #if canImport(Sentry)
        let breadcrumb = Breadcrumb(level: .info, category: category)
        breadcrumb.message = message
        SentrySDK.addBreadcrumb(breadcrumb)
        #endif
    }
}
