// SquadAvailability.swift
// Core / Social
//
// Session 34 (docs/spec.md §5.7 Squads & Duels). Whether Squad is shown anywhere. It needs the backend and a
// signed-in person like Household, AND a server side that does not exist yet: nothing implements
// `SquadDirectory` (resolving someone else's invite code) or `SquadRingSource` (squadmates' rings), and the
// `sync` Edge Function deliberately refuses squad rows (`SERVER_OWNED_ENTITY_NAMES`). Showing Squad on
// sign-in alone would put invite codes that can never resolve in front of App Review (2.1), so
// `hasServerSupport` holds it back until those pieces are built.

import Foundation

public enum SquadAvailability {
    /// Flip to `true` in the session that builds the squad directory / ring endpoints and their clients.
    public static let hasServerSupport = false

    /// Pure rule, unit tested.
    public static func shouldShow(configured: Bool, signedIn: Bool, serverSupport: Bool) -> Bool {
        serverSupport && BackendAvailability.isLive(configured: configured, signedIn: signedIn)
    }

    @MainActor public static var isLive: Bool {
        let status = AccountStatus.shared
        return shouldShow(configured: status.isConfigured, signedIn: status.isSignedIn, serverSupport: hasServerSupport)
    }
}
