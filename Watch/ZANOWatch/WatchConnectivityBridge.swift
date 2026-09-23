// WatchConnectivityBridge.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21 ("Apple Watch": "start focus/lock from the wrist") and §11's architecture
// note that ZANOWatch is v3/speculative. This is the one piece of plumbing that makes both true:
// since `Watch/ZANOWatch` cannot `import Core` (see `WatchTheme.swift`'s header comment for the
// full reason — `Core/Package.swift` doesn't declare watchOS, and several of `Core`'s frameworks
// don't exist on watchOS SDK regardless), the watch cannot call `LockEngineManager.startLock` or
// `FocusSessionVerifier.startSession` directly. It asks the iPhone to, over `WatchConnectivity`.
//
// ⚠️ KNOWN GAP (flagged per this task's brief and in knownIssues): this file is the WATCH side
// only. There is currently no matching `WCSessionDelegate` on the iPhone side to receive
// `WatchToPhoneRequest` and actually call into `LockEngineManager`/`FocusSessionVerifier`, or to
// push `WatchStateSnapshot` updates back down via `updateApplicationContext`/`sendMessage`. That
// receiver belongs in `Core/Sources/Core/Sync/*.swift` (spec §11: "Sync (Supabase client, outbox
// pattern)" is the closest existing home for a second, WatchConnectivity-flavored sync path) or
// possibly `App/ZANO`'s app-delegate-equivalent — both are explicitly forbidden paths for this
// task run (see this task's own instructions). Until that receiver exists, every `send(_:)` call
// below reaches a real, activated `WCSession` and is delivered to iOS's WatchConnectivity
// framework correctly, but nothing on the phone acts on it yet — requests will appear to "send
// successfully" (no error from `WCSession` itself) while doing nothing. The watch UI's confirmation
// copy (`Copy.watch.lockRequestedConfirmation` etc.) reflects "the phone was asked", not "the lock
// actually started" for exactly this reason — see `StartActionsView.swift`.
//
// API-certainty note (flagged per this task's brief — "be explicit about which calls are least
// certain", no watchOS SDK available to check against): `WCSession` itself, `.default`,
// `.isSupported()`, `.activate()`, `.isReachable`, `.sendMessage`, `.transferUserInfo`, and
// `.updateApplicationContext` are stable, long-standing WatchConnectivity API (iOS 9 / watchOS
// 2+) — HIGH confidence. `WCSessionDelegate`'s exact *required-vs-optional* member set on watchOS
// specifically (this file assumes only `session(_:activationDidCompleteWith:error:)` is required,
// and that `sessionDidBecomeInactive`/`sessionDidDeactivate` are iOS-only — watchOS only ever
// pairs with exactly one iPhone, so there's nothing for "became inactive" to mean there) is
// MEDIUM confidence — verify against a real watchOS SDK on first build.

import Foundation
import Observation
import os
import WatchConnectivity

/// Owns the watch's one `WCSession` and turns it into `@Observable` state
/// (`isReachable`/`activationState`/`lastSendError`) plus two operations: `send(_:)` a
/// `WatchToPhoneRequest`, and forward any `WatchStateSnapshot` the phone pushes down into
/// `WatchStateStore.shared.apply(_:)`.
///
/// `@MainActor` + `NSObject` + `WCSessionDelegate`: `WCSessionDelegate`'s callback methods are
/// invoked by WatchConnectivity on its own private queue, not necessarily the main thread — they
/// are NOT actor-isolated by the protocol itself (it's an Objective-C protocol ZANO doesn't own,
/// so it can't be annotated `@MainActor`). Per this codebase's `write-swift` Swift 6 concurrency
/// guidance ("bridging old callback APIs: mark the method `nonisolated` and hop back"), every
/// delegate method below is `nonisolated` and immediately re-enters the main actor with
/// `Task { @MainActor in ... }` before touching any of this class's `@Observable` state — never
/// `nonisolated(unsafe)`, and never `MainActor.assumeIsolated` (that asserts the calling thread
/// already *is* the main actor, which `WCSessionDelegate` callbacks are not guaranteed to be).
@MainActor
@Observable
public final class WatchConnectivityBridge: NSObject {
    public static let shared = WatchConnectivityBridge()

    /// `true` once the iPhone is nearby, running ZANO, and reachable for interactive messaging
    /// (`WCSession.isReachable`). `StartActionsView` uses this to show
    /// `Copy.watch.noConnectionBanner` instead of letting a lock/focus request silently queue.
    public private(set) var isReachable = false
    public private(set) var activationState: WCSessionActivationState?
    /// The most recent send failure, for a lightweight inline error banner. Cleared on the next
    /// successful send.
    public private(set) var lastSendError: String?

