// HapticsPlayer.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21: "haptic 'verified' tap when the gym dwell threshold is hit." A thin, named
// wrapper around `WKInterfaceDevice.current().play(_:)` rather than scattering raw `WKHapticType`
// cases at every call site, so the mapping from "what happened" to "which haptic plays" lives in
// exactly one place (the same reasoning `Core/Sources/Core/Copy`'s files give for centralizing
// copy — this is that same discipline applied to haptics instead of strings).
//
// API-certainty note (flagged per this task's brief): `WKInterfaceDevice.current().play(_:)` and
// the `WKHapticType` enum itself are stable, long-standing watchOS API (watchOS 3+) — HIGH
// confidence this call compiles and fires *a* haptic. Which exact `WKHapticType` case best matches
// "verified" is a product/feel judgment call, not something to verify against an SDK: `.success`
// is chosen here as the closest built-in semantic match (a positive, "this completed" tap,
// distinct from `.notification`'s more neutral "FYI" feel) — MEDIUM confidence as a *product* pick
// worth a real Watch in hand to compare against `.notification`/`.click` before shipping; not an
// API-existence risk.

import WatchKit

public enum HapticsPlayer {
    /// docs/spec.md §5.21's "verified" tap — fired by `WatchStateStore.apply(_:)` when a received
    /// snapshot's `gymDwell.isVerified` flips `false` → `true`.
    public static func playVerified() {
        WKInterfaceDevice.current().play(.success)
    }

    /// A lighter tap for "the watch successfully asked the phone to do something" (a lock/focus
    /// request was sent) — distinct from `.playVerified()` so a person can feel the difference
    /// between "request sent" and "goal actually verified" without looking at the screen.
    public static func playActionSent() {
        WKInterfaceDevice.current().play(.click)
    }

    /// `WatchConnectivityBridge.send(_:)` couldn't reach the phone at all (not even queued).
    public static func playActionFailed() {
        WKInterfaceDevice.current().play(.failure)
    }

    /// A wrist workout session started/ended (`WatchWorkoutSessionController`).
    public static func playWorkoutStart() {
        WKInterfaceDevice.current().play(.start)
    }

    public static func playWorkoutStop() {
        WKInterfaceDevice.current().play(.stop)
    }
}
