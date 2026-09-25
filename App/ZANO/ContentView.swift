// ContentView.swift
// App / ZANO
//
// The app's root view (replaces the Session-0 placeholder). Everything that has to sit above the
// individual screens lives here:
//
//   1. Onboarding gate — `OnboardingContainerView` until `AppRouter.hasCompletedOnboarding`, then
//      the five-tab UI. The container already exposes the completion signal
//      (`OnboardingContainerView.onFinished`, fired once by `Screen14FirstWin`), so no hook had to
//      be added to it.
//   2. Tabs — Today / Lock / Fuel / Progress / Settings (docs/spec.md §15). Titles reuse each
//      screen's existing `Copy.<area>.screenTitle`; no new copy. Today's `onOpenFuel` hook is wired
//      to the Fuel tab here (see `MainTabView`).
//   3. Alarm ringing — a full-screen cover for `AlarmRingingView`, presented whenever
//      `SunriseAlarmManager.shared.isRinging` is true. That is the presentation assumption
//      `AlarmRingingView`'s own header asks the app shell to fulfil (docs/spec.md §5.10).
//   4. Unlock celebration — a full-screen cover for `UnlockCelebrationView` driven by
//      `LockEngineManager.lastUnlockedSessionID` (docs/spec.md §16 P3). Held back while the alarm
//      is ringing (one full-screen presentation at a time; the alarm always wins) and shown once it
//      clears. See `AppRouter.handleUnlock` for when it is deliberately *not* shown.
//   5. Foreground work — while the scene is active, keeps checking whether an alarm is due, since
//      `isRinging` is only ever turned on by `SunriseAlarmManager.beginRingingIfDue`.
//
// Deep links (`.onOpenURL`, notification taps) are received in `ZANOApp` and routed through
// `AppRouter`; this view only reflects `router.selectedTab`.
//
// ONE THING TO KNOW ABOUT NAMES: `ProgressView` below is *this app's* Progress screen
// (`Features/Progress/ProgressView.swift`), not SwiftUI's spinner — a module-local type shadows the
// imported one. If that screen is ever renamed, this file's `ProgressView()` would silently start
// compiling as the SwiftUI spinner instead of failing. Update the one line in `MainTabView` when
// it is renamed.

