// Core/Tests/CoreTests/FocusSessionPersistenceTests.swift
//
// Tests the launch-blocker fixes in Core/Sources/Core/Verification/FocusSessionVerifier.swift
// (docs/design/unfinished-audit-2026-10-02.md L3/L4/L5/L8; spec section 3 Focus session row):
// a running session persisted in the App Group survives a relaunch and verifies once its planned
// active time has elapsed; leaving the app pauses an in-app session and returning resumes it.
//
// Each test uses its own in-memory store and its own `UserDefaults` suite, and seeds sessions
// through the persisted record (no `startSession`), so no Live Activity is ever requested.

import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor
private final class VerifiedSpy {
    var goalIDs: [UUID] = []
}

@MainActor
private struct FocusHarness {
    let container: ModelContainer
    let store: FocusSessionStore
    let spy: VerifiedSpy
    let verifier: FocusSessionVerifier
    let goalID: UUID

    init() throws {
        let container = try ModelContainer.makeAppGroupContainer(inMemory: true)
        let context = ModelContext(container)
        let user = User()
        context.insert(user)
        let goal = Goal(type: .focusSession, title: "Focus", targetValue: 25, verificationTier: .a, user: user)
        context.insert(goal)
        try context.save()

        let suite = "test.focusSession.\(UUID().uuidString)"
        let store = FocusSessionStore(defaults: UserDefaults(suiteName: suite)!)
        let spy = VerifiedSpy()
        self.container = container
        self.store = store
        self.spy = spy
        self.goalID = goal.id
        self.verifier = FocusSessionVerifier(modelContainer: container, store: store) { goalID in
            spy.goalIDs.append(goalID)
        }
    }

    func seed(startedMinutesAgo: Double, plannedMinutes: Int = 25, pausesWhenAppLeaves: Bool = false, now: Date) -> UUID {
        let record = PersistedFocusSession(
            id: UUID(),
            goalID: goalID,
            plannedMinutes: plannedMinutes,
            startedAt: now.addingTimeInterval(-startedMinutesAgo * 60),
            isPlanB: false,
            pausesWhenAppLeaves: pausesWhenAppLeaves,
            activityID: nil
        )
        store.save(store.load() + [record])
        return record.id
    }

    func events() throws -> [GoalEvent] {
        let goalID = goalID
        return try ModelContext(container).fetch(FetchDescriptor<GoalEvent>()).filter { $0.goal?.id == goalID }
    }
}

@Suite("FocusSessionVerifier — persisted sessions, auto-verify, leaving the app")
@MainActor
struct FocusSessionPersistenceTests {
    @Test("a persisted session whose planned time elapsed verifies on restore")
    func elapsedSessionVerifiesOnRestore() async throws {
        let h = try FocusHarness()
        let now = Date.now
        _ = h.seed(startedMinutesAgo: 30, now: now)

        await h.verifier.restorePersistedSessions(now: now)

        let events = try h.events()
        #expect(events.count == 1)
        #expect(events.first?.kind == .complete)
        #expect(events.first?.verified == true)
        #expect(h.spy.goalIDs == [h.goalID])
        #expect(h.store.load().isEmpty)
        #expect(h.verifier.activeSession == nil)
    }

    @Test("a persisted session still running is re-adopted, visible, and ended by endActiveSession")
    func runningSessionIsReadoptedAndEndable() async throws {
        let h = try FocusHarness()
        let now = Date.now
        let id = h.seed(startedMinutesAgo: 5, now: now)

        await h.verifier.restorePersistedSessions(now: now)
        #expect(h.verifier.activeSession?.id == id)
        #expect(h.verifier.activeSession?.goalID == h.goalID)
        #expect(h.store.load().map(\.id) == [id])

        // Ended early: logged as a miss, not verified.
        let verified = try await h.verifier.endActiveSession(now: now)
        #expect(verified == false)
        #expect(try h.events().first?.kind == .miss)
        #expect(h.verifier.activeSession == nil)
        #expect(h.store.load().isEmpty)
        // Ending it again returns the same result instead of throwing.
        #expect(try await h.verifier.endSession(sessionID: id) == false)
    }

    @Test("endActiveSession with nothing running returns nil")
    func endActiveSessionWithoutSession() async throws {
        let h = try FocusHarness()
        #expect(try await h.verifier.endActiveSession() == nil)
    }

