// WatchStateStore.swift
// Watch/ZANOWatch
//
// Holds the latest `WatchStateSnapshot` the watch knows about, drives every view that reads it,
// persists it locally so the watch has *something* to show cold-launched with no phone in range,
// and is the single place that decides "did the gym dwell threshold just get hit" for docs/spec.md
// §5.21's haptic requirement.
//
// ⚠️ App Group scope (flagged per this task's knownIssues — a common, easy-to-get-wrong point):
// `UserDefaults(suiteName: "group.com.zano.app")` on watchOS opens a container that is LOCAL TO
// THIS APPLE WATCH. App Groups do not sync their contents between a paired iPhone and Watch —
// each physical device has its own separate copy of "group.com.zano.app", the same identifier
// string but not the same bytes. So this class's persistence exists ONLY so a future WidgetKit
// complication extension running on this same watch (see `ComplicationPlaceholder.swift`'s header
// comment — that extension target doesn't exist yet, project.yml's job) can read the same
// last-known snapshot this app process wrote, mirroring the exact pattern CLAUDE.md already uses
// for `ZANOWidgets` on iOS ("Extensions... read state from the App Group only"). It is NOT how a
// snapshot gets onto the watch in the first place — that is entirely `WatchConnectivityBridge`'s
// job (a real cross-device transport), and losing connectivity does not make this class fall back
// to reading anything from the iPhone's own storage — there is no such path.

import Foundation
import Observation
import os

@MainActor
@Observable
public final class WatchStateStore {
    public static let shared = WatchStateStore()

    public private(set) var snapshot: WatchStateSnapshot

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.zano.app.watch", category: "WatchStateStore")

    /// Same App Group identifier `Core/Sources/Core/Store/ModelContainer+AppGroup.swift`'s
    /// `AppGroup.identifier` uses on iOS — kept as a literal (not imported) for the same reason
    /// every other cross-reference in this target is a literal: no `import Core` is possible here
    /// (see `WatchTheme.swift`'s header comment). Already declared as this watch target's
    /// `com.apple.security.application-groups` entitlement in `project.yml`'s `ZANOWatch` block.
    /// `nonisolated`: read by `readSnapshotForComplication()` below, which must itself be callable
    /// with no main-actor hop (a future complication extension process has no reason to ever be
    /// on this app's main actor) — an immutable `String` constant carries no actor-isolated state
    /// to protect, so opting it out of this class's `@MainActor` default is safe.
    private nonisolated static let appGroupIdentifier = "group.com.zano.app"
    private nonisolated static let snapshotDefaultsKey = "watch.lastKnownStateSnapshot"

    private init() {
        let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
        self.defaults = defaults
        self.snapshot = Self.readPersistedSnapshot(from: defaults) ?? .empty
    }

    /// Called by `WatchConnectivityBridge` whenever a new `WatchStateSnapshot` arrives from the
    /// phone. Fires the docs/spec.md §5.21 "verified" haptic exactly on the `false` → `true` edge
    /// of `gymDwell.isVerified` — not on every snapshot where it happens to already be `true`
    /// (which would re-fire the haptic on every routine sync while someone's mid-dwell-but-already-
    /// verified, which is not "the moment the threshold is hit").
    public func apply(_ newSnapshot: WatchStateSnapshot) {
        let wasVerified = snapshot.gymDwell?.isVerified ?? false
        let isNowVerified = newSnapshot.gymDwell?.isVerified ?? false
        let crossedThreshold = isNowVerified && !wasVerified

        snapshot = newSnapshot
        persist(newSnapshot)

        if crossedThreshold {
            logger.notice("Gym dwell threshold reached (\(newSnapshot.gymDwell?.elapsedMinutes ?? -1, privacy: .public) min) — playing verified haptic.")
            HapticsPlayer.playVerified()
        }
    }

    /// Optimistic local update after `WatchConnectivityBridge.send(.startLock/.startFocusSession)`
    /// succeeds, so the UI reflects "requested" immediately rather than waiting for the phone's
    /// next snapshot push — reconciled/overwritten by the next real `apply(_:)` regardless, so a
    /// stale optimistic guess can never persist past one real sync.
    public func markFocusSessionPending(goalTitle: String, plannedMinutes: Int) {
        // Uses a nil UUID placeholder until the phone assigns/confirms a real `sessionID` in its
        // next snapshot — `FocusView`/`StartActionsView` treat a `.distantPast`-free but
        // zero-second snapshot as "pending", not "running", by checking `secondsRemaining > 0 ||
        // pending`. Kept intentionally minimal: this is UI-affordance sugar, not source of truth.
        let pending = WatchFocusSessionSnapshot(
            sessionID: UUID(),
            goalTitle: goalTitle,
            plannedMinutes: plannedMinutes,
            secondsRemaining: plannedMinutes * 60,
            isPaused: false
        )
        var next = snapshot
        next.focusSession = pending
        snapshot = next
        // Deliberately NOT persisted — this is a transient, optimistic guess; only a real
        // `apply(_:)` from the phone should ever be written to disk, so a killed-and-relaunched
        // watch app never shows a phantom "pending" state that was never confirmed.
    }

    // MARK: - Persistence

    private func persist(_ snapshot: WatchStateSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Self.snapshotDefaultsKey)
        } catch {
            logger.error("Failed to persist WatchStateSnapshot: \(String(describing: error), privacy: .public)")
        }
    }

    /// `nonisolated` for the same reason as `appGroupIdentifier` above — this is a pure function of
    /// its `UserDefaults` argument (no access to `self`/any actor-isolated instance state), so it's
    /// callable from `readSnapshotForComplication()`'s `nonisolated` context with no actor hop.
    private nonisolated static func readPersistedSnapshot(from defaults: UserDefaults) -> WatchStateSnapshot? {
        guard let data = defaults.data(forKey: snapshotDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(WatchStateSnapshot.self, from: data)
    }

    /// Complication-side read helper. A `TimelineProvider` running in a *separate* WidgetKit
    /// extension process (once that target exists — see `ComplicationPlaceholder.swift`) cannot
    /// reach this class's in-memory `shared` instance; it can only open the same on-device App
    /// Group suite and decode what was last persisted here. `nonisolated` + `static` so it needs
    /// no actor hop and no dependency on `WatchStateStore.shared` ever having been constructed in
    /// that process.
    public nonisolated static func readSnapshotForComplication() -> WatchStateSnapshot {
        let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
        return readPersistedSnapshot(from: defaults) ?? .empty
    }
}
