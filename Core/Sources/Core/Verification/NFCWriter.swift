// Core/Sources/Core/Verification/NFCWriter.swift
//
// Programs a blank NFC tag with a fresh `zano://tag/<uuid>` NDEF URI record — docs/spec.md §25.1
// ("Setup: tag writes `zano://tag/<uuid>`; app maps it to an action in one screen") and §6. Before
// this file, a blank NTAG failed in `NFCReader` with `noZanoTagFound` and the user hit a dead end.
//
// One foreground session does both jobs, so the "Add a tag" button needs a single tap:
//   - the tag already carries a ZANO URL (a pre-written Tag Pack tag) → report its id, write nothing;
//   - the tag is blank (formatted NDEF, no records) → write a new id;
//   - the tag carries someone else's NDEF data → refuse unless the caller passed
//     `overwriteForeignContent: true` (the UI asks first — never silently erase a tag);
//   - read-only / not NDEF-capable / too small → a specific failure the UI can explain.
//
// Concurrency: same model as `NFCReader` — `@MainActor` class, session built with `queue: .main`
// so delegate callbacks land on the main actor, `@preconcurrency` delegate conformance. The
// connect/query/read/write completion handlers are written as explicit `@Sendable` closures
// that only hop a Sendable value (an `Error?`, an enum, a `UUID?`) back to the main actor with
// `Task { @MainActor in ... }`, so nothing assumes which queue Core NFC calls them on, and no
// non-Sendable Core NFC object crosses an isolation boundary: the session and tag stay in
// main-actor stored properties.
//
// UNVERIFIED against a compiler/SDK (no Mac here; CLAUDE.md working rule 5). Transcribed from the
// CoreNFC API surface as documented for iOS 13+:
//   - `NFCNDEFReaderSessionDelegate.readerSession(_:didDetect:)` ([any NFCNDEFTag]) — optional
//     method; when implemented, `readerSession(_:didDetectNDEFs:)` is not called.
//   - `NFCNDEFReaderSession.connect(to:completionHandler:)`, `.restartPolling()`.
//   - `NFCNDEFTag.queryNDEFStatus(completionHandler:)` → (`NFCNDEFStatus`, Int capacity, Error?),
//     `.readNDEF(completionHandler:)` → (`NFCNDEFMessage?`, Error?),
//     `.writeNDEF(_:completionHandler:)` → (Error?).
//   - `NFCNDEFPayload.wellKnownTypeURIPayload(url:)` (class factory, returns optional),
//     `NFCNDEFMessage(records:)`, `NFCNDEFMessage.length`.
// Entitlement: the app's existing `com.apple.developer.nfc.readersession.formats = [NDEF]`
// (project.yml) covers NDEF writing through `NFCNDEFReaderSession`; no `TAG` format is needed.

import Foundation

#if canImport(CoreNFC)
@preconcurrency import CoreNFC
#endif

// MARK: - Public types

/// What a successful programming session found or did.
public enum NFCWriteOutcome: Sendable, Equatable {
    /// The tag was blank (or foreign and the caller allowed overwrite); it now carries
    /// `zano://tag/<tagID>`.
    case wroteNew(tagID: UUID)
    /// The tag already carried a ZANO URL. Nothing was written; `tagID` is the id it holds.
    case alreadyZano(tagID: UUID)

    public var tagID: UUID {
        switch self {
        case .wroteNew(let id), .alreadyZano(let id): id
        }
    }
}

/// Why programming failed. Plain values only, so the type stays `Sendable`/`Equatable` without
/// `CoreNFC` being importable.
public enum NFCWriteFailure: Error, Sendable, Equatable {
    /// No NFC hardware, or the NFC entitlement / usage description is missing.
    case unsupportedDevice
    /// A write (or `NFCReader` scan) is already in flight.
    case sessionAlreadyActive
    /// The user dismissed the system sheet.
    case cancelled
    /// The tag isn't NDEF-capable (or isn't NDEF-formatted).
    case notNDEFCompatible
    /// The tag is write-protected and holds no ZANO URL.
    case readOnly
    /// The tag holds someone else's NDEF data. Retry with `overwriteForeignContent: true` only
    /// after the user agrees.
    case foreignContent
    /// The tag's NDEF capacity is smaller than the URL record.
    case insufficientCapacity
    /// Connecting to, reading, or writing the tag failed (tag moved away, bad read).
    case tagCommunicationFailed(String)
    /// The session ended with a system error other than user-cancel (timeout, radio off...).
    case invalidatedWithError(String)
    /// This SDK build has no CoreNFC at all.
    case unavailablePlatform
}

