// PhotoDedupe.swift
// Core / Verification
//
// docs/spec.md §9.8 Anti-Cheat Signals:
//   "Rate limits on taps; identical-photo detection (perceptual hash); geofence dwell/motion
//   checks. Never accuse — just don't count, and show 'not counted: too quick' transparently."
// docs/spec.md §3 Goal Catalog & Verification, Protein row (Tier B), anti-cheat column:
//   "Daily cap on identical NFC taps; photo dedupe" — the literal source for this file. Meal prep
//   (`GoalType.mealPrep`, Tier B, weekly; §3's own row: "Photo of prepped containers, vision model
//   confirms 'multiple meal containers'") also submits a photo for vision-model verification, and
//   this task's own brief names it as a second intended caller alongside the meal-vision flow for
//   Protein (`GoalType.protein`). So this file's contract below is written generically ("a photo
//   submitted for verification"), not Protein-specific, even though Protein is the only goal §3's
//   table explicitly pairs with the words "photo dedupe" today.
//
// This task's own brief is this file's fixed public contract:
//   func isLikelyDuplicate(of image: ...) async -> Bool
// for the meal-vision flow and meal-prep verification (both owned by other sessions, currently
// unbuilt — see knownIssues) to call before accepting a submitted photo.
//
// Scope boundary (per this wave's shared instructions, after a previous wave shipped a real bug
// from two agents independently assuming different shapes for the same not-yet-built thing): this
// task owns exactly this one new file. It does not touch `Models/Meal.swift`, anything under
// `Copy/`, or any UI. It never renders or hardcodes the "not counted: too quick"-style copy §9.8
// asks for — per CLAUDE.md, user-facing strings live only in `Core/Sources/Core/Copy`; this file
// returns a plain `Bool` (its fixed contract), and whichever Copy-aware caller layer turns a
// `true` result into that transparent "not counted" messaging owns the exact wording, the same
// division of labor `MotionAntiCheat.swift`/`TapRateLimiter` already establish for their own
// typed verdicts.
//
// Algorithm: §9.8 names the general family — "perceptual hash" — parenthetically glossed in this
// task's own brief as "average/difference", since aHash and dHash are the two standard, widely
// documented members of that family. This file implements dHash (difference hash): resize to a
// small grayscale grid one pixel wider than tall, and hash each row's left-to-right *gradient*
// (is pixel N brighter than pixel N+1?) into one bit. dHash, not aHash, is the better fit for this
// file's actual job — flagging the *same* photo, or a trivial recompress/rotate/crop-free
// resubmission of it — because comparing neighboring pixels cancels out uniform brightness/
// exposure shifts (flash vs. no flash, auto-exposure jitter between two shots of the same plate)
// that aHash's global-mean-threshold approach is more sensitive to. A documented choice within the
// family §9.8 names, not an unstated assumption.
//
// Storage: "a small on-device store of recent meal-photo hashes (via Core/Sources/Core/Store)" per
// this task's brief. `Store/ModelContainer+AppGroup.swift` defines the public `AppGroup.identifier`
// constant that `Store/SharedDefaults.swift` also builds its `UserDefaults` suite from — this file
// reads that same constant to open its *own* `UserDefaults`-backed store, under its own key,
// rather than editing `SharedDefaults.swift` to add a property there. Deliberate, not an oversight:
// this task owns exactly one new file, and a short-lived, capped, dedupe-only list of opaque
// 64-bit hashes is a poor fit for `SharedDefaults`'s documented contract ("engine-owned mirrors of
// durable SwiftData state" — this file's hash list is neither durable app state nor owned by any
// engine) and an equally poor fit for a new SwiftData `@Model` type (which would mean editing the
// shared `appGroupModelTypes` array in `ModelContainer+AppGroup.swift` — a file this task does not
// own, and exactly the kind of cross-file assumption this wave's shared brief warns against).
// Reusing `AppGroup.identifier` read-only keeps this file's storage inside the same App Group
// container everything else already uses, without writing to a file this task doesn't own.
//
// No Mac/compiler exists to build or run this. `CGContext(data:width:height:bitsPerComponent:
// bytesPerRow:space:bitmapInfo:)` with an 8-bit `DeviceGray`, no-alpha, `bytesPerRow == width`
// configuration is Apple's own documented supported pixel format (Quartz 2D Programming Guide's
// supported-formats table) and `UIGraphicsImageRenderer`'s thread-safety-off-main-thread guarantee
// is likewise documented; both used exactly as documented, but neither has been run on a device.
// Separately, exactly which executor a plain (non-actor-isolated) `async` function's synchronous
// prefix runs on under current Swift concurrency scheduling rules (relevant to
// `isLikelyDuplicate(of:at:window:)`'s doc comment below) is a language-semantics detail this task
// could not confirm without a toolchain either. Both flagged in this task's knownIssues per
// CLAUDE.md working rule 5.

