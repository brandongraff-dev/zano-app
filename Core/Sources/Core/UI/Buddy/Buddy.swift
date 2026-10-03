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

/// Which face the buddy is pulling (eight faces, 2026-10-03). Map the day's mood with `init(_:)`,
/// screen-time charge with `init(charge:)`, and Today's hero (both) with `hero(charge:mood:)`.
public enum BuddyPose: String, Sendable, CaseIterable {
    /// Content: the resting face.
    case idle
    /// Eyes closed, a snot bubble: locked with nothing done yet.
    case sleepy
    /// Smiling eyes, open smile.
    case happy
    /// Squeezed > < eyes, tears, a rain cloud, washed-out colours, arms hanging, ears down.
    case drained
    /// Worried brows, a tear, a frown, ears down.
    case sad
    /// Heavy lids, flat mouth, a sweat drop.
    case meh
    /// Sparkle eyes, a big open grin, one arm waving.
    case excited
    /// ^ ^ eyes, the biggest grin, both arms up, hearts.
    case ecstatic

    /// The App Group defaults key for the pose Today's hero is in. Today writes it as the day's
    /// mood changes; the `ZANOReport` extension (which draws Today's hero on a device, but knows
    /// nothing about goals) reads it, so the buddy pulls the same face in both processes.
    public static let heroStorageKey = "shared.buddyHeroPose"

    /// Sleepy while locked with nothing done, happy with some done, ecstatic once everything is
    /// done, otherwise content.
    public init(_ mood: ZanoMascotMood) {
        switch mood {
        case .sleepy: self = .sleepy
        case .idle: self = .idle
        case .perky: self = .happy
        case .charged: self = .ecstatic
        }
    }

    /// The face for a screen-time charge (0...1, the share of the waking day spent off the phone),
    /// in seven steps from drained to ecstatic.
    public init(charge: Double) {
        switch charge {
        case ..<0.15: self = .drained
        case ..<0.3: self = .sad
        case ..<0.45: self = .meh
        case ..<0.6: self = .idle
        case ..<0.75: self = .happy
        case ..<0.9: self = .excited
        default: self = .ecstatic
        }
    }

    /// Today's hero: once every goal is done (`mood` is `.ecstatic`) the buddy is ecstatic
    /// whatever the charge; otherwise its face follows the charge.
    public static func hero(charge: Double, mood: BuddyPose) -> BuddyPose {
        mood == .ecstatic ? .ecstatic : BuddyPose(charge: charge)
    }
}

/// One pose's pixels: 48 rows of 48 characters; "." is transparent, any other character indexes
/// `palette` (0xRRGGBB) through `keys`. Sizes that are multiples of 16pt draw every pixel the same
/// width on a 3x screen.
public struct BuddyPixels: Sendable {
    public static let size = 48
    let palette: [UInt32]
    let rows: [String]

    private static let keys: [Character: Int] = {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-/:;<=>?@[]^_`{|}~")
        return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })
    }()

    /// A 48x48 RGBA image (nearest-neighbour scaling keeps it crisp).
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

/// `BuddySprite` for the user's stored buddy (App Group defaults, live-updating when the choice
/// changes): empty states, the NFC toast, Settings' footer and the other small spots that show
/// "your buddy" without owning the choice themselves (buddy everywhere, 2026-10-03). Decorative.
public struct StoredBuddySprite: View {
    let pose: BuddyPose
    let size: CGFloat

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    public init(pose: BuddyPose = .idle, size: CGFloat = 64) {
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        BuddySprite(buddy, pose: pose, size: size)
    }
}
