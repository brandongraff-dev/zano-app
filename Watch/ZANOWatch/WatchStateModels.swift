// WatchStateModels.swift
// Watch/ZANOWatch
//
// Plain, `Codable`/`Sendable` data types shared between `WatchConnectivityBridge`,
// `WatchStateStore`, and every watch view — the watch-side half of the WatchConnectivity contract
// described in `WatchConnectivityBridge.swift`'s header comment. Every field here is deliberately
// named and shaped to mirror a real `Core` type 1:1 (see each type's doc comment for exactly which
// one) so that whichever future session wires the iPhone-side `WCSessionDelegate` (flagged as
// out-of-scope for this task in knownIssues — it would live in `Core/Sources/Core/Sync/*.swift`,
// which this run is explicitly forbidden from touching) can translate a decoded value here into a
// real `LockEngineManager`/`FocusSessionVerifier`/`GymVerifier` call, or vice versa, with no
// semantic guesswork — only a rename from this file's mirror type to the real one.
//
// No `import Core` — see `WatchTheme.swift`'s header comment for why that's not possible today.

import Foundation

// MARK: - Rings shown on the watch (Today tab + complication)

/// The subset of `Core/Sources/Core/Models/Goal.swift`'s `GoalType` cases the watch shows at a
/// glance — the same "three rings" set `GoalRing.swift`/`RingCluster.swift`'s own header comments
/// cite from spec §16's mockup ("Workout, Protein, Focus"), plus `water` (spec §6's medium widget
/// also always shows a water ring/button). Not every `GoalType` — a five-ring watch face reads as
/// noise; this task's scope is the glanceable subset, per CLAUDE.md's "don't add abstractions...
/// beyond what the current session's scope requires".
public enum WatchRingKind: String, CaseIterable, Sendable, Codable {
    case workout, protein, focus, water
}

/// One ring's display data. Deliberately not just a `[WatchRingKind: Double]` dictionary — a
/// dictionary can't hold `valueText` per ring, and `Codable` dictionaries with a non-`String`/`Int`
/// raw-representable key round-trip awkwardly through the plist-ish `[String: Any]` boundary
/// `WCSession` messages use elsewhere in this contract.
public struct WatchRingProgress: Sendable, Codable, Equatable, Identifiable {
    public var id: WatchRingKind { kind }
    public var kind: WatchRingKind
    /// Completion fraction. Any value is accepted; `WatchGoalRing` clamps to `0...1` the same way
    /// `Core`'s real `GoalRing` does.
    public var progress: Double
    /// Fully-composed value string (e.g. `"72/150g"`), or `nil` for a bare ring. Never formatted
    /// by the view — same copy discipline `GoalRing.swift`'s header comment states for the real
    /// component.
    public var valueText: String?

    public init(kind: WatchRingKind, progress: Double, valueText: String? = nil) {
        self.kind = kind
        self.progress = progress
        self.valueText = valueText
    }
}

// MARK: - Lock state (mirrors LockEngineManager's LockMode/LockTrigger + SharedDefaults' mirror)

/// Mirrors `Core/Sources/Core/LockEngine/LockEngineManager.swift`'s `public enum LockMode` —
/// **identical raw values** (`full`/`earn`) on purpose, so a phone-side bridge can round-trip this
/// through `LockMode(rawValue: mirror.rawValue)` with no translation table to keep in sync by hand.
public enum WatchLockModeMirror: String, Sendable, Codable, Equatable {
    case full
    case earn
}

/// Mirrors `LockEngineManager`'s `public enum LockTrigger` — same identical-raw-value contract as
/// `WatchLockModeMirror` above. The watch only ever originates `.manual` (a person tapping "Start
/// Lock" on their wrist); `.nfc`/`.schedule`/`.auto` are included so a *received* snapshot
/// (`WatchActiveLockSnapshot`, below — reflecting a lock already started some other way) can be
/// displayed accurately even when the watch itself didn't start it.
public enum WatchLockTriggerMirror: String, Sendable, Codable, Equatable {
    case nfc
    case schedule
    case manual
    case auto
}

/// Mirrors the handful of `Core/Sources/Core/Store/SharedDefaults.swift` fields that describe the
/// currently active lock (`activeLockSessionID`, `activeLockSetID`, `activeLockMode`,
/// `goalsRemainingForActiveLock`) — the same fields `LockEngineManager.mirrorActiveLock(_:)`
/// writes on every `startLock`.
public struct WatchActiveLockSnapshot: Sendable, Codable, Equatable {
    public var sessionID: UUID
    public var lockSetID: UUID
    public var mode: WatchLockModeMirror
    public var goalsRemaining: Int

