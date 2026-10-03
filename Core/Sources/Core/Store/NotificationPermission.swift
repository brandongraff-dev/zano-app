// Core/Sources/Core/Store/NotificationPermission.swift
//
// Notification permission and one-shot local notifications, as Sendable values only.
//
// Same reason as `NotificationCenterQueries.swift` (this directory): a completion handler written
// inside a `@MainActor` type is main-actor isolated, the notification center calls it on a
// background queue, and Swift 6's runtime check traps. Every function here is `nonisolated` and
// builds/consumes the non-Sendable `UNNotification*` objects locally, so callers on the main actor
// only ever pass and receive strings, dates and enums.
//
// Callers (audit N2, 2026-10-02): the paywall's "Remind me before my trial ends" toggle, Today's
// Finish setup "Turn on notifications" item, and the first lock start. Asking only when the status
// is still `.notDetermined` keeps it to one system prompt per install.

import Foundation
import UserNotifications

public enum NotificationPermission {
    /// The three states a screen needs to tell apart.
    public enum Status: Sendable, Equatable {
        /// Never asked: asking shows the system prompt.
        case notDetermined
        /// Asked and refused (or restricted): only the Settings app can turn it on.
        case denied
        /// Authorized, provisional or ephemeral: the app can post.
        case allowed
    }

    public nonisolated static func status() async -> Status {
        await withCheckedContinuation { (continuation: CheckedContinuation<Status, Never>) in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let mapped: Status
                switch settings.authorizationStatus {
                case .notDetermined: mapped = .notDetermined
                case .authorized, .provisional, .ephemeral: mapped = .allowed
                case .denied: mapped = .denied
                @unknown default: mapped = .denied
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    /// Shows the system prompt only if it has never been answered. Returns the status afterwards.
    @discardableResult
    public nonisolated static func requestIfUndetermined() async -> Status {
        let current = await status()
        guard current == .notDetermined else { return current }
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .allowed : .denied
    }

    /// Schedules (or replaces, same `identifier`) one local notification at `date`. Returns `false`
    /// when `date` is in the past, posting isn't allowed, or the center refused the request.
    /// `deepLink` is routed by `ZANONotificationDelegate` (`"deepLink"` userInfo key). With a
    /// `buddyPose`, the user's buddy in that pose is attached as the image (`BuddyNotificationImage`;
    /// silently none if it can't be made).
    @discardableResult
    public nonisolated static func scheduleOneShot(
        identifier: String,
        title: String,
        body: String,
        at date: Date,
        deepLink: String?,
        buddyPose: BuddyPose? = nil,
        now: Date = .now
    ) async -> Bool {
        let interval = date.timeIntervalSince(now)
        guard interval > 1 else { return false }
        guard await status() == .allowed else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let deepLink {
            content.userInfo = [deepLinkUserInfoKey: deepLink]
        }
        if let buddyPose, let attachment = BuddyNotificationImage.attachment(pose: buddyPose) {
            content.attachments = [attachment]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().add(request) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    /// Removes pending (not yet delivered) notifications with these identifiers.
    public nonisolated static func cancel(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// The key `ZANONotificationDelegate` routes taps by (`NotificationRouting.deepLinkUserInfoKey`
    /// in the app target).
    nonisolated static let deepLinkUserInfoKey = "deepLink"
}
