// Core/Sources/Core/Store/NotificationCenterQueries.swift
//
// Reads from `UNUserNotificationCenter` that hand back only Sendable values.
//
// Why this file exists: under Swift 6, a completion-handler closure written inside a `@MainActor`
// type is itself main-actor isolated, and the notification center calls it on a background queue —
// the runtime isolation check then traps (EXC_BREAKPOINT), which crashed the app on every launch in
// CI. These functions are `nonisolated`, so their callbacks carry no actor isolation, and they map
// the non-Sendable request/settings objects to plain values before resuming.

import Foundation
import UserNotifications

public enum NotificationCenterQueries {
    /// Identifiers of every pending (scheduled, not yet delivered) request.
    public nonisolated static func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    /// Identifiers of every delivered notification still in Notification Center.
    public nonisolated static func deliveredIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
    }

    /// Whether the app may post alerts (authorized, provisional, or ephemeral).
    public nonisolated static func canPostNotifications() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status = settings.authorizationStatus
                continuation.resume(returning: status == .authorized || status == .provisional || status == .ephemeral)
            }
        }
    }
}
