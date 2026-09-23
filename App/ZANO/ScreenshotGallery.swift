// ScreenshotGallery.swift
// App
//
// CI-only screenshot gallery. There is no Mac (and no Simulator UI) in this project's workflow, so
// `.github/workflows/ci.yml` boots an iOS Simulator, installs the freshly built app, and launches it
// once per screen name:
//
//     xcrun simctl launch <sim> com.zano.app -ZANOScreen tab-today
//
// `-ZANOScreen <name>` lands in `UserDefaults.standard` (the argument domain) automatically, so no
// argument parsing is needed. When it is absent — every normal launch, including every App Store
// build — none of this file runs: `ZANOApp` only consults `ScreenshotMode.screen`, and a nil value
// falls straight through to `ContentView`.
//
// Screens render through the REAL code paths against the REAL App Group store, seeded once with
// believable demo data (`DemoData.seed()`), so what the screenshots show is what a user would see —
// not a mock-up. What they cannot show: anything needing FamilyControls / DeviceActivity / NFC /
// HealthKit workouts / a real geofence (none of which run in the Simulator, docs/spec.md §27).

import SwiftUI
import SwiftData
import Core

enum ScreenshotMode {
    /// The requested screen name, or nil on every normal launch.
    static var screen: String? {
        let value = UserDefaults.standard.string(forKey: "ZANOScreen")
        return (value?.isEmpty == false) ? value : nil
    }

    /// Called from `ZANOApp.init()` before the first render. Seeds demo data and puts the router in
    /// the state the requested screen needs (main app vs. onboarding, which tab).
    @MainActor
    static func prepare(screen name: String) {
        DemoData.seed()

        if name.hasPrefix("tab-") {
            AppRouter.shared.completeOnboarding()
            switch name {
            case "tab-lock": AppRouter.shared.selectedTab = .lock
            case "tab-fuel": AppRouter.shared.selectedTab = .fuel
            case "tab-progress": AppRouter.shared.selectedTab = .progress
            case "tab-settings": AppRouter.shared.selectedTab = .settings
            default: AppRouter.shared.selectedTab = .today
            }
        }
    }
}

// MARK: - Host

/// Renders one named screen. Onboarding screens go through the real container (with its chrome),
/// tabs go through the real `ContentView` (with the real tab bar), everything else is wrapped in a
/// `NavigationStack` the way it would be when pushed.
struct ScreenshotHost: View {
    let name: String

    var body: some View {
        content
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if name.hasPrefix("onboarding-"), let n = Int(name.dropFirst("onboarding-".count)) {
            OnboardingContainerView(initialScreen: n)
        } else if name.hasPrefix("tab-") {
            ContentView()
        } else {
            standalone
        }
    }

    @ViewBuilder
    private var standalone: some View {
        switch name {
        case "paywall":
            PaywallView(flowState: OnboardingFlowState())
        case "locksetup":
            NavigationStack { LockSetupView() }
        case "trophy":
            NavigationStack { TrophyCaseView() }
        case "cosmetics":
            NavigationStack { CosmeticsShopView() }
        case "sunrise-setup":
            NavigationStack { SunriseAlarmSetupView() }
        case "bedtime-setup":
            NavigationStack { BedtimeGateSetupView() }
        case "alarm-ringing":
            AlarmRingingView()
        default:
            ContentUnavailableView("Unknown screen", systemImage: "questionmark.square.dashed",
                                   description: Text(name))
        }
    }
}

// MARK: - Demo data

/// One believable "day 15 of a streak, mid-afternoon, locked until the workout is done" user.
/// Idempotent: does nothing if a `User` already exists (each screen is a separate launch).
@MainActor
enum DemoData {
    static func seed() {
        let context = ModelContext(ModelContainer.appGroup)
        guard ((try? context.fetchCount(FetchDescriptor<User>())) ?? 0) == 0 else { return }

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let created = calendar.date(byAdding: .day, value: -40, to: now) ?? now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let user = User(coachVoice: .hype, planTier: .pro)
        context.insert(user)

        let workout = Goal(type: .workoutGym, title: "Gym session", targetValue: 45, unit: "min",
                           cadence: "daily", verificationTier: .a, createdAt: created, user: user)
        let protein = Goal(type: .protein, title: "Protein", targetValue: 150, unit: "g",
                           cadence: "daily", verificationTier: .b, createdAt: created, user: user)
        let focus = Goal(type: .focusSession, title: "Focus", targetValue: 50, unit: "min",
                         cadence: "daily", verificationTier: .a, createdAt: created, user: user)
        let water = Goal(type: .water, title: "Water", targetValue: 3000, unit: "ml",
                         cadence: "daily", verificationTier: .b, createdAt: created, user: user)
        [workout, protein, focus, water].forEach { context.insert($0) }

        // Today's progress: protein 72/150 g, focus 25/50 min, water 1500/3000 ml, workout not yet.
        let morning = calendar.date(byAdding: .hour, value: 9, to: today) ?? now
        let noon = calendar.date(byAdding: .hour, value: 12, to: today) ?? now
        context.insert(GoalEvent(ts: morning, kind: .log, value: 30, source: .nfc, verified: true, user: user, goal: protein))
        context.insert(GoalEvent(ts: noon, kind: .log, value: 42, source: .photo, verified: true, user: user, goal: protein))
        context.insert(GoalEvent(ts: morning, kind: .log, value: 25, source: .timer, verified: true, user: user, goal: focus))
        context.insert(GoalEvent(ts: morning, kind: .log, value: 750, source: .nfc, verified: true, user: user, goal: water))
        context.insert(GoalEvent(ts: noon, kind: .log, value: 750, source: .widget, verified: true, user: user, goal: water))

        context.insert(Streak(userID: user.id, current: 14, best: 21, freezesLeft: 2, lastEarnedDate: yesterday))

        let lockSet = LockSet(userID: user.id, name: "Social", isDefault: true)
        context.insert(lockSet)
        let session = LockSession(userID: user.id, lockSetID: lockSet.id,
                                  startedAt: calendar.date(byAdding: .hour, value: 7, to: today) ?? now,
                                  trigger: .schedule, mode: .full,
                                  requiredGoalIDs: [workout.id, protein.id])
        context.insert(session)

        context.insert(TimeBank(userID: user.id, date: today, earnedMin: 90))
        context.insert(Coin(userID: user.id, balance: 240))
        for key in ["first_unlock", "streak_7", "streak_14"] {
            context.insert(Badge(userID: user.id, key: key, earnedAt: yesterday))
        }

        try? context.save()

        // The lightweight mirrors the shield and widgets read without opening SwiftData.
        SharedDefaults.currentStreak = 14
        SharedDefaults.bestStreak = 21
        SharedDefaults.coachVoice = "hype"
        SharedDefaults.activeLockSessionID = session.id
        SharedDefaults.activeLockSetID = lockSet.id
        SharedDefaults.activeLockMode = .full
        SharedDefaults.goalsRemainingForActiveLock = 2
        SharedDefaults.earnedMinutesRemainingToday = 90
    }
}
