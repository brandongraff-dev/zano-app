// Core/Sources/Core/Verification/NFCReader.swift
//
// Foreground Core NFC (NDEF) scanning — docs/spec.md §6 ("App reads NDEF tags. Each tag encodes
// a URL like `zano://tag/<uuid>`...") and §27 Known Platform Gotchas ("Background NFC reading
// requires an NDEF URL and the app's associated domain / URL scheme; when the app is not running,
// the user gets a notification. Shortcuts automations are the true no-touch path.", "NTAG215 tags
// are cheap and widely compatible; stick to NDEF URL records so Shortcuts automations work too.").
//
// `NFCReader` only covers the case where the app is already in the foreground and the user is
// actively holding their phone to a tag (tap-to-map in Settings, tap-to-log from Today, the
// Sunrise Alarm dismiss flow, etc.) — a `NFCNDEFReaderSession` the app opens itself. It has
// nothing to do with the *background* read path (iOS's own "tag detected" system notification
// when the app isn't running); that path needs no app code at all beyond the NDEF URL/URL-scheme
// association Apple's docs describe, and is explained to the user in plain language in
// `NFCTagSetupInstructions` — see that file for the Shortcuts-automation background-read
// workaround this file does not implement.
//
// `NFCTagMapper` (same directory) is the layer above this one: it resolves a scanned URL to a
// stored mapping and dispatches to an App Intent. This file only knows how to get a `URL` off a
// physical tag; it has no knowledge of tag mappings, goals, or intents.

import Foundation

#if canImport(CoreNFC)
// CoreNFC's delegate protocol predates Swift's Sendable/concurrency audit — it is not annotated
// `@MainActor` or `Sendable`. `@preconcurrency import` downgrades the resulting sendability
// diagnostics from errors to (eventually-removed) warnings rather than papering over a real race;
// see the `@preconcurrency` conformance below for how that's made *actually* safe, not just quiet.
@preconcurrency import CoreNFC
#endif

// MARK: - Result & error types

/// One successful foreground scan: the tag's `zano://tag/<uuid>` identifier plus the raw URL it
/// was parsed from (kept around for logging/debugging — `NFCTagMapper` only needs `tagUUID`).
public struct NFCScanResult: Sendable {
    public let tagUUID: UUID
    public let rawURL: URL

    public init(tagUUID: UUID, rawURL: URL) {
        self.tagUUID = tagUUID
        self.rawURL = rawURL
    }
}

/// Errors this wrapper raises itself, as opposed to whatever `CoreNFC.NFCReaderError` the system
/// framework raises (deliberately *not* named `NFCReaderError` — that name is `CoreNFC`'s own
/// type, and shadowing it here would make call sites that need to distinguish "our" errors from
/// the system's ambiguous).
public enum NFCReaderFailure: Error, Sendable, Equatable {
    /// This device has no NFC hardware, or the app is missing the `com.apple.developer.nfc.readersession.formats`
    /// entitlement / `Info.plist` usage description. See `docs/setup/apple-developer.md`.
    case unsupportedDevice
    /// `scanOnce` was called while a scan was already in flight. Callers should disable their
    /// "Scan a tag" button for the duration of the `await` instead of relying on this — it exists
    /// as a defensive guard, not a UI affordance.
    case sessionAlreadyActive
    /// The user dismissed the system NFC sheet ("Cancel" / swipe down) before any tag was read.
    case cancelled
    /// A tag was read, but none of its NDEF records decoded to a `zano://` URL this app
    /// recognizes. Distinct from `NFCTagMapperError.invalidZanoURL` in the mapper: this one means
    /// "not a ZANO tag at all," the mapper's means "a ZANO tag URL that doesn't parse."
    case noZanoTagFound
    /// The session invalidated with a system error other than user-cancel (radio disabled,
    /// timeout, tag connection lost, etc). The associated string is
    /// `(error as NSError).localizedDescription`, kept as a plain `String` so this type stays
    /// `Equatable`/`Sendable` without depending on `CoreNFC` being importable.
    case invalidatedWithError(String)

    #if !canImport(CoreNFC)
    /// This platform/SDK build has no `CoreNFC` at all (e.g. certain SDK/simulator
    /// configurations). `scanOnce` throws this immediately rather than pretending to scan.
    case unavailablePlatform
    #endif
}

