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
}
