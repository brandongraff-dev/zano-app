// ZANOUIScenarioSupport.swift
// ZANOUITests -- shared base class, element lookups, and onboarding driver for the Flow1/2/3
// scenario files next to this one. (ZANOUITests.swift, the launch smoke test, is untouched.)
//
// docs/spec.md §7 (onboarding, screen by screen) and §2 (core loop: lock -> goal -> verified ->
// unlock) are what the scenarios walk. Nothing in this target has been compiled or run: it was
// written on Windows with no Mac, Xcode, Simulator, or device (CLAUDE.md "Current environment
// status"). Every API used is a standard XCTest/XCUITest one, but treat the whole target as
// UNVERIFIED until a first Mac run.
//
// ============================================================================================
// HOW ELEMENTS ARE FOUND -- and why there are no accessibility identifiers here
// ============================================================================================
// As of this writing there is NOT ONE `accessibilityIdentifier` anywhere in the repo's Swift
// sources (App/, Core/, Extensions/, Watch/ -- re-checked by grep at the end of the 2026-09-23
// wiring wave; the only hit is this comment). The smoke test's header says "prefer accessibility
// identifiers over matching on rendered copy"; that is impossible today, and this target must not
// reference identifiers that do not exist. So every lookup below goes through what the real
// screens DO expose:
//   * accessibility LABELS -- SwiftUI derives them from the visible Text of a Button, plus the
//     explicit `.accessibilityLabel(...)` on the onboarding Back button, the hold-to-commit
//     `PrimaryButton`, and the onboarding progress bar ("Step N of 14");
//   * system control types (`sliders`, `tabBars`, `navigationBars`, `alerts`).
// Labels are matched with `CONTAINS`, never `==`, because a `Button` that also holds an
// `Image(systemName:)` can carry the symbol's auto-generated name in its label.
//
// The strings themselves are mirrored in `ZANOUILabel` below (one place to update). This target
// does not import Core (project.yml deliberately gives ZANOUITests no `package: Core`
// dependency), so it cannot read `Copy.*` directly. Where a string is spec-verbatim (§7 quotes,
// e.g. "Continue with limited free") it is stable by product decision; the rest are authored copy
// that WILL drift if retuned -- and it already had: when this file was reviewed against the live
// `Copy` sources on 2026-09-23, ten mirrors were stale (onboarding hook/wake-up/plan/first-win
// buttons, the emergency-unlock title, the Lock Sets strings, and Today's begin-lock button, which
// had also changed from a 2-second hold to a plain tap) and were corrected. Every entry below now
// names the exact `Copy` key (or App-module constant) it was checked against; when a Copy string is
// retuned, a scenario failing with "... button not found" is the symptom to look for here first.
// Cheapest way to end the drift for good: add `Core` as a package dependency of ZANOUITests in
// project.yml and replace `ZANOUILabel` with `Copy.*` (not done: an unbuilt Core link into a test
// bundle is a new, unverifiable build risk). Note the namespace is deliberately NOT called `Copy`:
// this is test-side lookup data, not app copy, and the app-side rule (CLAUDE.md) is that
// user-facing copy lives under `Copy.<area>` in Core.
//
// ============================================================================================
// PRECONDITIONS THE SCENARIOS ASSUME (each is checked at runtime and skipped, not silently faked)
// ============================================================================================
//  1. The app shell is wired: a fresh launch shows `OnboardingContainerView` (progress label
//     "Step 1 of 14"), and a launch after onboarding shows a tab bar with a "Today" tab.
//     `App/ZANO/ContentView.swift` now does this (gates on `AppRouter.hasCompletedOnboarding`,
//     persisted in `UserDefaults.standard`, then hosts a five-tab `TabView`: Today / Lock / Fuel /
//     Progress / Settings). NOT run yet -- if a first Mac run finds neither, `detectLaunchState`
//     reports `.unknown` and the tests fail with an explicit message plus the view hierarchy.
//  2. Physical device with FamilyControls (spec §27, docs/setup/windows-workflow.md: none of it
//     works in the Simulator), the Family Controls (Development) capability, and Screen Time
//     access ALREADY APPROVED for ZANO (approve once by hand: the system authorization prompt
//     needs Face ID / passcode, which XCUITest cannot enter). Device-only tests skip on Simulator.
//  3. Fresh app data for the tests that need onboarding (delete the app or `simctl uninstall`
//     between full runs). There is no in-app reset hook, and the SwiftData store survives
//     relaunch. Default XCTest ordering is alphabetical by class then method, which the
//     `Flow1/Flow2/Flow3` and `test1_/test2_` prefixes rely on: paywall test (fresh, does not
//     finish onboarding) -> onboarding e2e (fresh, finishes onboarding) -> lock setup (needs
//     onboarded). Out-of-order or randomized runs skip rather than fail.
//  4. Device Auto-Lock off: the first win is a real 10-minute focus timer with no skip.
//  5. Free tier throughout (RevenueCat is not linked, so `TierGating` treats everyone as Free).

