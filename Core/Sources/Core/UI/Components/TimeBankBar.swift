// TimeBankBar.swift
// Core / UI / Components
//
// Visualizes Earn Mode's Time Bank (docs/spec.md §5.2, `Core/Sources/Core/LockEngine/
// TimeBankEngine.swift`, `Models/TimeBank.swift`), per §15's core component list and the P3
// mockup in §16 ("a Time Bank bar filling to '2h 10m unlocked'"). Takes raw minute counts for its
// fraction math and an optional caller-composed label for display — it never formats minutes into
// "2h 10m" itself (that composition belongs to `Core/Sources/Core/Copy`, per CLAUDE.md).
//
// Design-quality pass (docs/design/{typography-color,composition-audit,better-ui}-findings):
//
//   * The number leads. The label ("2h 10m unlocked") was the smallest text in the card — 13pt
//     caption above a 10pt bar — while it is the entire reward of Earn Mode. It now renders through
//     `NumeralText` at `labelSize` (28pt by default), digits loud, "h"/"m"/"unlocked" quiet. A label
//     with no numeric lead (a plain heading such as "Time Bank") falls back to a plain headline, so
//     existing callers that pass a heading keep working.
//   * The empty half of the bar is visible. The track was `surface2` (1.08:1 on its card); it is
//     `Theme.Colors.track` now, so "how much is left" is legible at a glance.
//   * The bar has presence and a glow: 12pt tall, a static glow under the fill in its own hue (the
//     earned/active element), and a minimum-width fill so a nearly-empty bank is still a visible dot.
//   * The pulse is one-shot and lands where it started. `repeatCount(3, autoreverses: true)` on a
//     `toggle()` ends on the *target* value, so after the low-balance warning the fill stayed dimmed
//     to 70% forever. The pulse is now an explicit down-up loop that always ends at full opacity.
//   * The glyph is `hourglass.bottomhalf.filled` (a bank draining), no longer the same `hourglass`
//     the recap uses for "reclaimed", and takes the bar's own hue instead of staying accent while
//     the bar turns warning.

import SwiftUI

/// A horizontal bar showing how many earned minutes remain in today's Time Bank out of the total
/// earned. Spec §5.2's "no hoarding" rule means this always represents a single calendar day —
/// callers are responsible for passing that day's `TimeBank.earnedMin`/`remainingMin` (or the
/// equivalent from `TimeBankEngine.remainingMinutes(for:)`).
public struct TimeBankBar: View {
    private let remainingMinutes: Int
    private let totalMinutes: Int
    /// Fully-composed label (e.g. `"2h 10m unlocked"`), shown above the bar. Optional — omit for
    /// a bare bar.
    private let label: String?
    /// Numeral tier for `label`. Defaults to `.medium` (28pt digits).
    private let labelSize: NumeralText.Size
    /// Whether the bank is near-empty — caller-computed (e.g. `remainingMinutes <= 5`) since only
    /// the caller knows what "low" means for its context. Defaults to `false`, so existing call
    /// sites are unaffected unless they opt in. Drives a one-shot warning pulse the moment this
    /// flips `false → true` (docs/design/animation-opportunities.md row 7a) — not a looping
    /// ambient animation, so it doesn't need its own ongoing Reduce Motion suppression beyond the
    /// gate already applied below.
    private let isLow: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseActive = false
    @State private var pulseTask: Task<Void, Never>?

    /// - Parameters:
    ///   - remainingMinutes: Minutes still available to spend today.
    ///   - totalMinutes: Minutes earned today (the fraction's denominator). Callers should not
    ///     pass yesterday's total — Time Bank balances don't carry across days (spec §5.2).
    ///   - label: Optional caller-composed display label.
    ///   - labelSize: Numeral tier for the label. Defaults to `.medium`.
    ///   - isLow: Whether to show the low-balance warning tint/pulse. Defaults to `false`.
    public init(
        remainingMinutes: Int,
        totalMinutes: Int,
        label: String? = nil,
        labelSize: NumeralText.Size = .medium,
        isLow: Bool = false
    ) {
        self.remainingMinutes = remainingMinutes
        self.totalMinutes = totalMinutes
        self.label = label
        self.labelSize = labelSize
        self.isLow = isLow
    }

    private var fraction: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1, max(0, Double(remainingMinutes) / Double(totalMinutes)))
    }

    private var barTint: Color {
        isLow ? Theme.Colors.warning : Theme.Colors.accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let label {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(barTint)
                    NumeralText(label, size: labelSize)
                    Spacer(minLength: 0)
                }
            }

            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "\(remainingMinutes)")
        .accessibilityValue(Text("\(Int((fraction * 100).rounded()))%"))
        .onChange(of: isLow) { oldValue, newValue in
            // One-shot warning pulse on the false→true edge only — never a looping ambient
            // animation, and skipped entirely under Reduce Motion (the color change to `.warning`
            // above already carries the state signal statically).
            guard newValue, !oldValue, !reduceMotion else { return }
            pulse()
        }
        .onDisappear {
            pulseTask?.cancel()
            pulseActive = false
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.track)

                Capsule()
                    .fill(barTint)
                    // A bank with anything in it shows at least a dot; 0 shows nothing.
                    .frame(width: fraction > 0 ? max(Theme.Metrics.progressBarHeight, proxy.size.width * fraction) : 0)
                    // The static "earned/active element" glow (spec §16), in the fill's own hue.
                    .shadow(color: barTint.opacity(fraction > 0 ? 0.35 : 0), radius: 6)
                    .opacity(pulseActive ? 0.55 : 1.0)
                    // The fill's width is information (a live balance), not decoration, so
                    // Reduce Motion shortens the curve rather than removing it.
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: fraction)
                    .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isLow)
            }
        }
        .frame(height: Theme.Metrics.progressBarHeight)
    }

    /// Three dim-and-return beats (~2s), then a guaranteed return to full opacity. Cancelled if the
    /// bar leaves the screen mid-pulse.
    private func pulse() {
        pulseTask?.cancel()
        pulseTask = Task { @MainActor in
            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.3)) { pulseActive = true }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.3)) { pulseActive = false }
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { break }
            }
            pulseActive = false
        }
    }
}

#Preview("TimeBankBar") {
    VStack(spacing: Theme.Spacing.lg) {
        TimeBankBar(remainingMinutes: 130, totalMinutes: 180, label: "2h 10m unlocked")
        TimeBankBar(remainingMinutes: 130, totalMinutes: 180, label: "2h 10m unlocked", labelSize: .hero)
        TimeBankBar(remainingMinutes: 4, totalMinutes: 180, label: "4m unlocked", isLow: true)
        TimeBankBar(remainingMinutes: 0, totalMinutes: 60, label: "Time Bank empty")
        TimeBankBar(remainingMinutes: 90, totalMinutes: 180, label: "Time Bank")
    }
    .padding(Theme.Spacing.md)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
