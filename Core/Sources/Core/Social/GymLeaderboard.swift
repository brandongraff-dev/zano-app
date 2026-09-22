// Core/Sources/Core/Social/GymLeaderboard.swift
//
// docs/spec.md §5.8 Gym Home Turf (opt-in):
//   "Users who save the same gym form an anonymous leaderboard: 'You're #4 most consistent at
//   this gym this month.' Optional handle. Works as local virality: people at the same gym
//   discover the app from each other."
// Also docs/spec.md §5.9 Seasons, Ranks, Monthly Challenges ("Ranks... based on 4-week
// consistency (not volume, so a 3x/week person can hit Diamond)") — the same "consistency, not
// volume" framing this file's ranking uses, and §13 (Data Model — `gyms`).
//
// This file has no fixed public shape in the orchestrator's SYSTEM CONTRACTS block (unlike
// `GymVerifier`/`LockEngineManager`/etc.), so its API is designed here to satisfy this task and
// spec §5.8 exactly, following the same conventions `SquadManager.swift`/`ReferralManager.swift`
// (this same directory) already establish: an actor-owned `ModelContext` against the shared App
// Group store, `Sendable`/`Codable` snapshot structs instead of live `@Model` instances, a
// protocol seam for the one thing this device genuinely cannot compute on its own, and
// `LocalizedError` diagnostics kept out of `Core/Sources/Core/Copy` (whatever user-facing string
// a Gym Home Turf screen renders for "You're #4 most consistent at this gym this month" belongs
// in `Copy`, filled in from `GymLeaderboardEntry.rank`/`consistency` below — this file never
// formats that sentence itself, per CLAUDE.md "no hardcoded user-facing strings").
//
// Ownership: `Gym` (`Core/Sources/Core/Models/Gym.swift`) is reused verbatim — every field read
// below (`confirmed`, `id`) matches that file exactly, nothing is redeclared. `Goal`/`GoalType`/
// `GoalEvent`/`GoalEventKind`/`User` (same Models directory) are reused the same way.
// `SyncEngine.shared.enqueue` (`Core/Sources/Core/Sync`, another session) is called
// exactly per its own documented contract to queue this device's own opt-in fact for the backend
// — this file never talks to the network directly for that write (CLAUDE.md: "Extensions do no
// networking... Backend: Supabase... never put secrets in the app").
//
// Known architectural gaps (see this task's `knownIssues` in the structured report for the full
// list) — named here up front, the same way `SquadManager.swift`'s header comment does, so a
// future session reads the real shape of what exists vs. what's still a seam:
//
//   1. **Cross-user gym matching has no canonical id.** `Gym` (`Models/Gym.swift`) is just one
//      user's own saved `lat`/`lng`/`radiusMeters` — there is no `place_id`/shared-gym foreign
//      key anywhere in the schema (`backend/supabase/migrations/0001_init.sql`). "Two users share
//      a gym" can only be decided by geographic proximity clustering, and that clustering
//      threshold/algorithm is a backend decision this Core-only, no-Mac session has no basis to
//      invent silently. `GymLeaderboardBackend.fetchParticipants(gymID:...)` takes *this device's
//      own* `Gym.id` and leaves "which other users' gyms count as the same one" entirely to the
//      backend for exactly this reason.
//   2. **RLS forbids reading anyone else's `gyms`/`goal_events` rows from the client.**
//      `backend/supabase/migrations/0001_init.sql`: `create policy "gyms_owner" on gyms for all
//      using (user_id = auth.uid())`. Every other table with a `user_id` column carries the same
//      shape of policy. So even a direct authenticated Postgres query from this device could
//      never assemble a leaderboard — only a service-role backend function (a `SECURITY DEFINER`
//      RPC or Edge Function, matching how `ReferralManager.swift`'s header comment describes the
//      referral credit needing a service-role write) can read across users and return anonymized
//      rows. No such endpoint exists yet under `backend/supabase/functions` (today's list:
//      `meal-vision`, `revenuecat-webhook`, `sync`, `weekly-recap`) — `GymLeaderboardBackend`
//      below is the seam a future backend session implements against, exactly the same pattern
//      `SquadManager.SquadRingSource`/`ReferralManager.ReferralBackend` already establish.
//   3. **Consistency is scored from `.workoutGym`-type goal completions, not "at this specific
//      gym."** Neither `Goal` nor `GoalEvent` (`Models/Goal.swift`, `Models/GoalEvent.swift`)
//      carries a `gymID` linking a completion back to which saved `Gym` earned it — `GymVerifier`
//      (`Core/Sources/Core/Verification/GymVerifier.swift`) verifies dwell/anti-cheat but does not
//      itself write `GoalEvent` rows (see that file's doc comment: "this file does not write
//      GoalEvent itself"), so there is nowhere upstream that could have recorded one even if this
//      file wanted to read it. This file therefore scores a user's overall `.workoutGym`
//      consistency (see `fetchVerifiedWorkoutGymEvents`), which is the correct answer for a user
//      with exactly one confirmed gym (the common case a "home turf" feature is built for) but
//      would double-count someone who confirmed more than one gym rather than splitting their
//      consistency per gym. Flagged, not silently assumed away.
//   4. **This device never trusts a client-submitted consistency number.** See
//      `GymLeaderboardBackend`'s doc comment: only the opt-in *fact* (`optedIn`/`handle`) is
//      queued through the Sync outbox; every participant's actual `consistency` — including this
//      device's own, as seen by *other* users — must be computed server-side from the
//      `goal_events` rows that already sync through that same outbox. A leaderboard that let the
//      client dictate its own score would be trivially gameable.

