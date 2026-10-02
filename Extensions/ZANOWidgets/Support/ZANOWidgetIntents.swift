// ZANOWidgetIntents.swift
// Extensions/ZANOWidgets/Support
//
// The shared "is a lock on?" read for widgets and controls.
//
// Starting a lock is Core's `StartLockIntent` everywhere (Home widget button, NFC Lock Card,
// Siri), so there is one "start a lock" code path. The extension used to carry its own
// `ZANOStartLockIntent` and a `SetValueIntent` lock toggle from before Core's intent existed; both
// are gone. The toggle could also END a lock from Control Center with one tap, which the product
// rules forbid: a lock only ends by earning it or through the app's emergency flow.
//
// The Control Center "Start lock" button runs Core's `LockControlIntent`: no lock running →
// `StartLockIntent`; lock running → open ZANO, never touching the lock.

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

// The control's action is Core's `LockControlIntent` (a `LiveActivityIntent`, so it runs in the
// app's process, which holds the Family Controls entitlement this extension lacks).