/// Where a write session is, for an in-app progress indicator next to the system sheet.
public enum NFCWriteStage: Sendable, Equatable {
    case waitingForTag
    case connecting
    case writing
}

/// Caller-supplied system-sheet text (CLAUDE.md: no user-facing strings outside `Copy` —
/// `Copy.nfc.writerMessages` builds one of these).
public struct NFCWriterMessages: Sendable {
    public let hold: String
    public let multipleTags: String
    public let writing: String
    public let success: String
    public let alreadyZano: String
    public let failure: String

    public init(hold: String, multipleTags: String, writing: String, success: String, alreadyZano: String, failure: String) {
        self.hold = hold
        self.multipleTags = multipleTags
        self.writing = writing
        self.success = success
        self.alreadyZano = alreadyZano
        self.failure = failure
    }
}

// MARK: - NFCWriter

@MainActor
public final class NFCWriter: NSObject {
    public static let shared = NFCWriter()

    /// Same availability check as `NFCReader.isAvailable` (reading and NDEF writing share the
    /// session type and the entitlement).
    public static var isAvailable: Bool {
        #if canImport(CoreNFC)
        NFCNDEFReaderSession.readingAvailable
        #else
        false
        #endif
    }

    /// The URL written for `tagID`. The one place the `zano://tag/<uuid>` shape is built;
    /// `NFCTagMapper.tagID(from:)` is its inverse.
    public nonisolated static func url(for tagID: UUID) -> URL {
        // Force-unwrap is safe: a fixed scheme/host plus a UUID string is always a valid URL.
        URL(string: "zano://tag/\(tagID.uuidString)")!
    }

    private var continuation: CheckedContinuation<NFCWriteOutcome, Error>?
    private var stageHandler: (@MainActor (NFCWriteStage) -> Void)?
    private var newTagID = UUID()
    private var allowOverwrite = false
    private var messages: NFCWriterMessages?

    #if canImport(CoreNFC)
    private var session: NFCNDEFReaderSession?
    private var activeTag: (any NFCNDEFTag)?
    #endif

    private override init() {
        super.init()
    }

