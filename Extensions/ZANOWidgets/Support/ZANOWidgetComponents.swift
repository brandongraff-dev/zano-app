// ZANOWidgetComponents.swift
// Extensions/ZANOWidgets/Support
//
// Small, reusable SwiftUI pieces shared by the Home Screen and Lock Screen widget families, plus
// the widget's static "charged star": the ZANO swoosh-star in graphite, filled with silver from
// left to right as goals get done, over a soft blue glow.
//
// `ZanoLivingMark` (Core/UI) is the in-app version, but it animates through `TimelineView`,
// which widgets can't run, so the star here is a still frame of the same idea.
//
// Charge is GOAL progress, not Screen Time: WidgetKit extensions cannot read DeviceActivity usage
// numbers (only the DeviceActivityReport extension can), so everything below comes from
// `ZANOWidgetSnapshot` (App Group reads only).

import Core
import SwiftUI
import WidgetKit

// MARK: - Charge

/// How charged the star is. While a lock is running it's "goals done vs. goals still needed to
/// unlock"; with no lock it's today's tracked goals (protein / water / focus) done vs. tracked.
struct ZANOWidgetCharge: Equatable {
    let done: Int
    let total: Int
    /// Goals still needed to unlock. Zero when no lock is running.
    let remaining: Int
    let isLocked: Bool

    var fraction: Double {
        guard total > 0 else { return isLocked ? 0 : 1 }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    init(snapshot: ZANOWidgetSnapshot) {
        let tracked = snapshot.trackedGoals.map(\.progress)
        let completed = tracked.filter(\.isComplete).count
        isLocked = snapshot.isLocked
        if snapshot.isLocked {
            // The snapshot knows how many required goals are left, not which ones or how many
            // there were, so the total is what's been finished today plus what's left.
            remaining = max(snapshot.goalsRemainingForActiveLock, 0)
            done = completed
            total = completed + remaining
        } else {
            remaining = 0
            done = completed
            total = tracked.count
        }
    }
}

/// One goal row's data: progress, its ring color, and its SF Symbol.
struct ZANOTrackedGoal: Identifiable {
    enum Kind: String { case protein, water, focus }

    let kind: Kind
    let progress: ZANORingProgress

    var id: String { kind.rawValue }

    var color: Color {
        switch kind {
        case .protein: ZANOWidgetColor.ringProtein
        case .water: ZANOWidgetColor.ringWater
        case .focus: ZANOWidgetColor.ringFocus
        }
    }

    var systemImage: String {
        switch kind {
        case .protein: "fork.knife"
        case .water: "drop.fill"
        case .focus: "brain.head.profile"
        }
    }
}

extension ZANOWidgetSnapshot {
    private var allGoals: [ZANOTrackedGoal] {
        [
            ZANOTrackedGoal(kind: .protein, progress: protein),
            ZANOTrackedGoal(kind: .water, progress: water),
            ZANOTrackedGoal(kind: .focus, progress: focus)
        ]
    }

    /// The goals the user actually has set up (a ring with no `Goal` behind it has no `goalID`).
    var trackedGoals: [ZANOTrackedGoal] {
        allGoals.filter { $0.progress.goalID != nil }
    }

    /// Goals to draw as rows: the tracked ones, or all three when nothing is set up yet (the
    /// placeholder, and a fresh install), so the layout never collapses to empty.
    var displayGoals: [ZANOTrackedGoal] {
        let tracked = trackedGoals
        return tracked.isEmpty ? allGoals : tracked
    }

    var charge: ZANOWidgetCharge { ZANOWidgetCharge(snapshot: self) }

    /// The widget gallery / placeholder frame: like `.placeholder`, but with real-looking goals
    /// (one done) so the star shows a partial charge instead of an empty outline.
    static let galleryPreview = ZANOWidgetSnapshot(
        asOf: .now,
        currentStreak: 14,
        bestStreak: 21,
        isLocked: true,
        lockMode: .earn,
        goalsRemainingForActiveLock: 2,
        lockSetName: placeholder.lockSetName,
        earnedMinutesRemainingToday: 35,
        nextScheduledLockAt: placeholder.nextScheduledLockAt,
        protein: ZANORingProgress(
            goalID: UUID(), title: placeholder.protein.title, current: 150, target: 150, unit: placeholder.protein.unit
        ),
        water: ZANORingProgress(
            goalID: UUID(), title: placeholder.water.title, current: 1250, target: 2000, unit: placeholder.water.unit
        ),
        focus: ZANORingProgress(
            goalID: UUID(), title: placeholder.focus.title, current: 25, target: 50, unit: placeholder.focus.unit
        ),
        defaultLockSetID: nil,
        todaysActiveGoalIDs: []
    )
}

// MARK: - Charged star

/// The static charged star. Size it with `.frame`; it keeps the mark's aspect ratio.
struct ZANOChargedStar: View {
    let charge: Double
    /// The blue glow behind the star (full-color rendering only).
    var showsGlow: Bool = true
    var glowRadius: CGFloat = 14

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var clampedCharge: Double { min(max(charge, 0), 1) }

