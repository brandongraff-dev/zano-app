// BackendConnections.swift
// Core / Auth
//
// Session 34. The one place that hands the signed-in session to every Supabase client, so adding the
// project URL + anon key to the build is the only step needed to switch the backend features on
// (docs/launch/supabase-setup.md). With no keys in the build both calls return immediately and nothing
// talks to the network.
//
// Clients wired here: `SyncEngine` (via `SupabaseSyncBackend`), `MealVisionClient`, `HouseholdClient`,
// `FamilyLinkClient`, `StravaClient` (session 40). NOT wired, because no server side exists for them yet (no Edge Function or RPC):
// `ReferralBackend`, `SquadDirectory` / `SquadRingSource`, `GymLeaderboardBackend`, `MealPrepVisionBackend`.
// Those features stay hidden; see docs/sessions/34-apple-sign-in.md.

import Foundation
import os

public enum BackendConnections {
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "BackendConnections")

    /// Call once at launch, AFTER `SyncEngine.shared.configure(modelContainer:)` (which resets its backend).
    /// Safe with no keys: does nothing.
    public static func connect(session: SupabaseAuthSession = .shared) async {
        guard let configuration = BackendAvailability.configuration else { return }
        let functionsBaseURL = configuration.projectURL.appendingPathComponent("functions/v1")
        await SyncEngine.shared.setBackend(
            SupabaseSyncBackend(
                functionsBaseURL: functionsBaseURL,
                anonKey: configuration.anonKey,
                tokenProvider: session
            )
        )
        await MealVisionClient.shared.configure(configuration: configuration, tokenProvider: session)
        await HouseholdClient.shared.configure(configuration: configuration, tokenProvider: session)
        await FamilyLinkClient.shared.configure(configuration: configuration, tokenProvider: session)
        await StravaClient.shared.configure(session: session, configuration: configuration)
    }

    /// Pushes the outbox and pulls server changes (docs/spec.md §11: "Sync outbox pushes to Supabase when
    /// online... app pulls on launch"). Best effort and never throws: unlock never waits on this. A no-op
    /// when the build has no backend or nobody is signed in.
    public static func syncIfSignedIn(session: SupabaseAuthSession = .shared) async {
        guard BackendAvailability.isConfigured, await session.isSignedIn else { return }
        do {
            let pushed = try await SyncEngine.shared.flush()
            if pushed > 0 { logger.info("Sync pushed \(pushed, privacy: .public) events.") }
        } catch {
            logger.notice("Sync push failed (will retry next time): \(String(describing: error), privacy: .public)")
        }
        await SyncEngine.shared.pullAndMerge()
    }
}
