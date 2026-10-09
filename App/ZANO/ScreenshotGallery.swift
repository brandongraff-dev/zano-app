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
//
// DEBUG-only. `DemoData.seed()` writes fake rows into the REAL App Group store, so none of the
// seeding, routing or gallery code may exist in a Release build. The two names other files read
// (`ScreenshotMode.screen` in TodayView/PaywallView/WeeklyRecapShareView, `DemoData.screenTime` in
// TodayView) still compile in Release so those call sites need no `#if`; `screen` is always nil
// there, which makes every such branch dead.

import SwiftUI
import SwiftData
import os
import Core

enum ScreenshotMode {
    /// The requested screen name, or nil on every normal launch. Always nil in Release.
    static var screen: String? {
        #if DEBUG
        // A "light-" prefix (e.g. `light-tab-fuel`) only picks the scheme (see `colorScheme`), so a
        // focused CI run (the workflow's `screens` input) can shoot light mode too.
        guard var value = UserDefaults.standard.string(forKey: "ZANOScreen") else { return nil }
        if value.hasPrefix("light-") { value.removeFirst("light-".count) }
        return value.isEmpty ? nil : value
        #else
        return nil
        #endif
    }

    /// The scheme a screenshot run renders in: `-ZANOAppearance light` forces light (the CI light
    /// pass, saved as `shots/light-<name>.png`); anything else, including no argument, is dark, so
    /// the main tour stays comparable with earlier runs. Applied at the root by `ZANOApp`.
    static var colorScheme: ColorScheme {
        #if DEBUG
        let lightScreen = UserDefaults.standard.string(forKey: "ZANOScreen")?.hasPrefix("light-") == true
        return UserDefaults.standard.string(forKey: "ZANOAppearance") == "light" || lightScreen ? .light : .dark
        #else
        return .dark
        #endif
    }

    #if DEBUG

    /// Called from `ZANOApp.init()` before the first render. Seeds demo data and puts the router in
    /// the state the requested screen needs (main app vs. onboarding, which tab).
    @MainActor
    static func prepare(screen name: String) {
        DemoData.seed()
        applyBuddyArgument()
        applyOutfitArgument(screen: name)

        if name.hasPrefix("tab-") {
            AppRouter.shared.completeOnboarding()
            switch name {
            case "tab-lock": AppRouter.shared.selectedTab = .lock
            case "tab-fuel": AppRouter.shared.selectedTab = .fuel
            case "tab-squad": AppRouter.shared.selectedTab = .squad
            case "tab-progress": AppRouter.shared.selectedTab = .progress
            case "tab-settings": AppRouter.shared.selectedTab = .settings
            default: AppRouter.shared.selectedTab = .today
            }
        }
    }

    /// `-ZANOBuddy <rawValue>` (e.g. `brick`) stores that buddy before the first render, so CI can
    /// shoot any screen with any buddy (`buddy-brick-today`). Without it (or with an unknown name)
    /// the stored choice is cleared, so every other shot shows the default (Stash) whatever an
    /// earlier launch left behind. DEBUG screenshot runs only.
    private static func applyBuddyArgument() {
        if let raw = UserDefaults.standard.string(forKey: "ZANOBuddy"), let buddy = Buddy(rawValue: raw) {
            SharedDefaults.store.set(buddy.rawValue, forKey: Buddy.storageKey)
        } else {
            SharedDefaults.store.removeObject(forKey: Buddy.storageKey)
        }
    }

    /// A few tasks around today so the calendar shot shows dots, an agenda and an overdue item.
    private static func seedPlannerDemo() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return hour.flatMap { cal.date(bySettingHour: $0, minute: 0, second: 0, of: d) } ?? d
        }
        PlannerStore.tasks = [
            PlannerTask(title: "Send the invoice", due: day(-1)),
            PlannerTask(title: "Call the dentist", due: day(0, hour: 15), hasTime: true, remind: true),
            PlannerTask(title: "Read chapter 4", due: day(0)),
            PlannerTask(title: "Plan next week", due: day(2, hour: 10), hasTime: true),
            PlannerTask(title: "Renew passport", due: day(5)),
        ]
    }

    /// The Buddy Closet shot (and any run with `-ZANOOutfit demo`) shows a dressed buddy; every other
    /// shot clears the saved outfit, so an earlier launch can't leave one behind.
    private static func applyOutfitArgument(screen name: String) {
        if name == "planner" { seedPlannerDemo() } else { PlannerStore.tasks = [] }
        let buddy = Buddy.stored
        let wantsDemo = name == "buddy-closet" || UserDefaults.standard.string(forKey: "ZANOOutfit") == "demo"
        if wantsDemo {
            BuddyOutfit(skin: .sunset, hat: .hatWizard, eyewear: .eyewearRoundGlasses, neck: .neckBowtie,
                        backdrop: .backdropSunrise).save(for: buddy)
        } else {
            SharedDefaults.store.removeObject(forKey: BuddyOutfit.storageKey(for: buddy))
        }
    }
    #endif
}

