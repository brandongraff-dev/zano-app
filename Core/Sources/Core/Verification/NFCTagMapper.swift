// Core/Sources/Core/Verification/NFCTagMapper.swift
//
// docs/spec.md §6 ("Each tag encodes a URL like `zano://tag/<uuid>` mapped to an action in-app
// (Lock, Log Water 750ml, Log Shake 25g, Sunrise Key, Creatine)."), §14 App Intents Catalog
// ("NFC tag URL scheme: `zano://tag/<uuid>` → mapped in-app to one of the above with saved
// params."), §25.1 Tag Pack ("Setup: tag writes `zano://tag/<uuid>`; app maps it to an action in
// one screen.") and §25 tag kinds (Sunrise / Bottle / Shaker / Desk / Gym bag).
//
// This file owns two things:
//   1. The tag → action mapping itself (`NFCTagMapping`/`NFCTagAction`) and its storage.
//   2. Dispatching a resolved mapping to the matching App Intent (Session 4,
//      `Core/Sources/Core/Intents`).
//
// Storage note: there is deliberately no SwiftData model for tag mappings. docs/spec.md §13's
// Data Model table (the Session 1 Models this codebase treats as frozen — see this session's
// `decisions`) has no `nfc_tags` table, and a mapping is pure on-device configuration (which
// physical tag triggers which local action) with nothing to sync remotely — closer in spirit to
// `LockSet.appTokensBlob` (device-local, spec §13/§24: "FamilyControls app tokens never leave the
// device") than to a synced entity. Mappings are therefore persisted as a small JSON blob in the
// App Group's shared `UserDefaults` suite (`AppGroup.identifier`, `Store/ModelContainer+AppGroup.
// swift`), following the exact pattern `Store/SharedDefaults.swift` already uses for
// extension-readable state, without touching that file (owned by Session 1).

import AppIntents
import Foundation
import SwiftData

// MARK: - Tag kind (Tag Pack, spec §25.1)

/// Which physical tag this mapping is for, from the Tag Pack's five printed placements
/// (docs/spec.md §25.1: "Sunrise (mirror), Bottle, Shaker/Protein, Desk (focus), Gym bag").
/// Purely descriptive — it drives placement copy (`NFCTagSetupInstructions`) and a starting
/// `suggestedAction` for the one-screen mapping flow; `NFCTagMapper` itself dispatches on
/// `NFCTagAction`, never on `kind`.
public enum NFCTagKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Placed away from the bed (mirror, kitchen, coffee machine) — dismisses the Sunrise Alarm.
    case sunrise
    /// On a water bottle — logs a preset water amount.
    case bottle
    /// On a shaker/protein tub — logs a preset protein amount.
    case shaker
    /// On a desk — starts a focus lock.
    case desk
    /// In/on a gym bag — starts (or contributes to) a workout-oriented lock.
    case gymBag = "gym_bag"
    /// The Lock Card (spec §5.3, §25.2): tap to lock, tap again to check status. Also covers its
    /// Lock Key / Desk / MagSafe variants — they all run `.lockCardToggle`.
    case lockCard = "lock_card"
    /// A tag the user is mapping outside the stock placements (e.g. a spare Tag Pack tag put
    /// somewhere unplanned).
    case custom

    public var id: String { rawValue }
}

public extension NFCTagKind {
    /// A reasonable starting suggestion for the one-screen mapping flow (spec §25.1) — always
    /// shown as an editable default, never saved without the user confirming it. `nil` only for a
    /// Custom tag, which has no default at all.
    var suggestedAction: NFCTagAction? {
        switch self {
        case .sunrise: return .sunriseKey
        case .bottle: return .logWater(milliliters: 750)
        case .shaker: return .logProtein(grams: 25)
        // Spec §25.1 labels the Desk tag "(focus)"; 25 min is `StartFocusIntent`'s own default.
        case .desk: return .startFocus(minutes: 25)
        case .gymBag: return .gymCheckIn
        case .lockCard: return .lockCardToggle
        case .custom: return nil
        }
    }
}

// MARK: - Action

