// BuddyPickerView.swift
// App / ZANO / Features / Buddy
//
// "Pick your buddy" (mascot redesign, 2026-10-03; docs/design/visual-direction-v2.md §11). Nine
// pixel-art buddies replace the ZANO star as the app's character; this screen picks one. It is shown
// twice: as onboarding step 2 (right after the hook) and from Settings > Buddy.
//
// Layout, on the app's ink canvas: a hero glass stage (`zanoHero`) with the selected buddy (96pt) beside its name, a
// soft radial glow in its signature colour behind it (the screen's one glow) and an elliptical shadow
// under its feet; its name in big rounded heavy type, what it is and its world under that; a 3x3 grid
// of glass tiles (sprite + name), the selected one with a 2pt rim in the buddy's colour over an ~18%
// tint of it; and one solid "Team up with <name>" button in the buddy's colour with a dark ink label.
//
// The choice is stored on every tap (`@AppStorage(Buddy.storageKey, store: SharedDefaults.store)`,
// the App Group, so widgets and the Screen Time report draw the same buddy), with a light haptic and
// a little hop of the hero (none under Reduce Motion). "Team up" also makes the buddy the Home Screen
// icon (`BuddyAppIcon`), then moves on: the next onboarding step, or back out of Settings. Sprites
// are drawn at 64 and 96pt (multiples of 16pt, so their 48px grid stays even on 3x screens); the
// compact hero keeps all nine tiles above the button on a 6.1" phone.

import SwiftUI
import Core

struct BuddyPickerView: View {
    enum Context {
        /// Onboarding step 2: the scaffold paints the backdrop and the header; the button advances.
        case onboarding
        /// Pushed from Settings: paints its own backdrop; the button pops back.
        case settings
    }

    let context: Context
    /// Called by "Team up" in onboarding (Settings dismisses instead).
    var onTeamUp: () -> Void = {}

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var hopTick = 0

    private static let heroSize: CGFloat = 96
    private static let tileSpriteSize: CGFloat = 64

    var body: some View {
        content
            .zanoActionBar { teamUpButton }
            .sensoryFeedback(.impact(weight: .light), trigger: buddy)
            .onChange(of: buddy) { _, _ in WidgetRefresh.reloadAll() }
            .modifier(BuddyPickerChrome(isSettings: context == .settings))
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header
                BuddyHeroStage(buddy: buddy, hopTick: hopTick, size: Self.heroSize)
                grid
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(Copy.buddy.pickerTitle)
                .zanoText(.display)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.buddy.pickerSubtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            ForEach(Buddy.allCases) { option in
                BuddyTile(buddy: option, isSelected: option == buddy, spriteSize: Self.tileSpriteSize) {
                    pick(option)
                }
            }
        }
    }

    private func pick(_ option: Buddy) {
        buddy = option
        if !reduceMotion { hopTick += 1 }
    }

    // MARK: Button

    private var teamUpButton: some View {
        Button(action: teamUp) {
            Text(Copy.buddy.teamUp(buddy))
                .font(Theme.Typography.headline.weight(.heavy))
                .foregroundStyle(Theme.BuddyColors.onSignature)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(buddy.color))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable(scale: 0.97))
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: buddy)
    }

    private func teamUp() {
        Analytics.shared.capture(event: "buddy_picked", properties: ["buddy": buddy.rawValue])
        BuddyAppIcon.apply(buddy)
        switch context {
        case .onboarding: onTeamUp()
        case .settings: dismiss()
        }
    }
}

/// Settings paints its own backdrop and an inline title; onboarding's scaffold does both itself.
private struct BuddyPickerChrome: ViewModifier {
    let isSettings: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSettings {
            content
                .zanoBackdrop()
                .navigationTitle(Copy.buddy.settingsRow)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

// MARK: - Hero stage

/// The selected buddy, big, on a raised glass stage: a soft radial glow in its colour, an elliptical
/// shadow under its feet, a hop on every pick. Name, kind and world under it. One VoiceOver element.
private struct BuddyHeroStage: View {
    let buddy: Buddy
    let hopTick: Int
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The kind line in the buddy's colour on ink; in light mode the brighter signatures (lime,
    /// sun) don't read as text on white, so it falls back to `textSecondary`.
    private var kindColor: Color {
        colorScheme == .dark ? buddy.color : Theme.Colors.textSecondary
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            stage
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Copy.buddy.name(buddy))
                    .font(Theme.Typography.display.weight(.heavy))
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                Text(Copy.buddy.kind(buddy))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(kindColor)
                    .fixedSize(horizontal: false, vertical: true)
                worldChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .zanoHero()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.buddy.heroLabel(buddy))
    }

    /// The sprite on its floor shadow. The glow sits in the background so its size never pushes the
    /// sprite around.
    private var stage: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Theme.Colors.shadow)
                .frame(width: size * 0.62, height: size * 0.1)
                .offset(y: size * 0.03)
            BuddySprite(buddy, pose: .happy, size: size)
                .modifier(BuddyHop(trigger: hopTick, height: size * 0.16))
        }
        .frame(width: size + Theme.Spacing.md, height: size + Theme.Spacing.sm)
        .background {
            if !reduceTransparency {
                glow
            }
        }
    }

    private var glow: some View {
        RadialGradient(
            colors: [buddy.color.opacity(0.45), buddy.color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: size * 0.9
        )
        .frame(width: size * 1.8, height: size * 1.8)
        .allowsHitTesting(false)
    }

    /// The buddy's world as a small solid chip in its colour (dark ink label, legible in both
    /// appearances).
    private var worldChip: some View {
        Text(Copy.buddy.world(buddy))
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.BuddyColors.onSignature)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Capsule().fill(buddy.color))
    }
}

/// A quick hop: up, then a bouncy landing. Fired by bumping `trigger`; the picker never bumps it
/// under Reduce Motion.
private struct BuddyHop: ViewModifier {
    let trigger: Int
    let height: CGFloat

    func body(content: Content) -> some View {
        // A plain value: the keyframe closures are `@Sendable`.
        let leap = height
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, lift in
            view.offset(y: -lift)
        } keyframes: { _ in
            CubicKeyframe(leap, duration: 0.16)
            SpringKeyframe(0, duration: 0.42, spring: .bouncy)
        }
    }
}

// MARK: - Tile

/// One glass tile: the sprite over its name. Selected: a 2pt rim in the buddy's colour over an ~18%
/// tint of it. At least 88pt tall (well past the 44pt target).
private struct BuddyTile: View {
    let buddy: Buddy
    let isSelected: Bool
    let spriteSize: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                BuddySprite(buddy, pose: .idle, size: spriteSize)
                Text(Copy.buddy.name(buddy))
                    .font(Theme.Typography.label)
                    .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background { shape.fill(isSelected ? buddy.color.opacity(0.18) : Theme.Colors.glassFill) }
            .overlay { rim(shape) }
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.94))
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityLabel(Copy.buddy.tileLabel(buddy))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func rim(_ shape: RoundedRectangle) -> some View {
        if isSelected {
            shape.strokeBorder(buddy.color, lineWidth: 2)
        } else {
            shape.strokeBorder(Theme.Colors.hairline, lineWidth: 1)
        }
    }
}

#Preview("Pick your buddy") {
    NavigationStack {
        BuddyPickerView(context: .settings)
    }
}