import Foundation
import SwiftData
import os

// MARK: - Errors

/// Errors `GymLeaderboardManager` throws itself, as opposed to errors bubbled up from SwiftData
/// or a `GymLeaderboardBackend`. Plain, developer-facing diagnostics — mirroring
/// `SquadManagerError`/`ReferralManagerError`'s documented convention — never routed through
/// `Core/Sources/Core/Copy`; whatever user-facing message a Gym Home Turf screen chooses for one
/// of these belongs there, not here.
public enum GymLeaderboardManagerError: Error, Sendable, Equatable, LocalizedError {
    /// No local `User` row exists yet to attribute this action to.
    case noSignedInUser
    /// `updateHandle`/`optIn(handle:)` was given a handle outside
    /// ``GymLeaderboardManager/handleLengthRange`` or containing a character outside
    /// ``GymLeaderboardManager/handleAllowedCharacters``.
    case invalidHandle(String)
    /// No local `Gym` exists with this id — it was never saved on this device (or belongs to a
    /// different device entirely; local storage only ever holds the signed-in user's own gyms,
    /// per `Models/User.swift`'s documented single-user-graph assumption).
    case gymNotFound(UUID)
    /// `Gym.confirmed == false` for this id. Mirrors `Gym.confirmed`'s own documented invariant
    /// ("GymVerifier must only use confirmed gyms for real unlocks; an unconfirmed autoDetected
    /// row is a suggestion only") — the same rule applies here: an unconfirmed candidate gym never
    /// gets a leaderboard, so a user can't be shown consistency rankings for a location they
    /// haven't actually confirmed as their gym yet.
    case gymNotConfirmed(UUID)
    /// `leaderboard(gymID:...)` was called before a `GymLeaderboardBackend` was configured
    /// (`setBackend(_:)`) — expected before a backend session lands, mirroring
    /// `SyncEngineError.backendUnavailable`/`ReferralManagerError.backendUnavailable`.
    case backendUnavailable

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser:
            "No local User row exists yet."
        case .invalidHandle(let handle):
            "\"\(handle)\" is not a valid leaderboard handle."
        case .gymNotFound(let id):
            "No Gym found with id \(id)."
        case .gymNotConfirmed(let id):
            "Gym \(id) is not confirmed yet — Gym Home Turf only ranks confirmed gyms."
        case .backendUnavailable:
            "No GymLeaderboardBackend configured — cannot fetch other members' standings yet."
        }
    }
}

// MARK: - Opt-in state

/// This device's own Gym Home Turf participation (spec §5.8: "opt-in... Optional handle").
/// A single, account-level toggle — not per-gym — since the spec's handle is one identity the
/// user shows across whichever confirmed gym(s) they opt into, not a per-location alias.
public struct GymLeaderboardOptIn: Sendable, Equatable, Codable {
    public var optedIn: Bool
    /// `nil`/empty means "anonymous, ranked by number only" — spec §5.8's "Optional handle" is
    /// optional in the literal sense: opting in never requires picking one.
    public var handle: String?
    public var optedInAt: Date?

