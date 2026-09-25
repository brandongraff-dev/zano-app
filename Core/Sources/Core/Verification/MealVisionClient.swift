// Core/Sources/Core/Verification/MealVisionClient.swift
//
// Swift client for `backend/supabase/functions/meal-vision/index.ts` (spec 9.5 Meal Vision:
// photo -> vision LLM -> strict JSON protein estimate; the user confirms/edits; confirmed values
// persist) and for uploading meal photos into the private `meal-photos` Storage bucket
// (`backend/supabase/migrations/0002_auth_storage.sql`) that function reads from.
//
// Wire contract (copied from meal-vision/index.ts's own header, read in full 2026-09-25):
//   Upload first: the function never receives image bytes, only an object path under the
//   caller's own folder — `meal-photos/<auth.uid()>/<file>` (RLS in 0002 enforces the folder; the
//   function additionally 403s any other prefix). JPEG only from this client: the function 415s
//   HEIC/HEIF because the vision provider doesn't accept them.
//   POST {project}/functions/v1/meal-vision  { "action": "analyze", "photoPath": "<uid>/<file>" }
//     -> 200 { mealId, photoPath, confirmed: false,
//              result: { items: [{ name, grams_protein_est, confidence }], total_protein, notes } }
//   POST {project}/functions/v1/meal-vision  { "action": "confirm", "mealId", "items",
//                                               "totalProtein" }
//     -> 200 { mealId, confirmed: true, proteinG }
//   Errors: JSON { error: "<code>", message? } with 400/401/403/404/409/415/502/500.
//   Headers: `Authorization: Bearer <user access token>` + `apikey: <anon key>` — the same pair
//   `Sync/SupabaseSyncBackend.swift` sends, for the same reason (supabase-js's own
//   `functions.invoke()` behaviour).
//
// Configuration / degrade-gracefully contract: this client is "configured" only when it has
// (1) a Supabase project URL + anon key — read from the app's Info.plist keys `SUPABASE_URL` /
// `SUPABASE_ANON_KEY` if present (neither exists in project.yml yet; no Supabase project is live)
// or passed to `configure(...)` — AND (2) a `SupabaseAuthTokenProviding` (nothing implements one
// yet; Supabase Auth isn't wired). Until both exist `isConfigured` is `false` and every UI caller
// skips straight to manual entry — no network call is ever attempted with a missing key.
//
// Local-first: nothing here writes goal events. Logging protein stays `LogProteinIntent`'s job on
// the device (CLAUDE.md: every user action is an intent); the vision estimate is only a starting
// number the user edits. `confirm(...)` is a best-effort, fire-and-forget server-side bookkeeping
// call made *after* the local log succeeded.
//
// UNVERIFIED (no Mac, no live project): the Storage REST upload shape
// (`POST /storage/v1/object/<bucket>/<path>` with raw bytes, `Content-Type` and `x-upsert`
// headers) is the documented Supabase Storage API as of training knowledge — confirm against the
// current Storage API reference when the project goes live. The `sub` claim of a Supabase access
// token being the `auth.uid()` the bucket's RLS compares against is likewise standard Supabase
// JWT behaviour, not verified against a live token.

import Foundation
import os

// MARK: - Configuration

/// The two public values the client needs to reach a Supabase project. The anon key is public by
/// Supabase's design (never the service-role key — CLAUDE.md "API keys live only in Edge
/// Functions").
public struct MealVisionConfiguration: Sendable, Equatable {
    /// e.g. `https://<project-ref>.supabase.co` — no trailing slash, no `/functions/v1`.
    public let projectURL: URL
    public let anonKey: String

    public init(projectURL: URL, anonKey: String) {
        self.projectURL = projectURL
        self.anonKey = anonKey
    }

    /// Info.plist keys read by ``fromMainBundle()``. Add them under the ZANO target's `info:`
    /// properties in project.yml (fed from a build setting, not committed) once a project exists.
    public static let urlInfoKey = "SUPABASE_URL"
    public static let anonKeyInfoKey = "SUPABASE_ANON_KEY"

