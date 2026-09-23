// ZANOUITests.swift
// ZANOUITests (target declared in project.yml, type `bundle.ui-testing`, depends on ZANO)
//
// One deliberately minimal smoke test: it proves the UI-test target exists, compiles, is wired to
// the ZANO app as its "Target Application", and that the app can be launched. Real scenarios
// (onboarding -> paywall -> first earned unlock, lock/unlock flows, etc.) are a later phase.
//
// Shape follows Xcode's own "UI Testing Bundle" template (XCTestCase + XCUIApplication, test
// methods `@MainActor` because XCUIApplication is main-actor-isolated under Swift 6 strict
// concurrency). XCTest rather than Swift Testing: Core's unit tests use Swift Testing, but
// XCUIApplication-driven UI tests are still XCTest's home turf and Xcode's UI-test template
// still generates XCTest.
//
// No user-facing strings are asserted on here (CLAUDE.md: user-facing copy lives in
// Core/Sources/Core/Copy). When scenarios arrive, prefer accessibility identifiers over matching
// on rendered copy so tests don't break every time a coach voice is retuned.
//
// UNVERIFIED — written on Windows with no Mac/Xcode to compile or run against. Note FamilyControls,
// DeviceActivity, Core NFC, and HealthKit workouts do not work in the Simulator (CLAUDE.md
// "Build & test"); this only checks that the app process reaches the foreground, not that any of
// those features work.

import XCTest

final class ZANOUITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop at the first failure — a failed launch makes every later step in the test noise.
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToForeground() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "ZANO did not reach the foreground within 15s of launch (state: \(app.state.rawValue))."
        )
    }
}
