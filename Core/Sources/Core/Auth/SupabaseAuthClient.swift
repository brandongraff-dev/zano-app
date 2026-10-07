// SupabaseAuthClient.swift
// Core / Auth
//
// Session 34 (docs/spec.md §11: "Auth (Sign in with Apple)"). Talks to Supabase Auth (GoTrue) over plain
// REST, so no new package is needed. Stateless: `SupabaseAuthSession` owns the session and calls this.
//
// Wire contract. Checked 2026-10-07 against supabase/auth's openapi.yaml (master); NOT run against a live
// project (none exists yet), so treat as UNVERIFIED until the first real sign-in:
//   POST {project}/auth/v1/token?grant_type=id_token
//        { "provider": "apple", "id_token": "<Apple identity token>", "nonce": "<RAW nonce>" }
//   POST {project}/auth/v1/token?grant_type=refresh_token   { "refresh_token": "<token>" }
//     -> 200 { access_token, token_type: "bearer", expires_in, expires_at, refresh_token, user: { id, email } }
//     -> 400/401/403/422 { error / error_code, msg / error_description } on a bad token or a spent refresh token
//   POST {project}/auth/v1/logout   (Authorization: Bearer <access token>) -> 204. Best effort.
//   POST {project}/functions/v1/delete-account   (Authorization: Bearer <access token>)
//        -> 200 { "deleted": true }   (backend/supabase/functions/delete-account, this session)
//   Every request carries `apikey: <anon key>` (openapi.yaml's APIKeyAuth is the `apikey` header).
//
// The anon key is public by Supabase's design. The service-role key never appears in the app; account
// deletion goes through the Edge Function, which holds it server-side (CLAUDE.md).

import Foundation

// MARK: - Session

/// A Supabase session as kept in the Keychain. `Codable` for storage; `Sendable` so it crosses actors.
public struct SupabaseSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userID: String?
    public let email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String?, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }

    /// Refresh a little early so a request never leaves with a token that expires in flight.
    public static let refreshLeeway: TimeInterval = 60

    /// Pure: whether the access token is expired or about to be.
    public static func needsRefresh(expiresAt: Date, now: Date, leeway: TimeInterval = refreshLeeway) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }

    public func needsRefresh(now: Date) -> Bool {
        Self.needsRefresh(expiresAt: expiresAt, now: now)
    }
}

// MARK: - Errors

public enum SupabaseAuthError: Error, Sendable, Equatable {
    /// The build has no Supabase URL / anon key.
    case notConfigured
    /// No session: the person hasn't signed in (or signed out).
    case notSignedIn
    /// Supabase refused the Apple token or the refresh token (400/401/403/422).
    case invalidCredentials
    /// The refresh token was refused, so the stored session was cleared. The person must sign in again.
    case sessionExpired
    /// No network, or it timed out.
    case offline
    /// A 2xx body that didn't match the contract above.
    case invalidResponse
    /// Any other status.
    case server(status: Int)
}

// MARK: - Client

public struct SupabaseAuthClient: Sendable {
    /// Sends one request. Injected so `CoreTests` can answer without a network.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let requestTimeoutSeconds: TimeInterval = 20
    static let deleteAccountFunctionPath = "functions/v1/delete-account"

    let configuration: MealVisionConfiguration
    private let transport: Transport

    public init(
        configuration: MealVisionConfiguration,
        transport: @escaping Transport = { request in try await URLSession.shared.data(for: request) }
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    // MARK: Calls

    /// Exchanges an Apple identity token (+ the raw nonce whose hash was given to Apple) for a session.
    public func signInWithApple(idToken: String, rawNonce: String, now: Date = .now) async throws -> SupabaseSession {
        let request = try Self.idTokenRequest(configuration: configuration, idToken: idToken, rawNonce: rawNonce)
        let data = try await send(request)
        return try Self.parseSession(data, now: now)
    }

    /// Trades a refresh token for a new session (Supabase rotates the refresh token every time).
    public func refresh(refreshToken: String, now: Date = .now) async throws -> SupabaseSession {
        let request = try Self.refreshRequest(configuration: configuration, refreshToken: refreshToken)
        let data = try await send(request)
        return try Self.parseSession(data, now: now)
    }

    /// Revokes the session server-side. Callers ignore failures: signing out locally always works.
    public func signOut(accessToken: String) async throws {
        _ = try await send(Self.logoutRequest(configuration: configuration, accessToken: accessToken))
    }

    /// Deletes the account and every server row and photo (App Store 5.1.1(v)).
    public func deleteAccount(accessToken: String) async throws {
        _ = try await send(Self.deleteAccountRequest(configuration: configuration, accessToken: accessToken))
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError {
            throw MealVisionClient.isOfflineError(error) ? SupabaseAuthError.offline : SupabaseAuthError.server(status: 0)
        }
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.mapStatus(http.statusCode)
        }
        return data
    }

    // MARK: Pure helpers (internal so CoreTests can check them without a network)

    static func mapStatus(_ status: Int) -> SupabaseAuthError {
        switch status {
        case 400, 401, 403, 422: return .invalidCredentials
        default: return .server(status: status)
        }
    }

    static func tokenURL(projectURL: URL, grantType: String) throws -> URL {
        var components = URLComponents(
            url: projectURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components?.url else { throw SupabaseAuthError.notConfigured }
        return url
    }

    static func baseRequest(url: URL, anonKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        return request
    }

    static func idTokenRequest(configuration: MealVisionConfiguration, idToken: String, rawNonce: String) throws -> URLRequest {
        var request = baseRequest(
            url: try tokenURL(projectURL: configuration.projectURL, grantType: "id_token"),
            anonKey: configuration.anonKey
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": rawNonce,
        ])
        return request
    }

    static func refreshRequest(configuration: MealVisionConfiguration, refreshToken: String) throws -> URLRequest {
        var request = baseRequest(
            url: try tokenURL(projectURL: configuration.projectURL, grantType: "refresh_token"),
            anonKey: configuration.anonKey
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        return request
    }

    static func logoutRequest(configuration: MealVisionConfiguration, accessToken: String) -> URLRequest {
        var request = baseRequest(
            url: configuration.projectURL.appendingPathComponent("auth/v1/logout"),
            anonKey: configuration.anonKey
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func deleteAccountRequest(configuration: MealVisionConfiguration, accessToken: String) -> URLRequest {
        var request = baseRequest(
            url: configuration.projectURL.appendingPathComponent(deleteAccountFunctionPath),
            anonKey: configuration.anonKey
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        return request
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String?
            let email: String?
        }

        let access_token: String
        let refresh_token: String
        let expires_in: Double?
        let expires_at: Double?
        let user: User?
    }

    /// `expires_at` (UNIX seconds) wins when present; otherwise `now + expires_in`; otherwise one hour
    /// (Supabase's default JWT lifetime), so a missing field never yields a session that never refreshes.
    static func parseSession(_ data: Data, now: Date) throws -> SupabaseSession {
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !decoded.access_token.isEmpty, !decoded.refresh_token.isEmpty
        else { throw SupabaseAuthError.invalidResponse }
        let expiresAt: Date
        if let absolute = decoded.expires_at {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else {
            expiresAt = now.addingTimeInterval(decoded.expires_in ?? 3_600)
        }
        let email = decoded.user?.email.flatMap { $0.isEmpty ? nil : $0 }
        return SupabaseSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: expiresAt,
            userID: decoded.user?.id,
            email: email
        )
    }
}
