// FamilyLinkClient.swift
// Core / Family
//
// The app's side of Family Link (session 23; docs/spec.md §5.23): talks to Supabase PostgREST (links,
// tasks), the RPCs in `0006_family_link.sql` (every state change), Storage (the teen's proof upload) and the
// `family-proof-open` Edge Function (the parent's one view of a photo).
//
// Not live yet, and honest about it: it follows `MealVisionClient`'s shape and uses its configuration, and
// like it only works once a Supabase project exists AND something implements
// `SupabaseAuthTokenProviding` (nothing does yet; Supabase Auth isn't wired). Until then `isConfigured` is
// `false` and the Family screens say so instead of failing. No network call is made without both.
//
// Privacy: a proof photo is never written to disk by this client. `openProof` downloads the bytes with an
// ephemeral session (no cache, no cookies) and hands them straight back; the caller shows them from memory.
//
// UNVERIFIED (no live project, no device): PostgREST filter syntax, RPC error bodies and the Storage upload
// path are written from memory of the Supabase REST API.

import Foundation

public enum FamilyLinkError: Error, Sendable, Equatable {
    case notConfigured
    /// The server's machine-readable reason (`invalid_invite`, `not_found`, `photo_required`...).
    case server(code: String)
    case http(status: Int)
    case badResponse
    /// The one open of a proof was already used, or it was deleted.
    case gone
}