    public init(sessionID: UUID, lockSetID: UUID, mode: WatchLockModeMirror, goalsRemaining: Int) {
        self.sessionID = sessionID
        self.lockSetID = lockSetID
        self.mode = mode
        self.goalsRemaining = goalsRemaining
    }
}

// MARK: - Gym dwell (mirrors GymDwellActivityAttributes.ContentState exactly)

/// Field-for-field mirror of `Core/Sources/Core/LiveActivity/GymDwellActivityAttributes.swift`'s
/// `ContentState` (`elapsedMinutes`/`verifiedAtMinutes`/`isVerified`), plus the attributes'
/// `gymName`, flattened into one struct since the watch has no attributes/content-state split to
/// preserve — it just renders the latest snapshot. This is exactly the shape
/// `GymVerifier.currentContentState(gymID:requiredMinutes:)` already assembles on the phone
/// (`Core/Sources/Core/Verification/GymVerifier.swift`); the phone-side bridge (not built this
/// task — see this file's header) would send this struct's fields straight from that call's
/// result plus `Gym.name`.
///
/// `isVerified` flipping `false` → `true` between two snapshots is exactly the transition
/// `WatchStateStore.apply(_:)` watches to fire the "verified" haptic (docs/spec.md §5.21).
public struct WatchGymDwellSnapshot: Sendable, Codable, Equatable {
    public var gymName: String
    public var elapsedMinutes: Int
    public var verifiedAtMinutes: Int
    public var isVerified: Bool

    public init(gymName: String, elapsedMinutes: Int, verifiedAtMinutes: Int, isVerified: Bool) {
        self.gymName = gymName
        self.elapsedMinutes = elapsedMinutes
        self.verifiedAtMinutes = verifiedAtMinutes
        self.isVerified = isVerified
    }
}

// MARK: - Focus session (mirrors FocusActivityAttributes + ContentState)

/// Field-for-field mirror of `Core/Sources/Core/LiveActivity/FocusActivityAttributes.swift`
/// (`goalTitle`, `plannedMinutes`) + its `ContentState` (`secondsRemaining`, `isPaused`), plus the
/// running session's id so the watch can send `WatchToPhoneRequest.endFocusSession(sessionID:)`
/// back for the exact session it's showing.
public struct WatchFocusSessionSnapshot: Sendable, Codable, Equatable {
    public var sessionID: UUID
    public var goalTitle: String
    public var plannedMinutes: Int
    public var secondsRemaining: Int
    public var isPaused: Bool

    public init(
        sessionID: UUID,
        goalTitle: String,
        plannedMinutes: Int,
        secondsRemaining: Int,
        isPaused: Bool
    ) {
        self.sessionID = sessionID
        self.goalTitle = goalTitle
        self.plannedMinutes = plannedMinutes
        self.secondsRemaining = secondsRemaining
        self.isPaused = isPaused
    }
}

// MARK: - The whole snapshot (phone -> watch, via WCSession application context)

/// Everything the watch app + complication render, in one `Codable` value. Sent whole
/// (`WCSession.updateApplicationContext(_:)` semantics: "latest wins", no queueing of partial
/// updates) rather than as a diff — small enough (a handful of ints/UUIDs/strings) that this is
/// simpler and can't drift into an inconsistent partial state.
public struct WatchStateSnapshot: Sendable, Codable, Equatable {
    public var rings: [WatchRingProgress]
    public var currentStreak: Int
    public var activeLock: WatchActiveLockSnapshot?
    public var gymDwell: WatchGymDwellSnapshot?
    public var focusSession: WatchFocusSessionSnapshot?

    /// The `LockSet.id` (`Core/Sources/Core/Models/LockSet.swift`) the wrist's one-tap "Start
    /// Lock" button should start, `nil` if the phone hasn't told the watch which one to suggest
    /// yet. The watch has no way to browse/pick from every saved `LockSet` (that needs the full
    /// SwiftData model graph this target can't reach — see this file's header), so `Core`'s side
    /// of this contract is expected to pick "the user's default/most-recently-used LockSet", the
    /// same way a single hardware NFC tag already implies one fixed LockSet today. A future
    /// version could let the watch cycle between a short suggested list; out of this task's scope.
    public var suggestedLockSetID: UUID?
    /// Mirrors `LockEngineManager.startLock(requiredGoalIDs:)`'s expectation of an explicit goal
    /// list — the phone is expected to populate this with whichever goals `suggestedLockSetID`
    /// actually requires, so `StartActionsView` doesn't have to guess.
    public var suggestedLockRequiredGoalIDs: [UUID]
    public var suggestedLockMode: WatchLockModeMirror

