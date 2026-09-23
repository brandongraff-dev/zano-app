// Core/Sources/Core/Retention/CalendarAwareness.swift
//
// docs/spec.md §9.7 Schedule & Travel Awareness:
//   "New city detection (coarse) → Travel mode suggestion. Calendar density (opt-in) → suggest
//   lighter goals on packed days." — this file is the *second* half only: calendar density. New
//   city detection is `TravelMode.swift` (this same directory, same wave — read for the sibling
//   pattern this file follows) and is not duplicated here; this file never touches location, and
//   `TravelMode` never touches EventKit.
// docs/spec.md §9.2 Slip Prediction lists "calendar density (if Calendar access granted)" among
// that model's own input features. This file does not implement Slip Prediction (§9.2 is Session
// 12/ML-service scope, out of this task's file list) — it only supplies the one signal that
// section names. A future caller can fold `isPackedDay(_:)` into the `isHighRisk: Bool` that
// `PlanB.offer(for:on:isHighRisk:)` (`Core/Sources/Core/Retention/PlanB.swift`, read for this
// task, not owned) already takes as an opaque, already-decided input — either directly, as a
// simple v1 heuristic before the real Slip Prediction model exists, or as one feature folded into
// that model's own output once it does. This file never calls `PlanB` or anything else itself; it
// only exposes the read signal, matching `TravelMode`'s own "read API only, cross-module wiring
// is a future session's job" convention (see that file's header).
//
// Opt-in only (spec §9.7's own parenthetical; spec §24 Safety/Legal already treats every
// sensitive-data permission this app requests as ask-only-when-the-user-asked-for-it — e.g.
// Location: "When in Use first... only at gym setup with a clear explanation"):
// `isPackedDay(_:)` NEVER triggers an EventKit authorization prompt itself. It only reads calendar
// events when both (a) this file's own persisted opt-in flag is `true` and (b)
// `EKEventStore.authorizationStatus(for: .event)` is currently `.fullAccess`, checked fresh on
// every call. The only method in this file that ever calls `requestFullAccessToEvents()` is
// `optIn()`, and nothing else in this file calls `optIn()` — it exists to be called from an
// explicit user action elsewhere.
//
// TODO(follow-up, Settings/Onboarding UI session; not this task's file list): there is no UI
// toggle yet anywhere in `App/ZANO/Features` that calls `CalendarAwareness.shared.optIn()`. Until
// one exists, `isOptedIn()` can never become `true` and `isPackedDay(_:)` always returns `false` —
// a safe (not broken) default, the same "the feature simply never fires until its collector
// exists" posture `TravelMode`'s header documents for its own still-missing location collector.
// That Settings screen should also surface `optOut()` (this file's opt-in flag has no other way to
// become `false` again, short of reinstalling the app) and explain that declining the system
// prompt, or revoking access later in iOS Settings, is respected automatically — `isPackedDay(_:)`
// re-checks live `authorizationStatus()` on every call, never the persisted flag alone. Copy for
// that toggle belongs in `Core/Sources/Core/Copy` (a future `Copy.calendarAwareness` or similar
// area, following the `Copy.<area>` umbrella pattern in `Copy.swift`/`OnboardingCopy.swift`) — not
// hardcoded there or here.
//
// KNOWN GAP flagged for that same follow-up session, not fixed here (out of this task's file
// list — `project.yml`/Info.plist): `project.yml`'s `ZANO` target has no
// `NSCalendarsFullAccessUsageDescription` entry alongside its existing
// `NSLocationWhenInUseUsageDescription`/`NSHealthShareUsageDescription`/etc. keys. Calling
// `optIn()` (which calls `EKEventStore.requestFullAccessToEvents()`) before that key exists will
// crash the process immediately — Apple's documented behavior for requesting a protected resource
// with no usage-description string in Info.plist. The Settings toggle must not ship without it.
//
// Relationship to `TravelMode.swift` (read for this task): same directory, same wave, same
// "opt-in signal engine" shape — both are `@MainActor` singletons backed by their own small slice
// of App-Group-`UserDefaults`-suite state (never `Store/SharedDefaults.swift` itself, keyed
// distinctly from every other engine's keys so none of them collide despite sharing the same
// suite), both split a pure/testable calculation out from the I/O-touching shell around it (the
// same split `GymAutoDetect.clusterVisits` pioneered in this codebase), and neither ever mutates a
// `Goal`/`DailyPlan`/streak on its own — each only exposes a read signal for another call site to
// act on.
//
// UNVERIFIED (no Mac/compiler this task — CLAUDE.md rule 5): this task's training-knowledge best
// guess is that `EKEventStore.requestFullAccessToEvents() async throws -> Bool` and the
// `.fullAccess`/`.writeOnly` `EKAuthorizationStatus` cases have existed since iOS 17 (this
// package's minimum — `project.yml`), replacing the older `requestAccess(to:completion:)` /
// `.authorized` pair those cases superseded. Not checked against current Apple documentation —
// flagged again in `knownIssues`.

