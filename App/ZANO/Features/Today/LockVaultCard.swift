// LockVaultCard.swift
// App / ZANO / Features / Today
//
// The lock-state hero shared by Today and Lock (docs/design/premium-ui-plan.md Phase 2, "vault
// card"; spec §5.1, §16 P1). The product's core idea is "your apps are locked away until you earn
// them back", so this card shows exactly that instead of a sentence about it:
//
//   * the apps themselves, dimmed behind a lock (FamilyControls' own `Label(token)` icons, the same
//     rendering Screen4AppSelection uses; the tokens never leave the device, this only draws them);
//   * one huge condensed number that says what it buys ("2" / "goals to unlock");
//   * concentric rings, one per goal, nested like Activity rings, each filling in *that goal's*
//     color as the day goes, so the card slowly takes on the color of the work you've done
//     ("light is earned", premium-ui-plan.md §4).
//
// Locked is cool navy (`lockedAmbient` wash, `textSecondary` glyph): red is reserved for emergency.
// The earned state (`.unlocking` / all done) is the one place the card glows accent.
//
// v2 (docs/design/visual-direction-v2.md): the raised glass hero (radius `hero`), a lock medallion
// beside the set's name instead of a "Locked · Name" eyebrow, the "since" time as a glass chip, the
// score face for the number, bigger rings.
//
// Pass 2 "playful" (2026-10-03, docs/design/visual-direction-v2.md "Pass 2: playful"): the vault has a
// tenant. A little padlock lives in the middle of the rings and acts out the lock: it droops while
// nothing is done, sits up once something is, wobbles every time a goal lands, and pops open (and
// bounces) when the day is earned. Each ring lights up as its goal finishes: full colour, a stronger
// glow and a sparkle sticker at the top of the ring. The medallion is a sticker; the number rolls.

import SwiftUI
import FamilyControls
import ManagedSettings
import Core

/// One goal in the vault: a ring in the concentric stack (and a slot in the segmented bar).
struct VaultSegment: Identifiable, Equatable {
    let id: UUID
    let color: Color
    let isDone: Bool
    /// `0...1`, today's progress toward the goal.
    var progress: Double = 0
}

struct LockVaultCard: View {

    enum Status: Equatable {
        case setup
        case locked
        case earned
        case unlocked
    }

    let status: Status
    /// "Locked · Social", "Unlocked", "Setup"…
    let eyebrow: String
    /// Trailing detail on the eyebrow row ("since 7:00 AM").
    var detail: String? = nil
    /// The hero line `NumeralText` splits into a big number and a quiet tail ("2 goals to unlock").
    var numeralLine: String? = nil
    /// Used instead of `numeralLine` for states that are a sentence ("Finish setup to start locking").
    var message: String? = nil
    /// A quiet line under the hero number naming what's left ("Gym session + Protein").
    var caption: String? = nil
    var segments: [VaultSegment] = []
    /// A small accent chip (Earn Mode's banked minutes).
    var chip: String? = nil
    /// The lock set's `FamilyActivitySelection` blob, for the locked-apps strip.
    var appTokensBlob: Data? = nil
    var showsChevron: Bool = false
    /// Drives the number roll.
    var changeKey: Int = 0