    /// The `Goal.id` + display title the wrist's one-tap "Start Focus" button should start —
    /// same one-suggestion-not-a-picker reasoning as `suggestedLockSetID` above.
    public var suggestedFocusGoalID: UUID?
    public var suggestedFocusGoalTitle: String?

    /// When the phone assembled this snapshot — shown as "last synced" copy so a stale (phone
    /// unreachable for hours) snapshot doesn't read as live data. Not the same as "when the watch
    /// received it" — deliberately: a snapshot sent while the phone had no connectivity and
    /// delivered later via `transferUserInfo` should still show its true original age.
    public var updatedAt: Date

    public init(
        rings: [WatchRingProgress],
        currentStreak: Int,
        activeLock: WatchActiveLockSnapshot?,
        gymDwell: WatchGymDwellSnapshot?,
        focusSession: WatchFocusSessionSnapshot?,
        suggestedLockSetID: UUID? = nil,
        suggestedLockRequiredGoalIDs: [UUID] = [],
        suggestedLockMode: WatchLockModeMirror = .full,
        suggestedFocusGoalID: UUID? = nil,
        suggestedFocusGoalTitle: String? = nil,
        updatedAt: Date
    ) {
        self.rings = rings
        self.currentStreak = currentStreak
        self.activeLock = activeLock
        self.gymDwell = gymDwell
        self.focusSession = focusSession
        self.suggestedLockSetID = suggestedLockSetID
        self.suggestedLockRequiredGoalIDs = suggestedLockRequiredGoalIDs
        self.suggestedLockMode = suggestedLockMode
        self.suggestedFocusGoalID = suggestedFocusGoalID
        self.suggestedFocusGoalTitle = suggestedFocusGoalTitle
        self.updatedAt = updatedAt
    }

    /// Shown before the watch has ever heard from the phone (fresh install, or `WatchStateStore`
    /// found nothing persisted). Every ring at zero, nothing active, no suggestion — never
    /// fabricated non-zero data (CLAUDE.md's spirit: never show the user a number ZANO didn't
    /// actually verify), and never a "Start Lock" button that would start a guessed `LockSet.id`.
    public static let empty = WatchStateSnapshot(
        rings: WatchRingKind.allCases.map { WatchRingProgress(kind: $0, progress: 0) },
        currentStreak: 0,
        activeLock: nil,
        gymDwell: nil,
        focusSession: nil,
        updatedAt: .distantPast
    )
}

// MARK: - Watch -> phone requests (via WCSession interactive messaging)

/// Every action the watch can ask the phone to perform, shaped to match the real `Core` call
/// signature it corresponds to (see each case's doc comment) so the not-yet-built phone-side
/// receiver is a direct pass-through, not a translation layer.
///
/// `WCSession.sendMessage(_:replyHandler:errorHandler:)` requires a plain
/// `[String: Any]` (property-list-compatible values only — no `UUID`, no `enum` — hence the
/// manual `asMessage`/`init?(message:)` below instead of `Codable`, which has no built-in bridge
/// to that boundary).
public enum WatchToPhoneRequest: Sendable, Equatable {
    /// Mirrors `FocusSessionVerifier.startSession(goalID:plannedMinutes:) async throws -> UUID`
    /// (`Core/Sources/Core/Verification/FocusSessionVerifier.swift`) — same two parameters, same
    /// names, same types.
    case startFocusSession(goalID: UUID, plannedMinutes: Int)

    /// Mirrors `FocusSessionVerifier.endSession(sessionID:) async throws -> Bool`.
    case endFocusSession(sessionID: UUID)

    /// Mirrors `LockEngineManager.startLock(lockSetID:mode:requiredGoalIDs:trigger:) async throws
    /// -> UUID` (`Core/Sources/Core/LockEngine/LockEngineManager.swift`) — same four parameters,
    /// same names, same types (`WatchLockModeMirror`/`WatchLockTriggerMirror` instead of the real
    /// `LockMode`/`LockTrigger` only because this target cannot import `Core` to reference those
    /// types directly; the raw values are identical by construction, see those mirrors' doc
    /// comments).
    case startLock(lockSetID: UUID, mode: WatchLockModeMirror, requiredGoalIDs: [UUID], trigger: WatchLockTriggerMirror)

