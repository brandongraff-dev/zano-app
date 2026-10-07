// StravaClient.swift
// Core / Strava
//
// Talks to the `strava-oauth` and `strava-activities` Edge Functions (session 40). The app never talks to
// Strava's API directly and never holds a Strava token: the functions keep the client secret and the
// tokens (backend/supabase/migrations/0008_strava.sql). Same shape as `HouseholdClient`: the Supabase
// project URL + anon key come from `MealVisionConfiguration` (Info.plist), the signed-in user from the
// `StravaBackendSessionProviding` seam (StravaModels.swift).
//
// UNVERIFIED (no live project, no Mac): never run against a deployed function.

import Foundation
import os

public actor StravaClient {
    public static let shared = StravaClient()

    private var configuration: MealVisionConfiguration?
    private var session: (any StravaBackendSessionProviding)?
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "StravaClient")

    init(configuration: MealVisionConfiguration? = MealVisionConfiguration.fromMainBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    /// Call once at launch with the app's auth session (the seam). Passing `nil` for `configuration` keeps
    /// whatever Info.plist provided.
    public func configure(session: any StravaBackendSessionProviding, configuration: MealVisionConfiguration? = nil) {
        if let configuration { self.configuration = configuration }
        self.session = session
    }

    /// Whether anything Strava may be shown: a project in this build, a session wired, and someone signed in.
    public func isAvailable() async -> Bool {
        guard configuration != nil, let session else { return false }
        return await session.isBackendConfigured()
    }

    // MARK: Connect

    /// Step 1: the Strava authorize URL to open in `ASWebAuthenticationSession`.
    public func authorizeURL() async throws -> URL {
        let data = try await call("strava-oauth", body: ["action": "start"])
        struct Start: Decodable { let authorizeURL: String }
        guard let start = try? JSONDecoder().decode(Start.self, from: data),
              let url = URL(string: start.authorizeURL)
        else { throw StravaLinkError.failed }
        return url
    }

    /// Step 2: hand Strava's redirect to the server, which swaps the code for tokens and keeps them.
    /// Returns the athlete's first name when Strava shared it.
    @discardableResult
    public func completeAuthorization(callbackURL: URL) async throws -> String? {
        switch StravaCallback.parse(callbackURL) {
        case .denied?:
            throw StravaLinkError.cancelled
        case .authorized(let code, let state, let scope)?:
            let data = try await call("strava-oauth", body: ["action": "exchange", "code": code, "state": state, "scope": scope])
            struct Exchange: Decodable { let connected: Bool; let athleteFirstName: String? }
            guard let result = try? JSONDecoder().decode(Exchange.self, from: data), result.connected else {
                throw StravaLinkError.failed
            }
            StravaActivityStore.isLinked = true
            return result.athleteFirstName
        case nil:
            throw StravaLinkError.failed
        }
    }

    /// Asks the server whether this user is still linked, and mirrors the answer locally.
    @discardableResult
    public func refreshStatus() async throws -> Bool {
        let data = try await call("strava-oauth", body: ["action": "status"])
        struct Status: Decodable { let connected: Bool }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { throw StravaLinkError.failed }
        StravaActivityStore.isLinked = status.connected
        return status.connected
    }

    /// Revokes at Strava and deletes the stored tokens. Local cache is cleared even if the call fails.
    public func disconnect() async throws {
        defer { StravaActivityStore.isLinked = false }
        _ = try await call("strava-oauth", body: ["action": "disconnect"])
    }

    // MARK: Activities

    /// Activities that started after `after` (the server clamps to 8 days back).
    public func activities(after: Date) async throws -> [StravaActivity] {
        let data = try await call("strava-activities", body: ["after": Int(after.timeIntervalSince1970)])
        do {
            return try StravaJSON.decoder.decode(StravaActivitiesResponse.self, from: data).activities
        } catch {
            logger.error("Strava activities didn't decode: \(String(describing: error), privacy: .public)")
            throw StravaLinkError.failed
        }
    }

    // MARK: HTTP

    private func call(_ function: String, body: [String: Any]) async throws -> Data {
        guard let configuration, let session else { throw StravaLinkError.notConfigured }
        let token: String
        do { token = try await session.supabaseAccessToken() } catch { throw StravaLinkError.notConfigured }
        var request = URLRequest(url: configuration.projectURL.appendingPathComponent("functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result: (Data, URLResponse)
        do {
            result = try await urlSession.data(for: request)
        } catch {
            throw StravaLinkError.failed
        }
        let data = result.0
        guard let http = result.1 as? HTTPURLResponse else { throw StravaLinkError.failed }
        if (200..<300).contains(http.statusCode) { return data }
        throw Self.error(status: http.statusCode, body: data)
    }

    /// Maps a function's error response onto `StravaLinkError`. Pure, unit tested.
    nonisolated static func error(status: Int, body: Data) -> StravaLinkError {
        struct Body: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Body.self, from: body))?.error
        switch (status, code) {
        case (404, _), (410, _): return .notLinked
        case (429, _): return .rateLimited
        case (401, _), (503, _): return .notConfigured
        case (_, "scope_missing"?): return .scopeMissing
        default: return .failed
        }
    }
}
