// GoalRing.swift
// Core / UI / Components
//
// A single circular progress ring for one goal, per docs/spec.md §15's core component list and
// the P1/P3 mockups in §16 ("three progress rings labeled Workout, Protein (72/150g), Focus (25/50
// min)"). Built entirely from `Theme` tokens; carries no copy of its own — every piece of text is
// supplied pre-composed by the caller (CLAUDE.md: "User-facing copy lives in Core/Sources/Core/
// Copy — no hardcoded UI strings elsewhere"), so this file never imports or duplicates Copy.
//
// Design-quality pass (docs/design/{competitive-research,composition-audit,better-ui-findings}.md):
//
//   * The number goes INSIDE the ring. The ring centre used to be an SF Symbol and the value
//     ("72/150g") a 13pt muted caption beneath — the smallest text on screen was the most
//     important number in the app. `GoalRingCenter.value` (and `.text`, which now splits
//     "value/target unit" strings) puts the value in a numeral sized from the ring's own diameter
//     and the target/unit under it. Where WHOOP and Cal AI put the number.
//   * The track is the ring's own hue at 30%, not a neutral `surface2` (1.16:1 on `background`, so
//     a 0% ring vanished). An empty ring still reads as *that goal's* ring.
//   * The stroke is inset so the ring's outer edge equals its frame. It used to be centred on the
//     frame edge and overflow by half a stroke, overlapping neighbours.
//   * A soft static glow on the filled arc, stronger when complete — the "active element" glow of
//     spec §16, never animated (HIG: avoid animating depth/blur under Reduce Motion).
//   * `Size.hero` (200pt) and `Size.custom(_:)` (any diameter) so rings can be fitted to a width
//     instead of overflowing it — three `.large` rings were 500pt wide in a 361pt column.
//   * `GoalRingCenter.add` is the empty state: a dashed outline and a plus, an invitation instead
//     of a rendering bug.

import SwiftUI

/// What renders in the center of a `GoalRing`. Kept as an enum (rather than several optional
/// properties) so a caller can't accidentally supply conflicting content at once.
public enum GoalRingCenter: Equatable, Sendable {
    /// An SF Symbol name (e.g. `"dumbbell.fill"`). Symbol names are identifiers, not user-facing
    /// copy, so they're fine to pass as plain strings.
    case icon(systemName: String)
    /// A fully-composed value string the caller has already formatted (e.g. `"72/150g"`,
    /// `"25 min"`, `"0:45"`). `GoalRing` never formats numbers or appends units itself. A string of
    /// the form "value/target unit" ("72/150g", "25/50 min") is *styled* as a big value over a
    /// small "/150g" — the string itself is untouched; anything else is shown on one line in the
    /// ring's numeral face.
    case text(String)
    /// An explicit value and optional unit/target line (e.g. `.value("72", unit: "/150g")`). The
    /// unit is hidden on rings too small to fit it (under 72pt).
    case value(String, unit: String?)
    /// The unconfigured/empty state: a dashed outline instead of a track, and a plus glyph.
    case add
    /// No center content — just the ring.
    case none
}

/// A circular progress indicator for a single goal's completion fraction. Used standalone (e.g. a
/// hero ring on the Today screen) or composed inside `RingCluster`.
public struct GoalRing: View {

    /// Preset diameters/line widths so rings stay consistent across screens instead of every call
    /// site inventing its own numbers.
    public enum Size: Sendable, Equatable {
        case small
        case medium
        case large
        /// 200pt — one dominant ring on a screen (the goal the primary button acts on).
        case hero
        /// Any diameter; the stroke scales with it (`Theme.Metrics.ringStrokeRatio`). What
        /// `RingCluster` uses to fit rings to the available width.
        case custom(CGFloat)

        public var diameter: CGFloat {
            switch self {
            case .small: 44
            case .medium: 88
            case .large: 148
            case .hero: 200
            case .custom(let diameter): max(0, diameter)
            }
        }

        public var lineWidth: CGFloat {
            switch self {
            case .small: 5
            case .medium: 9
            case .large: 14
            case .hero: 18
            case .custom(let diameter): max(3, (diameter * Theme.Metrics.ringStrokeRatio).rounded())
            }
        }
    }

