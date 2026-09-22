// FocusActivityAttributes.swift
// Core / LiveActivity
//
// docs/spec.md §6 (Widgets, Controls, Live Activities, NFC, Siri → "Live Activities (ActivityKit)":
// "Focus session: countdown, pause, end") and §3 (Goal Catalog & Verification → "Focus session"
// row: "In-app timer (25/50/90 min) with shields active; Live Activity shows countdown").
//
// Defines the `ActivityAttributes` contract for the Focus Session Live Activity, exactly per this
// task's SYSTEM CONTRACTS shape, so the widget extension (`Extensions/ZANOWidgets` — real Live
// Activity UI lands in Session 4, docs/spec.md §6/§14) and `FocusSessionVerifier` (which starts,
// ticks, and ends the Activity — `Core/Sources/Core/Verification/FocusSessionVerifier.swift`,
// same session as this file) share one `Codable`/`Hashable` type without either depending on the
// other session's code, per CLAUDE.md's "one App Intent / one shared type, never duplicated"
// architecture rule.
//
// `ActivityAttributes` (ActivityKit) refines `Codable & Hashable` on the *whole* type, not just
// `ContentState` — every stored property below is a `String`/`Int`, so both conformances are
// synthesized automatically for this type and for `ContentState`.

import ActivityKit

/// Fixed (non-changing for the lifetime of one Live Activity) attributes for a Focus Session:
/// which goal it counts toward and how long it was planned to run. Everything that changes
/// tick-to-tick — the countdown, whether it's paused — lives in ``ContentState`` instead, per
/// ActivityKit's attributes/content-state split.
public struct FocusActivityAttributes: ActivityAttributes {

    /// The part of the Live Activity that updates while a session is running. ActivityKit content
    /// updates replace this wholesale (they are not incremental/patched), so every field the UI
    /// needs to redraw the countdown must be present here.
    public struct ContentState: Codable, Hashable {
        /// Countdown remaining, in whole seconds. `FocusSessionVerifier`'s tick loop decrements
        /// this roughly once a second while the session is running and not paused; it stops
        /// changing (frozen at its last value) while ``isPaused`` is `true`.
        public var secondsRemaining: Int

        /// `true` while the session is paused. Focus sessions pause automatically when the user
        /// leaves the app (docs/spec.md §3 Focus session row: "Leaving the app pauses timer").
        ///
        /// TODO(cross-module integration — UI layer, `App/ZANO/Features`, not this session's
        /// scope): the actual `scenePhase`/`UIApplication` background observation that decides
        /// *when* to call `FocusSessionVerifier.shared.pauseSession(sessionID:)` /
        /// `resumeSession(sessionID:)` lives in the app target, which is built in a later session
        /// (docs/spec.md §17 Session 3 owns verification/timers; the screen that hosts the timer
        /// is Session 5, §15). `FocusSessionVerifier` implements the pause/resume mechanics and
        /// exposes them as a real public hook (see that file); wiring the SwiftUI `scenePhase`
        /// observer to call them is what's left. The widget/Live Activity UI that renders this
        /// flag (e.g. showing a "Paused" pill instead of a ticking countdown) is also owned by
        /// that later session.
        public var isPaused: Bool

        public init(secondsRemaining: Int, isPaused: Bool) {
            self.secondsRemaining = secondsRemaining
            self.isPaused = isPaused
        }
    }

    /// The `Goal.title` (`Core/Sources/Core/Models/Goal.swift`) this focus session counts toward,
    /// copied in at session start so the Live Activity/Dynamic Island never needs a SwiftData
    /// fetch — from a widget extension process — just to render its headline (docs/spec.md §27:
    /// extensions must stay tiny and fast).
    public var goalTitle: String

    /// The originally planned session length in minutes — one of the 25/50/90 presets
    /// (docs/spec.md §3; see `FocusSessionPreset` in `FocusSessionVerifier.swift`), kept
    /// alongside `ContentState.secondsRemaining` so the widget can render a progress fraction
    /// (`1 - Double(secondsRemaining) / Double(plannedMinutes * 60)`) without looking it up
    /// anywhere else.
    public var plannedMinutes: Int

    public init(goalTitle: String, plannedMinutes: Int) {
        self.goalTitle = goalTitle
        self.plannedMinutes = plannedMinutes
    }
}
