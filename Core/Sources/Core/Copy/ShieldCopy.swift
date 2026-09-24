// ShieldCopy.swift
// Core / Copy
//
// The Living Shield's copy engine (docs/spec.md §5.1): "The block screen isn't static. It
// reflects state and personality." This is the ONLY place that decides what the shield says —
// `ShieldConfigurationExtension` and `ShieldActionExtension` (Extensions/ZANOShieldConfig,
// Extensions/ZANOShieldAction) call into this file and render whatever it returns; neither
// extension should ever build a `String` for the shield itself (CLAUDE.md: "user-facing copy
// lives in Core/Sources/Core/Copy — no hardcoded UI strings elsewhere").
//
// Inputs are deliberately narrow: everything here comes from `SharedDefaults`
// (`Core/Sources/Core/Store/SharedDefaults.swift`), never a SwiftData fetch or a network call —
// docs/spec.md §11/§27: "Extensions must be tiny. No network in Shield extensions. Read state
// from the App Group only." `SharedDefaults` is itself the App-Group-backed mirror that makes
// that possible.
//
// Voice: every string is written once per `CoachVoice` case (docs/spec.md §5.13: Hype / Tough
// Love / Chill / Data) via `CoachVoiceTone` (`CoachVoice.swift`, this directory). Variants exist
// per voice+moment so the shield doesn't say the exact same sentence every single time it's
// shown; which variant renders is a pure function of the day (`Date`), not randomness, so a
// screenshot taken twice in the same day is reproducible. docs/spec.md §9.3's Nudge
// Optimizer/bandit (v3) is the eventual home for "which variant converts best" — this is the v1
// static rotation that bandit will later drive instead of replace.

import Foundation

public enum ShieldCopy {

    // MARK: - Moment

    /// Which of the Living Shield's states to render (docs/spec.md §5.1: "mid-lock",
    /// "near-completion", "after a miss"). `moment(for:)` below resolves one of these from a
    /// `ShieldContext`; kept as its own type so `content(for:)` is a plain switch instead of
    /// re-deriving these priority rules inline at every call site.
    public enum Moment: Sendable, Equatable {
        /// `goalsRemainingForActiveLock` reads 0 but the shield is still on screen — a brief race
        /// between the last verification landing and `LockEngineManager.endLock` tearing the
        /// shield down. Never claim "you're 1 goal away" (or completion) before the engine has;
        /// ask the user to hold on for a second instead.
        case verifying
        /// One verified goal away from unlocking everything — spec §5.1's "You're 12g of protein
        /// from unlocking everything" finish-line moment. (This engine only has a goal *count*
        /// from `SharedDefaults`, not which goal or its remaining amount — see `ShieldContext`.)
        case nearCompletion
        /// `StreakEngine` armed Never Miss Twice off yesterday's miss (spec §5.6) and today
        /// hasn't earned an unlock yet to disarm it. Acknowledged once, never re-shown once the
        /// user has re-earned today (that's what `ShieldContext.recentMiss` going back to
        /// `false` represents).
        case afterMiss
        /// The default state: locked, multiple (or zero-but-not-yet-verifying) goals open, no
        /// miss to acknowledge.
        case midLock

        /// Resolves the moment from state, applying spec §5.1's implicit priority: a
        /// still-verifying shield always wins (never show stale copy), then the finish line
        /// (most motivating, most actionable), then the miss acknowledgment, then the default.
        static func resolve(goalsRemaining: Int, recentMiss: Bool) -> Moment {
            if goalsRemaining <= 0 { return .verifying }
            if goalsRemaining == 1 { return .nearCompletion }
            if recentMiss { return .afterMiss }
            return .midLock
        }
    }

    // MARK: - Context