/// What tapping a mapped tag does. Spec §6's list ("Lock, Log Water 750ml, Log Shake 25g, Sunrise
/// Key, Creatine") plus the Tag Pack's Desk (focus) and Gym bag placements (§25.1), honesty-tier
/// custom goals, and the Lock Card (§5.3). `EndLockIntent` and `EmergencyUnlockIntent` are
/// deliberately never reachable by a tap: a tag can start or report on a lock, never end one.
///
/// Not `Hashable`/`Equatable`: `.startLock`'s `LockMode` payload is declared (system contract,
/// `LockEngine/LockEngineManager.swift`) as only `String, Codable` — not `Hashable` — and this
/// type must not presume conformances beyond what that contract actually states. If a future
/// change adds `Hashable` to `LockMode`, this type can safely gain it too.
public enum NFCTagAction: Codable, Sendable {
    /// → `StartLockIntent(lockSet:mode:requiredGoals:)`. `requiredGoalIDs` is usually `[]` for a
    /// tag-triggered lock (the Desk/Gym Bag tags start a lock, not a specific goal requirement);
    /// non-empty is supported for a tag mapped to "lock until goal X" setups.
    case startLock(lockSetID: UUID, mode: LockMode, requiredGoalIDs: [UUID])
    /// → `LogWaterIntent(ml:source:)`, always `source: .nfc`.
    case logWater(milliliters: Int)
    /// → `LogProteinIntent(grams:source:)`, always `source: .nfc`.
    case logProtein(grams: Int)
    /// → `LogCreatineIntent()`. Spec §14 lists no parameters for this intent at all.
    case logCreatine
    /// → `SunriseKeyIntent(tagId:)`, using the id of the tag that was actually scanned (spec
    /// §5.10: "Tapping the tag = alarm off + morning goal verified...").
    case sunriseKey
    /// → `StartFocusIntent(minutes:)` against the user's active Focus goal (the Desk tag).
    case startFocus(minutes: Int)
    /// Starts gym dwell tracking for the user's confirmed gym via `GymVerifier.beginDwellTracking`
    /// (the Gym Bag tag). The tap only *starts* the clock — the workout still verifies through
    /// `GymVerifier`'s own dwell + anti-cheat rules (spec §3); a tap far from the gym is ended by
    /// the geofence reporting "outside" once it is armed.
    case gymCheckIn
    /// → `LogCustomGoalIntent(goal:)`. The mapping UI only offers honesty-tier goals (custom,
    /// reading, cold shower/sauna), never an auto-verified one like a gym workout.
    case logCustomGoal(goalID: UUID)
    /// The Lock Card (spec §5.3): no lock running → start the default lock (`StartLockIntent()`);
    /// lock running → report what's left. **Never unlocks.** The emergency hold on the Lock tab
    /// stays the only manual way out (CLAUDE.md: emergency unlock always exists).
    case lockCardToggle
}

// MARK: - Mapping

/// One saved `zano://tag/<uuid>` → `NFCTagAction` mapping, plus the display metadata the
/// one-screen mapping flow (spec §25.1) and a "your tags" settings list need.
public struct NFCTagMapping: Codable, Sendable, Identifiable {
    /// The tag's id — the `<uuid>` in `zano://tag/<uuid>`.
    public let id: UUID
    /// Which physical Tag Pack placement this is, for grouping/iconography in settings.
    public var kind: NFCTagKind
    /// User-facing label, e.g. "Kitchen bottle" or "Desk lock". Editable at mapping time; this
    /// file has no opinion on its default beyond what the mapping UI (not owned here) passes in.
    public var label: String
    public var action: NFCTagAction
    public var createdAt: Date
    /// When this tag last ran its action (a successful dispatch through `handleTap`). `nil` until
    /// the first tap after mapping. Optional so mappings saved before this field existed still
    /// decode (synthesized `Decodable` treats a missing optional key as `nil`).
    public var lastTappedAt: Date?

    public init(
        id: UUID,
        kind: NFCTagKind = .custom,
        label: String,
        action: NFCTagAction,
        createdAt: Date = .now,
        lastTappedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.action = action
        self.createdAt = createdAt
        self.lastTappedAt = lastTappedAt
    }
}

// MARK: - Errors

public enum NFCTagMapperError: Error, Sendable, Equatable {
    /// The scanned URL wasn't a `zano://tag/<uuid>` URL at all, or its `<uuid>` segment didn't
    /// parse as a `UUID`. `NFCReader` filters most of this out already (it only resolves a scan
    /// when `tagID(from:)` succeeds), so in practice this only fires when `handleScannedURL` is
    /// called directly with an arbitrary URL (e.g. a deep link, not a live NFC scan).
    case invalidZanoURL(URL)
    /// A `.gymCheckIn` tag was tapped but the user has no confirmed gym saved yet.
    case noConfirmedGym
}

// MARK: - Dispatch outcome

