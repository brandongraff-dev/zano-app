// Core/Sources/Core/Social/ReferralManager.swift
//
// docs/spec.md §4 v2 Feature Spec ("Referral: invite a friend → both get a streak freeze") and
// §13 Data Model (`users.referral_code`, `users.referred_by`).
//
// Ownership split — forced by this codebase's own already-written architecture, not a choice
// made in this file:
//   - `backend/supabase/functions/sync/index.ts` (owned by Session 7, `feat/backend`)
//     deliberately excludes `referral_code`/`referred_by` from the generic outbox's syncable
//     `user` columns — see that file's `user` entity comment: "Only user-editable preferences...
//     referral_code/referred_by are never client-writable through the outbox." That's correct,
//     not an oversight: this device never has the *referrer's* row locally
//     (`Models/User.swift`'s doc comment — "local-first storage only ever holds the signed-in
//     user's own graph"), and Postgres RLS (`user_id = auth.uid()`) would reject a client write
//     to someone else's `streaks` row even if this file tried. Crediting the referrer's freeze
//     can only happen with a service-role write on the server, after the server itself has
//     validated the code — never from this device.
//   - So this file owns exactly the client-side half of §4's loop: generating/persisting *this*
//     device's own referral code, redeeming a friend's code through a dedicated backend call
//     (`ReferralBackend` — the same protocol-seam pattern `Sync/SyncEngine.swift`'s `SyncBackend`
//     already established for this exact "no real network reachable from this session" gap:
//     define the shape now, `configure`/`setBackend` wires in a real implementation later without
//     any other call site changing), and crediting *this* device's own streak freeze once the
//     server confirms redemption. See `ReferralBackend`'s doc comment and this task's
//     `knownIssues` for the Edge Function that still needs to exist server-side to actually
//     implement this — that is `feat/backend` work, not this file's.

import Foundation
import SwiftData
import os

// MARK: - Code alphabet

/// Characters used for generated referral codes: uppercase alphanumerics with the usual
/// visually-ambiguous set removed (`0`/`O`, `1`/`I`/`L`) so a code read aloud, hand-typed, or
/// shown on a Share Card (docs/spec.md §5.14) doesn't get miskeyed.
private let referralCodeAlphabet: [Character] = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
private let referralCodeLength = 7

// MARK: - Errors

/// Errors `ReferralManager` throws itself, as opposed to errors bubbled up from SwiftData or a
/// `ReferralBackend`. Plain, developer-facing diagnostics (mirroring `LockEngineError`'s
/// documented convention) — not routed through `Core/Sources/Core/Copy`; whatever user-facing
/// message a view chooses for one of these belongs there, not here.
public enum ReferralManagerError: Error, Sendable, Equatable, LocalizedError {
    /// No local `User` row exists yet.
    case noSignedInUser
    /// `redeem(code:)` was called before a `ReferralBackend` was configured (`setBackend(_:)`) —
    /// expected before Session 7 (`feat/backend`) lands, mirroring `SyncEngineError
    /// .backendUnavailable`.
    case backendUnavailable
    /// `code` doesn't match the generated-code shape (`referralCodeLength` characters, all drawn
    /// from `referralCodeAlphabet`) — rejected before ever reaching the network.
    case invalidCodeFormat(String)
    /// `code` is this same user's own referral code.
    case cannotRedeemOwnCode
    /// `User.referredBy` is already set — a user may only redeem one referral, ever (matches
    /// `users.referred_by`'s single-FK shape in spec §13; there is no list of redemptions to
    /// append to).
    case alreadyRedeemed

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser:
            "No local User row exists yet."
        case .backendUnavailable:
            "No ReferralBackend configured — cannot validate/redeem a referral code yet."
        case .invalidCodeFormat(let code):
            "\"\(code)\" is not a validly formatted referral code."
        case .cannotRedeemOwnCode:
            "You can't redeem your own referral code."
        case .alreadyRedeemed:
            "This account has already redeemed a referral code."
        }
    }
}

// MARK: - Backend seam (Session 7, `feat/backend`, implements this for real)

/// What actually happened on the server for a redeemed code. `referrerUserID` lets the caller
/// (e.g. onboarding, or a Settings "you were referred by ✓" row) show who gets credit;
/// `refereeFreezeGranted`/`referrerFreezeGranted` report whether each side's streak freeze
/// (docs/spec.md §4 v2) was actually applied, in case a future server-side edge case (e.g. a
/// freeze cap) grants one side but not the other.
public struct ReferralRedemptionResult: Sendable, Equatable {
    public let referrerUserID: UUID
    public let refereeFreezeGranted: Bool
    public let referrerFreezeGranted: Bool

    public init(referrerUserID: UUID, refereeFreezeGranted: Bool, referrerFreezeGranted: Bool) {
        self.referrerUserID = referrerUserID
        self.refereeFreezeGranted = refereeFreezeGranted
        self.referrerFreezeGranted = referrerFreezeGranted
    }
}

