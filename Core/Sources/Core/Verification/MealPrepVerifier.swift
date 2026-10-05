// Core/Sources/Core/Verification/MealPrepVerifier.swift
//
// docs/spec.md §3 "Goal Catalog & Verification" — "Meal prep (weekly)" row (Tier B):
//   How it's verified: "Photo of prepped containers, vision model confirms 'multiple meal
//   containers'"
//   Anti-cheat: "Weekly only"
// docs/spec.md §9.5 "Meal Vision" describes the sibling photo-vision pipeline this file's own
// vision call mirrors (strict JSON prompt, private bucket photo path, vision LLM provider
// contract) — see backend/supabase/functions/meal-vision/index.ts, read in full for this task.
//
// GoalType.mealPrep (`Models/Goal.swift`) already exists and is reused exactly as-is — no
// parallel case introduced here, per this task's own instruction.
//
// ---------------------------------------------------------------------------------------
// Ownership / design decisions (this task's own "your call, document it" instruction)
// ---------------------------------------------------------------------------------------
//
// 1. Photo transport: `verifyMealPrepPhoto`'s `photoPath` argument is, by contract, an object path
//    already uploaded to the private "meal-photos" Supabase Storage bucket
//    (`<user_id>/<file>`, `backend/supabase/migrations/0002_auth_storage.sql`) — the exact same
//    convention `backend/supabase/functions/meal-vision/index.ts`'s own `photoPath` and
//    `Models/Meal.swift`'s `photoPath` doc comment ("Sync... owns uploading it to Supabase
//    Storage") already establish. No new bucket/migration is introduced here; meal-prep container
//    photos are expected to reuse "meal-photos" — that bucket's RLS (0002_auth_storage.sql)
//    already accepts any object under the caller's own `auth.uid()` folder regardless of what the
//    photo is *of*, so there is nothing to add there for this to work.
//
// 2. Vision endpoint: this task explicitly offers a choice ("call the same meal-vision function
//    with a mode parameter, or its own tiny edge function if that is cleaner"). Decision: neither
//    is built *in this task*. `backend/supabase/functions/meal-vision/index.ts` is not in this
//    task's owned-file list, and its current system prompt/response shape (`{items,
//    total_protein, notes}`) answers a different question (how much protein?) than this row needs
//    (how many containers?) — bolting a `mode` branch onto it, or standing up a second Edge
//    Function, are both real server-side changes with no owned file for them here. Editing a file
//    two independently-scoped tasks both touch, or guessing a `mode` parameter shape that file
//    doesn't have yet, is exactly the kind of cross-agent shape mismatch this wave was told to
//    avoid — so instead this file defines the seam only: `MealPrepVisionBackend`, mirroring the
//    exact pattern `Sync/SyncEngine.swift`'s `SyncBackend` and `Social/ReferralManager.swift`'s
//    `ReferralBackend` already established in this codebase for "the real networking doesn't exist
//    yet, here's the shape a future session drops a real implementation into" — `setBackend(_:)`,
//    called once at launch, exactly like those two. See `MealPrepVisionBackend`'s doc comment for
//    the recommended real implementation (extending meal-vision with a mode branch, since the
//    bucket/RLS/provider scaffolding already exists for it) and the alternative (a standalone
//    function) this file deliberately leaves open rather than picking blind.
//
// 3. Weekly cap: the *only* anti-cheat spec §3 lists for this row is "Weekly only" — no photo
//    dedupe, no tap-rate limit (those belong to other rows). Enforced here via
//    `Calendar.current.dateInterval(of: .weekOfYear:)` against this goal's own already-verified
//    `.verify` `GoalEvent`s — the same week-boundary primitive `Retention/GhostMode.swift` and
//    `Social/SquadManager.swift`/`Retention/StreakEngine.swift` already use elsewhere in `Core` for
//    "this calendar week" — checked *before* calling the vision backend, so an already-used week
//    never spends a vision call.
//
// ---------------------------------------------------------------------------------------
// Concurrency / shape
// ---------------------------------------------------------------------------------------
// `@MainActor final class` with an injectable `modelContainer` (defaults to `.appGroup`) and a
// `.shared` singleton — matching `ReferralManager`/`FocusSessionVerifier`'s own declared
// convention exactly (same reasoning: every realistic call site — a Fuel/meal-prep photo screen, a
// future `LogMealPrepIntent` — is already on the main actor or happy to hop onto it).
//
// `#Predicate` caution: like `LockEngine/LockEngineManager.swift`'s `isGoalVerified` and
// `Verification/BedtimeGateManager.swift`'s own documented choice (deliberately *not*
// `Intents/IntentSupport.swift`'s more optimistic one, which compares `event.goal?.id == goalID`
// directly inside `#Predicate`) — this session has no Mac/Swift toolchain to compile-verify how
// `#Predicate` handles optional-relationship chaining on the target SDK, so only unambiguous
// `Date`/`Bool` fields go inside the macro here; the goal-id comparison is filtered in plain Swift
// after the fetch, matching this same directory's existing, more conservative files.

