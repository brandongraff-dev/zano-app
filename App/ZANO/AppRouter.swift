// AppRouter.swift
// App / ZANO
//
// The one root router that ties the app together (the wave that wired `ContentView`/`ZANOApp`). It
// holds exactly the cross-screen state nothing else can own:
//   - whether onboarding is finished (`hasCompletedOnboarding`, persisted),
//   - the tab on screen and any deep-link destination that arrived before it could be applied
//     (`selectedTab`, `pendingDeepLink`),
//   - the two full-screen "moments" the root presents over everything: the Sunrise Alarm ringing
//     screen (`isAlarmRingingPresented`) and the unlock celebration (`unlockCelebration`).
//
// Why a `static let shared` singleton instead of `@State` in `ZANOApp`: the two things that push
// into it — `UNUserNotificationCenterDelegate` callbacks and `.onOpenURL` — can fire before any
// SwiftUI view exists (a notification tap cold-launches the app), and the delegate object is
// created in `ZANOApp.init()` where a `@State` value can't be read. Every engine in `Core` is a
// `.shared` singleton for the same reason. It is still handed to views through `.environment(_:)`
// (see `ZANOApp.body`) so the views never reach for the global themselves.
//
// docs/spec.md sections this implements: §6 / §14 (`zano://tag/<uuid>` → NFC tag dispatch), §27
// ("Shield buttons cannot open your app directly; the standard workaround is ShieldActionDelegate →
// local notification → tap opens app" — the `zano://goals` / `zano://emergency` half of that
// workaround), §5.10 (the alarm's ringing screen), §16 P3 / §8 rule 4 (unlock celebration), and
// CLAUDE.md's "never ship a lock with no way out" (see `init(defaults:)`'s launch-time guard).
//
// Copy: none. Tab titles come from the existing per-screen `Copy.<area>.screenTitle` constants
// (`ContentView.swift`); nothing in this file shows the user a string.

import Foundation
import Observation
import SwiftData
import os
import Core

// MARK: - Destinations

/// The five tabs (docs/spec.md §15 screen list minus Squad, which has no built screen yet).
enum AppTab: Hashable, Sendable {
    case today
    case lock
    case fuel
    case progress
    case settings
}

/// A destination the app can be sent to from outside a view: a tapped shield notification, a
/// widget/Live Activity `Link`, or an NFC tag URL.
enum AppDeepLink: Equatable, Sendable {
    /// `zano://today` (Earn Meter Live Activity's "View Today") and `zano://focus/end` (Focus Live
    /// Activity's "End" link). Both land on Today, where the focus session's own controls live.
    case today
    /// `zano://goals` — `ShieldActionExtension`'s "Show my goals". Today shows exactly what's left.
    case goals
    /// `zano://emergency` — `ShieldActionExtension`'s "Emergency". Lands on the Lock tab, whose
    /// `LockStatusView` carries the emergency-unlock hold for the active session.
    case emergency
    /// The Settings tab, where the gym and NFC-tag setup steps live. Deliberately *not* parsed from a
    /// URL (`init?(url:)` never returns it): no widget, extension or tag posts a `zano://settings`
    /// link, so an outside URL has no business steering the app here. Only
    /// `handleNotificationTap(deepLink:isSunriseAlarm:onboardingDrip:)` builds it, for the
    /// post-onboarding drip pushes whose setup step is on that tab.
    case settings
    /// `zano://tag/<uuid>` — dispatched to `NFCTagMapper`. `url` is kept so the mapper re-parses
    /// the exact URL it was given rather than one rebuilt from `id`.
    case tag(id: UUID, url: URL)

    /// `nil` for anything that isn't a well-formed `zano://` URL this app handles.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "zano" else { return nil }

        // `NFCTagMapper.tagID(from:)` already accepts both `zano://tag/<uuid>` and the
        // authority-less `zano:tag/<uuid>` some NDEF encoders emit — reuse it, never re-implement.
        if let tagID = NFCTagMapper.tagID(from: url) {
            self = .tag(id: tagID, url: url)
            return
        }

