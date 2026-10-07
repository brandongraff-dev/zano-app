// WatchAppGroup.swift
// Watch/Shared — compiled into BOTH ZANOWatch and ZANOWatchComplications (project.yml).
//
// The contract between the watch app and its complication extension: the App Group both open on
// the watch, the key the app persists the last phone snapshot under, and the complication kind
// the app asks WidgetKit to reload. Kept in one file so the two targets can't drift apart.
//
// The App Group on the watch is the watch's own container; nothing in it comes from the iPhone's
// copy of "group.com.zano.app". The phone's state reaches the watch only through
// WatchConnectivity (WatchConnectivityBridge), and WatchStateStore writes it here.

import Foundation

enum WatchAppGroup {
    /// Same identifier as Core's `AppGroup.identifier` on iOS, and the `application-groups`
    /// entitlement of both watch targets.
    static let identifier = "group.com.zano.app"

    /// JSON of the watch app's `WatchStateSnapshot` (its synthesized `Codable` keys). The
    /// complication decodes a subset of the same keys (`ComplicationSnapshot`).
    static let snapshotKey = "watch.lastKnownStateSnapshot"

    /// `StreakComplication`'s WidgetKit kind.
    static let streakComplicationKind = "com.zano.app.watch.complication.streak"
}