    /// Everything the Living Shield needs, read once from `SharedDefaults` by the caller and
    /// handed in as a plain value — keeps `content(for:)`/`moment(for:)` pure functions with no
    /// `UserDefaults` access of their own, so they're trivially unit-testable and so it's obvious
    /// at a glance that this file never reaches past the App Group.
    public struct ShieldContext: Sendable {
        /// `CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice)`.
        public var voice: CoachVoice
        /// `Application.localizedDisplayName` / `WebDomain.domain` for the thing being shielded
        /// right now, when the extension point hands one to us. `nil` for the category-level
        /// overrides (`configuration(shielding:in:)`), which shield a whole category rather than
        /// one named app/site.
        public var shieldedName: String?
        /// `SharedDefaults.currentStreak`.
        public var currentStreak: Int
        /// `SharedDefaults.goalsRemainingForActiveLock`.
        public var goalsRemaining: Int
        /// `SharedDefaults.activeLockMode`. `nil` is treated like `.full` (the safer, more
        /// conservative default: never promise Time Bank minutes that might not exist).
        public var mode: LockMode?
        /// `SharedDefaults.earnedMinutesRemainingToday`, only meaningful when `mode == .earn`
        /// and `earnedMinutesMirrorIsForToday` is `true` (spec §5.2: minutes expire at midnight —
        /// a stale mirror must never be read as today's balance).
        public var earnedMinutesRemainingToday: Int
        /// `SharedDefaults.earnedMinutesMirrorIsForToday`.
        public var earnedMinutesMirrorIsForToday: Bool
        /// Best-effort "user slipped yesterday and hasn't recovered yet" signal for the
        /// after-a-miss moment (spec §5.6).
        ///
        /// TODO(cross-module, StreakEngine/Store session): `SharedDefaults` does not yet mirror
        /// `Streak.neverMissTwiceArmed` (`Core/Sources/Core/Models/Streak.swift`). Once
        /// `StreakEngine` adds e.g. `SharedDefaults.neverMissTwiceArmed` and keeps it in sync
        /// with `recordMiss`/`recordEarnedUnlock`, extensions should read it and pass it through
        /// here instead of a hardcoded `false`. Everything downstream (`Moment.resolve`,
        /// `content(for:)`) already branches correctly on this value — only the call site needs
        /// to change.
        public var recentMiss: Bool

        public init(
            voice: CoachVoice,
            shieldedName: String? = nil,
            currentStreak: Int,
            goalsRemaining: Int,
            mode: LockMode?,
            earnedMinutesRemainingToday: Int,
            earnedMinutesMirrorIsForToday: Bool,
            recentMiss: Bool = false
        ) {
            self.voice = voice
            self.shieldedName = shieldedName
            self.currentStreak = currentStreak
            self.goalsRemaining = goalsRemaining
            self.mode = mode
            self.earnedMinutesRemainingToday = earnedMinutesRemainingToday
            self.earnedMinutesMirrorIsForToday = earnedMinutesMirrorIsForToday
            self.recentMiss = recentMiss
        }
    }

    // MARK: - Rendered content

    /// A rendered title/subtitle pair, ready to hand straight to
    /// `ShieldConfiguration.Label(text:color:)`.
    public struct Content: Sendable, Equatable {
        public let title: String
        public let subtitle: String
    }

    public static func moment(for context: ShieldContext) -> Moment {
        .resolve(goalsRemaining: context.goalsRemaining, recentMiss: context.recentMiss)
    }

    /// Renders the Living Shield's title/subtitle for the given state (docs/spec.md §5.1).
    ///
    /// Shape (shield redesign): the **title is the fact** — what's left and what it opens
    /// ("2 goals to unlock Instagram", "Earn Instagram back: 1 goal left") — worded the same in
    /// every voice, because the shield is seen dozens of times a day and the fact has to be
    /// readable in one glance. The **subtitle is the coach** — the voice-varied nudge, plus at
    /// most one extra clause (Time Bank in Earn Mode, otherwise the streak) so it never runs past
    /// two short sentences. The one exception is the after-a-slip moment, whose title stays a
    /// voice-varied comeback line so the total goals left is never the headline for someone who
    /// just slipped (docs/design/writing-findings.md §3.5 and §4).
    /// - Parameter now: injectable for deterministic variant-rotation tests; defaults to `.now`.
    public static func content(for context: ShieldContext, now: Date = .now) -> Content {
        let m = moment(for: context)
        let variantIndex = dayIndex(on: now)
        let name: String
        if let shieldedName = context.shieldedName, !shieldedName.isEmpty {
            name = shieldedName
        } else {
            name = categoryFallbackName
        }
        // One extra clause at most: in Earn Mode the banked minutes are the more useful fact;
        // otherwise the streak.
        let extra = timeBankClause(context)
            ?? CoachVoiceTone.streakClause(context.voice, streak: context.currentStreak)

        switch m {
        case .verifying:
            var subtitle = verifyingSubtitles[context.voice] ?? "Checking your last goal. Hang on."
            if let bank = timeBankClause(context) {
                subtitle += " " + bank
            }
            return Content(title: verifyingTitle, subtitle: subtitle)

        case .nearCompletion:
            var subtitle = nearCompletionSubtitles[context.voice] ?? "Last one."
            if let extra {
                subtitle += " " + extra
            }
            return Content(title: remainingTitle(context, name: name), subtitle: subtitle)

        case .afterMiss:
            let titles = afterMissTitles[context.voice] ?? []
            let title = pick(titles, at: variantIndex, fallback: "Comeback day.")
            // `missAcknowledgment` already ends on the next smallest step (docs/spec.md §8 rule 9),
            // so nothing is appended after it: never show the total goals left to someone who just
            // slipped (docs/design/writing-findings.md §3.5 and §4).
            let subtitle = CoachVoiceTone.missAcknowledgment(context.voice)
            return Content(title: title, subtitle: subtitle)

        case .midLock:
            let nudges = midLockNudges[context.voice] ?? []
            var subtitle = pick(nudges, at: variantIndex, fallback: "It'll be here when your goals are done.")
            if let extra {
                subtitle += " " + extra
            }
            return Content(title: remainingTitle(context, name: name), subtitle: subtitle)
        }
    }