    @Test("leaving the app pauses an in-app session; returning resumes it")
    func backgroundPausesAndForegroundResumes() async throws {
        let h = try FocusHarness()
        let now = Date.now
        let id = h.seed(startedMinutesAgo: 1, pausesWhenAppLeaves: true, now: now)
        await h.verifier.restorePersistedSessions(now: now)

        h.verifier.appDidEnterBackground(now: now)
        let paused = try #require(h.store.load().first { $0.id == id })
        #expect(paused.pausedAt == now)
        #expect(paused.autoPaused)
        #expect(paused.appLeaveCount == 1)
        #expect(h.verifier.activeSession?.isPaused == true)

        await h.verifier.appDidBecomeActive(now: now.addingTimeInterval(120))
        let resumed = try #require(h.store.load().first { $0.id == id })
        #expect(resumed.pausedAt == nil)
        #expect(resumed.accumulatedPauseDuration == 120)
        #expect(h.verifier.activeSession?.isPaused == false)

        h.verifier.resetAll()
        #expect(h.store.load().isEmpty)
    }

    @Test("a session started outside the app keeps running when the app goes to the background")
    func outsideSessionDoesNotPause() async throws {
        let h = try FocusHarness()
        let now = Date.now
        let id = h.seed(startedMinutesAgo: 1, pausesWhenAppLeaves: false, now: now)
        await h.verifier.restorePersistedSessions(now: now)

        h.verifier.appDidEnterBackground(now: now)
        #expect(h.store.load().first { $0.id == id }?.pausedAt == nil)
        h.verifier.resetAll()
    }

    @Test("paused time never counts toward the plan")
    func pausesAreExcludedFromElapsedTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var record = PersistedFocusSession(
            id: UUID(), goalID: UUID(), plannedMinutes: 25, startedAt: start,
            isPlanB: false, pausesWhenAppLeaves: true, activityID: nil
        )
        record.accumulatedPauseDuration = 300
        record.pausedAt = start.addingTimeInterval(1_200)
        // 30 min wall clock − 5 min past pause − 10 min current pause = 15 min active.
        #expect(record.elapsedActiveSeconds(asOf: start.addingTimeInterval(1_800)) == 900)
    }

    @Test("verification needs the planned time, with a few seconds of slack per app leave")
    func verificationRule() {
        #expect(FocusSessionVerifier.isVerified(elapsedSeconds: 1_500, plannedSeconds: 1_500, appLeaveCount: 0))
        #expect(!FocusSessionVerifier.isVerified(elapsedSeconds: 1_490, plannedSeconds: 1_500, appLeaveCount: 0))
        #expect(FocusSessionVerifier.isVerified(elapsedSeconds: 1_490, plannedSeconds: 1_500, appLeaveCount: 2))
        // Capped: leaving a lot never buys more than 30 seconds.
        #expect(!FocusSessionVerifier.isVerified(elapsedSeconds: 1_460, plannedSeconds: 1_500, appLeaveCount: 50))
    }
}

@Suite("SunriseAlarmManager — recurrence (audit V1)")
struct SunriseAlarmRecurrenceTests {
    private let fire = Date(timeIntervalSince1970: 2_000_000)

    @Test("an upcoming occurrence is left alone")
    func upcomingIsLeftAlone() {
        #expect(!SunriseAlarmManager.needsNextOccurrence(fireDate: fire, dismissedAt: nil, now: fire.addingTimeInterval(-60)))
    }

    @Test("a ringing occurrence is left alone until its window passes")
    func ringingIsLeftAlone() {
        #expect(!SunriseAlarmManager.needsNextOccurrence(fireDate: fire, dismissedAt: nil, now: fire.addingTimeInterval(120)))
        let pastWindow = fire.addingTimeInterval(SunriseAlarmEngineDefaults.escalationWindow + 61)
        #expect(SunriseAlarmManager.needsNextOccurrence(fireDate: fire, dismissedAt: nil, now: pastWindow))
    }

    @Test("a dismissed occurrence schedules the next one")
    func dismissedSchedulesNext() {
        #expect(SunriseAlarmManager.needsNextOccurrence(fireDate: fire, dismissedAt: fire.addingTimeInterval(90), now: fire.addingTimeInterval(100)))
    }
}