    private let progress: Double
    private let color: Color
    private let size: Size
    private let center: GoalRingCenter
    private let label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tracks whether the ring has ever reached 100%, purely to detect the *moment* it first
    /// crosses that threshold (`.onChange` below) and play a one-shot completion pulse. This is
    /// deliberately self-contained state, not a caller-supplied flag — `GoalRing` is a value-driven
    /// view with no other notion of "before"/"after", but `@State` still persists across body
    /// re-evaluations for the same view identity, so it can detect its own progress crossing 1.0
    /// without the caller having to track history itself (docs/design/animation-opportunities.md
    /// row 4b).
    @State private var justCompleted = false

    /// - Parameters:
    ///   - progress: Completion fraction. Any value is accepted and clamped to `0...1` internally
    ///     — callers computing `current / target` don't need to clamp themselves.
    ///   - color: Ring tint. Pass `Theme.Colors.Ring.color(for:)` for a goal-typed ring, or any
    ///     other `Theme` color for a purpose-specific ring (e.g. `Theme.Colors.accent` for a
    ///     generic Time Bank / earn-progress ring).
    ///   - size: Preset diameter/line-width. Defaults to `.medium`.
    ///   - center: What to render in the ring's center. Defaults to `.none`.
    ///   - label: Optional caller-composed VoiceOver label naming what this ring represents (e.g.
    ///     `"Workout"`, `"Protein"`). Defaults to `nil`, matching this component's previous
    ///     behavior. Pass one for a ring shown standalone with no adjacent text describing it; a
    ///     ring already followed by its own title/value text (e.g. inside `RingClusterCell`/
    ///     `GoalRow`, both of which combine their own child text into one announcement) can leave
    ///     this `nil` to avoid a doubled-up VoiceOver read. See
    ///     `docs/design/ui-stress-test-findings.md` §2.2.
    public init(
        progress: Double,
        color: Color = Theme.Colors.accent,
        size: Size = .medium,
        center: GoalRingCenter = .none,
        label: String? = nil
    ) {
        self.progress = progress
        self.color = color
        self.size = size
        self.center = center
        self.label = label
    }

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    private var isComplete: Bool {
        clampedProgress >= 1
    }

    private var isPlaceholder: Bool {
        center == .add
    }

