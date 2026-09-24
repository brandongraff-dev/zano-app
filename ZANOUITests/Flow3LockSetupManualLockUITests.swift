// Flow3LockSetupManualLockUITests.swift
// ZANOUITests -- scenario 2: create a lock set and start a manual lock (the LockSetup flow).
//
// docs/spec.md §2 (core loop: "Manual button" is one of the lock triggers), §4 v1 ("App picker with
// saved 'lock sets'"), §21 (Free tier: "1 lock set"). Screens under test:
//   * App/ZANO/Features/LockSetup/LockSetupView.swift + AppPickerView.swift -- list, "New Lock Set"
//     editor sheet (name + FamilyActivityPicker; Save is enabled only with a name AND a selection)
//   * App/ZANO/Features/Today/TodayView.swift -- the "Start today's lock" primary button, a plain
//     TAP (`Copy.today.beginLockStandardTitle`; the old 2-second-hold variant was retired by the
//     2026-09-23 design pass) that calls `LockEngineManager.startLock(trigger: .manual)`
//   * App/ZANO/Features/Lock/LockStatusView.swift -- "Hold to unlock in an emergency"
//     (`Copy.lockStatus.emergencyUnlockTitle`, a 2-second hold; CLAUDE.md: every lock keeps a way
//     out; the last step here uses it so the test leaves the device unlocked)
//
// Needs the ONBOARDED shell (tab bar), so run after Flow2 (or onboard by hand). Three tests:
//   test1_  editor Save-gating. No FamilyControls needed (never picks apps), so it can run
//           anywhere the app is onboarded.
//   test2_  create a lock set with real apps. DEVICE ONLY.
//   test3_  start a manual lock, then emergency-unlock out of it. DEVICE ONLY, real shields.
//
// !! test3_ applies a REAL ManagedSettings shield to the apps in the default lock set. If it fails
// between "lock started" and "emergency unlock", those apps stay shielded on the device: open ZANO
// -> Lock and hold "Hold to unlock in an emergency" (always available; whether it costs a streak
// point is NOT settled -- see the footnote comment on `Copy.lockStatus.emergencyUnlockFootnote`).
//
// Free-tier interaction that shapes test2_: onboarding's Plan Reveal already creates one default
// lock set ("Distractions"), and `TierGating.freeLockSetLimit` is 1 with RevenueCat not linked (so
// every user is Free). Creating a SECOND lock set is therefore EXPECTED to fail with
// `LockSetManagerError.freeTierLockSetLimitReached` -> the "Couldn't save" alert. test2_ decides
// its expectation from the pre-state it observes (empty list -> row appears; list not empty ->
// cap alert), which is the spec §21 rule, rather than accepting either outcome. If the tester
// account is ever Pro this test's second branch would need to change.
//
// UNVERIFIED -- see ZANOUIScenarioSupport.swift header. No accessibility identifiers exist yet
// (re-grepped 2026-09-23: zero `accessibilityIdentifier` in the repo), so every lookup here is by
// accessibility label.
// Route to LockSetupView: `SettingsView.verificationSetupSection` has a "Lock sets"
// `SettingsNavRow` (a `NavigationLink`, exposed as a button) that pushes it. `openLockSets` taps the
// Settings tab, scrolls that row into view, and taps it; it still tries the Lock tab second and
// fails with an explicit message (plus the view hierarchy) if neither has the entry, so a future
// move of the row shows up as a clear failure rather than a silent skip.

import XCTest

final class Flow3LockSetupManualLockUITests: ZANOScenarioTestCase {

    private static let testLockSetName = "UITest Lock Set"

    // MARK: - test1: editor Save gating (no FamilyControls)

