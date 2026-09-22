// Core/Sources/Core/LockEngine/AutoFocusIntegration.swift
//
// docs/spec.md §5.12 Auto-Focus Integration: "When a lock starts, optionally trigger an iOS
// Focus mode via Shortcuts automation so notifications from blocked apps also stop. One-tap
// setup guide."
//
// This file owns the small piece of *state* that feature needs — whether the user has actually
// done the one-time Shortcuts automation setup, plus the "should we still be asking" cadence —
// not the words. The full step-by-step guide and every user-facing string, including the short
// "at the right moment" nudge this file decides *when* to show, live in
// `Core/Sources/Core/Copy/AutoFocusSetupInstructions.swift`, per CLAUDE.md ("user-facing copy
// lives in Core/Sources/Core/Copy — no hardcoded UI strings elsewhere") and the same state/copy
// split `EmergencyUnlock.swift` (this directory) already documents for itself: "none of the copy
// ... is hardcoded here ... a view reads state and looks its copy up in Copy."
//
// Naming note: "Focus" here is Apple's system Focus mode (Settings > Focus / Control Center),
// unrelated to ZANO's own in-app "Focus session" goal type (spec §3, `FocusSessionVerifier`,
// `Intents/StartFocusIntent.swift`/`EndFocusIntent.swift`). This file never touches the latter.
//
// Not part of this task's SYSTEM CONTRACTS list — like `EmergencyUnlock.swift` and
// `PartialUnlockTiers.swift` (this directory), this file's shape is this session's own design,
// scoped exactly to what was assigned: "a small helper exposing whether the user has this set up
// (a SharedDefaults flag) and copy prompting setup at the right moment."
//
// Cross-module integration point (TODO, out of this session's scope — do not wire this up here):
// nothing calls into this file yet. The natural call sites are `LockEngineManager.startLock`
// (to read `setupPromptIfNeeded` and surface it when a lock actually starts) and wherever a
// setup/confirmation screen lives that calls `recordSetupCompleted()`/`recordPromptDismissed()`
// — both outside this session's assigned file list. This file only exposes the API; it does not
// call itself from anywhere, and touches no other file.

import Foundation

/// Whether the user has completed the one-time Auto-Focus Shortcuts automation (spec §5.12), and
/// the light cadence logic for when to still be asking if they haven't.
///
/// Mirrors `Store/SharedDefaults.swift`'s shape deliberately — its own private App-Group-backed
/// `UserDefaults` suite, plain `get`/`set` static vars — rather than adding new properties to
/// that file, which this session was not asked to own or edit. `SharedDefaults`'s own header
/// documents its properties as "a cheap mirror that the engine which actually owns that state
/// writes"; this file *is* that owning engine for the Auto-Focus flag, the same relationship
/// `StreakEngine`/`LockEngineManager` have to the properties they mirror there. It deliberately
/// keeps its own separate `UserDefaults` suite rather than editing `SharedDefaults` directly, for
/// the same reason: this flag has no Shield/Widget-extension reader that needs it mirrored
/// through that particular file today (unlike `activeLockSessionID` etc., which extensions read
/// every render), so there is nothing to gain from coupling this session's addition to a file
/// another agent owns.
public enum AutoFocusIntegration {

    /// See `SharedDefaults.defaults`'s identical comment: `UserDefaults` is documented
    /// thread-safe by Apple but not yet marked `Sendable` by the SDK as of this writing.
    /// `nonisolated(unsafe)` reflects that documented guarantee under Swift 6 strict concurrency.
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let isSetUp = "autoFocus.isSetUp"
        static let promptDismissCount = "autoFocus.promptDismissCount"
    }

    /// After this many times the user has dismissed the lock-start nudge without completing
    /// setup, stop auto-surfacing it — nagging past this point reads as exactly the kind of
    /// pressure CLAUDE.md/spec §24 rule out for goals, and that spirit ("no restrictive/shaming")
    /// extends to unprompted nudges too. Setup stays reachable wherever Settings/onboarding
    /// surfaces it; this constant only caps the *unprompted* lock-start banner.
    public static let maxPromptDismissals = 3

    // MARK: - The flag

    /// `true` once the user has completed the Shortcuts automation
    /// (`AutoFocusSetupInstructions.steps`). Defaults to `false` (absent key reads as `false` via
    /// `UserDefaults.bool(forKey:)`). Nothing in this file ever sets this to `true` on its own —
    /// a setup-confirmation screen (out of this session's scope) calls `recordSetupCompleted()`
    /// once the user says they finished the steps. ZANO has no way to *verify* the automation
    /// actually exists — Apple gives third-party apps no API to inspect a user's Shortcuts
    /// automations — so this is deliberately an honest "the user told us they did it" flag, the
    /// same trust model most one-tap setup guides use; it never gates anything ZANO itself
    /// depends on (see the emergency-unlock note on `AutoFocusSetupInstructions.limits`).
    public static var isSetUp: Bool {
        get { defaults.bool(forKey: Keys.isSetUp) }
        set { defaults.set(newValue, forKey: Keys.isSetUp) }
    }

    /// Marks setup complete and, implicitly, stops any further prompting (`isSetUp == true`
    /// alone makes ``shouldOfferSetupPrompt`` `false`). Prefer this over setting ``isSetUp``
    /// directly from a confirmation screen — reads more clearly at the call site than a bare
    /// `= true`.
    public static func recordSetupCompleted() {
        isSetUp = true
    }

    /// Undoes ``recordSetupCompleted()`` — e.g. a Settings row for "I removed the automation."
    /// Also resets the dismiss cadence below, so the lock-start nudge can start offering setup
    /// again instead of staying silenced from before the user ever set it up.
    public static func recordSetupRemoved() {
        isSetUp = false
        defaults.set(0, forKey: Keys.promptDismissCount)
    }

    // MARK: - "At the right moment" (spec §5.12's implicit ask — don't nag forever)

    /// How many times the user has dismissed the lock-start nudge (``setupPromptIfNeeded``)
    /// without completing setup.
    public static var promptDismissCount: Int {
        defaults.integer(forKey: Keys.promptDismissCount)
    }

    /// Call when the user dismisses the lock-start nudge (taps "Not now," swipes it away —
    /// whatever the surface's dismiss affordance is) without completing setup. Safe to call more
    /// than ``maxPromptDismissals`` times; the count just stops mattering once
    /// ``shouldOfferSetupPrompt`` is already `false`.
    public static func recordPromptDismissed() {
        defaults.set(promptDismissCount + 1, forKey: Keys.promptDismissCount)
    }

    /// Whether "the right moment" is now — i.e. whether a lock-start banner should offer
    /// Auto-Focus setup at all. `false` once ``isSetUp``, or once the user has dismissed the
    /// nudge ``maxPromptDismissals`` times.
    public static var shouldOfferSetupPrompt: Bool {
        !isSetUp && promptDismissCount < maxPromptDismissals
    }

    /// The nudge to show at lock start, or `nil` when this isn't "the right moment" (already set
    /// up, or already dismissed enough times). A lock-start call site checks this single property
    /// rather than re-deriving ``shouldOfferSetupPrompt`` and separately looking up copy — this is
    /// the one property that combines both, matching this file's assigned job: "a small helper
    /// exposing whether the user has this set up ... and copy prompting setup at the right
    /// moment."
    public static var setupPromptIfNeeded: String? {
        shouldOfferSetupPrompt ? AutoFocusSetupInstructions.lockStartPrompt : nil
    }
}
