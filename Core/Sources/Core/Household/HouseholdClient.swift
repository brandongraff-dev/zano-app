// HouseholdClient.swift
// Core / Household
//
// The Household API (session 28; docs/spec.md §5.31): PostgREST reads and RPC writes against
// `0007_household.sql`, over an ephemeral URLSession. Same shape and same blocker as `FamilyLinkClient`:
// it reuses `MealVisionConfiguration` for the project URL and key, and `SupabaseAuthTokenProviding` for the
// signed-in user's token (session 34: `SupabaseAuthSession`), so `isConfigured` is false until someone signs in.
//
// UNVERIFIED (no live project): PostgREST filter syntax and RPC error bodies are written from memory of the
// Supabase REST API, like the Family Link client.

import Foundation

public actor HouseholdClient {
    public static let shared = HouseholdClient()

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

    /// Configured AND signed in (session 34): a signed-out person gets the offline state, not a failed call.
    public var isConfigured: Bool {
        get async {
            guard configuration != nil, let tokenProvider else { return false }
            return await tokenProvider.hasSupabaseSession()
        }
    }

    /// The signed-in person's id (the token's `sub`), so the screen can tell "mine" from "theirs".
    public func currentUserID() async throws -> UUID {
        guard let tokenProvider else { throw FamilyLinkError.notConfigured }
        let token = try await tokenProvider.supabaseAccessToken()
        guard let id = Self.userID(fromJWT: token) else { throw FamilyLinkError.badResponse }
        return id
    }

    /// The `sub` claim of a JWT, if it is a UUID.
    public nonisolated static func userID(fromJWT token: String) -> UUID? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = object["sub"] as? String
        else { return nil }
        return UUID(uuidString: sub)
    }

    // MARK: Households

    public func households() async throws -> [Household] {
        let data = try await get("households", query: "select=*&order=created_at.asc")
        return try FamilyJSON.decoder.decode([Household].self, from: data)
    }

    public func members(householdID: UUID) async throws -> [HouseholdMember] {
        let data = try await get("household_members", query: "select=*&household_id=eq.\(householdID.uuidString)&order=joined_at.asc")
        return try FamilyJSON.decoder.decode([HouseholdMember].self, from: data)
    }

    @discardableResult
    public func create(name: String, displayName: String) async throws -> UUID {
        let data = try await rpc("create_household", body: ["p_name": name, "p_display_name": displayName])
        return try Self.uuid(from: data)
    }

    @discardableResult
    public func join(code: String, displayName: String) async throws -> UUID {
        let data = try await rpc("join_household", body: ["p_code": code, "p_display_name": displayName])
        return try Self.uuid(from: data)
    }

    public func rotateInvite(householdID: UUID) async throws -> String {
        let data = try await rpc("rotate_household_invite", body: ["p_household_id": householdID.uuidString])
        guard let code = try? JSONDecoder().decode(String.self, from: data) else { throw FamilyLinkError.badResponse }
        return code
    }

    public func leave(householdID: UUID) async throws {
        _ = try await rpc("leave_household", body: ["p_household_id": householdID.uuidString])
    }

    // MARK: Tasks

    public func tasks(householdID: UUID) async throws -> [HouseholdTask] {
        let data = try await get("household_tasks", query: "select=*&household_id=eq.\(householdID.uuidString)&order=created_at.desc&limit=300")
        return try FamilyJSON.decoder.decode([HouseholdTask].self, from: data)
    }

    @discardableResult
    public func createTask(householdID: UUID, title: String, notes: String, dueAt: Date?, assignee: UUID?) async throws -> UUID {
        var body: [String: Any] = ["p_household_id": householdID.uuidString, "p_title": title, "p_notes": notes]
        body["p_due_at"] = dueAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        body["p_assignee"] = assignee?.uuidString ?? NSNull()
        let data = try await rpc("create_household_task", body: body)
        return try Self.uuid(from: data)
    }

    public func setDone(taskID: UUID, done: Bool) async throws {
        _ = try await rpc("set_household_task_done", body: ["p_task_id": taskID.uuidString, "p_done": done])
    }

    public func assign(taskID: UUID, to assignee: UUID?) async throws {
        _ = try await rpc("assign_household_task", body: ["p_task_id": taskID.uuidString, "p_assignee": assignee?.uuidString ?? NSNull()])
    }

    public func deleteTask(taskID: UUID) async throws {
        _ = try await rpc("delete_household_task", body: ["p_task_id": taskID.uuidString])
    }

    // MARK: Screen-free times (session 44, `0009_household_quiet_times.sql`)

    public func quietTimes(householdID: UUID) async throws -> [HouseholdQuietTime] {
        let data = try await get("household_quiet_times", query: "select=*&household_id=eq.\(householdID.uuidString)&order=start_minute.asc")
        return try FamilyJSON.decoder.decode([HouseholdQuietTime].self, from: data)
    }

    @discardableResult
    public func createQuietTime(householdID: UUID, name: String, startMinute: Int, endMinute: Int, weekdays: [Int]) async throws -> UUID {
        let data = try await rpc("create_household_quiet_time", body: [
            "p_household_id": householdID.uuidString, "p_name": name,
            "p_start_minute": startMinute, "p_end_minute": endMinute, "p_weekdays": weekdays.sorted(),
        ])
        return try Self.uuid(from: data)
    }

    public func updateQuietTime(id: UUID, name: String, startMinute: Int, endMinute: Int, weekdays: [Int]) async throws {
        _ = try await rpc("update_household_quiet_time", body: [
            "p_id": id.uuidString, "p_name": name,
            "p_start_minute": startMinute, "p_end_minute": endMinute, "p_weekdays": weekdays.sorted(),
        ])
    }

    public func deleteQuietTime(id: UUID) async throws {
        _ = try await rpc("delete_household_quiet_time", body: ["p_id": id.uuidString])
    }

    // MARK: HTTP

    private nonisolated static func uuid(from data: Data) throws -> UUID {
        guard let id = try? JSONDecoder().decode(UUID.self, from: data) else { throw FamilyLinkError.badResponse }
        return id
    }

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

    private func run(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FamilyLinkError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw FamilyLinkClient.error(status: http.statusCode, body: data) }
        return data
    }
}