import Foundation
import SwiftData
import os

// MARK: - Vision result

/// The strict result this file expects back from whatever vision call `MealPrepVisionBackend`
/// wraps — deliberately small: spec §3's own bar for this row is binary ("vision model confirms
/// 'multiple meal containers'"), not a full item breakdown like `meal-vision`'s protein estimate.
public struct MealPrepVisionResult: Sendable, Equatable, Codable {
    /// The vision model's best-effort count of distinct meal containers visible in the photo.
    public let containersDetected: Int
    /// `true` once the vision model confirms "multiple meal containers" (spec §3) — the single
    /// signal `verifyMealPrep` gates a `GoalEvent` write on. A real implementation should set this
    /// once `containersDetected >= 2` at a high enough confidence to be worth trusting; the exact
    /// confidence bar is a future backend session's tuning call, not fixed here.
    public let confirmed: Bool
    /// The vision model's confidence in `containersDetected`/`confirmed`, `0...1`.
    public let confidence: Double
    /// At most one short, neutral sentence (mirrors `meal-vision`'s own `notes` field) — e.g. "only
    /// one container clearly visible" — surfaced back to the caller so a rejected photo isn't a
    /// silent no.
    public let notes: String

    public init(containersDetected: Int, confirmed: Bool, confidence: Double, notes: String = "") {
        self.containersDetected = containersDetected
        self.confirmed = confirmed
        self.confidence = confidence
        self.notes = notes
    }
}

// MARK: - Backend seam (a future backend session implements this for real — see header, decision 2)

/// The network transport `MealPrepVerifier` runs its photo check through. Exactly the shape a
/// future backend session needs to drop a real implementation into without touching
/// `MealPrepVerifier` itself — construct one, call `MealPrepVerifier.shared.setBackend(_:)` once at
/// launch, and `verifyMealPrep` starts working. `Sendable` so it can be passed into `setBackend`
/// from any isolation domain, matching `SyncBackend`/`ReferralBackend`'s exact convention.
///
/// Recommended real implementation (this file's header, decision 2): call
/// `backend/supabase/functions/meal-vision/index.ts` with a `photoPath` already uploaded to the
/// private "meal-photos" bucket, once that function gains a `mode: "meal_prep"` branch using a
/// system prompt asking specifically for a container count and a strict `{"containers_detected":
/// number, "confirmed": boolean, "confidence": number, "notes": string}` JSON response — the same
/// "strict JSON prompt, private bucket photo path, API key from `Deno.env` only" pattern
/// `meal-vision/index.ts` already follows for its own protein estimate, just answering a different
/// question and parsing a different response shape. A standalone Edge Function is the fallback if
/// a future session decides the two vision questions shouldn't share one endpoint; either way, no
/// call site of this protocol needs to change.
public protocol MealPrepVisionBackend: Sendable {
    /// Runs the "multiple meal containers" vision check on `photoPath` (an object path already
    /// uploaded under `userID`'s own folder in the private `meal-photos` bucket — see this file's
    /// header, decision 1). Should throw for transport/auth/upstream failures; a photo that simply
    /// doesn't show multiple containers is not an error — it's `MealPrepVisionResult.confirmed ==
    /// false`, exactly like `meal-vision`'s own "not every photo has identifiable food" is not an
    /// error there either.
    func verifyMealPrepPhoto(photoPath: String, userID: UUID) async throws -> MealPrepVisionResult
}

// MARK: - Errors

