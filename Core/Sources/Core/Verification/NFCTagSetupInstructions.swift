// Core/Sources/Core/Verification/NFCTagSetupInstructions.swift
//
// docs/spec.md §6 (NFC background reading + the Shortcuts Automation workaround), §25.1 (Tag Pack
// placements + one-screen in-app mapping), §27 (background-read platform gotcha), §5.10 (Sunrise
// Tag placement).
//
// Plain-text setup/troubleshooting copy for NFC tags — scoped to this session's task exactly as
// assigned: "plain-text steps for the Shortcuts-automation background-read workaround," plus the
// adjacent in-app mapping and placement copy needed to make that useful on its own. Lives here,
// not in `Core/Sources/Core/Copy`, deliberately: this is a fixed technical how-to (tap this,
// toggle that, inside Apple's own Shortcuts app) rather than persona-voiced app chrome that
// varies by Coach Voice (spec §5.13: Hype/Tough Love/Chill/Data). If a later session wants these
// wrapped in coach-voice framing for a setup screen's surrounding chrome ("Nice, one more
// thing..."), that framing belongs in Copy and should *reference* this file's steps rather than
// duplicate them — see this session's `decisions`.

import Foundation

/// Plain-text NFC tag setup and troubleshooting content. Not a SwiftUI view — a settings/setup
/// screen (owned elsewhere) renders these into whatever UI it wants.
public enum NFCTagSetupInstructions {

    /// One step in an ordered setup/troubleshooting flow.
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

    // MARK: - In-app mapping (spec §25.1: "app maps it to an action in one screen")

    /// Steps for the one-screen "map this tag" flow after a fresh (unmapped) tag is scanned in
    /// the app — what a setup screen should walk the user through when
    /// `NFCTagMapper.handleScannedURL(_:)` returns `.unmapped(tagID:)`.
    public static let mapTagInApp: [Step] = [
        Step(
            id: 1,
            title: "Tap the tag",
            detail: "Hold the top back of your iPhone (near the camera) against the tag until the " +
                "scan confirms."
        ),
        Step(
            id: 2,
            title: "Choose what it does",
            detail: "Pick an action — Log Water, Log Shake, Log Creatine, Sunrise Key, or Start a " +
                "Lock — and, for Log Water/Shake, the amount this tag always logs."
        ),
        Step(
            id: 3,
            title: "Name it",
            detail: "Give it a label like \"Kitchen bottle\" or \"Desk lock\" so you can find it " +
                "again later in Settings → Gear → NFC Tags."
        ),
        Step(
            id: 4,
            title: "Save",
            detail: "From now on, tapping this exact tag runs that action immediately — no need to " +
                "open the app first."
        )
    ]

    // MARK: - Background read: the Shortcuts-automation workaround (spec §6, §27)

    /// Why a Shortcuts automation is worth the one-time setup — meant to be shown once, above
    /// ``shortcutsAutomationSteps``.
    public static let backgroundReadExplainer =
        "By default, tapping a ZANO tag while the app is closed shows a notification you have to " +
        "tap to finish the action — iOS doesn't let apps run code in the background from an NFC " +
        "tap alone. A one-time Shortcuts automation removes that extra tap: scan the tag, done — " +
        "no notification, no unlocking your phone to confirm."

    /// Steps to create a silent, no-touch NFC automation in Apple's Shortcuts app — the "true
    /// no-touch path" spec §27 calls for. About 20 seconds, matching spec §6's estimate.
    ///
    /// Requires ``mapTagInApp`` to already be done for this tag — step 4 asks the user to add the
    /// same ZANO action they just mapped in-app, so the automation and the in-app mapping agree.
    public static let shortcutsAutomationSteps: [Step] = [
        Step(
            id: 1,
            title: "Open Shortcuts",
            detail: "Open the Shortcuts app (built into iOS) and go to the Automation tab at the " +
                "bottom of the screen."
        ),
        Step(
            id: 2,
            title: "Start a new automation",
            detail: "Tap the + in the top corner, then \"Create Personal Automation.\""
        ),
        Step(
            id: 3,
            title: "Choose NFC as the trigger",
            detail: "Scroll down and select \"NFC,\" then tap \"Scan\" and hold your iPhone " +
                "against the same tag you just mapped in the app. Tap \"Next.\""
        ),
        Step(
            id: 4,
            title: "Add the matching ZANO action",
            detail: "Tap \"Add Action,\" search \"ZANO,\" and choose the action matching what you " +
                "mapped this tag to (e.g. \"Log Water,\" \"Start Lock\"). Fill in the same " +
                "amount or lock you chose in-app if it asks."
        ),
        Step(
            id: 5,
            title: "Turn off \"Ask Before Running\"",
            detail: "Tap \"Next,\" then turn off \"Ask Before Running.\" This is the step that " +
                "makes it silent — without it, iOS still shows a confirmation banner every time."
        ),
        Step(
            id: 6,
            title: "Done",
            detail: "Tap \"Done.\" Tapping this tag now runs the action instantly, even with your " +
                "phone locked and the app closed."
        )
    ]

    // MARK: - Placement guidance (spec §25.1 tag kinds)

    /// Where to stick each Tag Pack tag, matching the pack's printed placement card
    /// (docs/spec.md §25.1).
    public static func placementGuidance(for kind: NFCTagKind) -> String {
        switch kind {
        case .sunrise:
            "Somewhere you have to get out of bed to reach — a bathroom mirror, the kitchen " +
            "counter, or the coffee machine. Not the nightstand: the whole point is getting up " +
            "(spec §5.10)."
        case .bottle:
            "On your water bottle, clear of any metal cap or threads if it has them — metal can " +
            "block the read."
        case .shaker:
            "On the base or lid of your shaker. If the lid is metal, test a few taps after " +
            "sticking the tag on; a metal lid sometimes needs the tag nudged slightly to read " +
            "reliably."
        case .desk:
            "Somewhere you'll actually tap before sitting down to work — a monitor stand edge, a " +
            "desk mat corner, or a mousepad."
        case .gymBag:
            "Inside the top pocket or on a zipper pull you touch every time you grab the bag — " +
            "not buried at the bottom."
        case .custom:
            "Anywhere you'll tap consistently — the mapping only helps if it's somewhere you'll " +
            "actually touch it."
        }
    }

    // MARK: - Troubleshooting

    public static let troubleshooting: [String] = [
        "Hold the tag to the top back of your iPhone, near the camera — that's where the NFC " +
            "antenna sits on every iPhone model, not the bottom or the screen.",
        "If a tap does nothing, confirm the tag is an NDEF-formatted URL tag (ZANO's Tag Pack " +
            "ships pre-written NTAG215 tags) and not blank, damaged, or write-protected.",
        "Metal blocks NFC almost entirely. If a tag is stuck to or sitting near metal (a metal " +
            "bottle, a metal desk edge, a MagSafe mount, a metal phone case), move it clear of " +
            "the metal or a few centimeters away from it.",
        "A Shortcuts automation is tied to the exact physical tag it was recorded against — if a " +
            "tag is lost or damaged, redo both the in-app mapping and the automation on its " +
            "replacement.",
        "\"Ask Before Running\" turning itself back on after an iOS update is a known Shortcuts " +
            "quirk. If a previously-silent automation starts showing a confirmation again, check " +
            "that setting first."
    ]
}
