// StreakPill.swift
// Core / UI / Components
//
// The streak indicator from docs/spec.md §15's core component list and the P1 mockup in §16
// ("streak pill '14 🔥'"). Renders an SF Symbol flame instead of the literal emoji so it inherits
// system dynamic type, tinting, and dark-mode rendering correctly. `count` is numeric data (not
// copy), so it's safe to render directly per CLAUDE.md's no-hardcoded-copy rule; any surrounding
// sentence ("14-day streak") is the caller's job via `Core/Sources/Core/Copy`.

import SwiftUI

/// A compact capsule showing the user's current streak length, per docs/spec.md §8 (Retention
/// Psychology Rules) — "streaks have forgiveness"; see `isFrozen` below for how that's reflected.
public struct StreakPill: View {
    private let count: Int
    /// True while a streak freeze (`StreakEngine.useFreeze`) is covering today instead of an
    /// earned unlock — swaps the flame for a snowflake and cools the tint so the pill visibly
    /// communicates "protected", not "broken" (spec §8 rule 3: "should feel protective, not
    /// fragile").
    private let isFrozen: Bool
    /// Optional VoiceOver label override. When `nil`, falls back to just the numeral (data, not a
    /// composed sentence) so this component never hardcodes accessibility copy; callers that want
    /// a full spoken phrase (e.g. "14 day streak") should supply it from `Copy`.
    private let accessibilityLabelOverride: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fires the flame/snowflake bounce only when the streak count *increases* — see `body`'s
    /// `.onChange(of: count)` below. Keyed separately from `count` itself so a streak reset to 0
    /// doesn't read as a celebratory bounce (spec §8's "no shame" principle is about copy, but the
    /// same spirit applies to motion — docs/design/animation-opportunities.md row 6b).
    @State private var bounceTrigger = 0

    public init(count: Int, isFrozen: Bool = false, accessibilityLabelOverride: String? = nil) {
        self.count = count
        self.isFrozen = isFrozen
        self.accessibilityLabelOverride = accessibilityLabelOverride
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Group {
                if reduceMotion {
                    // Reduce Motion: no `.symbolEffect` at all — the flame/snowflake swap still
                    // reflects `isFrozen` via `.contentTransition(.opacity)` below, and the
                    // count change is still reflected by the numeral redraw, so no information
                    // is lost, only the bounce/morph motion.
                    Image(systemName: isFrozen ? "snowflake" : "flame.fill")
                        .contentTransition(.opacity)
                } else {
                    Image(systemName: isFrozen ? "snowflake" : "flame.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: bounceTrigger)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isFrozen ? Theme.Colors.Ring.water : Theme.Colors.accent)

            Text("\(count)")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.surface2, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelOverride ?? defaultAccessibilityLabel)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isFrozen)
        .onChange(of: count) { oldValue, newValue in
            guard newValue > oldValue else { return }
            bounceTrigger += 1
        }
    }

    /// The un-overridden fallback VoiceOver label. Previously just `"\(count)"` regardless of
    /// `isFrozen`, silently dropping the one piece of state this pill's whole visual (flame vs.
    /// snowflake, tint) exists to communicate — a VoiceOver user got the bare number either way
    /// unless every caller remembered to pass a hand-authored override. `"frozen"` here is a short,
    /// factual state word attached to a numeral, in the same spirit as this file's existing
    /// "data, not a composed sentence" fallback (see `accessibilityLabelOverride`'s doc comment)
    /// rather than narrative copy — still no full sentence, and a caller that wants one still
    /// supplies it via `accessibilityLabelOverride` from `Copy`. See
    /// `docs/design/ui-stress-test-findings.md` §3.1.
    private var defaultAccessibilityLabel: String {
        isFrozen ? "\(count), frozen" : "\(count)"
    }
}