/// The network transport `ReferralManager` validates/redeems referral codes through. Exactly the
/// shape Session 7 needs to drop a real Supabase-backed implementation (an Edge Function call)
/// into without touching `ReferralManager` itself: construct one, call
/// `ReferralManager.shared.setBackend(_:)` once at launch, and `redeem(code:)` starts working.
/// `Sendable` so it can be passed into `setBackend` from any isolation domain, matching
/// `SyncBackend`'s exact convention.
public protocol ReferralBackend: Sendable {
    /// Registers `code` as `forUserID`'s referral code server-side. Implementations should treat
    /// repeat calls with the same `(code, forUserID)` pair as a no-op (idempotent upsert), and
    /// should throw if `code` already belongs to a *different* user (a random-generation
    /// collision — astronomically unlikely at 32^7 combinations, but `ReferralManager` should be
    /// able to regenerate and retry rather than silently colliding two users onto one code).
    func register(code: String, forUserID: UUID) async throws

    /// Validates and redeems `code` on behalf of `refereeUserID`. Server-side responsibilities —
    /// deliberately never this file's, per the header comment: confirm `code` belongs to a real,
    /// different user; confirm `refereeUserID` hasn't already redeemed a code
    /// (`users.referred_by IS NULL`); set `users.referred_by = <referrer id>`; and credit **both**
    /// the referrer's and the referee's `streaks.freezes_left` by 1 (docs/spec.md §4 v2) inside
    /// one server-side transaction, using the service-role client the way
    /// `backend/supabase/functions/sync/index.ts` already does for every other cross-row write.
    func redeem(code: String, refereeUserID: UUID) async throws -> ReferralRedemptionResult
}

// MARK: - ReferralManager

/// `@MainActor`, matching this codebase's established choice for every other `Core` engine that
/// owns a `ModelContext` against the shared App Group store (`LockEngineManager`,
/// `FocusSessionVerifier`, `NudgeSender`) — see those files' doc comments for the same reasoning.
@MainActor
public final class ReferralManager {
    public static let shared = ReferralManager()

