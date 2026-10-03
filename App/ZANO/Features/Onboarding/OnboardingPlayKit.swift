// OnboardingPlayKit.swift
// App / Features / Onboarding
//
// Visual pass 2 (2026-10-03, founder: "make it MORE PLAYFUL"; docs/design/visual-direction-v2.md is
// the system this builds on). Onboarding now plays like a game's character select, and the pieces
// that make it feel that way live here so the steps stay small:
//
//   * `OnboardingGuideStar`   the living star as a guide character: it says one short line in a
//                             glass speech bubble and reacts (a charge burst, a little pop, a soft
//                             haptic) every time its line changes, i.e. every time you answer.
//   * `OnboardingChargeMeter` the header's progress: seven chunky power cells that light up one per
//                             step, ending in the star, which charges with them. Replaces the thin
//                             progress line. Keeps the "Step N of 7" accessibility element.
//   * `OnboardingChargeButton` the hold-to-commit as a charging button: a tall glass capsule that
//                             fills blue-to-violet while held, a bolt that bounces on each tenth,
//                             a glow that grows with the charge, and a burst when it lands.
//                             Same accessibility contract as `PrimaryButton(.holdToCommit)` (a
//                             button whose label is the title; VoiceOver's activate commits).
//   * `OnboardingPickTile`    a chunky selectable glass tile washed in a colour, with a sticker
//                             icon and a check sticker when picked.
//   * `OnboardingSticker`     a point-sized front for Core's `ZanoSticker` (icon-only, filled).
//
// Nothing here edits Core/UI; it only composes `ZanoLivingMark`, `zanoMascot`, `zanoChargeBurst`,
// `ZanoSticker`, `zanoCard`, `zanoGlass` and `Theme` tokens. Every motion is gated on Reduce Motion (the star is still, the
// bubble cross-fades, nothing scales). One orchestrated moment per screen is the caller's job.

import SwiftUI
import Core

// MARK: - Sticker

/// An icon-only sticker in `tint`: Core's `ZanoSticker` (filled, die-cut rim, bounce on
/// `bounceTrigger`), sized from a point size so the steps can say "about 44pt". Decorative.
struct OnboardingSticker: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 44
    /// A bounce plays each time this changes (pass the selection, a tick, ...).
    var bounceTrigger: Int = 0
    /// Degrees of playful lean (icon-only stickers may lean). None under Reduce Motion.
    var tilt: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stickerSize: ZanoSticker.Size {
        if size >= 44 { return .large }
        if size >= 32 { return .regular }
        return .small
    }

    var body: some View {
        ZanoSticker(
            systemImage: systemImage,
            color: tint,
            style: .filled,
            size: stickerSize,
            tilt: reduceMotion ? 0 : tilt,
            bounceTrigger: bounceTrigger
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Guide star

/// The star with a speech bubble. `line` is what it says; whenever it changes the star reacts.
/// `charge` is how full it is (callers raise it as the user answers).
struct OnboardingGuideStar: View {
    let line: String
    var charge: Double = 0.5
    var starHeight: CGFloat = 52
    /// The bubble's accent edge (a goal colour once one is picked).
    var tint: Color = Theme.Colors.accent
    /// `.idle` while it waits for an answer, `.perky` once it has one.
    var mood: ZanoMascotMood = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reactTick = 0

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            ZanoLivingMark(charge: charge, height: starHeight)
                .background {
                    OnboardingKit.StarBloom(diameter: starHeight * 3)
                        .opacity(0.35 + 0.5 * charge)
                }
                // Core's mascot motion: perky once you've answered, a hop each time it reacts.
                .zanoMascot(mood: mood, jump: reactTick, sparkColors: [tint], size: starHeight, showsGlow: false)
                .zanoChargeBurst(trigger: reactTick, color: tint)
                .accessibilityHidden(true)

            bubble
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: line) { _, _ in reactTick += 1 }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: reactTick)
    }

    private var bubble: some View {
        Text(line)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)
            .id(line)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                        removal: .opacity
                    )
            )
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GuideBubbleShape()
                    .fill(Theme.Colors.glassFillTop)
                    .background(GuideBubbleShape().fill(.ultraThinMaterial))
            }
            .overlay {
                GuideBubbleShape(includesTail: false)
                    .stroke(
                        tint.opacity(0.5),
                        lineWidth: 1
                    )
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springPop, value: line)
            .accessibilityElement(children: .combine)
    }
}

/// A rounded speech bubble with a small tail on its leading edge, pointing at the star.
private struct GuideBubbleShape: Shape {
    /// The rim is drawn without the tail, so the outline never cuts across the tail's base.
    var includesTail = true

    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 7
        let body = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: min(18, body.height / 2), style: .continuous)
        guard includesTail else { return path }
        let midY = rect.midY
        path.move(to: CGPoint(x: body.minX, y: midY - 6))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: midY + 2), control: CGPoint(x: body.minX - 2, y: midY - 1))
        path.addQuadCurve(to: CGPoint(x: body.minX, y: midY + 6), control: CGPoint(x: body.minX - 1, y: midY + 5))
        path.closeSubpath()
        return path
    }
}

// MARK: - Charge meter (header progress)