import Foundation
import EventKit
import os

/// Reads calendar event density for a given day (docs/spec.md §9.7: "Calendar density (opt-in) →
/// suggest lighter goals on packed days") behind an explicit, persisted opt-in — never requests or
/// relies on Calendar access on its own. See this file's header for the opt-in contract, the
/// still-missing Settings toggle, and the still-missing Info.plist key that toggle depends on.
///
/// `@MainActor`, matching every other engine in this same directory (`TravelMode`, `ComebackMode`,
/// `StreakEngine`, `AdaptiveGoalEngine`) for the same reason each documents at its own
/// declaration: a plain `final class` singleton needs either `Sendable` conformance (unrealistic
/// for a type owning an `EKEventStore`, itself not documented `Sendable`) or global-actor
/// isolation under Swift 6 strict concurrency, and every realistic call site is already
/// `@MainActor` or happy to `await` a hop onto it.
@MainActor
public final class CalendarAwareness {
    public static let shared = CalendarAwareness()

    // MARK: - Tunables (spec §9.7 gives the behavior, not an exact number — this task's own
    // calibration, flagged here rather than presented as spec text, matching `TravelMode`'s/
    // `PlanB`'s own "Tunables"/"v1 constants" sections' convention).

    /// A day with at least this many non-all-day events counts as "packed" — spec §9.7's own
    /// words are just "packed days," no exact count. All-day entries (out-of-office markers,
    /// holidays, birthdays) are excluded from the count: they don't represent the back-to-back-
    /// meetings crunch spec means by "packed," and counting them would flag a day as packed for a
    /// reason that has nothing to do with how little free time the user actually has.
    nonisolated public static let packedDayEventThreshold = 5

    private let logger = Logger(subsystem: "com.zano.app.Core", category: "CalendarAwareness")

    /// Not documented `Sendable` by Apple; safe to store here only because every access to it goes
    /// through this `@MainActor` class's own isolation — same reasoning `TravelMode`'s
    /// `ModelContext` doc comment gives for its own non-`Sendable` SDK-owning stored property.
    /// (`GymAutoDetect`'s `HKHealthStore` takes the opposite approach — constructed fresh per call
    /// instead of stored — only because that type has no actor isolation of its own to lean on;
    /// this type does.)
    private let eventStore = EKEventStore()

    private let calendar = Calendar.current

    /// Separate, App-Group-backed `UserDefaults` instance (same suite `Store/SharedDefaults.swift`
    /// uses, a different file this task does not own) — same convention `TravelMode`/
    /// `ComebackMode` already use for their own small pieces of state that have nowhere else to
    /// live. Keyed distinctly from every key those files or `SharedDefaults` define so none of
    /// them can ever collide despite sharing the same underlying suite.
    private let calendarDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let optedInKey = "com.zano.app.calendarAwareness.optedIn"

    /// `internal`, not `private`, only so `CoreTests` can construct an isolated instance — though a
    /// real `EKEventStore` still talks to the live system Calendar database even in tests (there is
    /// no in-memory fake for it the way `ModelContainer(inMemory:)` exists for SwiftData), so a
    /// test against this initializer should stick to ``isPacked(eventCount:threshold:)``, the pure
    /// half, rather than exercising `isPackedDay(_:)` end to end.
    init() {}

    // MARK: - Opt-in state

    /// Whether the user has explicitly turned this feature on. `false` until a caller (the not-
    /// yet-built Settings toggle — see this file's header) calls ``optIn()`` for the first time.
    /// Reading this alone is not sufficient to know whether calendar events can actually be read
    /// right now — the user may have opted in here and later revoked access in iOS Settings, or
    /// answered the system prompt with "Don't Allow" — ``isPackedDay(_:)`` always re-checks live
    /// ``authorizationStatus()`` too, never this flag by itself.
    public func isOptedIn() async -> Bool {
        calendarDefaults.bool(forKey: Self.optedInKey)
    }

