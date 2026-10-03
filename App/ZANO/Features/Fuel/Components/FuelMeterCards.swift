// FuelMeterCards.swift
// App / Features / Fuel / Components
//
// Playful pass (2026-10-03, docs/design/visual-direction-v2.md, second pass on Fuel). The protein
// and water cards as game meters:
//
//   Protein  header (glyph + name + % chip) / score "72 / 150 g" / segmented power bar /
//            chunky quick-add chips / two sticker buttons (Snap a meal, Scan it).
//   Water    header / a liquid tank beside the score / chunky quick-add chips.
//
// Each card is glass washed in its goal's colour (v2: goal tiles are washed in their colour) and
// lights up with the earned glow when the goal is met. A log makes the glyph bounce, the digits
// roll, a "+25 g" float off the number and (water) the tank slosh. Completing the goal fires the
// shared charge burst on the glyph. All motion is Reduce Motion-gated; haptics are the screen's
// `.success` on a landed log plus a light tap on each chip press.
//
// Data/behaviour are the caller's: the card only draws `current`/`target` and calls the actions.

import SwiftUI
import Core

/// What the chip row needs: preset amounts and the callbacks.
struct FuelQuickAddConfig {
    let presets: [Int]
    let unit: String
    /// VoiceOver label for a preset chip ("Log 25 g of protein").
    let presetAccessibilityLabel: (Int) -> String
    let onPreset: (Int) -> Void
    let onCustom: () -> Void
}

/// A sticker button (camera, barcode): label, glyph, colour and action.
struct FuelStickerConfig: Identifiable {
    let id: String
    let title: String
    let accessibilityLabel: String
    let systemImage: String
    let color: Color
    /// Sticker tilt in degrees (flattened at accessibility sizes).
    let tilt: Double
    let action: () -> Void
}

enum FuelMeterKind {
    case protein, water
}

/// One goal's game-meter card.
struct FuelMeterCard: View {
    let kind: FuelMeterKind
    let title: String
    let systemImage: String
    let color: Color
    let current: Double
    let target: Double
    let quickAdd: FuelQuickAddConfig
    var stickers: [FuelStickerConfig] = []

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped when the logged amount goes up (by any path: chip, sheet, NFC, widget).
    @State private var gainTick = 0
    @State private var lastGain = 0
    /// Bumped when the goal tips over 100%.
    @State private var completeTick = 0

    private var progress: Double { target > 0 ? current / target : 0 }
    private var isComplete: Bool { progress >= 1 }
    private var currentInt: Int { Int(current.rounded()) }
    private var percent: Int { Int((min(progress, 9.99) * 100).rounded()) }

    private var suffix: String {
        target > 0 ? "/ \(Int(target.rounded()).formatted(.number)) \(quickAdd.unit)" : quickAdd.unit
    }

    private var chipText: String {
        guard isComplete else { return Copy.fuel.meterPercentChip(percent: percent) }
        return kind == .water ? Copy.fuel.waterMeterFullChip : Copy.fuel.proteinMeterFullChip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            readout
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(Copy.fuel.metricAccessibilityValue(
                    current: currentInt,
                    target: target > 0 ? Int(target.rounded()) : nil,
                    unit: quickAdd.unit
                ))

            FuelQuickAddChips(config: quickAdd, color: color)

            if !stickers.isEmpty {
                FuelStickerRow(stickers: stickers)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.large, tint: color, active: isComplete)
        .onChange(of: currentInt) { oldValue, newValue in
            guard newValue > oldValue else { return }
            lastGain = newValue - oldValue
            gainTick += 1
            if target > 0, Double(oldValue) < target, Double(newValue) >= target {
                completeTick += 1
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        switch kind {
        case .protein:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                header
                score
                FuelSegmentMeter(progress: progress, color: color)
            }
        case .water:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                header
                waterBody
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isComplete ? "checkmark" : systemImage)
                .font(Theme.Typography.icon(.medium, weight: .bold))
                .foregroundStyle(color)
                .padding(Theme.Spacing.xxs)
                .frame(minWidth: 36, minHeight: 36)
                .background(color.opacity(0.2), in: Circle())
                .symbolEffect(.bounce, value: gainTick)
                .zanoChargeBurst(trigger: completeTick, color: color)

            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(color)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.xs)

            ZanoGlassChip(chipText, systemImage: isComplete ? "star.fill" : nil, tint: color)
                .contentTransition(.numericText(value: Double(percent)))
        }
    }

    private var score: some View {
        FuelScore(value: currentInt, suffix: suffix, points: kind == .protein ? 56 : 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fuelGainBubble(
                Copy.fuel.gainBubble(amount: lastGain, unit: quickAdd.unit),
                trigger: gainTick,
                color: color
            )
    }

    /// Tank beside the score; stacked at accessibility sizes so the number keeps its width.
    @ViewBuilder
    private var waterBody: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                score
                FuelWaterTank(progress: progress, color: color, slosh: gainTick)
                    .frame(width: 96, height: 120)
            }
        } else {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                FuelWaterTank(progress: progress, color: color, slosh: gainTick)
                    .frame(width: 76, height: 112)
                score
            }
        }
    }
}

