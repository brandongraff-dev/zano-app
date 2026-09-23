// Core/Sources/Core/Social/OnboardingDripScheduler.swift
//
// docs/spec.md §7 Onboarding Flow, last line:
//   "Post-onboarding drip (Day 0-3 pushes): widget added? gym saved? NFC tag ordered/created?
//   first squad invite?"
// docs/spec.md §8 Retention Psychology Rules, rule 7 ("Nudge scarcity"): "Max 2 proactive
// pushes/day. A nudge must change what the user does tonight or it doesn't send." — enforced by
// `NudgeSender` (`Core/Sources/Core/Social/NudgeSender.swift`, a sibling file this task does not
// own), which this file calls into rather than redeclaring: every nudge this scheduler wants to
// send goes through `NudgeSender.shared.send(arm:on:deliver:)`, so it shares that file's single
// 2/day cap and its `Nudge` row bookkeeping with every other nudge source (the §9.3 bandit, a
// future v1 population-prior rule) instead of keeping its own separate counter that could push the
// user past the real daily limit.
//
// What "checks each Day-0-3 condition against real state" means concretely, and why each check
// reads what it reads (flagged in `decisions`/`knownIssues` where a real gap exists):
//   - "widget added?" → `WidgetCenter.getCurrentConfigurations` (WidgetKit, iOS 16+), matched
//     against the `kind` string literals `Extensions/ZANOWidgets/HomeWidget/ZANOHomeWidget.swift`
//     and `.../LockScreenWidget/ZANOLockScreenWidget.swift` declare on their own `Widget`
//     conformances. Core cannot import the `ZANOWidgets` extension target (extensions depend on
//     Core, never the reverse — CLAUDE.md's target list), so those two strings are necessarily
//     duplicated literals here, not a shared constant; if either widget's `kind` is ever renamed,
//     `knownWidgetKinds` below must be updated by hand. Flagged in `knownIssues`.
//   - "gym saved?" → a confirmed `Gym` row exists for the signed-in user (`Models/Gym.swift`,
//     Session 1). `confirmed == true` specifically, not just any row: `Gym.confirmed`'s own doc
//     comment is explicit that an unconfirmed `autoDetected` row is "a suggestion only," and
//     `GymVerifier` "must only use confirmed gyms for real unlocks" — the drip should only stop
//     nudging once the user has something that actually verifies workouts, not a candidate they
//     haven't looked at yet.
//   - "NFC tag ordered/created?" → at least one saved `NFCTagMapping` exists
//     (`Core/Sources/Core/Verification/NFCTagMapper.swift`, read-only from here, never edited or
//     duplicated). This checks "created" only — the "ordered" half of spec's "ordered/created"
//     would mean a completed Tag Pack purchase (spec §25.1), and there is no purchase-tracking
//     state reachable from `Core` for that today (no `TagPack`-shaped model, no RevenueCat/
//     StoreKit transaction mirror in `Store`/`SharedDefaults`) — flagged in `knownIssues` rather
//     than guessed at.
//   - "first squad invite?" → the signed-in user has at least one local `SquadMember` row, i.e.
//     has created or joined a squad (`Core/Sources/Core/Social/SquadManager.swift`, read-only from
//     here). This is the closest real, on-device-checkable signal to "first squad invite": nothing
//     in `SquadManager`'s public API represents "sent an invite" as its own event (its own file
//     records squad *creation*/*joining*, not a share-sheet completion), so membership is what
//     this file treats as "done" — flagged in `decisions`.
//
// "Day 0" is read as the signed-in `User.createdAt` (`Models/User.swift`), not onboarding's own
// `committedAt` (`App/ZANO/Features/Onboarding/OnboardingFlowState.swift`'s `private(set) var
// committedAt: Date?`): that property lives in the `ZANO` app target's transient, in-memory
// onboarding flow state, not in `Core`, and is never persisted anywhere `Core` can read (no
// `SharedDefaults` mirror, no SwiftData column) — `Core` cannot depend on the app target regardless
// (Core is the shared package every target imports, never the other way around). `User.createdAt`
// is the closest real anchor `Core` actually has: per spec §4's anonymous-first flow the local
// `User` row is created essentially at first launch, before or during the same under-3-minute
// onboarding flow (spec §7's own target), so its calendar day and the true onboarding-completion
// day coincide for the overwhelming majority of sessions. Flagged as an approximation in
// `decisions`, not exact spec text.
//
// Scheduling choice (this task's own design, not exact spec text — flagged in `decisions`): rather
// than firing all 4 checks on Day 0 itself (the day the user is still inside the paywall/first-win
// moment onboarding screen 14 already ends with — including its own widget prompt, spec §7 point
// 14 — and shouldn't be immediately followed by a push about the very thing that screen just
// offered), each condition has its own earliest-eligible day inside the Day 0-3 window
// (`eligibleDayOffset`), spreading the 4 possible nudges out instead of bursting them at once. Each
// condition is nudged **at most once** ever (`hasAlreadyNudged`/`markNudged`, an App-Group-
// `UserDefaults`-backed flag per condition — same "small piece of state with nowhere else to live"
// convention `ComebackMode`/`CalendarAwareness`/`NFCTagMapper` (all read for this task) already
// use): once the window closes on Day 3, an unmet condition is simply never nudged again, matching
// spec §8 rule 7's "a nudge must change what the user does tonight or it doesn't send" — nagging
// about a Day-1 setup step on Day 30 would not.
//
// Rendering: `NudgeSender.send(arm:on:deliver:)`'s `deliver` closure is documented as "a narrow,
// explicitly-scoped cross-module integration point for whichever session wires up push/widget/
// shield delivery" — this file is exactly that session for these 4 conditions, so
// `presentLocalNotification` gives it a real implementation (`UNUserNotificationCenter`, mirroring
// `Core/Sources/Core/Verification/SunriseAlarmManager.swift`'s already-established local-
// notification pattern) rather than leaving `NudgeSender`'s no-op default in place, per CLAUDE.md
// "write complete, real code, not TODO-only stubs."
//
// UNVERIFIED (no Mac/compiler this task — CLAUDE.md rule 5): this task's training-knowledge best
// guess is that `WidgetCenter.getCurrentConfigurations(_:)` (completion-handler based; there is no
// native `async`/`await` overload) and `WidgetInfo.kind`/`.family` have existed unchanged since
// iOS 16 (this package's minimum is iOS 17 — `Package.swift`). Not checked against current Apple
// documentation — flagged again in `knownIssues`.