/// Errors `MealPrepVerifier` throws itself, as opposed to errors bubbled up from SwiftData or a
/// `MealPrepVisionBackend`. Plain, developer-facing diagnostics — mirroring
/// `ReferralManagerError`/`FocusSessionVerifierError`'s documented convention — not routed through
/// `Core/Sources/Core/Copy`; whatever user-facing message a view chooses for one of these belongs
/// there, not here.
public enum MealPrepVerifierError: Error, Sendable, Equatable, LocalizedError {
    /// `photoPath` was empty/whitespace-only — never worth a round trip to the vision backend.
    case emptyPhotoPath
    /// No local `Goal` row exists for the given id.
    case goalNotFound(UUID)
    /// The `Goal` found for `goalID` is not a `.mealPrep` goal — this verifier only ever writes
    /// `GoalType.mealPrep` events (this task's own instruction: reuse the exact existing case,
    /// never invent a parallel one), so calling it against, say, a `.protein` goal id is a caller
    /// bug, not something to silently reinterpret.
    case wrongGoalType(UUID, GoalType)
    /// `goal.user` was `nil` — there is no local `User` to scope the vision call's storage path to
    /// (mirrors `ReferralManagerError.noSignedInUser`'s same underlying "no local user row yet"
    /// precondition failure).
    case userNotFoundForGoal(UUID)
    /// This goal already has a verified meal-prep completion in the current calendar week (spec
    /// §3: "Weekly only"). `nextEligible` is the start of next week's own `.weekOfYear` interval.
    case alreadyVerifiedThisWeek(nextEligible: Date)
    /// `verifyMealPrep` was called before `setBackend(_:)` — expected until a backend session wires
    /// in a real `MealPrepVisionBackend` (this file's header, decision 2), mirroring
    /// `ReferralManagerError.backendUnavailable`/`SyncEngineError.backendUnavailable`.
    case backendUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyPhotoPath:
            "No photo path was given to verify."
        case .goalNotFound(let goalID):
            "No Goal with id \(goalID) exists locally."
        case .wrongGoalType(let goalID, let type):
            "Goal \(goalID) is type \(type.rawValue), not mealPrep — MealPrepVerifier only verifies mealPrep goals."
        case .userNotFoundForGoal(let goalID):
            "Goal \(goalID) has no associated User — cannot scope a photo verification call without one."
        case .alreadyVerifiedThisWeek(let nextEligible):
            "Meal prep was already verified this week. Next eligible: \(nextEligible)."
        case .backendUnavailable:
            "No MealPrepVisionBackend configured — cannot run the photo check yet."
        }
    }
}

// MARK: - Verification result

/// What `verifyMealPrep` hands back after a photo check — richer than a bare `Bool` (unlike
/// `GymVerifier.isVerified`/`FocusSessionVerifier.endSession`) because, unlike those Tier A goals,
/// a rejected Tier B photo needs to tell the user *why* ("only one container visible") so they can
/// retake it, matching spec §3's own verification philosophy ("Make cheating annoying, not
/// impossible") — silently returning `false` would just look broken.
public struct MealPrepVerificationResult: Sendable, Equatable {
    /// `true` only when a `GoalEvent` was actually written (see `verifyMealPrep`'s doc comment).
    public let confirmed: Bool
    public let containersDetected: Int
    public let confidence: Double
    public let notes: String
}

// MARK: - MealPrepVerifier

