// Core/Sources/Core/Store/WidgetRefresh.swift
//
// One place to tell WidgetKit that the App Group state widgets and controls read has changed
// (goal logged, lock started/ended, streak or Time Bank updated). Without it, Lock Screen and
// Home widgets stay stale for up to their 15-minute timeline refresh.

import Foundation
import WidgetKit

public enum WidgetRefresh {
    /// The Control Center lock control's kind (`ZANOLockControl` in the widget extension).
    public static let lockControlKind = "com.zano.app.control.lockToggle"

    /// The Time Bank widget's kind (`ZANOTimeBankWidget` in the widget extension, session 35).
    public static let timeBankWidgetKind = "com.zano.app.widget.timebank"

    /// Cheap and safe to call often: WidgetKit coalesces reloads and budgets them itself.
    public static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: lockControlKind)
        }
    }
}
