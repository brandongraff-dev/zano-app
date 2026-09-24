// Flow1HardPaywallUITests.swift
// ZANOUITests -- scenario 3: the paywall is a hard wall, and it stays honest.
//
// docs/spec.md §21 (decision 2026-09-23): there is NO free tier. The paywall is screen 12 of
// onboarding (right after Commitment, at the emotional peak) and the only way past it is to start
// the trial or subscribe. What must stay true, and what this scenario guards:
//   * the paywall renders, whatever RevenueCat is doing (offerings failing to load is the normal
//     state while the SDK is not linked, and it must show a retry, not a blank screen);
//   * the retired "Continue with limited free" escape hatch is really gone;
//   * "Restore purchases" is visible (spec §24; also an App Review expectation, it is how a
//     returning subscriber gets back in without paying twice);
//   * the paywall does not advance on its own: with no purchase the user stays on step 12
//     (the DEBUG-only `-ZANOSkipPaywall` flag that Flow2 uses is deliberately NOT passed here).
//
// Reaching the paywall means passing onboarding screens 1-11, including screen 4's
// FamilyActivityPicker, so this is DEVICE-ONLY (see ZANOUIScenarioSupport.swift precondition 2).
// It stops on screen 12 and never triggers `onFinished`, so it leaves the install un-onboarded for
// the next scenario. (Commitment writes User/Goal/LockSet rows; those steps are idempotent on a
// rerun.)
//
// UNVERIFIED on a device -- see ZANOUIScenarioSupport.swift header. No accessibility identifiers
// exist yet, so lookups are label-based via `ZANOUILabel.Paywall`.

import XCTest

final class Flow1HardPaywallUITests: ZANOScenarioTestCase {

    @MainActor
    func test1_PaywallIsAHardWallWithRestoreAndNoFreePath() throws {
        try requireFamilyControlsEnvironment()
        let app = launchApp()
        try requireFreshOnboarding(app)
        try driveOnboardingToPaywall(app)   // steps 1...11, ends on step 12

        let P = ZANOUILabel.Paywall.self

        // -- On the paywall. -------------------------------------------------------------------
        XCTAssertTrue(waitForOnboardingStep(12, in: app), "Expected to be on the paywall (step 12).")
        XCTAssertTrue(
            app.anyElement(labelContaining: P.headline).waitForExistence(timeout: 10),
            "Paywall headline ('\(P.headline)') not found -- is step 12 really PaywallView?"
        )

        // -- (1) Let the offerings state settle and record what we saw. ------------------------
        let retry = app.button(labelContaining: P.retryOfferings)
        let annual = app.button(labelContaining: P.annualPlan)
        _ = poll(timeout: 20) { retry.exists || annual.exists }
        let observedState = retry.exists
            ? "offerings FAILED to load ('\(P.retryOfferings)' visible)"
            : (annual.exists ? "offerings LOADED (plan cards visible)" : "offerings still LOADING after 20s")
        attachNote(observedState, named: "Paywall offerings state observed")
        XCTAssertTrue(
            retry.exists || annual.exists,
            "The paywall showed neither plans nor a retry after 20s (\(observedState)) -- a blank wall."
        )

        // -- (2) No free path. Spec §21: the wall is the wall. --------------------------------
        XCTAssertFalse(
            app.anyElement(labelContaining: P.retiredFreePath).exists,
            "The retired '\(P.retiredFreePath)' escape hatch is back on the paywall (spec §21: no free tier)."
        )

        // -- (3) Restore purchases is visible (spec §24; also an App Review expectation). ------
        let restore = app.button(labelContaining: P.restorePurchases)
        XCTAssertTrue(
            revealByScrolling(restore, in: app),
            "'\(P.restorePurchases)' is not visible on the paywall (spec §24)."
        )
        XCTAssertFalse(
            app.anyElement(labelContaining: P.retiredFreePath).exists,
            "The retired '\(P.retiredFreePath)' wording appeared after scrolling the paywall."
        )

        // -- (4) It does not let anyone through by itself. --------------------------------------
        settle(1.5)
        XCTAssertTrue(
            app.onboardingStep(12).exists,
            "The paywall left step 12 with no purchase (spec §21: hard wall)."
        )
        XCTAssertFalse(
            app.onboardingStep(13).exists,
            "Notification priming (step 13) appeared without a purchase."
        )
    }
}
