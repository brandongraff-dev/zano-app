// CoachVoice.swift
// Core / Copy
//
// The `CoachVoice` *type* already exists — `Core/Sources/Core/Models/User.swift` mirrors
// `users.coach_voice` (`hype | tough_love | chill | data`) exactly, since that's the value that
// round-trips with Postgres and is the source of truth for which voice a user has picked
// (docs/spec.md §13, §5.13). This file does not redeclare it — Core is a single Swift module, so
// a second `enum CoachVoice` here would collide with that one at compile time. Instead this file
// is where a voice turns into *tone*: the small set of copy-shaping rules ("Hype leads with an
// exclamation and a verb", "Data reads like a stat line") that any Copy file — `ShieldCopy` today,
// future nudge/widget/onboarding copy later — draws on so all four voices (docs/spec.md §5.13:
// Hype / Tough Love / Chill / Data) stay consistent instead of every call site inventing its own
// punctuation. Kept intentionally small: only what `ShieldCopy` actually needs right now (CLAUDE.md
// "don't add abstractions... beyond what the current session's scope requires").

import Foundation

extension CoachVoice {

    /// Parses a `SharedDefaults.coachVoice` raw string back into the strong type.
    ///
    /// `SharedDefaults.coachVoice` (`Core/Sources/Core/Store/SharedDefaults.swift`) is documented
    /// as storing "whatever raw values the Copy module's voice type uses" and gives `"hype"`,
    /// `"toughLove"`, `"chill"`, `"data"` as its examples — note `"toughLove"` (camelCase), not
    /// this type's actual `CoachVoice.toughLove.rawValue` (`"tough_love"`, matching the Postgres
    /// check constraint in docs/spec.md §13). That's very likely that comment describing the case
    /// name rather than the literal stored value, not a second, divergent encoding — `StreakEngine`
    /// /onboarding write `CoachVoice.rawValue` strings everywhere else (spec §13 keeps local and
    /// remote shapes identical). This parses defensively either way: raw value first, then case
    /// name (case-insensitively, snake_case or camelCase), so a shield/widget render never
    /// silently drops to the wrong voice over a punctuation mismatch in a stored string.
    /// Falls back to `.hype` — onboarding's suggested default (docs/spec.md §7) — for anything
    /// unparseable, which keeps every caller total instead of `Optional`-chaining a voice lookup
    /// through render code that must never crash (a Shield/Widget extension has no error UI).
    public static func from(sharedDefaultsRaw raw: String) -> CoachVoice {
        if let exact = CoachVoice(rawValue: raw) {
            return exact
        }
        let normalized = raw
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        return CoachVoice.allCases.first {
            $0.rawValue.replacingOccurrences(of: "_", with: "").lowercased() == normalized
        } ?? .hype
    }

    /// Display name for the voice picker (onboarding §7, Settings §15). Title-cased, matching
    /// how docs/spec.md §5.13 names each voice ("Hype", "Tough Love", "Chill", "Data").
    public var displayName: String {
        switch self {
        case .hype: "Hype"
        case .toughLove: "Tough Love"
        case .chill: "Chill"
        case .data: "Data"
        }
    }

    /// The exact sample line docs/spec.md §5.13 uses to describe each voice — reused verbatim in
    /// the onboarding voice picker so what the user previews is what they actually get, not a
    /// paraphrase that drifts from spec over time.
    public var sampleLine: String {
        switch self {
        case .hype: "LET'S GO, 3 more grams"
        case .toughLove: "You said 4 days. It's Thursday. You're at 2."
        case .chill: "Whenever you're ready, the gym's open till 11"
        case .data: "Protein 72/150g. Avg completion 81% this month."
        }
    }
}

/// Tone-shaping helpers shared by every voice-aware Copy file. Pure string functions only — no
/// state, no App Group reads — so `ShieldCopy` (and later callers) can compose them freely and
/// they stay trivially unit-testable without a `ModelContainer`/`UserDefaults` suite.
public enum CoachVoiceTone: Sendable {

    /// A streak mention shaped like each voice would actually say it. Hype leads with fire and an
    /// exclamation; Tough Love states it flatly; Chill undersells it; Data reads it as a bare
    /// stat. `streak == 0` omits the streak clause entirely (no voice brags about a zero, and
    /// Tough Love doesn't kick someone who has no streak to lose).
    public static func streakClause(_ voice: CoachVoice, streak: Int) -> String? {
        guard streak > 0 else { return nil }
        switch voice {
        case .hype: "Streak: \(streak) 🔥"
        case .toughLove: "\(streak)-day streak on the line."
        case .chill: "\(streak) days in, no rush."
        case .data: "Streak \(streak)d."
        }
    }

    /// How each voice phrases "N goals still open," singular-aware. Used for the default
    /// mid-lock Living Shield moment (docs/spec.md §5.1).
    public static func goalsRemainingClause(_ voice: CoachVoice, remaining: Int) -> String {
        let goalWord = remaining == 1 ? "goal" : "goals"
        switch voice {
        case .hype: "\(remaining) \(goalWord) between you and everything."
        case .toughLove: "\(remaining) \(goalWord) left. Go do them."
        case .chill: "\(remaining) \(goalWord) whenever you're ready."
        case .data: "\(remaining) \(goalWord) open."
        }
    }

    /// How each voice acknowledges a miss without being punishing (docs/spec.md §5.6 "the app
    /// makes the comeback day feel special... shield copy that acknowledges it" — and CLAUDE.md's
    /// "no restrictive/shaming copy" spirit: acknowledge, don't scold).
    public static func missAcknowledgment(_ voice: CoachVoice) -> String {
        switch voice {
        case .hype: "Yesterday slipped — doesn't matter, TODAY'S the comeback."
        case .toughLove: "Yesterday slipped. Never miss twice. Handle today."
        case .chill: "Yesterday slipped, that's fine. Today's a reset."
        case .data: "Yesterday: missed. 2-in-a-row is what breaks a streak — today doesn't have to."
        }
    }
}
