// ZANOWatchApp.swift
// Watch/ZANOWatch
//
// v3 / speculative scope — docs/spec.md §5.21 ("Apple Watch": complication with rings; start
// focus/lock from the wrist; workout detection more reliable with HR; haptic "verified" tap on
// gym dwell) and §11's architecture diagram, which lists "ZANOWatch (watchOS app, v3)" as a
// sibling of ZANO/ZANOWidgets/etc. This is a Session-0-style skeleton only — same spirit as the
// placeholder extension entry points (e.g. Extensions/ZANOReport/ZANOReportExtension.swift): it
// confirms the target is wired correctly and nothing more. Real screens land in whichever future
// session actually owns Watch scope.
//
// Deliberately does NOT `import Core`: Core/Package.swift's `platforms:` list currently declares
// only `.iOS(.v17)` (no `.watchOS`), so Core cannot be linked into a watchOS target yet — see the
// project.yml comment above the ZANOWatch target for the full explanation. That also means this
// target has no access to the real App Group SwiftData store yet, so it renders no live ZANO
// state (streaks, locks, Time Bank) — just a static skeleton.

import SwiftUI

@main
struct ZANOWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