    public init(optedIn: Bool = false, handle: String? = nil, optedInAt: Date? = nil) {
        self.optedIn = optedIn
        self.handle = handle
        self.optedInAt = optedInAt
    }

    public static let notOptedIn = GymLeaderboardOptIn()
}

// MARK: - Consistency (local, always computable)

/// This device's own trailing-window `.workoutGym` consistency — see this file's header comment,
/// gap 3, for exactly what "consistency" is scored from. Always computable locally, with no
/// backend and regardless of opt-in state, so a Gym Home Turf screen can show "you'd rank..." as
/// a hook before the user ever opts in.
public struct GymConsistencyScore: Sendable, Equatable, Codable {
    public let userID: UUID
    /// Local midnight of the first day counted (inclusive).
    public let windowStart: Date
    /// Local midnight of the last day counted (inclusive) — the window's reference day, normally
    /// "today."
    public let windowEnd: Date
    public let trailingDays: Int
    /// How many of the `trailingDays` calendar days had at least one verified `.workoutGym`
    /// completion (`.complete`, `.planB`, or `.freeze` — see `fetchVerifiedWorkoutGymEvents`'s
    /// doc comment for why a freeze counts as consistent, not a miss).
    public let consistentDays: Int

    public init(userID: UUID, windowStart: Date, windowEnd: Date, trailingDays: Int, consistentDays: Int) {
        self.userID = userID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.trailingDays = trailingDays
        self.consistentDays = consistentDays
    }

    /// `0...1`. `0` (not vacuously `1`) when `trailingDays == 0` — matching
    /// `SquadMemberRingDay.fraction`'s identical "empty means 0, not full" convention.
    public var consistency: Double {
        trailingDays > 0 ? Double(consistentDays) / Double(trailingDays) : 0
    }
}

// MARK: - Leaderboard (ranking computation)

/// One opted-in participant's standing at a shared gym, exactly as a `GymLeaderboardBackend`
/// returns it — already anonymized server-side (see that protocol's doc comment for what
/// "anonymized" is assumed to mean) and already scored over the requested trailing window.
public struct GymLeaderboardParticipant: Sendable, Equatable, Codable, Identifiable {
    /// An opaque id used only to match a row against the signed-in user (`id == currentUserID`)
    /// and, when scores tie, to keep a stable sort order — never shown to the person viewing the
    /// leaderboard. Whether the backend happens to make this the participant's real `users.id` or
    /// a per-leaderboard pseudonymous id is a backend decision this file has no opinion on; either
    /// way this file never surfaces it as identity.
    public let id: UUID
    /// The handle that participant chose (`GymLeaderboardOptIn.handle`), `nil` if they opted in
    /// anonymously.
    public let handle: String?
    /// `0...1`. Clamped defensively on construction — a backend bug or a stale cached payload
    /// producing something outside that range should degrade to the nearest valid value rather
    /// than corrupt every rank computed from it.
    public let consistency: Double

    public init(id: UUID, handle: String?, consistency: Double) {
        self.id = id
        self.handle = handle
        self.consistency = min(1, max(0, consistency))
    }
}

/// One ranked row, ready for a Gym Home Turf screen to interpolate into spec §5.8's copy
/// template ("You're #4 most consistent at this gym this month") — that interpolation itself
/// belongs in `Core/Sources/Core/Copy`, not here.
public struct GymLeaderboardEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    /// 1-based. Tied consistency scores share a rank (standard competition ranking: 1, 2, 2, 4 —
    /// see `GymLeaderboardManager.rank(participants:currentUserID:)`'s doc comment for why).
    public let rank: Int
    public let handle: String?
    public let consistency: Double
    public let isCurrentUser: Bool

    public init(id: UUID, rank: Int, handle: String?, consistency: Double, isCurrentUser: Bool) {
        self.id = id
        self.rank = rank
        self.handle = handle
        self.consistency = consistency
        self.isCurrentUser = isCurrentUser
    }
}

