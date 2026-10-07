// SupabaseSessionStore.swift
// Core / Auth
//
// Session 34. Where the Supabase access + refresh tokens live between launches: the Keychain, app-only.
// No shared access group: the extensions never do networking (CLAUDE.md, docs/spec.md §11/§27), so they
// never need a token. `AfterFirstUnlockThisDeviceOnly` lets a background launch (HealthKit / geofence
// wake-ups) still read the session, and keeps it out of backups and off other devices.
//
// Keychain items survive deleting the app. That is deliberate and harmless here: a reinstall finds the old
// session, and the first refresh either works (same person, still signed in) or fails and clears it.
//
// UNVERIFIED (no Mac): the Security calls below are the standard generic-password pattern; unsigned
// Simulator builds (CI) may get errSecMissingEntitlement, in which case `save` returns false and the person
// simply stays signed in for this launch only. Logged, never fatal.

import Foundation
import Security
import os

/// Persistence for one `SupabaseSession`. A protocol so `CoreTests` can swap in memory storage.
public protocol SupabaseSessionStoring: Sendable {
    func load() -> SupabaseSession?
    @discardableResult func save(_ session: SupabaseSession) -> Bool
    func clear()
}

/// The real store: one generic-password Keychain item holding the JSON-encoded session.
public struct KeychainSessionStore: SupabaseSessionStoring {
    public static let standard = KeychainSessionStore(service: "com.zano.app.supabase-session", account: "session")

    let service: String
    let account: String
    private static let logger = Logger(subsystem: "com.zano.app.Core", category: "KeychainSessionStore")

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> SupabaseSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                Self.logger.notice("Keychain read failed: \(status, privacy: .public)")
            }
            return nil
        }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    @discardableResult
    public func save(_ session: SupabaseSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("Keychain write failed: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
