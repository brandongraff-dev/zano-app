// SettingsCopy.swift
// Core / Copy
//
// `Copy.settings` — every user-facing string `App/ZANO/Features/Settings/SettingsView.swift`
// calls, under the `Copy.<area>.<key>` umbrella this codebase actually uses (see `Copy.swift`'s
// header; `OnboardingCopy.swift`/`FuelCopy.swift`/`TrophyCosmeticsCopy.swift` are the precedent
// this follows). This is a reconciliation, not new scope: `SettingsView.swift`'s own "ASSUMED
// API" header comment already documents this exact key list, member for member — this file adds
// the umbrella shape that view already calls rather than re-deriving it. Repo-wide sweep
// (2026-09-22): this namespace was referenced across ~120 call sites in `SettingsView.swift` (the
// screen itself, `GymSetupDetailView`, `AddGymSheet`, `NFCTagSetupDetailView`, `MapTagSheet`) but
// never declared anywhere in `Core/Sources/Core/Copy`, which would have failed to compile.
//
// `Copy.common.ok`/`.cancel`/`.save`/`.delete` (also referenced by this same cluster) already
// exist in `CommonCopy.swift` — not duplicated here.

import Foundation

extension Copy {
    public enum settings {
        public static let screenTitle = "Settings"
        public static let saveErrorTitle = "Couldn't save that"
        public static let finishSetupFooter = "Finish setup to use these options."

        // MARK: - Coach voice (spec §5.13)

        public static let coachVoiceSectionTitle = "Coach voice"
        public static let coachVoiceSectionFooter = "Switch anytime. This changes how your coach talks to you, not what it asks of you."

        // MARK: - Gym Setup (spec §3, §9.4)

        public static let gymSetupRowLabel = "Gym setup"
        public static let gymSetupTitle = "Gym setup"
        public static let gymEmptyTitle = "No gyms saved yet"
        public static let gymEmptyMessage = "Add your gym so workouts can verify automatically."
        public static let gymAddButtonLabel = "Add a gym"
        public static let gymAddSheetTitle = "Add a gym"
        public static let gymNameFieldLabel = "Name"
        public static let gymNameFieldPlaceholder = "e.g. Downtown Fitness"
        public static func gymRadiusFieldLabel(meters: Int) -> String { "Radius: \(meters)m" }
        public static let gymLocateButtonLabel = "Use current location"
        public static let gymLocatingLabel = "Locating…"
        public static let gymLocationFailedMessage = "Couldn't get your location. Check Location Services in the iPhone Settings app."
        public static let gymUnnamedLabel = "Unnamed gym"
        public static let gymConfirmedLabel = "Confirmed"
        public static let gymUnconfirmedLabel = "Not confirmed yet"
        public static let gymConfirmButtonLabel = "Confirm"
        public static let gymAutoDetectedLabel = "Auto-detected"

        // MARK: - NFC Tag Setup (spec §6, §25.1)

        public static let nfcTagSetupRowLabel = "NFC tags"
        public static let nfcSetupTitle = "NFC tags"
        // One verb for the user action, everywhere: "Add a tag" (was "Scan a new tag" here, "Map
        // Tag" on the sheet, "registered"/"set up" on the alarm screens).
        public static let nfcScanButtonLabel = "Add a tag"
        public static let nfcScanAlertMessage = "Hold your iPhone near the tag."
        public static let nfcScanFailedTitle = "Couldn't read that tag"
        public static let nfcUnavailableMessage = "NFC scanning isn't available on this device."
        public static let nfcYourTagsSectionTitle = "Your tags"
        public static let nfcHowItWorksSectionTitle = "How it works"
        public static let nfcTroubleshootingSectionTitle = "Troubleshooting"

        public static let nfcMapSheetTitle = "New tag"
        public static let nfcMapKindSectionTitle = "Tag placement"
        public static let nfcMapKindFieldLabel = "Where is this tag?"
        public static let nfcMapActionSectionTitle = "Action"
        public static let nfcMapActionFieldLabel = "When tapped"
        public static let nfcMapAmountFieldLabel = "Amount"
        public static let nfcMapLabelSectionTitle = "Label"
        public static let nfcMapLabelFieldPlaceholder = "e.g. Kitchen shaker"
        public static let nfcMapLockSetFieldLabel = "Lock set"
        public static let nfcMapLockSetNoneLabel = "None"

        public static let nfcKindSunriseLabel = "Sunrise Tag"
        public static let nfcKindBottleLabel = "Water bottle"
        public static let nfcKindShakerLabel = "Shaker"
        public static let nfcKindDeskLabel = "Desk"
        public static let nfcKindGymBagLabel = "Gym bag"
        public static let nfcKindCustomLabel = "Custom"