/// A full gym's leaderboard, ready for a Gym Home Turf screen to render.
public struct GymLeaderboardResult: Sendable, Equatable, Codable {
    public let gymID: UUID
    public let windowStart: Date
    public let windowEnd: Date
    public let trailingDays: Int
    /// Ranked highest-consistency first. Empty (not an error) when nobody at this gym has opted
    /// in yet — spec §5.8 is opt-in, so "no one else has joined" is an expected, normal state.
    public let entries: [GymLeaderboardEntry]
    /// The signed-in user's own row, if present — `nil` when they haven't opted in on this
    /// device, or the backend hasn't returned it for any other reason. A UI showing "You're #4"
    /// should treat `nil` here as "not ranked yet," never render a fabricated rank.
    public let currentUserEntry: GymLeaderboardEntry?

    public init(
        gymID: UUID,
        windowStart: Date,
        windowEnd: Date,
        trailingDays: Int,
        entries: [GymLeaderboardEntry],
        currentUserEntry: GymLeaderboardEntry?
    ) {
        self.gymID = gymID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.trailingDays = trailingDays
        self.entries = entries
        self.currentUserEntry = currentUserEntry
    }

    public var totalParticipants: Int { entries.count }
}

// MARK: - Backend seam (a future backend session implements this for real)

/// Resolves everyone else sharing a confirmed gym's opted-in consistency standing — the one piece
/// of this feature that can never be computed on-device. See this file's header comment (gaps 1,
/// 2, 4) for exactly why: no canonical cross-user gym id exists to match on, Postgres RLS forbids
/// this device from reading anyone else's rows directly, and a client-submitted consistency
/// number could never be trusted on a competitive leaderboard anyway.
///
/// Exactly the seam `SquadManager.SquadRingSource`/`ReferralManager.ReferralBackend` already
/// establish for "no real networking yet, here is where the real implementation plugs in": a
/// future backend session constructs a concrete conformance and calls
/// `GymLeaderboardManager.shared.setBackend(_:)` once, and `leaderboard(gymID:...)` starts
/// returning everyone, not just the signed-in user.
///
/// Deliberately **read-only** — there is no `submitScore`-style write anywhere in this file. This
/// device's own opt-in *fact* (`optedIn`/`handle`) is queued through the ordinary Sync outbox
/// (`SyncEngine.shared.enqueue`, see `optIn`/`optOut`/`updateHandle` below), the same way
/// `SquadManager`/`ReferralManager` queue every other locally-originated fact; every
/// participant's actual `consistency` — including how the signed-in user's own score appears to
/// *other* people's devices — must be computed server-side from the `goal_events` rows that
/// already sync through that same outbox under their own `entityName`. Only the backend is ever
/// in a position to compute a number the rest of the leaderboard can trust.
public protocol GymLeaderboardBackend: Sendable {
    /// - Parameters:
    ///   - gymID: this device's own local `Gym.id` for the confirmed gym being viewed. The
    ///     backend resolves which *other* users' saved gyms count as "the same physical gym"
    ///     (geographic clustering — see this file's header comment, gap 1) from this id.
    ///   - trailingDays: the consistency window width, in days, so every participant is scored
    ///     over the identical window this device used for its own local score
    ///     (`GymLeaderboardManager.defaultTrailingDays` unless the caller overrides it).
    ///   - asOf: the window's reference day (local midnight of "today," normally). Passed
    ///     explicitly rather than always meaning "the server's now" so a client-triggered refresh
    ///     and the locally-computed score it's compared against always agree on which day range
    ///     they mean, even close to a day boundary.
    /// - Returns: every opted-in participant sharing this gym, already anonymized and already
    ///   scored. Never includes users who have not opted in, regardless of how many goals they've
    ///   completed — spec §5.8 is explicit that this is opt-in.
    func fetchParticipants(gymID: UUID, trailingDays: Int, asOf: Date) async throws -> [GymLeaderboardParticipant]
}

// MARK: - GymLeaderboardManager

