// GoalRing.swift
// Core / UI / Components
//
// A single circular progress ring for one goal, per docs/spec.md §15's core component list and
// the P1/P3 mockups in §16 ("three progress rings labeled Workout, Protein (72/150g), Focus (25/50
// min)"). Built entirely from `Theme` tokens; carries no copy of its own — every piece of text is
// supplied pre-composed by the caller (CLAUDE.md: "User-facing copy lives in Core/Sources/Core/
// Copy — no hardcoded UI strings elsewhere"), so this file never imports or duplicates Copy.

import SwiftUI

/// What renders in the center of a `GoalRing`. Kept as an enum (rather than two optional
/// properties) so a caller can't accidentally supply both an icon and a text label at once.
public enum GoalRingCenter: Equatable, Sendable {
    /// An SF Symbol name (e.g. `"dumbbell.fill"`). Symbol names are identifiers, not user-facing
    /// copy, so they're fine to pass as plain strings.
    case icon(systemName: String)
    /// A fully-composed value string the caller has already formatted (e.g. `"72/150g"`,
    /// `"25 min"`, `"3 of 4"`). `GoalRing` never formats numbers or appends units itself.
    case text(String)
    /// No center content — just the ring.
    case none
}

/// A circular progress indicator for a single goal's completion fraction. Used standalone (e.g. a
/// hero ring on the Today screen) or composed inside `RingCluster`.
public struct GoalRing: View {

    /// Preset diameters/line widths so rings stay consistent across screens instead of every call
    /// site inventing its own numbers.
    public enum Size: Sendable {
        case small
        case medium
        case large

        var diameter: CGFloat {
            switch self {
            case .small: 44
            case .medium: 88
            case .large: 148
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: 5
            case .medium: 9
            case .large: 14
            }
        }
    }

    private let progress: Double
    private let color: Color
    private let size: Size
    private let center: GoalRingCenter

    /// - Parameters:
    ///   - progress: Completion fraction. Any value is accepted and clamped to `0...1` internally
    ///     — callers computing `current / target` don't need to clamp themselves.
    ///   - color: Ring tint. Pass `Theme.Colors.Ring.color(for:)` for a goal-typed ring, or any
    ///     other `Theme` color for a purpose-specific ring (e.g. `Theme.Colors.accent` for a
    ///     generic Time Bank / earn-progress ring).
    ///   - size: Preset diameter/line-width. Defaults to `.medium`.
    ///   - center: What to render in the ring's center. Defaults to `.none`.
    public init(
        progress: Double,
        color: Color = Theme.Colors.accent,
        size: Size = .medium,
        center: GoalRingCenter = .none
    ) {
        self.progress = progress
        self.color = color
        self.size = size
        self.center = center
    }

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surface2, lineWidth: size.lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Theme.Motion.ringFill, value: clampedProgress)

            centerContent
        }
        .frame(width: size.diameter, height: size.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(Int((clampedProgress * 100).rounded()))%"))
    }

    @ViewBuilder
    private var centerContent: some View {
        switch center {
        case .icon(let systemName):
            Image(systemName: systemName)
                .font(.system(size: size.diameter * 0.34, weight: .semibold))
                .foregroundStyle(color)
        case .text(let text):
            Text(text)
                .font(size == .small ? Theme.Typography.numeralSmall() : Theme.Typography.numeralMedium())
                .foregroundStyle(Theme.Colors.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, size.diameter * 0.12)
        case .none:
            EmptyView()
        }
    }
}
