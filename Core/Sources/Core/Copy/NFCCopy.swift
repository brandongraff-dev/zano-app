// NFCCopy.swift
// Core / Copy
//
// `Copy.nfc` — every user-facing string in `App/ZANO/Features/NFC/` (tags screen, write-a-tag
// flow, map-tag sheet, tap toast, unmapped-tag prompt, Lock Card setup). The NFC strings that used
// to live under `Copy.settings.nfc*` are copied here so the NFC feature owns its copy; the
// `Copy.settings.nfc*` keys can be deleted once `SettingsView.swift` drops its old NFC section.
//
// Neutral voice, not coach-voiced (spec §5.13): these are setup instructions and confirmations,
// same reasoning as `NFCTagSetupInstructions`.

import Foundation

extension Copy {
    public enum nfc {
        // MARK: - Tags screen

        public static let screenTitle = "NFC tags"
        public static let heroTitle = "Tap to prove it"
        public static let heroMessage = "Stick a tag where the habit happens. One tap logs it, starts focus, or locks your apps. No need to open ZANO."
        public static let addTagButton = "Add a tag"
        public static let unavailableMessage = "NFC isn't available on this iPhone."
        public static let yourTagsSectionTitle = "Your tags"
        public static let emptyTagsMessage = "No tags yet. Blank NTAG213/215/216 stickers work, and so do ZANO Tag Pack tags."
        public static let howItWorksSectionTitle = "Tap without opening ZANO"
        public static let troubleshootingSectionTitle = "Troubleshooting"
        public static let editTagButton = "Edit"
        public static let removeTagButton = "Remove"
        public static func removeConfirmTitle(label: String) -> String { "Remove \(label)?" }
        public static let removeConfirmMessage = "Tapping this tag won't do anything until you add it again."
        public static let unnamedTagLabel = "this tag"
        public static let neverTappedLabel = "Not tapped yet"
        public static func lastTappedLabel(relative: String) -> String { "Tapped \(relative)" }
        public static let lockCardRowTitle = "Lock Card"
        public static let lockCardRowPairedSubtitle = "Paired. Tap to lock, tap again for status."
        public static let lockCardRowUnpairedSubtitle = "Tap to lock. Set your phone on it. Earn it back."

        // MARK: - Tag kinds (placements, spec Tag Pack)

        public static let kindSunrise = "Sunrise Tag"
        public static let kindBottle = "Water bottle"
        public static let kindShaker = "Shaker"
        public static let kindDesk = "Desk"
        public static let kindGymBag = "Gym bag"
        public static let kindLockCard = "Lock Card"
        public static let kindCustom = "Custom"

        // MARK: - Actions

        public static let actionLogProtein = "Log protein"
        public static let actionLogWater = "Log water"
        public static let actionLogCreatine = "Log creatine"
        public static let actionStartFocus = "Start focus"
        public static let actionGymCheckIn = "Gym check-in"
        public static let actionStartLock = "Start lock"
        public static let actionLockCard = "Lock Card"
        public static let actionSunriseKey = "Turn off Sunrise Alarm"
        public static let actionCustomGoal = "Log a goal"

        public static let actionLogProteinDetail = "Adds the same amount every tap."
        public static let actionLogWaterDetail = "Adds one bottle every tap."
        public static let actionLogCreatineDetail = "Counts today's scoop. Once a day."
        public static let actionStartFocusDetail = "Starts a focus session with your apps shielded."
        public static let actionGymCheckInDetail = "Starts your gym clock. Your workout still verifies by time at the gym."
        public static let actionStartLockDetail = "Locks a lock set until your goals are done."
        public static let actionLockCardDetail = "Tap to lock. Tap again to see what's left. Never unlocks."
        public static let actionSunriseKeyDetail = "Turns off your alarm and checks off your morning."
        public static let actionCustomGoalDetail = "Checks off a goal you track on your honor."

        public static func proteinAmount(grams: Int) -> String { "\(grams) g" }
        public static func waterAmount(milliliters: Int) -> String { "\(milliliters) ml" }
        public static func focusLength(minutes: Int) -> String { "\(minutes) min" }

        /// One-line summary shown under a tag's name ("Log protein · 25 g").
        public static func summary(action: String, detail: String) -> String { "\(action) · \(detail)" }

        // MARK: - Map sheet

        public static let mapSheetNewTitle = "New tag"
        public static let mapSheetEditTitle = "Edit tag"
        public static let mapPreviewEyebrow = "When you tap it"
        public static let mapKindSectionTitle = "Where it goes"
        public static let mapActionSectionTitle = "What it does"
        public static let mapProteinAmountTitle = "Grams per tap"
        public static let mapWaterAmountTitle = "Milliliters per tap"
        public static let mapFocusLengthTitle = "Focus length"
        public static let mapLockSetTitle = "Lock set"
        public static let mapGoalTitle = "Goal"
        public static let mapLabelTitle = "Name"
        public static let mapLabelPlaceholder = "e.g. Kitchen shaker"
        public static let mapNoConfirmedGymWarning = "Save and confirm your gym in Settings first, or taps won't have a gym to check in to."
        public static let mapNoHonorGoalsWarning = "Add a custom, reading, or cold shower goal first. Auto-verified goals like workouts can't be checked off by a tap."
        public static let mapNoLockSetsWarning = "Create a lock set first."
        public static let mapNoDefaultLockSetWarning = "Pick a default lock set first. The Lock Card locks that one."
        public static let mapSaveFailedTitle = "Couldn't save that tag"
        public static let mapSaveFailedMessage = "Try again."
        public static let mapAmountHint = "Amount"

        // MARK: - Tap toasts (what a tap just did)

