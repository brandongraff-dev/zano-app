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

    /// A streak mention shaped like each voice would actually say it. Hype puts the fire next to
    /// the count (never instead of it); Tough Love states the stakes flatly; Chill undersells it;
    /// Data reads it as a label and value. `streak == 0` omits the streak clause entirely (no
    /// voice brags about a zero, and Tough Love doesn't kick someone who has no streak to lose).
    /// Every form says "streak" and "day(s)" in words so VoiceOver reads a real sentence, and
    /// day(s) is singular-aware ("1 day", never "1 days").
    public static func streakClause(_ voice: CoachVoice, streak: Int) -> String? {
        guard streak > 0 else { return nil }
        let dayWord = streak == 1 ? "day" : "days"
        switch voice {
        case .hype: return "\(streak)-day streak 🔥"
        case .toughLove: return "\(streak)-day streak on the line."
        case .chill: return "\(streak) \(dayWord) in. Nice and steady."
        case .data: return "Streak: \(streak) \(dayWord)."
        }
    }

    /// How each voice phrases "N goals still open," singular-aware. Used for the default
    /// mid-lock Living Shield moment (docs/spec.md §5.1).
    ///
    /// Voice shape (docs/design/writing-findings.md §2.2): Hype lands on the stakes, Tough Love
    /// states the fact and stops (no bare commands, no scolding), Chill gives permission, Data
    /// gives label-and-value.
    public static func goalsRemainingClause(_ voice: CoachVoice, remaining: Int) -> String {
        let goalWord = remaining == 1 ? "goal" : "goals"
        switch voice {
        case .hype: return "\(remaining) \(goalWord) between you and everything."
        case .toughLove: return "\(remaining) \(goalWord) left. That's the whole list."
        case .chill: return "\(remaining) \(goalWord) left, at your pace."
        case .data: return "\(remaining) \(goalWord) open."
        }
    }

    /// How each voice acknowledges a slip without being punishing (docs/spec.md §5.6 "the app
    /// makes the comeback day feel special... shield copy that acknowledges it" and §8 rules 9 and
    /// 10: a slip is "slipped", never "missed", is never followed by a threat, and is always
    /// followed by the next smallest step).
    ///
    /// Every voice ends on the same step: start with the smallest goal. This deliberately does
    /// NOT append the total goals left (the heaviest possible framing for someone who just slipped)
    /// — `ShieldCopy.content(for:)` relies on that and adds nothing after this string. A more
    /// specific step ("One focus session and you're back") needs the shield to know which goal is
    /// smallest; see docs/design/writing-findings.md §3.3.
    public static func missAcknowledgment(_ voice: CoachVoice) -> String {
        switch voice {
        case .hype: "Yesterday slipped. TODAY is the comeback. Start with your smallest goal."
        case .toughLove: "Yesterday slipped. Today counts. Start with your smallest goal."
        case .chill: "Yesterday slipped, and that's fine. Start with the smallest goal when you're ready."
        case .data: "Streak holds through one slip. Start with your smallest goal."
        }
    }
}
