// Core/Sources/Core/Store/DeviceDataReset.swift
//
// The device-state half of Settings → "Delete all my data" (docs/design/unfinished-audit-2026-10-02.md
// N5; spec section 24 privacy). Deleting the SwiftData rows isn't enough: iOS keeps running what
// the app registered with the system, and the App Group defaults keep the ledgers. After this runs
// nothing the app set up can fire again — no scheduled lock, no reminder, no alarm, no Live
// Activity — until the person sets it up again.
//
// The caller ends the active lock first (emergency unlock), deletes the SwiftData rows, then calls
// `eraseDeviceState()`. Never touches the network.

import ActivityKit
import DeviceActivity
import Foundation
import ManagedSettings
import UserNotifications
import os

@MainActor
public enum DeviceDataReset {
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "DeviceDataReset")

    /// Stops every system registration and clears every App Group value. Idempotent.
    public static func eraseDeviceState() async {
        // 1. Scheduled locks, the Bedtime Gate, per-session keep-alives and Time Bank spend
        //    windows are all DeviceActivity registrations: stop every one this app owns.
        let center = DeviceActivityCenter()
        let activities = center.activities
        if !activities.isEmpty { center.stopMonitoring(activities) }
        // Never leave a shield behind with no lock to end (the lock itself was already ended).
        ManagedSettingsStore(named: .zanoLock).clearAllSettings()

        // 2. The Sunrise Alarm on both tiers (AlarmKit + the notification chain) and its settings,
        //    so the foreground hook (`hasBeenConfigured`) never reschedules it.
        await SunriseAlarmManager.shared.resetAll()

        // 3. Every pending and delivered local notification: nudges, onboarding drips, the shield's
        //    emergency hand-off, trial reminders.
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()

        // 4. Focus sessions, then every Live Activity the app can have running.
        FocusSessionVerifier.shared.resetAll()
        await endAll(FocusActivityAttributes.self)
        await endAll(EarnMeterActivityAttributes.self)
        await endAll(GymDwellActivityAttributes.self)
        await endAll(BedtimeWindDownActivityAttributes.self)
        await endAll(SunriseAlarmRingingActivityAttributes.self)

        // 5. The App Group defaults: milestone, reward and variable-reward ledgers, schedules,
        //    lock mirrors, nudge prefs, travel/comeback/Plan B state. Key by key, because
        //    `removePersistentDomain(forName:)` isn't documented to work on an App Group suite.
        if let shared = UserDefaults(suiteName: AppGroup.identifier) {
            for key in shared.dictionaryRepresentation().keys {
                shared.removeObject(forKey: key)
            }
            shared.removePersistentDomain(forName: AppGroup.identifier)
        }
        WidgetRefresh.reloadAll()
        logger.notice("Device state erased.")
    }

    private static func endAll<Attributes: ActivityAttributes>(_ type: Attributes.Type) async {
        for liveActivity in Activity<Attributes>.activities {
            nonisolated(unsafe) let activity = liveActivity
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