#if DEBUG

// MARK: - Host

/// Renders one named screen. Onboarding screens go through the real container (with its chrome),
/// tabs go through the real `ContentView` (with the real tab bar), everything else is wrapped in a
/// `NavigationStack` the way it would be when pushed.
struct ScreenshotHost: View {
    let name: String

    // The scheme (dark, or light with `-ZANOAppearance light`) is applied at the app root by
    // `ZANOApp.rootColorScheme`, so sheets and covers follow it too.
    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if name.hasPrefix("onboarding-"), let n = Int(name.dropFirst("onboarding-".count)) {
            // onboarding-1 ... onboarding-8 (the flow's steps; see OnboardingFlowState.swift).
            // onboarding-2 is the buddy step.
            // Out-of-range numbers are clamped by the container.
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
        case "buddy-picker":
            // As pushed from Settings > Buddy (onboarding-2 shows it inside the flow's chrome).
            NavigationStack { BuddyPickerView(context: .settings) }
        case "buddy-closet":
            NavigationStack { BuddyClosetView() }
        case "planner":
            PlannerView()
        case "fuel-bottom":
            // The Fuel tab scrolled to its end (Top-ups and staples), which `tab-fuel` can't reach.
            NavigationStack { FuelView() }
                .defaultScrollAnchor(.bottom)
        case "characters":
            CharacterSheet()
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
        case "repeat-days":
            NavigationStack { RepeatDaysPreviewHost() }
        case "alarm-sound":
            NavigationStack { AlarmSoundPreviewHost() }
        case "wake-moment":
            // The "you're up" payoff over the ringing screen, as it looks once the check has landed.
            ZStack {
                AlarmRingingView()
                WakeMomentOverlay(kind: .verified, onSkip: {})
            }
        case "sun-moods":
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 20) {
                    ForEach(SunMood.allCases, id: \.self) { mood in
                        SunCharacter(mood: mood, animated: false)
                            .frame(width: 96, height: 96)
                    }
                }
                .padding(24)
            }
            .background(Theme.Colors.background)
        case "celebration":
            UnlockCelebrationView(goalName: "Gym session", verificationDetail: "42 min at the gym",
                                  timeBankRemainingMinutes: 130, timeBankTotalMinutes: 180)
        case "lockedout":
            LockedOutMomentView(
                content: LockedOutMomentContent(appName: "Social", attemptCount: 4,
                                                blockingGoalSummary: "hit the gym",
                                                goalsRemaining: 2, streak: 14),
                onDismiss: {}
            )
        case "recap":
            WeeklyRecapShareView(recap: DemoData.recap, goalTitles: DemoData.recapGoalTitles,
                                 rankTierLabel: "Gold", onDismiss: {})
        // Build-out Waves 1–3.
        case "gym-setup":
            NavigationStack { GymSetupView() }
        case "gym-checkin":
            NavigationStack { GymCheckInView() }
        case "nfc-tags":
            NavigationStack { NFCTagsView() }
        case "lock-card":
            NavigationStack { LockCardSetupView() }
        case "goals-editor":
            NavigationStack { GoalsEditorView(showsDoneButton: true) }
        case "lock-schedule":
            NavigationStack { LockScheduleEditor(lockSetID: LockEngineSharedState.defaultLockSetID ?? UUID()) }
        case "earn-settings":
            NavigationStack { EarnModeSettingsView() }
        case "tier-editor":
            NavigationStack { TierEditorView(lockSetID: LockEngineSharedState.defaultLockSetID ?? UUID()) }
        case "nudge-settings":
            NavigationStack { NudgeSettingsView() }
        case "health-pause":
            NavigationStack { PauseForHealthView() }
        case "solo-duel":
            NavigationStack { SoloDuelView() }
        case "squad-create":
            CreateJoinSquadSheet(model: SquadHomeModel(), initialMode: .create)
        case "referral":
            NavigationStack { ReferralView() }
        case "gym-leaderboard":
            NavigationStack { GymLeaderboardView() }
        case "autofocus":
            NavigationStack { AutoFocusGuideView() }
        case "milestone":
            MilestoneMomentView(milestone: .streak(days: 30), onDismiss: {})
        case "monthly-story":
            MonthlyStoryView(
                story: MonthlyStory(year: 2026, month: 9, earnedDays: 21, earnedUnlocks: 26,
                                    lockedMinutes: 84 * 60, bestStreak: 12, topGoalTitle: "Gym session"),
                onDismiss: {}
            )
        case "earned-it-clip":
            // One still frame of the clip's payoff beat (the video itself is made on a device).
            EarnedItClipScene(buddy: Buddy.stored, goalName: "Gym session", streak: 14, doneGoal: .workoutGym, progress: 0.8)
        case "year-in-review":
            YearInReviewView(
                review: YearInReview(year: 2026, earnedDays: 212, earnedUnlocks: 260, lockedMinutes: 900 * 60,
                                     bestStreak: 41, topGoalTitle: "Gym session", bestMonth: 3, bestMonthDays: 27),
                onDismiss: {}
            )
        default:
            ContentUnavailableView("Unknown screen", systemImage: "questionmark.square.dashed",
                                   description: Text(name))
        }
    }
}