// MARK: - NFCReader

/// Thin wrapper around `NFCNDEFReaderSession` for a single foreground scan.
///
/// Deliberately narrow: one scan in flight at a time, one result (or error) per scan, no
/// persistent "always listening" mode — Core NFC has no such mode while foregrounded anyway; the
/// system sheet is inherently a one-shot, user-attended interaction. Callers that need "scan
/// again" (e.g. the tag-mapping settings screen, or retrying the Sunrise Tag dismiss after a
/// misread) just call `scanOnce` again.
///
/// `@MainActor`-isolated: the class owns UI-facing state (the live `NFCNDEFReaderSession`'s
/// `alertMessage`, the in-flight `CheckedContinuation`) that must only ever be touched from one
/// place at a time, and `NFCNDEFReaderSession` itself is explicitly constructed with
/// `queue: .main` below so its delegate callbacks really do land on the main actor's executor —
/// not just "probably do." That's what makes the `@preconcurrency` delegate conformance below
/// sound rather than a gamble: Swift's runtime isolation check for a `@MainActor`-isolated method
/// reached via `@preconcurrency` passes only when the calling thread is actually the main
/// executor, and `queue: .main` guarantees that.
///
/// - Note: This is written from Apple API knowledge as of this codebase's target (iOS 17+,
///   `Core/Package.swift`), with no Mac/Swift toolchain available to compile-check it (see this
///   session's `knownIssues`). `NFCNDEFPayload.wellKnownTypeURIPayload()` and the exact
///   `NFCReaderError.Code` cases used in `classify(_:)` below are the pieces most likely to need a
///   once-over against the current CoreNFC docs the first time this builds on a Mac.
@MainActor
public final class NFCReader: NSObject {
    public static let shared = NFCReader()

    /// `true` when this device/app build can attempt an NFC scan at all. Check before showing any
    /// "Scan a tag" UI — on an unsupported device (no NFC radio, or missing entitlement) Core NFC
    /// throws immediately rather than offering a fallback UI of its own.
    public static var isAvailable: Bool {
        #if canImport(CoreNFC)
        NFCNDEFReaderSession.readingAvailable
        #else
        false
        #endif
    }

    #if canImport(CoreNFC)
    private var session: NFCNDEFReaderSession?
    #endif
    private var continuation: CheckedContinuation<NFCScanResult, Error>?

    private override init() {
        super.init()
    }

