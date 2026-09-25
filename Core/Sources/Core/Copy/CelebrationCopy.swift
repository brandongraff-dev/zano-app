// CelebrationCopy.swift
// Core / Copy
//
// `Copy.celebration` — every user-facing string for the unlock-celebration moment
// (`Core/Sources/Core/UI/Components/CelebrationBurst.swift`,
// `App/ZANO/Features/Celebration/UnlockCelebrationView.swift`), per docs/spec.md §16's P3 mockup
// ("burst of acid-green particles, headline 'Earned.', subline 'Workout verified · 42 min at the
// gym', a Time Bank bar filling to '2h 10m unlocked', small badge 'Comeback' appearing") and §8
// rule 4 (variable reward: "1 in ~6 unlocks triggers a surprise (badge, coin bonus, milestone
// animation, coach voice line)... Keep it tasteful").
//
// New area, added here rather than left as an "ASSUMED API" note in `UnlockCelebrationView.swift`
// for a future session to build (the pattern e.g. `FuelView.swift`/`LockSetupView.swift` use when
// a Copy area belongs to a session that doesn't own `Core/Sources/Core/Copy` itself): this
// directory was grepped before adding this file and nothing else on disk references
// `Copy.celebration.*`, so there is no other agent's assumption to collide with — and this task's
// own brief names the exact shape to use: the `Copy.<area>` umbrella pattern (`extension Copy {
// public enum <area> { ... } }`, see `Copy.swift`'s header and `Copy.onboarding`/`Copy.badges`/
// `Copy.trophyCase`/`Copy.cosmetics`, all same directory), never a flat standalone top-level enum
// (the shape `ShieldCopy.swift`/`WidgetCopy.swift` use instead) — the exact kind of mismatch a
// previous batch shipped as a real build break.

import Foundation

extension Copy {
    public enum celebration {

        /// Spec §16 P3 verbatim: "headline 'Earned.'". `Copy.onboarding.firstWinCelebrationTitle`
        /// (`OnboardingCopy.swift`, same directory) is the same word for onboarding's own
        /// first-win screen — a different subline shape (a streak line, not a goal-verification
        /// line) for a different screen. Kept as its own constant here rather than shared, the same
        /// way `Copy.trophyCase`/`Copy.badges` (same directory) each independently own small pieces
        /// of overlapping wording instead of reaching into each other's area.
        public static let headline = "Earned."

        /// Spec §16 P3 verbatim shape: "subline 'Workout verified · 42 min at the gym'". Both
        /// arguments are already caller-resolved strings — this never takes a `GoalType` itself
        /// (see `UnlockCelebrationView.goalName`'s own doc comment for why: resolving a type to a
        /// display name is each screen's own job, not this view's).
        ///
        /// - Parameters:
        ///   - goalName: e.g. `"Workout"`.
        ///   - detail: e.g. `"42 min at the gym"`. `nil` or empty collapses to just `"<goalName>
        ///     verified"` — not every goal type has a detail worth showing (e.g. a plain Tier-C
        ///     "cold shower" tap).
        public static func subline(goalName: String, detail: String?) -> String {
            guard let detail, !detail.isEmpty else { return "\(goalName) verified" }
            return "\(goalName) verified · \(detail)"
        }

        /// Spec §16 P3 verbatim shape: "a Time Bank bar filling to '2h 10m unlocked'" — the same
        /// wording `WidgetCopy.minutesRemaining(_:)` (`Core/Sources/Core/Copy/WidgetCopy.swift`)
        /// produces. Reimplemented here rather than calling that function: `WidgetCopy`'s own file
        /// header scopes it specifically to `Extensions/ZANOWidgets` (widget/Live-Activity
        /// surfaces), and this is a different, in-app feature area that happens to want the exact
        /// same sentence shape — not a shared dependency on that file.
        public static func timeBankUnlockedLabel(minutes: Int) -> String {
            // Never "0 min unlocked": with nothing banked the moment is still an unlock, so it
            // says that with no figure.
            guard minutes > 0 else { return appsUnlockedEyebrow }
            let hours = minutes / 60
            let mins = minutes % 60
            if hours > 0 && mins > 0 { return "\(hours)h \(mins)m unlocked" }
            if hours > 0 { return "\(hours)h unlocked" }
            return "\(mins) min unlocked"
        }

