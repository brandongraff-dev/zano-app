import Foundation

/// Thin, typed wrapper around the App Group's shared `UserDefaults` suite
/// (`UserDefaults(suiteName: AppGroup.identifier)`, see `ModelContainer+AppGroup.swift`).
///
/// This is the *fast path* for state a Shield/Widget/Live-Activity extension needs to render
/// instantly — docs/spec.md §5.1 Living Shield ("Streak: 14 🔥"), §5.11 Dynamic Island Earn
/// Meter, §27 Known Platform Gotchas ("extensions must be tiny... no network... App Group state
/// only") — without opening the SwiftData store (`ModelContainer.appGroup`) just to read one
/// number. SwiftData stays the source of truth for everything durable (goals, events, lock
/// sessions, the full `Streak`/`TimeBank` rows, ...); every property below is a cheap mirror
/// that the engine which actually owns that state (`LockEngineManager`, `StreakEngine`,
/// `TimeBankEngine`, ...) writes whenever the underlying SwiftData record changes. Treat
/// `SharedDefaults` as read-mostly from everywhere except the one engine that owns each key.
///
/// Safety note: nothing here ever gates or disables the emergency-unlock path. CLAUDE.md: "Any
/// lock/shield feature must always keep an emergency-unlock path. Never trap the user." There is
/// deliberately no `emergencyUnlockEnabled`/`canEmergencyUnlock`-style flag anywhere in this
/// file — emergency unlock must always be reachable regardless of anything mirrored here, so
/// it's intentionally not represented as state that could be read as "off".
public enum SharedDefaults {

    /// `UserDefaults` is documented by Apple as safe to use concurrently from multiple threads,
    /// but as of this writing the stock SDK does not itself mark the class `Sendable`.
    /// `nonisolated(unsafe)` reflects that documented thread-safety guarantee under Swift 6
    /// strict concurrency; if a future SDK marks `UserDefaults` `Sendable` this annotation
    /// becomes a harmless no-op and can be dropped.
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    /// `true` when the App Group suite couldn't be opened (missing/misconfigured
    /// `com.apple.security.application-groups` entitlement on this target) and every property
    /// below is silently falling back to `UserDefaults.standard` — per-process only, **not**
    /// actually shared with the app or any other extension. Should always be `false` on a
    /// correctly configured build. Check it in a startup assertion or diagnostics screen rather
    /// than in normal control flow; this file itself never branches on it, so a misconfigured
    /// target degrades quietly (reads its own writes, sees nobody else's) instead of crashing.
    public static let isUsingFallbackStore: Bool =
        UserDefaults(suiteName: AppGroup.identifier) == nil

    private enum Keys {
        static let currentStreak = "shared.currentStreak"
        static let bestStreak = "shared.bestStreak"
        static let coachVoice = "shared.coachVoice"
        static let activeLockSessionID = "shared.activeLockSessionID"
        static let activeLockSetID = "shared.activeLockSetID"
        static let activeLockMode = "shared.activeLockMode"
        static let goalsRemainingForActiveLock = "shared.goalsRemainingForActiveLock"
        static let earnedMinutesRemainingToday = "shared.earnedMinutesRemainingToday"
        static let earnedMinutesMirrorDate = "shared.earnedMinutesMirrorDate"
        static let nextScheduledLockAt = "shared.nextScheduledLockAt"
        static let shieldImpressionCount = "shared.shieldImpressionCount"
    }

    // MARK: - Streak (spec §5.6 Never Miss Twice, §5.9 Ranks, §8 Retention Rules)

    /// Mirrors `StreakEngine.currentStreak()`. `StreakEngine` writes this on every
    /// `recordEarnedUnlock`/`recordMiss`/`useFreeze` call; everyone else only reads it.
    public static var currentStreak: Int {
        get { defaults.integer(forKey: Keys.currentStreak) }
        set { defaults.set(newValue, forKey: Keys.currentStreak) }
    }

    /// All-time longest streak, for celebratory shield/widget copy ("new best!"). Owned by
    /// `StreakEngine`.
    public static var bestStreak: Int {
        get { defaults.integer(forKey: Keys.bestStreak) }
        set { defaults.set(newValue, forKey: Keys.bestStreak) }
    }

    // MARK: - Coach voice (spec §5.13 Coach Voice)

    /// Raw coach-voice identifier — `"hype"`, `"toughLove"`, `"chill"`, or `"data"`, matching
    /// whatever raw values the `Copy` module's voice type uses
    /// (`Core/Sources/Core/Copy`). Kept as a plain `String` here rather than that module's own
    /// type so `Store` has no compile-time dependency on `Copy`; callers that need the strong
    /// type should look it up from this raw value on their side. Defaults to `"hype"`, matching
    /// onboarding's suggested default voice (spec §7).
    public static var coachVoice: String {
        get { defaults.string(forKey: Keys.coachVoice) ?? "hype" }
        set { defaults.set(newValue, forKey: Keys.coachVoice) }
    }

    // MARK: - Active lock (spec §5.1 Living Shield, §11 Architecture, §27 Gotchas)

    /// The `LockSession.id` currently in effect, `nil` when no lock is active. Written by
    /// `LockEngineManager.startLock`/`endLock` so `ShieldActionExtension` and
    /// `ShieldConfigurationExtension` (spec §27: shield buttons can't open the app directly, so
    /// these extensions must decide what to show/do from state like this alone) know which
    /// session is live without touching SwiftData.
    public static var activeLockSessionID: UUID? {
        get { uuid(forKey: Keys.activeLockSessionID) }
        set { setUUID(newValue, forKey: Keys.activeLockSessionID) }
    }