    /// The live, current-as-of-this-call EventKit authorization state — never cached, since it can
    /// change underneath the app at any time from iOS Settings. `nonisolated`: a plain,
    /// synchronous read of EventKit's own process-wide state, not this instance's.
    public nonisolated static func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// The user explicitly turned this feature on. Intended caller: the Settings toggle noted in
    /// this file's header — no other call site in this codebase should invoke this.
    ///
    /// Persists the opt-in flag *before* requesting EventKit's iOS 17 full-access prompt, so a
    /// declined/failed request still leaves ``isOptedIn()`` `== true` — the user's *intent* was
    /// still "yes, ask me." That's a deliberate distinction from "actually authorized right now,"
    /// which is exactly why `isPackedDay(_:)` checks both independently rather than trusting this
    /// flag alone. Flagged here as this task's own design choice, not spec-mandated: a caller that
    /// wants "declined the prompt" to also flip `isOptedIn()` back to `false` should call
    /// ``optOut()`` itself when `optIn()` returns `false`.
    ///
    /// Rethrows whatever `requestFullAccessToEvents()` throws rather than wrapping it in a custom
    /// error type — this file adds no translation layer over EventKit's own error (CLAUDE.md: no
    /// abstractions beyond what the current session's scope requires); a caller only needs to know
    /// it failed, mirroring `TravelMode.acceptTravelMode`'s own "an explicit action needs to know
    /// why it couldn't" convention for its own `throws`.
    ///
    /// - Returns: `true` if the user granted full Calendar access, `false` if declined. Either
    ///   outcome already degrades safely: `isPackedDay(_:)` returns `false` whenever authorization
    ///   isn't `.fullAccess`, regardless of why.
    @discardableResult
    public func optIn() async throws -> Bool {
        calendarDefaults.set(true, forKey: Self.optedInKey)
        let granted = try await eventStore.requestFullAccessToEvents()
        logger.notice("Calendar Awareness opt-in: access \(granted ? "granted" : "declined", privacy: .public).")
        return granted
    }

    /// "Not now"/"turn this off" — spec §8 rule 9 ("no shame") applies here the same way it does to
    /// every other opt-in suggestion in this codebase: declining or turning this back off has no
    /// penalty anywhere in this file. Clears only this file's own opt-in flag; it cannot revoke the
    /// OS-level Calendar grant itself (only the user, in iOS Settings, can do that) — that's fine,
    /// since `isPackedDay(_:)` checks this flag first and short-circuits before ever touching
    /// EventKit once it's `false`.
    public func optOut() async {
        calendarDefaults.set(false, forKey: Self.optedInKey)
    }

    // MARK: - Packed-day signal

    /// Pure, synchronous, side-effect-free — same split `TravelMode.evaluate`/
    /// `GymAutoDetect.clusterVisits` use in this codebase: the actual "is this count packed"
    /// decision is unit-testable without a real `EKEventStore`/device Calendar database.
    /// `nonisolated`: touches no actor-isolated state, everything it needs is a parameter.
    nonisolated public static func isPacked(
        eventCount: Int,
        threshold: Int = CalendarAwareness.packedDayEventThreshold
    ) -> Bool {
        eventCount >= threshold
    }

    /// docs/spec.md §9.7: "Calendar density (opt-in) → suggest lighter goals on packed days."
    /// `false` whenever this file isn't allowed to read the calendar for any reason — not opted
    /// in, not authorized, or genuinely few events that day — never `true` by assumption. This is
    /// the one signal this file exposes; folding it into an actual `isHighRisk: Bool` for
    /// `PlanB.offer(for:on:isHighRisk:)` (alongside Slip Prediction's other §9.2 features) is a
    /// future caller's job, not this method's — see this file's header.
    ///
    /// Known perf caveat (flagged in `knownIssues`, not fixed here): `EKEventStore.events(matching:)`
    /// is a synchronous, disk-backed EventKit call. This method is `async` and `@MainActor`-
    /// isolated, so that call still runs on the main actor's executor — acceptable for one day's
    /// worth of events (spec's own "packed day" framing implies a handful to a few dozen, not a
    /// bulk query), but a caller checking many days at once (e.g. a week-ahead view) should not
    /// call this in a tight loop from a scroll-performance-sensitive context without first
    /// profiling on a real device, which this task cannot do.
    ///
    /// - Parameter date: Any instant within the local calendar day to check; normalized internally
    ///   to that day's `[startOfDay, nextStartOfDay)` window, matching `ComebackMode`'s/
    ///   `AdaptiveGoalEngine`'s own local-day normalization convention.
    public func isPackedDay(_ date: Date) async -> Bool {
        guard await isOptedIn() else { return false }
        guard Self.authorizationStatus() == .fullAccess else { return false }

        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return false }

        // `calendars: nil` searches every calendar the user has granted access to (spec §9.7 says
        // "Calendar density," not "density in one specific calendar") — this task's own reading,
        // flagged as a v1 simplification rather than exact spec text; a future session could add a
        // per-calendar opt-in list if all-calendars density proves too noisy in practice.
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
        let count = events.filter { !$0.isAllDay }.count

        return Self.isPacked(eventCount: count)
    }
}
