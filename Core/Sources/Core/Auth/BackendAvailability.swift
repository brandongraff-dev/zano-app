// BackendAvailability.swift
// Core / Auth
//
// Session 34 (docs/spec.md §11 "Auth (Sign in with Apple)", §5.23 Family Link, §5.31 Household, §5.7 Squads).
// The single source of truth for "can this build talk to Supabase right now?":
//
//   * `BackendAvailability.isConfigured` — the build carries a Supabase project URL and anon key
//     (Info.plist `SUPABASE_URL` / `SUPABASE_ANON_KEY`, fed from build settings; see project.yml).
//   * `AccountStatus.shared.isSignedIn` — a Supabase session (from Sign in with Apple) exists.
//   * `isLive` — both. Every backend-only feature (Household, Family Link, Squad) keys off this, so with
//     no keys in the build nothing backend-dependent is ever visible (App Review 2.1).
//
// `AccountStatus` is `@MainActor @Observable` so a SwiftUI view that reads it (directly, or through
// `HouseholdAvailability.isLive` / `FamilyLinkAvailability.isLive`) re-renders the moment someone signs in
// or out. `SupabaseAuthSession` (an actor) is the only writer.

import Foundation
import Observation

/// Build-level availability. Pure and nonisolated: the configuration is read once from the main bundle.
public enum BackendAvailability {
    /// The project URL + anon key from Info.plist, or `nil` when the build has none (the default).
    public static let configuration: MealVisionConfiguration? = MealVisionConfiguration.fromMainBundle()

    /// `true` when the build carries a Supabase URL and anon key.
    public static var isConfigured: Bool { configuration != nil }

    /// The rule every backend feature uses: configured AND signed in. Pure, so it is unit tested.
    public static func isLive(configured: Bool, signedIn: Bool) -> Bool {
        configured && signedIn
    }
}

/// The signed-in state the UI observes. Starts from whatever session the Keychain holds (so a returning
/// user is signed in from the first frame) and is updated by `SupabaseAuthSession` on every change.
@MainActor
@Observable
public final class AccountStatus {
    public static let shared = AccountStatus()

    /// `false` whenever the build has no backend, whatever the Keychain holds.
    public let isConfigured: Bool
    public private(set) var isSignedIn: Bool
    /// The Apple-provided email (often a private relay address), when Supabase returned one.
    public private(set) var email: String?

    init(
        isConfigured: Bool = BackendAvailability.isConfigured,
        storedSession: SupabaseSession? = nil,
        loadFromKeychain: Bool = true
    ) {
        self.isConfigured = isConfigured
        var session = storedSession
        if session == nil, isConfigured, loadFromKeychain {
            session = KeychainSessionStore.standard.load()
        }
        self.isSignedIn = isConfigured && session != nil
        self.email = isConfigured ? session?.email : nil
    }

    /// Configured and signed in: Household, Family Link (and Squad, once its server side exists) show.
    public var isLive: Bool {
        BackendAvailability.isLive(configured: isConfigured, signedIn: isSignedIn)
    }

    /// Called by `SupabaseAuthSession` only.
    func update(session: SupabaseSession?) {
        isSignedIn = isConfigured && session != nil
        email = isConfigured ? session?.email : nil
    }
}
