// ZANOControls.swift
// Extensions/ZANOWidgets/Controls
//
// iOS 18+ Controls — docs/spec.md section 6:
//   Lock:    "Start lock" button. Unlocked → starts the default lock (Core's `StartLockIntent`).
//            Locked → shows "Locked" / "2 goals left" and a tap opens ZANO. It never ends a lock:
//            locks end by earning them or through the app's emergency flow.
//   Buttons: Log Water, Log Shake, Start Focus, Log Creatine
//   Assignable to Control Center, the Lock Screen bottom corners and the Action Button.
//
// Every control is a `ControlWidget`, gated `@available(iOSApplicationExtension 18.0, *)` and
// composed into the same `WidgetBundle` behind `#available` (ZANOWidgetsBundle.swift), so the
// extension still runs on this project's iOS 17 minimum.
//
// The lock control keeps the old toggle's kind string, so a control someone already placed
// becomes the new start-only button instead of disappearing. Its state comes from a
// `ControlValueProvider` reading the App Group mirror (no SwiftData, no networking); the system
// reloads it after its own action runs, and the app must call
// `ControlCenter.shared.reloadControls(ofKind:)` when a lock starts or ends elsewhere.
//
// The 4 button controls run Core's intents with the same quantities as the Home widget's chips
// (25g / 500ml / 25 min), one consistent "quick add" amount everywhere.

import AppIntents
import Core
import SwiftUI
import WidgetKit

/// What the lock control draws. Read from the App Group mirror only.
struct ZANOLockControlState: Sendable, Equatable {
    let isLocked: Bool
    let goalsRemaining: Int

    /// "Start lock", or "2 goals left" / "Locked" while a lock runs.
    var title: String {
        isLocked ? WidgetCopy.controlLockedStatus(goalsRemaining: goalsRemaining) : WidgetCopy.controlLockTitle
    }

    var systemImage: String {
        isLocked ? "lock.fill" : "lock.open.fill"
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ZANOLockControlValueProvider: ControlValueProvider {
    var previewValue: ZANOLockControlState {
        ZANOLockControlState(isLocked: false, goalsRemaining: 0)
    }

    func currentValue() async throws -> ZANOLockControlState {
        ZANOLockControlState(isLocked: ZANOLockState.isLocked, goalsRemaining: ZANOLockState.goalsRemaining)
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ZANOLockControl: ControlWidget {
    static let kind = "com.zano.app.control.lockToggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ZANOLockControlValueProvider()) { state in
            ControlWidgetButton(action: LockControlIntent()) {
                Label(state.title, systemImage: state.systemImage)
            }
            .tint(ZANOWidgetColor.accent)
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetCopy.controlLockTitle))
        .description(LocalizedStringResource(stringLiteral: WidgetCopy.controlLockDescription))
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ZANOLogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zano.app.control.logWater") {
            ControlWidgetButton(action: LogWaterIntent(milliliters: 500, source: .widget)) {
                Label(WidgetCopy.controlLogWaterTitle, systemImage: "drop.fill")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetCopy.controlLogWaterTitle))
        .description(LocalizedStringResource(stringLiteral: WidgetCopy.controlLogWaterDescription))
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ZANOLogShakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zano.app.control.logShake") {
            ControlWidgetButton(action: LogProteinIntent(grams: 25, source: .widget)) {
                Label(WidgetCopy.controlLogShakeTitle, systemImage: "fork.knife")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetCopy.controlLogShakeTitle))
        .description(LocalizedStringResource(stringLiteral: WidgetCopy.controlLogShakeDescription))
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ZANOStartFocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zano.app.control.startFocus") {
            ControlWidgetButton(action: StartFocusIntent(minutes: 25)) {
                Label(WidgetCopy.controlStartFocusTitle, systemImage: "timer")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetCopy.controlStartFocusTitle))
        .description(LocalizedStringResource(stringLiteral: WidgetCopy.controlStartFocusDescription))
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ZANOLogCreatineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zano.app.control.logCreatine") {
            ControlWidgetButton(action: LogCreatineIntent(source: .widget)) {
                Label(WidgetCopy.controlLogCreatineTitle, systemImage: "pills.fill")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetCopy.controlLogCreatineTitle))
        .description(LocalizedStringResource(stringLiteral: WidgetCopy.controlLogCreatineDescription))
    }
}
