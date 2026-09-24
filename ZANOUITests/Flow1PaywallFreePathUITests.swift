// Flow1PaywallFreePathUITests.swift
// ZANOUITests -- scenario 1: the hard paywall renders with its legally required parts.
//
// The paywall is HARD (decision 2026-09-23): there is no "Continue with limited free" path any
// more, so this scenario no longer taps through it. (The file keeps its old name so the scenario
// order Flow1 -> Flow2 -> Flow3 is unchanged.) What it guards now, from
// App/ZANO/Features/Onboarding/PaywallView.swift:
//   1. Onboarding reaches the paywall as screen 13, straight after Commitment (screen 12; the NFC
//      tags screen at 9 moved everything after it up by one on 2026-09-24).
//   2. The headline ("Earn your phone back") renders.
//   3. Restore purchases is on screen without scrolling (App Review, and "restore purchases
//      visible"), as are the Terms and Privacy links.
//   4. No free path is offered.
//   5. If offerings loaded: Annual is there, the CTA offers the trial, and choosing Monthly (no
//      trial) switches the CTA to "Subscribe" -- the page never promises a trial the selected plan
//      does not have. If offerings failed (RevenueCat not linked yet, the usual case), "Try again"
//      is there instead. Which state was seen is attached to the result.
//
// It never buys anything and stops on the paywall, so the install stays un-onboarded for the next
// scenario (no `onFinished`, no lock started).
//
// DEVICE-ONLY: reaching screen 13 passes screen 4's FamilyActivityPicker. It drives screens 1-12
// itself (the same path `driveOnboardingToPaywall` in ZANOUIScenarioSupport.swift now takes).
//
// UNVERIFIED -- see ZANOUIScenarioSupport.swift header. Lookups are label-based.

import XCTest

final class Flow1PaywallFreePathUITests: ZANOScenarioTestCase {

    /// Paywall screen number (`OnboardingContainerView.screen(for:)`): 12 after the 2026-09-23
    /// reorder, 13 since the NFC tags screen went in at 9 (2026-09-24).
    private static let paywallStep = 13

    /// Test-side lookups for strings `ZANOUILabel.Paywall` does not mirror yet (NOT app copy).
    private enum Label {
        /// Prefix of Copy.paywall.startTrialButtonLabel(trialDays:) -- "Start my 7-day free trial".
        static let startTrial = "Start my"
        /// Copy.paywall.subscribeButtonLabel.
        static let subscribe = "Subscribe"
        /// Copy.paywall.monthlyPlanTitle.
        static let monthlyPlan = "Monthly"
        /// Copy.paywall.termsLinkLabel / privacyLinkLabel.
        static let terms = "Terms of use"
        static let privacy = "Privacy policy"
        /// The removed free path's label, asserted absent.
        static let removedFreePath = "Continue with limited free"
    }

    @MainActor
    func test1_HardPaywallShowsRestoreTermsAndNoFreePath() throws {
        try requireFamilyControlsEnvironment()
        let app = launchApp()
        try requireFreshOnboarding(app)
        try driveOnboardingToHardPaywall(app)

        let P = ZANOUILabel.Paywall.self

        // -- (1)-(2) On the paywall. -------------------------------------------------------------
        XCTAssertTrue(
            app.anyElement(labelContaining: P.headline).waitForExistence(timeout: 10),
            "Paywall headline ('\(P.headline)') not found on step \(Self.paywallStep)."
        )

        // -- (3) Restore, Terms and Privacy visible without scrolling. ---------------------------
        let restore = app.button(labelContaining: P.restorePurchases)
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "'\(P.restorePurchases)' is missing.")
        XCTAssertTrue(restore.isHittable, "'\(P.restorePurchases)' is not on screen without scrolling.")
        XCTAssertTrue(app.button(labelContaining: Label.terms).isHittable, "'\(Label.terms)' is not on screen.")
        XCTAssertTrue(app.button(labelContaining: Label.privacy).isHittable, "'\(Label.privacy)' is not on screen.")

        // -- (4) No free path. -------------------------------------------------------------------
        XCTAssertFalse(
            app.button(labelContaining: Label.removedFreePath).exists,
            "The hard paywall still offers '\(Label.removedFreePath)'."
        )