/// The sole owner of this device's Gym Home Turf opt-in state and of the leaderboard
/// ranking/consistency computation (spec §5.8). Declared a plain `actor` — matching
/// `SquadManager`'s exact convention for a `Core` engine, in this same directory, that owns a
/// `ModelContext` and has no reason to be pinned to `@MainActor` (no `ManagedSettingsStore`/
/// `CLLocationManager`/`DeviceActivityCenter`-style main-thread-only Apple API is involved here,
/// unlike `LockEngineManager`/`GymVerifier`) — so `static let shared` stays a trivial singleton
/// and every method is safely callable from any isolation domain via `await`.
public actor GymLeaderboardManager {
    public static let shared = GymLeaderboardManager()

    /// The task's own wording ("goal completion rate over the trailing 30 days") — a fixed
    /// window, not a calendar month, so "today" always looks back the same distance regardless of
    /// where in the month it falls. Spec §5.8's "this month" copy is a UI/Copy framing of this
    /// same rolling window, not a literal calendar-month boundary this file needs to track.
    public static let defaultTrailingDays = 30

    /// Handles are free-typed but shown next to a rank on an otherwise-anonymous leaderboard, so
    /// kept short and unambiguous — mirroring `SquadManager`/`ReferralManager`'s identical
    /// documented-length-and-alphabet choices for invite/referral codes. Not spec-mandated (spec
    /// §5.8 only says "Optional handle"); a reasonable, narrow default rather than accepting
    /// arbitrary free text on a field other people will see.
    public static let handleLengthRange = 2...20
    public static let handleAllowedCharacters: CharacterSet =
        .alphanumerics.union(CharacterSet(charactersIn: "_-"))

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "GymLeaderboardManager")

    private var backend: GymLeaderboardBackend?

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance against
    /// an in-memory container and an injected `GymLeaderboardBackend` — every real call site uses
    /// `.shared`. Mirrors `SquadManager`/`ReferralManager`'s identical testability convention.
    init(modelContainer: ModelContainer = .appGroup, backend: GymLeaderboardBackend? = nil) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.backend = backend
    }

    /// Swaps in a real `GymLeaderboardBackend` once a backend session builds one — the seam this
    /// file's header comment describes. Safe to call at any time.
    public func setBackend(_ backend: GymLeaderboardBackend?) {
        self.backend = backend
    }

    // MARK: - Opt-in (spec §5.8: "opt-in... Optional handle")

    /// This device's current opt-in state. Never throws — an unreadable/missing local value is
    /// indistinguishable from "never opted in," which is the correct default anyway.
    public func optInStatus() -> GymLeaderboardOptIn {
        loadOptIn() ?? .notOptedIn
    }

    /// Opts the signed-in user into Gym Home Turf leaderboards for every confirmed gym they have
    /// (spec §5.8: account-level, not per-gym — see `GymLeaderboardOptIn`'s doc comment), with an
    /// optional handle. Idempotent: calling this again just updates the handle and re-stamps
    /// `optedInAt`.
    @discardableResult
    public func optIn(handle rawHandle: String? = nil) async throws -> GymLeaderboardOptIn {
        let user = try fetchCurrentUser()
        let handle = try Self.validateHandle(rawHandle)

        let state = GymLeaderboardOptIn(optedIn: true, handle: handle, optedInAt: .now)
        saveOptIn(state)

        try? await enqueueSync(
            entityName: "GymLeaderboardOptIn",
            entityID: user.id,
            payload: GymLeaderboardOptInSyncPayload(userID: user.id, optedIn: true, handle: handle)
        )
        Analytics.shared.capture(event: "gym_leaderboard_opted_in", properties: ["has_handle": handle != nil])
        logger.notice("Gym Home Turf opt-in enabled.")
        return state
    }

    /// Opts out. The handle is kept locally (so re-opting-in doesn't require retyping it) but the
    /// device stops publishing/appearing on any gym's leaderboard — mirrors
    /// `SquadManager.consumeSharedFreeze`'s "durable local fact, queued for sync" pattern.
    public func optOut() async {
        var state = loadOptIn() ?? .notOptedIn
        state.optedIn = false
        saveOptIn(state)

        if let userID = try? fetchCurrentUser().id {
            try? await enqueueSync(
                entityName: "GymLeaderboardOptIn",
                entityID: userID,
                payload: GymLeaderboardOptInSyncPayload(userID: userID, optedIn: false, handle: state.handle)
            )
        }
        Analytics.shared.capture(event: "gym_leaderboard_opted_out")
        logger.notice("Gym Home Turf opt-in disabled.")
    }

    /// Updates the handle without changing opt-in status. Pass `nil` (or an all-whitespace
    /// string) to go anonymous while staying opted in.
    @discardableResult
    public func updateHandle(_ rawHandle: String?) async throws -> GymLeaderboardOptIn {
        let user = try fetchCurrentUser()
        let handle = try Self.validateHandle(rawHandle)

        var state = loadOptIn() ?? .notOptedIn
        state.handle = handle
        saveOptIn(state)

        if state.optedIn {
            try? await enqueueSync(
                entityName: "GymLeaderboardOptIn",
                entityID: user.id,
                payload: GymLeaderboardOptInSyncPayload(userID: user.id, optedIn: true, handle: handle)
            )
        }
        return state
    }

    // MARK: - Local consistency (spec §5.8/§5.9: "consistency, not volume")

    /// This device's own `.workoutGym` consistency over the trailing window ending `asOf` — see
    /// this file's header comment, gap 3, for exactly what's counted. Computed purely from local
    /// `GoalEvent` rows; never needs a backend or opt-in status, so a Gym Home Turf screen can
    /// show this as a "here's how you'd rank" preview before the user ever opts in.
    ///
    /// Uses `asOf` (defaulting to `.now`) directly as the window's reference day, deliberately
    /// unlike `AdaptiveGoalEngine.adjustDifficulty`'s `referenceDay(from:)`, which anchors to the
    /// *latest event's* day instead of `Date.now` for reasons specific to that file's difficulty
    /// adjustment. A leaderboard has no equivalent reason to drift: every participant's window
    /// must be anchored to the same real calendar day for the ranking to be a fair comparison, and
    /// a user with zero events today should still be scored "as of today," not as of whenever they
    /// last logged something.
    public func myConsistencyScore(
        trailingDays: Int = GymLeaderboardManager.defaultTrailingDays,
        asOf date: Date = .now
    ) async throws -> GymConsistencyScore {
        let user = try fetchCurrentUser()

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: date)
        guard trailingDays > 0 else {
            return GymConsistencyScore(userID: user.id, windowStart: referenceDay, windowEnd: referenceDay, trailingDays: 0, consistentDays: 0)
        }
        let windowStart = calendar.date(byAdding: .day, value: -(trailingDays - 1), to: referenceDay) ?? referenceDay
        let windowEndExclusive = calendar.date(byAdding: .day, value: 1, to: referenceDay) ?? referenceDay

        let events = try fetchVerifiedWorkoutGymEvents(from: windowStart, to: windowEndExclusive)
        let consistentDayKeys = Set(events.map { Self.dayKey(for: $0.ts) })

        var consistentDays = 0
        for offset in 0..<trailingDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: referenceDay) else { continue }
            if consistentDayKeys.contains(Self.dayKey(for: day)) { consistentDays += 1 }
        }

        return GymConsistencyScore(
            userID: user.id,
            windowStart: windowStart,
            windowEnd: referenceDay,
            trailingDays: trailingDays,
            consistentDays: consistentDays
        )
    }

    // MARK: - Leaderboard

    /// Builds gym `gymID`'s ranked leaderboard: this device's own consistency, computed fresh
    /// from local data, plus every other opted-in participant the configured
    /// `GymLeaderboardBackend` returns.
    ///
    /// Viewing never requires having opted in yourself — spec §5.8's "opt-in" gates *appearing*
    /// on a leaderboard, not looking at one. `currentUserEntry` is only ever populated when this
    /// device's own opt-in state is `optedIn == true`; see the inline comment below for why that
    /// check is enforced here too, not just trusted from the backend response.
    ///
    /// - Throws: ``GymLeaderboardManagerError/gymNotFound(_:)`` /
    ///   ``GymLeaderboardManagerError/gymNotConfirmed(_:)`` for a bad/unconfirmed `gymID`,
    ///   ``GymLeaderboardManagerError/backendUnavailable`` if no `GymLeaderboardBackend` is
    ///   configured yet, or whatever `GymLeaderboardBackend.fetchParticipants` itself throws.
    public func leaderboard(
        gymID: UUID,
        trailingDays: Int = GymLeaderboardManager.defaultTrailingDays,
        asOf date: Date = .now
    ) async throws -> GymLeaderboardResult {
        guard let gym = try fetchGym(id: gymID) else {
            throw GymLeaderboardManagerError.gymNotFound(gymID)
        }
        guard gym.confirmed else {
            throw GymLeaderboardManagerError.gymNotConfirmed(gymID)
        }
        guard let backend else {
            throw GymLeaderboardManagerError.backendUnavailable
        }
        let user = try fetchCurrentUser()

        let localScore = try await myConsistencyScore(trailingDays: trailingDays, asOf: date)
        var participants = try await backend.fetchParticipants(gymID: gymID, trailingDays: trailingDays, asOf: date)

        // This device is always the freshest, most trustworthy source of its own consistency
        // (spec's "local-first, instant" bias, CLAUDE.md "Local-first data") — a backend
        // computation may lag behind whatever synced most recently. Overwrite (or insert) the
        // signed-in user's own row with the number just computed above, but only when actually
        // opted in: never show this device's own row on a leaderboard it hasn't joined, even if a
        // stale/misbehaving backend response happened to include one — a client-side guarantee,
        // not a substitute for the backend enforcing the same rule server-side.
        let optIn = loadOptIn() ?? .notOptedIn
        participants.removeAll { $0.id == user.id }
        if optIn.optedIn {
            participants.append(GymLeaderboardParticipant(id: user.id, handle: optIn.handle, consistency: localScore.consistency))
        }

        let entries = Self.rank(participants: participants, currentUserID: user.id)
        let currentUserEntry = entries.first { $0.isCurrentUser }

        Analytics.shared.capture(event: "gym_leaderboard_viewed", properties: ["gym_id": gymID.uuidString, "participant_count": entries.count])
        return GymLeaderboardResult(
            gymID: gymID,
            windowStart: localScore.windowStart,
            windowEnd: localScore.windowEnd,
            trailingDays: trailingDays,
            entries: entries,
            currentUserEntry: currentUserEntry
        )
    }

    // MARK: - Ranking (pure; no SwiftData, no network — the computation this task asks for)

    /// Ranks `participants` by consistency, highest first, and marks whichever entry (if any)
    /// matches `currentUserID`.
    ///
    /// Ties share a rank — standard competition ranking (1, 2, 2, 4), not a coin-flip ordering —
    /// because two participants with the identical trailing-window consistency really are equally
    /// consistent; silently giving one of them a better number than the other would be exactly
    /// the kind of ranking artifact spec §5.8/§5.9's "consistency, not volume" framing is trying
    /// to avoid. Exact `Double` equality is safe for this comparison specifically because every
    /// `consistency` value a real caller passes in is `Int / Int` over the *same* `trailingDays`
    /// denominator for the whole leaderboard (`GymConsistencyScore.consistency`,
    /// `GymLeaderboardBackend.fetchParticipants(gymID:trailingDays:asOf:)`'s contract) — two
    /// participants who completed the same number of consistent days produce bit-identical
    /// `Double`s, not merely close ones.
    ///
    /// Beyond the consistency comparison itself, ties are broken by `participants`' input order
    /// (`Array.sorted(by:)` is a documented-stable sort in Swift) rather than by, say, `handle`
    /// text — sorting by handle would let two anonymous users infer something about each other
    /// from a coincidence of display names, which has nothing to do with either person's actual
    /// consistency.
    public static func rank(participants: [GymLeaderboardParticipant], currentUserID: UUID?) -> [GymLeaderboardEntry] {
        let sorted = participants.sorted { $0.consistency > $1.consistency }

        var entries: [GymLeaderboardEntry] = []
        entries.reserveCapacity(sorted.count)
        var previousConsistency: Double?
        var previousRank = 0

        for (index, participant) in sorted.enumerated() {
            let rank: Int
            if let previousConsistency, participant.consistency == previousConsistency {
                rank = previousRank
            } else {
                rank = index + 1
            }
            entries.append(
                GymLeaderboardEntry(
                    id: participant.id,
                    rank: rank,
                    handle: participant.handle,
                    consistency: participant.consistency,
                    isCurrentUser: currentUserID != nil && participant.id == currentUserID
                )
            )
            previousConsistency = participant.consistency
            previousRank = rank
        }
        return entries
    }

    // MARK: - Handle validation

    private static func validateHandle(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard handleLengthRange.contains(trimmed.count) else {
            throw GymLeaderboardManagerError.invalidHandle(trimmed)
        }
        guard trimmed.unicodeScalars.allSatisfy({ handleAllowedCharacters.contains($0) }) else {
            throw GymLeaderboardManagerError.invalidHandle(trimmed)
        }
        return trimmed
    }

    // MARK: - SwiftData

    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw GymLeaderboardManagerError.noSignedInUser
        }
        return user
    }

    private func fetchGym(id: UUID) throws -> Gym? {
        var descriptor = FetchDescriptor<Gym>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Every verified `.workoutGym`-goal-type `GoalEvent` in `[from, to)`, counted as a
    /// consistent day for `.complete`, `.planB` (spec §5.5 Plan B Days — a smaller goal that still
    /// preserves the streak), or `.freeze` (spec §5.6 Never Miss Twice — a freeze covers the day
    /// instead of a completion; treating it as anything other than consistent would mean the
    /// leaderboard punishes exactly the forgiveness mechanic the rest of the app promises the user
    /// it won't). Mirrors `SquadManager.dailyRingProgress`'s identical event-kind set.
    ///
    /// Only `verified`/`ts` go into the `#Predicate` (matching `SquadManager.dailyRingProgress`'s
    /// and `LockEngineManager.isGoalVerified`'s documented tradeoff: this session has no
    /// Mac/Swift toolchain to compile-verify how `#Predicate` handles optional-relationship
    /// chaining or enum equality on this SDK version); `kind` and the goal-type filter run in
    /// plain Swift after the fetch. No `user` filter is applied — this device's local store only
    /// ever holds the signed-in user's own `GoalEvent` rows (`Models/User.swift`'s documented
    /// single-user-graph assumption), the same reasoning `SquadManager.dailyRingProgress` relies
    /// on for its own local-user computation.
    private func fetchVerifiedWorkoutGymEvents(from windowStart: Date, to windowEndExclusive: Date) throws -> [GoalEvent] {
        let events = try context.fetch(
            FetchDescriptor<GoalEvent>(
                predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= windowStart && $0.ts < windowEndExclusive }
            )
        )
        return events.filter { event in
            guard event.kind == .complete || event.kind == .planB || event.kind == .freeze else { return false }
            return event.goal?.type == .workoutGym
        }
    }

    /// Local-calendar-day key — identical implementation to
    /// `AdaptiveGoalEngine.dayKey(for:)`/`Calendar.current`, so a day boundary here always means
    /// the same thing it means everywhere else trailing-day consistency gets computed in `Core`.
    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - Opt-in persistence (App Group UserDefaults)

    /// Deliberately reads/writes the App Group `UserDefaults` suite directly by its identifier
    /// (`AppGroup.identifier`, `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`) rather
    /// than adding a key to `Core/Sources/Core/Store/SharedDefaults.swift` — that file is owned by
    /// a different session, and per-feature opt-in state doesn't fit its existing flat "one value
    /// per key, owned by the one engine that writes it" shape as a `Codable` blob anyway. Exactly
    /// `SquadManager.SquadFreezeState`'s identical documented reasoning, applied here. Still the
    /// same durable, cross-process App Group store `SharedDefaults` itself wraps (spec §11:
    /// "shared UserDefaults live here") — a Gym Home Turf widget/extension surface could read this
    /// same key directly if one is ever built, without going through this actor.
    private var optInDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private static let optInDefaultsKey = "com.zano.app.social.gymLeaderboard.optIn"

    private func loadOptIn() -> GymLeaderboardOptIn? {
        guard let data = optInDefaults.data(forKey: Self.optInDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(GymLeaderboardOptIn.self, from: data)
    }

    private func saveOptIn(_ state: GymLeaderboardOptIn) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        optInDefaults.set(data, forKey: Self.optInDefaultsKey)
    }

    // MARK: - Sync

    private func enqueueSync<Payload: Encodable & Sendable>(entityName: String, entityID: UUID, payload: Payload) async throws {
        try await SyncEngine.shared.enqueue(entityName: entityName, entityID: entityID, payload: payload)
    }
}

// MARK: - Sync payloads

/// The only fact about Gym Home Turf this device ever pushes outbound — see
/// `GymLeaderboardBackend`'s doc comment for why `consistency` itself is never part of this
/// payload.
private struct GymLeaderboardOptInSyncPayload: Codable, Sendable {
    let userID: UUID
    let optedIn: Bool
    let handle: String?
}
