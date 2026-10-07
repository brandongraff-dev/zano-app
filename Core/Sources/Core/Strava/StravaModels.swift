// StravaModels.swift
// Core / Strava
//
// Direct Strava link (session 40; docs/spec.md §3 "Workout (home/outdoor)"). Wire types for the
// `strava-oauth` / `strava-activities` Edge Functions (backend/supabase/functions/), the auth seam the app
// wires at launch, and the redirect parser. Pure parts are unit tested in `StravaTests`.

import Foundation

// MARK: - Auth seam (wired by the coordinator at merge)

/// What the Strava link needs from the app's sign-in. **The seam to wire:** a type in the sign-in/auth
/// session work conforms to this and is passed to `StravaClient.shared.configure(session:)` at launch.
///
/// - `supabaseAccessToken()` (from `SupabaseAuthTokenProviding`): the signed-in user's current Supabase
///   access token, refreshed if needed; throws when nobody is signed in.
/// - `isBackendConfigured()`: `true` only when this build has a Supabase project (URL + anon key) AND a user
///   is signed in right now. No network call. While it is `false`, Settings hides the Strava row entirely
///   (nothing non-working may be visible, App Review 2.1).
public protocol StravaBackendSessionProviding: SupabaseAuthTokenProviding {
    func isBackendConfigured() async -> Bool
}

// MARK: - Activities

/// One Strava activity as `strava-activities` returns it (a slim summary: no names, maps or places).
public struct StravaActivity: Codable, Sendable, Equatable, Identifiable {
    /// Strava activity id (64-bit on Strava's side, sent as a string).
    public let id: String
    public let sportType: String
    public let startDate: Date
    public let elapsedSeconds: Int
    public let movingSeconds: Int
    /// Typed in by hand on Strava. Does not count (see `StravaNotCountedReason.enteredByHand`).
    public let manual: Bool
    public let hasHeartrate: Bool
    public let maxHeartrate: Double?

    public init(
        id: String,
        sportType: String,
        startDate: Date,
        elapsedSeconds: Int,
        movingSeconds: Int,
        manual: Bool,
        hasHeartrate: Bool = false,
        maxHeartrate: Double? = nil
    ) {
        self.id = id
        self.sportType = sportType
        self.startDate = startDate
        self.elapsedSeconds = elapsedSeconds
        self.movingSeconds = movingSeconds
        self.manual = manual
        self.hasHeartrate = hasHeartrate
        self.maxHeartrate = maxHeartrate
    }
}

struct StravaActivitiesResponse: Decodable {
    let activities: [StravaActivity]
}

public enum StravaJSON {
    /// The function sends camelCase keys and ISO-8601 dates (Strava's own `start_date`, e.g.
    /// `2026-10-07T06:01:00Z`). Fractional seconds are accepted too.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: raw) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
        }
        return decoder
    }
}

// MARK: - Errors

public enum StravaLinkError: Error, Sendable, Equatable {
    /// No Supabase project in this build, or nobody signed in.
    case notConfigured
    /// This user has no Strava connection (or it was removed on strava.com).
    case notLinked
    /// The person cancelled the Strava sheet or tapped "Cancel" on Strava's screen.
    case cancelled
    /// The person unticked activity access on Strava's screen.
    case scopeMissing
    /// Strava's app-wide rate limit; try again later.
    case rateLimited
    /// Anything else (network, server, bad response).
    case failed
}

// MARK: - Redirect

/// The redirect Strava sends back to `zano://zano.app/strava?...` (the `STRAVA_REDIRECT_URI` the
/// `strava-oauth` function puts in the authorize URL).
public enum StravaCallback: Sendable, Equatable {
    case authorized(code: String, state: String, scope: String)
    case denied

    public static let scheme = "zano"

    /// `nil` when the URL is not a Strava redirect at all.
    public static func parse(_ url: URL) -> StravaCallback? {
        guard url.scheme?.lowercased() == scheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        if value("error") != nil { return .denied }
        guard let code = value("code"), let state = value("state") else { return nil }
        return .authorized(code: code, state: state, scope: value("scope") ?? "")
    }
}