import Foundation
import SwiftData
import WidgetKit
import UserNotifications
import os

// MARK: - Condition

/// One of spec §7's 4 Day 0-3 drip checks.
public enum OnboardingDripCondition: String, CaseIterable, Sendable, Codable, Identifiable {
    case widgetAdded = "widget_added"
    case gymSaved = "gym_saved"
    case nfcTagCreated = "nfc_tag_created"
    case firstSquadInvite = "first_squad_invite"

    public var id: String { rawValue }
}

// MARK: - Status snapshot

/// One condition's current state, for a future settings/checklist UI (e.g. "3 of 4 setup steps
/// done") to render without duplicating this file's own satisfied/nudged logic.
public struct OnboardingDripStatus: Sendable, Equatable {
    public let condition: OnboardingDripCondition
    public let isSatisfied: Bool
    /// `true` once this condition has already had its one-time nudge queued (see this file's
    /// header comment — never re-queued after that, satisfied or not).
    public let alreadyNudged: Bool

    public init(condition: OnboardingDripCondition, isSatisfied: Bool, alreadyNudged: Bool) {
        self.condition = condition
        self.isSatisfied = isSatisfied
        self.alreadyNudged = alreadyNudged
    }
}

// MARK: - Errors

/// Errors this file throws itself, as opposed to errors bubbled up from SwiftData or
/// `NudgeSender`. Plain, developer-facing diagnostics — mirroring `NudgeSenderError`'s/
/// `SquadManagerError`'s documented convention — never routed through `Core/Sources/Core/Copy`.
public enum OnboardingDripSchedulerError: Error, Sendable, Equatable, LocalizedError {
    case noSignedInUser

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser: "No local User row exists yet."
        }
    }
}