#endif

// MARK: - Demo data

extension DemoData {
    /// Today's screen time for CI screenshots (the Simulator has none): a believable 2h 34m by
    /// 5:42 PM, a third of it in locked apps, drawn by the same `ScreenTimeSummaryView` the
    /// `ZANOReport` extension renders on a device. Never shown outside `-ZANOScreen` launches.
    static var screenTime: ScreenTimeSummary {
        let today = Calendar.current.startOfDay(for: .now)
        let asOf = Calendar.current.date(bySettingHour: 17, minute: 42, second: 0, of: today) ?? .now
        let perHour: [(Int, Double, Double)] = [
            (6, 0, 4), (7, 6, 11), (8, 2, 9), (9, 0, 6), (10, 0, 8), (11, 4, 7),
            (12, 14, 12), (13, 3, 9), (14, 0, 5), (15, 5, 8), (16, 9, 7), (17, 8, 6),
        ]
        let hours = perHour.map { ScreenTimeSummary.Hour(hour: $0.0, lockedMinutes: $0.1, otherMinutes: $0.2) }
        let locked = perHour.reduce(0) { $0 + $1.1 } * 60
        let other = perHour.reduce(0) { $0 + $1.2 } * 60
        return ScreenTimeSummary(
            total: locked + other,
            lockedTime: locked,
            pickups: 61,
            apps: [
                .init(id: "instagram", name: "Instagram", duration: TimeInterval(31 * 60), isLocked: true),
                .init(id: "messages", name: "Messages", duration: TimeInterval(26 * 60), isLocked: false),
                .init(id: "safari", name: "Safari", duration: TimeInterval(19 * 60), isLocked: false),
                .init(id: "tiktok", name: "TikTok", duration: TimeInterval(14 * 60), isLocked: true),
                .init(id: "spotify", name: "Spotify", duration: TimeInterval(11 * 60), isLocked: false),
            ],
            hours: hours,
            asOf: asOf
        )
    }
}

#if DEBUG
extension DemoData {
    /// Not inserted into the store: `WeeklyRecapShareView` renders straight from the value.
    static let recapGoalIDs: [UUID] = (0..<4).map { _ in UUID() }
    static let recapGoalTitles: [UUID: String] = [
        recapGoalIDs[0]: "Gym session", recapGoalIDs[1]: "Protein",
        recapGoalIDs[2]: "Focus", recapGoalIDs[3]: "Water",
    ]
    static var recap: Recap {
        Recap(
            userID: UUID(),
            weekStart: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
            text: "Four workouts and a 14-day streak. Thursday was your best day. Protect it next week.",
            stats: RecapStats(
                goalCompletionRings: [
                    recapGoalIDs[0].uuidString: 0.86, recapGoalIDs[1].uuidString: 0.71,
                    recapGoalIDs[2].uuidString: 0.57, recapGoalIDs[3].uuidString: 1.0,
                ],
                bestDay: "Thursday", timeReclaimedMinutes: 400, streak: 14, rankMovement: 1,
                goalsCompleted: 22, goalsPlanned: 28
            )
        )
    }
}
#endif

/// One believable "day 15 of a streak, mid-afternoon, locked until the workout is done" user.
/// Idempotent: does nothing if a `User` already exists (each screen is a separate launch).
@MainActor
enum DemoData {
    #if DEBUG
    static func seed() {
        let context = ModelContext(ModelContainer.appGroup)
        guard ((try? context.fetchCount(FetchDescriptor<User>())) ?? 0) == 0 else {
            logCounts(in: context, note: "store already seeded")
            return
        }

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

        // Fourteen days of completed mornings, each with a finished lock session: fills the streak
        // calendar and gives "Time Reclaimed" a real number.
        // Varied lengths so the weekly bars show real scaling instead of seven equal columns.
        let lockMinutes = [240, 150, 300, 90, 210, 45, 180]
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let started = calendar.date(byAdding: .hour, value: 7, to: day),
                  let finished = calendar.date(byAdding: .minute, value: lockMinutes[offset % lockMinutes.count], to: started) else { continue }
            context.insert(GoalEvent(ts: finished, kind: .complete, value: 45, source: .geofence,
                                     verified: true, user: user, goal: workout))
            context.insert(LockSession(userID: user.id, lockSetID: lockSet.id, startedAt: started,
                                       endedAt: finished, trigger: .schedule, mode: .full,
                                       requiredGoalIDs: [workout.id], unlockKind: .earned))
        }