    private static let graphite = LinearGradient(
        colors: [Color.white.opacity(0.11), Color.white.opacity(0.035)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // A blurred blue star: grows and brightens with charge. Skipped in accented/vibrant
            // rendering, where a blur would turn into a flat white smudge.
            if showsGlow && renderingMode == .fullColor {
                ZanoMarkShape()
                    .fill(ZANOWidgetColor.accent, style: FillStyle(eoFill: true))
                    .blur(radius: glowRadius)
                    .scaleEffect(0.9 + 0.25 * clampedCharge)
                    .opacity(0.2 + 0.6 * clampedCharge)
            }

            // Uncharged metal. In vibrant/accented modes the translucent white still reads as a
            // faint outline of the star, so the "empty" part never vanishes.
            ZanoMarkShape()
                .fill(Self.graphite, style: FillStyle(eoFill: true))
                .overlay(
                    ZanoMarkShape()
                        .stroke(Color.white.opacity(renderingMode == .fullColor ? 0.12 : 0.35), lineWidth: 0.75)
                )

            // Charged metal, filled left to right.
            if clampedCharge > 0 {
                ZanoMarkShape()
                    .fill(Theme.Colors.metallic, style: FillStyle(eoFill: true))
                    .mask(chargeMask)
                    .widgetAccentable()
            }
        }
        .aspectRatio(ZanoMark.aspectRatio, contentMode: .fit)
    }

    /// Opaque from the left edge up to `charge`, with a slightly feathered leading edge.
    @ViewBuilder
    private var chargeMask: some View {
        if clampedCharge >= 1 {
            Rectangle()
        } else {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, clampedCharge - 0.015)),
                    .init(color: .clear, location: min(1, clampedCharge + 0.015))
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

// MARK: - Background

/// The Home Screen widgets' container background: near-black with a faint blue light sitting
/// behind the star, brighter as the star charges. The system drops it in accented/vibrant modes.
struct ZANOWidgetBackground: View {
    let glowCenter: UnitPoint
    let charge: Double
    var glowRadius: CGFloat = 120

    var body: some View {
        ZStack {
            ZANOWidgetColor.background
            RadialGradient(
                colors: [
                    ZANOWidgetColor.accent.opacity(0.08 + 0.20 * min(max(charge, 0), 1)),
                    ZANOWidgetColor.accent.opacity(0)
                ],
                center: glowCenter,
                startRadius: 0,
                endRadius: glowRadius
            )
        }
    }
}

// MARK: - Goal rows

/// A goal's progress as a capsule bar in its ring color.
struct ZANOGoalCapsuleBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.22))
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? height : 0))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// A compact goal row: icon, title, capsule bar, and an optional trailing quick-log button.
/// Used by the medium widget (compact) and the large one (with the "72 / 150g" readout).
struct ZANOGoalCapsuleRow<Trailing: View>: View {
    let goal: ZANOTrackedGoal
    var showsAmount: Bool = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: goal.progress.isComplete ? "checkmark.circle.fill" : goal.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(goal.color)
                .frame(width: 12)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(goal.progress.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(ZANOWidgetColor.textPrimary)
                        .lineLimit(1)
                    if showsAmount {
                        Spacer(minLength: 2)
                        Text(Self.amountText(goal.progress))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ZANOWidgetColor.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                ZANOGoalCapsuleBar(fraction: goal.progress.fraction, color: goal.color, height: showsAmount ? 6 : 4)
            }
            trailing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(goal.progress.title): \(Self.amountText(goal.progress))")
    }

    static func amountText(_ progress: ZANORingProgress) -> String {
        "\(format(progress.current)) / \(format(progress.target))\(progress.unit)"
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The small tinted pill on a goal row that runs a quick-log App Intent ("+25g").
struct ZANOQuickLogChip: View {
    let color: Color
    var text: String?
    var systemImage: String?

    var body: some View {
        Group {
            if let text {
                Text(text)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(ZANOWidgetColor.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.24)))
    }
}

// MARK: - Segment bar

/// "One segment per goal" bar for the rectangular Lock Screen widget: done segments solid, the
/// rest translucent. Capped so a big goal list still fits.
struct ZANOSegmentBar: View {
    let done: Int
    let total: Int
    var maxSegments: Int = 6

    var body: some View {
        let count = max(min(total, maxSegments), 1)
        let filled = total > maxSegments
            ? Int((Double(done) / Double(total) * Double(maxSegments)).rounded(.down))
            : (total == 0 ? 1 : done)
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Color.primary : Color.primary.opacity(0.25))
                    .widgetAccentable(index < filled)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Streak + lock

/// Tiny flame + streak number for a widget corner.
struct ZANOStreakFlameView: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ZANOWidgetColor.textMuted)
                .widgetAccentable()
            Text("\(streak)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ZANOWidgetColor.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.streak(streak))
    }
}

/// "Locked · Social" with a lock glyph (or "Unlocked"), muted.
struct ZANOLockStatusLine: View {
    let snapshot: ZANOWidgetSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 9, weight: .bold))
            Text(snapshot.isLocked
                ? WidgetCopy.lockStatusLine(lockSetName: snapshot.lockSetName)
                : WidgetCopy.noActiveLock)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(ZANOWidgetColor.textMuted)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Time Bank

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
                    .widgetAccentable()
            }
        }
        .frame(height: 8)
        .accessibilityLabel(WidgetCopy.minutesRemaining(remainingMinutes))
    }
}
