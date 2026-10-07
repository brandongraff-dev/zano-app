// Flow2OnboardingCompletionUITests.swift
// ZANOUITests -- scenario 1: complete onboarding end to end and land on the Today tab.
//
// docs/spec.md §7 (14 screens, hook -> first win; paywall is screen 12, notification priming 13)
// and §2 (core loop). Screen 14 IS the core loop
// run once inside onboarding: lock -> 10-minute focus goal -> verified -> unlock + streak Day 1
// (spec §7.14, §8 rule 11).
//
// Two tests, split by what they need:
//   test1_  screens 1-4 only, NO FamilyControls. Runs on the Simulator. Checks the screen chain,
//           the Continue gates (screen 3 needs a goal, screen 4 needs picked apps) and the Back
//           button. This is the part of §7 that is checkable without a device.
//   test2_  the whole flow through the first win to Today. DEVICE ONLY, ~11 minutes.
//
// Both need a fresh install (there is no in-app reset hook) and the app shell that hosts
// `OnboardingContainerView` then a tab UI (`ContentView`, wired) -- see ZANOUIScenarioSupport.swift
// preconditions.
// test1_ leaves the install un-onboarded (it never gets past screen 4), so test2_ can follow it.
//
// The first win cannot be shortened from here. `Screen14FirstWin` runs a real 10-minute
// `FocusSessionVerifier` session with no skip; its only other exit is a 60-second emergency hold
// that exists only when a real `LockSession` started (device + approved Screen Time). Waiting the
// timer out is the honest end-to-end path and needs ~11 minutes with the app foregrounded and
// Auto-Lock off. Whether that session comes out VERIFIED ("Earned." + streak + widget prompt) or
// NOT verified ("Not this time" -> straight to finish) depends on `FocusSessionVerifier`; both
// exits are valid ways to finish onboarding, so the test accepts either and records which it saw.
//
// "Completing onboarding" is asserted three ways: the tab bar appears with Today selected, the
// Today screen's own header renders, and a terminate + relaunch lands on Today again instead of
// restarting onboarding (i.e. the "onboarding finished" state persists).
//
// UNVERIFIED -- see ZANOUIScenarioSupport.swift header. No accessibility identifiers exist yet.

import XCTest

final class Flow2OnboardingCompletionUITests: ZANOScenarioTestCase {

    /// 10-minute focus timer + start/finish overhead + slack.
    private static let firstWinTimeout: TimeInterval = 12 * 60

    // MARK: - Screens 1-4 (Simulator-safe)

    @MainActor
    func test1_EarlyScreensAdvanceAndGateContinue() throws {
        let app = launchApp()
        try requireFreshOnboarding(app)
        let L = ZANOUILabel.Onboarding.self
        let continueButton = app.button(labelContaining: L.continueButton)

        // 1 Hook -> 2 Social proof -> 3 Q1 (spec §7.1-§7.3)
        advance(app, from: 1, tapping: app.button(labelContaining: L.hookCTA))
        advance(app, from: 2, tapping: continueButton)

        // 3 Q1 main goal: Continue is disabled until a goal is chosen (Screen3MainGoal).
        XCTAssertTrue(waitForOnboardingStep(3, in: app), "Expected onboarding step 3.")
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "Step 3: Continue button not found.")
        XCTAssertFalse(continueButton.isEnabled, "Step 3: Continue must be disabled until a main goal is picked.")
        let goalOption = app.button(labelContaining: L.mainGoalGym)
        XCTAssertTrue(goalOption.waitForExistence(timeout: 10), "Step 3: main-goal option not found.")
        goalOption.tap()
        XCTAssertTrue(poll(timeout: 5) { continueButton.isEnabled }, "Step 3: Continue did not enable after picking a goal.")
        advance(app, from: 3, tapping: continueButton)

        // 4 Q2 app selection: Continue stays disabled with nothing picked (Screen4AppSelection).
        XCTAssertTrue(waitForOnboardingStep(4, in: app), "Expected onboarding step 4.")
        XCTAssertTrue(
            app.button(labelContaining: L.appPickerButton).waitForExistence(timeout: 10),
            "Step 4: 'Choose apps' button not found."
        )
        XCTAssertTrue(continueButton.exists, "Step 4: Continue button not found.")
        XCTAssertFalse(continueButton.isEnabled, "Step 4: Continue must be disabled until apps are picked (spec §7.4).")