    @MainActor
    func test1_NewLockSetEditorGatesSaveOnNameAndApps() throws {
        let L = ZANOUILabel.LockSetup.self
        let app = launchApp()
        try requireOnboardedApp(app)
        openLockSets(app)
        openNewLockSetEditor(app)

        // `LockSetEditorSheet.canSave` = has a name AND has a selection.
        let save = app.navigationBars.buttons[L.save]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Editor: '\(L.save)' button not found.")
        XCTAssertFalse(save.isEnabled, "Editor: Save must be disabled with no name and no apps.")

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Editor: name field not found.")
        nameField.tap()
        nameField.typeText(Self.testLockSetName)
        XCTAssertFalse(save.isEnabled, "Editor: Save must stay disabled with a name but no apps chosen.")

        let cancel = app.navigationBars.buttons[L.cancel]
        XCTAssertTrue(cancel.exists, "Editor: '\(L.cancel)' button not found.")
        cancel.tap()
        XCTAssertTrue(
            poll(timeout: 10) { !app.navigationBars[L.newLockSet].exists },
            "Editor sheet did not dismiss after Cancel."
        )
        XCTAssertFalse(
            app.anyElement(labelContaining: Self.testLockSetName).exists,
            "Cancel must not create a lock set."
        )
    }

    // MARK: - test2: create a lock set (device)

    @MainActor
    func test2_CreateLockSetFromLockSetupFlow() throws {
        try requireFamilyControlsEnvironment()
        let L = ZANOUILabel.LockSetup.self
        let app = launchApp()
        try requireOnboardedApp(app)
        openLockSets(app)

        // Decide the expected outcome from the pre-state (spec §21 Free tier: 1 lock set).
        let emptyState = app.anyElement(labelContaining: L.emptyStateTitle)
        XCTAssertTrue(
            poll(timeout: 8) { emptyState.exists || app.cells.count > 0 },
            "Lock Sets screen showed neither the empty state nor any rows."
        )
        let hadLockSets = !emptyState.exists

        openNewLockSetEditor(app)

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Editor: name field not found.")
        nameField.tap()
        nameField.typeText(Self.testLockSetName)

        let opener = app.button(labelContaining: L.appsAndCategories)
        XCTAssertTrue(opener.waitForExistence(timeout: 10), "Editor: '\(L.appsAndCategories)' row not found.")
        try chooseAppsWithFamilyActivityPicker(app, opener: opener)

        let save = app.navigationBars.buttons[L.save]
        XCTAssertTrue(
            poll(timeout: 10) { save.isEnabled },
            "Editor: Save did not enable after entering a name and picking apps (picker selection failed?)."
        )
        save.tap()

        if hadLockSets {
            // Free tier already holds its one lock set -> LockSetManager throws
            // freeTierLockSetLimitReached -> the editor stays open with a "Couldn't save" alert.
            let alert = app.alerts.firstMatch
            XCTAssertTrue(
                alert.waitForExistence(timeout: 10),
                "Expected the free-tier cap alert ('\(L.saveErrorTitle)') when creating a second lock set (spec §21)."
            )
            XCTAssertTrue(
                alert.label.contains(L.saveErrorTitle),
                "Alert appeared but its title was '\(alert.label)', expected '\(L.saveErrorTitle)'."
            )
            alert.buttons[L.ok].tap()
            app.navigationBars.buttons[L.cancel].tap()
            XCTAssertTrue(
                poll(timeout: 10) { !app.navigationBars[L.newLockSet].exists },
                "Editor sheet did not dismiss after Cancel."
            )
            XCTAssertFalse(
                app.anyElement(labelContaining: Self.testLockSetName).exists,
                "A second lock set was created on the Free tier (limit is 1, spec §21)."
            )
        } else {
            XCTAssertTrue(
                poll(timeout: 15) { !app.navigationBars[L.newLockSet].exists },
                "Editor sheet did not dismiss after a successful Save."
            )
            XCTAssertTrue(
                app.anyElement(labelContaining: Self.testLockSetName).waitForExistence(timeout: 10),
                "New lock set '\(Self.testLockSetName)' is not in the list after Save."
            )
        }
    }

    // MARK: - test3: manual lock, then emergency exit (device)