import SwiftUI
import SwiftData
import Core

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Hard paywall (spec §21): blocks the app when a trial/subscription has definitively lapsed.
    private let entitlement = EntitlementGate.shared

    var body: some View {
        @Bindable var router = router
        // Read here (in `body`) rather than inside a `Binding` getter so the view is guaranteed to
        // re-render when the alarm starts/stops ringing.
        let isAlarmRinging = router.isAlarmRingingPresented

        Group {
            if router.hasCompletedOnboarding && entitlement.isBlocking {
                // EntitlementGate releases any active lock before this shows, but best-effort; if a
                // lock is still on, the emergency hold sits above the paywall (spec §21: a billing
                // state never traps anyone). Draws nothing without an active lock.
                PaywallView(flowState: OnboardingFlowState(), context: .lapsed)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        PaywallLockEscape()
                    }
            } else if router.hasCompletedOnboarding {
                MainTabView(selection: $router.selectedTab, isAlarmRinging: isAlarmRinging)
            } else {
                OnboardingContainerView(onFinished: { router.completeOnboarding() })
            }
        }
        .preferredColorScheme(.dark)
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: router.hasCompletedOnboarding)
        // Presented purely from `isRinging`: the setter ignores SwiftUI's own dismissal attempts
        // because the only legitimate way out is `SunriseAlarmManager` clearing `isRinging`
        // (a verified dismiss, the one snooze, or the 60-second escape hatch), which
        // `AlarmRingingView` itself already reacts to by dismissing. Presented over onboarding too —
        // a ringing alarm outranks everything.
        .fullScreenCover(isPresented: Binding(get: { isAlarmRinging }, set: { _ in })) {
            AlarmRingingView()
                .preferredColorScheme(.dark)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await runForegroundChecks()
        }
        .onChange(of: LockEngineManager.shared.lastUnlockedSessionID) { _, sessionID in
            guard let sessionID else { return }
            router.handleUnlock(sessionID: sessionID)
        }
        // Tag-tap confirmations ("+25 g protein logged") over every screen (Wave 1B).
        .zanoTagTapToast()
    }

    // MARK: - Foreground checks

    /// Runs while the scene is `.active` (`.task(id: scenePhase)` cancels it on any phase change).
    ///
    /// One catch-up on entry, then a light poll. The poll is what makes the alarm show when the app
    /// is *already* foregrounded as the alarm fires — a scene-phase change never happens in that
    /// case (an AlarmKit "stop" button that opens the app, or a fallback-tier notification landing
    /// while the app is open). `beginAlarmIfDue` reads one small `UserDefaults` blob and returns
    /// immediately when nothing is scheduled, so 5 seconds is cheap.
    ///
    /// TODO(Core owner): `SunriseAlarmManager.ensureScheduledIfNeeded()` and
    /// `BedtimeGateManager.evaluateOnForeground()` are documented as belonging in this same hook but
    /// are deliberately NOT called here. `SunriseAlarmManager.Settings.enabled` defaults to `true`
    /// and nothing public says whether the person ever configured it, so calling either on every
    /// foreground would schedule a 06:30 alarm and auto-arm a bedtime lock for people who never
    /// opted in (spec §5.10 frames both as opt-in). Once Core exposes a "has been configured"
    /// signal (or defaults `enabled` to `false`), add both calls right here.
    private func runForegroundChecks() async {
        // Turn any lock the monitor started while the app was closed into a real session.
        await LockScheduler.shared.reconcile()
        // First foreground after onboarding: make the plan's "locks each morning until your goals
        // are done" real by saving that schedule for the default lock set (once, never overwriting
        // a schedule the user set).
        if router.hasCompletedOnboarding,
           !UserDefaults.standard.bool(forKey: "zano.morningScheduleCreated.v1"),
           let lockSetID = LockEngineSharedState.defaultLockSetID {
            if LockScheduler.shared.schedule(for: lockSetID) == nil {
                try? LockScheduler.shared.save(.morningDefault(lockSetID: lockSetID))
            }
            UserDefaults.standard.set(true, forKey: "zano.morningScheduleCreated.v1")
        }
        await entitlement.refresh()
        await router.beginAlarmIfDue()
        await router.reconcileAlarmIfNeeded()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await router.beginAlarmIfDue()
        }
    }
}

// MARK: - Tabs