    // Explicit because the private `@Environment` properties below would make the memberwise
    // initializer private, and Today/Lock build this from other files.
    init(
        status: Status,
        eyebrow: String,
        detail: String? = nil,
        numeralLine: String? = nil,
        message: String? = nil,
        caption: String? = nil,
        segments: [VaultSegment] = [],
        chip: String? = nil,
        appTokensBlob: Data? = nil,
        showsChevron: Bool = false,
        changeKey: Int = 0
    ) {
        self.status = status
        self.eyebrow = eyebrow
        self.detail = detail
        self.numeralLine = numeralLine
        self.message = message
        self.caption = caption
        self.segments = segments
        self.chip = chip
        self.appTokensBlob = appTokensBlob
        self.showsChevron = showsChevron
        self.changeKey = changeKey
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            topRow
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    heroLine
                    if let caption {
                        Text(caption)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let chip {
                        chipView(chip)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !segments.isEmpty {
                    ConcentricGoalRings(segments: segments, diameter: 140, lock: lockMood)
                }
            }
            LockedAppsStrip(blob: appTokensBlob, isLocked: status == .locked)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .zanoHero(
            tint: reduceTransparency ? nil : washTint,
            active: status == .earned && !reduceTransparency
        )
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: status)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: segments)
    }

    // MARK: - Pieces

    private var topRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            statusDot
            Text(eyebrow)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Theme.Spacing.xs)
            if let detail {
                ZanoGlassChip(detail, systemImage: "clock", tint: Theme.Colors.muted)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    /// The lock medallion: the state's glyph as a sticker, filled ZANO Blue once earned.
    private var statusDot: some View {
        ZanoSticker(
            systemImage: statusSymbol,
            color: status == .earned ? Theme.Colors.accent : Theme.Colors.textSecondary,
            style: status == .earned ? .filled : .tinted,
            size: .regular,
            bounceTrigger: status == .earned ? 1 : 0
        )
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
    }

    /// How the padlock in the rings feels.
    private var lockMood: VaultLockMood {
        switch status {
        case .earned, .unlocked: .open
        case .setup: .resting
        case .locked: segments.contains(where: \.isDone) ? .perky : .resting
        }
    }

    @ViewBuilder
    private var heroLine: some View {
        if let numeralLine {
            // The number alone at poster size, its words on their own line beneath: beside the
            // rings there's no room for "2 goals to unlock" on one line at 88pt.
            VStack(alignment: .leading, spacing: 0) {
                NumeralText(
                    numeralLine,
                    size: .hero,
                    color: status == .earned ? Theme.Colors.accent : Theme.Colors.text,
                    remainder: .hidden
                )
                .animation(reduceMotion ? nil : Theme.Motion.numberRoll, value: changeKey)
                Text(NumeralText.remainder(of: numeralLine))
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(numeralLine)
        } else if let message {
            Text(message)
                .font(Theme.Typography.titleLarge)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chipView(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.accent)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.Colors.accentWash, in: Capsule())
            .fixedSize()
    }

    // MARK: - State styling

    private var statusSymbol: String {
        switch status {
        case .setup: "gearshape.fill"
        case .locked: "lock.fill"
        case .earned: "checkmark"
        case .unlocked: "lock.open.fill"
        }
    }


    private var washTint: Color? {
        switch status {
        case .locked: Theme.Colors.lockedAmbient
        case .earned: Theme.Colors.accent
        case .setup, .unlocked: nil
        }
    }
}

// MARK: - Concentric rings

/// The padlock's mood in the middle of the vault rings (pass 2).
enum VaultLockMood: Equatable {
    /// Nothing done yet: drooping, dim.
    case resting
    /// Something done: sitting up.
    case perky
    /// Earned: popped open, lit.
    case open
}

/// The vault's signature: one ring per goal, nested like Apple's Activity rings, each in its goal's
/// color, sweeping from dim to full hue as the day's progress grows. A done ring is full, glows, and
/// wears a sparkle at its top (pass 2). Outermost ring = first goal. Capped at four rings (a fifth is
/// too thin to read); the segmented bar is the fallback for more. With `lock`, a little padlock
/// character sits in the middle (pass 2).
struct ConcentricGoalRings: View {
    let segments: [VaultSegment]
    let diameter: CGFloat
    var lock: VaultLockMood? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxRings = 4
    private static let gap: CGFloat = 3

    init(segments: [VaultSegment], diameter: CGFloat, lock: VaultLockMood? = nil) {
        self.segments = segments
        self.diameter = diameter
        self.lock = lock
    }

    private var shown: [VaultSegment] { Array(segments.prefix(Self.maxRings)) }

    private var lineWidth: CGFloat {
        // Ring + gap per step must fit inside the radius.
        let steps = CGFloat(max(shown.count, 1))
        return min(16, (diameter / 2 - 14) / steps - Self.gap)
    }

    /// The empty middle, inside the innermost ring.
    private var innerDiameter: CGFloat {
        max(0, diameter - 2 * CGFloat(shown.count) * (lineWidth + Self.gap))
    }

    private var doneCount: Int { segments.filter(\.isDone).count }

    var body: some View {
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, segment in
                ring(segment, inset: CGFloat(index) * (lineWidth + Self.gap))
            }
            if let lock, innerDiameter >= 24 {
                VaultLockCharacter(mood: lock, size: innerDiameter * 0.78, wobble: doneCount)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func ring(_ segment: VaultSegment, inset: CGFloat) -> some View {
        let progress = segment.isDone ? 1 : min(1, max(0, segment.progress))
        return ZStack {
            Circle()
                .stroke(segment.color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                // Pass 3 (restraint): one flat stroke per ring, no sweep, no glow.
                .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0.001 ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: progress)
        }
        .overlay(alignment: .top) {
            // Pass 2: a lit ring wears a sparkle where it starts (12 o'clock).
            if segment.isDone {
                ZanoSparkleShape()
                    .fill(Color.white)
                    .frame(width: lineWidth * 1.3, height: lineWidth * 1.3)
                    .offset(y: -lineWidth / 2)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .padding(inset + lineWidth / 2)
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: segment.isDone)
    }
}

/// The padlock that lives in the vault: no face, just body language. Droops while resting, sits up
/// when perky, wobbles each time `wobble` grows (a goal landed), pops open and bounces when earned.
/// Reduce Motion: the pose without the wobble or bounce.
struct VaultLockCharacter: View {
    let mood: VaultLockMood
    let size: CGFloat
    let wobble: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: mood == .open ? "lock.open.fill" : "lock.fill")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.46, weight: .heavy))
            .foregroundStyle(glyphColor)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .symbolEffect(.bounce, value: reduceMotion ? 0 : (mood == .open ? 1 : 0))
            .frame(width: size, height: size)
            .background {
                if mood == .open {
                    Circle().fill(Theme.Colors.accentFill)
                } else if reduceTransparency {
                    Circle().fill(Theme.Colors.surface2)
                } else {
                    Circle().fill(Theme.Colors.glassFillTop)
                }
            }
            .overlay(Circle().strokeBorder(Theme.Colors.glassEdge, lineWidth: Theme.Metrics.edgeWidth))
            .rotationEffect(.degrees(mood == .resting ? -12 : 0), anchor: .bottom)
            .offset(y: mood == .resting ? size * 0.04 : 0)
            .opacity(mood == .resting ? 0.8 : 1)
            .modifier(VaultLockWobble(trigger: reduceMotion ? 0 : wobble))
            .animation(reduceMotion ? nil : Theme.Motion.springPop, value: mood)
    }

    private var glyphColor: Color {
        switch mood {
        case .resting: Theme.Colors.textSecondary
        case .perky: Theme.Colors.text
        case .open: Theme.Colors.onAccent
        }
    }
}

