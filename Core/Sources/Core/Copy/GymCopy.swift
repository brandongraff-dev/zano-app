// GymCopy.swift
// Core / Copy
//
// `Copy.gym` — every user-facing string in `App/ZANO/Features/GymSetup/` (Gym setup list, the
// add/edit sheet, the location permission primer, the live check-in screen, the manual check-in
// sheet) and the gym presence notifications/Live Activity fallback name in
// `Core/Sources/Core/Verification/GymPresenceService.swift`.
//
// The gym strings that used to live in `Copy.settings` moved here with the screens (Wave 1A);
// `Copy.settings.gymSetupRowLabel` stays there because the Settings row still owns it.
//
// Privacy lines follow spec §24 ("Location: request When in Use first; Always only at gym setup
// with a clear explanation. Provide a manual check-in fallback.") and say only what is true in
// this build: location is evaluated on the phone by the geofence and no location history is
// kept or uploaded.

import Foundation

extension Copy {
    public enum gym {
        // MARK: - Gym setup list

        public static let setupTitle = "Gym setup"
        public static let emptyTitle = "No gyms saved yet"
        public static let emptyMessage = "Add your gym so workouts verify on their own when you show up."
        public static let addButtonLabel = "Add a gym"
        public static let unnamedLabel = "Unnamed gym"
        public static let fallbackName = "Your gym"
        public static let confirmedLabel = "Confirmed"
        public static let unconfirmedLabel = "Not confirmed yet"
        public static let confirmButtonLabel = "Confirm"
        public static let autoDetectedLabel = "Auto-detected"
        public static let editLabel = "Edit"
        public static func radiusLabel(meters: Int) -> String { "Radius: \(meters)m" }
        public static func deleteConfirmTitle(name: String) -> String { "Delete \(name)?" }
        public static let deleteConfirmMessage = "Workouts here won't verify automatically anymore."
        public static let saveErrorTitle = "Couldn't save that"
        public static let saveErrorMessage = "Something went wrong saving your gym. Try again."
        public static let checkInRowTitle = "Check in now"
        public static let checkInRowSubtitle = "See your timer, or check in manually."

        // MARK: - Add / edit sheet

        public static let addSheetTitle = "Add a gym"
        public static let editSheetTitle = "Edit gym"
        public static let searchPlaceholder = "Search a gym or address"
        public static let searchNoResults = "No matches. Try the street address."
        public static let searchFailed = "Search isn't available right now. Tap the map or use your location instead."
        public static let mapHintUnplaced = "Search, tap the map, or use your location to drop the pin."
        public static let mapHintPlaced = "Drag the map to fine-tune. The circle is where you'll count as at the gym."
        public static let mapAccessibilityLabel = "Gym location map"
        public static let locateButtonLabel = "Use current location"
        public static let locatingLabel = "Locating…"
        public static let locationFailedMessage = "Couldn't get your location. Check Location Services in the iPhone Settings app."
        public static let radiusHint = "Cover the building and its parking. Smaller is stricter."
        public static let nameFieldLabel = "Name"
        public static let nameFieldPlaceholder = "e.g. Downtown Fitness"

        // MARK: - Location permission primer (spec §24)

        public static let whenInUseTitle = "Find your gym on the map"
        public static let whenInUseMessage = "ZANO uses your location while you set up, so it can drop the pin where you're standing."
        public static let whenInUseButton = "Allow location"

        public static let alwaysTitle = "Check in without opening the app"
        public static let alwaysMessage = "Choose \u{201C}Always\u{201D} and your iPhone notices when you walk into your gym, starts the timer, and verifies the workout — no tapping."
        public static let alwaysButton = "Allow \u{201C}Always\u{201D}"
        public static let alwaysNotNow = "Not now"
        public static let privacyPointOnDevice = "Checked on this iPhone. ZANO doesn't keep a history of where you go."
        public static let privacyPointGymOnly = "Only your saved gym's circle matters. Everywhere else is ignored."
        public static let privacyPointFallback = "Prefer not to? You can always check in manually."

        public static let whenInUseOnlyTitle = "Auto check-in is limited"
        public static let whenInUseOnlyMessage = "With \u{201C}While Using the App\u{201D}, ZANO can only check you in while it's open."
        public static let deniedTitle = "Location is off for ZANO"
        public static let deniedMessage = "Gym workouts can't verify on their own without it. Turn it on in Settings, or check in manually."
        public static let openSettingsButton = "Open Settings"

        // MARK: - Check-in screen

        public static let checkInTitle = "Gym check-in"
        public static func headTo(gym: String) -> String { "Head to \(gym)" }
        public static let awayMessage = "Your timer starts on its own when you arrive."
        public static let startCheckInButton = "Start check-in"
        public static let resumeCheckInButton = "Resume check-in"
        public static func notAtGymYet(gym: String) -> String {
            "You're not at \(gym) yet. The timer starts on its own when you get there."
        }
        public static let checkInUnavailable = "That gym isn't set up for check-ins. Confirm it in Gym setup."
        public static func atGym(_ gym: String) -> String { "At \(gym)" }
        public static let minutesUnit = "min"
        public static func verifiesAt(minutes: Int) -> String { "Verified at \(minutes) min" }
        public static func verifiesIn(minutes: Int) -> String {
            minutes <= 1 ? "Verifies in about a minute" : "Verifies in \(minutes) min"
        }
        public static let stayHint = "Stay inside the circle. Leaving stops the timer."
        public static let verifiedTitle = "Workout verified"
        public static func verifiedDetail(minutes: Int, gym: String) -> String { "\(minutes) min at \(gym). It counts toward today." }
        public static let manualDoneTitle = "Checked in manually"
        public static let manualDoneDetail = "It counts toward today, marked as a manual check-in."
        public static func leftEarlyTitle(minutes: Int) -> String { "You left at \(minutes) min" }
        public static func leftEarlyMessage(target: Int) -> String {
            "Go back to pick it up. A new visit starts a fresh \(target)-minute timer."
        }
        public static let heartRateUp = "Heart rate confirms"
        public static let heartRateSteady = "Heart rate steady"
        public static let manualLink = "Can't verify? Check in manually"
        public static let noGymTitle = "Set up your gym first"
        public static let noGymMessage = "Save your gym once and workouts verify when you show up."
        public static let setUpGymButton = "Set up gym"
        public static let doneButton = "Done"
        public static let ringLabel = "Gym check-in progress"

        // MARK: - Manual check-in (spec §24 fallback, Tier C)

        public static let manualTitle = "Manual check-in"
        public static let manualHeadline = "Check in on your honor"
        public static let manualMessage = "For when GPS can't find you — a basement gym, a hotel, somewhere new. It counts toward today and shows as a manual check-in in your history."
        public static let manualRule = "One manual check-in a day."
        public static let manualHoldButton = "Hold to check in"
        public static let manualUsedToday = "You've used today's manual check-in."
        public static let manualAlreadyComplete = "Today's workout is already done."
        public static let manualNoGoal = "Add a gym workout goal first, then check in."
        public static let manualFailed = "Couldn't save that. Try again."
        public static let manualTierBadge = "Manual · counts, flagged"

        // MARK: - Presence notifications

        public static func arrivalNotificationTitle(gym: String) -> String { "At \(gym)" }
        public static func arrivalNotificationBody(minutes: Int) -> String {
            "Checked in. Stay \(minutes) min and your workout verifies itself."
        }
        public static func targetNotificationTitle(minutes: Int) -> String { "\(minutes) minutes in" }
        public static let targetNotificationBody = "Open ZANO to lock in your workout."
    }
}
