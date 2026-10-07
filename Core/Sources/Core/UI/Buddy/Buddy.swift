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

    // Activity emotions (session 15, 2026-10-05): how the buddy feels about the thing you're doing.
    // Every one is encouraging: hunger and thirst read as "ready for it", never as guilt, and
    // there is deliberately no restrictive-goal face (CLAUDE.md, spec §24).

    /// Determined brows, gritted teeth, a barbell, a sweat drop: mid-workout.
    case lifting
    /// Smug grin, flushed, sparkles: workout done.
    case flexing
    /// Closed happy eyes, a small "o" mouth, a water bottle: drinking water.
    case sipping
    /// Heavy lids, tongue out, an empty bottle: water is behind.
    case thirsty
    /// Closed eyes, a big chomp, a drumstick: logging protein.
    case eating
    /// Big wet eyes, a little drool, an egg: protein is behind.
    case hungry
    /// Heavy lids, level mouth, a target: a focus session or reading.
    case focused
    /// Squeezed eyes, a huge yawn, "zzz", arms up: sunrise alarm and stretching.
    case yawning
    /// Closed eyes, a soft smile, a gold star: a goal finished.
    case proud
    /// Heart eyes: a friend's nudge, a squad cheer, a gift (not wired to a screen yet).
    case lovey
    /// Fire eyes and raised fists: a streak that is alive (the streak pill).
    case blaze
    /// Pale ice eyes and snowflakes: a streak held safe by a freeze (the streak pill).
    case frozen
    /// Heavy-lidded and watchful with a padlock: the Lock tab.
    case guarding
    /// Curious, with a little hammer: Settings.
    case tinkering
    /// Bright eyes and a bar chart: Progress.
    case analyzing

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

    /// What the user is doing about a goal right now.
    public enum Moment: Sendable {
        /// The goal is still open and the user hasn't started.
        case needed
        /// Starting or logging it (a set, a glass of water, a meal, a focus block).
        case doing
        /// The goal is complete for today.
        case done
    }

    /// The emotion for a goal at `moment`: lifting then flexing for workouts, thirsty then sipping
    /// for water, hungry then eating for protein, focused for focus and reading, yawning for the
    /// sunrise alarm and stretching. Anything without its own face falls back to the plain
    /// excited / proud / idle faces.
    public init(goal: GoalType, moment: Moment) {
        switch (goal, moment) {
        case (.workoutGym, .doing), (.workoutHomeOutdoor, .doing), (.steps, .doing): self = .lifting
        case (.workoutGym, .done), (.workoutHomeOutdoor, .done), (.steps, .done): self = .flexing
        case (.water, .needed): self = .thirsty
        case (.water, .doing): self = .sipping
        case (.protein, .needed), (.mealPrep, .needed): self = .hungry
        case (.protein, .doing), (.mealPrep, .doing): self = .eating
        case (.focusSession, .doing), (.reading, .doing): self = .focused
        case (.sunriseAlarm, .doing), (.stretchMobility, .doing): self = .yawning
        case (.sunriseAlarm, .needed), (.sleepOnTime, .needed): self = .sleepy
        case (.sunriseAlarm, .done), (.sleepOnTime, .done), (.stretchMobility, .done): self = .happy
        case (_, .done): self = .proud
        case (_, .doing): self = .excited
        case (_, .needed): self = .idle
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

    static let keys: [Character: Int] = {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-/:;<=>?@[]^_`{|}~")
        return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })
    }()

    /// A 48x48 RGBA image (nearest-neighbour scaling keeps it crisp).
    public func cgImage() -> CGImage? {
        Self.image(layers: [self])
    }

    /// The layers drawn bottom to top into one 48x48 image (a face, then its gear).
    public static func image(layers: [BuddyPixels]) -> CGImage? {
        let n = size
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for layer in layers {
            for (y, row) in layer.rows.enumerated() where y < n {
                for (x, ch) in row.enumerated() where x < n {
                    guard let i = keys[ch], i < layer.palette.count else { continue }
                    let c = layer.palette[i]
                    let o = (y * n + x) * 4
                    bytes[o] = UInt8((c >> 16) & 0xFF)
                    bytes[o + 1] = UInt8((c >> 8) & 0xFF)
                    bytes[o + 2] = UInt8(c & 0xFF)
                    bytes[o + 3] = 0xFF
                }
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

extension Buddy {
    /// The buddy in `pose` wearing `gear`, as one image (UIKit callers such as the shield).
    public func image(pose: BuddyPose, gear: BuddyGear = .bare) -> CGImage? {
        let slumped = pose == .drained || pose == .sad
        let layers = [gearUnderPixels(gear, slumped: slumped), pixels(pose), gearPixels(gear, slumped: slumped)].compactMap { $0 }
        return BuddyPixels.image(layers: layers)
    }
}

/// Draws a buddy, pixel-crisp, as a square `size` points wide. Decorative: callers label the
/// surrounding element (the buddy's name is in `Copy.buddy`).
public struct BuddySprite: View {
    let buddy: Buddy
    let pose: BuddyPose
    let size: CGFloat
    /// nil: whatever the user is wearing (`BuddyGear.storageKey`); otherwise exactly this.
    let gearOverride: BuddyGear?
    let showsBackdrop: Bool

    @AppStorage(BuddyGear.storageKey, store: SharedDefaults.store) private var storedGear: BuddyGear = .bare
    /// This buddy's saved outfit (`BuddyOutfit`, JSON). Ignored when `gear` is set explicitly, so a
    /// gear tile shows the item on its own.
    @AppStorage private var outfitData: Data

    /// - Parameter showsBackdrop: draws the buddy's bought backdrop behind it, clipped to a rounded
    ///   square; for big spots (hero stages, share cards), not 32pt avatars.
    public init(_ buddy: Buddy, pose: BuddyPose = .idle, size: CGFloat = 96, gear: BuddyGear? = nil, showsBackdrop: Bool = false) {
        self.buddy = buddy
        self.pose = pose
        self.size = size
        self.gearOverride = gear
        self.showsBackdrop = showsBackdrop
        _outfitData = AppStorage(wrappedValue: Data(), BuddyOutfit.storageKey(for: buddy), store: SharedDefaults.store)
    }

    private var outfit: BuddyOutfit { gearOverride == nil ? BuddyOutfit.decode(outfitData) : BuddyOutfit() }

    public var body: some View {
        Group {
            if let image = buddy.image(pose: pose, gear: gearOverride ?? storedGear, outfit: outfit, showsBackdrop: showsBackdrop) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .clipShape(RoundedRectangle(cornerRadius: showsBackdrop && outfit.backdrop != nil ? size * 0.16 : 0))
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
    let gear: BuddyGear?
    let showsBackdrop: Bool

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var buddy: Buddy = .default

    /// - Parameter gear: nil wears whatever the user picked; set it to dress the buddy for the spot.
    public init(pose: BuddyPose = .idle, size: CGFloat = 64, gear: BuddyGear? = nil, showsBackdrop: Bool = false) {
        self.pose = pose
        self.size = size
        self.gear = gear
        self.showsBackdrop = showsBackdrop
    }

    public var body: some View {
        // `.id(buddy)`: `BuddySprite` reads the outfit through an `@AppStorage` keyed by the buddy,
        // set in its init. A new identity per buddy makes sure a swap reads the new buddy's outfit
        // rather than keeping the first key's storage (session 36).
        BuddySprite(buddy, pose: pose, size: size, gear: gear, showsBackdrop: showsBackdrop)
            .id(buddy)
    }
}
