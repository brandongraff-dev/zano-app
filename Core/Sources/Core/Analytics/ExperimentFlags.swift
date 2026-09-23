// ExperimentFlags.swift
// Core / Analytics
//
// docs/spec.md §23 ("Metrics & Experiments") names ten concrete experiments to run first:
// paywall placement (after plan vs after first win), trial length (3 vs 7 days), starting
// difficulty (70% vs 85% of target), shield copy voice, widget prompt timing, Earn Mode default
// on/off, onboarding length (10 vs 14 screens), freeze count, nudge cap (1 vs 2), and the Plan B
// offer threshold. This file turns that list into ten named, typed flags rather than ten bare
// PostHog string keys scattered across call sites — a call site says
// `ExperimentFlags.paywallPlacement.resolve()` and gets back a real Swift `enum` case, never a
// stringly-typed flag value it has to re-validate.
//
// This builds on `Analytics.swift`'s PostHog wrapper (`featureFlagVariant(key:)` etc.) rather than
// talking to `PostHogSDK` directly — same reasoning as that file's own header: it's the one place
// that has to reason about the SDK not being linked yet (`#if canImport(PostHog)`), and every
// other file, including this one, should go through it instead of duplicating that guard.
// `Analytics.featureFlagVariant(key:)` already returns `nil` for "not resolved yet" (SDK not
// linked, `setup` not called yet, or PostHog hasn't fetched this device's flags over the network
// yet) instead of coercing that to a specific arm, which is exactly the case each experiment
// below has its own `defaultVariant` for.
//
// Every variant below is a real Swift value, not a raw PostHog string — but each `Variant`'s
// `rawValue` is still the literal string PostHog is configured with for that flag, since that's
// what `Analytics.featureFlagVariant(key:)` hands back over the wire and what `resolve()`
// (below) parses. When setting these ten flags up in the PostHog dashboard, the variant keys must
// match the `rawValue`s here exactly.
//
// Wiring an experiment's `resolve()` into the screen/engine it actually controls (paywall
// placement into the onboarding flow, starting difficulty into the adaptive engine, freeze count
// into `StreakEngine`, ...) belongs to the session that owns each of those surfaces — same
// division of labor `Analytics.swift` already documents for its own event call sites. This file
// only defines the flags and their safe-before-PostHog-loads defaults.

import Foundation

// MARK: - ExperimentFlag

/// A single PostHog experiment: a stable feature-flag key, a closed set of named variants, and
/// the variant to fall back to when the flag service hasn't resolved yet.
///
/// Conforming types are plain value types (see the ten below) — the protocol exists so
/// `resolve()` (below) is written once instead of once per experiment, and so every experiment
/// shares the exact same "unresolved → default" fallback rule instead of each one reimplementing
/// its own `?? someDefault`.
public protocol ExperimentFlag: Sendable {
    /// The experiment's set of named arms. Always `String`-backed because that's what a PostHog
    /// multivariate feature flag's variant key is, and always `CaseIterable` so a future
    /// debug/QA surface can list every arm without this file exposing a second, parallel list.
    associatedtype Variant: RawRepresentable & CaseIterable & Sendable where Variant.RawValue == String

    /// The PostHog feature flag key this experiment reads, e.g. `"paywall_placement"`. Must match
    /// the key configured in the PostHog dashboard exactly — PostHog keys are conventionally
    /// snake_case, which every key below follows.
    var key: String { get }

    /// The variant to use before PostHog's flags have loaded, when the PostHog SDK isn't linked
    /// yet (`#if canImport(PostHog)` false), or when PostHog returns a value that doesn't match
    /// any case of `Variant` (e.g. the dashboard flag was deleted or renamed after this file
    /// shipped). Chosen to match whatever ZANO already ships as its non-experimental behavior —
    /// each concrete flag below documents exactly why its default is what it is.
    var defaultVariant: Variant { get }
}

extension ExperimentFlag {
    /// Resolves this experiment's active variant for the current user.
    ///
    /// Reads `Analytics.shared.featureFlagVariant(key:)` — itself a documented no-op returning
    /// `nil` when PostHog isn't linked, hasn't been set up, or hasn't loaded flags for this device
    /// yet — and turns that `nil`, or any string PostHog returns that doesn't map back to a
    /// `Variant` case, into `defaultVariant`. Callers always get a total, non-optional variant;
    /// nobody downstream has to know PostHog was involved at all.
    ///
    /// Safe to call every time a value is needed (e.g. once per screen render) — it does not
    /// cache, so it always reflects the latest flags PostHog has resolved, including right after
    /// `Analytics.shared.reloadFeatureFlags()`.
    public func resolve() -> Variant {
        guard let raw = Analytics.shared.featureFlagVariant(key: key) else { return defaultVariant }
        return Variant(rawValue: raw) ?? defaultVariant
    }
}

