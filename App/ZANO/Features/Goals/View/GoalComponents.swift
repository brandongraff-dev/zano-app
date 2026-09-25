// GoalComponents.swift
// App / Features / Goals / View
//
// Small pieces shared by the goals editor and the goal picker: the goal's ring glyph, the "how
// it's verified" chip (spec §3 tiers), and the sheet that runs a goal's one setup step (gym, tag,
// or Apple Health).

import SwiftUI
import Core

// MARK: - Ring glyph

/// The goal's icon inside a thin ring in the goal's ring color — the same hue its ring uses on
/// Today, so a goal looks the same everywhere.
struct GoalTypeGlyph: View {
    let type: GoalType
    var progress: Double = 0.72

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 44

    var body: some View {
        let color = Theme.Colors.Ring.color(for: type)
        ZStack {
            Circle()
                .stroke(Theme.Colors.Ring.track(for: color), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: goalIconName(for: type))
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Verification chip

/// "✓ Verified by Apple Health" on a small glass capsule. The symbol carries the tier (automatic /
/// one tap / honor); VoiceOver reads the tier name before the line.
struct GoalVerificationChip: View {
    let type: GoalType

    var body: some View {
        let tier = GoalCatalog.tier(for: type)
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: GoalCatalog.tierSymbol(for: tier))
                .font(Theme.Typography.icon(.xsmall))
                .foregroundStyle(tier == .a ? Theme.Colors.accent : Theme.Colors.textSecondary)
            Text(Copy.goals.verification(for: type))
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xxs)
        .zanoGlass()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.goals.verificationSpoken(tier: tier, type: type))
    }
}

// MARK: - Setup step copy

extension GoalSetupStep {
    var title: String {
        switch self {
        case .gym: Copy.goals.setupGymTitle
        case .tag: Copy.goals.setupTagTitle
        case .health: Copy.goals.setupHealthTitle
        }
    }

    var message: String {
        switch self {
        case .gym: Copy.goals.setupGymMessage
        case .tag: Copy.goals.setupTagMessage
        case .health: Copy.goals.setupHealthMessage
        }
    }

    var buttonTitle: String {
        switch self {
        case .gym: Copy.goals.setupGymButton
        case .tag: Copy.goals.setupTagButton
        case .health: Copy.goals.setupHealthButton
        }
    }

    var shortTitle: String {
        switch self {
        case .gym: Copy.goals.setupGymShort
        case .tag: Copy.goals.setupTagShort
        case .health: Copy.goals.setupHealthShort
        }
    }

    var systemImage: String {
        switch self {
        case .gym: "mappin.and.ellipse"
        case .tag: "wave.3.right"
        case .health: "heart.fill"
        }
    }
}

// MARK: - Setup sheet

/// The sheet content for one setup step. Gym and tag setup are pushed-style screens owned by
/// their own features, so they get a `NavigationStack` and a Done button here.
struct GoalSetupDestination: View {
    let step: GoalSetupStep

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch step {
        case .gym:
            NavigationStack {
                GymSetupView()
                    .toolbar { doneButton }
            }
        case .tag:
            NavigationStack {
                NFCTagsView()
                    .toolbar { doneButton }
            }
        case .health:
            HealthPermissionPrimer(onFinished: { dismiss() })
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(Copy.common.done) { dismiss() }
        }
    }
}
