// TrophyBadgeDisc.swift
// App / Features / Trophy
//
// The one badge disc: `TrophyCaseView`'s milestone grid and the trophy strip on Progress both draw
// this, so an earned badge looks the same wherever it shows up. Earned = the logo's brushed silver
// (`metallic`) with the glyph in `onFill` and a thin specular rim: a trophy is a metal object, not a
// blue tint. Not earned = an empty socket, a solid hairline ring on `surface2`, the milestone's own
// glyph in `muted` (so the case says what there is to win) and a small lock badge. No dashes: a
// dashed outline reads as "drop zone", not "not yet".
//
// `TrophyBadgeGlyph.forKey(_:)` is also the single badge-key -> glyph map for both screens, so the
// two can't drift apart. SF Symbol names are unverified without the SF Symbols app on a Mac.

import SwiftUI
import Core

/// What a badge disc draws in its centre: an SF Symbol, or the ZANO brand star (the first earned
/// unlock is the brand's own moment).
enum TrophyBadgeGlyph: Equatable {
    case symbol(String)
    case zanoMark

    /// The glyph for a `Badge.key`. Both streak milestones share `flame.fill` (one streak family,
    /// told apart by title, not by a filled-vs-outline flame). Per-occurrence comeback keys are
    /// matched by prefix, since they're stamped with a date.
    static func forKey(_ key: String) -> TrophyBadgeGlyph {
        if key.hasPrefix("comeback_challenge") { return .symbol("flag.checkered") }
        if key.hasPrefix("comeback") { return .symbol("arrow.uturn.forward") }
        switch key {
        case "first_earned_unlock": return .zanoMark
        case "streak_7", "streak_14", "streak_30": return .symbol("flame.fill")
        case "streak_100": return .symbol("crown.fill")
        case "streak_365": return .symbol("trophy.fill")
        case "protein_1000g_week": return .symbol("fork.knife")
        case "gym_50_sessions": return .symbol("dumbbell.fill")
        default:
            if key.hasPrefix("streak_") { return .symbol("flame.fill") }
            return .symbol("rosette")
        }
    }

    /// The collectible colour for a `Badge.key` (pass 2): each badge family earns in its own hue,
    /// the way stickers in a set differ. Streaks are ember, the big streaks pink and sun, fuel is
    /// apricot, the gym is volt, the first unlock is ZANO Blue, comebacks are violet.
    static func tint(forKey key: String) -> Color {
        if key.hasPrefix("comeback") { return Theme.Colors.Ring.focus }
        switch key {
        case "first_earned_unlock": return Theme.Colors.accent
        case "streak_7", "streak_14": return Theme.Colors.ember
        case "streak_30": return Theme.Colors.Ring.creatine
        case "streak_100", "streak_365": return Theme.Colors.Ring.sunriseAlarm
        case "protein_1000g_week": return Theme.Colors.Ring.protein
        case "gym_50_sessions": return Theme.Colors.Ring.workout
        default:
            if key.hasPrefix("streak_") { return Theme.Colors.ember }
            return Theme.Colors.Ring.water
        }
    }
}

/// A round badge, earned or not. Decorative: callers put the title and status next to it and own
/// the VoiceOver label.
struct TrophyBadgeDisc: View {
    let isEarned: Bool
    let glyph: TrophyBadgeGlyph
    var diameter: CGFloat = TrophyBadgeDisc.defaultDiameter
    /// Pass 2: when set, an earned disc is a collectible sticker in this colour (gradient fill,
    /// white die-cut rim, hard printed shadow) instead of brushed silver. `nil` keeps the silver
    /// disc, so callers that don't opt in look exactly as before.
    var tint: Color? = nil

    static let defaultDiameter: CGFloat = 60

    init(isEarned: Bool, systemImage: String, diameter: CGFloat = TrophyBadgeDisc.defaultDiameter) {
        self.isEarned = isEarned
        self.glyph = .symbol(systemImage)
        self.diameter = diameter
    }

    init(isEarned: Bool, glyph: TrophyBadgeGlyph, diameter: CGFloat = TrophyBadgeDisc.defaultDiameter, tint: Color? = nil) {
        self.isEarned = isEarned
        self.glyph = glyph
        self.diameter = diameter
        self.tint = tint
    }

    /// The collectible disc for a `Badge.key`: its glyph and its colour.
    init(isEarned: Bool, badgeKey: String, diameter: CGFloat = TrophyBadgeDisc.defaultDiameter) {
        self.init(isEarned: isEarned, glyph: .forKey(badgeKey), diameter: diameter, tint: TrophyBadgeGlyph.tint(forKey: badgeKey))
    }

    /// Theme icon sizes, picked by disc size. Capped at xxLarge Dynamic Type below: the disc is a
    /// fixed-size object, and an accessibility-size glyph would burst out of it.
    private var glyphFont: Font {
        Theme.Typography.icon(diameter >= 48 ? .large : .small, weight: isEarned ? .bold : .semibold)
    }
    private var lockBadgeDiameter: CGFloat { (diameter / 3).rounded() }

    var body: some View {
        ZStack {
            if isEarned, let tint {
                Circle().fill(tint)
                Circle().strokeBorder(Color.white, lineWidth: max(2, diameter * 0.05))
                // A shine streak across the top-left, like a foil sticker.
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: diameter * 0.12, height: diameter * 0.42)
                    .rotationEffect(.degrees(40))
                    .offset(x: -diameter * 0.22, y: -diameter * 0.16)
            } else if isEarned {
                Circle().fill(Theme.Colors.metallic)
                // Subtle specular: a top-lit rim, brighter at the top than the bottom.
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [Theme.Colors.specular, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: Theme.Metrics.edgeWidth
                )
            } else {
                Circle().fill(Theme.Colors.surface2)
                Circle().strokeBorder(Theme.Colors.hairlineStrong, lineWidth: Theme.Metrics.edgeWidth)
            }

            glyphView
                .foregroundStyle(isEarned ? Theme.Colors.onFill : Theme.Colors.muted)

            if !isEarned {
                Image(systemName: "lock.fill")
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: lockBadgeDiameter, height: lockBadgeDiameter)
                    .background(Theme.Colors.background, in: Circle())
                    .overlay { Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth) }
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .offset(x: diameter / 3, y: diameter / 3)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: isEarned && tint != nil ? Color.black.opacity(0.45) : .clear, radius: 0, x: 2, y: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(glyphFont)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        case .zanoMark:
            // The brand star, filled even-odd so its cut-outs stay open. `foregroundStyle` above
            // colours it like the SF Symbols.
            ZanoMarkShape()
                .fill(style: FillStyle(eoFill: true))
                .aspectRatio(ZanoMark.aspectRatio, contentMode: .fit)
                .frame(width: diameter * 0.5, height: diameter * 0.5)
        }
    }
}
