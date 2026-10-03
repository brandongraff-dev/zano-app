// SettingsInfoCopy.swift
// Core / Copy
//
// Visual pass 2 (2026-10-03): Settings and its sub-screens moved most of their captions behind a
// small (i) next to the section title. These are the labels those buttons and the new section
// headings need. Explanations themselves keep their existing keys.

import Foundation

extension Copy.settings {
    /// VoiceOver label of a section's (i) button: "About Coach voice".
    public static func sectionInfoLabel(_ title: String) -> String { "About \(title)" }

    /// Heading over the goals / lock sets / gym / tags group (it had none).
    public static let setupSectionTitle = "Your setup"
    /// Heading over the plan card (the old small "Plan" label inside it is gone).
    public static let planSectionTitle = "Your plan"

    /// Pause screen: the "how long" options' heading is unchanged; this is the info for the toggle.
    public static let pauseInfoLabel = "About pausing"
}

extension Copy.lockSetup {
    /// VoiceOver label of a rules section's (i) button when the section has no title of its own.
    public static let rulesInfoLabel = "More about this setting"
}