/// Verifies the Meal prep (weekly) goal (docs/spec.md §3, Tier B) by running a submitted photo
/// through `MealPrepVisionBackend`'s "multiple meal containers" check and, only on confirmation,
/// writing a weekly `GoalEvent` (`kind: .verify`, `source: .photo`, `verified: true`) against the
/// given `GoalType.mealPrep` goal — this task's own fixed instruction.
@MainActor
public final class MealPrepVerifier {
    public static let shared = MealPrepVerifier()

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private var backend: MealPrepVisionBackend?
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "MealPrepVerifier")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance (an
    /// in-memory container, a fake `MealPrepVisionBackend`); every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup, backend: MealPrepVisionBackend? = nil) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.backend = backend
    }

    /// The seam a future backend session uses to go from "no networking" to a real implementation,
    /// mirroring `SyncEngine.setBackend(_:)`/`ReferralManager.setBackend(_:)` exactly — same name,
    /// same "call once at launch" contract.
    public func setBackend(_ backend: MealPrepVisionBackend) {
        self.backend = backend
    }

    /// `true` once `setBackend(_:)` has been called. The meal-prep photo sheet
    /// (`App/ZANO/Features/Fuel/MealPhoto/MealPrepCaptureSheet.swift`) reads this to choose
    /// between the vision-checked path (``verifyMealPrep(goalID:photoPath:at:)``) and the honor
    /// tier (``logHonorTier(goalID:at:)``) *before* uploading anything.
    public var hasVisionBackend: Bool { backend != nil }

    // MARK: - Honor tier (no vision backend yet)

    /// Logs this week's meal prep on the user's honor, for when no `MealPrepVisionBackend` is
    /// configured (true today: `meal-vision` has no container-count mode yet, so nothing calls
    /// `setBackend(_:)`). Added 2026-09-25 for the meal-prep photo sheet, so a user who took the
    /// photo is never left with no way to log.
    ///
    /// Same weekly cap as the vision path (spec 3's only anti-cheat for this row: "weekly only"),
    /// same `GoalEvent` shape (`kind: .verify`, `source: .photo`, `verified: true` — so the lock
    /// engine counts it like any other honor-system goal), plus `meta.tier = "honor"` and
    /// `meta.visionChecked = false` so analytics/recaps can tell an honor log from a
    /// vision-confirmed one, and a later backend session can decide whether to treat them
    /// differently. No photo path is stored: nothing was uploaded.
    ///
    /// - Throws: `MealPrepVerifierError.goalNotFound` / `.wrongGoalType` /
    ///   `.alreadyVerifiedThisWeek`, or a SwiftData save error.
    public func logHonorTier(goalID: UUID, at now: Date = .now) async throws {
        guard let goal = try fetchGoal(id: goalID) else {
            throw MealPrepVerifierError.goalNotFound(goalID)
        }
        guard goal.type == .mealPrep else {
            throw MealPrepVerifierError.wrongGoalType(goalID, goal.type)
        }
        if let nextEligible = try nextEligibleDate(for: goal, at: now) {
            throw MealPrepVerifierError.alreadyVerifiedThisWeek(nextEligible: nextEligible)
        }

        let event = GoalEvent(
            ts: now,
            kind: .verify,
            value: nil,
            source: .photo,
            verified: true,
            meta: .object([
                "tier": .string("honor"),
                "visionChecked": .bool(false),
            ]),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        try context.save()
        await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
        logger.notice("Meal prep logged on honor tier for goal \(goalID.uuidString, privacy: .public) (no vision backend).")
    }

    // MARK: - Verify

    /// Runs the weekly meal-prep photo check for `goalID` and, on confirmation, logs it.
    ///
    /// - Parameters:
    ///   - goalID: A `Goal.id` whose `type == .mealPrep`. Must already exist locally.
    ///   - photoPath: The photo's object path already uploaded to the private `meal-photos`
    ///     bucket, `<user_id>/<file>` (see this file's header, decision 1). Uploading it there is
    ///     the caller's job — the same division of responsibility `Models/Meal.swift`'s own
    ///     `photoPath` doc comment already documents for protein photos (Sync owns the upload;
    ///     verification only ever consumes an already-uploaded path).
    ///   - now: Injectable for tests; defaults to `.now`.
    /// - Returns: A `MealPrepVerificationResult`. `confirmed == false` is not an error — it means
    ///   the photo didn't show multiple containers; the caller can let the user retake it and call
    ///   this again (the weekly cap only trips once a confirmation actually succeeds).
    /// - Throws: `MealPrepVerifierError` for every client-checkable precondition (empty path, goal
    ///   not found, wrong goal type, no user, already verified this week, no backend configured),
    ///   or whatever `MealPrepVisionBackend.verifyMealPrepPhoto` throws for a transport/upstream
    ///   failure, or a SwiftData save error.
    @discardableResult
    public func verifyMealPrep(goalID: UUID, photoPath: String, at now: Date = .now) async throws -> MealPrepVerificationResult {
        let trimmedPath = photoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw MealPrepVerifierError.emptyPhotoPath
        }
        guard let goal = try fetchGoal(id: goalID) else {
            throw MealPrepVerifierError.goalNotFound(goalID)
        }
        guard goal.type == .mealPrep else {
            throw MealPrepVerifierError.wrongGoalType(goalID, goal.type)
        }
        guard let userID = goal.user?.id else {
            throw MealPrepVerifierError.userNotFoundForGoal(goalID)
        }
        if let nextEligible = try nextEligibleDate(for: goal, at: now) {
            throw MealPrepVerifierError.alreadyVerifiedThisWeek(nextEligible: nextEligible)
        }
        guard let backend else {
            throw MealPrepVerifierError.backendUnavailable
        }

        let vision = try await backend.verifyMealPrepPhoto(photoPath: trimmedPath, userID: userID)

        if vision.confirmed {
            try logVerification(goal: goal, photoPath: trimmedPath, vision: vision, at: now)
            await GoalCompletionCoordinator.shared.goalEventRecorded(goalID: goalID)
            logger.notice("Meal prep verified for goal \(goalID.uuidString, privacy: .public): \(vision.containersDetected, privacy: .public) containers, confidence \(vision.confidence, privacy: .public).")
        } else {
            logger.notice("Meal prep photo rejected for goal \(goalID.uuidString, privacy: .public): \(vision.notes, privacy: .public)")
        }

        return MealPrepVerificationResult(
            confirmed: vision.confirmed,
            containersDetected: vision.containersDetected,
            confidence: vision.confidence,
            notes: vision.notes
        )
    }

    /// `true` if `goalID` (a `.mealPrep` goal) still has an unused verification slot this calendar
    /// week — lets a UI gray out the "log meal prep" entry point *before* the user takes a photo,
    /// without spending a vision call just to discover the week is already used. Never throws;
    /// mirrors `FocusSessionVerifier`/`GymVerifier`'s own "a read-only verification-state check
    /// degrades to a safe default rather than propagate a SwiftData error" convention — `false`
    /// here means "don't know, or already used this week," not "definitely blocked forever."
    public func isEligibleThisWeek(goalID: UUID, at now: Date = .now) -> Bool {
        guard let goal = try? fetchGoal(id: goalID), goal.type == .mealPrep else { return false }
        return (try? nextEligibleDate(for: goal, at: now)) == nil
    }

    // MARK: - Weekly cap

    /// `nil` if `goal` has no verified `.verify` `GoalEvent` in `now`'s own calendar week yet
    /// (i.e. eligible right now); otherwise the start of *next* week, i.e. the earliest moment
    /// `verifyMealPrep` will accept another confirmation for this goal.
    ///
    /// Known race (flagged in this task's `knownIssues`, not fixed here — see that note for why):
    /// two overlapping `verifyMealPrep` calls for the same goal can both pass this check before
    /// either one's vision call returns and writes its event, since the `await` inside
    /// `verifyMealPrep` suspends this `@MainActor` class mid-method. A real double-submit guard
    /// (e.g. an in-flight-request lock keyed by `goalID`) is a reasonable follow-up, not built here
    /// to keep this task's scope to what spec §3 actually asks for ("weekly only").
    private func nextEligibleDate(for goal: Goal, at now: Date) throws -> Date? {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            // Unresolvable calendar week is vanishingly unlikely (`.weekOfYear` is defined for
            // every `Calendar`) — fail open rather than block a legitimate weekly check on a
            // calendar-math edge case this session can't reproduce without a device.
            return nil
        }

        let weekStart = week.start
        let weekEnd = week.end
        let goalID = goal.id
        let descriptor = FetchDescriptor<GoalEvent>(
            predicate: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= weekStart && $0.ts < weekEnd }
        )
        let events = try context.fetch(descriptor)
        let alreadyVerified = events.contains { $0.goal?.id == goalID && $0.kind == .verify }
        return alreadyVerified ? weekEnd : nil
    }

    // MARK: - Persistence

    private func fetchGoal(id: UUID) throws -> Goal? {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Writes the confirmed meal-prep `GoalEvent` (`kind: .verify`, `source: .photo`, `verified:
    /// true`) — this task's own fixed instruction. `value` holds `containersDetected` (mirrors
    /// `FocusSessionVerifier.logOutcome`'s own choice of putting the single most meaningful number
    /// on `value` rather than only inside `meta`, so aggregation code — `AdaptiveGoalEngine`, a
    /// recap — can read it without decoding `meta` first); the rest of the vision result lives in
    /// `meta`, following `GoalEvent.meta`'s own doc comment ("different goal types attach different
    /// metadata... a photo confidence score").
    private func logVerification(goal: Goal, photoPath: String, vision: MealPrepVisionResult, at now: Date) throws {
        let event = GoalEvent(
            ts: now,
            kind: .verify,
            value: Double(vision.containersDetected),
            source: .photo,
            verified: true,
            meta: .object([
                "photoPath": .string(photoPath),
                "containersDetected": .number(Double(vision.containersDetected)),
                "confidence": .number(vision.confidence),
                "notes": .string(vision.notes),
            ]),
            user: goal.user,
            goal: goal
        )
        context.insert(event)
        try context.save()
    }
}