    /// Mirrors `LockEngineManager.emergencyUnlock(sessionID:) async throws` — the always-available
    /// escape hatch (CLAUDE.md: "Emergency unlock must always exist on any lock-type feature.
    /// Never ship a lock with no way out."). The watch UI that sends this
    /// (`StartActionsView.swift`) gates it behind the same hold-to-confirm affordance
    /// `Theme.Motion.holdToCommitDuration`/`PrimaryButton`'s `.holdToCommit` variant use on the
    /// phone — mirrored locally the same way `WatchTheme.swift` mirrors everything else — so a
    /// stray wrist tap can't emergency-unlock by accident, while never making the path *harder*
    /// to reach than a deliberate 2-second hold.
    case emergencyUnlock(sessionID: UUID)

    private enum Key {
        static let type = "type"
        static let goalID = "goalID"
        static let plannedMinutes = "plannedMinutes"
        static let sessionID = "sessionID"
        static let lockSetID = "lockSetID"
        static let mode = "mode"
        static let requiredGoalIDs = "requiredGoalIDs"
        static let trigger = "trigger"
    }

    private enum TypeValue {
        static let startFocusSession = "startFocusSession"
        static let endFocusSession = "endFocusSession"
        static let startLock = "startLock"
        static let emergencyUnlock = "emergencyUnlock"
    }

    /// A plist-safe `[String: Any]`, ready for `WCSession.sendMessage`/`transferUserInfo`.
    public var asMessage: [String: Any] {
        switch self {
        case .startFocusSession(let goalID, let plannedMinutes):
            [Key.type: TypeValue.startFocusSession, Key.goalID: goalID.uuidString, Key.plannedMinutes: plannedMinutes]
        case .endFocusSession(let sessionID):
            [Key.type: TypeValue.endFocusSession, Key.sessionID: sessionID.uuidString]
        case .startLock(let lockSetID, let mode, let requiredGoalIDs, let trigger):
            [
                Key.type: TypeValue.startLock,
                Key.lockSetID: lockSetID.uuidString,
                Key.mode: mode.rawValue,
                Key.requiredGoalIDs: requiredGoalIDs.map(\.uuidString),
                Key.trigger: trigger.rawValue,
            ]
        case .emergencyUnlock(let sessionID):
            [Key.type: TypeValue.emergencyUnlock, Key.sessionID: sessionID.uuidString]
        }
    }

    /// Decodes a message built by `asMessage` back into a request. `nil` for anything malformed
    /// or unrecognized — a future phone-side receiver should treat that as "ignore, log it", never
    /// crash on an unexpected/older-watch-app message shape.
    public init?(message: [String: Any]) {
        guard let type = message[Key.type] as? String else { return nil }
        switch type {
        case TypeValue.startFocusSession:
            guard let goalIDString = message[Key.goalID] as? String,
                  let goalID = UUID(uuidString: goalIDString),
                  let plannedMinutes = message[Key.plannedMinutes] as? Int
            else { return nil }
            self = .startFocusSession(goalID: goalID, plannedMinutes: plannedMinutes)

        case TypeValue.endFocusSession:
            guard let sessionIDString = message[Key.sessionID] as? String,
                  let sessionID = UUID(uuidString: sessionIDString)
            else { return nil }
            self = .endFocusSession(sessionID: sessionID)

        case TypeValue.startLock:
            guard let lockSetIDString = message[Key.lockSetID] as? String,
                  let lockSetID = UUID(uuidString: lockSetIDString),
                  let modeRaw = message[Key.mode] as? String,
                  let mode = WatchLockModeMirror(rawValue: modeRaw),
                  let requiredGoalIDStrings = message[Key.requiredGoalIDs] as? [String],
                  let triggerRaw = message[Key.trigger] as? String,
                  let trigger = WatchLockTriggerMirror(rawValue: triggerRaw)
            else { return nil }
            self = .startLock(
                lockSetID: lockSetID,
                mode: mode,
                requiredGoalIDs: requiredGoalIDStrings.compactMap(UUID.init(uuidString:)),
                trigger: trigger
            )

        case TypeValue.emergencyUnlock:
            guard let sessionIDString = message[Key.sessionID] as? String,
                  let sessionID = UUID(uuidString: sessionIDString)
            else { return nil }
            self = .emergencyUnlock(sessionID: sessionID)

        default:
            return nil
        }
    }
}