import XCTest

// MARK: - Lookup strings (mirrors of Core/Sources/Core/Copy -- see header)

/// Test-side lookup strings. NOT app copy. Each entry names the `Copy` key it mirrors.
enum ZANOUILabel {

    /// `OnboardingFlowState.lastScreen` / docs/spec.md §7 (14 screens).
    static let onboardingScreenCount = 14

    enum Onboarding {
        /// Copy.onboarding.hookCTA. Spec §7.1 quotes it as "I'm ready." WITH a trailing period, but
        /// the shipped constant has none -- and lookups are `CONTAINS`, so the period must not be here.
        static let hookCTA = "I'm ready"
        /// Copy.common.continueButtonLabel.
        static let continueButton = "Continue"
        /// MainGoal.gymConsistency.displayLabel -- spec §7.3 verbatim.
        static let mainGoalGym = "Get consistent at the gym"
        /// Copy.onboarding.q2PickerButtonLabel.
        static let appPickerButton = "Choose apps"
        /// FallOffPattern.evenings.displayLabel -- spec §7.7 verbatim.
        static let fallOffEvenings = "Evenings"
        /// CoachVoice.toughLove.displayName -- spec §5.13 / §7.8 verbatim.
        static let coachVoiceToughLove = "Tough Love"
        /// Copy.onboarding.wakeUpContinueButton.
        static let wakeUpContinue = "See my plan"
        /// Copy.onboarding.planContinueButton (the same word as `continueButton`).
        static let planContinue = "Continue"
        /// Copy.onboarding.commitHoldButtonLabel -- spec §7.11 "Hold to commit".
        static let holdToCommit = "Hold to commit"
        /// Copy.onboarding.permissionAllowButton.
        static let allowNotifications = "Allow notifications"
        /// Copy.onboarding.backButtonAccessibilityLabel.
        static let backButton = "Back"
        /// Copy.onboarding.firstWinStartButton.
        static let firstWinStart = "Start focus session"
        /// Copy.onboarding.firstWinRunningHeadline.
        static let firstWinRunning = "Stay locked in"
        /// Copy.onboarding.firstWinCelebrationTitle (session verified).
        static let firstWinEarned = "Earned."
        /// Copy.onboarding.firstWinNotVerifiedTitle (session not verified).
        static let firstWinNotVerified = "Not this time"
        /// Copy.onboarding.firstWinDoneButton (appears on the celebration/exit screen AND on the
        /// widget prompt).
        static let firstWinDone = "Done"
        /// Copy.onboarding.firstWinWidgetPromptHeadline.
        static let widgetPromptHeadline = "Add ZANO to your Home Screen"
    }

    enum Paywall {
        /// Copy.paywall.headline -- spec §16 P5 verbatim.
        static let headline = "Earn your phone back"
        /// Copy.paywall.continueWithLimitedFreeLink -- spec §7.13 / §21 verbatim.
        static let continueWithLimitedFree = "Continue with limited free"
        /// Copy.paywall.restorePurchasesButtonLabel (spec §24: "restore purchases visible").
        static let restorePurchases = "Restore purchases"
        /// Copy.paywall.retryButtonLabel (shown only when offerings failed to load).
        static let retryOfferings = "Try again"
        /// Copy.paywall.annualPlanTitle (shown only when offerings loaded).
        static let annualPlan = "Annual"
    }

    /// `ContentView.MainTabView` builds each tab as `Label(Copy.<area>.screenTitle, systemImage:)`,
    /// so a tab button's accessibility label equals the screen's own title.
    enum Shell {
        /// Copy.today.screenTitle.
        static let todayTab = "Today"
        /// Copy.lockStatus.screenTitle.
        static let lockTab = "Lock"
        /// Copy.settings.screenTitle.
        static let settingsTab = "Settings"
    }

