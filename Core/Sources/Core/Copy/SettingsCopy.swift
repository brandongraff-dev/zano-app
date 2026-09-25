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
        // The rest of the gym strings moved to `Copy.gym` (GymCopy.swift) with the screens.

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

        public static func nfcRemoveConfirmTitle(label: String) -> String { "Remove \(label)?" }
        public static let nfcRemoveConfirmMessage = "Tapping this tag won't do anything until you add it again."
        public static let nfcScanFailedMessage = "Hold the top of your iPhone near the tag and try again."
        public static let nfcUnnamedTagLabel = "this tag"

        // MARK: - Notifications

        public static let notificationsSectionTitle = "Notifications"
        public static let notificationsRowLabel = "Notifications"
        public static let notificationsFooter = "Choose your nudges here. Sounds, banners, and turning everything off live in the iPhone Settings app."
        public static let systemNotificationsRowLabel = "iPhone notification settings"

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

        // MARK: - Pause for health reasons (spec §24) — calm, no guilt, nothing about food/body goals

        public static let pauseRowLabel = "Pause for health reasons"
        public static let pauseTitle = "Pause for health reasons"
        public static let pauseHeadline = "Your health comes first."
        public static let pauseMessage = "If you're sick, injured, or need a break from anything around food or your body, take it. Nothing here is worth pushing through that."
        public static let pauseToggleLabel = "Pause ZANO"
        public static let pauseWhatHappensTitle = "While you're paused"
        public static let pauseWhatHappensLocks = "No scheduled locks. A lock that's on now ends right away."
        public static let pauseWhatHappensStreak = "Your streak waits for you. Paused days never count as missed."
        public static let pauseWhatHappensNudges = "No nudges."
        public static let pauseLengthTitle = "How long"
        public static let pauseLengthThreeDays = "3 days"
        public static let pauseLengthOneWeek = "1 week"
        public static let pauseLengthTwoWeeks = "2 weeks"
        public static let pauseLengthUntilOff = "Until I turn it off"
        public static let pauseStartButtonLabel = "Start pause"
        public static let pauseResumeButtonLabel = "Resume now"
        public static let pauseActiveTitle = "You're paused"
        public static func pauseActiveUntil(_ date: String) -> String { "Paused until \(date). Take the time you need." }
        public static let pauseActiveOpenEnded = "Paused until you turn it off. Take the time you need."
        public static let pauseActiveExtendHint = "Picking a new length starts the pause again from now."
        public static let pauseResumeFooter = "Come back whenever you're ready. Your goals and streak will be right where you left them."
        /// Settings status capsule.
        public static let pauseStatusCapsule = "Health pause on"
        public static func pauseStatusCapsuleUntil(_ date: String) -> String { "Health pause on · until \(date)" }
        public static let pauseStatusCapsuleHint = "Opens health pause settings"
        public static let pauseEditGoalsButtonLabel = "Edit goals"
        public static let pauseEditGoalsTitle = "Change or remove goals"
        public static let pauseEditGoalsMessage = "Lower a target or remove a goal for as long as you need."
        public static let pauseContactTitle = "Talk to us"
        public static let pauseContactMessage = "Write to us and we'll help you take a break."
        public static let pauseContactButtonLabel = "Contact support"

        // MARK: - Nudges (spec §8 rule 7, §9.3)

        public static let nudgesRowLabel = "Nudges"
        public static let nudgesTitle = "Nudges"
        public static let nudgesToggleLabel = "Nudges"
        public static let nudgesIntro = "A nudge is a short reminder when it could change your day. Choose which ones you get and when."
        public static let nudgesCapNote = "ZANO sends at most 2 nudges a day, never more. That limit is built in."
        public static let nudgesTypesSectionTitle = "Which nudges"
        public static let nudgeKindMorningPlanTitle = "Morning plan"
        public static let nudgeKindMorningPlanDetail = "Today's goals, first thing."
        public static let nudgeKindProteinTitle = "Protein last mile"
        public static let nudgeKindProteinDetail = "An evening heads-up when you're close to your protein goal."
        public static let nudgeKindStreakTitle = "Streak at risk"
        public static let nudgeKindStreakDetail = "When today's goals are still open late in the day."
        public static let nudgeKindRecapTitle = "Weekly recap"
        public static let nudgeKindRecapDetail = "Your week in one card."
        public static let nudgesQuietSectionTitle = "Quiet hours"
        public static let nudgesQuietToggleLabel = "Quiet hours"
        public static let nudgesQuietStartLabel = "From"
        public static let nudgesQuietEndLabel = "Until"
        public static let nudgesQuietFooter = "No nudges during these hours. Alarms you set yourself, like Sunrise Alarm, still ring."
        public static let nudgesPausedNote = "Nudges are off while your health pause is on."
        public static let nudgesSystemFooter = "To turn off all notifications from ZANO, use the iPhone Settings app."

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

// MARK: - Wave 3L: invite, Auto-Focus guide, Founder Series

extension Copy.settings {
    public static let inviteFriendsRowLabel = "Invite friends"
    public static let autoFocusRowLabel = "Auto-Focus"
    public static let autoFocusRowValueOn = "On"
    public static let calendarAwarenessRowLabel = "Lighter plans on packed days"
    public static let calendarAwarenessDeniedTitle = "Calendar access is off"
    public static let calendarAwarenessDenied = "Turn on Calendar access for ZANO in iOS Settings, then try again."

    // Auto-Focus guide (spec §5.12). The steps and limits themselves live in
    // `AutoFocusSetupInstructions` (same directory).
    public static let autoFocusScreenTitle = "Auto-Focus"
    public static let autoFocusHeadline = "Quiet notifications during a lock"
    public static let autoFocusStepsTitle = "Set it up"
    /// "Step 3 of 7".
    public static func autoFocusStepLabel(_ step: Int, of total: Int) -> String { "Step \(step) of \(total)" }
    public static let autoFocusOpenShortcuts = "Open Shortcuts"
    public static let autoFocusTestTitle = "Test it"
    public static let autoFocusTestBody =
        "Swipe ZANO away in the App Switcher, then open it again. Your Focus should turn on within a second."
    public static let autoFocusMarkDone = "I've set it up"
    public static let autoFocusMarkedDone = "Auto-Focus is set up"
    public static let autoFocusRemove = "I removed the automation"
    public static let autoFocusNFCTitle = "Using NFC tags?"
    public static let autoFocusTurnOffTitle = "Turning Focus off"
    public static let autoFocusLimitsTitle = "Limits"
    public static let autoFocusTroubleshootingTitle = "Not working?"

    // Founder Series (spec §5.22). No content link yet, so the card has no button.
    public static let founderCardBody =
        "ZANO is built by one founder, in public. Build updates will show up here once they're posted."
}