public actor FamilyLinkClient {
    public static let shared = FamilyLinkClient()

    private var configuration: MealVisionConfiguration?
    private var tokenProvider: (any SupabaseAuthTokenProviding)?
    private let session: URLSession

    init(configuration: MealVisionConfiguration? = MealVisionConfiguration.fromMainBundle(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func configure(configuration: MealVisionConfiguration? = nil, tokenProvider: any SupabaseAuthTokenProviding) {
        if let configuration { self.configuration = configuration }
        self.tokenProvider = tokenProvider
    }

    public var isConfigured: Bool { configuration != nil && tokenProvider != nil }

    // MARK: Links

    /// A parent makes an invite; returns the 8-character code to share.
    public func createInvite() async throws -> String {
        let data = try await rpc("create_family_invite", body: [:])
        guard let code = try? JSONDecoder().decode(String.self, from: data) else { throw FamilyLinkError.badResponse }
        return code
    }

    /// The teen accepts: this is the consent. Returns the link id.
    public func acceptInvite(code: String) async throws -> UUID {
        let data = try await rpc("accept_family_invite", body: ["p_code": code])
        guard let id = try? JSONDecoder().decode(UUID.self, from: data) else { throw FamilyLinkError.badResponse }
        return id
    }

    /// Either side can end the link at any time.
    public func leave(linkID: UUID) async throws {
        _ = try await rpc("leave_family_link", body: ["p_link_id": linkID.uuidString])
    }

    public func links() async throws -> [FamilyLink] {
        let data = try await get("family_links", query: "select=*&status=in.(invited,active)&order=created_at.desc")
        return try FamilyJSON.decoder.decode([FamilyLink].self, from: data)
    }

    // MARK: Tasks

    public func tasks(linkID: UUID) async throws -> [FamilyTask] {
        let data = try await get("family_tasks", query: "select=*&link_id=eq.\(linkID.uuidString)&order=created_at.desc&limit=100")
        return try FamilyJSON.decoder.decode([FamilyTask].self, from: data)
    }

    @discardableResult
    public func createTask(linkID: UUID, title: String, dueAt: Date?, requiresPhoto: Bool) async throws -> UUID {
        var body: [String: Any] = ["p_link_id": linkID.uuidString, "p_title": title, "p_requires_photo": requiresPhoto]
        body["p_due_at"] = dueAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        let data = try await rpc("create_family_task", body: body)
        guard let id = try? JSONDecoder().decode(UUID.self, from: data) else { throw FamilyLinkError.badResponse }
        return id
    }

    /// The teen hands a task in. With a photo, it is uploaded to the private bucket first (JPEG only).
    public func submitTask(taskID: UUID, linkID: UUID, photoJPEG: Data?) async throws {
        var path: Any = NSNull()
        if let photoJPEG {
            let objectPath = "\(linkID.uuidString)/\(taskID.uuidString)/\(UUID().uuidString).jpg"
            try await upload(photoJPEG, to: objectPath)
            path = objectPath
        }
        _ = try await rpc("submit_family_task", body: ["p_task_id": taskID.uuidString, "p_proof_path": path])
    }

    /// The parent answers. Approving or asking for a redo both end the photo's life right away (server side).
    public func decideTask(taskID: UUID, approved: Bool, note: String?) async throws {
        var body: [String: Any] = ["p_task_id": taskID.uuidString, "p_decision": approved ? "approved" : "redo"]
        body["p_note"] = note ?? NSNull()
        _ = try await rpc("decide_family_task", body: body)
    }

    // MARK: Proofs

    public func proofs(taskID: UUID) async throws -> [FamilyProofRecord] {
        let data = try await get("family_proofs", query: "select=id,task_id,first_opened_at,expires_at&task_id=eq.\(taskID.uuidString)")
        return try FamilyJSON.decoder.decode([FamilyProofRecord].self, from: data)
    }

    /// Opens a proof, once. Returns the picture's bytes (never saved by this client) and when it will be
    /// deleted. Throws `.gone` if it was already opened or has expired.
    public func openProof(proofID: UUID) async throws -> (image: Data, deletedAt: Date) {
        guard let configuration, let tokenProvider else { throw FamilyLinkError.notConfigured }
        let token = try await tokenProvider.supabaseAccessToken()
        var request = URLRequest(url: configuration.projectURL.appendingPathComponent("functions/v1/family-proof-open"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["proofId": proofID.uuidString])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FamilyLinkError.badResponse }
        if http.statusCode == 410 { throw FamilyLinkError.gone }
        guard http.statusCode == 200 else { throw Self.error(status: http.statusCode, body: data) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = object["url"] as? String, let url = URL(string: urlString),
              let expires = object["expiresAt"] as? String, let deletedAt = ISO8601DateFormatter().date(from: expires)
                ?? FamilyJSONDate.parse(expires)
        else { throw FamilyLinkError.badResponse }
        // An ephemeral session: nothing about the picture is cached or stored.
        let (image, imageResponse) = try await URLSession(configuration: .ephemeral).data(from: url)
        guard (imageResponse as? HTTPURLResponse)?.statusCode == 200 else { throw FamilyLinkError.gone }
        return (image, deletedAt)
    }

    // MARK: HTTP

    private func get(_ table: String, query: String) async throws -> Data {
        guard let configuration, let tokenProvider else { throw FamilyLinkError.notConfigured }
        let token = try await tokenProvider.supabaseAccessToken()
        guard let url = URL(string: configuration.projectURL.absoluteString + "/rest/v1/\(table)?\(query)") else { throw FamilyLinkError.badResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        return try await run(request)
    }

    private func rpc(_ name: String, body: [String: Any]) async throws -> Data {
        guard let configuration, let tokenProvider else { throw FamilyLinkError.notConfigured }
        let token = try await tokenProvider.supabaseAccessToken()
        var request = URLRequest(url: configuration.projectURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await run(request)
    }

    private func upload(_ jpeg: Data, to objectPath: String) async throws {
        guard let configuration, let tokenProvider else { throw FamilyLinkError.notConfigured }
        let token = try await tokenProvider.supabaseAccessToken()
        var request = URLRequest(url: configuration.projectURL.appendingPathComponent("storage/v1/object/family-proofs/\(objectPath)"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        _ = try await run(request)
    }

    private func run(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FamilyLinkError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, body: data) }
        return data
    }

    /// PostgREST reports a `raise exception 'invalid_invite'` as `{ "message": "invalid_invite", ... }`.
    static func error(status: Int, body: Data) -> FamilyLinkError {
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = (object["message"] as? String) ?? (object["error"] as? String),
           !message.isEmpty, !message.contains(" ") {
            return .server(code: message)
        }
        return .http(status: status)
    }
}

/// The edge function's `expiresAt` may carry fractional seconds.
enum FamilyJSONDate {
    static func parse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}
