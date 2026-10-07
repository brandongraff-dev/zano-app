// SupabaseAuthSession.swift
// Core / Auth
//
// Session 34. The one owner of the signed-in Supabase session, and the concrete
// `SupabaseAuthTokenProviding` every backend client (sync, meal vision, Household, Family Link) was built to
// accept. An actor: sign-in, refresh, sign-out and delete can arrive from any task, and two requests that
// both find the token stale must share ONE refresh (Supabase rotates refresh tokens, so a second refresh
// with the same token would fail and sign the person out).
//
// Local-first is untouched: nothing that gates a lock waits on this. With no keys in the build,
// `configuration` is nil and every call throws `.notConfigured` without touching the network.

import Foundation
import os

public actor SupabaseAuthSession: SupabaseAuthTokenProviding {
    public static let shared = SupabaseAuthSession()

    private let client: SupabaseAuthClient?
    private let store: any SupabaseSessionStoring
    private let now: @Sendable () -> Date
    private let onChange: @Sendable (SupabaseSession?) async -> Void
    private var session: SupabaseSession?
    private var refreshTask: Task<SupabaseSession, any Error>?
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "SupabaseAuthSession")

    /// `internal` so `CoreTests` can inject a configuration, an in-memory store, a fake transport, a clock and
    /// a change observer; every real call site uses `.shared`.
    init(
        configuration: MealVisionConfiguration? = BackendAvailability.configuration,
        store: any SupabaseSessionStoring = KeychainSessionStore.standard,
        transport: SupabaseAuthClient.Transport? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable (SupabaseSession?) async -> Void = { session in
            await MainActor.run { AccountStatus.shared.update(session: session) }
        }
    ) {
        if let configuration {
            if let transport {
                self.client = SupabaseAuthClient(configuration: configuration, transport: transport)
            } else {
                self.client = SupabaseAuthClient(configuration: configuration)
            }
            self.session = store.load()
        } else {
            self.client = nil
            self.session = nil
        }
        self.store = store
        self.now = now
        self.onChange = onChange
    }

    // MARK: State

    public var isConfigured: Bool { client != nil }
    public var isSignedIn: Bool { client != nil && session != nil }
    public var email: String? { session?.email }

    // MARK: Sign in / out

    /// Exchanges an Apple identity token for a Supabase session and stores it. `rawNonce` is the value whose
    /// SHA-256 was put on the Apple request (`AppleSignInNonce`).
    public func signInWithApple(idToken: String, rawNonce: String) async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let newSession = try await client.signInWithApple(idToken: idToken, rawNonce: rawNonce, now: now())
        await apply(newSession)
    }

    /// Signs out on this device. Tries to revoke the session server-side too, but never fails because of it.
    public func signOut() async {
        if let client, let session {
            do {
                try await client.signOut(accessToken: session.accessToken)
            } catch {
                Self.logger.notice("Server sign-out failed (signed out locally anyway): \(String(describing: error), privacy: .public)")
            }
        }
        refreshTask?.cancel()
        refreshTask = nil
        await apply(nil)
    }

    /// Deletes the account server-side (the `delete-account` Edge Function removes every row and photo), then
    /// signs out locally. Throws, and keeps the session, if the server didn't confirm, so the person can retry.
    public func deleteAccount() async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let token = try await supabaseAccessToken()
        try await client.deleteAccount(accessToken: token)
        refreshTask?.cancel()
        refreshTask = nil
        await apply(nil)
    }

    // MARK: SupabaseAuthTokenProviding

    public func supabaseAccessToken() async throws -> String {
        guard client != nil else { throw SupabaseAuthError.notConfigured }
        guard let current = session else { throw SupabaseAuthError.notSignedIn }
        guard current.needsRefresh(now: now()) else { return current.accessToken }
        return try await refreshed(from: current).accessToken
    }

    public func hasSupabaseSession() async -> Bool {
        isSignedIn
    }

    // MARK: Refresh

    /// One refresh at a time: a caller arriving while one is running waits for the same result.
    private func refreshed(from current: SupabaseSession) async throws -> SupabaseSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let client else { throw SupabaseAuthError.notConfigured }
        let refreshToken = current.refreshToken
        let date = now()
        let task = Task { try await client.refresh(refreshToken: refreshToken, now: date) }
        refreshTask = task
        do {
            let newSession = try await task.value
            refreshTask = nil
            // Signed out (or signed in as someone else) while the refresh ran: don't resurrect the old session.
            guard session?.refreshToken == refreshToken else { throw SupabaseAuthError.notSignedIn }
            await apply(newSession)
            return newSession
        } catch SupabaseAuthError.invalidCredentials {
            refreshTask = nil
            Self.logger.notice("Refresh token refused; clearing the session.")
            if session?.refreshToken == refreshToken { await apply(nil) }
            throw SupabaseAuthError.sessionExpired
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func apply(_ newSession: SupabaseSession?) async {
        session = newSession
        if let newSession {
            store.save(newSession)
        } else {
            store.clear()
        }
        await onChange(newSession)
    }
}
