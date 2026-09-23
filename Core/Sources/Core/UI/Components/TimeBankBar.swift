// TimeBankBar.swift
// Core / UI / Components
//
// Visualizes Earn Mode's Time Bank (docs/spec.md §5.2, `Core/Sources/Core/LockEngine/
// TimeBankEngine.swift`, `Models/TimeBank.swift`), per §15's core component list and the P3
// mockup in §16 ("a Time Bank bar filling to '2h 10m unlocked'"). Takes raw minute counts for its
// fraction math and an optional caller-composed label for display — it never formats minutes into
// "2h 10m" itself (that composition belongs to `Core/Sources/Core/Copy`, per CLAUDE.md).

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
    /// Whether the bank is near-empty — caller-computed (e.g. `remainingMinutes <= 5`) since only
    /// the caller knows what "low" means for its context. Defaults to `false`, so existing call
    /// sites are unaffected unless they opt in. Drives a one-shot warning pulse the moment this
    /// flips `false → true` (docs/design/animation-opportunities.md row 7a) — not a looping
    /// ambient animation, so it doesn't need its own ongoing Reduce Motion suppression beyond the
    /// gate already applied below.
    private let isLow: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseActive = false

    /// - Parameters:
    ///   - remainingMinutes: Minutes still available to spend today.
    ///   - totalMinutes: Minutes earned today (the fraction's denominator). Callers should not
    ///     pass yesterday's total — Time Bank balances don't carry across days (spec §5.2).
    ///   - label: Optional caller-composed display label.
    ///   - isLow: Whether to show the low-balance warning tint/pulse. Defaults to `false`.
    public init(remainingMinutes: Int, totalMinutes: Int, label: String? = nil, isLow: Bool = false) {
        self.remainingMinutes = remainingMinutes
        self.totalMinutes = totalMinutes
        self.label = label
        self.isLow = isLow
    }

    private var fraction: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1, max(0, Double(remainingMinutes) / Double(totalMinutes)))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let label {
                HStack {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(label)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer(minLength: 0)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.surface2)

                    Capsule()
                        .fill(isLow ? Theme.Colors.warning : Theme.Colors.accent)
                        .frame(width: proxy.size.width * fraction)
                        .opacity(pulseActive ? 0.7 : 1.0)
                        // The fill's width is information (a live balance), not decoration, so
                        // Reduce Motion shortens the curve rather than removing it.
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: fraction)
                        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isLow)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "\(remainingMinutes)")
        .accessibilityValue(Text("\(Int((fraction * 100).rounded()))%"))
        .onChange(of: isLow) { oldValue, newValue in
            // One-shot warning pulse on the false→true edge only — never a looping ambient
            // animation, and skipped entirely under Reduce Motion (the color change to `.warning`
            // above already carries the state signal statically).
            guard newValue, !oldValue, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true)) {
                pulseActive.toggle()
            }
        }
    }
}