    private let modelContainer: ModelContainer
    private let context: ModelContext
    private var backend: ReferralBackend?
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "ReferralManager")

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance (an
    /// in-memory container, a fake `ReferralBackend`); every real call site uses `.shared`.
    init(modelContainer: ModelContainer = .appGroup, backend: ReferralBackend? = nil) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        self.backend = backend
    }

    /// The seam Session 7 (`feat/backend`) uses to go from "no networking" to a real
    /// Supabase-backed implementation, mirroring `SyncEngine.setBackend(_:)` exactly — same name,
    /// same "call once at launch" contract.
    public func setBackend(_ backend: ReferralBackend) {
        self.backend = backend
    }

    // MARK: - Generate

    /// This device's own referral code: returns the existing `User.referralCode` if one is
    /// already set, otherwise generates one, persists it locally, and (best-effort) registers it
    /// with the backend so a friend can redeem it right away.
    ///
    /// - Throws: ``ReferralManagerError/noSignedInUser``, or whatever `ModelContext.save()`
    ///   throws. Backend registration failure is logged, not thrown — see the inline comment
    ///   below for why that's the right default.
    @discardableResult
    public func myReferralCode() throws -> String {
        let user = try fetchCurrentUser()
        if let existing = user.referralCode, !existing.isEmpty {
            return existing
        }

        let code = Self.generateCode()
        user.referralCode = code
        try context.save()

        registerWithBackendBestEffort(code: code, userID: user.id)
        return code
    }

    /// Generates a random, human-typeable code from `referralCodeAlphabet`. Not guaranteed
    /// globally unique on its own — `ReferralBackend.register` is the source of truth for
    /// uniqueness (matching `users.referral_code`'s `unique` constraint, docs/spec.md §13); a
    /// collision there is expected to be vanishingly rare (32^7 ≈ 34 billion combinations) and is
    /// the backend's job to reject, not this function's to guarantee up front.
    public static func generateCode(length: Int = referralCodeLength) -> String {
        String((0..<length).compactMap { _ in referralCodeAlphabet.randomElement() })
    }

    /// Fire-and-forget backend registration, kept out of `myReferralCode()`'s main `throws` path
    /// on purpose: the code is already durable locally the moment this is called (spec §5.1-style
    /// "local-first, instant" bias — CLAUDE.md "Local-first data; Supabase sync"), and a
    /// registration failure here is retryable (the next `myReferralCode()` call, or a future
    /// launch-time sync pass, can retry it) rather than something that should block whatever UI
    /// flow asked for the code (e.g. a Share Card render, spec §5.14) from proceeding.
    private func registerWithBackendBestEffort(code: String, userID: UUID) {
        guard let backend else {
            logger.notice("No ReferralBackend configured; referral code \(code, privacy: .public) generated locally only.")
            return
        }
        Task {
            do {
                try await backend.register(code: code, forUserID: userID)
            } catch {
                // Explicit `self.` — required here (not elsewhere in this file) because this
                // closure is the `@escaping` `operation` of an unstructured `Task`, so Swift
                // requires the capture to be spelled out rather than implicit.
                self.logger.error(
                    "Referral code registration failed for \(userID.uuidString, privacy: .public): \(String(describing: error), privacy: .public). Code is saved locally; a friend can't redeem it until this reaches the backend."
                )
            }
        }
    }

    // MARK: - Redeem

    /// Redeems a friend's referral `code` on behalf of the local signed-in user. Both sides'
    /// streak freeze (docs/spec.md §4 v2 — "invite a friend → both get a streak freeze") come out
    /// of this one call: the referrer's is credited server-side inside `ReferralBackend.redeem`
    /// (see its doc comment — this device has no local access to the referrer's row, and RLS
    /// would reject a direct write even if it tried); the referee's — the local user's — is
    /// credited right here, locally, once the server confirms.
    ///
    /// - Throws: a `ReferralManagerError` for every client-checkable precondition (bad format, no
    ///   signed-in user, already redeemed, own code, no backend configured yet), or whatever
    ///   `ReferralBackend.redeem` throws for anything only the server can determine (code doesn't
    ///   exist, belongs to no one, etc.).
    @discardableResult
    public func redeem(code rawCode: String) async throws -> ReferralRedemptionResult {
        let code = Self.normalize(rawCode)
        guard Self.isValidFormat(code) else {
            throw ReferralManagerError.invalidCodeFormat(rawCode)
        }

        let user = try fetchCurrentUser()
        guard user.referredBy == nil else {
            throw ReferralManagerError.alreadyRedeemed
        }
        guard user.referralCode != code else {
            throw ReferralManagerError.cannotRedeemOwnCode
        }
        guard let backend else {
            throw ReferralManagerError.backendUnavailable
        }

        let result = try await backend.redeem(code: code, refereeUserID: user.id)

        user.referredBy = result.referrerUserID
        try context.save()

        if result.refereeFreezeGranted {
            try grantLocalStreakFreeze(to: user.id)
        }

        logger.notice(
            "Redeemed referral code for user \(user.id.uuidString, privacy: .public); referrer=\(result.referrerUserID.uuidString, privacy: .public), refereeFreeze=\(result.refereeFreezeGranted, privacy: .public), referrerFreeze=\(result.referrerFreezeGranted, privacy: .public)."
        )
        return result
    }

    // MARK: - Validation

    private static func isValidFormat(_ code: String) -> Bool {
        code.count == referralCodeLength && code.allSatisfy { referralCodeAlphabet.contains($0) }
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - SwiftData

    /// This device's local store holds exactly one `User` row (see `Models/User.swift`'s doc
    /// comment), so the first (only) one is always the right one.
    private func fetchCurrentUser() throws -> User {
        var descriptor = FetchDescriptor<User>()
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else {
            throw ReferralManagerError.noSignedInUser
        }
        return user
    }

    /// Credits this device's own local `Streak.freezesLeft` by 1 (docs/spec.md §4 v2; §8 "Streaks
    /// have forgiveness. Freezes, Never Miss Twice, Plan B, Comeback mode.").
    ///
    /// TODO(cross-module integration — Retention session, `Core/Sources/Core/Retention/
    /// StreakEngine.swift`; called out explicitly in this task): this task's fixed `StreakEngine`
    /// contract only exposes `recordEarnedUnlock` / `recordMiss` / `useFreeze` / `currentStreak`
    /// — none of which *grant* a freeze — while `Models/Streak.swift`'s own doc comment says
    /// `StreakEngine` is "the sole owner of mutating it." Both are true only once `StreakEngine`
    /// grows a `grantFreeze`-shaped method; until it does, direct read-modify-write here (the same
    /// pattern every other engine in `Core` already uses for its own tables, e.g.
    /// `LockEngineManager` on `LockSession`) is the only way to actually fulfill §4 v2's "both get
    /// a streak freeze" today. Swap the body of this method for a call to
    /// `StreakEngine.shared.grantFreeze(on:)` (or equivalent) the moment that method exists — the
    /// call site above (`redeem(code:)`) does not need to change, only this one private method.
    private func grantLocalStreakFreeze(to userID: UUID) throws {
        var descriptor = FetchDescriptor<Streak>(predicate: #Predicate { $0.userID == userID })
        descriptor.fetchLimit = 1
        let streak: Streak
        if let existing = try context.fetch(descriptor).first {
            streak = existing
        } else {
            streak = Streak(userID: userID)
            context.insert(streak)
        }
        streak.freezesLeft += 1
        try context.save()
    }
}