        // -- (5) Offerings: loaded or a calm failure, never stuck. -------------------------------
        let retry = app.button(labelContaining: P.retryOfferings)
        let annual = app.button(labelContaining: P.annualPlan)
        _ = poll(timeout: 20) { retry.exists || annual.exists }
        XCTAssertTrue(retry.exists || annual.exists, "Offerings still loading after 20s (no plans, no 'Try again').")

        if annual.exists {
            attachNote("offerings LOADED (plan tiles visible)", named: "Paywall offerings state observed")
            XCTAssertTrue(
                app.button(labelContaining: Label.startTrial).exists,
                "Annual is pre-selected with a trial, but the CTA does not offer it."
            )
            let monthly = app.button(labelContaining: Label.monthlyPlan)
            if monthly.exists {
                monthly.tap()
                XCTAssertTrue(
                    app.button(labelContaining: Label.subscribe).waitForExistence(timeout: 5),
                    "Monthly has no trial, but the CTA did not switch to '\(Label.subscribe)'."
                )
            }
        } else {
            attachNote(
                "offerings FAILED to load ('\(P.retryOfferings)' visible) -- RevenueCat not linked or no products",
                named: "Paywall offerings state observed"
            )
            XCTAssertTrue(retry.isEnabled, "'\(P.retryOfferings)' is disabled.")
        }

        XCTAssertTrue(
            waitForOnboardingStep(Self.paywallStep, in: app, timeout: 2),
            "Left the paywall without a purchase."
        )
    }

    // MARK: - Driving screens 1-12

    /// Screens 1-12 in the current order, ending on the paywall (screen 13).
    @MainActor
    private func driveOnboardingToHardPaywall(_ app: XCUIApplication) throws {
        let L = ZANOUILabel.Onboarding.self
        let continueButton = app.button(labelContaining: L.continueButton)

        advance(app, from: 1, tapping: app.button(labelContaining: L.hookCTA))
        advance(app, from: 2, tapping: continueButton)

        XCTAssertTrue(waitForOnboardingStep(3, in: app), "Expected onboarding step 3.")
        let goalOption = app.button(labelContaining: L.mainGoalGym)
        XCTAssertTrue(goalOption.waitForExistence(timeout: 10), "Step 3: main-goal option not found.")
        goalOption.tap()
        advance(app, from: 3, tapping: continueButton)

        XCTAssertTrue(waitForOnboardingStep(4, in: app), "Expected onboarding step 4.")
        let pickerOpener = app.button(labelContaining: L.appPickerButton)
        XCTAssertTrue(pickerOpener.waitForExistence(timeout: 10), "Step 4: 'Choose apps' button not found.")
        try chooseAppsWithFamilyActivityPicker(app, opener: pickerOpener)
        advance(app, from: 4, tapping: continueButton)

        advance(app, from: 5, tapping: continueButton)
        advance(app, from: 6, tapping: continueButton)

        XCTAssertTrue(waitForOnboardingStep(7, in: app), "Expected onboarding step 7.")
        let fallOff = app.button(labelContaining: L.fallOffEvenings)
        XCTAssertTrue(fallOff.waitForExistence(timeout: 10), "Step 7: fall-off option not found.")
        fallOff.tap()
        advance(app, from: 7, tapping: continueButton)

        advance(app, from: 8, tapping: continueButton)
        chooseNFCSkip(app)
        advance(app, from: 9, tapping: continueButton)
        advance(app, from: 10, tapping: app.button(labelContaining: L.wakeUpContinue))
        advance(app, from: 11, tapping: app.button(labelContaining: L.planContinue))

        XCTAssertTrue(waitForOnboardingStep(12, in: app), "Expected onboarding step 12.")
        let commit = app.button(labelContaining: L.holdToCommit)
        XCTAssertTrue(commit.waitForExistence(timeout: 10), "Step 12: 'Hold to commit' button not found.")
        commit.holdToCommit()
        XCTAssertTrue(
            waitForOnboardingStep(Self.paywallStep, in: app, timeout: 20),
            "Held 'Hold to commit' but never reached the paywall (step \(Self.paywallStep))."
        )
        settle()
    }
}