import CoreGraphics
import Foundation
import UIKit
import os

// MARK: - PhotoHash

/// A 64-bit difference-hash (dHash) fingerprint of an image — see this file's header comment for
/// why dHash was chosen over average-hash. `Sendable`/`Codable`/`Equatable`/`Hashable` so it can
/// cross actor boundaries and persist to `UserDefaults` freely; a plain value type that never
/// holds onto the source `UIImage`/`CGImage`, which the SDK does not mark `Sendable`.
public struct PhotoHash: Sendable, Equatable, Hashable, Codable {
    public let bits: UInt64

    public init(bits: UInt64) {
        self.bits = bits
    }

    /// Number of differing bits between two hashes, `0...64`. `0` is bit-for-bit identical (the
    /// same photo, or a lossless re-encode of it); low single digits are what a JPEG
    /// recompression, a trivial rotate, or a 1px crop typically produce; per the perceptual-hash
    /// literature this family comes from, values much above that stop meaning "the same photo" and
    /// start meaning "a genuinely different image".
    public func hammingDistance(to other: PhotoHash) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }
}

// MARK: - PhotoDedupe

/// docs/spec.md §9.8: "identical-photo detection (perceptual hash) ... Never accuse — just don't
/// count, and show 'not counted: too quick' transparently." This is the one call other
/// verification code needs: "does this photo look like one we've already counted very recently?"
///
/// A plain `enum` namespace, not a `.shared`-singleton class/actor the way
/// `MotionAntiCheat`/`TapRateLimiter` are: the only genuinely shared mutable state here (the
/// recent-hash list) is fully owned and serialized by the private ``RecentHashStore`` actor below,
/// so the public surface itself has nothing to instantiate — closer to
/// `QuickRepeatSuggester.signature(for:)`'s "static, callable from anywhere" shape than
/// `TapRateLimiter`'s "instance you evaluate against" shape, since there is exactly one dedupe
/// store for the whole process, never one per caller/key.
public enum PhotoDedupe {

    // MARK: Tunables
    //
    // Neither number below is stated by spec §9.8 ("a short window" is the spec's own phrase, no
    // exact figure given) — both are this file's own documented judgment call, the same kind
    // `TapRateLimiter.Policy.protein`'s daily cap already flags for its own unsourced number.

    /// Default lookback window for "recent" when checking/recording a submission. Long enough to
    /// catch someone resubmitting the exact same shot for a second goal credit minutes apart —
    /// the realistic cheat this guards against (snap once, log Protein, then log meal prep or a
    /// second meal off the identical photo) — short enough that two genuinely different, ordinary
    /// meals eaten hours apart are never at risk of colliding.
    public static let defaultRecentWindow: TimeInterval = 6 * 60 * 60 // 6 hours

    /// Hamming-distance threshold (out of 64 bits) at or under which two dHash values count as
    /// "the same photo" for this file's purposes. Deliberately tight — general perceptual-hash
    /// similarity search often uses a much looser threshold (~10+), but §9.8's own framing is
    /// "never accuse": this file would rather under-flag two photos that happen to look alike (two
    /// plain white plates) than over-flag two photos that are actually different meals.
    public static let duplicateHammingThreshold = 4

