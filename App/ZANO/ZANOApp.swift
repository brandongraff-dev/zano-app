import Foundation
import SwiftUI
import SwiftData
import UserNotifications
import Core

@main
struct ZANOApp: App {
    init() {
        // docs/spec.md §23 "Instrument from day one": wire analytics/crash reporting at launch so
        // every later session's screen views, intents, unlock kinds, and shield impressions have
        // somewhere to land from day one instead of being retrofitted in later.
        //
        // Neither SPM package is added to project.yml yet (see docs/dependencies.md, Session 1),
        // so each block below is guarded with `#if canImport` — it compiles out entirely today
        // and starts running with no code changes once the package is linked. `Analytics.setup`
        // / `CrashReporting.setup` are themselves also no-ops without their SDK linked; the guard
        // here is belt-and-suspenders so this file never depends on either package existing.
        #if canImport(PostHog)
        Analytics.shared.setup(
            apiKey: Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? "",
            host: (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String)
                .flatMap(URL.init(string:)) ?? URL(string: "https://us.i.posthog.com")!
        )
        #endif

        #if canImport(Sentry)
        CrashReporting.shared.setup(
            dsn: Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
        )
        #endif

        // TODO(cross-module, Session 1): once the PostHog/Sentry accounts exist and the SPM
        // packages are added to project.yml (docs/PROGRESS.md currently lists both "Not
        // created"), add `POSTHOG_API_KEY` / `POSTHOG_HOST` / `SENTRY_DSN` to project.yml's
        // ZANO target Info.plist properties. Until real values are present there, both `setup`
        // calls above no-op on the empty string `Bundle.main` returns.

        // docs/spec.md §11 data flow: "every user action → App Intent → Core → SwiftData (App
        // Group) → widgets/shield read state instantly → Sync outbox pushes to Supabase when
        // online". `SyncEngine` is an actor (`Core/Sources/Core/Sync/SyncEngine.swift`) and must
        // be configured "once, as early as possible during app/extension launch" per its own doc
        // comment, before anything calls `enqueue` — `init()` itself can't be async, so this
        // fires the one-time configuration from a detached launch task instead. No `SyncBackend`
        // is supplied yet (Session 7, `feat/backend`, owns that); `enqueue` works without one and
        // only `flush()` needs it, so outbox rows queue safely from day one and start actually
        // pushing the moment Session 7 calls `SyncEngine.shared.setBackend(_:)`.
        Task {
            await SyncEngine.shared.configure(modelContainer: ModelContainer.appGroup)
        }

        // --- App-shell wiring (added when ContentView/AppRouter replaced the Session-0
        // placeholder; everything above this line is unchanged from the earlier wave). ---

        // RevenueCat (`RevenueCatManager.configure`'s own doc comment asks for exactly this call).
        // Deliberately NOT wrapped in `#if canImport(RevenueCat)` like the PostHog/Sentry blocks
        // above: `configure` already no-ops on an empty key and carries its own `#if canImport`
        // internally, and RevenueCat is a dependency of `Core`, not necessarily of this target — a
        // guard here could compile the call out even after the SDK is linked. The Info.plist key
        // doesn't exist in `project.yml` yet (same gap as POSTHOG_API_KEY above), so today this
        // passes "" and does nothing.
        RevenueCatManager.shared.configure(
            apiKey: Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
        )

        // Notification taps (docs/spec.md §27: shield buttons can't open the app, so
        // `ShieldActionExtension` posts a local notification whose tap must route somewhere).
        // `UNUserNotificationCenter.delegate` is a weak reference and must be set before launch
        // finishes to catch a cold-launch tap, hence here and hence `ZANONotificationDelegate.shared`.
        UNUserNotificationCenter.current().delegate = ZANONotificationDelegate.shared

        // Registers the Sunrise Alarm notification's "Open ZANO" action/category — its own doc
        // comment: "Intended to run once at app launch (ZANOApp.init...)". Only registers; it
        // never schedules anything or asks for permission.
        SunriseAlarmManager.shared.registerNotificationCategories()

        // Apple Watch link (`WatchSyncManager.activate()`: "call once, early at launch (the watch
        // may be waiting on the phone to wake it)"). Safe to call repeatedly and on a device with
        // no watch support; returns immediately (the work runs on the main actor afterwards).
        WatchSyncManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // `AppRouter` is a singleton (see its header for why); views read it from the
                // environment rather than reaching for the global.
                .environment(AppRouter.shared)
                // `zano://tag/<uuid>`, `zano://goals`, `zano://emergency` (+ the widgets'
                // `zano://today` / `zano://focus/end`) — docs/spec.md §6, §14, §27. NOTE: this
                // only fires if `project.yml`'s ZANO target registers the `zano` scheme under
                // `CFBundleURLTypes`, which it does not yet (flagged in this task's knownIssues).
                .onOpenURL { url in
                    AppRouter.shared.handle(url: url)
                }
        }
        // The one shared App Group SwiftData store (docs/spec.md §11/§13; `Core/Sources/Core/
        // Store/ModelContainer+AppGroup.swift`) — attached here so every view in the hierarchy
        // gets a working `\.modelContext`/`@Query` for free, instead of each Feature screen
        // reaching for `ModelContainer.appGroup` individually. `ModelContainer.appGroup` never
        // throws (it falls back to an in-memory container and logs a `.fault` if the App Group
        // entitlement is misconfigured — see that file's doc comment) so there is no `throws`/
        // `try?` to handle at this call site.
        .modelContainer(ModelContainer.appGroup)
    }
}

