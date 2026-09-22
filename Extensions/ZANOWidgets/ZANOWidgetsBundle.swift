// ZANOWidgetsBundle.swift
// Extensions/ZANOWidgets
//
// @main entry point for the ZANOWidgets extension — docs/spec.md §6 (full widget/control/live
// activity catalog) and this session's task. Composes:
//   - Home Screen widget (Small/Medium/Large) — HomeWidget/ZANOHomeWidget.swift
//   - Lock Screen widget (circular/rectangular/inline) — LockScreenWidget/ZANOLockScreenWidget.swift
//   - 5 iOS 18 Controls (Lock toggle + Log Water/Shake/Focus/Creatine) — Controls/ZANOControls.swift
//   - 3 Live Activities (Focus, Gym dwell, Earn meter) — LiveActivities/*.swift
//
// Controls are mixed directly into this same `WidgetBundle`'s `body`, gated
// `#available(iOS 18.0, *)`, per Apple's own Controls sample code/documentation ("Add a control to
// your app and widget extension") — they ship from the same `com.apple.widgetkit-extension`
// extension point as the widgets above, no separate target or Info.plist entry needed. This
// mixing mechanism (a `ControlWidget` composed inside `WidgetBundleBuilder` alongside `Widget`s)
// could not be verified against a real compiler in this environment (see CLAUDE.md — no Mac
// available) — flagged plainly in this task's knownIssues as the one part of this file worth a
// double-check the first time this project builds on a Mac.

import SwiftUI
import WidgetKit

@main
struct ZANOWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ZANOHomeWidget()
        ZANOLockScreenWidget()

        ZANOFocusLiveActivity()
        ZANOGymDwellLiveActivity()
        ZANOEarnMeterLiveActivity()

        if #available(iOSApplicationExtension 18.0, *) {
            ZANOLockToggleControl()
            ZANOLogWaterControl()
            ZANOLogShakeControl()
            ZANOStartFocusControl()
            ZANOLogCreatineControl()
        }
    }
}
