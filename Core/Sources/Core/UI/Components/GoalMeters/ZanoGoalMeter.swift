// ZanoGoalMeter.swift
// Core / UI / Components / GoalMeters
//
// A meter that looks like the goal (session 34; the founder asked for "meters for every goal" after
// the Fuel protein bar). One slim strip per goal type, in the goal's colour:
//
//   workout     a barbell; plate pairs load from the middle out        (BodyMeters.swift)
//   steps       a trail of footprints                                  (BodyMeters.swift)
//   stretch     a resistance band pulled toward a target               (BodyMeters.swift)
//   cold/sauna  a thermometer with a snowflake at the end              (BodyMeters.swift)
//   protein     a chocolate protein bar with a bite out of it          (FoodMeters.swift)
//   water       a row of glasses filling up                            (FoodMeters.swift)
//   creatine    scoops of powder                                       (FoodMeters.swift)
//   meal prep   meal-prep containers                                   (FoodMeters.swift)
//   focus       a battery charging, with a bolt                        (TimeMeters.swift)
//   sunrise     the sun rising over the horizon                        (TimeMeters.swift)
//   sleep       moon phases, crescent to full                          (TimeMeters.swift)
//   reading     a row of book spines                                   (TimeMeters.swift)
//   custom      a row of stars                                         (TimeMeters.swift)
//
// Motion is only ever a reply to progress changing: the fill springs to the new level and the strip
// pops once when it reaches 100%. Reduce Motion: the level just changes. Decorative: whatever shows
// the meter also shows the number, so the meter is hidden from VoiceOver.

import SwiftUI

/// The goal-shaped meter for `goal` at `progress` (0...1; above 1 draws full).
public struct ZanoGoalMeter: View {
    private let goal: GoalType
    private let progress: Double
    private let color: Color
    private let height: CGFloat
    private let pulse: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completeTick = 0

    /// - Parameters:
    ///   - goal: Which goal's meter to draw.
    ///   - progress: Today's progress, 0...1.
    ///   - color: The goal's colour. Defaults to `Theme.Colors.Ring.color(for: goal)`.
    ///   - height: Strip height. 30 on a goal tile.
    ///   - pulse: Bump on each log, for the meters that react to one (protein crumbs).
    public init(goal: GoalType, progress: Double, color: Color? = nil, height: CGFloat = 30, pulse: Int = 0) {
        self.goal = goal
        self.progress = progress
        self.color = color ?? Theme.Colors.Ring.color(for: goal)
        self.height = height
        self.pulse = pulse
    }

    private var level: Double { min(max(progress, 0), 1) }
    private var isFull: Bool { level >= 1 }

    public var body: some View {
        let popScale: Double = reduceMotion ? 1 : 1.08
        meter
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .shadow(color: isFull ? color.opacity(0.55) : .clear, radius: 6)
            .keyframeAnimator(initialValue: 1.0, trigger: completeTick) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(popScale, duration: 0.14, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
            .animation(reduceMotion ? nil : Theme.Motion.springPop, value: level)
            .onChange(of: isFull) { wasFull, nowFull in
                if !wasFull && nowFull { completeTick += 1 }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var meter: some View {
        switch goal {
        case .workoutGym, .workoutHomeOutdoor: BarbellMeter(progress: level, color: color)
        case .steps: FootprintsMeter(progress: level, color: color)
        case .stretchMobility: StretchBandMeter(progress: level, color: color)
        case .coldShowerSauna: ThermometerMeter(progress: level, color: color)
        case .protein: ZanoProteinBar(progress: level, color: color, crumbs: pulse, chunks: 8, height: height)
        case .water: WaterGlassesMeter(progress: level, color: color)
        case .creatine: ScoopsMeter(progress: level, color: color)
        case .mealPrep: MealPrepMeter(progress: level, color: color)
        case .focusSession: BatteryMeter(progress: level, color: color)
        case .sunriseAlarm: SunriseMeter(progress: level, color: color)
        case .sleepOnTime: MoonPhasesMeter(progress: level, color: color)
        case .reading: BookshelfMeter(progress: level, color: color)
        case .custom: StarsMeter(progress: level, color: color)
        }
    }
}

// MARK: - Shared pieces

/// `count` items in a row; item `i` gets its own fill (0...1), so the row fills left to right.
struct MeterItemRow<Item: View>: View {
    let count: Int
    let progress: Double
    var spacing: CGFloat = 3
    let item: (_ index: Int, _ fill: Double) -> Item

    init(count: Int, progress: Double, spacing: CGFloat = 3, @ViewBuilder item: @escaping (_ index: Int, _ fill: Double) -> Item) {
        self.count = count
        self.progress = progress
        self.spacing = spacing
        self.item = item
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                item(index, Self.fill(index: index, count: count, progress: progress))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    static func fill(index: Int, count: Int, progress: Double) -> Double {
        min(max(progress * Double(count) - Double(index), 0), 1)
    }
}

/// An item drawn empty, with the filled version revealed over it up to `fill` (left to right, or
/// bottom to top).
struct MeterReveal<Empty: View, Filled: View>: View {
    enum Axis { case horizontal, vertical }

    let fill: Double
    var axis: Axis = .horizontal
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let filled: () -> Filled

    var body: some View {
        ZStack {
            empty()
            filled()
                .mask {
                    GeometryReader { proxy in
                        switch axis {
                        case .horizontal:
                            Rectangle()
                                .frame(width: proxy.size.width * fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        case .vertical:
                            Rectangle()
                                .frame(height: proxy.size.height * fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
        }
    }
}

extension Shape {
    /// The meters' glossy paint: the colour, a lit top and a shaded bottom.
    func meterGloss(_ color: Color) -> some View {
        ZStack {
            fill(color)
            fill(LinearGradient(
                colors: [Color.white.opacity(0.42), Color.white.opacity(0), Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    /// The meters' empty slot: a faint wash of the colour and a dashed outline.
    func meterGhost(_ color: Color, lineWidth: CGFloat = 1.5) -> some View {
        ZStack {
            fill(color.opacity(0.10))
            stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth, dash: [3, 2.5]))
        }
    }
}

#Preview("Goal meters") {
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(GoalType.allCases, id: \.self) { goal in
                HStack(spacing: 10) {
                    ForEach([0.0, 0.45, 1.0], id: \.self) { value in
                        ZanoGoalMeter(goal: goal, progress: value)
                    }
                }
            }
        }
        .padding()
    }
}
