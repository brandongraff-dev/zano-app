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
        public static let finishSetupFooter = "Finish setting up your account to unlock these options."

        // MARK: - Coach Voice (spec §5.13)

        public static let coachVoiceSectionTitle = "Coach Voice"
        public static let coachVoiceSectionFooter = "Switch anytime — this changes how your coach talks to you, not what it asks of you."

        // MARK: - Gym Setup (spec §3, §9.4)

        public static let gymSetupRowLabel = "Gym Setup"
        public static let gymSetupTitle = "Gym Setup"
        public static let gymEmptyTitle = "No gyms saved yet"
        public static let gymEmptyMessage = "Add your gym so workouts can verify automatically."
        public static let gymAddButtonLabel = "Add Gym"
        public static let gymAddSheetTitle = "Add Gym"
        public static let gymNameFieldLabel = "Name"
        public static let gymNameFieldPlaceholder = "e.g. Downtown Fitness"
        public static func gymRadiusFieldLabel(meters: Int) -> String { "Radius: \(meters)m" }
        public static let gymLocateButtonLabel = "Use current location"
        public static let gymLocatingLabel = "Locating…"
        public static let gymLocationFailedMessage = "Couldn't get your location. Check Settings > Privacy > Location Services."
        public static let gymUnnamedLabel = "Unnamed gym"
        public static let gymConfirmedLabel = "Confirmed"
        public static let gymUnconfirmedLabel = "Not confirmed yet"
        public static let gymConfirmButtonLabel = "Confirm"
        public static let gymAutoDetectedLabel = "Auto-detected"

        // MARK: - NFC Tag Setup (spec §6, §25.1)

        public static let nfcTagSetupRowLabel = "NFC Tags"
        public static let nfcSetupTitle = "NFC Tags"
        public static let nfcScanButtonLabel = "Scan a new tag"
        public static let nfcScanAlertMessage = "Hold your iPhone near the tag."
        public static let nfcScanFailedTitle = "Couldn't read that tag"
        public static let nfcUnavailableMessage = "NFC scanning isn't available on this device."
        public static let nfcYourTagsSectionTitle = "Your Tags"
        public static let nfcHowItWorksSectionTitle = "How It Works"
        public static let nfcTroubleshootingSectionTitle = "Troubleshooting"

        public static let nfcMapSheetTitle = "Map Tag"
        public static let nfcMapKindSectionTitle = "Tag Placement"
        public static let nfcMapKindFieldLabel = "Where is this tag?"
        public static let nfcMapActionSectionTitle = "Action"
        public static let nfcMapActionFieldLabel = "When tapped"
        public static let nfcMapAmountFieldLabel = "Amount"
        public static let nfcMapLabelSectionTitle = "Label"
        public static let nfcMapLabelFieldPlaceholder = "e.g. Kitchen shaker"
        public static let nfcMapLockSetFieldLabel = "Lock Set"
        public static let nfcMapLockSetNoneLabel = "None"

        public static let nfcKindSunriseLabel = "Sunrise Tag"
        public static let nfcKindBottleLabel = "Water Bottle"
        public static let nfcKindShakerLabel = "Shaker"
        public static let nfcKindDeskLabel = "Desk"
        public static let nfcKindGymBagLabel = "Gym Bag"
        public static let nfcKindCustomLabel = "Custom"

        public static let nfcActionStartLockLabel = "Start Lock"
        public static let nfcActionLogWaterLabel = "Log Water"
        public static let nfcActionLogProteinLabel = "Log Protein"
        public static let nfcActionLogCreatineLabel = "Log Creatine"
        public static let nfcActionSunriseKeyLabel = "Sunrise Key"

        public static let nfcForgetTagButtonLabel = "Forget Tag"

        // MARK: - Subscription (spec §21, §24)

        public static let subscriptionSectionTitle = "Subscription"
        public static let planLabel = "Plan"
        public static let renewsLabel = "Renews"
        public static let planFreeLabel = "Free"
        public static let planProLabel = "Pro"
        public static let manageSubscriptionButtonLabel = "Manage Subscription"
        public static let restorePurchasesButtonLabel = "Restore Purchases"
        public static let restoreFailedTitle = "Couldn't restore purchases"
        public static let restoreUnavailableTitle = "Restore unavailable"
        public static let restoreUnavailableMessage = "Purchases aren't available in this build yet."

        public static let proBenefits = [
            "Unlimited lock sets",
            "Full coach voice library",
            "Cosmetics Shop access",
        ]
        public static let proPriceLabel = "$6.99/month"
        public static let proHeadline = "Go Pro"
        public static let proCtaLabel = "Upgrade"

        // MARK: - Gear (spec §25.6)

        public static let gearSectionTitle = "Gear"
        public static let gearRowLabel = "ZANO Gear Store"
        public static func gearOfferShaker(tapCount: Int) -> String {
            "You've logged \(tapCount) shakes — check out the bottle that logs itself."
        }
        public static func gearOfferEarnedCard(streakDays: Int) -> String {
            "\(streakDays)-day streak — you've earned a card. Get it shipped."
        }

        // MARK: - About (spec §24)

        public static let aboutSectionTitle = "About"
        public static let versionLabel = "Version"
        public static let privacyPolicyButtonLabel = "Privacy Policy"

        // MARK: - Daily Rhythm (spec §5.10) — Sunrise Alarm / Bedtime Gate entries

        public static let dailyRhythmSectionTitle = "Sleep & Mornings"
        public static let sunriseAlarmRowLabel = "Sunrise Alarm"
        public static let bedtimeGateRowLabel = "Bedtime Gate"

        // MARK: - Rewards (spec §5.17) — Trophy Case / Cosmetics Shop entries

        public static let rewardsSectionTitle = "Rewards"
        public static let trophyCaseRowLabel = "Trophy Case"
        public static let cosmeticsShopRowLabel = "Cosmetics Shop"
    }
}