// MARK: - 1. Paywall placement

/// docs/spec.md §23, experiment 1/10: "paywall placement (after plan vs after first win)".
///
/// Today's shipped flow (spec §7) shows the paywall as screen 13, after the "Your Lock-In Plan"
/// reveal at screen 10 — there is no shipped "after first win" flow to fall back to, so
/// `.afterPlan` is the only safe default until this experiment is actually configured in
/// PostHog.
public struct PaywallPlacementExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        /// Paywall shown immediately after the plan-reveal screen, before the user has completed
        /// anything — today's shipped flow.
        case afterPlan = "after_plan"
        /// Paywall deferred until after the user's first earned unlock (their "first win"),
        /// trading a longer time-to-paywall for showing the product actually working first.
        case afterFirstWin = "after_first_win"
    }

    public let key = "paywall_placement"
    public let defaultVariant: Variant = .afterPlan

    public init() {}
}

// MARK: - 2. Trial length

/// docs/spec.md §23, experiment 2/10: "trial length" (§21: "Test 3-day vs 7-day").
///
/// Ships today as a 7-day trial (spec §7 screen 13, §21) — `.sevenDay` is the default so an
/// unresolved flag matches current shipped behavior exactly.
public struct TrialLengthExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case threeDay = "3_day"
        case sevenDay = "7_day"

        /// The trial length this variant represents, for anything that needs the actual number
        /// (RevenueCat offering selection, the paywall's "we'll remind you N days before it
        /// ends" copy) rather than the variant name.
        public var days: Int {
            switch self {
            case .threeDay: 3
            case .sevenDay: 7
            }
        }
    }

    public let key = "trial_length_days"
    public let defaultVariant: Variant = .sevenDay

    public init() {}
}

// MARK: - 3. Starting difficulty

/// docs/spec.md §23, experiment 3/10: "starting difficulty (70% vs 85% of target)".
///
/// Spec §7 screen 10 describes the shipped plan as starting "deliberately below stated target"
/// (§16's mockup prompt for that same screen calls it "Starting easy on purpose") without pinning
/// an exact number — `.seventyPct`, the lower of the two tested values, is the safer default: it
/// matches that "start easy" intent most conservatively, and an adaptive engine that starts a new
/// user too hard risks the very first day feeling like a miss (spec §9.1's whole point is climbing
/// *into* difficulty over time, not starting there).
public struct StartingDifficultyExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case seventyPct = "70_pct"
        case eightyFivePct = "85_pct"

        /// The starting bar as a fraction of the user's stated target (e.g. `0.70`), for the
        /// Adaptive Goal Engine (spec §9.1) to multiply against a goal's target value directly.
        public var fractionOfTarget: Double {
            switch self {
            case .seventyPct: 0.70
            case .eightyFivePct: 0.85
            }
        }
    }

    public let key = "starting_difficulty_pct"
    public let defaultVariant: Variant = .seventyPct

    public init() {}
}

// MARK: - 4. Shield copy voice

/// docs/spec.md §23, experiment 4/10: "shield copy voice".
///
/// Every voice already exists as `CoachVoice` (`Core/Sources/Core/Models/User.swift`) — this
/// experiment does not invent a second voice enum, it only decides which voice a user who hasn't
/// picked one yet sees by default (onboarding §7 lets them choose explicitly; this only covers
/// the window/cohort where that choice is itself being A/B tested). `Variant`'s raw values match
/// `CoachVoice.rawValue` exactly (`CoachVoice.toughLove.rawValue == "tough_love"`, per
/// `Core/Sources/Core/Models/User.swift`), so `coachVoice` below is a lossless, unconditional
/// mapping rather than a fuzzy string match.
///
/// `CoachVoice.swift`'s own documentation already calls out `.hype` as "onboarding's suggested
/// default" — this experiment's default matches that exactly, so an unresolved flag never
/// contradicts what onboarding already tells the user to expect.
public struct ShieldCopyVoiceExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case hype
        case toughLove = "tough_love"
        case chill
        case data

        /// This variant as the real `CoachVoice` every Copy file (`ShieldCopy`, `CoachVoiceTone`,
        /// …) already knows how to render — never re-derive tone logic from this raw variant
        /// directly.
        public var coachVoice: CoachVoice {
            switch self {
            case .hype: .hype
            case .toughLove: .toughLove
            case .chill: .chill
            case .data: .data
            }
        }
    }

    public let key = "shield_copy_voice_default"
    public let defaultVariant: Variant = .hype

    public init() {}
}

