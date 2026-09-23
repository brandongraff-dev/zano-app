// Flow1PaywallFreePathUITests.swift
// ZANOUITests -- scenario 3: the paywall's "Continue with limited free" path stays reachable.
//
// Why this is its own scenario: App Store review requires that a reviewer with no subscription
// (and possibly with no approved sandbox products at all) can get past the paywall and use the
// app. docs/spec.md §7.13 / §21: "Clear 'Continue with limited free' option below (1 goal, 1 lock
// set)", "clear free path", "no dark patterns"; spec §24: "restore purchases visible".
//
// What the code guarantees today (App/ZANO/Features/Onboarding/PaywallView.swift): the free link
// is unconditional in `ctaSection` -- it does not depend on `viewModel.loadState` -- and its
// action is `viewModel.continueWithLimitedFree(); flowState.advance()`. So the property under
// test is a REGRESSION GUARD: if someone later hides the link behind `.loaded`, disables it while
// a purchase is in flight, or moves it off the scrollable content, this fails. RevenueCat is not
// linked yet, so on a real run offerings normally FAIL to load ("Try again" state) -- which is
// exactly the situation a reviewer whose sandbox products are not approved sees, and the free
// path must still work there. The test records which load state it observed as an attachment.
//
// Reaching the paywall means passing onboarding screens 1-12, including screen 4's
// FamilyActivityPicker, so this is DEVICE-ONLY (see ZANOUIScenarioSupport.swift precondition 2).
// It stops on screen 14 and never triggers `onFinished` (the only place `OnboardingContainerView`
// reports completion), so it leaves the install un-onboarded for the next scenario PROVIDED the
// app shell records "onboarding finished" only from `onFinished`. `AppRouter.completeOnboarding()`
// (the `onFinished` hook in `ContentView`) does; its one other writer is a launch-time guard that
// marks onboarding done when a lock is ALREADY active (`SharedDefaults.activeLockSessionID`), which
// this test never starts (it stops before screen 14's "Start focus session"). (Commitment/Plan
// Reveal do write User/Goal/LockSet rows; those steps are idempotent on a rerun.) Flow2 covers
// free path -> first win -> Today end to end.
//
// UNVERIFIED -- see ZANOUIScenarioSupport.swift header. No accessibility identifiers exist yet, so
// lookups are label-based via `ZANOUILabel.Paywall`.

import XCTest

final class Flow1PaywallFreePathUITests: ZANOScenarioTestCase {

    @MainActor
    func test1_ContinueWithLimitedFreeStaysReachableAndLeavesThePaywall() throws {
        try requireFamilyControlsEnvironment()
        let app = launchApp()
        try requireFreshOnboarding(app)
        try driveOnboardingToPaywall(app)   // steps 1...12, ends on step 13

        let P = ZANOUILabel.Paywall.self

        // -- On the paywall. -------------------------------------------------------------------
        XCTAssertTrue(waitForOnboardingStep(13, in: app), "Expected to be on the paywall (step 13).")
        XCTAssertTrue(
            app.anyElement(labelContaining: P.headline).waitForExistence(timeout: 10),
            "Paywall headline ('\(P.headline)') not found -- is step 13 really PaywallView?"
        )

        // -- (1) The free path exists straight away, whatever RevenueCat is doing. -------------
        // Checked BEFORE waiting for offerings to settle: the link must not be gated on loading.
        let freeLink = app.button(labelContaining: P.continueWithLimitedFree)
        XCTAssertTrue(
            revealByScrolling(freeLink, in: app),
            "'\(P.continueWithLimitedFree)' is not reachable on the paywall (missing or not hittable after scrolling)."
        )

        // -- (2) Let the offerings state settle and record what we saw. -----------------------
        let retry = app.button(labelContaining: P.retryOfferings)
        let annual = app.button(labelContaining: P.annualPlan)
        _ = poll(timeout: 20) { retry.exists || annual.exists }
        let observedState = retry.exists
            ? "offerings FAILED to load ('\(P.retryOfferings)' visible) -- the reviewer-without-products case"
            : (annual.exists ? "offerings LOADED (plan cards visible)" : "offerings still LOADING after 20s")
        attachNote(observedState, named: "Paywall offerings state observed")

        // -- (3) Still reachable and enabled in that settled state. ---------------------------
        XCTAssertTrue(
            revealByScrolling(freeLink, in: app),
            "'\(P.continueWithLimitedFree)' disappeared or became unreachable once the paywall settled (\(observedState))."
        )
        XCTAssertTrue(freeLink.isEnabled, "'\(P.continueWithLimitedFree)' is disabled (\(observedState)).")

        // -- (4) Restore purchases is visible (spec §24; also an App Review expectation). ------
        let restore = app.button(labelContaining: P.restorePurchases)
        XCTAssertTrue(
            revealByScrolling(restore, in: app),
            "'\(P.restorePurchases)' is not visible on the paywall (spec §24)."
        )
        XCTAssertTrue(
            revealByScrolling(freeLink, in: app),
            "Could not scroll back to '\(P.continueWithLimitedFree)' after checking Restore."
        )

        // -- (5) Taking the free path leaves the paywall without any purchase. -----------------
        freeLink.tap()
        XCTAssertTrue(
            waitForOnboardingStep(14, in: app, timeout: 15),
            "Tapped '\(P.continueWithLimitedFree)' but onboarding never advanced to step 14 (first win)."
        )
        settle()
        XCTAssertFalse(
            app.anyElement(labelContaining: P.headline).exists,
            "Still showing the paywall after taking the free path."
        )
        XCTAssertTrue(
            app.button(labelContaining: ZANOUILabel.Onboarding.firstWinStart).waitForExistence(timeout: 10),
            "Step 14 ('\(ZANOUILabel.Onboarding.firstWinStart)') did not render after the free path."
        )
    }
}