        context.insert(TimeBank(userID: user.id, date: today, earnedMin: 90))
        context.insert(Coin(userID: user.id, balance: 240))
        // Badge keys must be the ones TrophyCaseView's grid uses (the six milestone keys), or a
        // badge lands in "More badges" instead of lighting its tile. A 15-day user has earned the
        // first unlock and the 7-day streak; "streak_14" is not a milestone key, and the old
        // "first_unlock" key was title-cased into a second "First Unlock" under "More badges".
        // The one extra is a real per-occurrence key (StreakEngine's "comeback_<yyyy-MM-dd>"):
        // the day this streak restarted after the 21-day best ended.
        let firstUnlockDay = calendar.date(byAdding: .day, value: -14, to: today) ?? yesterday
        let seventhDay = calendar.date(byAdding: .day, value: -8, to: today) ?? yesterday
        context.insert(Badge(userID: user.id, key: "first_earned_unlock", earnedAt: firstUnlockDay))
        context.insert(Badge(userID: user.id, key: "streak_7", earnedAt: seventhDay))
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        context.insert(Badge(userID: user.id, key: "comeback_\(dayFormatter.string(from: firstUnlockDay))",
                             earnedAt: firstUnlockDay))

        do {
            try context.save()
        } catch {
            logger.error("DemoData save failed: \(String(describing: error), privacy: .public)")
        }
        logCounts(in: context, note: "seeded")

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

    private static let logger = Logger(subsystem: "com.zano.app", category: "DemoData")

    /// One line in CI's app.log proving what the Progress tab should see: lock sessions total /
    /// ended / earned, plus the badge keys. Read back from a FRESH context, the same way `@Query`
    /// would see the store, so a save that silently dropped rows shows up here as a zero.
    private static func logCounts(in context: ModelContext, note: String) {
        let readBack = ModelContext(context.container)
        let sessions = (try? readBack.fetch(FetchDescriptor<LockSession>())) ?? []
        let ended = sessions.filter { $0.endedAt != nil }
        let earned = ended.filter { $0.unlockKind == .earned }
        let badgeKeys = ((try? readBack.fetch(FetchDescriptor<Badge>())) ?? []).map(\.key).sorted()
        logger.notice("DemoData \(note, privacy: .public): sessions total=\(sessions.count) ended=\(ended.count) earned=\(earned.count) badges=\(badgeKeys.joined(separator: ","), privacy: .public) tz=\(TimeZone.current.identifier, privacy: .public)")
    }
#endif
}

/// Hosts for the Repeat and Sound screens: each needs a binding, which a screenshot has no parent for.
private struct RepeatDaysPreviewHost: View {
    @State private var days = RepeatDays.weekdays
    var body: some View { RepeatDaysView(days: $days) }
}

private struct AlarmSoundPreviewHost: View {
    @State private var sound = AlarmSoundChoice.daybreak
    var body: some View { AlarmSoundView(sound: $sound) }
}

#if DEBUG
/// Every new page companion on one screen: Cal's four moods, the streak's fire and ice faces, and the
/// four tab buddies (session 29). Screenshot runs only.
private struct CharacterSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Cal").font(Theme.Typography.title).foregroundStyle(Theme.Colors.text)
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(CalPose.allCases, id: \.self) { CalSprite($0, size: 72) }
                }
                Text("Streak").font(Theme.Typography.title).foregroundStyle(Theme.Colors.text)
                HStack(spacing: Theme.Spacing.md) {
                    ForEach([BuddyPose.blaze, .frozen, .sleepy], id: \.self) { StoredBuddySprite(pose: $0, size: 96) }
                }
                Text("Tabs").font(Theme.Typography.title).foregroundStyle(Theme.Colors.text)
                HStack(spacing: Theme.Spacing.md) {
                    ForEach([BuddyPose.guarding, .eating, .analyzing, .tinkering], id: \.self) { StoredBuddySprite(pose: $0, size: 72) }
                }
                StreakPill(count: 14)
                StreakPill(count: 3, isFrozen: true)
                StreakPill(count: 0)
            }
            .padding(Theme.Spacing.lg)
        }
        .zanoBackdrop()
    }
}
#endif