        // `zano://goals` puts the target in the host; `zano:goals` (no `//`) puts it in the path.
        let pathTarget = url.pathComponents.first(where: { $0 != "/" })
        let target = (url.host ?? pathTarget)?.lowercased()
        switch target {
        case "today", "focus": self = .today
        case "goals": self = .goals
        case "emergency": self = .emergency
        default: return nil
        }
    }
}

/// `userInfo` keys that mark a tapped/delivered notification as something this router handles. The
/// three families this app posts today (`grep userInfo` across `App`, `Core` and `Extensions`):
/// shield notifications, the Sunrise Alarm's fallback chain, and the post-onboarding drip pushes.
/// Plain, non-isolated constants because `ZANONotificationDelegate` reads them off the main actor.
enum NotificationRouting {
    /// The exact key `Extensions/ZANOShieldAction/ShieldActionExtension.swift` writes
    /// (`notification.userInfo = ["deepLink": content.deepLink.absoluteString]`) — value is a
    /// `zano://` URL string.
    static let deepLinkUserInfoKey = "deepLink"
    /// The exact key `SunriseAlarmManager.scheduleNotificationFallback` writes
    /// (`["zano.sunriseAlarm": true, "escalationIndex": index]`).
    static let sunriseAlarmUserInfoKey = "zano.sunriseAlarm"
    /// The exact key `OnboardingDripScheduler.presentLocalNotification` writes
    /// (`["zano.onboardingDrip": condition.rawValue]`) — value is an `OnboardingDripCondition`
    /// raw value (`"widget_added"`, `"gym_saved"`, `"nfc_tag_created"`, `"first_squad_invite"`).
    static let onboardingDripUserInfoKey = "zano.onboardingDrip"
}

// MARK: - Unlock celebration content

/// Everything `UnlockCelebrationView` needs, already resolved to plain values (that view takes no
/// SwiftData models — see its own header). `id` is the ended `LockSession.id`, which makes this
/// usable directly as a `.fullScreenCover(item:)` payload and means two different unlocks can
/// never be mistaken for one presentation.
struct UnlockCelebrationContent: Identifiable, Equatable, Sendable {
    let id: UUID
    let goalName: String
    let timeBankRemainingMinutes: Int
    let timeBankTotalMinutes: Int
}