    /// The `LockSet.id` currently applied, `nil` when no lock is active.
    public static var activeLockSetID: UUID? {
        get { uuid(forKey: Keys.activeLockSetID) }
        set { setUUID(newValue, forKey: Keys.activeLockSetID) }
    }

    /// The active lock's mode (`.full` vs `.earn`, from `LockEngine/LockEngineManager.swift`'s
    /// `LockMode`), `nil` when no lock is active. Drives shield copy that reads differently
    /// depending on mode (e.g. earn mode can mention the Time Bank; full mode can't).
    public static var activeLockMode: LockMode? {
        get {
            guard let raw = defaults.string(forKey: Keys.activeLockMode) else { return nil }
            return LockMode(rawValue: raw)
        }
        set { defaults.set(newValue?.rawValue, forKey: Keys.activeLockMode) }
    }

    /// How many of the active lock's `requiredGoalIDs` are still unmet. Feeds Living Shield
    /// copy like "You're 12g of protein from unlocking everything" (spec §5.1) without a
    /// SwiftData fetch from inside the shield extension.
    public static var goalsRemainingForActiveLock: Int {
        get { defaults.integer(forKey: Keys.goalsRemainingForActiveLock) }
        set { defaults.set(newValue, forKey: Keys.goalsRemainingForActiveLock) }
    }

    // MARK: - Time Bank (spec §5.2 Earn Rate, §5.11 Dynamic Island Earn Meter)

    /// Mirrors `TimeBankEngine.remainingMinutes(for: .now)`, for `ZANOWidgets`'/the Dynamic
    /// Island's draining bar to render on its own timeline without opening SwiftData. Writing
    /// this also stamps `earnedMinutesMirrorDate`, which backs
    /// ``earnedMinutesMirrorIsForToday``.
    public static var earnedMinutesRemainingToday: Int {
        get { defaults.integer(forKey: Keys.earnedMinutesRemainingToday) }
        set {
            defaults.set(newValue, forKey: Keys.earnedMinutesRemainingToday)
            defaults.set(Date.now, forKey: Keys.earnedMinutesMirrorDate)
        }
    }

    /// `false` once local midnight has passed since ``earnedMinutesRemainingToday`` was last
    /// written. Time Bank minutes expire at midnight and never carry over (spec §5.2: "no
    /// hoarding"); a reader that sees `false` here should treat the mirrored balance as stale
    /// (i.e. show 0) rather than yesterday's leftover minutes, until `TimeBankEngine` refreshes
    /// it for the new day.
    public static var earnedMinutesMirrorIsForToday: Bool {
        guard let mirrorDate = defaults.object(forKey: Keys.earnedMinutesMirrorDate) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(mirrorDate)
    }

    /// When the active lock set is next scheduled to re-arm — a `DeviceActivity` schedule or
    /// the Bedtime Gate (spec §5.10) — for copy like "Gym is 6 min away" / next-lock countdowns
    /// in the widget and Live Activities. `nil` when nothing is scheduled.
    public static var nextScheduledLockAt: Date? {
        get { defaults.object(forKey: Keys.nextScheduledLockAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.nextScheduledLockAt) }
    }

    // MARK: - Shield impressions (spec §23 "Instrument from day one": "every shield impression
    // (count only, on device → aggregate)")

    /// Raw on-device tally of how many times `ShieldConfigurationExtension` has rendered a shield
    /// since the count was last flushed. Shield extensions do no networking (spec §11, §27), so
    /// this is the only place a shield impression is recorded the instant it happens — the count
    /// just accumulates here until some later app launch reports it. Prefer
    /// ``incrementShieldImpressionCount()``/``flushShieldImpressionCount()`` over reading/writing
    /// this directly; the getter/setter stay `public` for tests and diagnostics.
    public static var shieldImpressionCount: Int {
        get { defaults.integer(forKey: Keys.shieldImpressionCount) }
        set { defaults.set(newValue, forKey: Keys.shieldImpressionCount) }
    }

    /// Adds one to ``shieldImpressionCount``. Call from
    /// `ShieldConfigurationExtension.configuration(shielding:)` — the only intended writer of
    /// this key — every time a shield is actually rendered. `UserDefaults` doesn't give us a true
    /// atomic increment across processes, but the worst case from two shield renders racing here
    /// is undercounting by one impression on an aggregate, on-device, count-only metric, which is
    /// an acceptable trade for not adding cross-process locking inside a shield extension's tiny
    /// time/memory budget (spec §27: "extensions must be tiny").
    public static func incrementShieldImpressionCount() {
        defaults.set(defaults.integer(forKey: Keys.shieldImpressionCount) + 1, forKey: Keys.shieldImpressionCount)
    }

    /// Atomically reads ``shieldImpressionCount`` and resets it to `0`, for the main app to report
    /// as a single aggregate `Analytics.capture(event: "shield_impression")` call the next time it
    /// opens (see `LockStatusView`). Returns `0` — and writes nothing — when there's nothing to
    /// flush, so a caller can skip firing an empty event.
    @discardableResult
    public static func flushShieldImpressionCount() -> Int {
        let count = defaults.integer(forKey: Keys.shieldImpressionCount)
        guard count != 0 else { return 0 }
        defaults.set(0, forKey: Keys.shieldImpressionCount)
        return count
    }

    // MARK: - UUID storage helpers

    /// `UserDefaults` has no native `UUID` support (it's not a property-list type), so `UUID`
    /// properties above are stored as `uuidString` and parsed back here.
    private static func uuid(forKey key: String) -> UUID? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    private static func setUUID(_ value: UUID?, forKey key: String) {
        defaults.set(value?.uuidString, forKey: key)
    }
}