/// The five-tab shell. Split out of `ContentView` so the unlock-celebration cover lives on the tab
/// UI only — it can never present over onboarding, which runs its own first-win celebration.
private struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Query private var lockSessions: [LockSession]
    @Binding var selection: AppTab
    /// Today's "Pick your goals" / "Finish setup" opens the goals editor as a sheet.
    @State private var showGoalsEditor = false
    /// Passed down (rather than re-read) so this view re-renders exactly when the parent's
    /// `isAlarmRingingPresented` changes.
    let isAlarmRinging: Bool

    var body: some View {
        // Captured as plain locals (rather than read through `self.router` inside the escaping
        // closures below) so those closures hold the router object itself and never touch an
        // `@Environment` value after `body` has finished evaluating. (Named `appRouter`, not
        // `router`, so no local shadows the property of the same name.)
        let appRouter = router
        let celebration = appRouter.unlockCelebration

        TabView(selection: $selection) {
            // `TodayView` owns its `NavigationStack` (it pushes `LockStatusView` itself), so it is
            // the one tab not wrapped here. `onOpenFuel` is the tab-switch hook its header asks the
            // shell to inject: without it, the "log the rest on Fuel" state (protein/water goals
            // left, nothing else Today can drive) degrades to a read-only status row with no way
            // to get to Fuel from the very screen that says to go there.
            //
            // `onFinishSetup` opens the goals editor (a sheet, below); `onOpenGymSetup` lands on
            // Settings, where the gym setup row lives (its detail view is private to Settings).
            TodayView(
                onOpenFuel: { appRouter.selectedTab = .fuel },
                onFinishSetup: { showGoalsEditor = true },
                onOpenGymSetup: { appRouter.openGymSetup() }
            )
            .zanoTabContent()
            .tag(AppTab.today)

            // The other four use `.navigationTitle` but carry no stack of their own
            // (`LockStatusView`'s header says so explicitly; `FuelView`/`ProgressView`/
            // `SettingsView` only set titles), so each tab supplies one.
            NavigationStack { LockStatusView(onGoToToday: { appRouter.selectedTab = .today }) }
                .zanoTabContent()
                .tag(AppTab.lock)

            NavigationStack { FuelView() }
                .zanoTabContent()
                .tag(AppTab.fuel)

            NavigationStack { ProgressView() }
                .zanoTabContent()
                .tag(AppTab.progress)

            NavigationStack { SettingsView() }
                .zanoTabContent()
                .tag(AppTab.settings)
        }
        .tint(Theme.Colors.interactive)
        // The floating glass bar replaces the system tab bar (hidden per tab by `zanoTabContent`).
        // It stays put when the keyboard opens rather than riding up on it.
        .overlay(alignment: .bottom) {
            ZanoTabBar(selection: $selection, isLockActive: lockSessions.contains(where: \.isActive))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard)
        }
        .sheet(isPresented: $showGoalsEditor) {
            NavigationStack { GoalsEditorView(showsDoneButton: true) }
                .preferredColorScheme(.dark)
        }
        // Held back (getter returns `nil`) while the alarm is ringing, then presents as soon as it
        // clears — the queued `router.unlockCelebration` isn't lost. `UnlockCelebrationView`'s own
        // "Nice" button calls `dismiss()`, which writes `nil` back through the setter.
        //
        // The setter ignores a `nil` write while the alarm is up (read live from the router, not
        // from the value captured for this render): the getter is already returning `nil` then, so
        // any `nil` SwiftUI writes back during that window is bookkeeping for a presentation it just
        // tore down or never started, not the person tapping "Nice" — and honouring it would throw
        // away the celebration that is queued to show once the alarm clears.
        .fullScreenCover(
            item: Binding<UnlockCelebrationContent?>(
                get: { isAlarmRinging ? nil : celebration },
                set: { newValue in
                    if newValue == nil, appRouter.isAlarmRingingPresented { return }
                    appRouter.unlockCelebration = newValue
                }
            )
        ) { content in
            UnlockCelebrationView(
                goalName: content.goalName,
                timeBankRemainingMinutes: content.timeBankRemainingMinutes,
                timeBankTotalMinutes: content.timeBankTotalMinutes
            )
            .preferredColorScheme(.dark)
        }
        // A tapped tag with no mapping yet: map it right here, over whatever tab is showing
        // (Wave 1B). Held back while the alarm rings, like the celebration above.
        .sheet(item: Binding(
            get: { isAlarmRinging ? nil : appRouter.pendingUnmappedTagID.map { UnmappedTagPrompt(tagID: $0) } },
            set: { if $0 == nil { _ = appRouter.consumeUnmappedTagID() } }
        )) { prompt in
            UnmappedTagView(tagID: prompt.tagID) { _ in _ = appRouter.consumeUnmappedTagID() }
        }
    }
}

private extension View {
    /// A tab's root: the system tab bar hidden, and room at the bottom for the floating one so the
    /// last row and any bottom action bar sit above it (content still scrolls under the glass).
    func zanoTabContent() -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: ZanoTabBar.reservedHeight)
            }
    }
}

#Preview {
    ContentView()
        .environment(AppRouter.shared)
        .modelContainer(ModelContainer.appGroup)
}