    public var body: some View {
        let diameter = size.diameter
        let lineWidth = size.lineWidth

        return ZStack {
            trackRing(lineWidth: lineWidth)
            progressArc(lineWidth: lineWidth)
            centerContent(diameter: diameter, lineWidth: lineWidth)
        }
        // One-shot delight beat the moment this ring first reaches 100%, scaling the whole ring +
        // center content together rather than just the stroke — purely visual (no haptic here:
        // screens that already fire a completion haptic, e.g. Today's
        // `.sensoryFeedback(.impact...)`, would otherwise double up; this stays a silent companion
        // for every other place GoalRing renders standalone). Dropped entirely under Reduce
        // Motion rather than swapped for a static variant: the ring is already visibly full, so no
        // information is lost by skipping the pulse (docs/design/animation-opportunities.md row 4b).
        .scaleEffect(justCompleted && !reduceMotion ? 1.06 : 1.0)
        // Explicit `reduceMotion ? nil : ...`, the idiom every other animation in this safe set
        // uses (see `Theme.Motion.standard(reduceMotion:)`'s own doc comment on why `nil`, not a
        // value-parity trick, is the deliberate pattern).
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: justCompleted)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "")
        .accessibilityValue(Text(accessibilityValueText))
        .onChange(of: clampedProgress) { oldValue, newValue in
            guard !reduceMotion, oldValue < 1, newValue >= 1 else { return }
            justCompleted = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                justCompleted = false
            }
        }
    }

    // MARK: - Track and arc

    /// The empty ring: the ring's own hue at 30% (`Ring.track(for:)`), or a dashed outline for the
    /// `.add` placeholder. Inset by half a stroke so the ring's outer edge equals its frame.
    @ViewBuilder
    private func trackRing(lineWidth: CGFloat) -> some View {
        if isPlaceholder {
            Circle()
                .stroke(
                    Theme.Colors.hairlineStrong,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 9])
                )
                .padding(lineWidth / 2)
        } else {
            Circle()
                .stroke(Theme.Colors.Ring.track(for: color), lineWidth: lineWidth)
                .padding(lineWidth / 2)
        }
    }

    /// The filled arc. Always in the view tree (faded out at 0%) rather than conditionally
    /// inserted, so the first fill from 0 animates instead of appearing already drawn — and so
    /// a zero-length round-capped stroke never draws a stray dot at 12 o'clock.
    private func progressArc(lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: clampedProgress)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            // The static "active element" glow (spec §16): soft while in progress, stronger once
            // earned. Never animated — a function of progress only.
            .shadow(color: color.opacity(isComplete ? 0.5 : 0.28), radius: lineWidth * 0.7)
            .padding(lineWidth / 2)
            .opacity(clampedProgress > 0.001 && !isPlaceholder ? 1 : 0)
            // The fill itself is information (a progress fraction), not decoration, so
            // Reduce Motion shortens it rather than removing it entirely — a quick, plain
            // ease still lands on the right value, just without the spec's full 600ms sweep
            // (docs/design/apple-design-review.md §1 fix pattern).
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: clampedProgress)
    }

    // MARK: - Center

    /// VoiceOver's spoken value for this ring. Prefers the caller's own composed center text (e.g.
    /// `"72/150g"`) when there is one — that's strictly more informative than a bare percentage and
    /// is otherwise invisible to VoiceOver (this view's `.accessibilityElement(children: .ignore)`
    /// above removes `centerContent`'s own `Text` from the tree) — falling back to the percentage
    /// for an icon/empty center, which has no such text to borrow. See
    /// `docs/design/ui-stress-test-findings.md` §2.2.
    private var accessibilityValueText: String {
        switch center {
        case .text(let text):
            return text
        case .value(let value, let unit):
            return [value, unit].compactMap { $0 }.joined(separator: " ")
        case .icon, .add, .none:
            return "\(Int((clampedProgress * 100).rounded()))%"
        }
    }

    /// The numeral for a ring of `diameter`: the named small tier under 60pt, otherwise 30% of the
    /// diameter (88pt → 26, 112pt → 34, 148pt → 44, 200pt → 60), so the value scales with the ring
    /// instead of every size sharing one token.
    private func valueFont(diameter: CGFloat) -> Font {
        diameter < 60 ? Theme.Typography.numeralSmall() : Theme.Typography.numeral(size: diameter * 0.30)
    }

    @ViewBuilder
    private func centerContent(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        switch center {
        case .icon(let systemName):
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.34, weight: .semibold))
                .foregroundStyle(color)
        case .text(let composed):
            if let parts = ProgressTextSplit.split(composed) {
                valueStack(value: parts.value, unit: parts.unit, diameter: diameter, lineWidth: lineWidth)
            } else {
                Text(composed)
                    .font(valueFont(diameter: diameter))
                    .foregroundStyle(Theme.Colors.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, lineWidth + diameter * 0.05)
            }
        case .value(let value, let unit):
            valueStack(value: value, unit: unit, diameter: diameter, lineWidth: lineWidth)
        case .add:
            Image(systemName: "plus")
                .font(.system(size: diameter * 0.28, weight: .semibold))
                .foregroundStyle(Theme.Colors.muted)
        case .none:
            EmptyView()
        }
    }

    /// The big value with the target/unit beneath it. The unit is dropped on rings under 72pt,
    /// where there is no room for a second line.
    private func valueStack(value: String, unit: String?, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(valueFont(diameter: diameter))
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if let unit, diameter >= 72 {
                Text(unit)
                    .font(.system(size: max(11, diameter * 0.115), weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, lineWidth + diameter * 0.05)
    }
}

#Preview("GoalRing") {
    VStack(spacing: Theme.Spacing.lg) {
        HStack(spacing: Theme.Spacing.lg) {
            GoalRing(progress: 0.72, color: Theme.Colors.Ring.protein, size: .small, center: .icon(systemName: "fork.knife"))
            GoalRing(progress: 0.5, color: Theme.Colors.Ring.focus, size: .medium, center: .text("25/50 min"))
            GoalRing(progress: 1.0, color: Theme.Colors.Ring.workout, size: .large, center: .icon(systemName: "dumbbell.fill"))
        }
        HStack(spacing: Theme.Spacing.lg) {
            GoalRing(progress: 0.48, color: Theme.Colors.Ring.protein, size: .custom(112), center: .text("72/150g"))
            GoalRing(progress: 0, color: Theme.Colors.Ring.water, size: .custom(112), center: .add)
            GoalRing(progress: 0.3, color: Theme.Colors.Ring.water, size: .custom(112))
        }
        GoalRing(progress: 0.62, color: Theme.Colors.accent, size: .hero, center: .value("72", unit: "/150g"))
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
