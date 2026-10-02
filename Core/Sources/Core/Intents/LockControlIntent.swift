// Core/Sources/Core/Intents/LockControlIntent.swift
//
// The Control Center / Lock Screen / Action Button "Start lock" control's action.
//
// It lives in Core (so it exists in both the app and the widget extension) and is a
// `LiveActivityIntent`, so the system runs it in the app's process. Only the app holds the Family
// Controls entitlement; running `StartLockIntent` inside the widget extension couldn't shield
// anything.
//
// A `ControlWidgetTemplateBuilder` can't branch, so the control carries one intent and the
// "start vs. open the app" choice happens here: no lock running → `StartLockIntent`; a lock
// running → open ZANO, never ending or restarting the lock (that only happens by earning it or
// through the in-app emergency unlock).

import ActivityKit
import AppIntents
import Foundation

public struct LockControlIntent: LiveActivityIntent {
    // Literals: the AppIntents metadata extractor only accepts string literals here. Keep in sync
    // with WidgetCopy.controlLockTitle / controlLockDescription.
    public static let title: LocalizedStringResource = "Start lock"
    public static let description = IntentDescription("Start your ZANO lock. While locked, opens ZANO.")

    public init() {}

    /// A running session, or a scheduled lock the monitor armed before the app adopted it.
    public static var isLocked: Bool {
        SharedDefaults.activeLockSessionID != nil || SharedDefaults.activeLockSetID != nil
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if Self.isLocked {
            // UNVERIFIED: the non-generic `result(opensIntent:)` that can share a return type with
            // `.result()` is believed to be iOS 18.2+; on earlier versions the tap is a harmless
            // no-op (the control already reads "Locked").
            if #available(iOS 18.2, *) {
                return .result(opensIntent: OpenTodayIntent())
            }
            return .result()
        }
        _ = try await StartLockIntent().perform()
        WidgetRefresh.reloadAll()
        return .result()
    }
}
