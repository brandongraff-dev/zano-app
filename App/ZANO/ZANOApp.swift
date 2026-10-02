import Foundation
import SwiftUI
import UIKit
import SwiftData
import UserNotifications
import Core

@main
struct ZANOApp: App {
    /// Drives the focus-session anti-cheat (spec section 3: "Leaving the app pauses timer").
    @Environment(\.scenePhase) private var scenePhase
    /// Set when the shared SwiftData store couldn't be opened (audit W1). The app then shows
    /// `StoreUnavailableView` instead of running against an empty in-memory fallback whose writes
    /// would vanish on the next launch (and whose onboarding would start over).
    private let storeOpenFailure: String?

    init() {
        #if DEBUG
        // Unsigned Simulator builds (CI, previews) get no App Group container at all, so they
        // always run on the in-memory fallback by design. Only real open failures stop a debug run.
        let failure = ModelContainer.appGroupOpenFailure
        storeOpenFailure = (failure?.contains("appGroupContainerUnavailable") ?? false) ? nil : failure
        #else
        storeOpenFailure = ModelContainer.appGroupOpenFailure
        #endif

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

        // Re-open the gym geofence monitor at launch (Wave 1A). Must run before the first frame:
        // when iOS relaunches the app in the background for a gym arrival/exit, CLMonitor only
        // delivers that event to a monitor re-created (same name) early in launch.
        GymPresenceService.shared.start()

        // Steps / home-workout verification for every active goal, not only while Today is on
        // screen (audit L6). Early in launch on purpose: when HealthKit relaunches the app in the
        // background for a step-count delivery, the observer query has to be re-registered right
        // away to receive it. Never prompts for Health access.
        Task { await HealthGoalChecks.run() }

        // CI screenshot gallery (ScreenshotGallery.swift). DEBUG builds only, and inert unless
        // `-ZANOScreen <name>` is passed, which no user launch ever does.
        #if DEBUG
        if let name = ScreenshotMode.screen { ScreenshotMode.prepare(screen: name) }
        #endif

        Self.configureNavigationBarTitles()
    }

    /// Large navigation titles (Fuel, Progress, Settings, Lock sets…) in the same condensed heavy
    /// face as `Theme.Typography.titleLarge`, so a tab with a system large title and a tab that
    /// draws its own header (Today) read as one family. SwiftUI has no API for the navigation
    /// bar's title font, so this is the one place the app reaches for UIKit appearance proxies.
    private static func configureNavigationBarTitles() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .heavy, width: .condensed)
        ]
        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .bold, width: .condensed)
        ]
    }

    @ViewBuilder
    private var rootContent: some View {
        if storeOpenFailure != nil {
            StoreUnavailableView()
        } else {
            appContent
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
        if let name = ScreenshotMode.screen {
            ScreenshotHost(name: name)
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                // `AppRouter` is a singleton (see its header for why); views read it from the
                // environment rather than reaching for the global.
                .environment(AppRouter.shared)
                // `zano://tag/<uuid>`, `zano://goals`, `zano://emergency` (+ the widgets'
                // `zano://today` / `zano://focus/end`) — docs/spec.md §6, §14, §27. Delivered
                // because `project.yml`'s ZANO target registers the `zano` scheme under
                // `CFBundleURLTypes`.
                .onOpenURL { url in
                    AppRouter.shared.handle(url: url)
                }
                // Focus sessions (audit L3/L4): re-adopt a session persisted before the app was
                // killed (verifying it if its time already ran), resume the one leaving the app
                // paused, and pause in-app sessions the moment the app goes to the background.
                // `.inactive` (Control Center, a notification pull-down) doesn't count as leaving.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        Task { await FocusSessionVerifier.shared.appDidBecomeActive() }
                    case .background:
                        FocusSessionVerifier.shared.appDidEnterBackground()
                    default:
                        break
                    }
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

// MARK: - Store unavailable (audit W1)

/// Shown instead of the app when the shared store couldn't be opened
/// (`ModelContainer.appGroupOpenFailure`). No lock can be read from here, so the usual emergency
/// unlock can't run: "Unlock my apps" lifts ZANO's shield directly (never trap the user).
private struct StoreUnavailableView: View {
    @Environment(\.openURL) private var openURL
    @State private var didUnlock = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Text(Copy.storeRecovery.title)
                .zanoText(.title)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.storeRecovery.body)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if didUnlock {
                Text(Copy.storeRecovery.unlockedConfirmation)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
            }
            Spacer(minLength: 0)
            PrimaryButton(title: Copy.storeRecovery.unlockButtonLabel, systemImage: "lock.open") {
                ScheduledLockMonitor.liftAllShieldsForRecovery()
                didUnlock = true
            }
            PrimaryButton(title: Copy.storeRecovery.contactLabel, systemImage: "envelope", style: .secondary) {
                if let url = URL(string: "mailto:\(Copy.settings.supportEmail)") { openURL(url) }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .zanoBackdrop()
        .preferredColorScheme(.dark)
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