        public static func toastProtein(grams: Int) -> String { "+\(grams) g protein logged" }
        public static func toastWater(milliliters: Int) -> String { "+\(milliliters) ml water logged" }
        public static let toastCreatine = "Creatine logged"
        public static let toastSunrise = "Alarm off. Morning checked off."
        public static let toastLockStarted = "Lock started"
        public static func toastLockStatus(goalsRemaining: Int) -> String {
            switch goalsRemaining {
            case ..<1: "Still locked. Everything's done, unlocking soon."
            case 1: "Still locked. 1 goal left."
            default: "Still locked. \(goalsRemaining) goals left."
            }
        }
        public static func toastFocusStarted(minutes: Int) -> String { "\(minutes)-min focus started" }
        public static let toastGymCheckIn = "Checked in. Gym clock running."
        public static func toastCustomGoal(title: String) -> String { "\(title) logged" }
        public static let toastTapFailed = "That tag didn't go through. Open ZANO and try again."
        public static let toastNoConfirmedGym = "No confirmed gym yet. Add one in Settings."

        // MARK: - Write-a-tag flow

        public static let writeTitle = "Add a tag"
        public static let writeReadyTitle = "Hold your tag to the top of your iPhone"
        public static let writeReadyMessage = "Blank tags get programmed. ZANO tags get recognized. Either way it takes a second."
        public static let writeStepStick = "Stick it where the habit happens"
        public static let writeStepHold = "Hold it to the top back of your iPhone"
        public static let writeStepPick = "Pick what a tap does"
        public static let writeStartButton = "Scan tag"
        public static let writeRetryButton = "Try again"
        public static let writeOverwriteButton = "Erase and use for ZANO"
        public static let writeStageWaiting = "Waiting for a tag"
        public static let writeStageConnecting = "Reading tag"
        public static let writeStageWriting = "Writing"
        public static let writeSuccessNewTitle = "Tag programmed"
        public static let writeSuccessExistingTitle = "ZANO tag found"
        public static let writeAlreadyMappedTitle = "This tag is already set up"
        public static func writeAlreadyMappedMessage(label: String, summary: String) -> String { "\(label): \(summary)." }
        public static let writeFailedTitle = "Couldn't set up that tag"
        public static let writeFailureNotNDEF = "This tag type can't hold a link. Use an NTAG213, 215, or 216 sticker."
        public static let writeFailureReadOnly = "This tag is locked and can't be written. Use a different blank tag."
        public static let writeFailureForeign = "This tag already holds something else. Erase it and use it for ZANO?"
        public static let writeFailureCapacity = "This tag is too small. Use an NTAG213, 215, or 216 sticker."
        public static let writeFailureCommunication = "The tag moved away too soon. Hold it still near the top of your iPhone."
        public static let writeFailureGeneric = "Something interrupted the scan. Try again."
        public static let writeFailureUnsupported = "NFC isn't available on this iPhone."

        // System NFC sheet lines.
        public static let sheetHold = "Hold your iPhone near the tag."
        public static let sheetMultipleTags = "More than one tag found. Hold just one."
        public static let sheetWriting = "Writing. Keep holding."
        public static let sheetSuccess = "Tag programmed."
        public static let sheetAlreadyZano = "ZANO tag found."
        public static let sheetFailure = "Couldn't set up this tag."

        public static var writerMessages: NFCWriterMessages {
            NFCWriterMessages(
                hold: sheetHold,
                multipleTags: sheetMultipleTags,
                writing: sheetWriting,
                success: sheetSuccess,
                alreadyZano: sheetAlreadyZano,
                failure: sheetFailure
            )
        }

        // MARK: - Unmapped tag

        public static let unmappedEyebrow = "New tag"
        public static let unmappedTitle = "This tag isn't set up yet"
        public static let unmappedMessage = "Pick what a tap does. It takes ten seconds, and every tap after that just works."
        public static let unmappedSetUpButton = "Set up this tag"
        public static let unmappedNotNowButton = "Not now"

        // MARK: - Lock Card (spec: tap to lock, the stand ritual)

        public static let lockCardTitle = "Lock Card"
        public static let lockCardEyebrow = "Tap. Stand. Earn it back."
        public static let lockCardIntro = "Your Lock Card is a phone stand first and a tag second. Tapping it is how you start. Standing your phone on it is how you stay out of it."
        public static let lockCardRitualTitle = "The ritual"
        public static let lockCardStep1Title = "Tap the card"
        public static let lockCardStep1Detail = "Your default lock set locks right away."
        public static let lockCardStep2Title = "Fold out the stand"
        public static let lockCardStep2Detail = "Set your phone on it across the desk. Out of your hand, still in view."
        public static let lockCardStep3Title = "Tap again anytime"
        public static let lockCardStep3Detail = "See how many goals are left. The card never unlocks. Finish your goals to earn your apps back."
        public static let lockCardEmergencyNote = "Need your phone for something real? Emergency Unlock on the Lock tab always works."
        public static let lockCardPairButton = "Pair your Lock Card"
        public static let lockCardPairAnotherButton = "Pair another card"
        public static let lockCardPairedTitle = "Paired"
        public static func lockCardPairedCount(_ count: Int) -> String { count == 1 ? "1 card paired" : "\(count) cards paired" }
        public static let lockCardPairedToast = "Lock Card paired"
        public static let lockCardDefaultLabel = "Lock Card"
        public static let lockCardNoDefaultLockSet = "Pick a default lock set first. That's what the card locks."
        public static let lockCardWorksWithTags = "No card yet? Any blank tag works the same way. Keychain tags make a good Lock Key."
    }
}