    /// Hard cap on how many recent hashes are kept in the store regardless of the time window, so
    /// a pathological case (unusually many photo submissions inside one window, or a manually
    /// rolled-back system clock defeating the time-based prune) can't grow this file's App Group
    /// storage without bound. Comfortably above any realistic count of photo-verified goals inside
    /// ``defaultRecentWindow``.
    public static let maxStoredHashes = 200

    // MARK: - Public contract

    /// This task's fixed contract: flags a photo as a likely near-duplicate of one already
    /// verified "within a short window" — for callers like the meal-vision flow (Protein, §3's
    /// "photo dedupe" anti-cheat column) and meal prep (weekly photo submissions) to check
    /// *before* accepting a photo-verified goal.
    ///
    /// Hashes `image`, compares it against every hash recorded within `window` of `date`, and —
    /// mirroring the "evaluate, and if allowed record" shape `TapRateLimiter.evaluate(...)`
    /// already established for this codebase's other anti-cheat primitives — if no near-duplicate
    /// is found, records this photo's hash so a *later* resubmission of it is the one that gets
    /// flagged. A photo that comes back `true` (a likely duplicate) is deliberately NOT recorded
    /// again: it wasn't counted, so it shouldn't extend the window during which the *original*
    /// photo keeps getting flagged as reused.
    ///
    /// Fails open on every error path — cannot get pixel data from `image`, cannot allocate the
    /// hashing bitmap context — by returning `false` (not a duplicate) rather than throwing or
    /// blocking. Per §9.8's "never accuse" and CLAUDE.md's "never trap the user": a missed
    /// duplicate is an acceptable cost here; a falsely rejected legitimate meal photo is not.
    ///
    /// `image` itself never crosses into the actor that owns the recent-hash store — required
    /// because the SDK does not mark `UIImage`/`CGImage` `Sendable`. ``hash(of:)`` reduces it to a
    /// plain `Sendable` ``PhotoHash`` first (mirrors `MotionAntiCheat.swift`'s documented reason
    /// for converting non-`Sendable` `CMMotionActivity` samples into a `Sendable` snapshot before
    /// crossing any `async` boundary), and only that hash is awaited across. That hashing step is
    /// cheap regardless of the source photo's resolution, since its very first drawing pass
    /// downsamples to a small, fixed-size canvas (see ``hash(of:)``) — but exactly which
    /// thread/executor a plain non-actor-isolated `async` function's synchronous portion runs on
    /// is a Swift-concurrency scheduling detail this task could not confirm without a toolchain
    /// (see this file's header comment and knownIssues). A caller that needs the hashing work
    /// guaranteed off the main thread can call ``hash(of:)`` itself inside its own background
    /// `Task.detached` and use ``isLikelyDuplicate(hash:at:window:)`` below instead.
    public static func isLikelyDuplicate(
        of image: UIImage,
        at date: Date = .now,
        window: TimeInterval = defaultRecentWindow
    ) async -> Bool {
        guard let computedHash = hash(of: image) else {
            logger.notice("isLikelyDuplicate: could not hash submitted image; failing open (not a duplicate).")
            return false
        }
        return await isLikelyDuplicate(hash: computedHash, at: date, window: window)
    }

    /// Same evaluate-and-record contract as ``isLikelyDuplicate(of:at:window:)``, for a caller
    /// that already has a `PhotoHash` — e.g. one computed off the main thread via ``hash(of:)``
    /// inside its own `Task`, or (for tests) a synthetic hash with no real image behind it.
    public static func isLikelyDuplicate(
        hash: PhotoHash,
        at date: Date = .now,
        window: TimeInterval = defaultRecentWindow
    ) async -> Bool {
        await RecentHashStore.shared.evaluateAndRecord(
            hash: hash,
            at: date,
            window: window,
            threshold: duplicateHammingThreshold,
            maxStored: maxStoredHashes
        )
    }