        public static let nfcActionStartLockLabel = "Start lock"
        public static let nfcActionLogWaterLabel = "Log water"
        public static let nfcActionLogProteinLabel = "Log protein"
        public static let nfcActionLogCreatineLabel = "Log creatine"
        /// The action a Sunrise Tag runs when tapped (the `.sunriseKey` action). Was "Sunrise Key" —
        /// an orphan term users never meet elsewhere. Written as a verb phrase like its siblings
        /// ("Start lock", "Log water"). `SunriseKeyIntent`'s Shortcuts title (outside Copy) still
        /// says "Sunrise Key".
        public static let nfcActionSunriseKeyLabel = "Turn off Sunrise Alarm"

        public static let nfcForgetTagButtonLabel = "Remove"

        // MARK: - Subscription (spec §21 hard paywall: every user is on the trial or paid)

        public static let subscriptionSectionTitle = "Subscription"
        public static let planLabel = "Plan"
        public static let renewsLabel = "Renews"
        public static let trialEndsLabel = "Trial ends"
        public static let planProLabel = "ZANO Pro"
        public static let planStatusActive = "Active"
        public static let planStatusTrial = "Free trial"
        public static let planManagedByAppleNote = "Billing is handled by Apple. Change or cancel your plan in your Apple Account."
        public static let manageSubscriptionButtonLabel = "Manage subscription"
        public static let restorePurchasesButtonLabel = "Restore purchases"
        public static let restoreFailedTitle = "Couldn't restore purchases"
        public static let restoreFailedMessage = "Check your connection and try again."
        public static let restoreUnavailableTitle = "Restore unavailable"
        public static let restoreUnavailableMessage = "Restoring purchases isn't available right now. Try again later."
        public static let restoreNothingFoundTitle = "Nothing to restore"
        public static let restoreNothingFoundMessage = "No purchases found for this Apple Account."
        public static let restoreSucceededTitle = "Purchases restored"
        public static let restoreSucceededMessage = "Your subscription is active on this iPhone."

        // MARK: - Setup rows

        public static let goalsRowLabel = "Goals"

        // MARK: - Goals editor (spec §3 catalog; §24: additive goals only)

        public static let goalsEditorTitle = "Goals"
        public static let goalsYourGoalsSectionTitle = "Your goals"
        public static let goalsFooter = "Change a target anytime. Smaller is fine. Showing up is what counts."
        public static let goalsEmptyTitle = "No goals yet"
        public static let goalsEmptyMessage = "Add a goal to start earning your apps back."
        public static let goalsAddButtonLabel = "Add goal"
        public static let goalsAddDialogTitle = "Add a goal"
        public static let goalsAllAddedMessage = "You've added every goal that's available right now."
        public static let goalsNeedsProfileMessage = "Finish setup to add goals."
        public static let goalRemoveMenuLabel = "Remove goal"
        public static func goalRemoveConfirmTitle(title: String) -> String { "Remove \(title)?" }
        public static let goalRemoveConfirmMessage = "It stops counting toward your locks. Your history stays, and you can add it back anytime."
        public static let goalRemoveButtonLabel = "Remove"
        public static func goalTargetDecreaseLabel(title: String) -> String { "Lower the target for \(title)" }
        public static func goalTargetIncreaseLabel(title: String) -> String { "Raise the target for \(title)" }

        /// "3 workouts a week", "25 min a day", "120 g a day". Units are the ones onboarding stores
        /// on `Goal.unit` ("workouts", "min", "g"); anything else falls back to "<value> <unit>".
        public static func goalTargetSummary(type: GoalType, value: Int, unit: String?) -> String {
            switch type {
            case .workoutGym, .workoutHomeOutdoor:
                value == 1 ? "1 workout a week" : "\(value) workouts a week"
            case .focusSession:
                "\(value) min a day"
            case .protein:
                "\(value) g a day"
            case .steps:
                "\(value.formatted()) steps a day"
            case .water where unit == "ml" || unit == "oz":
                "\(value.formatted()) \(unit ?? "") a day"
            default:
                if let unit, !unit.isEmpty { "\(value) \(unit)" } else { "\(value)" }
            }
        }

        // MARK: - Save errors (never show raw system error text)

        public static let saveErrorMessage = "Your change wasn't saved. Try again."

        // MARK: - Confirmations

        public static func gymDeleteConfirmTitle(name: String) -> String { "Delete \(name)?" }
        public static let gymDeleteConfirmMessage = "Workouts here won't verify automatically anymore."
        public static func nfcRemoveConfirmTitle(label: String) -> String { "Remove \(label)?" }
        public static let nfcRemoveConfirmMessage = "Tapping this tag won't do anything until you add it again."
        public static let nfcScanFailedMessage = "Hold the top of your iPhone near the tag and try again."
        public static let nfcUnnamedTagLabel = "this tag"