        // Back returns to step 3 and the earlier answer survived (flowState is shared).
        let back = app.button(labelContaining: L.backButton)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Step 4: Back button not found.")
        back.tap()
        XCTAssertTrue(waitForOnboardingStep(3, in: app), "Back from step 4 did not return to step 3.")
        settle()
        XCTAssertTrue(
            poll(timeout: 5) { continueButton.isEnabled },
            "Step 3: the goal answer was lost after going Back (Continue is disabled again)."
        )
    }

    // MARK: - Full flow (device only)

    @MainActor
    func test2_CompleteOnboardingEndToEndLandsOnToday() throws {
        try requireFamilyControlsEnvironment()
        // There is no free path (spec §21) and no product to buy in a test run, so this launches
        // with the DEBUG-only paywall skip. Flow1 covers the paywall itself.
        let app = launchApp(skipPaywall: true)
        try requireFreshOnboarding(app)

        // Screens 1-11 and Commitment; the skipped paywall (12) advances itself to priming (13).
        try driveOnboardingToPaywall(app, skippingPaywall: true)
        passNotificationPriming(app)

        // 14 First win: the core loop, once.
        completeFirstWin(app)

        // Landed on Today...
        assertLandedOnToday(app)

        // ...and it sticks: relaunch must NOT restart onboarding.
        app.terminate()
        app.launch()
        assertLandedOnToday(app)
        XCTAssertFalse(
            app.onboardingStep(1).exists,
            "After relaunch the app showed onboarding again -- 'onboarding finished' was not persisted."
        )
    }

    // MARK: - Helpers

    /// Screen 14 (spec §7.14): start the 10-minute focus session, wait it out, finish.
    @MainActor
    private func completeFirstWin(_ app: XCUIApplication) {
        let L = ZANOUILabel.Onboarding.self

        let start = app.button(labelContaining: L.firstWinStart)
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Step 14: '\(L.firstWinStart)' button not found.")
        start.tap()

        // `start()` failing shows an alert (errorMessage) and stays on the intro; success shows the
        // running view.
        let running = app.anyElement(labelContaining: L.firstWinRunning)
        if !running.waitForExistence(timeout: 20) {
            attachHierarchy(of: app, named: "First win did not start")
            XCTFail(
                "Tapped '\(L.firstWinStart)' but the running view ('\(L.firstWinRunning)') never appeared within 20s. "
                + "An error alert here means FocusSessionVerifier.startSession failed."
            )
            return
        }

        // Wait out the real 10-minute timer. Either outcome finishes onboarding.
        let earned = app.anyElement(labelContaining: L.firstWinEarned)
        let notVerified = app.anyElement(labelContaining: L.firstWinNotVerified)
        let finished = poll(timeout: Self.firstWinTimeout, interval: 5) { earned.exists || notVerified.exists }
        XCTAssertTrue(
            finished,
            "The first-win focus session did not finish within \(Int(Self.firstWinTimeout / 60)) minutes."
        )
        attachNote(
            earned.exists
                ? "First win VERIFIED ('\(L.firstWinEarned)' celebration shown)."
                : "First win NOT verified ('\(L.firstWinNotVerified)' shown) -- check FocusSessionVerifier.endSession.",
            named: "First-win outcome"
        )

        // "Done" on the celebration / not-verified screen. A verified win then shows the widget
        // prompt with a second "Done"; a not-verified one finishes straight away.
        let done = app.button(labelContaining: L.firstWinDone)
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Step 14: '\(L.firstWinDone)' button not found after the timer.")
        done.tap()
        settle()
        if app.anyElement(labelContaining: L.widgetPromptHeadline).waitForExistence(timeout: 4) {
            let widgetDone = app.button(labelContaining: L.firstWinDone)
            XCTAssertTrue(widgetDone.waitForExistence(timeout: 10), "Widget prompt: '\(L.firstWinDone)' button not found.")
            widgetDone.tap()
        }
    }

    /// The post-onboarding shell: tab bar with Today selected, and Today's own header rendered.
    /// `ContentView.MainTabView` puts "Today" first and `AppRouter.selectedTab` defaults to it.
    @MainActor
    private func assertLandedOnToday(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 25),
            "No tab bar appeared after finishing onboarding."
        )
        XCTAssertTrue(app.todayTab.waitForExistence(timeout: 10), "No '\(ZANOUILabel.Shell.todayTab)' tab in the tab bar.")
        XCTAssertTrue(app.todayTab.isSelected, "The '\(ZANOUILabel.Shell.todayTab)' tab is not the selected tab after onboarding.")
        // `.firstMatch`: the word "Today" can legitimately appear more than once on screen.
        let todayHeader = app.staticTexts
            .matching(NSPredicate(format: "label == %@", ZANOUILabel.Shell.todayTab))
            .firstMatch
        XCTAssertTrue(
            todayHeader.waitForExistence(timeout: 10),
            "TodayView's header ('\(ZANOUILabel.Shell.todayTab)') did not render."
        )
    }
}