// MARK: - AppRouter

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// `TodayView.swift` already presents its own `UnlockCelebrationView` (a `.fullScreenCover`
    /// driven by its `@Query` of `LockSession`s) whenever an *earned* unlock lands while it is on
    /// screen, and that file isn't this task's to edit. So the root only presents the celebration
    /// when some *other* tab is selected — the case Today can't cover (e.g. logging the last
    /// protein on Fuel earns the unlock). Presenting from both would show the celebration twice
    /// back to back. Flip this to `false` if `TodayView`'s own cover is ever removed in favour of
    /// this one.
    static let todayTabPresentsOwnUnlockCelebration = true

    // MARK: State

    /// The tab on screen. `TabView(selection:)` binds straight to this (`ContentView`).
    var selectedTab: AppTab = .today

    /// `true` once the person has finished (or, per the launch guard below, been carried past)
    /// onboarding. Persisted, so it survives relaunch; `ContentView` swaps
    /// `OnboardingContainerView` for the tab UI on it.
    private(set) var hasCompletedOnboarding: Bool

    /// A destination that arrived before onboarding finished; applied by `completeOnboarding()`.
    /// `nil` otherwise — a deep link that can be applied immediately is never parked here.
    private(set) var pendingDeepLink: AppDeepLink?

    /// Set when `zano://tag/<uuid>` named a tag that has no saved mapping yet. The one-screen tag
    /// mapping flow lives in Settings (`SettingsView`'s `MapTagSheet`), so the router selects the
    /// Settings tab and parks the id here for that screen to pick up via `consumeUnmappedTagID()`.
    /// Nothing reads it yet — `SettingsView.swift` isn't this task's file (see this task's
    /// `knownIssues`).
    private(set) var pendingUnmappedTagID: UUID?

    /// The celebration currently queued/presented at the root. `ContentView` binds a
    /// `.fullScreenCover(item:)` to this and holds it back while the alarm is ringing.
    var unlockCelebration: UnlockCelebrationContent?

    /// Whether the Sunrise Alarm's ringing screen should be up right now. Derived, not stored:
    /// `AlarmRingingView`'s own header documents the contract — "shown whenever
    /// `SunriseAlarmManager.shared.isRinging` is true" — and `SunriseAlarmManager` is `@Observable`,
    /// so reading it here makes any view that reads this property update when it changes. Never
    /// gate on onboarding: a ringing alarm outranks every other screen.
    var isAlarmRingingPresented: Bool {
        SunriseAlarmManager.shared.isRinging
    }

    // MARK: Init

    private static let onboardingCompletedKey = "zano.app.hasCompletedOnboarding.v1"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.zano.app", category: "AppRouter")

    /// - Parameter defaults: Overridable for tests/previews. `.standard`, not the App Group suite:
    ///   nothing outside the app process (no extension, no watch) needs to know onboarding state.
    init(defaults: UserDefaults = .standard) {
        var completed = defaults.bool(forKey: Self.onboardingCompletedKey)

        // Launch-time safety guard (CLAUDE.md: "Never ship a lock with no way out"). Onboarding's
        // last screen (`Screen14FirstWin`) starts a *real* shield. If the app is killed or crashes
        // while that lock is up, the flag is still `false` and the person would be sent back to
        // screen 1 with apps still shielded — and the shield's own "Emergency" notification would
        // deep-link into a screen that has no emergency control. An active lock at launch proves
        // they got through the commitment screen, so treat onboarding as done and drop them where
        // the Lock tab's emergency hold exists. Runs only here, at construction, so it can never
        // yank a *live* onboarding flow out from under its own first-win lock.
        if !completed, SharedDefaults.activeLockSessionID != nil {
            completed = true
            defaults.set(true, forKey: Self.onboardingCompletedKey)
        }

        self.defaults = defaults
        self.hasCompletedOnboarding = completed
    }

    // MARK: Onboarding

    /// The hook `OnboardingContainerView.onFinished` is wired to (it fires once, from
    /// `Screen14FirstWin.finishOnboarding()`, after the widget prompt is dismissed). Persists the
    /// flag, then applies any deep link that arrived while onboarding was still running.
    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        defaults.set(true, forKey: Self.onboardingCompletedKey)
        hasCompletedOnboarding = true

        if let link = pendingDeepLink {
            pendingDeepLink = nil
            apply(link)
        }
    }

    // MARK: Deep links (spec §6, §14, §27)

    /// Entry point for `.onOpenURL` and for a notification's `deepLink` string.
    func handle(url: URL) {
        guard let link = AppDeepLink(url: url) else {
            logger.notice("Ignoring an unrecognized URL: \(url.absoluteString, privacy: .private)")
            return
        }
        handle(link)
    }

    func handle(_ link: AppDeepLink) {
        guard hasCompletedOnboarding else {
            switch link {
            case .tag:
                // No tag can be mapped before onboarding finishes, and replaying a tap's action
                // minutes later would surprise the person — drop it.
                logger.notice("Dropping a tag link received before onboarding finished.")
            case .today, .goals, .emergency, .settings:
                pendingDeepLink = link
            }
            return
        }
        apply(link)
    }

    /// `ZANONotificationDelegate.didReceive` lands here. Handles the three notification families this
    /// app posts that need routing: shield notifications (a `deepLink` URL string), the Sunrise
    /// Alarm chain (the alarm's own ringing screen, not a URL), and the post-onboarding drip pushes
    /// (`onboardingDrip` is the `OnboardingDripCondition` raw value; a tap lands on the tab where
    /// that setup step lives instead of dead-ending on whatever tab was last open).
    func handleNotificationTap(deepLink: String?, isSunriseAlarm: Bool, onboardingDrip: String?) async {
        if let deepLink, let url = URL(string: deepLink) {
            handle(url: url)
        }
        if let onboardingDrip, let condition = OnboardingDripCondition(rawValue: onboardingDrip) {
            switch condition {
            case .gymSaved, .nfcTagCreated:
                // Gym confirmation and NFC tag mapping are both Settings flows.
                handle(.settings)
            case .widgetAdded, .firstSquadInvite:
                // Widgets are added from the Home Screen and there is no Squad screen yet (spec §15
                // lists it; none is built), so there is no better place than where the app opens.
                break
            }
        }
        if isSunriseAlarm {
            await beginAlarmIfDue()
        }
    }

    private func apply(_ link: AppDeepLink) {
        switch link {
        case .today, .goals:
            selectedTab = .today
        case .emergency:
            selectedTab = .lock
        case .settings:
            selectedTab = .settings
        case .tag(let id, let url):
            Task { await performTagDispatch(id: id, url: url) }
        }
    }

    /// Runs a scanned/opened tag URL through `NFCTagMapper`, exactly as `AlarmRingingView` and
    /// `SettingsView` do for an in-app scan.
    private func performTagDispatch(id: UUID, url: URL) async {
        do {
            let outcome = try await NFCTagMapper.shared.handleScannedURL(url)
            switch outcome {
            case .handled(let action, let tagID):
                Analytics.shared.capture(event: "nfc_tag_url_handled", properties: ["outcome": "handled"])
                // `NFCTagAction` is deliberately not `Equatable`, so pattern-match.
                if case .sunriseKey = action {
                    await finishSunriseAlarmIfRinging(tagID: tagID)
                }
            case .unmapped(let tagID):
                // First tap of an unmapped tag is the expected setup path, not a failure
                // (`NFCTagDispatchOutcome.unmapped`'s own doc comment): send them to Settings.
                Analytics.shared.capture(event: "nfc_tag_url_handled", properties: ["outcome": "unmapped"])
                pendingUnmappedTagID = tagID
                selectedTab = .settings
            }
        } catch {
            logger.error("Tag dispatch failed for \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// The alarm half of "tapping the Sunrise Tag" (`AlarmRingingView`'s documented two-step
    /// handshake): `NFCTagMapper` → `SunriseKeyIntent` already logged the morning goal and armed
    /// the day's lock, but has no idea an alarm is ringing, so the alarm's own sound/notification
    /// chain/Live Activity are still going until `dismissViaTag(tagID:)` silences them. Without
    /// this, opening the app via the tag would leave the alarm buzzing.
    private func finishSunriseAlarmIfRinging(tagID: UUID) async {
        await beginAlarmIfDue()
        let alarm = SunriseAlarmManager.shared
        guard alarm.isRinging else { return }
        do {
            try await alarm.dismissViaTag(tagID: tagID)
        } catch {
            logger.error("Sunrise alarm tag dismiss failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Returns and clears `pendingUnmappedTagID`. For the (future) Settings hook noted above.
    func consumeUnmappedTagID() -> UUID? {
        defer { pendingUnmappedTagID = nil }
        return pendingUnmappedTagID
    }

    // MARK: Sunrise Alarm (spec §5.10)

    /// Flips `SunriseAlarmManager.isRinging` on if an alarm is due — which is what presents
    /// `AlarmRingingView` (see `isAlarmRingingPresented`). Nothing else ever sets `isRinging`
    /// (`SunriseAlarmManager.beginRingingIfDue`'s doc comment: "call when the app is opened
    /// around/after the alarm's fire time... then present `AlarmRingingView`").
    ///
    /// Guarded on `!isRinging` because `beginRingingIfDue` is *not* idempotent while ringing: it
    /// resets `stepsWalked` to 0 and restarts the Squad-notify timer on every call, which would
    /// break the Steps dismiss variant if this were polled unguarded.
    func beginAlarmIfDue() async {
        let alarm = SunriseAlarmManager.shared
        guard !alarm.isRinging else { return }
        await alarm.beginRingingIfDue()
    }

    /// Defensive catch-up for a Tag dismiss that happened without `AlarmRingingView` on screen
    /// (`SunriseAlarmManager.reconcileIfDismissedElsewhere`). Cheap no-op unless the alarm is
    /// ringing. Called once per foreground entry, not per poll — it does a SwiftData fetch.
    func reconcileAlarmIfNeeded() async {
        await SunriseAlarmManager.shared.reconcileIfDismissedElsewhere()
    }

    // MARK: Unlock celebration (spec §16 P3, §8 rule 4)

    /// Called by `ContentView` when `LockEngineManager.lastUnlockedSessionID` changes. Presents
    /// the celebration only for an *earned* unlock, only after onboarding (`Screen14FirstWin`
    /// ends its own first-win lock as `.earned` and runs its own confetti — a second celebration
    /// there would double up), and never on the Today tab (see
    /// `todayTabPresentsOwnUnlockCelebration`).
    func handleUnlock(sessionID: UUID) {
        guard hasCompletedOnboarding else { return }
        if Self.todayTabPresentsOwnUnlockCelebration, selectedTab == .today { return }
        guard let content = makeUnlockCelebration(forSessionID: sessionID) else { return }

        // Same event name and shape `TodayView` already fires for its own screen (spec §23:
        // "every unlock kind"), so unlocks that land on another tab aren't silently uncounted.
        Analytics.shared.capture(event: "unlock_completed", properties: ["kind": "earned", "screen": "root"])
        unlockCelebration = content
    }

    /// Builds the celebration's plain-value payload from SwiftData, or `nil` if `sessionID` isn't
    /// an earned unlock. Mirrors `TodayView`'s own resolution (single required goal → its title,
    /// otherwise `Copy.today.unlockCelebrationFallbackGoalName`; today's `TimeBank` row for the
    /// bar) so the same unlock reads identically whichever surface presents it.
    ///
    /// A fresh `ModelContext` per call — same reasoning as `WatchSyncManager.buildSnapshot`/the App
    /// Intents: a long-lived context can serve stale rows another context has since changed, and
    /// this is called at the exact moment `LockEngineManager`'s own context just saved one.
    ///
    /// No `verificationDetail` and no bonus `badge`: neither has a source of truth anywhere yet
    /// (spec §8 rule 4's "1 in ~6" reward has no gating logic in the codebase — `TodayView` flags
    /// the same gap).
    private func makeUnlockCelebration(forSessionID sessionID: UUID) -> UnlockCelebrationContent? {
        let context = ModelContext(ModelContainer.appGroup)

        var sessionDescriptor = FetchDescriptor<LockSession>(predicate: #Predicate<LockSession> { $0.id == sessionID })
        sessionDescriptor.fetchLimit = 1
        guard let session = try? context.fetch(sessionDescriptor).first,
              session.unlockKind == .earned
        else { return nil }

        // `Set.contains` in plain Swift after a full fetch rather than inside `#Predicate` — this
        // codebase's established conservatism (see `LockEngineManager.isGoalVerified`) for
        // SwiftData predicate features nobody could compile-check. Goals per user are few.
        let requiredIDs = Set(session.requiredGoalIDs)
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let required = goals.filter { requiredIDs.contains($0.id) }
        let goalName = required.count == 1
            ? required[0].title
            : Copy.today.unlockCelebrationFallbackGoalName

        let banks = (try? context.fetch(FetchDescriptor<TimeBank>())) ?? []
        let todaysBank = banks.first { Calendar.current.isDateInToday($0.date) }

        return UnlockCelebrationContent(
            id: sessionID,
            goalName: goalName,
            timeBankRemainingMinutes: todaysBank?.remainingMin ?? 0,
            timeBankTotalMinutes: todaysBank?.earnedMin ?? 0
        )
    }
}
