import ManagedSettings
import UserNotifications
import os
import Core

// docs/spec.md §27 Known Platform Gotchas: "Shield buttons cannot open your app directly; the
// standard workaround is ShieldActionDelegate → local notification → tap opens app." Both shield
// buttons follow that path here:
//   - "Show my goals" (primary) → posts a notification deep-linking to `zano://goals`.
//   - "Emergency" (secondary)   → posts a notification deep-linking to `zano://emergency`, the
//     60-second emergency-unlock hold screen (spec §5.1, §24: "provide an in-app emergency
//     unlock with a short hold. Never trap users.").
// Copy for both notifications is composed by `ShieldCopy`
// (`Core/Sources/Core/Copy/ShieldCopy.swift`) from the user's coach voice — this file only reads
// that voice from the App Group and posts what `ShieldCopy` returns.
//
// This extension never grants the emergency unlock itself — it only gets the user to the app,
// where the actual 60-second hold runs and `LockEngineManager.emergencyUnlock(sessionID:)`
// (system contract, `Core/Sources/Core/LockEngine/LockEngineManager.swift`) is the sole thing
// that ends the lock. Keeping the grant in exactly one place (the in-app hold flow) is what makes
// CLAUDE.md's "any lock/shield feature must always keep an emergency-unlock path" enforceable —
// an extension that could grant it unilaterally would make "never trap the user" and "never let
// the user skip the hold" two different promises instead of one.
//
// No networking here either (docs/spec.md §11, §27) — `UNUserNotificationCenter.add` and
// `SharedDefaults` are both purely local/App-Group calls.
class ShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for _: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for _: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for _: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    // MARK: - Shared handling

    /// Both buttons resolve the same way regardless of *what* is shielded (a single app, a web
    /// domain, or a whole category) — only *which* button matters, so all three `handle` overrides
    /// above funnel into this one implementation instead of triple-writing the same switch.
    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let voice = CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice)

        switch action {
        case .primaryButtonPressed:
            post(ShieldCopy.showGoalsNotification(
                voice: voice,
                goalsRemaining: SharedDefaults.goalsRemainingForActiveLock
            ))
            // `.close` dismisses the shield's action UI immediately — the shield itself stays up
            // (this extension has no power to unlock anything), but the user is never stuck on a
            // frozen button waiting for a response (CLAUDE.md: never trap the user).
            completionHandler(.close)

        case .secondaryButtonPressed:
            post(ShieldCopy.emergencyNotification(voice: voice))
            completionHandler(.close)

        @unknown default:
            // A future OS could add a third button we don't know about yet; closing is the safe,
            // non-trapping default rather than leaving the shield's action sheet hanging.
            completionHandler(.close)
        }
    }

    /// Schedules the local notification described by `content`. A short (1s) time-interval
    /// trigger is used rather than firing with no trigger at all — this extension's process is
    /// short-lived and may suspend the instant `completionHandler` runs, so the notification is
    /// scheduled to fire just after, not delivered synchronously in-process.
    private func post(_ content: ShieldCopy.NotificationContent) {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        // `App/ZANO`'s notification-response handling (session that owns `onOpenURL`/App Intents
        // routing) reads this to know where to deep-link — see the TODO on `ShieldCopy.DeepLink`.
        notification.userInfo = ["deepLink": content.deepLink.absoluteString]

        let request = UNNotificationRequest(
            identifier: content.identifier,
            content: notification,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            // Best-effort only: notification permission is requested during onboarding, not
            // here (an extension should never itself prompt for permissions) — if it hasn't been
            // granted yet, `add` fails and this is simply logged, never a crash. The shield has
            // already been told to close either way, so the user isn't left stuck on either
            // outcome.
            Self.logger.error("Failed to post shield notification \(content.identifier, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "com.zano.app.ZANOShieldAction", category: "ShieldActionExtension")
}