    /// Check-only half of the evaluate-and-record contract: `true` if `hash` is a near-duplicate
    /// of a photo recorded within `window` of `date`, WITHOUT recording `hash` itself. Added for
    /// the meal-photo UI (Fuel and meal prep, 2026-09-25): there, a photo is checked the moment
    /// it's taken but only *counted* once the user confirms and the log succeeds. Recording on
    /// the check (as ``isLikelyDuplicate(hash:at:window:)`` does) would flag a user who cancels
    /// and then re-picks the same photo as "reusing" a photo that was never counted — exactly the
    /// false accusation spec 9.8 rules out. Pair with ``recordAccepted(hash:at:window:)``.
    public static func wouldBeDuplicate(
        hash: PhotoHash,
        at date: Date = .now,
        window: TimeInterval = defaultRecentWindow
    ) async -> Bool {
        await RecentHashStore.shared.evaluate(
            hash: hash,
            at: date,
            window: window,
            threshold: duplicateHammingThreshold
        )
    }

    /// Record-only half: remembers `hash` as counted at `date`, so a later resubmission within
    /// `window` is flagged by ``wouldBeDuplicate(hash:at:window:)``. Call after the photo's log
    /// actually succeeded.
    public static func recordAccepted(
        hash: PhotoHash,
        at date: Date = .now,
        window: TimeInterval = defaultRecentWindow
    ) async {
        await RecentHashStore.shared.record(hash: hash, at: date, window: window, maxStored: maxStoredHashes)
    }

    /// Clears all stored recent-hash state. Not called by any production path — exposed only for
    /// tests (and a possible future debug "reset anti-cheat state" action), mirroring
    /// `TapRateLimiter.reset(key:)`'s identical reason for existing.
    public static func resetForTesting() async {
        await RecentHashStore.shared.reset()
    }

    // MARK: - Hashing (pure, synchronous, no shared state — safe to call from any isolation domain)

    /// Computes a 64-bit dHash for `image`. `nil` only if `image` has no renderable pixel data
    /// (e.g. a zero-size `UIImage`) or the CoreGraphics bitmap context this needs fails to
    /// allocate — both extremely unlikely for a real camera/photo-picker image. See this file's
    /// fail-open contract above for what a caller should do with `nil`: treat it as "not a
    /// duplicate", never as an error to surface to the user.
    ///
    /// Two-pass by design:
    /// 1. `UIGraphicsImageRenderer` redraws `image` into a modest, fixed-size square. This is the
    ///    only step that needs to know about `UIImage.imageOrientation` — a `CGImage` on its own
    ///    carries no orientation, and `UIKit`'s own orientation-aware `draw(in:)` is the documented
    ///    way to bake it in, rather than this file re-deriving the six `UIImage.Orientation`
    ///    transform matrices by hand. The stretch-to-fill this step does (source aspect ratio is
    ///    not preserved) is intentional and harmless for this file's purpose — it's applied
    ///    identically to every image hashed, so it never changes whether two near-identical photos
    ///    compare as a match; it would only matter for a general similarity search, which this
    ///    file is not.
    /// 2. That flattened, orientation-correct `CGImage` is then drawn into a `CGContext` this file
    ///    creates with an explicit, fully-known pixel format (8-bit `DeviceGray`, no alpha) sized
    ///    exactly to the hash grid, and pixel bytes are read back out of *that* context. Reading
    ///    raw bytes back is only safe to do "by hand" (as `grayscaleHashGrid` below does) when this
    ///    file controls the exact format doing the producing — `UIGraphicsImageRenderer`'s own
    ///    output is not documented as a fixed byte layout (it may use a wide-gamut/extended-range
    ///    backing store on some devices), so this file never reads raw bytes from step 1's output
    ///    directly, only from the second, self-specified `CGContext`.
    public static func hash(of image: UIImage) -> PhotoHash? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        guard let flattened = orientationFlattenedCGImage(from: image) else { return nil }
        // dHash grid: one column wider than tall, so every row yields exactly `hashGridHeight`
        // left-to-right gradient bits — `hashGridHeight * hashGridHeight` bits total (64 for the
        // 8×8 default below).
        guard let grid = grayscaleHashGrid(from: flattened, width: hashGridWidth, height: hashGridHeight) else {
            return nil
        }

