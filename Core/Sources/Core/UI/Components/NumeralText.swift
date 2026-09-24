// NumeralText.swift
// Core / UI / Components
//
// The numeral system spec §15 asks for ("big numerals for grams/minutes/streak") and the app never
// delivered: across the screens the three headline numbers of the product — protein grams, focus /
// Time Bank minutes, streak — rendered at 13–17pt in muted grey, because every value arrives as one
// pre-composed `String` ("72/150g", "2h 10m unlocked") and a plain `Text` cannot make the digits
// louder than their unit. (docs/design/typography-color-findings.md T3, composition-audit.md S-1.)
//
// `NumeralText` takes those same caller-composed strings unchanged and styles the runs: digits in
// the rounded, monospaced numeral face at the requested size; units ("g", "min", "/150g") in the
// same face at a fraction of the size and in a quieter color, on a shared baseline; trailing words
// ("unlocked", "goals") in the unit style. It never rewrites, reorders or translates the string —
// only styles it — so all copy still comes from `Copy` (CLAUDE.md), and VoiceOver reads the
// original string.
//
// Everything here scales with Dynamic Type (a `Font` value cannot hold `@ScaledMetric`, which is
// why the fixed-size `Theme.Typography.numeral*()` fonts cannot do this on their own), clamped so
// a 72pt hero does not become 130pt at AX5.

import SwiftUI
import Foundation

// MARK: - Parsing

/// Splits a caller-composed value string into a numeric lead (number and unit runs) and a
/// remainder of plain words. Pure and side-effect free so it is trivially unit-testable.
///
/// The lead is the longest prefix of whitespace-separated tokens that are either numeric ("2h",
/// "10m", "1,020g", "$39.99/yr", "72/150g", "10:30") or a known unit word directly after a bare
/// number ("40 min", "4 of 6"). Anything else — including English words that merely *look* short
/// like "goal" — ends the lead, so "1 goal left" leads with "1" and leaves "goal left" as words.
enum ValueTextParser {

    enum RunKind: Equatable, Sendable {
        case number
        case unit
        case space
    }

    struct Run: Equatable, Sendable {
        let text: String
        let kind: RunKind
    }

    struct Parsed: Equatable, Sendable {
        /// The numeric lead, in order. Empty when the string has no numeric lead.
        let runs: [Run]
        /// The words after the lead ("unlocked", "goals"), space-joined; the whole string when
        /// there is no lead.
        let remainder: String

        var hasNumber: Bool { runs.contains { $0.kind == .number } }

        /// The lead re-joined as plain text ("2h 10m"). Used for the accessibility label when the
        /// remainder is shown elsewhere.
        var leadText: String { runs.map(\.text).joined() }
    }

    /// Words that may follow a bare number and read as its unit. Deliberately a whitelist:
    /// a length heuristic would swallow "goal" in "1 goal left".
    private static let unitWords: Set<String> = [
        "h", "hr", "hrs", "hour", "hours", "m", "min", "mins", "minute", "minutes",
        "s", "sec", "secs", "d", "day", "days", "wk", "wks", "week", "weeks",
        "g", "kg", "mg", "ml", "l", "oz", "lb", "lbs", "km", "mi",
        "x", "of", "am", "pm", "%", "kcal", "cal", "reps", "steps"
    ]

    private static let prefixSymbols: Set<Character> = ["$", "€", "£", "¥", "₹", "+", "-", "−"]

    static func parse(_ text: String) -> Parsed {
        let tokens = text
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .map(String.init)

        var runs: [Run] = []
        var consumed = 0
        var previousWasBareNumber = false

        for token in tokens {
            if let (number, suffix) = splitNumericToken(token) {
                if !runs.isEmpty { runs.append(Run(text: " ", kind: .space)) }
                runs.append(Run(text: number, kind: .number))
                if !suffix.isEmpty { runs.append(Run(text: suffix, kind: .unit)) }
                previousWasBareNumber = suffix.isEmpty
                consumed += 1
            } else if previousWasBareNumber, unitWords.contains(token.lowercased()) {
                runs.append(Run(text: " ", kind: .space))
                runs.append(Run(text: token, kind: .unit))
                previousWasBareNumber = false
                consumed += 1
            } else {
                break
            }
        }

        guard consumed > 0 else { return Parsed(runs: [], remainder: text) }
        let remainder = tokens.dropFirst(consumed).joined(separator: " ")
        return Parsed(runs: runs, remainder: remainder)
    }