        /// VoiceOver label for the optional badge reveal (spec §16 P3: "small badge 'Comeback'
        /// appearing"; §8 rule 4's variable reward). `title` is already caller-resolved display
        /// copy — the canonical `Badge.key` → title resolver is `Copy.badges.title(forKey:)`
        /// (`TrophyCosmeticsCopy.swift`, same directory); this file doesn't call that itself, and
        /// neither does `UnlockCelebrationView` (see that type's `UnlockCelebrationBadge` doc
        /// comment) — badge resolution is the presenting screen's job.
        public static func badgeRevealAccessibilityLabel(title: String) -> String {
            "Bonus badge earned: \(title)"
        }

        /// The small eyebrow above "Earned." on the unlock moment: what just happened, in plain
        /// words, before the brand word lands.
        public static let appsUnlockedEyebrow = "Apps unlocked"

        /// The caption beside the Time Bank figure on the unlock moment ("2h 10m  in your Time
        /// Bank"). The figure itself is formatted by the view with the system `Duration` style.
        public static let timeBankFigureCaption = "in your Time Bank"

        /// Dismiss control for the celebration once it's played. Deliberately not `Copy.common.
        /// continueButtonLabel` (`CommonCopy.swift`, same directory): this screen is closing a
        /// moment, not advancing an onboarding step. "Done" (was "Nice"): a button label should be a
        /// verb-ish action, not a reaction — and "Nice" read oddly to Tough Love and Data users. The
        /// "Earned." headline stays fixed across voices; a per-voice coach line under it needs a
        /// voice parameter (docs/design/writing-findings.md §3.6).
        public static let dismissButtonLabel = "Done"
    }
}

// MARK: - Variable reward reveal (spec §8 rule 4, `Retention/VariableReward.swift`)

extension Copy.celebration {
    /// The reveal's eyebrow.
    public static let surpriseEyebrow = "Surprise!"
    /// "+50 coins".
    public static func surpriseCoinsTitle(_ coins: Int) -> String { "+\(coins) coins" }
    public static let surpriseCoinsDetail = "For the Cosmetics Shop."
    /// The one-time badge. Matches `Copy.badges.title(forKey: "lucky_unlock")`'s fallback.
    public static let surpriseBadgeTitle = "Lucky Unlock badge"
    public static let surpriseBadgeDetail = "It's in your Trophy Case."
    public static func surpriseAccessibilityLabel(_ text: String) -> String { "Surprise. \(text)" }

    /// A bonus coach line, `VariableReward.coachLineCount` per voice.
    public static func surpriseCoachLine(voice: CoachVoice, index: Int) -> String {
        let lines: [String]
        switch voice {
        case .hype:
            lines = [
                "THAT'S how it's done. Enjoy every minute.",
                "Earned, not given. You're on a roll.",
                "Another one in the books. Let's keep it moving.",
            ]
        case .toughLove:
            lines = [
                "You said you'd do it. You did. Good.",
                "No shortcuts today. That's the point.",
                "Earned the hard way. Keep that standard.",
            ]
        case .chill:
            lines = [
                "Nice work. Take it easy for a bit.",
                "Done and dusted. Enjoy the break.",
                "Steady wins it. Go enjoy your apps.",
            ]
        case .data:
            lines = [
                "Goals verified. Unlock logged. Consistency up.",
                "Another earned day on the chart.",
                "Plan met. That's a data point you made.",
            ]
        }
        return lines[((index % lines.count) + lines.count) % lines.count]
    }
    public static let surpriseCoachDetail = "A bonus word from your coach."
}