        var bits: UInt64 = 0
        for row in 0..<hashGridHeight {
            for col in 0..<hashGridHeight {
                let left = grid[row * hashGridWidth + col]
                let right = grid[row * hashGridWidth + col + 1]
                bits <<= 1
                if left > right {
                    bits |= 1
                }
            }
        }
        return PhotoHash(bits: bits)
    }

    /// Hash grid height (and, per the dHash construction above, bit-rows). `8` yields the
    /// standard, widely used 64-bit dHash size — enough resolution to distinguish real photos
    /// while staying a single `UInt64`.
    private static let hashGridHeight = 8
    /// One wider than `hashGridHeight` — see ``hash(of:)``'s doc comment: each row needs `width`
    /// pixels to produce `width - 1` (== `hashGridHeight`) gradient bits.
    private static let hashGridWidth = hashGridHeight + 1

    /// Orientation-correct downsample of `image` into a fixed, modest square, as plain pixels this
    /// file will re-hash at a much smaller size in ``grayscaleHashGrid``. Sized well above the
    /// final hash grid so that resample isn't working from an already-degraded thumbnail, and well
    /// below a real camera photo's resolution so this pass stays cheap regardless of source size.
    private static let intermediateFlattenSize = CGSize(width: 64, height: 64)

    private static func orientationFlattenedCGImage(from image: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: intermediateFlattenSize, format: format)
        let flattened = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: intermediateFlattenSize))
        }
        return flattened.cgImage
    }

    /// Draws `cgImage` into a `CGContext` this file fully controls (8-bit `DeviceGray`, no alpha,
    /// `bytesPerRow == width` — the minimum valid, padding-free value for that format) and reads
    /// the resulting grayscale pixels back out, row-major. `CGContext.draw` performs both the
    /// resize (arbitrary source size down to `width`×`height`) and the RGB→gray conversion in one
    /// documented Core Graphics call; this file never assumes anything about `cgImage`'s own pixel
    /// format going in.
    private static func grayscaleHashGrid(from cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: pointer, count: width * height))
    }

    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "PhotoDedupe")
}

// MARK: - RecentHashStore (private actor: the mutable, persisted recent-hash list)