// MARK: - OnboardingDripScheduler

/// `@MainActor`, matching this codebase's established choice for every other `Core` engine that
/// owns a `ModelContext` against the shared App Group store (`NudgeSender`, `SquadManager` is the
/// one exception — a plain `actor`, for reasons that file's own header explains and that don't
/// apply here) — see those files' doc comments for the identical reasoning.
@MainActor
public final class OnboardingDripScheduler {
    public static let shared = OnboardingDripScheduler()

    /// docs/spec.md §7: "Day 0-3 pushes." A condition is never nudged once more than this many
    /// days have passed since `User.createdAt` — see this file's header comment.
    public static let dripWindowDays = 3

    /// This task's own scheduling choice (see header comment) for which day inside the Day 0-3
    /// window each condition first becomes eligible to nudge. Every condition remains eligible
    /// through `dripWindowDays` once its own offset is reached (a late `runDailyCheck` call, e.g.
    /// the app not being opened on exactly the "right" day, still catches up rather than missing
    /// the window entirely) — only `hasAlreadyNudged`/the day-3 cutoff stop it, not a narrow
    /// single-day slot.
    private static let eligibleDayOffset: [OnboardingDripCondition: Int] = [
        .widgetAdded: 1,
        .gymSaved: 1,
        .nfcTagCreated: 2,
        .firstSquadInvite: 3,
    ]

