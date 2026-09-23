// WatchWorkoutSessionController.swift
// Watch/ZANOWatch
//
// docs/spec.md §5.21: "workout detection is more reliable with HR." This is the piece that makes
// that true, and it is genuinely independent of the WatchConnectivity gap the rest of this
// target's Core-calling code has (see `WatchConnectivityBridge.swift`'s header) — `HealthKit`
// itself IS available on watchOS (unlike `FamilyControls`/`ManagedSettings`/`DeviceActivity`/
// `ActivityKit`), and Apple's shared HealthKit store already syncs heart-rate samples recorded on
// the Watch to the paired iPhone automatically, with no app code required on either side to move
// the bytes. That's exactly the corroboration signal
// `Core/Sources/Core/Verification/GymVerifier.swift`'s `elevatedHeartRateDuringDwell(_:)` already
// reads via `HKSampleQuery` (see that file, same session's earlier reading) — so a person simply
// wearing the Watch and starting a workout session here makes THAT phone-side query far more
// likely to find real samples during their gym dwell window than it would with no paired Watch at
// all. This file does not call `GymVerifier` (can't — no `import Core`); it only makes sure
// HealthKit has real HR data for `GymVerifier` to find once it queries.
//
// ⚠️ API-certainty note (flagged explicitly per this task's brief — this is the single riskiest
// API surface in this whole task, no watchOS SDK available to check against):
//   - `HKHealthStore`, `HKWorkoutConfiguration`, `.requestAuthorization(toShare:read:)` — stable
//     since watchOS 2/3. HIGH confidence.
//   - `HKWorkoutSession(healthStore:configuration:)` (the `throws` initializer, watchOS-only) and
//     `HKLiveWorkoutBuilder`/`HKLiveWorkoutDataSource` — stable since watchOS 5. HIGH confidence
//     these types exist and are named this way.
//   - `session.startActivity(with:)` + `builder.beginCollection(withStart:completion:)` as the
//     start sequence, and `session.stopActivity(with:)` + `session.end()` +
//     `builder.endCollection(withEnd:completion:)` + `builder.finishWorkout(completion:)` as the
//     end sequence — this is the modern (watchOS 8+) multi-sport-session-safe API shape recalled
//     from training knowledge. MEDIUM confidence on exact method names/argument labels — earlier
//     watchOS versions used a simpler `session.startWorkout()`/`session.stopWorkout()` pair with
//     no `with:` argument, and Apple has adjusted this API's shape more than once across watchOS
//     releases. **Flag for a real-SDK check on first build** — this is exactly the kind of API
//     CLAUDE.md working rule 5 says to verify rather than trust from training memory, and this
//     session had no way to do that.
//   - `HKWorkoutSessionDelegate`/`HKLiveWorkoutBuilderDelegate`'s exact method signatures below
//     (`workoutSession(_:didChangeTo:from:date:)`, `workoutSession(_:didFailWithError:)`,
//     `workoutBuilder(_:didCollectDataOf:)`, `workoutBuilder(_:didBegin:)`,
//     `workoutBuilder(_:didEnd:)`) — MEDIUM confidence on the exact set required vs. optional.
//
// Given all of the above, this controller is deliberately conservative: every HealthKit call is
// wrapped so a thrown/failed step degrades to "no wrist HR session running" rather than crashing
// the watch app, and nothing else in this target depends on it succeeding — the rings, lock,
// focus, and gym-dwell-haptic features all work with this file entirely absent.

import Foundation
import HealthKit
import Observation
import os

@MainActor
@Observable
public final class WatchWorkoutSessionController: NSObject {
    public static let shared = WatchWorkoutSessionController()

    public enum State: Equatable {
        case idle
        case requestingAuthorization
        case running(startedAt: Date)
        case ended
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// Most recent heart-rate sample collected during the running session, in BPM. `nil` until
    /// the first `HKLiveWorkoutBuilder` HR callback arrives — HealthKit's sensor takes a few
    /// seconds to report the first reading after a session starts.
    public private(set) var latestHeartRateBPM: Double?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let logger = Logger(subsystem: "com.zano.app.watch", category: "WatchWorkoutSessionController")