    enum Today {
        /// `Copy.today.beginLockStandardTitle` -- declared in an `extension Copy.today` at the bottom
        /// of `App/ZANO/Features/Today/TodayView.swift` (App module, not Core), as a plain-TAP
        /// `PrimaryButton`. The 2026-09-23 design pass replaced the old hold variant
        /// (`Copy.today.beginLockTitle` = "Hold to start today's lock", still in `TodayCopy.swift`
        /// but no longer used by `TodayView`). Tap it; do not hold it.
        static let startLock = "Start today's lock"
        /// Prefix of Copy.today.lockStatusLine(isLocked: true, ...): "Locked · N goal(s) left".
        /// `TodayView`'s hero card is one `Button` whose accessibility label starts with it.
        /// Case-sensitive on purpose so it does NOT match "Unlocked".
        static let lockedPrefix = "Locked \u{00B7}"
        /// Copy.today.lockStatusLine(isLocked: false, ...) / Copy.lockStatus.unlockedHeadline.
        static let unlocked = "Unlocked"
    }

    enum LockStatus {
        /// Copy.lockStatus.emergencyUnlockTitle -- CLAUDE.md: every lock keeps a way out. A
        /// `EmergencyUnlockControl` (60-second hold on Core's `EmergencyUnlock`).
        static let emergencyUnlock = "Hold to unlock in an emergency"
    }

    enum LockSetup {
        /// Copy.lockSetup.screenTitle (also the label of the Settings row that opens the screen:
        /// `SettingsView.verificationSetupSection`).
        static let screenTitle = "Lock sets"
        /// Copy.lockSetup.newLockSetButtonLabel == Copy.lockSetup.newLockSetTitle.
        static let newLockSet = "New lock set"
        /// Copy.lockSetup.emptyStateTitle.
        static let emptyStateTitle = "No lock sets yet"
        /// Copy.lockSetup.selectAppsButtonLabel.
        static let appsAndCategories = "Apps & categories"
        /// Copy.lockSetup.saveButtonLabel.
        static let save = "Save"
        /// Copy.common.cancel.
        static let cancel = "Cancel"
        /// Copy.common.ok.
        static let ok = "OK"
        /// Copy.lockSetup.saveErrorTitle.
        static let saveErrorTitle = "Couldn't save"
        /// Copy.onboarding.lockSetName -- the default set Plan Reveal creates.
        static let onboardingLockSetName = "Distractions"
    }
}

// MARK: - Launch state

enum ZANOLaunchState {
    /// `OnboardingContainerView` is showing ("Step N of 14" progress label present).
    case onboarding
    /// A tab bar is showing (onboarding already completed).
    case main
    /// Neither appeared in time -- almost certainly the app shell is not wired yet.
    case unknown
}

// MARK: - XCUIApplication / XCUIElement lookups

extension XCUIApplication {

