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

    /// - Parameters:
    ///   - isLocked: Drives the padlock icon/color only — never rendered as text by this view.
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
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .animation(Theme.Motion.springStandard, value: isLocked)
    }

    private var content: some View {
        Group {
            if let action {
                Button(action: action) { rowBody }
                    .buttonStyle(.plain)
            } else {
                rowBody
            }
        }
    }

    private var rowBody: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill((isLocked ? Theme.Colors.danger : Theme.Colors.accent).opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isLocked ? Theme.Colors.danger : Theme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusLine)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(2)
                if let detailLine {
                    Text(detailLine)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if action != nil {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .contentShape(Rectangle())
    }
}