/// Owns the actual mutable state `PhotoDedupe` checks/records against: a small, time-windowed list
/// of recently seen `PhotoHash` values, persisted to the shared App Group `UserDefaults` suite
/// (`AppGroup.identifier`, from `Store/ModelContainer+AppGroup.swift`) so a duplicate resubmitted
/// after the app was killed and relaunched — a real scenario, since iOS suspends/kills backgrounded
/// apps routinely — is still caught, not just one held in memory for the current process's
/// lifetime.
///
/// An `actor`, matching `TapRateLimiter`'s own reasoning for its per-key tap history: two photo
/// submissions (e.g. Protein logged from the camera, meal prep logged from the photo picker,
/// moments apart) can plausibly race, and actor isolation is the idiomatic Swift 6 way to
/// serialize that without hand-rolled locking.
///
/// Known limitation (flagged in this task's knownIssues, not fixed here): pruning happens on every
/// call using *that call's own* `window` argument, so a caller that mixes different `window` values
/// across calls will have earlier, larger-window entries pruned away by a later, smaller-window
/// call. Every real call site is expected to use the same policy — in practice, always
/// `PhotoDedupe.defaultRecentWindow` — so this doesn't bite in normal use; a store that tracked
/// per-entry windows independently would be more correct but is more than this task's contract
/// needs.
private actor RecentHashStore {
    static let shared = RecentHashStore()

    /// One recorded submission: its hash and when it was recorded, so old entries can be pruned by
    /// `window` without a separate cleanup pass/timer.
    private struct Entry: Codable, Sendable {
        let bits: UInt64
        let date: Date
    }

    /// `UserDefaults` is documented by Apple as safe to use concurrently from multiple threads;
    /// the SDK itself does not mark the class `Sendable` as of this writing. `Store/
    /// SharedDefaults.swift` already documents this exact situation for its own use of
    /// `UserDefaults` and adopts the same `nonisolated(unsafe)` annotation; this actor mirrors
    /// that rather than inventing a different justification for the identical fact.
    nonisolated(unsafe) private let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    /// This file's own key, deliberately not added to `Store/SharedDefaults.swift`'s `Keys` enum —
    /// see this file's header comment on why this store's short-lived, dedupe-only hash list
    /// doesn't fit that type's documented contract, and on this task's file-ownership boundary.
    private static let storageKey = "core.verification.photoDedupe.recentHashes"

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "PhotoDedupe.RecentHashStore")

    /// Lazily loaded from `UserDefaults` on first access this process, then kept in memory and
    /// written back on every mutation — avoids re-decoding JSON on every single evaluate call
    /// while still persisting across relaunches.
    private var cachedEntries: [Entry]?

    private func entries() -> [Entry] {
        if let cachedEntries { return cachedEntries }
        guard let data = defaults.data(forKey: Self.storageKey) else {
            cachedEntries = []
            return []
        }
        let decoded = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        cachedEntries = decoded
        return decoded
    }

    private func save(_ entries: [Entry]) {
        cachedEntries = entries
        guard let data = try? JSONEncoder().encode(entries) else {
            logger.error("save: failed to encode \(entries.count) entries; on-disk store left unchanged.")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// See `PhotoDedupe.isLikelyDuplicate(hash:at:window:)`'s doc comment for the full
    /// evaluate-and-record contract this implements.
    func evaluateAndRecord(
        hash: PhotoHash,
        at date: Date,
        window: TimeInterval,
        threshold: Int,
        maxStored: Int
    ) -> Bool {
        let windowStart = date.addingTimeInterval(-window)
        var recent = entries().filter { $0.date >= windowStart }

        let isDuplicate = recent.contains {
            PhotoHash(bits: $0.bits).hammingDistance(to: hash) <= threshold
        }

        if !isDuplicate {
            recent.append(Entry(bits: hash.bits, date: date))
            // Oldest-first: this list isn't guaranteed sorted by `date` in general (a caller could
            // pass an out-of-order `date`, e.g. in tests), so sort before trimming rather than
            // assuming append order is already chronological.
            if recent.count > maxStored {
                recent.sort { $0.date < $1.date }
                recent.removeFirst(recent.count - maxStored)
            }
        }

        save(recent)
        return isDuplicate
    }

    /// See `PhotoDedupe.wouldBeDuplicate(hash:at:window:)`. Read-only: does not prune or save.
    func evaluate(hash: PhotoHash, at date: Date, window: TimeInterval, threshold: Int) -> Bool {
        let windowStart = date.addingTimeInterval(-window)
        return entries().contains {
            $0.date >= windowStart && PhotoHash(bits: $0.bits).hammingDistance(to: hash) <= threshold
        }
    }

    /// See `PhotoDedupe.recordAccepted(hash:at:window:)`.
    func record(hash: PhotoHash, at date: Date, window: TimeInterval, maxStored: Int) {
        let windowStart = date.addingTimeInterval(-window)
        var recent = entries().filter { $0.date >= windowStart }
        recent.append(Entry(bits: hash.bits, date: date))
        if recent.count > maxStored {
            recent.sort { $0.date < $1.date }
            recent.removeFirst(recent.count - maxStored)
        }
        save(recent)
    }

    /// See `PhotoDedupe.resetForTesting()`.
    func reset() {
        save([])
    }
}
