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
//
// Character pass (session 30, 2026-10-06): picking spins the hero round to the new buddy, which
// cheers (excited) for a moment and settles happy, with a burst in its colour; the picked tile's
// sprite cheers and hops too, and the other tiles idle with a slow, out-of-step bob so the grid
// feels alive. "Team up" is a moment: the hero goes ecstatic with a burst and a success haptic, and
// the screen moves on ~0.55s later. Reduce Motion: no spin, bob or delay; the faces still change.

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
    @State private var heroPose: BuddyPose = .happy
    @State private var poseTask: Task<Void, Never>?
    @State private var teamUpTick = 0
    @State private var isTeamingUp = false

    private static let heroSize: CGFloat = 96
    private static let tileSpriteSize: CGFloat = 64

    var body: some View {
        content
            .zanoActionBar { teamUpButton }
            .sensoryFeedback(.impact(weight: .light), trigger: buddy)
            .sensoryFeedback(.success, trigger: teamUpTick)
            .onDisappear {
                poseTask?.cancel()
                // Session 47: the family portrait shows this buddy on everyone's phone (does nothing unless Household is live).
                Task { await HouseholdBuddySync.syncIfNeeded() }
            }
            .onChange(of: buddy) { _, _ in WidgetRefresh.reloadAll() }
            .modifier(BuddyPickerChrome(isSettings: context == .settings))
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header
                BuddyHeroStage(buddy: buddy, pose: heroPose, hopTick: hopTick, burstTick: teamUpTick, size: Self.heroSize)
                if context == .settings {
                    // Growth (level, next reward, earned gear) right under your buddy; not in
                    // onboarding, where nothing is earned yet.
                    BuddyGearSection(buddy: buddy)
                    NavigationLink {
                        BuddyClosetView()
                    } label: {
                        Label(Copy.buddyStyle.openClosetButtonTitle, systemImage: "tshirt.fill")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .zanoCard()
                    }
                    .buttonStyle(.pressable(scale: 0.97))
                }
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
        guard !isTeamingUp else { return }
        buddy = option
        if !reduceMotion { hopTick += 1 }
        // A cheer, then settle: the new buddy is pleased to be picked.
        heroPose = .excited
        poseTask?.cancel()
        poseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            heroPose = .happy
        }
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
        guard !isTeamingUp else { return }
        isTeamingUp = true
        Analytics.shared.capture(event: "buddy_picked", properties: ["buddy": buddy.rawValue])
        BuddyAppIcon.apply(buddy)
        poseTask?.cancel()
        heroPose = .ecstatic
        teamUpTick += 1
        if !reduceMotion { hopTick += 1 }
        poseTask = Task { @MainActor in
            // Long enough to see the celebration land; never a wait under Reduce Motion.
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(550)) }
            switch context {
            case .onboarding: onTeamUp()
            case .settings: dismiss()
            }
            isTeamingUp = false
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
    let pose: BuddyPose
    let hopTick: Int
    /// Bumped by "Team up": a burst in the buddy's colour.
    let burstTick: Int
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
            BuddySprite(buddy, pose: pose, size: size)
                .modifier(BuddySpin(trigger: hopTick))
                .modifier(BuddyHop(trigger: hopTick, height: size * 0.16))
                .zanoChargeBurst(trigger: burstTick, color: buddy.color)
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
/// One full turn about the vertical axis on each `trigger` (the new buddy spinning round to face
/// you). Ends at 0 so the next trigger starts from rest. Callers only bump it outside Reduce Motion.
private struct BuddySpin: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
            view.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        } keyframes: { _ in
            CubicKeyframe(360, duration: 0.42)
            LinearKeyframe(0, duration: 0.001)
        }
    }
}

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
                BuddySprite(buddy, pose: isSelected ? .excited : .idle, size: spriteSize)
                    .modifier(BuddyHop(trigger: isSelected && !reduceMotion ? 1 : 0, height: spriteSize * 0.14))
                    .modifier(BuddyIdleBob(isActive: !isSelected && !reduceMotion, delay: Self.bobDelay(for: buddy)))
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

    /// Out of step on purpose: each tile starts its bob a little after the one before.
    private static func bobDelay(for buddy: Buddy) -> Double {
        Double(Buddy.allCases.firstIndex(of: buddy) ?? 0) * 0.17
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

/// A slow two-point bob (up 2pt, down again) while `isActive`: an idle buddy breathing.
private struct BuddyIdleBob: ViewModifier {
    let isActive: Bool
    let delay: Double

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([0.0, -2.5]) { view, lift in
                view.offset(y: lift)
            } animation: { lift in
                .easeInOut(duration: 0.9).delay(lift == 0 ? delay : 0)
            }
        } else {
            content
        }
    }
}

#Preview("Pick your buddy") {
    NavigationStack {
        BuddyPickerView(context: .settings)
    }
}
