import Testing
import Foundation
@testable import Core

// Session 34: Sign in with Apple + Supabase auth. Covers the pure parts (nonce, refresh decision, request
// shapes, response parsing, configuration parsing, availability rules) and the session actor against an
// in-memory store and a fake transport. Nothing here touches the network or the Keychain.

// MARK: - Test doubles

/// In-memory `SupabaseSessionStoring`. A lock, not an actor, because the protocol is synchronous.
private final class MemorySessionStore: SupabaseSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SupabaseSession?

    init(_ session: SupabaseSession? = nil) { stored = session }

    func load() -> SupabaseSession? { lock.withLock { stored } }
    @discardableResult func save(_ session: SupabaseSession) -> Bool { lock.withLock { stored = session }; return true }
    func clear() { lock.withLock { stored = nil } }
}

/// Records every request the fake transport receives.
private actor RequestLog {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
    var count: Int { requests.count }
    var last: URLRequest? { requests.last }
}

private func fakeTransport(
    status: Int,
    body: String,
    log: RequestLog
) -> SupabaseAuthClient.Transport {
    { request in
        await log.record(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private let testConfig = MealVisionConfiguration(projectURL: URL(string: "https://abcd.supabase.co")!, anonKey: "anon-key")
private let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)

private func tokenBody(access: String = "new-access", refresh: String = "new-refresh", expiresAt: Double? = nil, expiresIn: Double? = 3_600) -> String {
    var parts = ["\"access_token\":\"\(access)\"", "\"refresh_token\":\"\(refresh)\"", "\"token_type\":\"bearer\""]
    if let expiresAt { parts.append("\"expires_at\":\(Int(expiresAt))") }
    if let expiresIn { parts.append("\"expires_in\":\(Int(expiresIn))") }
    parts.append("\"user\":{\"id\":\"11111111-2222-3333-4444-555555555555\",\"email\":\"x@privaterelay.appleid.com\"}")
    return "{" + parts.joined(separator: ",") + "}"
}

private func jsonBody(_ request: URLRequest) -> [String: String] {
    guard let data = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else { return [:] }
    return object
}

// MARK: - Pure parts

@Suite("Auth — nonce, refresh decision, requests, parsing")
struct AuthPureTests {
    @Test func sha256MatchesKnownVector() {
        #expect(AppleSignInNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func randomNonceHasLengthAndCharset() {
        let nonce = AppleSignInNonce.random(length: 32)
        #expect(nonce.count == 32)
        #expect(nonce.allSatisfy { AppleSignInNonce.charset.contains($0) })
        #expect(AppleSignInNonce.random() != AppleSignInNonce.random())
    }

    @Test func refreshDecisionUsesLeeway() {
        #expect(SupabaseSession.needsRefresh(expiresAt: fixedNow.addingTimeInterval(30), now: fixedNow))
        #expect(SupabaseSession.needsRefresh(expiresAt: fixedNow.addingTimeInterval(-5), now: fixedNow))
        #expect(!SupabaseSession.needsRefresh(expiresAt: fixedNow.addingTimeInterval(600), now: fixedNow))
    }

    @Test func idTokenRequestShape() throws {
        let request = try SupabaseAuthClient.idTokenRequest(configuration: testConfig, idToken: "apple-jwt", rawNonce: "raw")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://abcd.supabase.co/auth/v1/token?grant_type=id_token")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(jsonBody(request) == ["provider": "apple", "id_token": "apple-jwt", "nonce": "raw"])
    }

    @Test func refreshRequestShape() throws {
        let request = try SupabaseAuthClient.refreshRequest(configuration: testConfig, refreshToken: "r1")
        #expect(request.url?.absoluteString == "https://abcd.supabase.co/auth/v1/token?grant_type=refresh_token")
        #expect(jsonBody(request) == ["refresh_token": "r1"])
    }

    @Test func logoutAndDeleteCarryTheUserToken() {
        let logout = SupabaseAuthClient.logoutRequest(configuration: testConfig, accessToken: "a1")
        #expect(logout.url?.absoluteString == "https://abcd.supabase.co/auth/v1/logout")
        #expect(logout.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
        let delete = SupabaseAuthClient.deleteAccountRequest(configuration: testConfig, accessToken: "a1")
        #expect(delete.url?.absoluteString == "https://abcd.supabase.co/functions/v1/delete-account")
        #expect(delete.httpMethod == "POST")
        #expect(delete.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
        #expect(delete.value(forHTTPHeaderField: "apikey") == "anon-key")
    }

    @Test func parseSessionPrefersExpiresAt() throws {
        let absolute = fixedNow.addingTimeInterval(1_000).timeIntervalSince1970
        let session = try SupabaseAuthClient.parseSession(Data(tokenBody(expiresAt: absolute).utf8), now: fixedNow)
        #expect(session.accessToken == "new-access")
        #expect(session.refreshToken == "new-refresh")
        #expect(session.expiresAt == Date(timeIntervalSince1970: absolute))
        #expect(session.userID == "11111111-2222-3333-4444-555555555555")
        #expect(session.email == "x@privaterelay.appleid.com")
    }

    @Test func parseSessionFallsBackToExpiresIn() throws {
        let session = try SupabaseAuthClient.parseSession(Data(tokenBody(expiresAt: nil, expiresIn: 120).utf8), now: fixedNow)
        #expect(session.expiresAt == fixedNow.addingTimeInterval(120))
    }

    @Test func parseSessionRejectsGarbage() {
        do {
            _ = try SupabaseAuthClient.parseSession(Data("{\"access_token\":\"\"}".utf8), now: fixedNow)
            Issue.record("expected invalidResponse")
        } catch let error as SupabaseAuthError {
            #expect(error == .invalidResponse)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func statusMapping() {
        #expect(SupabaseAuthClient.mapStatus(400) == .invalidCredentials)
        #expect(SupabaseAuthClient.mapStatus(401) == .invalidCredentials)
        #expect(SupabaseAuthClient.mapStatus(422) == .invalidCredentials)
        #expect(SupabaseAuthClient.mapStatus(500) == .server(status: 500))
    }
}

// MARK: - Configuration + availability

@Suite("Auth — configuration and availability")
struct AuthAvailabilityTests {
    @Test func configurationAcceptsFullURLAndBareHost() {
        let full = MealVisionConfiguration.make(rawURL: "https://abcd.supabase.co/", rawKey: " key ")
        #expect(full?.projectURL.absoluteString == "https://abcd.supabase.co")
        #expect(full?.anonKey == "key")
        let host = MealVisionConfiguration.make(rawURL: "abcd.supabase.co", rawKey: "key")
        #expect(host?.projectURL.absoluteString == "https://abcd.supabase.co")
    }

    @Test func configurationRejectsMissingOrUnsafeValues() {
        #expect(MealVisionConfiguration.make(rawURL: nil, rawKey: "key") == nil)
        #expect(MealVisionConfiguration.make(rawURL: "", rawKey: "key") == nil)
        #expect(MealVisionConfiguration.make(rawURL: "https://abcd.supabase.co", rawKey: "") == nil)
        #expect(MealVisionConfiguration.make(rawURL: "$(SUPABASE_URL)", rawKey: "key") == nil)
        #expect(MealVisionConfiguration.make(rawURL: "https://abcd.supabase.co", rawKey: "$(SUPABASE_ANON_KEY)") == nil)
        #expect(MealVisionConfiguration.make(rawURL: "http://abcd.supabase.co", rawKey: "key") == nil)
    }

    @Test func liveNeedsConfigAndSignIn() {
        #expect(!BackendAvailability.isLive(configured: false, signedIn: false))
        #expect(!BackendAvailability.isLive(configured: false, signedIn: true))
        #expect(!BackendAvailability.isLive(configured: true, signedIn: false))
        #expect(BackendAvailability.isLive(configured: true, signedIn: true))
    }

    @Test func squadAlsoNeedsServerSupport() {
        #expect(!SquadAvailability.shouldShow(configured: true, signedIn: true, serverSupport: false))
        #expect(SquadAvailability.shouldShow(configured: true, signedIn: true, serverSupport: true))
        #expect(!SquadAvailability.shouldShow(configured: false, signedIn: true, serverSupport: true))
    }

    @MainActor @Test func accountStatusIgnoresSessionWithoutConfig() {
        let session = SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: fixedNow, userID: nil, email: "e@x.com")
        let unconfigured = AccountStatus(isConfigured: false, storedSession: session, loadFromKeychain: false)
        #expect(!unconfigured.isSignedIn)
        #expect(!unconfigured.isLive)
        #expect(unconfigured.email == nil)

        let configured = AccountStatus(isConfigured: true, storedSession: session, loadFromKeychain: false)
        #expect(configured.isLive)
        #expect(configured.email == "e@x.com")
        configured.update(session: nil)
        #expect(!configured.isLive)
    }
}

// MARK: - Session actor

@Suite("Auth — SupabaseAuthSession")
struct AuthSessionTests {
    private func makeSession(
        configured: Bool = true,
        stored: SupabaseSession? = nil,
        status: Int = 200,
        body: String = tokenBody(),
        log: RequestLog,
        store: MemorySessionStore
    ) -> SupabaseAuthSession {
        if let stored { store.save(stored) }
        return SupabaseAuthSession(
            configuration: configured ? testConfig : nil,
            store: store,
            transport: fakeTransport(status: status, body: body, log: log),
            now: { fixedNow },
            onChange: { _ in }
        )
    }

    @Test func unconfiguredNeverTouchesTheNetwork() async {
        let log = RequestLog()
        let session = makeSession(configured: false, log: log, store: MemorySessionStore())
        do {
            _ = try await session.supabaseAccessToken()
            Issue.record("expected notConfigured")
        } catch let error as SupabaseAuthError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(await session.hasSupabaseSession() == false)
        #expect(await log.count == 0)
    }

    @Test func signedOutThrowsNotSignedIn() async {
        let log = RequestLog()
        let session = makeSession(log: log, store: MemorySessionStore())
        do {
            _ = try await session.supabaseAccessToken()
            Issue.record("expected notSignedIn")
        } catch let error as SupabaseAuthError {
            #expect(error == .notSignedIn)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(await log.count == 0)
    }

    @Test func freshTokenIsReturnedWithoutRefresh() async throws {
        let log = RequestLog()
        let fresh = SupabaseSession(accessToken: "old", refreshToken: "r0", expiresAt: fixedNow.addingTimeInterval(3_000), userID: nil, email: nil)
        let session = makeSession(stored: fresh, log: log, store: MemorySessionStore())
        #expect(try await session.supabaseAccessToken() == "old")
        #expect(await session.hasSupabaseSession())
        #expect(await log.count == 0)
    }

    @Test func expiredTokenIsRefreshedAndStored() async throws {
        let log = RequestLog()
        let store = MemorySessionStore()
        let stale = SupabaseSession(accessToken: "old", refreshToken: "r0", expiresAt: fixedNow.addingTimeInterval(10), userID: nil, email: nil)
        let session = makeSession(stored: stale, log: log, store: store)
        #expect(try await session.supabaseAccessToken() == "new-access")
        #expect(await log.count == 1)
        let sent = await log.last
        #expect(sent?.url?.query == "grant_type=refresh_token")
        #expect(sent.map(jsonBody) == ["refresh_token": "r0"])
        #expect(store.load()?.refreshToken == "new-refresh")
    }

    @Test func refusedRefreshSignsOut() async {
        let log = RequestLog()
        let store = MemorySessionStore()
        let stale = SupabaseSession(accessToken: "old", refreshToken: "r0", expiresAt: fixedNow, userID: nil, email: nil)
        let session = makeSession(stored: stale, status: 400, body: "{\"error\":\"invalid_grant\"}", log: log, store: store)
        do {
            _ = try await session.supabaseAccessToken()
            Issue.record("expected sessionExpired")
        } catch let error as SupabaseAuthError {
            #expect(error == .sessionExpired)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(store.load() == nil)
        #expect(await session.isSignedIn == false)
    }

    @Test func signInWithAppleStoresTheSession() async throws {
        let log = RequestLog()
        let store = MemorySessionStore()
        let session = makeSession(log: log, store: store)
        try await session.signInWithApple(idToken: "apple-jwt", rawNonce: "raw")
        #expect(await session.isSignedIn)
        #expect(await session.email == "x@privaterelay.appleid.com")
        #expect(store.load()?.accessToken == "new-access")
        let sent = await log.last
        #expect(sent.map(jsonBody) == ["provider": "apple", "id_token": "apple-jwt", "nonce": "raw"])
    }

    @Test func signOutClearsEvenWhenServerFails() async {
        let log = RequestLog()
        let store = MemorySessionStore()
        let fresh = SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: fixedNow.addingTimeInterval(3_000), userID: nil, email: nil)
        let session = makeSession(stored: fresh, status: 500, body: "{}", log: log, store: store)
        await session.signOut()
        #expect(await session.isSignedIn == false)
        #expect(store.load() == nil)
        #expect(await log.last?.url?.path == "/auth/v1/logout")
    }

    @Test func failedDeleteKeepsTheSession() async {
        let log = RequestLog()
        let store = MemorySessionStore()
        let fresh = SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: fixedNow.addingTimeInterval(3_000), userID: nil, email: nil)
        let session = makeSession(stored: fresh, status: 500, body: "{\"error\":\"delete_failed\"}", log: log, store: store)
        do {
            try await session.deleteAccount()
            Issue.record("expected a server error")
        } catch {
            #expect((error as? SupabaseAuthError) == .server(status: 500))
        }
        #expect(await session.isSignedIn)
        #expect(store.load() != nil)
    }
}
