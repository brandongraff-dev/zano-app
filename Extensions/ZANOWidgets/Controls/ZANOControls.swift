// ZANOControls.swift
// Extensions/ZANOWidgets/Controls
//
// iOS 18+ Controls — docs/spec.md §6:
//   Toggle:  Lock On/Off (with confirmation for Off)
//   Buttons: Log Water, Log Shake, Start Focus, Log Creatine
//   Assignable to Lock Screen bottom corners and the Action Button
//
// Every control is a `ControlWidget`, gated `@available(iOSApplicationExtension 18.0, *)` per
// spec §27 ("Controls require iOS 18 and a `ControlWidget`; gate by availability") and this
// task's instructions. They live in the same widget extension as the Home/Lock Screen widgets —
// no separate Info.plist/extension point is needed (`ZANOWidgetsBundle.swift` composes them into
// the same `WidgetBundle`).
//
// The 4 button controls run the exact CONTRACTS intent names from this task (`LogWaterIntent`,
// `LogProteinIntent` — "Log Shake" in spec's own control label, since a protein shake is this
// app's shorthand for a protein log — `StartFocusIntent`, `LogCreatineIntent`) via
// `ControlWidgetButton(action:)`, with the same quantities as the Home widget's buttons (25g /
// 500ml / 25 min) for one consistent "quick add" amount everywhere. The toggle control's backing
// intent (`ZANOSetLockStateIntent`) is defined in Support/ZANOWidgetIntents.swift — see that
// file's header comment for why it isn't one of Core's Intents.

import AppIntents
import Core
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct ZANOLockToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zano.app.control.lockToggle") {
            ControlWidgetToggle(
                LocalizedStringResource(stringLiteral: WidgetCopy.controlLockToggleTitle),
                isOn: SharedDefaults.activeLockSessionID != nil,
                action: ZANOSetLockStateIntent()
            ) { isLocked in
                Label(
                    isLocked ? WidgetCopy.controlLockedLabel : WidgetCopy.controlUnlockedLabel,
                    systemImage: isLocked ? "lock.fill" : "lock.open.fill"
                )
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetCopy.controlLockToggleTitle))
        .description(LocalizedStringResource(stringLiteral: WidgetCopy.controlLockToggleDescription))
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