    private override init() {
        super.init()
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - Start

    /// Requests HealthKit authorization (first call only — subsequent calls are a fast no-op per
    /// `HKHealthStore`'s own caching) and starts a workout session so heart-rate samples begin
    /// recording into the shared HealthKit store immediately (see this file's header for why that
    /// alone is the point, independent of anything else in this session actually reading it back).
    ///
    /// `activityType: .traditionalStrengthTraining` — a reasonable default for "started from the
    /// gym tab on the wrist" per docs/spec.md §3's Workout (gym) goal row; not `.functionalStrength
    /// Training`/`.mixedCardio`/etc. `Core` has no per-goal activity-type model to read here (no
    /// `import Core`), so this is a fixed, documented choice rather than a per-workout picker —
    /// flagged as a product simplification, not a bug, consistent with CLAUDE.md's "don't add
    /// abstractions beyond what the current session's scope requires".
    public func start() {
        guard !isRunning else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .failed("HealthKit is not available on this device.")
            return
        }

        state = .requestingAuthorization
        // `HKQuantityType.quantityType(forIdentifier:)` — the same optional-returning lookup
        // `GymVerifier.swift`'s `elevatedHeartRateDuringDwell(_:)` already uses (this codebase's
        // one other HealthKit call site), rather than a newer `HKQuantityType(.heartRate)`
        // initializer sugar this task could not confirm is available at this target's
        // `deploymentTarget: "10.0"` (watchOS 10 / iOS 17) — see this file's header note.
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            state = .failed("Heart rate is not a supported HealthKit type on this device.")
            return
        }
        let workoutType = HKObjectType.workoutType()

        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType, workoutType]) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.error("HealthKit authorization failed: \(String(describing: error), privacy: .public)")
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard success else {
                    self.state = .failed("HealthKit authorization was not granted.")
                    return
                }
                self.beginSession()
            }
        }
    }

    private func beginSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let now = Date.now
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { [weak self] success, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.logger.error("beginCollection failed: \(String(describing: error), privacy: .public)")
                        self.state = .failed(error.localizedDescription)
                        return
                    }
                    self.state = .running(startedAt: now)
                    HapticsPlayer.playWorkoutStart()
                }
            }
        } catch {
            logger.error("Failed to start HKWorkoutSession: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - End

    public func end() {
        guard let session, isRunning else { return }
        session.end()
        // The rest of teardown (`endCollection`/`finishWorkout`) happens in the
        // `HKWorkoutSessionDelegate` callback once the session actually reaches `.ended` — ending
        // is not synchronous.
    }

    private func finishAndTearDown() {
        guard let builder else {
            state = .ended
            return
        }
        let endDate = Date.now
        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.error("endCollection failed: \(String(describing: error), privacy: .public)")
                }
                builder.finishWorkout { [weak self] workout, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.logger.error("finishWorkout failed: \(String(describing: error), privacy: .public)")
                        }
                        self.state = .ended
                        self.session = nil
                        self.builder = nil
                        HapticsPlayer.playWorkoutStop()
                    }
                }
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
//
// Delivered on an arbitrary HealthKit background queue, not guaranteed main — same
// nonisolated-then-hop pattern as `WatchConnectivityBridge`'s `WCSessionDelegate` conformance, for
// the same Swift 6 strict-concurrency reason (see that file's header comment).

// `@preconcurrency` on both HealthKit delegate conformances below, same reasoning as
// `WatchConnectivityBridge`'s `@preconcurrency WCSessionDelegate` conformance (see that file's
// comment) — `HKWorkoutSession`/`HKLiveWorkoutBuilder` callbacks also arrive off-main-thread from a
// pre-Swift-6 delegate protocol.
extension WatchWorkoutSessionController: @preconcurrency HKWorkoutSessionDelegate {
    public nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            if toState == .ended {
                self.finishAndTearDown()
            }
        }
    }

    public nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("HKWorkoutSession failed: \(String(describing: error), privacy: .public)")
            self.state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutSessionController: @preconcurrency HKLiveWorkoutBuilderDelegate {
    public nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType)
        else { return }
        let statistics = workoutBuilder.statistics(for: heartRateType)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = statistics?.mostRecentQuantity()?.doubleValue(for: unit)

        Task { @MainActor in
            if let bpm {
                self.latestHeartRateBPM = bpm
            }
        }
    }

    public nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No event-driven UI in this task's scope — present only because
        // `HKLiveWorkoutBuilderDelegate` declares it as a required method.
    }
}