    /// The fact line: how many goals stand between the user and the shielded app. Full Mode
    /// unlocks the app outright; Earn Mode deposits minutes to spend on it (spec §5.2), so the
    /// wording differs — Earn Mode never promises the app simply "unlocks".
    private static func remainingTitle(_ context: ShieldContext, name: String) -> String {
        let n = context.goalsRemaining
        let goals = n == 1 ? "1 goal" : "\(n) goals"
        switch context.mode {
        case .earn: return "Earn \(name) back: \(goals) left"
        case .full, nil: return "\(goals) to unlock \(name)"
        }
    }

    // MARK: - Time Bank clause (Earn Mode only, spec §5.2/§5.11)

    /// Earn Mode can talk about the Time Bank; Full Mode never can (spec §5.2: the bank only
    /// exists in Earn Mode). `nil` whenever the mirror is stale/absent/zero, so the shield never
    /// promises minutes that don't exist or have already expired at midnight.
    private static func timeBankClause(_ context: ShieldContext) -> String? {
        guard context.mode == .earn,
              context.earnedMinutesMirrorIsForToday,
              context.earnedMinutesRemainingToday > 0 else { return nil }
        let minutes = context.earnedMinutesRemainingToday
        switch context.voice {
        case .hype: return "You've already banked \(minutes) min — spend it the second you're done."
        case .toughLove: return "\(minutes) min earned. Spend them when you finish."
        case .chill: return "\(minutes) min sitting in your Time Bank whenever you want them."
        case .data: return "Time Bank: \(minutes) min available."
        }
    }

    // MARK: - Buttons (docs/spec.md §5.1, §27 — labels are fixed, not voice-varied)

    /// "Shield buttons: **'Show me my goals'** ... **'Emergency'**" (spec §5.1); the shipped labels
    /// are the shorter "Show my goals" (docs/design/writing-findings.md §5.1, LOW) and the more
    /// explicit "Emergency unlock", so the escape hatch says what it does. Fixed across
    /// voices deliberately: the shield's two actions are wayfinding, not personality moments —
    /// varying them by voice would make the one predictable, always-tappable escape hatch
    /// (CLAUDE.md: "any lock/shield feature must always keep an emergency-unlock path") harder to
    /// recognize at a glance.
    public enum Buttons {
        public static let showGoals = "Show my goals"
        public static let emergency = "Emergency unlock"
    }

    // MARK: - Deep links (docs/spec.md §27: shields can't open the app directly)

    /// "Shield buttons cannot open your app directly; the standard workaround is
    /// `ShieldActionDelegate` → local notification → tap opens app" (spec §27). Reuses the same
    /// `zano://` scheme docs/spec.md §6 already defines for NFC tags (`zano://tag/<uuid>`) rather
    /// than inventing a second one.
    ///
    /// TODO(cross-module, App/Intents session): `project.yml`'s `ZANO` target does not yet
    /// register a `CFBundleURLTypes` entry for the `zano` scheme, and there is no `onOpenURL`
    /// handler in `App/ZANO/ZANOApp.swift` yet to route these. Both are needed before a tap on
    /// either notification actually lands on the right screen; until then these are well-formed,
    /// stable URLs that the app simply isn't listening for yet.
    public enum DeepLink {
        /// Routes to the goals/Today screen (spec §15 screen list) so the user can see exactly
        /// what's left.
        public static let goals = URL(string: "zano://goals")!
        /// Routes to the 60-second emergency-unlock hold screen (spec §5.1, §24: "provide an
        /// in-app emergency unlock with a short hold. Never trap users.").
        public static let emergency = URL(string: "zano://emergency")!
    }

    // MARK: - Local notification copy (posted by ShieldActionExtension, spec §27)

    /// A ready-to-post local notification: voice-appropriate title/body plus the deep link the
    /// app should route on when the user taps it.
    public struct NotificationContent: Sendable {
        public let identifier: String
        public let title: String
        public let body: String
        public let deepLink: URL
    }