    /// Splits a token into its leading number (optional sign/currency, digits, and "," "." ":"
    /// only where a digit follows) and whatever trails it. `nil` when the token has no digits.
    /// "1,020g" → ("1,020", "g"); "72/150g" → ("72", "/150g"); "$39.99/yr" → ("$39.99", "/yr");
    /// "10:30" → ("10:30", ""); "10," → ("10", ",").
    static func splitNumericToken(_ token: String) -> (String, String)? {
        let chars = Array(token)
        var index = 0
        var number = ""

        while index < chars.count, prefixSymbols.contains(chars[index]) {
            number.append(chars[index])
            index += 1
        }

        let digitsStart = index
        while index < chars.count {
            let character = chars[index]
            if isASCIIDigit(character) {
                number.append(character)
                index += 1
            } else if character == "." || character == "," || character == ":",
                      index + 1 < chars.count, isASCIIDigit(chars[index + 1]), index > digitsStart {
                number.append(character)
                index += 1
            } else {
                break
            }
        }

        guard index > digitsStart else { return nil }
        return (number, String(chars[index...]))
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

/// Splits a progress string of the form "value/target unit" — the shape every ring value has
/// ("72/150g", "25/50 min", "1250/3000ml", "3200/8000") — into the value and the target-and-unit
/// tail ("72", "/150g"), so a ring can show the value as its center numeral. Language-neutral by
/// construction: the tail keeps the caller's own slash and unit, so no word ("of") is invented.
enum ProgressTextSplit {
    static func split(_ text: String) -> (value: String, unit: String)? {
        guard let slash = text.firstIndex(of: "/") else { return nil }
        let value = text[..<slash].trimmingCharacters(in: .whitespaces)
        let rest = text[slash...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, rest.count > 1 else { return nil }
        guard value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        return (value, rest)
    }
}

// MARK: - View

/// Renders a caller-composed value string with a big numeral and a quiet unit. See the file
/// header. `NumeralText("2h 10m unlocked", size: .hero)` reads "2h 10m" in 72pt heavy digits with
/// small "h"/"m" and a small "unlocked" on the same baseline; a string with no numeric lead
/// ("Time Bank empty") falls back to plain text at a matching text style.
public struct NumeralText: View {

    /// The four numeral tiers (`Theme.Typography.numeral*`).
    public enum Size: Sendable {
        case hero, large, medium, small

        fileprivate var numberSize: CGFloat {
            switch self {
            case .hero: 88
            case .large: 48
            case .medium: 28
            case .small: 17
            }
        }

        fileprivate var unitSize: CGFloat {
            switch self {
            case .hero: 24
            case .large: 18
            case .medium: 15
            case .small: 13
            }
        }

        fileprivate var numberWeight: Font.Weight {
            switch self {
            case .hero: .heavy
            case .large, .medium: .bold
            case .small: .semibold
            }
        }

        fileprivate var tracking: CGFloat {
            switch self {
            case .hero: -0.5
            case .large: -0.3
            case .medium, .small: 0
            }
        }

        fileprivate var fallbackFont: Font {
            switch self {
            case .hero: Theme.Typography.titleLarge
            case .large: Theme.Typography.title
            case .medium: Theme.Typography.headline
            case .small: Theme.Typography.body
            }
        }
    }

    /// What to do with the words after the numeric lead.
    public enum Remainder: Sendable {
        /// Render them after the numbers, in the unit style, on the same baseline.
        case inline
        /// Do not render them — the caller shows `NumeralText.remainder(of:)` itself (e.g. as a
        /// caption under the number, in a narrow column that cannot fit both on one line).
        case hidden
    }

    private let text: String
    private let size: Size
    private let color: Color
    private let unitColor: Color
    private let remainderMode: Remainder

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 1.0 at the default text size. Hero numerals are clamped (see `body`) so a 72pt stat does
    /// not overflow its card at accessibility sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    /// - Parameters:
    ///   - text: A caller-composed value string (from `Copy`).
    ///   - size: Numeral tier. Defaults to `.medium`.
    ///   - color: Color of the numbers. Defaults to `text`.
    ///   - unitColor: Color of units and trailing words. Defaults to `muted`.
    ///   - remainder: Whether the words after the numbers render inline. Defaults to `.inline`.
    public init(
        _ text: String,
        size: Size = .medium,
        color: Color = Theme.Colors.text,
        unitColor: Color = Theme.Colors.muted,
        remainder: Remainder = .inline
    ) {
        self.text = text
        self.size = size
        self.color = color
        self.unitColor = unitColor
        self.remainderMode = remainder
    }

    /// The words after `text`'s numeric lead ("unlocked" for "2h 10m unlocked"), or the whole
    /// string when it has no numeric lead. Pair with `remainder: .hidden`.
    public static func remainder(of text: String) -> String {
        ValueTextParser.parse(text).remainder
    }

    /// Whether `text` has a numeric lead (so `NumeralText` will render a big numeral, not fall
    /// back to plain text).
    public static func hasNumeral(_ text: String) -> Bool {
        ValueTextParser.parse(text).hasNumber
    }

    public var body: some View {
        let parsed = ValueTextParser.parse(text)
        return Group {
            if parsed.hasNumber {
                Text(attributed(for: parsed))
                    .tracking(size.tracking)
            } else {
                Text(text)
                    .font(size.fallbackFont)
                    .foregroundStyle(color)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .contentTransition(reduceMotion ? .identity : .numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: parsed))
    }

    private func attributed(for parsed: ValueTextParser.Parsed) -> AttributedString {
        let factor = min(scale, 1.35)
        let numberFont = Theme.Typography.numeral(size: size.numberSize * factor, weight: size.numberWeight)
        let unitFont = Theme.Typography.numeral(size: size.unitSize * factor, weight: .semibold)

        var result = AttributedString()
        for run in parsed.runs {
            var piece = AttributedString(run.text)
            switch run.kind {
            case .number:
                piece.font = numberFont
                piece.foregroundColor = color
            case .unit, .space:
                piece.font = unitFont
                piece.foregroundColor = unitColor
            }
            result.append(piece)
        }

        if remainderMode == .inline, !parsed.remainder.isEmpty {
            var tail = AttributedString(" " + parsed.remainder)
            tail.font = unitFont
            tail.foregroundColor = unitColor
            result.append(tail)
        }
        return result
    }

    private func accessibilityText(for parsed: ValueTextParser.Parsed) -> String {
        guard parsed.hasNumber, remainderMode == .hidden else { return text }
        return parsed.leadText
    }
}

#Preview("NumeralText") {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        NumeralText("2h 10m unlocked", size: .hero, color: Theme.Colors.accent)
        NumeralText("72/150g", size: .large)
        NumeralText("4 of 6 goals", size: .medium)
        NumeralText("$39.99/yr", size: .medium)
        NumeralText("1 goal left", size: .small)
        NumeralText("Time Bank empty", size: .medium)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
