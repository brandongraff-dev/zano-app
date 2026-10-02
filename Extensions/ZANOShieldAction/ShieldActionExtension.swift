import ManagedSettings
import UserNotifications
import os
import Core

// docs/spec.md §27 Known Platform Gotchas: "Shield buttons cannot open your app directly; the
// standard workaround is ShieldActionDelegate → local notification → tap opens app."
//
// One sec-style shield (2026-10-02, research item 3 in docs/design/growth-and-ml-research.md):
//   - "Close app" (primary) → counts one reclaimed open (`ReclaimedOpens.recordClose`, a single
//     App Group dictionary write) and responds `.close`, which closes the shielded app. No
//     notification: closing is the whole point, it shouldn't buzz.
//   - "Use Time Bank" (secondary) → posts a notification deep-linking to ZANO's Lock tab
//     (`ShieldCopy.DeepLink.lockTab`), where the Time Bank borrow/spend card and the 60-second
//     emergency-unlock hold both live, then `.close`. The notification body names the emergency
//     unlock, so the way out stays one tap away (spec §5.1, §24: "provide an in-app emergency
//     unlock with a short hold. Never trap users.").
// Copy comes from `ShieldCopy` (`Core/Sources/Core/Copy/ShieldCopy.swift`) in the user's coach
// voice; this file only reads App Group state and posts what `ShieldCopy` returns.
//
// This extension never unlocks anything itself — it only gets the user to the app, where the
// actual 60-second hold runs and `LockEngineManager.emergencyUnlock(sessionID:)` is the sole thing
// that ends the lock early. Keeping the grant in exactly one place (the in-app hold flow) is what
// makes CLAUDE.md's "any lock/shield feature must always keep an emergency-unlock path"
// enforceable.
//
// ShieldAction API as used here (iOS 18.5 SDK): `ShieldAction` has `.primaryButtonPressed` and
// `.secondaryButtonPressed`; `ShieldActionResponse` is `.none` / `.close` / `.defer`. There's no
// response that opens the containing app, hence the notification hand-off. Unverified on iOS 26+.
//
// No networking here either (docs/spec.md §11, §27) — `UNUserNotificationCenter.add` and the App
// Group defaults are both purely local.
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
        switch action {
        case .primaryButtonPressed:
            // "Close app": a reclaimed open. Close the shielded app and drop the user on the Home
            // Screen. Nothing is unlocked (this extension has no power to).
            ReclaimedOpens.recordClose()
            completionHandler(.close)

        case .secondaryButtonPressed:
            // "Use Time Bank": unconditional, never gated on any mirrored state. Close, then the
            // notification posted here lands a second later; tapping it opens the Lock tab with the
            // Time Bank card and the emergency unlock.
            let voice = CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice)
            let earned = SharedDefaults.earnedMinutesMirrorIsForToday ? SharedDefaults.earnedMinutesRemainingToday : 0
            post(ShieldCopy.timeBankNotification(voice: voice, mode: SharedDefaults.activeLockMode, earnedMinutes: earned))
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