    private let modelContainer: ModelContainer
    private lazy var context = ModelContext(modelContainer)
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "OnboardingDripScheduler")

    /// Separate, App-Group-backed `UserDefaults` instance (same suite `Store/SharedDefaults.swift`
    /// uses, a different file this task does not own) holding one small per-condition flag: has
    /// this condition already had its one-time drip nudge queued? Keyed distinctly from every key
    /// `Store/SharedDefaults.swift`/`StreakEngine`/`ComebackMode`/`CalendarAwareness` define so
    /// none of them can ever collide despite sharing the same underlying suite.
    private let dripDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static func nudgedKey(_ condition: OnboardingDripCondition) -> String {
        "com.zano.app.onboardingDrip.nudged.\(condition.rawValue)"
    }

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container; every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public: run

    /// Checks every Day-0-3 condition against real state and queues a nudge (via `NudgeSender`,
    /// see this file's header comment) for each one that's eligible today, unmet, and hasn't
    /// already been nudged. Call this once per app foreground/launch, or from a periodic
    /// background task — it is cheap and fully idempotent to call more than once on the same day.
    ///
    /// - Returns: the conditions a nudge was actually queued for this call (empty if none —
    ///   whether because everything's already done, nothing's eligible yet, the window already
    ///   closed, or there's no signed-in user). Never throws: a missing `User` row or a
    ///   `NudgeSender` failure is logged and treated as "nothing to do," matching
    ///   `StreakEngine`/`ComebackMode`'s convention that a background retention check must never
    ///   block or crash its caller.
    @discardableResult
    public func runDailyCheck(asOf date: Date = .now) async -> [OnboardingDripCondition] {
        guard let user = try? fetchCurrentUser() else { return [] }
        guard let daysSinceOnboarding = Self.daysBetween(user.createdAt, date, calendar: calendar),
              daysSinceOnboarding >= 0, daysSinceOnboarding <= Self.dripWindowDays
        else { return [] }

        var queued: [OnboardingDripCondition] = []
        for condition in OnboardingDripCondition.allCases {
            guard let eligibleDay = Self.eligibleDayOffset[condition], daysSinceOnboarding >= eligibleDay else { continue }
            guard !hasAlreadyNudged(condition) else { continue }
            guard await !isSatisfied(condition, userID: user.id) else { continue }

            await queueNudge(for: condition, user: user, on: date)
            markNudged(condition)
            queued.append(condition)
        }
        return queued
    }

    // MARK: - Public: condition introspection

    /// Whether `condition` is currently met, checked against real state — see this file's header
    /// comment for exactly what each condition reads. `false` (never an error) when there's no
    /// signed-in user yet, matching every other read-only method in this codebase's engines.
    public func isSatisfied(_ condition: OnboardingDripCondition) async -> Bool {
        guard let user = try? fetchCurrentUser() else { return false }
        return await isSatisfied(condition, userID: user.id)
    }

    /// All 4 conditions' current status, for a future "finish setting up" checklist UI. Empty when
    /// there's no signed-in user yet.
    public func status() async -> [OnboardingDripStatus] {
        guard let user = try? fetchCurrentUser() else { return [] }
        var result: [OnboardingDripStatus] = []
        for condition in OnboardingDripCondition.allCases {
            result.append(OnboardingDripStatus(
                condition: condition,
                isSatisfied: await isSatisfied(condition, userID: user.id),
                alreadyNudged: hasAlreadyNudged(condition)
            ))
        }
        return result
    }

    /// Clears every per-condition "already nudged" flag. Not called anywhere in this file — a
    /// future sign-out/account-reset flow (out of this task's scope) should call this alongside
    /// clearing everything else App-Group-scoped, so a fresh account starts its own Day 0-3 window
    /// clean rather than inheriting a previous account's flags on the same device.
    public func resetForNewAccount() {
        for condition in OnboardingDripCondition.allCases {
            dripDefaults.removeObject(forKey: Self.nudgedKey(condition))
        }
    }

    private func isSatisfied(_ condition: OnboardingDripCondition, userID: UUID) async -> Bool {
        switch condition {
        case .widgetAdded: return await Self.hasAddedWidget()
        case .gymSaved: return hasSavedGym(userID: userID)
        case .nfcTagCreated: return await Self.hasCreatedTagMapping()
        case .firstSquadInvite: return await Self.hasJoinedSquad()
        }
    }

    // MARK: - Condition checks: real state (see this file's header comment for each one's exact meaning)

    /// Mirrors the `kind` string literals `Extensions/ZANOWidgets/HomeWidget/ZANOHomeWidget.swift`
    /// (`"com.zano.app.widget.home"`) and `.../LockScreenWidget/ZANOLockScreenWidget.swift`
    /// (`"com.zano.app.widget.lockscreen"`) declare — see this file's header comment for why these
    /// are duplicated literals rather than a shared constant.
    private static let knownWidgetKinds: Set<String> = [
        "com.zano.app.widget.home",
        "com.zano.app.widget.lockscreen",
    ]

    /// Bridges `WidgetCenter.getCurrentConfigurations(_:)`'s completion-handler API (see this
    /// file's header "UNVERIFIED" note — no native `async` overload as of this task's training
    /// knowledge) to `async`/`await` with `withCheckedContinuation`. Resuming a continuation is
    /// safe regardless of which queue/thread the completion handler actually runs on, so this
    /// needs no additional isolation handling even though `WidgetCenter`'s completion is not
    /// documented to run on the main actor. `false` on failure (e.g. WidgetKit unavailable in this
    /// process) rather than throwing — matching `NudgeSender.remainingToday`'s "returns a safe
    /// default rather than propagating" convention for a cheap, non-critical read.
    private static func hasAddedWidget() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let widgets):
                    continuation.resume(returning: widgets.contains { knownWidgetKinds.contains($0.kind) })
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// `confirmed == true` specifically — see this file's header comment for why an unconfirmed
    /// auto-detected candidate doesn't count as "saved."
    private func hasSavedGym(userID: UUID) -> Bool {
        let descriptor = FetchDescriptor<Gym>(
            predicate: #Predicate<Gym> { $0.userID == userID && $0.confirmed == true }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private static func hasCreatedTagMapping() async -> Bool {
        !(await NFCTagMapper.shared.allMappings()).isEmpty
    }

    private static func hasJoinedSquad() async -> Bool {
        !((try? await SquadManager.shared.mySquads()) ?? []).isEmpty
    }

    // MARK: - Queueing (reuses NudgeSender's 2/day cap — never redeclares it, see header comment)

    private func queueNudge(for condition: OnboardingDripCondition, user: User, on date: Date) async {
        let tone = NudgeTone(rawValue: user.coachVoice.rawValue) ?? .hype
        let arm = NudgeArm(tone: tone, timingSlot: Self.timingSlot(at: date), format: .push)

        do {
            let outcome = try await NudgeSender.shared.send(arm: arm, on: date) { deliveredArm in
                await self.presentLocalNotification(for: condition, tone: deliveredArm.tone)
            }
            logger.notice(
                "Drip nudge for \(condition.rawValue, privacy: .public) queued (delivered=\(outcome.delivered, privacy: .public))."
            )
            Analytics.shared.capture(event: "onboarding_drip_nudge_queued", properties: [
                "condition": condition.rawValue,
                "delivered": outcome.delivered,
            ])
        } catch {
            logger.error(
                "Failed to queue drip nudge for \(condition.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// The real `deliver` implementation for `NudgeSender.send(arm:on:deliver:)` — see this file's
    /// header comment for why this file, not `NudgeSender` itself, owns rendering. Mirrors
    /// `SunriseAlarmManager.scheduleNotificationFallback`'s already-established
    /// `UNUserNotificationCenter` pattern in this same package. `trigger: nil` delivers
    /// immediately: `NudgeSender` has already decided *now* is the right moment to send (it only
    /// invokes `deliver` once a caller is under the 2/day cap), so there is nothing left to defer.
    private func presentLocalNotification(for condition: OnboardingDripCondition, tone: NudgeTone) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])

        let copy = Self.copy(for: condition, tone: tone)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = ["zano.onboardingDrip": condition.rawValue]

        let request = UNNotificationRequest(
            identifier: "zano.onboardingDrip.\(condition.rawValue)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private static func copy(for condition: OnboardingDripCondition, tone: NudgeTone) -> (title: String, body: String) {
        switch condition {
        case .widgetAdded: return Copy.onboardingDrip.widgetNotAdded(tone: tone)
        case .gymSaved: return Copy.onboardingDrip.gymNotSaved(tone: tone)
        case .nfcTagCreated: return Copy.onboardingDrip.nfcTagNotCreated(tone: tone)
        case .firstSquadInvite: return Copy.onboardingDrip.noSquadYet(tone: tone)
        }
    }

    /// Same 4-bucket split `SquadManager.timingSlot(at:)` uses — not reused from there (that
    /// method is `private`, and this file does not own `SquadManager` to widen its access); a
    /// second small, independent copy of the same simple hour-bucketing logic, matching the
    /// tolerance this codebase already shows for exactly this kind of narrow private duplication
    /// (`SquadManager`'s own version wasn't reused from anywhere else either).
    private static func timingSlot(at date: Date) -> NudgeTimingSlot {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .morning
        case 11..<16: return .preGymWindow
        case 16..<18: return .afternoon4pm
        default: return .evening
        }
    }

    // MARK: - Idempotency (per-condition, App-Group-backed — see header comment)

    private func hasAlreadyNudged(_ condition: OnboardingDripCondition) -> Bool {
        dripDefaults.bool(forKey: Self.nudgedKey(condition))
    }

    private func markNudged(_ condition: OnboardingDripCondition) {
        dripDefaults.set(true, forKey: Self.nudgedKey(condition))
    }

    // MARK: - Day math

    /// Whole calendar days from `start`'s local day to `end`'s local day — `0` on the same day,
    /// negative if `end` is before `start`. Mirrors `StreakEngine`/`ComebackMode`'s identical
    /// local-day-normalized `dateComponents([.day], from:to:)` convention.
    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int? {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day
    }

    // MARK: - SwiftData

    /// This device's local store holds exactly one `User` row (`Models/User.swift`'s own doc
    /// comment), so the first (only) one is always the right one — same convention
    /// `NudgeSender`/`SquadManager`/`ReferralManager` each use.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw OnboardingDripSchedulerError.noSignedInUser
        }
        return user
    }
}