    /// `nil` unless both keys are present and non-empty and the URL parses.
    public static func fromMainBundle() -> MealVisionConfiguration? {
        let rawURL = (Bundle.main.object(forInfoDictionaryKey: urlInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (Bundle.main.object(forInfoDictionaryKey: anonKeyInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unexpanded build-setting reference ("$(SUPABASE_URL)") counts as absent.
        guard !rawURL.isEmpty, !key.isEmpty, !rawURL.hasPrefix("$("), !key.hasPrefix("$("),
              let url = URL(string: rawURL), url.scheme == "https"
        else { return nil }
        return MealVisionConfiguration(projectURL: url, anonKey: key)
    }
}

// MARK: - Result

/// What `analyze` hands back: the server's draft meal plus the vision estimate, already mapped
/// onto `Models/Meal.swift`'s `MealItem` (whose `CodingKeys` match the wire's
/// `grams_protein_est` exactly).
public struct MealVisionEstimate: Sendable, Equatable {
    /// The server-side draft `meals` row id — pass to ``MealVisionClient/confirm(mealID:items:totalProteinG:)``.
    public let mealID: UUID
    /// The object path inside `meal-photos` (`<uid>/<file>`).
    public let remotePhotoPath: String
    public let items: [MealItem]
    public let totalProteinG: Double
    /// At most one short, neutral sentence from the model (e.g. "portion size unclear").
    public let notes: String

    public init(mealID: UUID, remotePhotoPath: String, items: [MealItem], totalProteinG: Double, notes: String) {
        self.mealID = mealID
        self.remotePhotoPath = remotePhotoPath
        self.items = items
        self.totalProteinG = totalProteinG
        self.notes = notes
    }

    /// Below this, the confirm screen nudges the user to adjust. A judgment call (spec 9.5 gives
    /// no number): the model's per-item confidences cluster high for clearly visible food, so
    /// anything under ~0.6 is usually a guessed portion or an occluded item.
    public static let lowConfidenceThreshold = 0.6

    /// `true` when there's nothing to trust — no items found — or the least-confident item that
    /// actually contributes protein is under ``lowConfidenceThreshold``.
    public var isLowConfidence: Bool {
        guard !items.isEmpty else { return true }
        let contributing = items.filter { $0.proteinGramsEstimate > 0 }
        let lowest = (contributing.isEmpty ? items : contributing).map(\.confidence).min() ?? 0
        return lowest < Self.lowConfidenceThreshold
    }
}

// MARK: - Errors

/// Developer-facing diagnostics; the UI maps these to `Copy.fuel.mealPhoto` strings.
public enum MealVisionClientError: Error, Sendable, Equatable {
    /// No project URL/anon key or no auth token provider — callers should go straight to manual.
    case notConfigured
    /// No signed-in Supabase session, or the server rejected the token.
    case unauthorized
    /// The device looks offline (or the request timed out).
    case offline
    /// The server refused the image format/size.
    case unsupportedPhoto
    /// The vision provider was down or returned something unusable (502).
    case upstreamUnavailable
    /// A 2xx body that didn't match the documented contract.
    case invalidResponse
    /// Any other non-2xx, with the function's machine-readable `error` code when present.
    case server(status: Int, code: String?)
}

// MARK: - Client

/// An `actor` so configuration can be set once at launch (from any isolation domain) and read by
/// concurrent calls safely. Every value that crosses in or out is `Sendable` (`Data`, `String`,
/// `UUID`, `[MealItem]`), so callers never have to send a `UIImage` across an actor boundary —
/// encode to JPEG first.
public actor MealVisionClient {
    public static let shared = MealVisionClient()

    static let functionPath = "functions/v1/meal-vision"
    static let bucket = "meal-photos"
    static let requestTimeoutSeconds: TimeInterval = 40 // the function itself allows the LLM 30s
    static let uploadTimeoutSeconds: TimeInterval = 30

    private var configuration: MealVisionConfiguration?
    private var tokenProvider: (any SupabaseAuthTokenProviding)?
    private let session: URLSession
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "MealVisionClient")

    public init(
        configuration: MealVisionConfiguration? = MealVisionConfiguration.fromMainBundle(),
        tokenProvider: (any SupabaseAuthTokenProviding)? = nil,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Wires in the project + auth once they exist (same "call once at launch" contract as
    /// `SyncEngine.setBackend(_:)`). Passing `nil` for `configuration` keeps whatever Info.plist
    /// provided.
    public func configure(configuration: MealVisionConfiguration? = nil, tokenProvider: any SupabaseAuthTokenProviding) {
        if let configuration { self.configuration = configuration }
        self.tokenProvider = tokenProvider
    }

    /// `false` means: don't show a spinner, go straight to manual entry.
    public var isConfigured: Bool {
        configuration != nil && tokenProvider != nil
    }

    // MARK: Public calls

    /// Uploads `jpegData` and runs the vision estimate on it.
    public func analyze(jpegData: Data) async throws -> MealVisionEstimate {
        let photoPath = try await uploadMealPhoto(jpegData: jpegData)
        let body = try JSONSerialization.data(withJSONObject: ["action": "analyze", "photoPath": photoPath])
        let data = try await postFunction(body: body)
        return try Self.parseAnalyzeResponse(data, fallbackPhotoPath: photoPath)
    }

    /// Uploads a JPEG to `meal-photos/<uid>/<uuid>.jpg` and returns that object path. Public so the
    /// meal-prep flow can hand the path to `MealPrepVerifier.verifyMealPrep(goalID:photoPath:)`
    /// once a meal-prep vision backend exists.
    public func uploadMealPhoto(jpegData: Data) async throws -> String {
        guard let configuration, let tokenProvider else { throw MealVisionClientError.notConfigured }
        let token = try await accessToken(from: tokenProvider)
        guard let uid = Self.authUserID(fromAccessToken: token) else {
            throw MealVisionClientError.unauthorized
        }
        let objectPath = "\(uid)/\(UUID().uuidString.lowercased()).jpg"
        let url = configuration.projectURL
            .appendingPathComponent("storage/v1/object/\(Self.bucket)/\(objectPath)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jpegData
        request.timeoutInterval = Self.uploadTimeoutSeconds
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try await perform(request)
        return objectPath
    }

    /// Persists the user's edited values server-side. Best effort: callers log locally first and
    /// ignore a failure here (the local `Meal` row + `GoalEvent` are the source of truth; sync
    /// reconciles later).
    public func confirm(mealID: UUID, items: [MealItem], totalProteinG: Double) async throws {
        let wireItems: [[String: Any]] = items.map {
            ["name": $0.name, "grams_protein_est": $0.proteinGramsEstimate, "confidence": $0.confidence]
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "confirm",
            "mealId": mealID.uuidString.lowercased(),
            "items": wireItems,
            "totalProtein": totalProteinG,
        ] as [String: Any])
        _ = try await postFunction(body: body)
    }

    // MARK: Transport

    private func postFunction(body: Data) async throws -> Data {
        guard let configuration, let tokenProvider else { throw MealVisionClientError.notConfigured }
        let token = try await accessToken(from: tokenProvider)
        var request = URLRequest(url: configuration.projectURL.appendingPathComponent(Self.functionPath))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func accessToken(from provider: any SupabaseAuthTokenProviding) async throws -> String {
        do {
            return try await provider.supabaseAccessToken()
        } catch {
            Self.logger.notice("No Supabase access token: \(String(describing: error), privacy: .public)")
            throw MealVisionClientError.unauthorized
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            Self.logger.notice("Request failed: \(error.code.rawValue, privacy: .public)")
            throw Self.isOfflineError(error) ? MealVisionClientError.offline : MealVisionClientError.upstreamUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw MealVisionClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.mapStatus(http.statusCode, code: Self.errorCode(from: data))
        }
        return data
    }

    // MARK: Pure helpers (internal so CoreTests can exercise them without a network call)

    static func isOfflineError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    static func mapStatus(_ status: Int, code: String?) -> MealVisionClientError {
        switch status {
        case 401, 403: return .unauthorized
        case 413, 415: return .unsupportedPhoto
        case 502, 503, 504: return .upstreamUnavailable
        default: return .server(status: status, code: code)
        }
    }

    static func errorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }

    /// The `sub` claim of a Supabase JWT access token, i.e. `auth.uid()` — the folder name the
    /// bucket's RLS requires. Decodes the payload segment only; never verifies the signature (the
    /// server does that).
    static func authUserID(fromAccessToken token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let payload = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sub = object["sub"] as? String, !sub.isEmpty
        else { return nil }
        return sub.lowercased()
    }

    private struct AnalyzeResponse: Decodable {
        struct Result: Decodable {
            let items: [MealItem]
            let totalProtein: Double
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case items
                case totalProtein = "total_protein"
                case notes
            }
        }

        let mealId: String
        let photoPath: String?
        let result: Result
    }

    static func parseAnalyzeResponse(_ data: Data, fallbackPhotoPath: String) throws -> MealVisionEstimate {
        guard let decoded = try? JSONDecoder().decode(AnalyzeResponse.self, from: data),
              let mealID = UUID(uuidString: decoded.mealId)
        else { throw MealVisionClientError.invalidResponse }
        let items = decoded.result.items.map {
            MealItem(
                name: $0.name,
                proteinGramsEstimate: max(0, $0.proteinGramsEstimate),
                confidence: min(1, max(0, $0.confidence))
            )
        }
        return MealVisionEstimate(
            mealID: mealID,
            remotePhotoPath: decoded.photoPath ?? fallbackPhotoPath,
            items: items,
            totalProteinG: max(0, decoded.result.totalProtein),
            notes: decoded.result.notes ?? ""
        )
    }
}
