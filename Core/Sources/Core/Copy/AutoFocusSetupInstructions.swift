// Core/Sources/Core/Copy/AutoFocusSetupInstructions.swift
//
// docs/spec.md §5.12 Auto-Focus Integration: "When a lock starts, optionally trigger an iOS
// Focus mode via Shortcuts automation so notifications from blocked apps also stop. One-tap
// setup guide."
//
// Shape follows Core/Sources/Core/Verification/NFCTagSetupInstructions.swift exactly (its own
// header: "Plain-text setup/troubleshooting copy... for the Shortcuts-automation... workaround")
// — the same explainer + ordered Step list + troubleshooting shape, a different automation:
// instead of "NFC tag scanned -> run a ZANO action," this is "ZANO starts a lock -> turn on
// Focus."
//
// Placement note: unlike NFCTagSetupInstructions (which deliberately stays out of Copy — see its
// header — because it's a fixed technical how-to, not persona-voiced chrome), this file lives in
// Copy per this session's assignment and CLAUDE.md ("user-facing copy lives in
// Core/Sources/Core/Copy — no hardcoded UI strings elsewhere"). It still stays plain-text/
// un-voiced (no CoachVoice variants) like the pattern file: walking someone through Apple's own
// Shortcuts app is a fixed technical how-to, not a moment for Hype/Tough Love/Chill/Data framing
// (spec §5.13). `AutoFocusIntegration` (Core/Sources/Core/LockEngine/AutoFocusIntegration.swift)
// is the small state helper that decides *when* to surface ``lockStartPrompt`` below; this file
// only owns the words, matching the state/copy split `EmergencyUnlock.swift` (same LockEngine
// directory) already documents for itself.
//
// Naming note: "Focus" here is Apple's system Focus mode (Settings > Focus / Control Center),
// unrelated to ZANO's own in-app "Focus session" goal type (spec §3, `FocusSessionVerifier`,
// `Intents/StartFocusIntent.swift`/`EndFocusIntent.swift`). This file never touches the latter.
//
// Apple-API-surface caveat (CLAUDE.md rule 5 — flag uncertainty rather than guess): Shortcuts'
// Personal Automation trigger list has shifted across iOS releases, and there is no Mac/device in
// this session to confirm current exact wording. The trigger used below — "App" > "Is Opened",
// scoped to ZANO — is the trigger type that has existed since Shortcuts automations shipped
// (iOS 14) and is the closest available proxy for "a ZANO lock started": Shortcuts automations
// have no generic third-party "app posted a custom event" trigger, so ZANO cannot register its
// own "lock started" trigger the way an NFC tag registers its own scan. It is an imperfect proxy
// for a lock that arms on a schedule without the user opening the app first (spec §5.10 Bedtime
// Gate) — the "Limits" section below says so rather than overpromising. Flagged as unverified in
// this session's knownIssues.

import Foundation

/// Plain-text Auto-Focus setup content (spec §5.12). Not a SwiftUI view — a settings/setup screen
/// (owned elsewhere) renders these into whatever UI it wants, same convention as
/// `NFCTagSetupInstructions`.
public enum AutoFocusSetupInstructions {

    /// One step in the ordered setup flow. Mirrors `NFCTagSetupInstructions.Step`'s shape
    /// exactly; kept as its own type here rather than reused from that file so this file has no
    /// compile-time dependency on `Verification` — Copy content for one feature shouldn't need
    /// another feature's file to stay unedited in order to build.
    public struct Step: Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let detail: String

        public init(id: Int, title: String, detail: String) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    // MARK: - The "right moment" nudge (surfaced by `AutoFocusIntegration`)

    /// Short, single-line nudge — not the full guide — shown the first few times a lock starts
    /// and Auto-Focus isn't set up yet (`AutoFocusIntegration.shouldOfferSetupPrompt`). Kept to
    /// one line: this is an inline banner/toast moment, not a screen.
    public static let lockStartPrompt =
        "Want your phone to go quiet too? Set up Auto-Focus once and ZANO turns on a Focus mode " +
        "every time a lock starts — so blocked apps stop buzzing you, not just blocking you."

    /// The same nudge's title, for a banner that wants a title/body pair instead of one line.
    public static let lockStartPromptTitle = "Silence blocked apps, not just block them"

    /// The nudge's action-button label, for a banner that offers a direct way in rather than
    /// requiring the user to find Settings on their own.
    public static let lockStartPromptAction = "Set it up (30 sec)"

    // MARK: - Setup guide (spec §5.12 "One-tap setup guide")

    /// Shown on the dedicated setup screen, above ``steps``.
    public static let explainer =
        "ZANO can't turn on a Focus mode by itself — Apple doesn't let apps do that directly. A " +
        "one-time Shortcuts automation closes the gap: the moment you open ZANO to start a lock, " +
        "your phone quietly switches into a Focus mode you choose, so notifications from the " +
        "apps you just locked stop showing up too. Takes about 30 seconds, once."

