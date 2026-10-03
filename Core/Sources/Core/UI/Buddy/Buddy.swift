// Buddy.swift
// Core / UI / Buddy
//
// The user's buddy (mascot redesign, 2026-10-03): nine pixel-art characters, picked in onboarding
// and Settings, shown wherever the app used to show the ZANO star. Default: Stash. The choice lives
// in the App Group's shared defaults so widgets and the Screen Time report draw the same buddy.
// The art is generated (BuddySprites.swift, from scripts/buddies); names and blurbs are in
// `Copy.buddy`; each buddy's colours are in `Theme.BuddyColors`.

import SwiftUI

public enum Buddy: String, CaseIterable, Sendable, Identifiable {
    case stash, zib, lox, pip, moko, brick, tank, volt, howl

    public static let `default`: Buddy = .stash

    /// The App Group defaults key (`SharedDefaults.store`).
    public static let storageKey = "shared.buddy"

    /// The stored choice (the default when unset or unreadable).
    public static var stored: Buddy {
        SharedDefaults.store.string(forKey: storageKey).flatMap(Buddy.init(rawValue:)) ?? .default
    }

    public var id: String { rawValue }

    public enum Crew: Sendable { case cozy, hype }

    public var crew: Crew {
        switch self {
        case .stash, .zib, .lox, .pip, .moko: .cozy
        case .brick, .tank, .volt, .howl: .hype
        }
    }

    /// The buddy's signature colour: picker selection, hero glow, the "Team up" button.
    public var color: Color { Theme.BuddyColors.colors(for: self).signature }
    /// Its world's second and third colours (props, backdrops).
    public var secondaryColor: Color { Theme.BuddyColors.colors(for: self).second }
    public var tertiaryColor: Color { Theme.BuddyColors.colors(for: self).third }
}

/// Which face the buddy is pulling. Map the day's mood with `init(_:)`.
public enum BuddyPose: Sendable, CaseIterable {
    case idle, sleepy, happy

    /// Sleepy while locked with nothing done, happy once everything is done, otherwise idle (the
    /// motion layer adds the hop for "some done").
    public init(_ mood: ZanoMascotMood) {
        switch mood {
        case .sleepy: self = .sleepy
        case .idle, .perky: self = .idle
        case .charged: self = .happy
        }
    }
}

/// One pose's pixels: 32 rows of 32 characters; "." is transparent, any other character indexes
/// `palette` (0xRRGGBB).
public struct BuddyPixels: Sendable {
    public static let size = 32
    let palette: [UInt32]
    let rows: [String]

    private static let keys: [Character: Int] = {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })
    }()

    /// A 32x32 RGBA image (nearest-neighbour scaling keeps it crisp).
    public func cgImage() -> CGImage? {
        let n = Self.size
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for (y, row) in rows.enumerated() where y < n {
            for (x, ch) in row.enumerated() where x < n {
                guard let i = Self.keys[ch], i < palette.count else { continue }
                let c = palette[i]
                let o = (y * n + x) * 4
                bytes[o] = UInt8((c >> 16) & 0xFF)
                bytes[o + 1] = UInt8((c >> 8) & 0xFF)
                bytes[o + 2] = UInt8(c & 0xFF)
                bytes[o + 3] = 0xFF
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// Draws a buddy, pixel-crisp, as a square `size` points wide. Decorative: callers label the
/// surrounding element (the buddy's name is in `Copy.buddy`).
public struct BuddySprite: View {
    let buddy: Buddy
    let pose: BuddyPose
    let size: CGFloat

    public init(_ buddy: Buddy, pose: BuddyPose = .idle, size: CGFloat = 96) {
        self.buddy = buddy
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = buddy.pixels(pose).cgImage() {
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
