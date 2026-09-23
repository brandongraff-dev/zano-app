// LockStatusCard.swift
// Core / UI / Components
//
// Summarizes the current lock state on the Today screen, per docs/spec.md §15's core component
// list and the P1 mockup in §16 ("lock status card 'Locked · TikTok, Instagram, YouTube' with a
// small padlock"). Purely presentational: it takes `isLocked` (a fact, driving icon/color) plus
// caller-composed strings for everything textual — it never assembles sentences like "Locked ·
// {apps}" itself, so it carries no hardcoded copy (CLAUDE.md).
//
// This card intentionally has no dependency on `LockEngineManager`/`LockSession` — the calling
// screen owns fetching lock state and formatting it; this file only renders what it's given.
//
// Design-quality pass (docs/design/{better-ui,typography-color,competitive-research}):
//
//   * State reads from across the room, not from a 17pt label. Locked is a *neutral* card with a
//     danger padlock badge — the spec's "danger = locked" lives on the padlock, so the card is not a
//     red error slab for the whole of a normal locked day (spec §16: "calm, motivating, not
//     punishing"). Unlocked is the earned state: an accent wash and a static glow. The one place the
//     card is loud is the one place it means something.
//   * The whole card is the target. Padding and surface used to sit outside the `Button` (a 40pt tall
//     hit area with a dead ring around it, and no press state at all); both are inside now, under
//     `PressableStyle`.
//   * The badge is an `IconBadge` (on-hue accent wash instead of the olive `accent.opacity(0.16)`),
//     which morphs lock <-> unlock instead of popping, and bounces once on the earned edge only.
//   * Detail text wraps to two lines: "Earned · 2h 10m unlocked" is the payoff and must not clip.

import SwiftUI

/// A card summarizing whether the user is currently locked out of a set of apps, and what's left
/// to unlock. See the type-level note above for why every string here is caller-composed.
public struct LockStatusCard: View {
    private let isLocked: Bool
    /// Fully-composed headline, e.g. `"Locked · TikTok, Instagram, YouTube"` or `"Unlocked"`.
    private let statusLine: String
    /// Fully-composed detail line, e.g. `"1 goal left"` or `"Earned · 2h 10m unlocked"`. Optional.
    private let detailLine: String?
    private let action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped on the locked -> unlocked edge only, so the padlock bounces when the lock opens and
    /// never when it closes (spec §8 rule 9: no shame in the motion either).
    @State private var earnedTick = 0

    /// - Parameters:
    ///   - isLocked: Drives the padlock icon/color and the card's earned treatment — never rendered
    ///     as text by this view.
    ///   - statusLine: Caller-composed headline (see property doc above).
    ///   - detailLine: Caller-composed subtitle. Defaults to `nil`.
    ///   - action: Optional tap handler (e.g. navigate to the Lock screen). When `nil`, the card
    ///     is non-interactive.
    public init(
        isLocked: Bool,
        statusLine: String,
        detailLine: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.isLocked = isLocked
        self.statusLine = statusLine
        self.detailLine = detailLine
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { card }
                    .buttonStyle(PressableStyle())
            } else {
                card
            }
        }
        // Previously ungated — this card is the app's single most-visible state indicator
        // (every screen's lock/unlock summary), and the icon/tint swap it animates on
        // `isLocked` is exactly the "spring with no reduced-motion fallback" pattern this
        // wave's task brief calls out by name. See `docs/design/ui-stress-test-findings.md`
        // §2.5 (the same blanket gap flagged for the rest of this safe set).
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isLocked)
        .onChange(of: isLocked) { oldValue, newValue in
            guard oldValue, !newValue else { return }
            earnedTick += 1
        }
    }

    private var card: some View {
        rowBody
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Locked: neutral surface, edge only. Unlocked: the earned wash and glow.
            .zanoCard(tint: isLocked ? nil : Theme.Colors.accent, active: !isLocked)
    }

    private var rowBody: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(
                systemName: isLocked ? "lock.fill" : "lock.open.fill",
                tint: isLocked ? Theme.Colors.danger : Theme.Colors.accent,
                size: .medium
            )
            // `value:` is pinned to 0 under Reduce Motion so the bounce can never fire.
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : earnedTick)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(statusLine)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let detailLine {
                    Text(detailLine)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(isLocked ? Theme.Colors.muted : Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if action != nil {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    // Decorative affordance inside a `.combine` group: keep it out of the announcement.
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Theme.Metrics.minTapTarget)
        .contentShape(Rectangle())
        // One announcement: the state line, then the detail. The padlock badge is decorative (hidden).
        .accessibilityElement(children: .combine)
    }
}

#Preview("LockStatusCard") {
    VStack(spacing: Theme.Spacing.md) {
        LockStatusCard(
            isLocked: true,
            statusLine: "Locked · TikTok, Instagram, YouTube",
            detailLine: "1 goal left",
            action: {}
        )
        LockStatusCard(
            isLocked: false,
            statusLine: "Unlocked",
            detailLine: "Earned · 2h 10m unlocked"
        )
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
