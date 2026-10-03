// Flow1PaywallFreePathUITests.swift
// ZANOUITests -- scenario 1: the hard paywall renders with its legally required parts.
//
// The paywall is HARD (decision 2026-09-23): there is no "Continue with limited free" path any
// more, so this scenario no longer taps through it. (The file keeps its old name so the scenario
// order Flow1 -> Flow2 -> Flow3 is unchanged.) What it guards now, from
// App/ZANO/Features/Onboarding/PaywallView.swift:
//   1. Onboarding reaches the paywall as step 7 of 8 (since the buddy step, 2026-10-03), straight after the plan step's hold to commit
//      (short flow, founder decision 2026-10-02; it was screen 13 of 15).
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
// DEVICE-ONLY: reaching step 7 passes step 5's FamilyActivityPicker. It uses the shared
// `driveOnboardingToPaywall` in ZANOUIScenarioSupport.swift.
//
// UNVERIFIED -- see ZANOUIScenarioSupport.swift header. Lookups are label-based.

import XCTest

final class Flow1PaywallFreePathUITests: ZANOScenarioTestCase {

    /// Paywall step number (`OnboardingStep.paywall`): 7 of 8 since the buddy step.
    private static let paywallStep = ZANOUILabel.Step.paywall

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
        try driveOnboardingToPaywall(app)

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
}