// MARK: - 5. Widget prompt timing

/// docs/spec.md §23, experiment 5/10: "widget prompt timing".
///
/// Spec §7 screen 14 ("First win") already ships the widget prompt at this exact moment —
/// "Immediate loop completion. Streak = Day 1. Confetti. Prompt to add the Home Screen widget
/// with an animated guide" — right after the user's first earned unlock, not cold during
/// onboarding before they have anything to show. `.afterFirstUnlock` matches that shipped
/// placement exactly.
public struct WidgetPromptTimingExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        /// Prompted during onboarding, before the user has earned anything yet.
        case afterOnboarding = "after_onboarding"
        /// Prompted right after the user's first earned unlock.
        case afterFirstUnlock = "after_first_unlock"
    }

    public let key = "widget_prompt_timing"
    public let defaultVariant: Variant = .afterFirstUnlock

    public init() {}
}

// MARK: - 6. Earn Mode default

/// docs/spec.md §23, experiment 6/10: "Earn Mode default on/off" (§28 "Open Questions" lists the
/// same thing: "Earn Mode default: on or off for new users?").
///
/// Spec §21 lists Earn Mode under **Pro**, not the free tier's baseline feature set — `.off` is
/// the conservative default that matches that gating (a brand-new free-tier user should not land
/// in a Pro-tier mechanic before this experiment has actually been configured) and avoids
/// surprising a first-session user with a draining Time Bank bar (spec §5.2) they didn't opt into.
public struct EarnModeDefaultExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case on
        case off

        /// This variant as a plain `Bool`, for wherever a new user's `earnModeEnabled`-shaped
        /// field gets initialized.
        public var isEnabledByDefault: Bool { self == .on }
    }

    public let key = "earn_mode_default_enabled"
    public let defaultVariant: Variant = .off

    public init() {}
}

// MARK: - 7. Onboarding length

/// docs/spec.md §23, experiment 7/10: "onboarding length (10 vs 14 screens)".
///
/// Spec §17's session list and §7's own screen table both describe onboarding as shipping with 14
/// screens ("Onboarding (14 screens) + permission priming + RevenueCat paywall") — `.fourteen` is
/// the default so an unresolved flag matches the screen count onboarding actually ships with
/// today, not a shorter flow that doesn't exist yet.
public struct OnboardingLengthExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case ten = "10_screens"
        case fourteen = "14_screens"

        /// The screen count this variant represents.
        public var screenCount: Int {
            switch self {
            case .ten: 10
            case .fourteen: 14
            }
        }
    }

    public let key = "onboarding_length_screens"
    public let defaultVariant: Variant = .fourteen

    public init() {}
}

// MARK: - 8. Freeze count

/// docs/spec.md §23, experiment 8/10: "freeze count".
///
/// Spec §4 states the shipped free-tier baseline explicitly: "Streaks with 1 freeze/week (free) /
/// 3 freezes (paid)". This experiment is about the *free* tier's weekly freeze allowance (the paid
/// tier's count is a monetization lever, not an experiment on this list) — `.one` matches that
/// shipped free-tier default exactly.
public struct FreezeCountExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case one
        case two

        /// The free-tier weekly freeze allowance this variant represents, for `StreakEngine`'s
        /// `freezes_left` reset logic (spec §13's `streaks` table).
        public var freezesPerWeek: Int {
            switch self {
            case .one: 1
            case .two: 2
            }
        }
    }

    public let key = "streak_freeze_count_free"
    public let defaultVariant: Variant = .one

    public init() {}
}

// MARK: - 9. Nudge cap

/// docs/spec.md §23, experiment 9/10: "nudge cap (1 vs 2)" — the daily ceiling on squad nudges
/// (spec §5.7 "Squads & Duels": "one-tap 'nudge' that sends a push with the sender's face") and/or
/// risk-triggered retention nudges (spec §9.2: "schedule a nudge at the user's historically best
/// action hour") a single user can receive in a day.
///
/// `.one` is the conservative default: CLAUDE.md's "no restrictive/shaming" spirit extends to not
/// over-notifying by default before this has actually been tuned against real unsubscribe/opt-out
/// data.
public struct NudgeCapExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        case one
        case two

        /// The maximum nudge pushes a single user should receive per day under this variant.
        public var maxPerDay: Int {
            switch self {
            case .one: 1
            case .two: 2
            }
        }
    }

    public let key = "nudge_cap_per_day"
    public let defaultVariant: Variant = .one

    public init() {}
}

// MARK: - 10. Plan B offer threshold