        // MARK: - Notifications

        public static let notificationsSectionTitle = "Notifications"
        public static let notificationsRowLabel = "Notifications"
        public static let notificationsFooter = "Reminders, lock alerts, and your weekly recap. Choose which ones you get in the iPhone Settings app."

        // MARK: - Gear (spec §25.6)

        public static let gearSectionTitle = "Gear"
        public static let gearRowLabel = "ZANO gear store"
        public static func gearOfferShaker(tapCount: Int) -> String {
            "You've logged \(tapCount) shakes. Check out the ZANO shaker."
        }
        public static func gearOfferEarnedCard(streakDays: Int) -> String {
            "\(streakDays)-day streak. You've earned a Lock Card, free for subscribers."
        }

        // MARK: - About, support and legal (spec §24)

        public static let aboutSectionTitle = "About"
        public static let versionLabel = "Version"
        public static let privacyPolicyButtonLabel = "Privacy policy"
        public static let termsOfUseButtonLabel = "Terms of use"
        public static let helpRowLabel = "Help & feedback"
        public static let helpTitle = "Help & feedback"
        public static let helpMessage = "Questions, bugs, or ideas? Write to us. A real person reads every message."
        public static let helpEmailLabel = "Email"
        public static let helpEmailButtonLabel = "Email us"
        /// PLACEHOLDER — confirm the real support inbox before release.
        public static let supportEmail = "support@zano.app"
        /// PLACEHOLDER — must point at the real, published terms before release.
        public static let termsOfUseURLString = "https://zano.app/terms"
        /// PLACEHOLDER — must point at the real, published privacy policy before release.
        public static let privacyPolicyURLString = "https://zano.app/privacy"
        /// Apple's documented subscription-management page.
        public static let manageSubscriptionsURLString = "https://apps.apple.com/account/subscriptions"

        // MARK: - Pause for health reasons (spec §24)

        public static let pauseRowLabel = "Pause for health reasons"
        public static let pauseTitle = "Pause for health reasons"
        public static let pauseHeadline = "Your health comes first."
        public static let pauseMessage = "If you're sick, injured, or need a break from anything around food or your body, take it. Nothing here is worth pushing through that."
        public static let pauseStopLockTitle = "Stop a lock now"
        public static let pauseStopLockMessage = "Emergency unlock on the Lock tab always works."
        public static let pauseStopLockButtonLabel = "Go to Lock"
        public static let pauseEditGoalsButtonLabel = "Edit goals"
        public static let pauseEditGoalsTitle = "Change or remove goals"
        public static let pauseEditGoalsMessage = "Lower a target or remove a goal for as long as you need."
        public static let pauseContactTitle = "Talk to us"
        public static let pauseContactMessage = "Write to us and we'll help you take a break."
        public static let pauseContactButtonLabel = "Contact support"

        // MARK: - Delete all data (spec §24 privacy)

        public static let dataSectionTitle = "Your data"
        public static let deleteAllDataRowLabel = "Delete all my data"
        public static let deleteAllDataFooter = "Removes your goals, streaks, lock sets, gyms, tags, and history from this iPhone."
        public static let deleteAllDataConfirmTitle = "Delete all your data?"
        public static let deleteAllDataConfirmMessage = "This removes your goals, streaks, lock sets, gyms, tags, and history from this iPhone and ends any active lock. It can't be undone. Your subscription isn't affected."
        public static let deleteAllDataConfirmButtonLabel = "Delete everything"
        public static let deleteAllDataDoneTitle = "Your data was deleted"
        public static let deleteAllDataDoneMessage = "Close and reopen ZANO to start fresh."
        public static let deleteAllDataFailedTitle = "Couldn't delete everything"
        public static let deleteAllDataFailedMessage = "Some data wasn't removed. Try again."

        // MARK: - Daily Rhythm (spec §5.10) — Sunrise Alarm / Bedtime Gate entries

        public static let dailyRhythmSectionTitle = "Sleep & mornings"
        public static let sunriseAlarmRowLabel = "Sunrise Alarm"
        public static let bedtimeGateRowLabel = "Bedtime Gate"

        // MARK: - Rewards (spec §5.17) — Trophy Case / Cosmetics Shop entries

        public static let rewardsSectionTitle = "Rewards"
        public static let trophyCaseRowLabel = "Trophy Case"
        public static let cosmeticsShopRowLabel = "Cosmetics Shop"
    }
}