/// A quick side-to-side wobble each time `trigger` changes.
private struct VaultLockWobble: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
            view.rotationEffect(.degrees(angle), anchor: .bottom)
        } keyframes: { _ in
            CubicKeyframe(16, duration: 0.1)
            CubicKeyframe(-12, duration: 0.12)
            CubicKeyframe(7, duration: 0.12)
            SpringKeyframe(0, duration: 0.3, spring: .bouncy)
        }
    }
}

// MARK: - Segmented bar

/// One capsule per required goal, filled in that goal's own color once it's done. Decorative: the
/// card's spoken label carries the count.
struct VaultSegmentBar: View {
    let segments: [VaultSegment]

    private static let height: CGFloat = 10

    /// v2: each slot fills with its goal's progress (not only when done), in the goal's colour on
    /// that colour's own dim track, and glows once done.
    var body: some View {
        HStack(spacing: Theme.Spacing.xs - 2) {
            ForEach(segments) { segment in
                let fraction = segment.isDone ? 1 : min(1, max(0, segment.progress))
                Capsule()
                    .fill(Theme.Colors.Ring.track(for: segment.color))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(segment.color)
                                .frame(width: max(fraction > 0 ? Self.height : 0, proxy.size.width * fraction))
                        }
                    }
                    .clipShape(Capsule())
                    .frame(height: Self.height)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Locked apps

/// The lock set's apps as a row of overlapping icons, dimmed and desaturated while locked. Renders
/// nothing when the set has no tokens (the Simulator, or a set saved before any app was picked).
struct LockedAppsStrip: View {
    let blob: Data?
    let isLocked: Bool

    private static let maxTiles = 5
    private static let tileSize: CGFloat = 40

    private enum Tile: Hashable, Identifiable {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)
        var id: Self { self }
    }

    private var selection: FamilyActivitySelection? {
        guard let blob else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: blob)
    }

    var body: some View {
        if let selection {
            let apps = selection.applicationTokens.map(Tile.app)
            let categories = selection.categoryTokens.map(Tile.category)
            let all = apps + categories
            let shown = Array(all.prefix(Self.maxTiles))
            let overflow = all.count - shown.count
            if !shown.isEmpty {
                HStack(spacing: -Theme.Spacing.xs) {
                    ForEach(shown) { tile in
                        tileFrame { icon(tile) }
                    }
                    if overflow > 0 {
                        tileFrame {
                            Text("+\(overflow)")
                                .font(Theme.Typography.numeralSmall())
                                .foregroundStyle(Theme.Colors.text)
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func icon(_ tile: Tile) -> some View {
        Group {
            switch tile {
            case .app(let token): Label(token).labelStyle(.iconOnly)
            case .category(let token): Label(token).labelStyle(.iconOnly)
            }
        }
        .saturation(isLocked ? 0 : 1)
        .opacity(isLocked ? 0.55 : 1)
    }

    private func tileFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return content()
            .frame(width: Self.tileSize, height: Self.tileSize)
            .background(Theme.Colors.surface2, in: shape)
            .overlay(shape.strokeBorder(Theme.Colors.surface, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Colors.text)
                        .frame(width: 16, height: 16)
                        .background(Theme.Colors.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }
    }
}