/// docs/spec.md §23, experiment 10/10: "Plan B offer threshold" — spec §9.2's risk rule ("risk >
/// threshold at 9 AM → offer Plan B in the widget and shield copy") without a pinned numeric
/// threshold, and spec §5.5 calls Plan B "the single biggest retention lever: it stops one bad day
/// from becoming a quit."
///
/// Two named risk-threshold arms rather than a raw `Double` flag, matching every other experiment
/// in this file being a closed, named variant set instead of an unbounded numeric dial. `.moderate`
/// (the lower threshold, so Plan B is offered *more* readily) is the default — given spec §5.5's
/// framing, under-offering the single biggest retention lever by defaulting to the stricter
/// threshold is the riskier failure mode while this experiment is unconfigured.
public struct PlanBOfferThresholdExperiment: ExperimentFlag {
    public enum Variant: String, CaseIterable, Sendable {
        /// Offer Plan B whenever the adaptive engine's predicted slip risk (spec §9.2) is above
        /// 50% — offered more readily.
        case moderate
        /// Offer Plan B only when predicted slip risk is above 70% — offered more sparingly, for
        /// users who might find a frequent Plan B offer itself demotivating.
        case high

        /// The risk-score cutoff above which Plan B is offered under this variant, as a
        /// probability in `0...1` — spec §9.2 ("Slip Prediction") describes its output as a score
        /// compared against a threshold ("risk > threshold at 9 AM") without pinning its exact
        /// range; `0...1` is this file's own modeling choice, matching the natural output range
        /// of the gradient-boosted-trees/logistic-regression classifier §9.2 specifies. Whichever
        /// session wires the real `/risk` endpoint (spec §17 session 12, `feat/ml`) should adjust
        /// this scale if the shipped model's output range ends up different.
        public var riskThreshold: Double {
            switch self {
            case .moderate: 0.5
            case .high: 0.7
            }
        }
    }

    public let key = "plan_b_offer_risk_threshold"
    public let defaultVariant: Variant = .moderate

    public init() {}
}

// MARK: - ExperimentFlags

/// Namespace holding one instance of each of spec §23's "First 10 experiments" — the only place
/// call sites should reach for an experiment (`ExperimentFlags.paywallPlacement.resolve()`, not a
/// bare `PaywallPlacementExperiment()`), so every experiment is discoverable from one type instead
/// of call sites having to know each concrete struct's name.
public enum ExperimentFlags {
    public static let paywallPlacement = PaywallPlacementExperiment()
    public static let trialLength = TrialLengthExperiment()
    public static let startingDifficulty = StartingDifficultyExperiment()
    public static let shieldCopyVoice = ShieldCopyVoiceExperiment()
    public static let widgetPromptTiming = WidgetPromptTimingExperiment()
    public static let earnModeDefault = EarnModeDefaultExperiment()
    public static let onboardingLength = OnboardingLengthExperiment()
    public static let freezeCount = FreezeCountExperiment()
    public static let nudgeCap = NudgeCapExperiment()
    public static let planBOfferThreshold = PlanBOfferThresholdExperiment()

    /// Every experiment's currently-resolved variant, keyed by its PostHog flag key (e.g.
    /// `"paywall_placement"` → `"after_plan"`) rather than a display name, so this can be merged
    /// straight into a `capture(event:properties:)` properties dictionary
    /// (`Analytics.shared.capture(event: "app_launched", properties: ExperimentFlags.currentAssignments())`)
    /// and every product event ends up correlatable with which arm of every running experiment the
    /// user was in — without every call site re-deriving that list by hand, and without waiting on
    /// PostHog's own `$feature/<key>` event-enrichment round trip.
    ///
    /// Always total: falls back to each experiment's `defaultVariant` exactly like `resolve()`
    /// does, so this never has a missing key even before PostHog has loaded.
    public static func currentAssignments() -> [String: String] {
        [
            paywallPlacement.key: paywallPlacement.resolve().rawValue,
            trialLength.key: trialLength.resolve().rawValue,
            startingDifficulty.key: startingDifficulty.resolve().rawValue,
            shieldCopyVoice.key: shieldCopyVoice.resolve().rawValue,
            widgetPromptTiming.key: widgetPromptTiming.resolve().rawValue,
            earnModeDefault.key: earnModeDefault.resolve().rawValue,
            onboardingLength.key: onboardingLength.resolve().rawValue,
            freezeCount.key: freezeCount.resolve().rawValue,
            nudgeCap.key: nudgeCap.resolve().rawValue,
            planBOfferThreshold.key: planBOfferThreshold.resolve().rawValue,
        ]
    }
}
