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
// Locked keeps spec §15's `danger` only as the small status dot and a faint wash; the earned state
// (`.unlocking` / all done) is the one place the card glows accent.

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
                    ConcentricGoalRings(segments: segments, diameter: 132)
                }
            }
            LockedAppsStrip(blob: appTokensBlob, isLocked: status == .locked)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .zanoHero(
            tint: reduceTransparency ? nil : washTint,
            active: status == .earned && !reduceTransparency
        )
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: status)
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: segments)
    }

    // MARK: - Pieces

    private var topRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            statusDot
            Text(eyebrow)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    /// A small filled glyph in a tinted disc: the state at a glance, in the state's color.
    private var statusDot: some View {
        Image(systemName: statusSymbol)
            .font(Theme.Typography.icon(.xsmall, weight: .bold))
            .foregroundStyle(status == .earned ? Theme.Colors.onFill : statusColor)
            .frame(width: 24, height: 24)
            .background(status == .earned ? statusColor : Theme.Colors.wash(statusColor), in: Circle())
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
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
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: changeKey)
                Text(NumeralText.remainder(of: numeralLine))
                    .font(.system(.title3, weight: .bold).width(.condensed))
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

    private var statusColor: Color {
        switch status {
        case .setup, .unlocked: Theme.Colors.textSecondary
        case .locked: Theme.Colors.danger
        case .earned: Theme.Colors.accent
        }
    }

    private var washTint: Color? {
        switch status {
        case .locked: Theme.Colors.danger
        case .earned: Theme.Colors.accent
        case .setup, .unlocked: nil
        }
    }
}

// MARK: - Concentric rings

/// The vault's signature: one ring per goal, nested like Apple's Activity rings, each in its goal's
/// color, sweeping from dim to full hue as the day's progress grows. A done ring is full and
/// glows. Outermost ring = first goal. Capped at four rings (a fifth is too thin to read); the
/// segmented bar is the fallback for more.
struct ConcentricGoalRings: View {
    let segments: [VaultSegment]
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxRings = 4

    init(segments: [VaultSegment], diameter: CGFloat) {
        self.segments = segments
        self.diameter = diameter
    }

    private var shown: [VaultSegment] { Array(segments.prefix(Self.maxRings)) }

    private var lineWidth: CGFloat {
        // Ring + gap per step must fit inside the radius.
        let steps = CGFloat(max(shown.count, 1))
        return min(16, (diameter / 2 - 14) / steps - 3)
    }

    var body: some View {
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, segment in
                ring(segment, inset: CGFloat(index) * (lineWidth + 3))
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
                .stroke(
                    AngularGradient(
                        colors: [segment.color.opacity(0.6), segment.color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(max(1, 360 * progress))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: segment.color.opacity(segment.isDone ? 0.55 : 0.3), radius: lineWidth * 0.6)
                .opacity(progress > 0.001 ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.ringFill, value: progress)
        }
        .padding(inset + lineWidth / 2)
    }
}

// MARK: - Segmented bar

/// One capsule per required goal, filled in that goal's own color once it's done. Decorative: the
/// card's spoken label carries the count.
struct VaultSegmentBar: View {
    let segments: [VaultSegment]

    private static let height: CGFloat = 8

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(segments) { segment in
                Capsule()
                    .fill(segment.isDone ? segment.color : Theme.Colors.track)
                    .frame(height: Self.height)
                    .shadow(color: segment.isDone ? segment.color.opacity(0.45) : .clear, radius: 6)
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
