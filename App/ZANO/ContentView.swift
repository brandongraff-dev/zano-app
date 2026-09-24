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
                // Any active lock was already released by EntitlementGate before this shows.
                PaywallView(flowState: OnboardingFlowState())
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
    @Binding var selection: AppTab
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
            TodayView(onOpenFuel: { appRouter.selectedTab = .fuel })
                .tabItem { Label(Copy.today.screenTitle, systemImage: "target") }
                .tag(AppTab.today)

            // The other four use `.navigationTitle` but carry no stack of their own
            // (`LockStatusView`'s header says so explicitly; `FuelView`/`ProgressView`/
            // `SettingsView` only set titles), so each tab supplies one.
            NavigationStack { LockStatusView() }
                .tabItem { Label(Copy.lockStatus.screenTitle, systemImage: "lock.fill") }
                .tag(AppTab.lock)

            NavigationStack { FuelView() }
                .tabItem { Label(Copy.fuel.screenTitle, systemImage: "fork.knife") }
                .tag(AppTab.fuel)

            NavigationStack { ProgressView() }
                .tabItem { Label(Copy.progress.screenTitle, systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)

            NavigationStack { SettingsView() }
                .tabItem { Label(Copy.settings.screenTitle, systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        // Chrome is achromatic (decision 2026-09-24): the selected tab is white, and green stays
        // reserved for earned states.
        .tint(Theme.Colors.interactive)
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
    }
}

#Preview {
    ContentView()
        .environment(AppRouter.shared)
        .modelContainer(ModelContainer.appGroup)
}