/// What happened when a scanned tag was resolved and dispatched.
public enum NFCTagDispatchOutcome: Sendable {
    /// A mapping existed and its action was dispatched to the matching App Intent.
    case handled(action: NFCTagAction, tagID: UUID)
    /// The tag's id parsed fine, but no mapping is saved for it yet — the caller should route to
    /// the one-screen mapping flow (spec §25.1) rather than treat this as an error; tapping an
    /// unmapped tag for the first time is the expected setup path, not a failure.
    case unmapped(tagID: UUID)
}

/// What a handled tap actually did, resolved to plain values so the app can confirm it on screen
/// (`TagTapFeedback` in the app target turns this into "+25 g protein logged").
public enum NFCTagTapEffect: Sendable, Equatable {
    case loggedWater(milliliters: Int)
    case loggedProtein(grams: Int)
    case loggedCreatine
    case sunriseKey
    case lockStarted
    /// A Lock Card tap while a lock was already running: nothing changed, here's what's left.
    case lockStatus(goalsRemaining: Int)
    case focusStarted(minutes: Int)
    case gymCheckInStarted
    case loggedCustomGoal(title: String)
}

/// `NFCTagDispatchOutcome` plus what the tap did — the richer result `handleTap(_:)` returns.
public enum NFCTagTapResult: Sendable {
    case handled(mapping: NFCTagMapping, effect: NFCTagTapEffect)
    case unmapped(tagID: UUID)
}

// MARK: - NFCTagMapper