/// Seven power cells, lit up to the current step, ending in the star. Pass 3 (restraint): every lit
/// cell is the one accent blue, no glow; the newest one pops in. The star at the end charges with them.
struct OnboardingChargeMeter: View {
    let step: Int
    let total: Int
    let accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { Double(step) / Double(max(total, 1)) }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            cells
            ZanoLivingMark(charge: fraction, height: 26)
                .zanoChargeBurst(trigger: step, color: Theme.Colors.Aurora.violet)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var cells: some View {
        HStack(spacing: 3) {
            ForEach(1...max(total, 1), id: \.self) { index in
                cell(index)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.Colors.glassFill))
        .overlay(Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: 1))
    }

    private func cell(_ index: Int) -> some View {
        let isLit = index <= step
        let color = isLit ? Theme.Colors.accent : Theme.Colors.track.opacity(0.6)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(height: 10)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.springPop.delay(0.05), value: isLit)
    }
}

// MARK: - Charge button (hold to commit)

/// A 2-second press-and-hold that charges up. Fires `action` once the charge is full; releasing
/// early drains it. VoiceOver: one button whose label is `title`; activating it commits (a sustained
/// hold has no VoiceOver equivalent). Mirrors `PrimaryButton(.holdToCommit)`'s timing and contract,
/// so the UI tests' press-and-hold keeps working.
struct OnboardingChargeButton: View {
    let title: String
    var chargingTitle: String = Copy.onboarding.commitCharging
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHolding = false
    @State private var progress: Double = 0
    @State private var tick = 0
    @State private var commitTick = 0
    @State private var holdTask: Task<Void, Never>?

    private static let height: CGFloat = 64

    var body: some View {
        label
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background { track }
            .overlay { rim }
            .compositingGroup()
            .zanoChargeBurst(trigger: commitTick, color: Theme.Colors.Aurora.violet)
            .scaleEffect(isHolding && !reduceMotion ? 0.97 : 1)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { _ in end() }
            )
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: isHolding)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.4 + 0.5 * progress), trigger: tick)
            .sensoryFeedback(.success, trigger: commitTick)
            .disabled(!isEnabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint(Copy.common.holdControlHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard isEnabled else { return }
                commitTick += 1
                action()
            }
            .onDisappear { holdTask?.cancel() }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: progress > 0 ? "bolt.fill" : "bolt")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : tick)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Colors.text.opacity(0.10 + 0.12 * progress)))
            Text(isHolding ? chargingTitle : title)
                .font(Theme.Typography.headline.weight(.heavy))
                .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.opacity)
            Text("\(Int((progress * 100).rounded()))%")
                .font(Theme.Typography.score(size: 15, weight: .heavy))
                .foregroundStyle(Theme.Colors.text)
                .monospacedDigit()
                .contentTransition(.numericText(value: progress))
                .opacity(isHolding ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            ZanoGlass(Capsule(style: .continuous))
            GeometryReader { proxy in
                // Pass 3 (restraint): a solid accentFill sweep, not a blue-to-violet gradient.
                Rectangle()
                    .fill(Theme.Colors.accentFill)
                    .frame(width: proxy.size.width * progress)
            }
            .clipShape(Capsule(style: .continuous))
        }
    }

    private var rim: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isEnabled
                    ? AnyShapeStyle(Theme.Colors.accent)
                    : AnyShapeStyle(Theme.Colors.hairline),
                lineWidth: 1.5
            )
            .allowsHitTesting(false)
    }

    private func begin() {
        guard isEnabled, !isHolding else { return }
        isHolding = true
        let totalMs = max(1, Int(Theme.Motion.holdToCommitDuration * 1000))
        let tickMs = 50
        let startMs = Int(progress * Double(totalMs))
        let step: Animation? = reduceMotion ? nil : .linear(duration: Double(tickMs) / 1000)
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            var elapsed = startMs
            var lastDecile = Int(progress * 10)
            while elapsed < totalMs {
                try? await Task.sleep(for: .milliseconds(tickMs))
                if Task.isCancelled { return }
                elapsed += tickMs
                let value = min(1, Double(elapsed) / Double(totalMs))
                withAnimation(step) { progress = value }
                let decile = Int(value * 10)
                if decile != lastDecile {
                    lastDecile = decile
                    tick += 1
                }
            }
            guard !Task.isCancelled else { return }
            commitTick += 1
            action()
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            isHolding = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) { progress = 0 }
        }
    }

    private func end() {
        guard isHolding, progress < 1 else { return }
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) { progress = 0 }
    }
}

// MARK: - Pick tile

/// A chunky selectable glass tile: a sticker, a title, the tile washed in `tint`. Picked: a `tint`
/// rim, a stronger wash with a glow, a check sticker in the corner and the sticker bounces.
struct OnboardingPickTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    /// Horizontal (sticker beside the title) for a full-width tile; vertical for a grid tile.
    var isWide = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        Button(action: action) {
            content
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zanoCard(radius: Theme.Radius.medium, tint: tint, active: isSelected)
                .overlay {
                    shape.strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2)
                }
                .overlay(alignment: .topTrailing) { checkSticker }
                .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.95))
        .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1)
        .animation(reduceMotion ? nil : Theme.Motion.springPop, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        if isWide {
            HStack(spacing: Theme.Spacing.sm) {
                OnboardingSticker(systemImage: systemImage, tint: tint, size: 44, bounceTrigger: isSelected ? 1 : 0)
                titleText
                Spacer(minLength: Theme.Spacing.xl)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                OnboardingSticker(systemImage: systemImage, tint: tint, size: 48, bounceTrigger: isSelected ? 1 : 0)
                Spacer(minLength: 0)
                titleText
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(Theme.Typography.headline.weight(.bold))
            .foregroundStyle(Theme.Colors.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var checkSticker: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                .rotationEffect(.degrees(reduceMotion ? 0 : -8))
                .padding(Theme.Spacing.sm)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}