    public static let steps: [Step] = [
        Step(
            id: 1,
            title: "Pick or create a Focus",
            detail: "You'll need a Focus to turn on — in the Settings app, go to Focus. Any " +
                "existing Focus works, but a dedicated one (name it something like \"Locked " +
                "In\") keeps this separate from your regular Work/Sleep Focus. Set it to silence " +
                "notifications from the apps you lock with ZANO."
        ),
        Step(
            id: 2,
            title: "Open Shortcuts",
            detail: "Open the Shortcuts app (built into iOS) and go to the Automation tab at the " +
                "bottom of the screen."
        ),
        Step(
            id: 3,
            title: "Start a new automation",
            detail: "Tap the + in the top corner, then \"Create Personal Automation.\""
        ),
        Step(
            id: 4,
            title: "Choose \"App\" as the trigger",
            detail: "Scroll to \"App,\" tap \"Choose,\" and select ZANO. Choose \"Is Opened,\" " +
                "then tap \"Next.\" (This is the closest thing iOS gives a Shortcuts automation " +
                "to \"a ZANO lock started\" — see Limits below.)"
        ),
        Step(
            id: 5,
            title: "Add \"Set Focus\"",
            detail: "Tap \"Add Action,\" search \"Focus,\" and choose \"Set Focus.\" Set it to " +
                "\"Turn On\" and pick the Focus you set up in step 1."
        ),
        Step(
            id: 6,
            title: "Turn off \"Ask Before Running\"",
            detail: "Tap \"Next,\" then turn off \"Ask Before Running.\" Without this, iOS shows " +
                "a confirmation banner every single time you open ZANO — this is the step that " +
                "makes it silent."
        ),
        Step(
            id: 7,
            title: "Done",
            detail: "Tap \"Done.\" From now on, opening ZANO quietly turns that Focus on — no " +
                "extra tap. Turning it back off again is a separate, optional step — see " +
                "\"Turning Focus back off\" below."
        )
    ]

    // MARK: - Turning Focus back off

    public static let turnOffExplainer =
        "Auto-Focus only ever turns a Focus ON — it never turns it off for you, on purpose. You " +
        "stay in full control of when your phone goes back to normal, the same way you stay in " +
        "control of everything else ZANO locks (see Emergency Unlock). Turn the Focus off " +
        "yourself any time from Control Center, or repeat the steps above with \"Is Closed\" and " +
        "\"Turn Off\" instead if you'd rather it happen automatically when you leave the app."

    // MARK: - Folding this into an existing NFC-tag automation

    /// For users who start locks by tapping an NFC tag (spec §6, §25.1) rather than opening the
    /// app manually — the "App > Is Opened" trigger above won't fire from a background NFC tap
    /// the way it fires from a Home Screen launch. Their tag automation already exists
    /// (`NFCTagSetupInstructions.shortcutsAutomationSteps`); this adds one more action to it
    /// instead of creating a second, redundant automation.
    public static let nfcTagAddOn =
        "Start locks by tapping an NFC tag instead? Skip the automation above — open your " +
        "existing tag automation (Shortcuts > Automation > your tag), tap \"Add Action,\" add " +
        "\"Set Focus\" the same way as step 5, and it'll turn on the instant you tap, same as " +
        "the lock itself."

    // MARK: - Limits (honest about what this can't do)

    public static let limits: [String] = [
        "This only reliably catches locks you start by opening ZANO. A lock that arms itself on " +
            "a schedule (like the Bedtime Gate, spec §5.10) while ZANO isn't open won't trigger " +
            "this automation — iOS has no Shortcuts trigger for \"a specific app's background " +
            "timer fired.\" Set that Focus's own schedule (Settings > Focus > your Focus > a " +
            "fixed time) alongside this for those.",
        "Focus mode silences notifications; it doesn't block the apps themselves — that's still " +
            "ZANO's shield doing the actual blocking. Auto-Focus is the quiet-down layer on top, " +
            "not a replacement for it.",
        "You can always turn Focus off by hand from Control Center, regardless of this " +
            "automation — Auto-Focus never removes that option. It also never affects ZANO's own " +
            "Emergency Unlock (spec §24, §5.10 point 6: \"no one gets trapped\"): ending a lock " +
            "early works exactly the same whether or not Auto-Focus is set up."
    ]

    // MARK: - Troubleshooting

    public static let troubleshooting: [String] = [
        "If the Focus doesn't turn on, open the automation in Shortcuts and confirm \"Ask " +
            "Before Running\" is off — this is the single most common miss.",
        "\"Ask Before Running\" turning itself back on after an iOS update is a known Shortcuts " +
            "quirk (the same one can affect NFC tag automations). If a previously-silent " +
            "automation starts asking again, check that setting first.",
        "If ZANO was already open in the background, reopening it may not count as \"Is " +
            "Opened\" — fully close ZANO first (swipe it away in the App Switcher) if you're " +
            "testing this.",
        "Nothing here ever stops you from reaching ZANO's own Emergency Unlock, and nothing here " +
            "can lock you out of your phone — Focus mode only changes notifications, never app " +
            "access."
    ]
}
