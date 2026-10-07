// AppleSignInNonce.swift
// Core / Auth
//
// Session 34. Sign in with Apple + Supabase use a nonce in two forms:
//   * Apple gets the SHA-256 hash (hex, lowercase) in `ASAuthorizationAppleIDRequest.nonce`; Apple puts that
//     hash into the identity token's `nonce` claim.
//   * Supabase gets the RAW nonce in `POST /auth/v1/token?grant_type=id_token` (`"nonce"`); it hashes it and
//     compares with the token's claim. That is what stops a stolen identity token being replayed.
// This is the pattern in Supabase's "Login with Apple" guide for native iOS (checked 2026-10-07 against
// supabase/auth's openapi.yaml for the request fields; the hash-for-Apple, raw-for-Supabase split is from
// the guide and the supabase-swift sample, not observed against a live project).

import CryptoKit
import Foundation

public enum AppleSignInNonce {
    /// The characters a raw nonce is drawn from (URL- and JSON-safe).
    static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    /// A fresh random nonce. `SystemRandomNumberGenerator` is cryptographically secure on Apple platforms.
    public static func random(length: Int = 32) -> String {
        precondition(length > 0)
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    /// Lowercase hex SHA-256 of `input` (UTF-8). This is what goes to Apple.
    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