    @MainActor
    func test3_StartManualLockThenEmergencyUnlock() throws {
        try requireFamilyControlsEnvironment()
        let T = ZANOUILabel.Today.self
        let app = launchApp()
        try requireOnboardedApp(app)

        // Start from Today.
        XCTAssertTrue(app.todayTab.waitForExistence(timeout: 10), "No '\(ZANOUILabel.Shell.todayTab)' tab.")
        if !app.todayTab.isSelected { app.todayTab.tap() }

        // TodayView offers "Start today's lock" only with >= 1 active goal, a default lock set, and
        // no active lock. Otherwise the hero says "Finish setup to start locking" and no button shows.
        let beginLock = app.button(labelContaining: T.startLock)
        if !beginLock.waitForExistence(timeout: 20) {
            attachHierarchy(of: app, named: "Today without the begin-lock button")
            XCTFail(
                "'\(T.startLock)' not found on Today. Either a lock is already active (use the in-app "
                + "emergency unlock and rerun) or setup is incomplete (no active goal / no default lock set)."
            )
            return
        }
        XCTAssertTrue(beginLock.isEnabled, "'\(T.startLock)' is disabled.")

        // A plain tap (the button is a non-hold `PrimaryButton` now). Calls
        // LockEngineManager.startLock(trigger: .manual), which throws `authorizationNotGranted`
        // unless Screen Time access is approved.
        beginLock.tap()

        let lockedCard = app.button(labelContaining: T.lockedPrefix)
        if !lockedCard.waitForExistence(timeout: 15) {
            attachHierarchy(of: app, named: "Today after tapping the begin-lock button")
            XCTFail(
                "Tapped '\(T.startLock)' but Today never showed a locked state ('\(T.lockedPrefix) ...'). "
                + "TodayView shows the startLock error as caption text -- 'authorizationNotGranted' means "
                + "Screen Time access is not approved for ZANO on this device."
            )
            return
        }

        // Open the Lock detail. The emergency-unlock path MUST exist on every lock (CLAUDE.md).
        lockedCard.tap()
        let emergency = app.button(labelContaining: ZANOUILabel.LockStatus.emergencyUnlock)
        XCTAssertTrue(
            revealByScrolling(emergency, in: app),
            "Lock detail has no '\(ZANOUILabel.LockStatus.emergencyUnlock)' control while locked -- a lock with no way out (CLAUDE.md)."
        )

        // Use it, so the device is left unlocked. `LockEngineManager.emergencyUnlock`.
        emergency.holdToCommit(for: 62)
        XCTAssertTrue(
            app.anyElement(labelContaining: T.unlocked).waitForExistence(timeout: 20),
            "After the emergency unlock the Lock screen never showed '\(T.unlocked)'."
        )
        XCTAssertFalse(
            emergency.exists,
            "The emergency-unlock control is still showing after unlocking (lock did not end)."
        )
    }

    // MARK: - Navigation helpers

    /// Gets to `LockSetupView` through the Settings tab's "Lock sets" row (`SettingsView.
    /// verificationSetupSection`), falling back to the Lock tab, and fails loudly if neither has it.
    /// `ContentView.MainTabView` is a five-tab `TabView` (Today / Lock / Fuel / Progress / Settings),
    /// which iPhone shows without a "More" tab; a sixth tab would fold Settings into "More" and this
    /// lookup would need updating.
    @MainActor
    private func openLockSets(_ app: XCUIApplication) {
        let title = ZANOUILabel.LockSetup.screenTitle
        for tabName in [ZANOUILabel.Shell.settingsTab, ZANOUILabel.Shell.lockTab] {
            let tab = app.zanoTab(tabName)
            guard tab.exists else { continue }
            tab.tap()
            // Settings is a `ScrollView` of cards; the row sits under the hero but may start below
            // the fold on a small phone or when the Always-Allowed warning is showing above it.
            let entry = app.button(labelContaining: title)
            if entry.waitForExistence(timeout: 4), revealByScrolling(entry, in: app, maxSwipes: 4) {
                entry.tap()
                if app.navigationBars[title].waitForExistence(timeout: 5) { return }
            }
        }
        attachHierarchy(of: app, named: "No route to the Lock Sets screen")
        XCTFail(
            "Could not reach the '\(title)' screen from the Settings or Lock tab. Expected a '\(title)' "
            + "row (SettingsView.verificationSetupSection) -- check the attached hierarchy for a renamed or "
            + "moved row."
        )
    }

    /// Taps "New Lock Set" (toolbar "+" or the empty-state button) and waits for the editor sheet.
    @MainActor
    private func openNewLockSetEditor(_ app: XCUIApplication) {
        let title = ZANOUILabel.LockSetup.newLockSet
        let newButton = app.button(labelContaining: title)
        XCTAssertTrue(newButton.waitForExistence(timeout: 10), "'\(title)' button not found on the Lock Sets screen.")
        newButton.tap()
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 10),
            "The '\(title)' editor sheet did not appear."
        )
    }
}
