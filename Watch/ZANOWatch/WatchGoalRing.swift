// WatchGoalRing.swift
// Watch/ZANOWatch
//
// A target-local MIRROR of `Core/Sources/Core/UI/Components/GoalRing.swift`'s trim-circle
// rendering — same reason as `WatchTheme.swift`/`WatchCopy.swift`: this target cannot `import
// Core`, so the real `GoalRing` view isn't reachable here. Same trim/rotation/animation approach,
// re-expressed against `WatchTheme` instead of `Theme`, sized for a watch face instead of a phone
// screen. See `WatchTheme.swift`'s header for the full explanation and the knownIssues note about
// collapsing this back into the real component once `Core` supports watchOS.

import SwiftUI

public enum WatchGoalRingCenter: Equatable {
    case icon(systemName: String)
    case text(String)
    case none
}

public struct WatchGoalRing: View {
    public enum Size {
        case small
        case medium
        case large

        var diameter: CGFloat {
            switch self {
            case .small: 28
            case .medium: 52
            case .large: 84
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: 4
            case .medium: 6
            case .large: 9
            }
        }
    }

    private let progress: Double
    private let color: Color
    private let size: Size
    private let center: WatchGoalRingCenter

    public init(
        progress: Double,
        color: Color = WatchTheme.Colors.accent,
        size: Size = .medium,
        center: WatchGoalRingCenter = .none
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
                .stroke(WatchTheme.Colors.surface2, lineWidth: size.lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(WatchTheme.Motion.ringFill, value: clampedProgress)

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
                .font(size == .small ? WatchTheme.Typography.numeralSmall() : WatchTheme.Typography.numeralMedium())
                .foregroundStyle(WatchTheme.Colors.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        case .none:
            EmptyView()
        }
    }
}
