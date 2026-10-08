// StreakPill.swift
// Core / UI / Components
//
// The streak indicator from docs/spec.md §15's core component list and the P1 mockup in §16
// ("streak pill '14 🔥'"). Renders an SF Symbol flame instead of the literal emoji so it inherits
// system dynamic type, tinting, and dark-mode rendering correctly. `count` is numeric data (not
// copy), so it's safe to render directly per CLAUDE.md's no-hardcoded-copy rule; any surrounding
// sentence ("14-day streak") is the caller's job via `Core/Sources/Core/Copy`.
//
// Design-quality pass (docs/design/{better-ui,typography-color}-findings):
//
//   * Glyph and digits share a baseline and an optical size. The 13pt flame beside 17pt digits sat
//     below the digits' cap height on a centre-aligned stack (ALN-03); the flame is now the 17pt
//     icon tier and the row is baseline-aligned, so they read as one mark.
//   * The count is a `NumeralText`, so it scales with Dynamic Type (a fixed 17pt numeral never did)
//     and rolls like an odometer when the streak grows.
//   * The pill has an edge. `surface2` on a `surface` card is 1.08:1, so the capsule dissolved into
//     the card it sits on; a hairline outlines it on every background.

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
    /// Optional VoiceOver label override. When `nil`, falls back to
    /// `Copy.common.streakSpoken(days:frozen:)` ("14 days" / "14 days, frozen"); callers that want
    /// a full spoken phrase (e.g. "14 day streak") should supply it from `Copy`.
    private let accessibilityLabelOverride: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fires the flame/snowflake bounce only when the streak count *increases* — see `body`'s
    /// `.onChange(of: count)` below. Keyed separately from `count` itself so a streak reset to 0
    /// doesn't read as a celebratory bounce (spec §8's "no shame" principle is about copy, but the
    /// same spirit applies to motion — docs/design/animation-opportunities.md row 6b).
    @State private var bounceTrigger = 0
    /// True for a moment after the count goes up: the buddy pops.
    @State private var pop = false

    public init(count: Int, isFrozen: Bool = false, accessibilityLabelOverride: String? = nil) {
        self.count = count
        self.isFrozen = isFrozen
        self.accessibilityLabelOverride = accessibilityLabelOverride
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xxs) {
            // The streak is the person's own buddy: fire eyes while the streak is alive, ice eyes while a
            // freeze holds it, asleep at zero (session 29). It bounces when the count goes up.
            StoredBuddySprite(pose: isFrozen ? .frozen : (count > 0 ? .blaze : .sleepy), size: 34)
                .frame(width: 34, height: 34)
                .scaleEffect(pop ? 1.18 : 1)
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: pop)

            NumeralText("\(count)", size: .small)
        }
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, 2)
        // Pass 2 (playful): the pill warms with the streak, an ember tint that grows to full at 30
        // days (the same curve as the aurora's warmth). Paint over the glass, never the label.
        // Pass 3 (restraint): one flat tint (up to 18%), no gradient, no flame glow.
        .background {
            Capsule(style: .continuous)
                .fill(Theme.Colors.ember.opacity(0.18 * emberWarmth))
        }
        // v2: chrome glass, like every floating capsule.
        .zanoGlass()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelOverride ?? defaultAccessibilityLabel)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isFrozen)
        // The odometer roll needs an animation context to interpolate in; `NumeralText` supplies the
        // `.numericText` transition, this supplies the transaction (and nothing under Reduce Motion).
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: count)
        .onChange(of: count) { oldValue, newValue in
            guard newValue > oldValue else { return }
            bounceTrigger += 1
            guard !reduceMotion else { return }
            pop = true
            Task {
                try? await Task.sleep(nanoseconds: 220_000_000)
                pop = false
            }
        }
    }

    private var emberWarmth: Double {
        isFrozen ? 0 : ZanoAuroraWarmth.forStreak(days: count)
    }

    /// The un-overridden fallback VoiceOver label: the day count plus the frozen state (the one
    /// piece of state the flame/snowflake swap exists to communicate), from
    /// `Copy.common.streakSpoken(days:frozen:)`. A caller that wants a fuller sentence still
    /// supplies it via `accessibilityLabelOverride`. See `docs/design/ui-stress-test-findings.md`
    /// §3.1.
    private var defaultAccessibilityLabel: String {
        Copy.common.streakSpoken(days: count, frozen: isFrozen)
    }
}

#Preview("StreakPill") {
    HStack(spacing: Theme.Spacing.md) {
        StreakPill(count: 14)
        StreakPill(count: 3, isFrozen: true)
        StreakPill(count: 365)
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