// MARK: - Quick-add chips

/// Preset chips plus an "Other" chip. One row when it fits, two columns otherwise (iPhone SE),
/// one column at accessibility sizes.
struct FuelQuickAddChips: View {
    let config: FuelQuickAddConfig
    let color: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.xs) { chips }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) { chips }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Theme.Spacing.xs), GridItem(.flexible(), spacing: Theme.Spacing.xs)],
                    spacing: Theme.Spacing.xs
                ) { chips }
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(config.presets, id: \.self) { preset in
            FuelChunkyChip(
                amount: "+\(preset)",
                unit: config.unit,
                systemImage: nil,
                color: color,
                accessibilityLabel: config.presetAccessibilityLabel(preset)
            ) {
                config.onPreset(preset)
            }
        }
        FuelChunkyChip(
            amount: nil,
            unit: Copy.fuel.customChipLabel,
            systemImage: "plus",
            color: color,
            accessibilityLabel: Copy.fuel.logCustomButtonLabel,
            action: config.onCustom
        )
    }
}

/// A chunky 48pt capsule in the goal's colour that pops when hit: press squash (PressableStyle),
/// a bounce after release, and a light haptic tap.
struct FuelChunkyChip: View {
    let amount: String?
    let unit: String
    let systemImage: String?
    let color: Color
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        // A plain local for the keyframes closure (no actor-isolated reads inside it).
        let popScale: Double = reduceMotion ? 1.0 : 1.1
        return Button {
            taps += 1
            action()
        } label: {
            label
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, Theme.Spacing.xxs)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(chipBackground)
                .contentShape(Capsule(style: .continuous))
                .keyframeAnimator(initialValue: 1.0, trigger: taps) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(popScale, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.icon(.xsmall, weight: .heavy))
                    .foregroundStyle(color)
            }
            if let amount {
                Text(amount)
                    .font(.system(.headline, design: .rounded, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Theme.Colors.text)
            }
            Text(unit)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(amount == nil ? Theme.Colors.text : Theme.Colors.textSecondary)
        }
    }

    private var chipBackground: some View {
        let shape = Capsule(style: .continuous)
        return shape
            .fill(LinearGradient(colors: [color.opacity(0.30), color.opacity(0.14)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(color.opacity(0.6), lineWidth: 1.5))
            .overlay(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 3)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, 4)
            }
    }
}

// MARK: - Sticker buttons

/// The camera and barcode actions as die-cut stickers: solid colour, a thick white border, a slight
/// tilt and a drop shadow. Side by side; stacked and untilted at accessibility sizes.
struct FuelStickerRow: View {
    let stickers: [FuelStickerConfig]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.sm) { items(tilted: false) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.sm) { items(tilted: true) }
                VStack(spacing: Theme.Spacing.sm) { items(tilted: false) }
            }
        }
    }

    @ViewBuilder
    private func items(tilted: Bool) -> some View {
        ForEach(stickers) { sticker in
            FuelStickerButton(sticker: sticker, tilted: tilted)
        }
    }
}

struct FuelStickerButton: View {
    let sticker: FuelStickerConfig
    let tilted: Bool

    @State private var taps = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Button {
            taps += 1
            sticker.action()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: sticker.systemImage)
                    .font(Theme.Typography.icon(.medium, weight: .bold))
                    .symbolEffect(.bounce, value: taps)
                Text(sticker.title)
                    .font(Theme.Typography.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.Colors.onFill)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(sticker.color, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.92), lineWidth: 3))
            .shadow(color: Color.black.opacity(0.35), radius: 6, y: 4)
            .rotationEffect(.degrees(tilted ? sticker.tilt : 0))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(sticker.accessibilityLabel)
    }
}
