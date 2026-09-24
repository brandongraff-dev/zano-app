// EntitlementGate.swift
// Core / Monetization
//
// The hard paywall's enforcement point (docs/spec.md §21, decision 2026-09-23: no free tier — every
// user starts the trial or subscribes before reaching the app). Onboarding's paywall screen is the
// front door; this is what keeps the door shut afterwards, when a trial or subscription ends.
//
// Two rules matter more than the gate itself:
//
// 1. FAIL OPEN when the answer is unknown. Offline, no RevenueCat key (development / CI / any build
//    made before the account exists), SDK not linked: `RevenueCatManager.entitlementCheck()` says
//    `.unavailable`, and this treats that as entitled. A paying user must never be locked out of the
//    app because a network call failed.
//
// 2. A LAPSED SUBSCRIPTION MUST NEVER TRAP A USER BEHIND A SHIELD (spec §21 safety rule, CLAUDE.md
//    "never trap the user"). When the check definitively says "not subscribed", any active lock is
//    released *before* the paywall is shown, so the user is never stuck unable to open their own
//    apps because of a billing state. The release goes through `LockEngineManager.emergencyUnlock`
//    directly — the app's always-available exit — and deliberately applies no streak penalty.

import Foundation
import Observation

@MainActor
@Observable
public final class EntitlementGate {
    public static let shared = EntitlementGate()

    public enum State: Equatable, Sendable {
        /// Not checked yet this launch. Treated as entitled (never block on an unknown).
        case unknown
        case entitled
        /// A definitive "no active trial or subscription".
        case lapsed
    }

    public private(set) var state: State = .unknown

    /// `true` when the app must show the paywall instead of its content.
    public var isBlocking: Bool { state == .lapsed }

    private init() {}

    /// Re-reads the entitlement. Cheap; call on launch and whenever the app becomes active, and after
    /// a purchase or restore.
    public func refresh() async {
        switch await RevenueCatManager.shared.entitlementCheck() {
        case .entitled:
            state = .entitled
        case .notEntitled:
            state = .lapsed
            await releaseAnyActiveLock()
        case .unavailable:
            // Fail open — see this file's header. Keep a definitive earlier answer if we have one.
            if state == .unknown { state = .entitled }
        }
    }

    /// For feature checks (`TierGating`): everything is available to a subscriber, and nothing is
    /// blocked on an unknown.
    public func isEntitledNow() async -> Bool {
        if state == .unknown { await refresh() }
        return state != .lapsed
    }

    private func releaseAnyActiveLock() async {
        guard let sessionID = SharedDefaults.activeLockSessionID else { return }
        try? await LockEngineManager.shared.emergencyUnlock(sessionID: sessionID)
    }
}

/// What `RevenueCatManager.entitlementCheck()` could establish.
public enum EntitlementCheck: Sendable, Equatable {
    case entitled
    case notEntitled
    /// Couldn't tell: offline, RevenueCat not linked, or no API key yet.
    case unavailable
}
