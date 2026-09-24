// OnboardingNFCCopy.swift
// Core / Copy
//
// `Copy.onboarding` strings for the NFC tag screen (onboarding screen 9,
// `App/ZANO/Features/Onboarding/Screen9NFCTags.swift`) and the "verified by" line it feeds into the
// plan reveal (screen 11). docs/spec.md §3 (protein/water/creatine verified by an NFC tap), §5.10
// (the Sunrise Tag), §6 (NFC), §25.1 (Tag Pack placements) and §25.5-§25.6 (the gear store).
//
// Honesty rules these strings follow:
//   - No price and no "free with annual": the Tag Pack's price and its annual-plan bundling are
//     spec intentions, not something the paywall or any store offers today.
//   - No store link text that implies a store exists: `SettingsReferenceData.gearStoreURL` is `nil`
//     until a real store is live, so the "get tags" answer says tags aren't on sale yet. The
//     `nfcGearStoreLinkLabel` line is only shown once that URL is set.
//   - "A real tap, not a number you type in" rather than "no honor system": a tag tap proves you
//     were at the shaker, not that you drank it (spec §3 puts these goals in tier B).

import Foundation

extension Copy.onboarding {

    // MARK: - Screen 9: NFC tags (spec §6, §25.1)

    public static let nfcEyebrow = "ZANO tags"
    public static let nfcTitle = "Tap to prove it"
    public static let nfcBody =
        "Stick a tag where the habit happens. One tap logs it and verifies it, instantly, even offline."
    public static let nfcProofLine = "A real tap, not a number you type in."

    // Use-case chips (where the tags go, spec §25.1).
    public static let nfcUseCaseProtein = "Shaker"
    public static let nfcUseCaseWater = "Water bottle"
    public static let nfcUseCaseSunrise = "Sunrise alarm"

    /// One line for VoiceOver covering the three chips, so they read as a sentence.
    public static let nfcUseCasesAccessibilityLabel =
        "Tags go on your shaker, your water bottle, and away from your bed to turn off the Sunrise alarm."

    public static let nfcChoiceTitle = "Do you have ZANO tags?"

    public static let nfcChoiceHaveTagsTitle = "I have ZANO tags"
    /// Settings → NFC tags is `Copy.settings.nfcTagSetupRowLabel` ("NFC tags").
    public static let nfcChoiceHaveTagsDetail = "Add them in Settings, under NFC tags, once you're set up."

    public static let nfcChoiceGetTagsTitle = "Get tags"
    /// There is no live store yet (see the file header), so this answer records interest only.
    public static let nfcChoiceGetTagsDetail = "Tag packs aren't on sale yet. They'll show up in Settings when they are."

    public static let nfcChoiceSkipTitle = "Skip for now"
    public static let nfcChoiceSkipDetail = "Log with widgets and buttons. You can add tags anytime."

    /// Only shown when `SettingsReferenceData.gearStoreURL` is set to a real store.
    public static let nfcGearStoreLinkLabel = "Open the ZANO gear store"

    // MARK: - Screen 11: Plan reveal, how a protein goal is verified

    /// The user said they have tags.
    public static let planVerifiedByNFC = "Verified by: NFC tap"
    /// The user wants tags but doesn't have them yet.
    public static let planVerifiedByNFCWhenTagsArrive = "Verified by: NFC tap, once your tags arrive"
    /// No tags: the other protein methods (spec §3: meal photo, barcode).
    public static let planVerifiedByPhotoOrBarcode = "Verified by: meal photo or barcode"
}