/// Resolves a scanned `zano://tag/<uuid>` URL to a stored `NFCTagMapping` and dispatches its
/// action to the matching App Intent. See the file-level doc comment for storage rationale.
///
/// Declared as a plain `actor` with a trivial `static let shared` singleton, matching every other
/// engine in `Core` (`LockEngineManager`, `TimeBankEngine`, `SyncEngine`, ...).
public actor NFCTagMapper {
    public static let shared = NFCTagMapper()

    private init() {}

    // MARK: URL parsing

    /// Parses the `<uuid>` out of a `zano://tag/<uuid>` URL. `nil` for anything else (wrong
    /// scheme, malformed uuid segment, or a URL that isn't a ZANO tag URL at all).
    ///
    /// Accepts two shapes defensively: the canonical `zano://tag/<uuid>` (host `"tag"`, `<uuid>`
    /// as the path) and, in case a tag was ever encoded without the `//` authority separator
    /// (`zano:tag/<uuid>` — some NDEF URI-record encoders normalize this), `"tag"` as the first
    /// path component instead of the host. Both are meant to represent the same identifier; this
    /// function does not distinguish the two on output.
    public static func tagID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "zano" else { return nil }

        if url.host?.lowercased() == "tag" {
            return UUID(uuidString: url.lastPathComponent)
        }

        let components = url.pathComponents.filter { $0 != "/" }
        if components.count >= 2, components[0].lowercased() == "tag" {
            return UUID(uuidString: components[1])
        }

        return nil
    }

    // MARK: Mapping CRUD

    /// In-memory cache of the persisted mappings, loaded lazily on first access this process and
    /// kept in sync with every write. Actor-isolated, so reads/writes from concurrent callers
    /// (e.g. a settings screen and a live NFC scan finishing at the same moment) serialize safely.
    private var cache: [UUID: NFCTagMapping]?

    /// The saved mapping for `tagID`, if any.
    public func mapping(for tagID: UUID) -> NFCTagMapping? {
        loadedMappings()[tagID]
    }

    /// All saved mappings, oldest first — the shape a "your tags" settings list wants.
    public func allMappings() -> [NFCTagMapping] {
        loadedMappings().values.sorted { $0.createdAt < $1.createdAt }
    }

    /// Saves (creating or overwriting) a mapping. The one-screen mapping flow (spec §25.1) calls
    /// this after the user confirms an action for a freshly-scanned tag.
    public func saveMapping(_ mapping: NFCTagMapping) {
        var mappings = loadedMappings()
        mappings[mapping.id] = mapping
        cache = mappings
        Self.persist(mappings)
    }

    /// Removes a saved mapping, e.g. from a "forget this tag" settings action.
    ///
    /// - Returns: `true` if a mapping existed and was removed, `false` if there was nothing to
    ///   remove.
    @discardableResult
    public func removeMapping(for tagID: UUID) -> Bool {
        var mappings = loadedMappings()
        guard mappings.removeValue(forKey: tagID) != nil else { return false }
        cache = mappings
        Self.persist(mappings)
        return true
    }

    private func loadedMappings() -> [UUID: NFCTagMapping] {
        if let cache { return cache }
        let loaded = Self.load()
        cache = loaded
        return loaded
    }

    // MARK: Persistence (App Group UserDefaults — see file-level doc comment)

    /// Mirrors `Store/SharedDefaults.swift`'s established fallback: `UserDefaults` is documented
    /// thread-safe but not SDK-marked `Sendable`, so this is `nonisolated(unsafe)` rather than
    /// actor-isolated storage; falls back to `.standard` (per-process only) if the App Group
    /// entitlement is missing/misconfigured, so a packaging bug degrades quietly instead of
    /// crashing an extension.
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private static let storageKey = "core.nfc.tagMappings.v1"

    private static func load() -> [UUID: NFCTagMapping] {
        guard
            let data = defaults.data(forKey: storageKey),
            let list = try? JSONDecoder().decode([NFCTagMapping].self, from: data)
        else {
            return [:]
        }
        // `uniquingKeysWith:`, not `uniqueKeysWithValues:` — this reads back a JSON blob from
        // `UserDefaults`, and a `uniqueKeysWithValues:` duplicate-key trap would crash every
        // caller (including a live NFC scan) on nothing worse than a corrupted preferences file.
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private static func persist(_ mappings: [UUID: NFCTagMapping]) {
        guard let data = try? JSONEncoder().encode(Array(mappings.values)) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // MARK: Resolve + dispatch

    /// Resolves `url` to a mapping and, if one exists, dispatches its action to the matching App
    /// Intent. Call this with the `rawURL` from an `NFCReader.scanOnce` result, or with a
    /// `zano://` deep link the app was opened with (spec §27: the background/notification-tap
    /// path hands the app a URL the same way a foreground scan does).
    ///
    /// - Throws: `NFCTagMapperError.invalidZanoURL` if `url` isn't a parseable `zano://tag/<uuid>`
    ///   URL, or whatever the dispatched App Intent's `perform()` throws.
    @discardableResult
    public func handleScannedURL(_ url: URL) async throws -> NFCTagDispatchOutcome {
        switch try await handleTap(url) {
        case .handled(let mapping, _):
            return .handled(action: mapping.action, tagID: mapping.id)
        case .unmapped(let tagID):
            return .unmapped(tagID: tagID)
        }
    }

    /// Same as `handleScannedURL(_:)`, but also returns what the tap did (for an on-screen
    /// confirmation) and stamps the mapping's `lastTappedAt`. Prefer this in new call sites.
    public func handleTap(_ url: URL) async throws -> NFCTagTapResult {
        guard let tagID = Self.tagID(from: url) else {
            throw NFCTagMapperError.invalidZanoURL(url)
        }
        guard let mapping = mapping(for: tagID) else {
            return .unmapped(tagID: tagID)
        }
        let effect = try await perform(mapping.action, scannedTagID: tagID)
        // Re-read after the `await`: actor reentrancy means the mapping may have been edited or
        // removed while the intent ran. Stamp only what is still saved; never resurrect a removed tag.
        guard var current = self.mapping(for: tagID) else {
            return .handled(mapping: mapping, effect: effect)
        }
        current.lastTappedAt = .now
        saveMapping(current)
        return .handled(mapping: current, effect: effect)
    }

    /// Convenience that opens a foreground scan (`NFCReader.shared.scanOnce`) and immediately
    /// resolves + dispatches whatever it reads. What a "Tap a tag" button in Today/Settings calls.
    ///
    /// - Parameters:
    ///   - alertMessage: Forwarded to `NFCReader.scanOnce` — caller-supplied copy, see that
    ///     method's doc comment.
    ///   - noMatchMessage: Forwarded to `NFCReader.scanOnce`.
    @discardableResult
    public func scanAndHandle(alertMessage: String, noMatchMessage: String? = nil) async throws -> NFCTagDispatchOutcome {
        let result = try await NFCReader.shared.scanOnce(alertMessage: alertMessage, noMatchMessage: noMatchMessage)
        return try await handleScannedURL(result.rawURL)
    }

    // MARK: Intent dispatch

    /// Constructs and runs the App Intent matching `action`, now that
    /// `Core/Sources/Core/Intents` (docs/spec.md §14) is real, on-disk code — this reconciles the
    /// call sites this method's doc comment originally flagged as a guess against those intents'
    /// actual signatures:
    ///   - `StartLockIntent.lockSet`/`requiredGoals` are `LockSetEntity?`/`[GoalEntity]?`
    ///     (`AppEntity` picker wrappers, `Intents/IntentSupport.swift`), not raw `UUID`s, so this
    ///     resolves them via `LockSetQuery`/`GoalQuery` first. `.mode` is the Siri-facing
    ///     `LockModeOption` (`Intents/StartLockIntent.swift`), a different type from
    ///     `LockEngine`'s `LockMode` this action carries — same case names, mapped by hand below.
    ///   - `LogWaterIntent`'s amount parameter is named `milliliters`, not `ml`.
    ///   - `LogProteinIntent.grams` is `Double`, not `Int` — `NFCTagAction.logProtein`'s `Int`
    ///     payload is converted at the call site.
    ///   - `SunriseKeyIntent.tagId` is a `String` (AppIntents has no raw `UUID` parameter type —
    ///     see that file's own header comment), not `UUID`.
    ///
    /// Every intent here is constructed with `source: .nfc` (or, for `StartLockIntent`, `trigger`
    /// is `LockEngineManager`'s job, not a settable intent param — see `SunriseKeyIntent`'s own
    /// `.nfc`-trigger call site for the equivalent pattern) since every call in this file
    /// genuinely did originate from a physical tag tap.
    private func perform(_ action: NFCTagAction, scannedTagID: UUID) async throws -> NFCTagTapEffect {
        switch action {
        case .startLock(let lockSetID, let mode, let requiredGoalIDs):
            let lockSetEntity = try await LockSetQuery().entities(for: [lockSetID]).first
            let modeOption: LockModeOption = (mode == .earn) ? .earn : .full
            let goalEntities = requiredGoalIDs.isEmpty
                ? nil
                : try await GoalQuery().entities(for: requiredGoalIDs)
            let intent = StartLockIntent(lockSet: lockSetEntity, mode: modeOption, requiredGoals: goalEntities)
            _ = try await intent.perform()
            return .lockStarted

        case .logWater(let milliliters):
            let intent = LogWaterIntent(milliliters: milliliters, source: .nfc)
            _ = try await intent.perform()
            return .loggedWater(milliliters: milliliters)

        case .logProtein(let grams):
            let intent = LogProteinIntent(grams: Double(grams), source: .nfc)
            _ = try await intent.perform()
            return .loggedProtein(grams: grams)

        case .logCreatine:
            let intent = LogCreatineIntent(source: .nfc)
            _ = try await intent.perform()
            return .loggedCreatine

        case .sunriseKey:
            let intent = SunriseKeyIntent(tagId: scannedTagID.uuidString)
            _ = try await intent.perform()
            return .sunriseKey

        case .startFocus(let minutes):
            let clamped = max(1, minutes)
            let intent = StartFocusIntent(minutes: clamped)
            _ = try await intent.perform()
            return .focusStarted(minutes: clamped)

        case .gymCheckIn:
            guard let gymID = try await Self.confirmedGymID() else {
                throw NFCTagMapperError.noConfirmedGym
            }
            await GymVerifier.shared.beginDwellTracking(gymID: gymID)
            return .gymCheckInStarted

        case .logCustomGoal(let goalID):
            guard let goal = try await GoalQuery().entities(for: [goalID]).first else {
                throw ZanoIntentError.goalNotFound
            }
            let intent = LogCustomGoalIntent(goal: goal)
            _ = try await intent.perform()
            return .loggedCustomGoal(title: goal.title)

        case .lockCardToggle:
            // Lock running → status only. This branch must never end or loosen a lock: the
            // emergency hold is the only manual exit (CLAUDE.md).
            if SharedDefaults.activeLockSessionID != nil {
                return .lockStatus(goalsRemaining: SharedDefaults.goalsRemainingForActiveLock)
            }
            _ = try await StartLockIntent().perform()
            return .lockStarted
        }
    }

    /// The current user's confirmed gym (`Gym.confirmed` — `GymVerifier` ignores unconfirmed
    /// rows anyway). `Gym` has no timestamp, so with several confirmed gyms the first by name is
    /// the stable, predictable pick.
    @MainActor
    private static func confirmedGymID() throws -> UUID? {
        let context = IntentSupport.makeContext()
        let user = try IntentSupport.currentUser(in: context)
        let userID = user.id
        let descriptor = FetchDescriptor<Gym>(
            predicate: #Predicate { $0.userID == userID && $0.confirmed }
        )
        let gyms = try context.fetch(descriptor)
        return gyms.min { ($0.name ?? "") < ($1.name ?? "") }?.id
    }
}