    /// Posted when the shield's primary button ("Show my goals") is tapped.
    public static func showGoalsNotification(voice: CoachVoice, goalsRemaining: Int) -> NotificationContent {
        let title = showGoalsNotificationTitles[voice] ?? "Your goals are waiting"
        let body: String
        switch voice {
        case .hype: body = "Tap in — \(CoachVoiceTone.goalsRemainingClause(.hype, remaining: goalsRemaining))"
        case .toughLove: body = CoachVoiceTone.goalsRemainingClause(.toughLove, remaining: goalsRemaining)
        // Just the clause: it already carries the permission ("at your pace"), so a prefix on top
        // stacked the same reassurance twice in one push.
        case .chill: body = CoachVoiceTone.goalsRemainingClause(.chill, remaining: goalsRemaining)
        case .data: body = CoachVoiceTone.goalsRemainingClause(.data, remaining: goalsRemaining)
        }
        return NotificationContent(
            identifier: "zano.shield.showGoals",
            title: title,
            body: body,
            deepLink: DeepLink.goals
        )
    }

    /// Posted when the shield's "Emergency" button is tapped. Deliberately calm, never guilt-
    /// inducing — an emergency unlock is a promised escape hatch, not a failure (CLAUDE.md: never
    /// trap the user).
    public static func emergencyNotification(voice: CoachVoice) -> NotificationContent {
        let title = "Emergency unlock"
        let body: String
        switch voice {
        case .hype: body = "You've got this — tap to start the 60-second hold and get back in."
        // No lecture at the one exit the user must always have (docs/spec.md §8 rule 12): the
        // escape hatch gets a plain instruction in every voice.
        case .toughLove: body = "Tap to start the 60-second hold and get back in."
        case .chill: body = "No worries. Tap to start the 60-second hold."
        case .data: body = "Tap to start the 60-second emergency hold."
        }
        return NotificationContent(
            identifier: "zano.shield.emergency",
            title: title,
            body: body,
            deepLink: DeepLink.emergency
        )
    }

    // MARK: - Variant tables

    /// Used mid-sentence ("2 goals to unlock this app") for a category-level shield with no
    /// single app/site name to show — hence lowercase.
    private static let categoryFallbackName = "this app"

    /// The fact line while the last verification lands. Deliberately never "Unlocked" — the
    /// engine hasn't torn the shield down yet (see `Moment.verifying`).
    private static let verifyingTitle = "Checking your last goal…"

    /// Follows the fixed "Checking your last goal…" title, so none of these repeat it.
    private static let verifyingSubtitles: [CoachVoice: String] = [
        .hype: "Almost there. This clears any second.",
        .toughLove: "It's being verified. Hold on.",
        .chill: "Just a sec, then you're through.",
        .data: "Final goal event pending verification."
    ]

    /// Mode-neutral on purpose: in Earn Mode the last goal deposits minutes rather than
    /// "unlocking everything", so none of these promise a full unlock.
    private static let nearCompletionSubtitles: [CoachVoice: String] = [
        .hype: "Last one. It lands the second it's verified.",
        .toughLove: "Last one. Finish it.",
        .chill: "Last one, whenever you're ready.",
        .data: "Final goal. Applies on verification."
    ]

    /// "slip", never "miss" (docs/spec.md §8 rule 9). Titles here name the comeback; the subtitle
    /// (`CoachVoiceTone.missAcknowledgment`) carries the next smallest step.
    private static let afterMissTitles: [CoachVoice: [String]] = [
        .hype: ["Comeback day. Let's GO.", "Today's the bounce-back."],
        .toughLove: ["One slip. Not two.", "Comeback day. It starts now."],
        .chill: ["Fresh start today.", "New day, clean slate."],
        .data: ["Recovery day. 1 slip logged.", "Streak protection active."]
    ]

    /// The most-seen shield state's coach line (the title already names the app and the goals
    /// left). Built on the brand's one line — the star charges while you're off your phone — in
    /// each voice's shape (docs/design/writing-findings.md §2.2): Hype on the stakes, Tough Love
    /// states the fact and stops (no scolding), Chill gives permission, Data gives the rule.
    private static let midLockNudges: [CoachVoice: [String]] = [
        .hype: ["The star charges while you're off your phone. Go fill it.", "Every verified goal charges the star. Let's GO."],
        .toughLove: ["It'll still be here after the work's done.", "The star only charges off your phone."],
        .chill: ["It'll be here when you're done. No rush.", "The star charges while you're off your phone."],
        .data: ["Unlock triggers on goal verification.", "Star charge accrues while you're off your phone."]
    ]

    private static let showGoalsNotificationTitles: [CoachVoice: String] = [
        .hype: "Let's see those goals!",
        .toughLove: "Here's what's left.",
        .chill: "Your goals, no pressure.",
        .data: "Goal status"
    ]

    // MARK: - Variant rotation helpers

    /// A stable, non-random index derived from the calendar day (UTC epoch day number), so the
    /// same day always renders the same variant (reproducible screenshots/support requests)
    /// while still varying day to day.
    private static func dayIndex(on date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }

    private static func pick(_ variants: [String], at index: Int, fallback: @autoclosure () -> String) -> String {
        guard !variants.isEmpty else { return fallback() }
        return variants[index % variants.count]
    }
}
