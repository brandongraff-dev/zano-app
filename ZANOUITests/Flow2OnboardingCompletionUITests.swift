// Flow2OnboardingCompletionUITests.swift
// ZANOUITests -- scenario 1: complete onboarding end to end and land on the Today tab.
//
// docs/spec.md §7 (7 steps since the short flow of 2026-10-02: hook -> main goal -> your why -> apps
// -> plan + hold to commit -> paywall -> first win) and §2 (core loop). Step 7 IS the core loop run
// once inside onboarding: lock -> 2-minute focus goal -> verified -> unlock + streak Day 1
// (spec §7.14, §8 rule 11).
//
// Two tests, split by what they need:
//   test1_  steps 1-4 only, NO FamilyControls. Runs on the Simulator. Checks the step chain, the
//           Continue gates (step 2 needs a goal, step 4 needs picked apps) and the Back button.
//   test2_  the whole flow through the first win to Today. DEVICE ONLY, ~4 minutes. Launched with
//           `-ZANOSkipPaywall YES` (DEBUG only), since a test cannot buy the hard paywall's trial.
//
// Both need a fresh install (there is no in-app reset hook) and the app shell that hosts
// `OnboardingContainerView` then a tab UI (`ContentView`, wired) -- see ZANOUIScenarioSupport.swift
// preconditions. test1_ leaves the install un-onboarded (it never gets past step 4), so test2_ can
// follow it.
//
// The first win is a real 2-minute `FocusSessionVerifier` session. Its exits while running are a
// 60-second emergency hold (when a real `LockSession` started) or "Do it later" (when none did).
// Waiting the timer out is the honest end-to-end path. Start also asks for notification permission
// once (the old priming screen, folded in); the system prompt is answered if it shows. Whether the
// session comes out VERIFIED ("Earned." + streak + widget prompt) or NOT verified ("Not this time")
// depends on `FocusSessionVerifier`; both finish onboarding, so the test accepts either.
//
// "Completing onboarding" is asserted three ways: the tab bar appears with Today selected, the
// Today screen's own header renders, and a terminate + relaunch lands on Today again instead of
// restarting onboarding (i.e. the "onboarding finished" state persists).
//
// UNVERIFIED -- see ZANOUIScenarioSupport.swift header. No accessibility identifiers exist yet.

import XCTest

final class Flow2OnboardingCompletionUITests: ZANOScenarioTestCase {

    /// 2-minute focus timer + notification prompt + start/finish overhead + slack.
    private static let firstWinTimeout: TimeInterval = 5 * 60

    // MARK: - Steps 1-4 (Simulator-safe)

    @MainActor
    func test1_EarlyScreensAdvanceAndGateContinue() throws {
        let app = launchApp()
        try requireFreshOnboarding(app)
        let L = ZANOUILabel.Onboarding.self
        let S = ZANOUILabel.Step.self
        let continueButton = app.button(labelContaining: L.continueButton)

        // 1 Hook -> 2 Main goal
        advance(app, from: S.hook, tapping: app.button(labelContaining: L.hookCTA))

        // 2 Main goal: Continue is disabled until a goal is chosen (Screen3MainGoal).
        XCTAssertTrue(waitForOnboardingStep(S.mainGoal, in: app), "Expected onboarding step \(S.mainGoal).")
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "Step \(S.mainGoal): Continue button not found.")
        XCTAssertFalse(continueButton.isEnabled, "Step \(S.mainGoal): Continue must be disabled until a main goal is picked.")
        let goalOption = app.button(labelContaining: L.mainGoalGym)
        XCTAssertTrue(goalOption.waitForExistence(timeout: 10), "Step \(S.mainGoal): main-goal option not found.")
        goalOption.tap()
        XCTAssertTrue(poll(timeout: 5) { continueButton.isEnabled }, "Step \(S.mainGoal): Continue did not enable after picking a goal.")
        advance(app, from: S.mainGoal, tapping: continueButton)

        // 3 Your why: never gated.
        advance(app, from: S.yourWhy, tapping: continueButton)

        // 4 Apps: Continue stays disabled with nothing picked (Screen4AppSelection).
        XCTAssertTrue(waitForOnboardingStep(S.appSelection, in: app), "Expected onboarding step \(S.appSelection).")
        XCTAssertTrue(
            app.button(labelContaining: L.appPickerButton).waitForExistence(timeout: 10),
            "Step \(S.appSelection): 'Choose apps' button not found."
        )
        XCTAssertTrue(continueButton.exists, "Step \(S.appSelection): Continue button not found.")
        XCTAssertFalse(continueButton.isEnabled, "Step \(S.appSelection): Continue must be disabled until apps are picked (spec §7.4).")

        // Back twice returns to step 2 and the earlier answer survived (flowState is shared).
        let back = app.button(labelContaining: L.backButton)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Step \(S.appSelection): Back button not found.")
        back.tap()
        XCTAssertTrue(waitForOnboardingStep(S.yourWhy, in: app), "Back from step \(S.appSelection) did not return to step \(S.yourWhy).")
        settle()
        back.tap()
        XCTAssertTrue(waitForOnboardingStep(S.mainGoal, in: app), "Back from step \(S.yourWhy) did not return to step \(S.mainGoal).")
        settle()
        XCTAssertTrue(
            poll(timeout: 5) { continueButton.isEnabled },
            "Step \(S.mainGoal): the goal answer was lost after going Back (Continue is disabled again)."
        )
    }

    // MARK: - Full flow (device only)

    @MainActor
    func test2_CompleteOnboardingEndToEndLandsOnToday() throws {
        try requireFamilyControlsEnvironment()
        let app = launchApp(skipPaywall: true)
        try requireFreshOnboarding(app)

        // Steps 1-5; the DEBUG-only paywall skip carries the flow straight on to step 7.
        try driveOnboardingToPaywall(app, expectPaywall: false)

        // 7 First win: the core loop, once.
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

    /// Step 7 (spec §7.14): start the focus session, answer the notification prompt if it shows,
    /// wait the session out, finish.
    @MainActor
    private func completeFirstWin(_ app: XCUIApplication) {
        let L = ZANOUILabel.Onboarding.self

        let start = app.button(labelContaining: L.firstWinStart)
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Step 7: '\(L.firstWinStart)' button not found.")
        start.tap()

        // Start asks for notification permission once, while it is undetermined.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAlert = springboard.alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 6) {
            let systemAllow = systemAlert.buttons["Allow"]
            if systemAllow.exists { systemAllow.tap() }
        }

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

        // Wait out the real 2-minute timer. Either outcome finishes onboarding.
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
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Step 7: '\(L.firstWinDone)' button not found after the timer.")
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
            app.zanoTabBar.waitForExistence(timeout: 25),
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