// MARK: - Notification routing

/// Receives notification taps/deliveries and hands them to `AppRouter`. Owned by `ZANOApp` (set as
/// the center's delegate in `init()`); kept in this file because it exists only to feed the app
/// shell and has no other caller.
///
/// Reads the three `userInfo` shapes this app posts (`NotificationRouting`):
///   - `["deepLink": "<zano:// URL>"]` from `ShieldActionExtension` — routed as a URL.
///   - `["zano.sunriseAlarm": true, ...]` from `SunriseAlarmManager`'s fallback-tier chain — makes
///     the alarm's ringing screen appear (`SunriseAlarmManager.beginRingingIfDue` is what flips
///     `isRinging` on).
///   - `["zano.onboardingDrip": "<OnboardingDripCondition raw value>"]` from
///     `OnboardingDripScheduler` — lands on the tab where that setup step lives.
///
/// Not actor-isolated and stateless, so `@unchecked Sendable` is honest (an `NSObject` subclass can't
/// be checked) and lets `shared` be a plain `static let`. `UNNotification`/`UNNotificationResponse`
/// are not `Sendable`, so each callback pulls out only `String`/`Bool` values before hopping to the
/// main actor via `await` — the non-`Sendable` `userInfo` dictionary never leaves this method.
final class ZANONotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ZANONotificationDelegate()

    /// A notification arriving while the app is open. Still shows it (banner + sound) — a shield
    /// or alarm notification is worthless if it is silently swallowed in the foreground — and, for
    /// the alarm chain, starts the ringing screen immediately instead of waiting for the next poll.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if Self.isSunriseAlarm(notification.request.content.userInfo) {
            await AppRouter.shared.beginAlarmIfDue()
        }
        return [.banner, .list, .sound]
    }

    /// The person tapped a notification (or one of its actions — the alarm's "Open ZANO" action is
    /// `.foreground`, so it lands here too).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let deepLink = userInfo[NotificationRouting.deepLinkUserInfoKey] as? String
        let isSunriseAlarm = Self.isSunriseAlarm(userInfo)
        let onboardingDrip = userInfo[NotificationRouting.onboardingDripUserInfoKey] as? String
        await AppRouter.shared.handleNotificationTap(
            deepLink: deepLink,
            isSunriseAlarm: isSunriseAlarm,
            onboardingDrip: onboardingDrip
        )
    }

    private static func isSunriseAlarm(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo[NotificationRouting.sunriseAlarmUserInfoKey] as? Bool) == true
    }
}