    /// `nil` on any device/simulator where `WCSession.isSupported()` is `false` — every method
    /// below no-ops (rather than force-unwrapping) so the rest of the app still renders using
    /// whatever `WatchStateStore` last persisted, instead of crashing.
    private let session: WCSession?

    private let logger = Logger(subsystem: "com.zano.app.watch", category: "WatchConnectivityBridge")

    private override init() {
        self.session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
    }

    /// Call once, early in `ZANOWatchApp`'s lifetime (its `init`). Idempotent per `WCSession`'s
    /// own contract — a second `activate()` call is a documented no-op if already active/activating.
    public func activate() {
        guard let session else {
            logger.notice("WatchConnectivity unsupported on this device; ZANOWatch will run watch-local-only.")
            return
        }
        session.activate()
    }

    /// Sends a `WatchToPhoneRequest` to the iPhone. Prefers interactive `sendMessage` (delivered
    /// immediately, but requires `isReachable`); if the phone isn't currently reachable, falls
    /// back to `transferUserInfo`, which iOS queues and delivers once connectivity resumes (e.g.
    /// the phone comes back in Bluetooth/Wi-Fi range) — so tapping "Start Lock" on the wrist with
    /// the iPhone briefly out of range still eventually reaches it instead of being silently
    /// dropped, at the cost of losing the immediate reply/confirmation `sendMessage` would give.
    public func send(_ request: WatchToPhoneRequest) {
        guard let session else {
            lastSendError = Copy.watch.connectivityUnsupported
            return
        }
        guard session.activationState == .activated else {
            lastSendError = Copy.watch.connectivityActivating
            session.activate()
            return
        }

        if session.isReachable {
            session.sendMessage(request.asMessage, replyHandler: { [weak self] _ in
                Task { @MainActor in self?.lastSendError = nil }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.logger.error("sendMessage failed: \(String(describing: error), privacy: .public)")
                    self?.lastSendError = error.localizedDescription
                }
            })
        } else {
            // Best-effort background delivery — see doc comment above. `transferUserInfo` has no
            // completion/error callback for an individual transfer, so this can't distinguish
            // "queued" from "will eventually fail"; `lastSendError` reflects only what's knowable
            // right now (phone unreachable), not the eventual outcome.
            _ = session.transferUserInfo(request.asMessage)
            lastSendError = Copy.watch.noConnectionBanner
        }
    }

    // MARK: - Applying a received snapshot

    /// Shared by both `didReceiveApplicationContext` and `didReceiveMessage` below — the phone may
    /// reasonably use either transport for the same `WatchStateSnapshot` payload (application
    /// context for routine "latest state" syncs; an interactive message for something the phone
    /// wants the watch to see immediately, e.g. right after `GymVerifier` crosses the dwell
    /// threshold, per docs/spec.md §5.21's haptic requirement — see `WatchStateStore.apply(_:)`
    /// for where that haptic actually fires).
    private func applySnapshotPayload(_ payload: [String: Any]) {
        guard let data = payload[Self.snapshotPayloadKey] as? Data else { return }
        do {
            let snapshot = try JSONDecoder().decode(WatchStateSnapshot.self, from: data)
            WatchStateStore.shared.apply(snapshot)
        } catch {
            logger.error("Failed to decode WatchStateSnapshot: \(String(describing: error), privacy: .public)")
        }
    }

    /// The single dictionary key both directions of the snapshot payload agree on. Not part of
    /// `WatchStateSnapshot` itself (that type is the *value*, not the transport envelope) — kept
    /// here since this file owns both send and receive sides of that envelope. A real phone-side
    /// sender must use this exact key.
    static let snapshotPayloadKey = "zano.watchStateSnapshot"
}

// MARK: - WCSessionDelegate

// `@preconcurrency` on this conformance: `WCSessionDelegate`'s parameters (`WCSession` itself,
// `[String: Any]`) predate Swift 6 strict concurrency and are not fully `Sendable`-audited in the
// SDK's module interface as of this task's training knowledge. Combined with `nonisolated` +
// `Task { @MainActor in ... }` on every method below, `@preconcurrency` is what keeps the compiler
// from hard-erroring on capturing those legacy types into a main-actor-isolated closure, per this
// codebase's `write-swift` Swift 6 migration guidance ("bridging old callback APIs... `@preconcurrency`
// on the conformance is the shorthand"). MEDIUM confidence this is the exact right spelling for the
// current WatchConnectivity module's concurrency annotations — flagged for a real-SDK check on
// first build, same as this file's other watchOS-specific notes above.
extension WatchConnectivityBridge: @preconcurrency WCSessionDelegate {
    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = session.isReachable
            if let error {
                self.logger.error("WCSession activation finished with error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    public nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applySnapshotPayload(applicationContext)
        }
    }

    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.applySnapshotPayload(message)
        }
    }
}
