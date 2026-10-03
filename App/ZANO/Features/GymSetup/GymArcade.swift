// GymArcade.swift
// App / ZANO / Features / GymSetup
//
// Pass 2 (2026-10-03, "make it more playful"): the gym screens' own artwork, built here rather than
// in Core because only this feature uses it.
//
//   * `GymChargeMeter`: the dwell as an arcade charge meter. A big score numeral (minutes so far),
//     then a battery of segments that light up in the workout volt as the dwell runs, the next
//     segment blinking while you're inside the circle (still under Reduce Motion), a bolt cap at
//     the end. Full = verified. On a raised glass hero.
//   * `GymPinSticker`: the gym as a die-cut sticker (volt disc, white rim, dumbbell, hard shadow),
//     for the empty states and on top of the map card.
//   * `GymMapCard`: a small, non-interactive map of a saved gym with its circle, the pin sticker
//     in the middle, under the card's glass content.
//
// Unverified (no Mac here): `Map(initialPosition:interactionModes:)` + `MapCircle` (iOS 17
// MapKit for SwiftUI; `AddGymSheet` uses the same family) rendered inside a scrolling list.

import SwiftUI
@preconcurrency import MapKit
import Core

// MARK: - Charge meter

struct GymChargeMeter: View {
    /// 0...1 (clamped).
    let progress: Double
    /// The big number; `nil` shows the gym glyph instead (nothing running yet).
    let minutes: Int?
    let targetMinutes: Int
    let tint: Color
    /// The dwell is running: the next segment blinks.
    let isCharging: Bool
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinkOn = false
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 76

    private static let segments = 10
    private var clamped: Double { min(1, max(0, progress)) }
    private var litSegments: Int { Int((clamped * Double(Self.segments)).rounded(.down)) }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            numeral
            battery
            Text(Copy.gym.verifiesAt(minutes: targetMinutes))
                .zanoText(.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
        }
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoHero(tint: tint, active: clamped >= 1)
        .onAppear { startBlink() }
        .onChange(of: isCharging) { _, _ in startBlink() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text("\(minutes ?? 0) / \(targetMinutes) \(Copy.gym.minutesUnit)"))
    }

    @ViewBuilder
    private var numeral: some View {
        if let minutes {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(minutes)")
                    .font(Theme.Typography.score(size: numeralSize))
                    .foregroundStyle(Theme.Colors.text)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .shadow(color: tint.opacity(0.4), radius: 16)
                Text(Copy.gym.minutesUnit)
                    .font(Theme.Typography.title)
                    .foregroundStyle(tint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        } else {
            GymPinSticker(diameter: 84)
        }
    }

    private var battery: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.segments, id: \.self) { index in
                segment(index)
            }
            Image(systemName: "bolt.fill")
                .font(Theme.Typography.icon(.medium, weight: .black))
                .foregroundStyle(clamped >= 1 ? tint : Theme.Colors.muted)
                .padding(.leading, Theme.Spacing.xxs)
        }
        .padding(7)
        .background(Color.black.opacity(0.25), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.hairlineStrong, lineWidth: 1.5))
    }

    private func segment(_ index: Int) -> some View {
        let isLit = index < litSegments
        let isNext = index == litSegments && isCharging
        let fill: Color = isLit ? tint : (isNext && (blinkOn || reduceMotion) ? tint.opacity(0.45) : Theme.Colors.track)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(height: 30)
            .shadow(color: isLit ? tint.opacity(0.6) : .clear, radius: 5)
    }

    private func startBlink() {
        guard isCharging, !reduceMotion else {
            blinkOn = false
            return
        }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            blinkOn = true
        }
    }
}

// MARK: - Pin sticker

struct GymPinSticker: View {
    var diameter: CGFloat = 96
    var tint: Color = Theme.Colors.Ring.workout

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Circle().strokeBorder(Color.white, lineWidth: max(2, diameter * 0.045))
            Image(systemName: "dumbbell.fill")
                .font(.system(size: diameter * 0.4, weight: .black))
                .foregroundStyle(Theme.Colors.onFill)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(0.45), radius: 0, x: 2, y: 4)
        .rotationEffect(.degrees(-8))
        .accessibilityHidden(true)
    }
}

/// The empty-state sticker with two soft rings around it, like a geofence.
struct GymPinHero: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.Colors.Ring.workout.opacity(0.18), lineWidth: 2)
                .frame(width: 190, height: 190)
            Circle()
                .strokeBorder(Theme.Colors.Ring.workout.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [5, 7]))
                .frame(width: 142, height: 142)
            GymPinSticker(diameter: 96)
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }
}

// MARK: - Map card header

/// A small map of the gym and its circle. Not interactive (the card's tap edits the gym); the pin
/// sticker sits on the centre, which is the gym because the camera is centred on it.
struct GymMapPreview: View {
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int
    let tint: Color

    private var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        Map(
            initialPosition: .region(MKCoordinateRegion(
                center: center,
                latitudinalMeters: Double(radiusMeters) * 5,
                longitudinalMeters: Double(radiusMeters) * 5
            )),
            interactionModes: []
        ) {
            MapCircle(center: center, radius: CLLocationDistance(radiusMeters))
                .foregroundStyle(tint.opacity(0.22))
                .stroke(tint, lineWidth: 2)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .overlay { GymPinSticker(diameter: 34, tint: tint) }
        .overlay {
            // Fade the map into the glass below it.
            LinearGradient(
                colors: [Color.clear, Theme.Colors.background.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}