    /// Opens the system NFC sheet and programs (or recognizes) the first tag held to the phone.
    ///
    /// - Parameters:
    ///   - newTagID: The id to write if the tag turns out to be blank. Defaults to a fresh UUID.
    ///   - overwriteForeignContent: Replace non-ZANO NDEF data. Pass `true` only after the user
    ///     confirmed; the default refuses with `.foreignContent`.
    ///   - messages: System-sheet copy.
    ///   - onStage: Optional progress callback for the in-app view behind the sheet.
    public func programTag(
        newTagID: UUID = UUID(),
        overwriteForeignContent: Bool = false,
        messages: NFCWriterMessages,
        onStage: (@MainActor (NFCWriteStage) -> Void)? = nil
    ) async throws -> NFCWriteOutcome {
        #if canImport(CoreNFC)
        guard Self.isAvailable else { throw NFCWriteFailure.unsupportedDevice }
        guard continuation == nil else { throw NFCWriteFailure.sessionAlreadyActive }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.newTagID = newTagID
            self.allowOverwrite = overwriteForeignContent
            self.messages = messages
            self.stageHandler = onStage

            // `invalidateAfterFirstRead: false` is required to connect to and write a tag.
            let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            session.alertMessage = messages.hold
            self.session = session
            onStage?(.waitingForTag)
            session.begin()
        }
        #else
        throw NFCWriteFailure.unavailablePlatform
        #endif
    }

    /// Cancels an in-flight session (e.g. the sheet behind it was dismissed).
    public func stop() {
        #if canImport(CoreNFC)
        session?.invalidate()
        #endif
        finish(.failure(NFCWriteFailure.cancelled))
    }

    // MARK: Internals

    /// Resumes exactly once; later calls (e.g. the invalidation callback that follows every
    /// `invalidate`) are no-ops.
    private func finish(_ result: Result<NFCWriteOutcome, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.stageHandler = nil
        self.messages = nil
        #if canImport(CoreNFC)
        self.activeTag = nil
        self.session = nil
        #endif
        continuation.resume(with: result)
    }

    #if canImport(CoreNFC)
    /// Ends the sheet with an error line and resolves the call with `failure`.
    private func fail(_ failure: NFCWriteFailure, sheetMessage: String? = nil) {
        let session = self.session
        let text = sheetMessage ?? messages?.failure
        finish(.failure(failure))
        if let text {
            session?.invalidate(errorMessage: text)
        } else {
            session?.invalidate()
        }
    }

    /// Ends the sheet with a success line (the checkmark) and resolves the call.
    private func succeed(_ outcome: NFCWriteOutcome, sheetMessage: String?) {
        let session = self.session
        if let sheetMessage { session?.alertMessage = sheetMessage }
        finish(.success(outcome))
        session?.invalidate()
    }

    private func classify(_ error: Error) -> NFCWriteFailure {
        guard let readerError = error as? CoreNFC.NFCReaderError else {
            return .invalidatedWithError(error.localizedDescription)
        }
        switch readerError.code {
        case .readerSessionInvalidationErrorUserCanceled:
            return .cancelled
        default:
            return .invalidatedWithError(readerError.localizedDescription)
        }
    }

    // Step 2: connected (or not).
    private func didConnect(error: Error?) {
        guard continuation != nil, let tag = activeTag else { return }
        if let error {
            fail(.tagCommunicationFailed(error.localizedDescription))
            return
        }
        tag.queryNDEFStatus { @Sendable status, capacity, error in
            Task { @MainActor [weak self] in
                self?.didQueryStatus(status: status, capacity: capacity, error: error)
            }
        }
    }

    // Step 3: status known — read what's on it before deciding anything.
    private func didQueryStatus(status: NFCNDEFStatus, capacity: Int, error: Error?) {
        guard continuation != nil, let tag = activeTag else { return }
        if let error {
            fail(.tagCommunicationFailed(error.localizedDescription))
            return
        }
        if status == .notSupported {
            fail(.notNDEFCompatible)
            return
        }
        tag.readNDEF { @Sendable message, _ in
            // Summarize on whatever queue Core NFC used; only Sendable values hop to main. A read
            // error is expected for a blank tag (zero-length message), so it's treated as empty.
            let zanoID = message.flatMap(Self.zanoTagID(in:))
            let hasRecords = !(message?.records.isEmpty ?? true)
            Task { @MainActor [weak self] in
                self?.didRead(status: status, capacity: capacity, zanoID: zanoID, hasRecords: hasRecords)
            }
        }
    }

    // Step 4: decide.
    private func didRead(status: NFCNDEFStatus, capacity: Int, zanoID: UUID?, hasRecords: Bool) {
        guard continuation != nil, let tag = activeTag, let messages else { return }

        if let zanoID {
            succeed(.alreadyZano(tagID: zanoID), sheetMessage: messages.alreadyZano)
            return
        }
        if status == .readOnly {
            fail(.readOnly)
            return
        }
        if hasRecords && !allowOverwrite {
            fail(.foreignContent)
            return
        }

        let tagID = newTagID
        guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: Self.url(for: tagID)) else {
            fail(.tagCommunicationFailed("payload"))
            return
        }
        let message = NFCNDEFMessage(records: [payload])
        if capacity > 0, message.length > capacity {
            fail(.insufficientCapacity)
            return
        }

        session?.alertMessage = messages.writing
        stageHandler?(.writing)
        tag.writeNDEF(message) { @Sendable error in
            Task { @MainActor [weak self] in
                self?.didWrite(tagID: tagID, error: error)
            }
        }
    }

    // Step 5: written.
    private func didWrite(tagID: UUID, error: Error?) {
        guard continuation != nil else { return }
        if let error {
            fail(.tagCommunicationFailed(error.localizedDescription))
            return
        }
        succeed(.wroteNew(tagID: tagID), sheetMessage: messages?.success)
    }

    /// The first `zano://tag/<uuid>` id in `message`, if any. Nonisolated: runs inside Core NFC's
    /// completion handler.
    private nonisolated static func zanoTagID(in message: NFCNDEFMessage) -> UUID? {
        for record in message.records {
            if let url = record.wellKnownTypeURIPayload(), let id = NFCTagMapper.tagID(from: url) {
                return id
            }
        }
        return nil
    }
    #endif
}

// MARK: - NFCNDEFReaderSessionDelegate

#if canImport(CoreNFC)
// See `NFCReader`'s identical conformance: `queue: .main` above is what makes `@preconcurrency`
// sound here, not just quiet.
extension NFCWriter: @preconcurrency NFCNDEFReaderSessionDelegate {
    // Step 1: a tag is in the field.
    public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard continuation != nil else { return }
        guard tags.count == 1, let tag = tags.first else {
            // Two tags at once: ask for one, then keep scanning.
            if let text = messages?.multipleTags { session.alertMessage = text }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                session.restartPolling()
            }
            return
        }
        activeTag = tag
        stageHandler?(.connecting)
        session.connect(to: tag) { @Sendable error in
            Task { @MainActor [weak self] in
                self?.didConnect(error: error)
            }
        }
    }

    /// Required by the protocol; not called when `readerSession(_:didDetect:)` is implemented.
    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        finish(.failure(classify(error)))
    }
}
#endif