    /// Opens the system NFC scanning sheet, waits for the user to tap a tag, and resolves with
    /// the first `zano://tag/<uuid>` URL found on it.
    ///
    /// - Parameters:
    ///   - alertMessage: Text shown in the system NFC sheet while scanning (e.g. "Hold your
    ///     phone near a ZANO tag"). Caller-supplied so this file never hardcodes user-facing copy
    ///     — see `Core/Sources/Core/Copy` (CLAUDE.md: "No hardcoded user-facing strings").
    ///   - noMatchMessage: Text shown in the sheet, briefly, if a tag was read but didn't carry a
    ///     recognizable `zano://` URL, before the sheet dismisses. `nil` uses Core NFC's own
    ///     default failure text.
    /// - Returns: The scanned tag's id and raw URL.
    /// - Throws: `NFCReaderFailure`, or a `CoreNFC.NFCReaderError` this wrapper didn't recognize
    ///   and passed through as `.invalidatedWithError`'s description.
    public func scanOnce(alertMessage: String, noMatchMessage: String? = nil) async throws -> NFCScanResult {
        #if canImport(CoreNFC)
        guard Self.isAvailable else { throw NFCReaderFailure.unsupportedDevice }
        guard continuation == nil else { throw NFCReaderFailure.sessionAlreadyActive }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: NFCReaderFailure.unsupportedDevice)
                return
            }
            self.continuation = continuation
            self.pendingNoMatchMessage = noMatchMessage

            // `queue: .main` (not `nil`) is deliberate — see the type-level doc comment: it's
            // what makes the `@preconcurrency` delegate conformance below provably safe instead
            // of an assumption about which queue Core NFC happens to use by default.
            let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            session.alertMessage = alertMessage
            self.session = session
            session.begin()
        }
        #else
        throw NFCReaderFailure.unavailablePlatform
        #endif
    }

    /// Updates the system sheet's message mid-scan (e.g. "Got it — verifying…"). No-op if no scan
    /// is in flight.
    public func updateAlert(_ message: String) {
        #if canImport(CoreNFC)
        session?.alertMessage = message
        #endif
    }

    /// Cancels an in-flight scan, if any, resuming its continuation with `.cancelled`. Call from
    /// a "Cancel" button in scan UI, or on view disappearance.
    public func stopScanning() {
        #if canImport(CoreNFC)
        guard let session else { return }
        session.invalidate()
        self.session = nil
        #endif
        finish(.failure(NFCReaderFailure.cancelled))
    }

    #if canImport(CoreNFC)
    /// Caller-supplied text to flash in the sheet when a tag reads but isn't a recognizable ZANO
    /// tag, set for the duration of one scan by `scanOnce`.
    private var pendingNoMatchMessage: String?

    /// Resumes the current continuation exactly once and clears scan state. Safe to call more
    /// than once per scan (e.g. once from `readerSession(_:didDetectNDEFs:)` and again from the
    /// `didInvalidateWithError` callback Core NFC fires right after) — every call after the first
    /// is a no-op because `continuation` is nil'd out on the first.
    private func finish(_ result: Result<NFCScanResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        self.pendingNoMatchMessage = nil
        continuation.resume(with: result)
    }

    /// Best-effort mapping from a `CoreNFC.NFCReaderError` to `NFCReaderFailure`. Unrecognized
    /// codes (any future/undocumented case) fall through to `.invalidatedWithError` with the
    /// system's own localized description rather than silently dropping the failure reason.
    ///
    /// - Note: The specific `.Code` cases switched on here are transcribed from training
    ///   knowledge of the CoreNFC SDK, not verified against a compiler — flagged in this session's
    ///   `knownIssues`. `.readerSessionInvalidationErrorFirstNDEFTagRead` in particular is *not*
    ///   a real failure: it's the code Core NFC uses when it auto-invalidates a session after
    ///   `invalidateAfterFirstRead: true` did its job, which happens on every successful scan
    ///   *after* `readerSession(_:didDetectNDEFs:)` already resolved the continuation — so
    ///   `finish` below is already a no-op by the time it arrives, and this case is handled only
    ///   for documentation's sake.
    private func classify(_ error: Error) -> NFCReaderFailure {
        guard let readerError = error as? CoreNFC.NFCReaderError else {
            return .invalidatedWithError(error.localizedDescription)
        }
        switch readerError.code {
        case .readerSessionInvalidationErrorFirstNDEFTagRead:
            // Normal post-success invalidation — see the note above. Treated the same as any
            // other case here since `finish` is idempotent; this branch exists for clarity only.
            return .invalidatedWithError(readerError.localizedDescription)
        case .readerSessionInvalidationErrorUserCanceled:
            return .cancelled
        default:
            return .invalidatedWithError(readerError.localizedDescription)
        }
    }
    #endif
}

// MARK: - NFCNDEFReaderSessionDelegate

#if canImport(CoreNFC)
// `@preconcurrency` on the conformance is the shorthand for "trust that this @MainActor type's
// delegate methods really do run on the main actor" — see the type-level doc comment for why that
// trust is backed by `queue: .main` above rather than being a bare assumption. Without it, Swift 6
// strict concurrency refuses to let a `@MainActor` type conform to a non-isolated ObjC protocol
// with non-`nonisolated` method bodies.
@preconcurrency
extension NFCReader: NFCNDEFReaderSessionDelegate {
    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                guard let url = record.wellKnownTypeURIPayload() else { continue }
                if let tagID = NFCTagMapper.tagID(from: url) {
                    finish(.success(NFCScanResult(tagUUID: tagID, rawURL: url)))
                    return
                }
            }
        }
        // Read something, but not a ZANO tag — surface `.noZanoTagFound` and let the sheet show
        // `pendingNoMatchMessage` (or Core NFC's own default failure text, if the caller didn't
        // supply one) before it auto-dismisses.
        if let pendingNoMatchMessage {
            session.invalidate(errorMessage: pendingNoMatchMessage)
        } else {
            session.invalidate()
        }
        finish(.failure(NFCReaderFailure.noZanoTagFound))
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        finish(.failure(classify(error)))
    }
}
#endif
