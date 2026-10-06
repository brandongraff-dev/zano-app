// BuddyViews.swift
// Watch/ZANOWatch
//
// The buddy on the wrist (session 13b): the user's chosen buddy, in the face Today's hero is pulling
// on the phone, wearing its gear, with its level and XP bar. Art comes from the generated
// `Generated/WatchBuddySprites.swift` (the watch can't import Core); the state comes from the phone
// through `WatchStateSnapshot`'s buddy fields. A goal finishing or a lock being earned flips
// `WatchStateStore.isCelebrating` on for a few seconds and the buddy goes ecstatic.

import SwiftUI

/// A 48x48 sprite drawn pixel-crisp as a square `size` points wide. Decorative. Sizes that are
/// multiples of 24pt draw every pixel the same width on a 2x watch screen (72pt = 3 px per pixel).
struct WatchPixelImage: View {
    let image: CGImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A thin rounded bar filled to `fraction` (0...1): the XP bar and the boss's HP bar.
struct WatchProgressBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WatchTheme.Colors.surface2)
                Capsule()
                    .fill(color)
                    .frame(width: clamped > 0 ? max(height, proxy.size.width * clamped) : 0)
            }
        }
        .frame(height: height)
        .animation(WatchTheme.Motion.ringFill, value: clamped)
    }
}

/// The top of the home page: the buddy (glowing in its signature colour), its name, "Lv N" and
/// the XP bar.
struct BuddyHeroView: View {
    @Environment(WatchStateStore.self) private var store

    private static let spriteSize: CGFloat = 72

    private var buddy: WatchBuddy { store.snapshot.resolvedBuddy }
    private var pose: WatchBuddyPose { store.isCelebrating ? .ecstatic : store.snapshot.resolvedPose }
    private var level: Int { store.snapshot.resolvedLevel }
    private var signature: Color { WatchTheme.Buddy.signature(buddy) }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.xs) {
            sprite
            BuddyLevelColumn(
                title: store.isCelebrating ? Copy.watch.celebration : Copy.watch.buddyName(buddy),
                level: level,
                fraction: store.snapshot.resolvedLevelFraction,
                color: signature
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.watch.buddySpoken(buddy, level: level))
    }

    private var sprite: some View {
        ZStack {
            Circle()
                .fill(signature.opacity(0.22))
                .frame(width: Self.spriteSize * 0.9, height: Self.spriteSize * 0.9)
            WatchPixelImage(
                image: buddy.image(pose: pose, gear: store.snapshot.resolvedGear),
                size: Self.spriteSize
            )
        }
        .scaleEffect(store.isCelebrating ? 1.12 : 1)
        .animation(WatchTheme.Motion.springStandard, value: store.isCelebrating)
    }
}

private struct BuddyLevelColumn: View {
    let title: String
    let level: Int
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
            Text(title)
                .font(WatchTheme.Typography.headline)
                .foregroundStyle(WatchTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(Copy.watch.level(level))
                .font(WatchTheme.Typography.numeralSmall())
                .foregroundStyle(color)
            WatchProgressBar(fraction: fraction, color: color)
        }
    }
}

#Preview {
    BuddyHeroView()
        .environment(WatchStateStore.shared)
}
