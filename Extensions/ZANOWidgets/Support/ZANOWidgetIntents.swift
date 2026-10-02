// ZANOWidgetIntents.swift
// Extensions/ZANOWidgets/Support
//
// The one App Intent that lives in this extension, plus the shared "is a lock on?" read.
//
// Starting a lock is Core's `StartLockIntent` everywhere (Home widget button, NFC Lock Card,
// Siri), so there is one "start a lock" code path. The extension used to carry its own
// `ZANOStartLockIntent` and a `SetValueIntent` lock toggle from before Core's intent existed; both
// are gone. The toggle could also END a lock from Control Center with one tap, which the product
// rules forbid: a lock only ends by earning it or through the app's emergency flow.
//
// `ZANOLockControlIntent` is the Control Center "Start lock" button's action. It's a thin
// dispatcher, not new lock logic: no lock running → Core's `StartLockIntent`; lock running →
// open ZANO, never touching the lock.

import AppIntents
import Core
import Foundation

/// What every widget and the lock control treat as "locked". A running `LockSession` writes
/// `activeLockSessionID`; a scheduled lock the monitor armed before the app adopted it writes only
/// `activeLockSetID` (see `LockScheduler`), and its apps are shielded all the same. Every path that
/// ends a lock clears both.
enum ZANOLockState {
    static var isLocked: Bool {
        SharedDefaults.activeLockSessionID != nil || SharedDefaults.activeLockSetID != nil
    }

    /// Goals still needed to unlock, never negative. Zero when nothing is locked.
    static var goalsRemaining: Int {
        isLocked ? max(SharedDefaults.goalsRemainingForActiveLock, 0) : 0
    }
}

/// The Control Center / Lock Screen / Action Button "Start lock" control's action.
///
/// A `ControlWidgetTemplateBuilder` can't branch, so a control kind can carry only one intent
/// type; the "start vs. open the app" choice therefore happens here at run time.
@available(iOSApplicationExtension 18.0, *)
struct ZANOLockControlIntent: AppIntent {
    // Literals: the AppIntents metadata extractor only accepts string literals here. Keep in
    // sync with WidgetCopy.controlLockTitle / controlLockDescription.
    static let title: LocalizedStringResource = "Start lock"
    static let description = IntentDescription("Start your ZANO lock. While locked, opens ZANO.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if ZANOLockState.isLocked {
            // Never end or restart a running lock from Control Center. Hand off to the app, where
            // the remaining goals and the emergency unlock are. UNVERIFIED: the non-generic
            // `result(opensIntent:)` that can share a return type with `.result()` is believed
            // to be iOS 18.2+; on 18.0/18.1 the tap is a harmless no-op (the label already says
            // "Locked"). If CI rejects this overload, replace the `#available` block with
            // `return .result()`.
            if #available(iOSApplicationExtension 18.2, *) {
                return .result(opensIntent: OpenTodayIntent())
            }
            return .result()
        }
        _ = try await StartLockIntent().perform()
        return .result()
    }
}
