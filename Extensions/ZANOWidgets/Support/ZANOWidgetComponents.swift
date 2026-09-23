// ZANOWidgetComponents.swift
// Extensions/ZANOWidgets/Support
//
// Small, reusable SwiftUI pieces shared by the Home Screen and Lock Screen widget families.
// Extension-only (not Core/UI — see ZANOWidgetColor.swift's header comment for why), and kept to
// system styles: SF Symbols, system fonts, and the literal spec §15 tokens in `ZANOWidgetColor`.

import Core
import SwiftUI

/// A single progress ring for a goal (protein/water/focus), drawn as a simple trimmed stroke —
/// the Home Screen widget's own take on spec §15's `GoalRing` component (not imported: Core/UI
/// may not exist yet, see this task's knownIssues).
struct ZANOGoalRingView: View {
    let progress: ZANORingProgress
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Self.valueText(progress))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(4)
        }
        .accessibilityLabel("\(progress.title): \(Self.valueText(progress)) of \(Self.targetText(progress))")
    }

    private static func valueText(_ progress: ZANORingProgress) -> String {
        formattedAmount(progress.current)
    }

    private static func targetText(_ progress: ZANORingProgress) -> String {
        "\(formattedAmount(progress.target))\(progress.unit)"
    }

    private static func formattedAmount(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// A labelled goal row for the Large Home Screen widget's "Today's Plan" list — a small ring plus
/// a "72 / 150g" readout.
struct ZANOGoalRowView: View {
    let progress: ZANORingProgress
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            ZANOGoalRingView(progress: progress, color: color, lineWidth: 4)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(progress.title)
                    .font(.caption)
                    .foregroundStyle(ZANOWidgetColor.textMuted)
                Text("\(intText(progress.current)) / \(intText(progress.target))\(progress.unit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZANOWidgetColor.textPrimary)
            }
            Spacer(minLength: 0)
            if progress.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ZANOWidgetColor.accent)
                    .font(.caption)
            }
        }
    }

    private func intText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// "14🔥" streak pill — the widget-scale take on spec §15's `StreakPill`.
struct ZANOStreakPillView: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("\(streak)")
                .font(.system(.footnote, design: .rounded, weight: .bold))
            Text("🔥")
                .font(.footnote)
        }
        .foregroundStyle(ZANOWidgetColor.textPrimary)
        // Previously no accessibility modifiers at all: VoiceOver read the numeral and the emoji
        // as two separate stops. `WidgetCopy.streak(_:)` already composes this exact pair for the
        // rectangular Lock Screen widget's own accessible text elsewhere in this file's sibling —
        // reusing it here gives one combined announcement instead of a new hardcoded string.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.streak(streak))
    }
}

/// A compact lock/unlock badge — the widget-scale take on spec §15's `LockStatusCard`.
struct ZANOLockBadgeView: View {
    let isLocked: Bool

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isLocked ? ZANOWidgetColor.danger : ZANOWidgetColor.accent)
            // No explicit label previously — VoiceOver fell back to the SF Symbol's own default
            // glyph description ("padlock" / "unlocked padlock"), not guaranteed to convey the
            // app-semantic Locked/Unlocked state as clearly as `LockStatusCard`'s in-app
            // equivalent does. Both keys already exist and are used elsewhere in
            // `ZANOControls.swift`. See `docs/design/ui-stress-test-findings.md` §3.2.
            .accessibilityLabel(isLocked ? WidgetCopy.controlLockedLabel : WidgetCopy.controlUnlockedLabel)
    }
}

/// A minimal draining bar for the Time Bank (spec §5.2 Earn Rate / §5.11 Dynamic Island Earn
/// Meter) — `remaining` and `capMinutes` are both in minutes; `capMinutes` is a visual ceiling
/// only (there is no fixed daily maximum in the data model), so the bar always reads as "how full
/// relative to a big win", not a literal percentage of some absolute cap.
struct ZANOTimeBankBarView: View {
    let remainingMinutes: Int
    var capMinutes: Int = 120

    private var fraction: Double {
        guard capMinutes > 0 else { return 0 }
        return min(max(Double(remainingMinutes) / Double(capMinutes), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ZANOWidgetColor.surface2)
                Capsule()
                    .fill(ZANOWidgetColor.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 8)
        .accessibilityLabel(WidgetCopy.minutesRemaining(remainingMinutes))
    }
}