    /// Any element (any type) whose accessibility label contains `text` (case-sensitive).
    func anyElement(labelContaining text: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    /// A button whose accessibility label contains `text` (case-sensitive).
    func button(labelContaining text: String) -> XCUIElement {
        buttons
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    /// The onboarding chrome's progress element for `step`. `OnboardingScaffold` gives its
    /// progress bar `.accessibilityLabel(Copy.onboarding.progressAccessibilityLabel(screen:total:))`
    /// = "Step N of 14"; type-agnostic because the element has no button/text trait.
    func onboardingStep(_ step: Int) -> XCUIElement {
        let label = "Step \(step) of \(ZANOUILabel.onboardingScreenCount)"
        return descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// ZANO's floating tab bar (`ZanoTabBar`, a custom view, so not an `XCUIElement` of type tabBar).
    var zanoTabBar: XCUIElement { otherElements["zano.tabBar"] }
    func zanoTab(_ title: String) -> XCUIElement { zanoTabBar.buttons[title] }

    var todayTab: XCUIElement { zanoTab(ZANOUILabel.Shell.todayTab) }
}

extension XCUIElement {

    /// Presses and holds the element's centre. For `PrimaryButton(style: .holdToCommit)`, which is
    /// a `DragGesture(minimumDistance: 0)` rather than a real tap target: a plain `tap()` is
    /// touch-down + touch-up in one instant, which starts the hold and immediately cancels it.
    /// `Theme.Motion.holdToCommitDuration` is 2.0s; 2.6s leaves headroom for the 50ms tick loop.
    /// Uses a coordinate so it still completes if the element leaves the tree the moment the
    /// hold fires (the onboarding screen swaps out on commit).
    func holdToCommit(for seconds: TimeInterval = 2.6) {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: seconds)
    }
}

// MARK: - Base class

/// Base class for the scenario files. Holds no tests itself. Follows the shape of Xcode's UI-test
/// template (and `ZANOUITests.swift`): non-isolated class, `@MainActor` on the methods that touch
/// `XCUIApplication`, no stored `XCUIApplication` (Swift 6 strict concurrency).
class ZANOScenarioTestCase: XCTestCase {

    override func setUpWithError() throws {
        // A failed step makes every later step noise (same choice as ZANOUITests.swift).
        continueAfterFailure = false
    }

    // MARK: Launch / state

    /// Launches ZANO with English pinned so the label lookups in `ZANOUILabel` match.
    @MainActor
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func detectLaunchState(_ app: XCUIApplication, timeout: TimeInterval = 25) -> ZANOLaunchState {
        var state = ZANOLaunchState.unknown
        _ = poll(timeout: timeout) {
            if app.onboardingStep(1).exists {
                state = .onboarding
                return true
            }
            if app.zanoTabBar.exists {
                state = .main
                return true
            }
            return false
        }
        return state
    }

    /// The scenario needs to start on onboarding screen 1. Skips if the app is already onboarded
    /// (no in-app reset exists -- see header precondition 3); fails if the shell is not wired.
    @MainActor
    func requireFreshOnboarding(_ app: XCUIApplication) throws {
        switch detectLaunchState(app) {
        case .onboarding:
            return
        case .main:
            throw XCTSkip(
                "App is already onboarded (tab bar showing). This scenario needs a fresh install: "
                + "delete ZANO from the device (or `xcrun simctl uninstall booted com.zano.app`) and rerun."
            )
        case .unknown:
            attachHierarchy(of: app, named: "Launch hierarchy (no onboarding, no tab bar)")
            XCTFail(
                "Neither the onboarding flow ('Step 1 of \(ZANOUILabel.onboardingScreenCount)') nor a tab bar "
                + "appeared within 25s of launch. ContentView is expected to host OnboardingContainerView "
                + "until AppRouter.hasCompletedOnboarding, then a TabView -- check the attached hierarchy "
                + "(a launch crash, a system alert, or a renamed progress label would all land here)."
            )
        }
    }

    /// The scenario needs the post-onboarding tab UI.
    @MainActor
    func requireOnboardedApp(_ app: XCUIApplication) throws {
        switch detectLaunchState(app) {
        case .main:
            return
        case .onboarding:
            throw XCTSkip(
                "App is still on onboarding. Run Flow2OnboardingCompletionUITests (fresh install) first, "
                + "or complete onboarding by hand, then rerun this scenario."
            )
        case .unknown:
            attachHierarchy(of: app, named: "Launch hierarchy (no onboarding, no tab bar)")
            XCTFail("Neither onboarding nor a tab bar appeared within 25s of launch -- see the attached hierarchy.")
        }
    }

    /// FamilyControls (Screen Time authorization, `FamilyActivityPicker`, shields) does not work in
    /// the Simulator -- docs/spec.md §27, docs/setup/windows-workflow.md. Anything that must pick
    /// apps or start a real lock is device-only.
    func requireFamilyControlsEnvironment() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip(
            "Needs a physical device: FamilyControls (Screen Time authorization, FamilyActivityPicker, "
            + "ManagedSettings shields) does not work in the iOS Simulator (docs/spec.md §27). Use a device "
            + "with the Family Controls (Development) capability and Screen Time access already approved for ZANO."
        )
        #endif
    }

    // MARK: Waiting / diagnostics

    /// Polls `condition` on the main run loop until it is true or `timeout` elapses.
    @MainActor
    func poll(timeout: TimeInterval, interval: TimeInterval = 0.25, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
        return condition()
    }

    /// Lets a screen transition finish (`OnboardingContainerView` slides screens for ~0.35s) so a
    /// lookup right after `waitForOnboardingStep` cannot grab the outgoing screen's button.
    @MainActor
    func settle(_ seconds: TimeInterval = 0.5) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    @MainActor
    func waitForOnboardingStep(_ step: Int, in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        app.onboardingStep(step).waitForExistence(timeout: timeout)
    }

    /// Scrolls the frontmost scroll view up until `element` exists and is hittable. The paywall is
    /// a `ScrollView`; on small phones its "Continue with limited free" link starts below the fold.
    @MainActor
    func revealByScrolling(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    @MainActor
    func attachHierarchy(of app: XCUIApplication, named name: String) {
        attachNote(app.debugDescription, named: name)
    }

    func attachNote(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Onboarding driver (screens 1-12)

    /// Taps `button` on onboarding screen `step` and waits for screen `step + 1`.
    /// Waits for the button to be ENABLED first: Continue on screens 3, 4 and 7 is disabled until
    /// the user answers, and XCUITest will happily tap a disabled button as a no-op.
    @MainActor
    func advance(
        _ app: XCUIApplication,
        from step: Int,
        tapping button: XCUIElement,
        timeout: TimeInterval = 15
    ) {
        XCTAssertTrue(
            waitForOnboardingStep(step, in: app, timeout: timeout),
            "Expected to be on onboarding step \(step) before advancing."
        )
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Step \(step): button to advance not found.")
        XCTAssertTrue(poll(timeout: timeout) { button.isEnabled }, "Step \(step): button stayed disabled.")
        button.tap()
        XCTAssertTrue(
            waitForOnboardingStep(step + 1, in: app, timeout: timeout),
            "Tapped the button on step \(step) but never reached step \(step + 1)."
        )
        settle()
    }

    /// Drives a fresh install from onboarding screen 1 to the paywall (screen 13, docs/spec.md §7).
    /// Device-only: screen 4 needs a real FamilyControls selection to enable Continue.
    /// Leaves the app on screen 13.
    @MainActor
    func driveOnboardingToPaywall(_ app: XCUIApplication) throws {
        let L = ZANOUILabel.Onboarding.self
        let continueButton = app.button(labelContaining: L.continueButton)

        // 1 Hook -> 2 Social proof -> 3 Q1 main goal
        advance(app, from: 1, tapping: app.button(labelContaining: L.hookCTA))
        advance(app, from: 2, tapping: continueButton)

        // 3 Q1: Continue is gated on picking a goal.
        XCTAssertTrue(waitForOnboardingStep(3, in: app), "Expected onboarding step 3.")
        let goalOption = app.button(labelContaining: L.mainGoalGym)
        XCTAssertTrue(goalOption.waitForExistence(timeout: 10), "Step 3: main-goal option not found.")
        goalOption.tap()
        advance(app, from: 3, tapping: continueButton)

        // 4 Q2: FamilyActivityPicker (device only). Continue is gated on a non-empty selection.
        XCTAssertTrue(waitForOnboardingStep(4, in: app), "Expected onboarding step 4.")
        let pickerOpener = app.button(labelContaining: L.appPickerButton)
        XCTAssertTrue(pickerOpener.waitForExistence(timeout: 10), "Step 4: 'Choose apps' button not found.")
        try chooseAppsWithFamilyActivityPicker(app, opener: pickerOpener)
        advance(app, from: 4, tapping: continueButton)

        // 5 Q3: phone-time slider. Any value 1...10 is valid; move it off the default (5h) so the
        // wake-up math on screen 9 is exercised with a non-default value.
        XCTAssertTrue(waitForOnboardingStep(5, in: app), "Expected onboarding step 5.")
        let slider = app.sliders.firstMatch
        if slider.waitForExistence(timeout: 5) {
            slider.adjust(toNormalizedSliderPosition: 0.6)
        }
        advance(app, from: 5, tapping: continueButton)

        // 6 Q4: workouts/week steppers. Left at their defaults (0 current, 3 target) on purpose: how
        // SwiftUI's `Stepper` surfaces to XCUITest is not something this target can check without a
        // Mac, and the defaults are valid answers.
        advance(app, from: 6, tapping: continueButton)

        // 7 Q5: Continue is gated on picking a fall-off pattern.
        XCTAssertTrue(waitForOnboardingStep(7, in: app), "Expected onboarding step 7.")
        let fallOff = app.button(labelContaining: L.fallOffEvenings)
        XCTAssertTrue(fallOff.waitForExistence(timeout: 10), "Step 7: fall-off option not found.")
        fallOff.tap()
        advance(app, from: 7, tapping: continueButton)

        // 8 Q6: coach voice (defaults to Hype; pick a different one so selection is exercised).
        XCTAssertTrue(waitForOnboardingStep(8, in: app), "Expected onboarding step 8.")
        let voice = app.button(labelContaining: L.coachVoiceToughLove)
        XCTAssertTrue(voice.waitForExistence(timeout: 10), "Step 8: coach-voice option not found.")
        voice.tap()
        advance(app, from: 8, tapping: continueButton)

        // 9 Wake-up moment -> 10 Plan reveal (creates User + Goal + default LockSet)
        advance(app, from: 9, tapping: app.button(labelContaining: L.wakeUpContinue))
        advance(app, from: 10, tapping: app.button(labelContaining: L.planContinue))

        // 11 Commitment: 2-second hold, not a tap.
        XCTAssertTrue(waitForOnboardingStep(11, in: app), "Expected onboarding step 11.")
        let commit = app.button(labelContaining: L.holdToCommit)
        XCTAssertTrue(commit.waitForExistence(timeout: 10), "Step 11: 'Hold to commit' button not found.")
        commit.holdToCommit()
        XCTAssertTrue(waitForOnboardingStep(12, in: app), "Held 'Hold to commit' but never reached step 12.")
        settle()

        // 12 Permission priming. Advances whether the system prompt is allowed, denied, or was
        // already answered on a previous install, so handle the prompt if it shows and move on.
        let allow = app.button(labelContaining: L.allowNotifications)
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "Step 12: 'Allow notifications' button not found.")
        allow.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAlert = springboard.alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 6) {
            let systemAllow = systemAlert.buttons["Allow"]
            if systemAllow.exists { systemAllow.tap() }
        }
        XCTAssertTrue(waitForOnboardingStep(13, in: app, timeout: 20), "Never reached the paywall (step 13).")
        settle()
    }

    /// Opens the system `FamilyActivityPicker` from `opener`, picks the first thing it offers, and
    /// confirms with Done. DEVICE ONLY -- callers must have run `requireFamilyControlsEnvironment()`.
    ///
    /// UNVERIFIED and the most speculative code in this target: the picker is a system
    /// (out-of-process) view whose accessibility tree could not be inspected from Windows. It
    /// assumes (a) its elements appear under the host app in XCUITest like other system remote
    /// views (PHPicker, Contacts), (b) it has a "Done" button, and (c) rows/checkboxes are cells or
    /// buttons. The picker hierarchy is attached to the test result every time so the selectors
    /// can be fixed from a real run. The oracle that the pick worked is NOT here -- it is the
    /// caller's Continue/Save button becoming enabled (`flowState.selectedApps` non-empty).
    @MainActor
    func chooseAppsWithFamilyActivityPicker(_ app: XCUIApplication, opener: XCUIElement) throws {
        opener.tap()

        enum Outcome { case picker, zanoAlert, systemAlert, timeout }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let done = app.buttons["Done"]
        var outcome = Outcome.timeout
        _ = poll(timeout: 15) {
            if done.exists { outcome = .picker; return true }
            if app.alerts.firstMatch.exists { outcome = .zanoAlert; return true }
            if springboard.alerts.firstMatch.exists { outcome = .systemAlert; return true }
            return false
        }

        switch outcome {
        case .picker:
            break
        case .zanoAlert:
            attachHierarchy(of: app, named: "ZANO alert after tapping the app picker")
            XCTFail(
                "ZANO showed an alert instead of the picker -- Screen Time authorization was not granted. "
                + "Approve Screen Time access for ZANO by hand once, then rerun."
            )
            return
        case .systemAlert:
            attachHierarchy(of: springboard, named: "SpringBoard alert during Screen Time authorization")
            XCTFail(
                "A system prompt appeared while requesting Screen Time authorization. It needs Face ID or "
                + "the device passcode, which XCUITest cannot enter. Approve access by hand once, then rerun."
            )
            return
        case .timeout:
            attachHierarchy(of: app, named: "Hierarchy 15s after tapping the app picker (no 'Done' button found)")
            XCTFail(
                "The FamilyActivityPicker never showed a 'Done' button within 15s. Either its elements are "
                + "not exposed to XCUITest or its button is not called 'Done' -- inspect the attached hierarchy."
            )
            return
        }

        attachHierarchy(of: app, named: "FamilyActivityPicker hierarchy (use this to fix selectors)")

        // Prefer a category checkbox by common category name; fall back to the first list cell.
        let categoryNames = ["social", "games", "entertainment", "productivity", "creativity"]
        let predicate = NSPredicate(
            format: categoryNames.map { _ in "label CONTAINS[c] %@" }.joined(separator: " OR "),
            argumentArray: categoryNames
        )
        let categoryButton = app.buttons.matching(predicate).firstMatch
        if categoryButton.waitForExistence(timeout: 5) {
            categoryButton.tap()
        } else if app.cells.firstMatch.waitForExistence(timeout: 5) {
            app.cells.firstMatch.tap()
        } else {
            XCTFail("FamilyActivityPicker is open but no category button or cell was found -- see attached hierarchy.")
            return
        }

        done.tap()
        settle()
    }
}
