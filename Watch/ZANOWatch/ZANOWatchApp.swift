// ZANOWatchApp.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21 ("Apple Watch": complication with rings; start focus/lock from the wrist;
// workout detection more reliable with HR; haptic "verified" tap on gym dwell) and §11's
// architecture note that ZANOWatch is v3/speculative. This task (see this session's report)
// replaced the Session-0 skeleton this file used to be with the real thing: every screen under
// `ContentView` is complete, working SwiftUI backed by `WatchStateStore`/`WatchConnectivityBridge`.
//
// Still deliberately does NOT `import Core` — that gap is unchanged from the skeleton this
// replaces and is explained in full in `WatchTheme.swift`'s header comment (`Core/Package.swift`
// declares only `.iOS(.v17)`, and several of `Core`'s own imports — `FamilyControls`,
// `ManagedSettings`, `DeviceActivity`, `ActivityKit` — don't exist on watchOS regardless). Every
// piece of state this app shows comes from `WatchStateStore` (a target-local, App-Group-persisted
// mirror) fed by `WatchConnectivityBridge` (a real `WCSession`, though with no phone-side receiver
// wired yet — see that file's header for the exact gap, flagged in this task's knownIssues).

import SwiftUI

@main
struct ZANOWatchApp: App {
    /// Activated once here (not lazily on first use inside a view) so `WCSession.activate()` — and
    /// therefore the chance to receive a `didReceiveApplicationContext` snapshot the phone already
    /// has queued — happens as early in the process's lifetime as possible, the same reasoning
    /// Apple's own WatchConnectivity guidance gives for calling `activate()` from the app's launch
    /// path rather than deferring it.
    init() {
        WatchConnectivityBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(WatchStateStore.shared)
                .environment(WatchConnectivityBridge.shared)
                .preferredColorScheme(.dark) // matches Theme's fixed dark palette (Theme.swift, spec §15)
        }
    }
}
