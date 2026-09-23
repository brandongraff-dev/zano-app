// LockStatusView.swift
// App / ZANO / Features / Lock
//
// The Lock screen — docs/spec.md §15 ("Screens: Today, Lock, Fuel, Progress, Squad, Settings...").
// §16 doesn't give Lock its own P1-style mockup prompt (P1 covers Today only), so this screen's
// layout is derived from this task's brief ("current lock session detail: required goals, progress,
// time context") plus the Living Shield's own state model (spec §5.1) and the emergency-unlock
// guarantee that applies to every lock/shield surface (CLAUDE.md: "Any lock/shield feature must
// always keep an emergency-unlock path. Never trap the user.").
//
// No `NavigationStack` of its own: this view is pushed from `TodayView`'s `LockStatusCard` tap via
// `navigationDestination`, and may also become its own tab root later (spec §15's tab bar) — either
// host already supplies navigation chrome, so nesting a second `NavigationStack` here would be
// wrong in the pushed case. `.navigationTitle`/`.navigationBarTitleDisplayMode` below work in both
// hosts.
//
// Engine calls (`LockEngineManager`, `TimeBankEngine`) follow this task's SYSTEM CONTRACTS shape
// exactly; none of those files exist on disk in this session (parallel work), and nothing here has
// been compiled (no Mac/Swift toolchain available). See this task's "decisions"/"knownIssues".
//
// Copy note: user-facing strings go through `Copy.lockStatus.*`
// (`Core/Sources/Core/Copy/LockStatusCopy.swift`), following the `Copy.<area>` umbrella convention
// `Copy.swift` documents — moved there from this file's own private nested `Copy` enum by the
// repo-wide Copy sweep (2026-09-22); see that file's header for why.
//
// Analytics (gap-fill wave, spec §23): this screen logs its own screen view and flushes
// `SharedDefaults.shieldImpressionCount` — the on-device-only tally `ShieldConfigurationExtension`
// increments locally since shield extensions cannot do networking (spec §11, §27) — into a single
// aggregate `Analytics` event the next time this screen opens. See the "Analytics" MARK below.

import Foundation
import SwiftUI
import SwiftData
import Core

struct LockStatusView: View {

    // MARK: - Data

    @Query private var users: [User]
    @Query private var goals: [Goal]
    @Query private var goalEvents: [GoalEvent]
    @Query private var dailyPlans: [DailyPlan]
    @Query private var lockSessions: [LockSession]
    @Query private var timeBanks: [TimeBank]

    // MARK: - Local state

    @State private var isEmergencyUnlocking = false
    @State private var actionError: String?
    @State private var timeBankRemainingMinutes: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                lockStatusCard
                timeContextCard

                if !requiredGoals.isEmpty {
                    goalsSection
                }

                if activeSession?.mode == .earn {
                    timeBankSection
                }

                if let actionError {
                    Text(actionError)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.danger)
                }

                emergencySection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.lockStatus.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: timeBankTaskKey) {
            timeBankRemainingMinutes = await TimeBankEngine.shared.remainingMinutes(for: .now)
        }
        .task {
            logScreenView()
            flushShieldImpressions()
        }
    }

    // MARK: - Analytics (spec §23: "Instrument from day one: every screen view, every intent,
    // every unlock kind, every shield impression").
    //
    // This screen is the natural place to flush ``SharedDefaults/shieldImpressionCount``: shield
    // extensions cannot do networking (spec §11, §27) so `ShieldConfigurationExtension` only
    // increments that on-device counter locally, and the main app reports the accumulated total
    // via `Analytics` the next time it opens the Lock screen — count-only, no per-impression
    // detail, per spec §23/§24.

    /// Fires once per appearance of this screen, in a plain (non-`id`-keyed) `.task` so it isn't
    /// re-triggered by `timeBankTaskKey` changing underneath it.
    private func logScreenView() {
        Analytics.shared.capture(
            event: "lock_screen_viewed",
            properties: [
                "is_locked": activeSession != nil,
                "mode": activeSession?.mode?.rawValue ?? "none",
                "goals_remaining": remainingRequiredGoalCount
            ]
        )
    }

    /// Reads and resets ``SharedDefaults/shieldImpressionCount`` and reports the total as a
    /// single aggregate event. No-op (and no event fired) when the count is already `0`, so
    /// opening this screen with no shield impressions to report doesn't spam an empty event.
    private func flushShieldImpressions() {
        let count = SharedDefaults.flushShieldImpressionCount()
        guard count > 0 else { return }
        Analytics.shared.capture(event: "shield_impression", properties: ["count": count])
    }

    // MARK: - Lock status card

    private var lockStatusCard: some View {
        LockStatusCard(
            isLocked: activeSession != nil,
            statusLine: statusLine,
            detailLine: detailLine
        )
    }

    private var statusLine: String {
        guard activeSession != nil else { return Copy.lockStatus.unlockedHeadline }
        return remainingRequiredGoalCount == 1
            ? Copy.lockStatus.lockedHeadlineSingular
            : Copy.lockStatus.lockedHeadlinePlural(remainingRequiredGoalCount)
    }

    private var detailLine: String? {
        guard activeSession != nil else { return nil }
        if let bank = todaysTimeBank, activeSession?.mode == .earn, bank.remainingMin > 0 {
            return "\(bank.remainingMin) min banked"
        }
        return CoachVoiceTone.goalsRemainingClause(voice, remaining: remainingRequiredGoalCount)
    }

    // MARK: - Time context

    private var timeContextCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let session = activeSession {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Theme.Colors.muted)
                    Text(Copy.lockStatus.lockedSincePrefix)
                        .foregroundStyle(Theme.Colors.text)
                    Text(session.startedAt, style: .time)
                        .foregroundStyle(Theme.Colors.text)
                }
                .font(Theme.Typography.body)

                Text(Copy.lockStatus.triggerLine(session.trigger))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)

                if let nextLockAt = SharedDefaults.nextScheduledLockAt {
                    nextLockRow(nextLockAt)
                }
            } else if let nextLockAt = SharedDefaults.nextScheduledLockAt {
                nextLockRow(nextLockAt)
            } else {
                Text(Copy.lockStatus.noScheduleLine)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func nextLockRow(_ date: Date) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "calendar")
                .foregroundStyle(Theme.Colors.muted)
            Text(Copy.lockStatus.nextLockPrefix)
                .foregroundStyle(Theme.Colors.muted)
            Text(date, style: .time)
                .foregroundStyle(Theme.Colors.muted)
        }
        .font(Theme.Typography.caption)
    }

    // MARK: - Required goals

    private var requiredGoals: [Goal] {
        guard let session = activeSession else { return [] }
        let requiredIDs = Set(session.requiredGoalIDs)
        return goals.filter { requiredIDs.contains($0.id) }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.lockStatus.requiredGoalsHeading)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            ForEach(requiredGoals) { goal in
                goalRow(goal)
            }
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        let p = progress(for: goal)
        return HStack(spacing: Theme.Spacing.sm) {
            GoalRing(progress: p.fraction, color: Theme.Colors.Ring.color(for: goal.type), size: .small)

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                Text(p.valueText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }

            Spacer(minLength: 0)

            if p.fraction >= 1 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    // MARK: - Time Bank (Earn Mode only — spec §5.2)

    private var timeBankSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            TimeBankBar(
                remainingMinutes: displayedRemainingMinutes,
                totalMinutes: todaysTimeBank?.earnedMin ?? 0,
                label: Copy.lockStatus.timeBankHeading
            )

            Text("\(displayedRemainingMinutes) min available")
                .font(Theme.Typography.numeralSmall())
                .foregroundStyle(Theme.Colors.text)

            Text(Copy.lockStatus.timeBankFootnote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var displayedRemainingMinutes: Int {
        timeBankRemainingMinutes ?? todaysTimeBank?.remainingMin ?? 0
    }

    private var timeBankTaskKey: String {
        "\(todaysTimeBank?.earnedMin ?? 0)-\(todaysTimeBank?.spentMin ?? 0)"
    }

    // MARK: - Emergency unlock (CLAUDE.md: every lock keeps a way out — no exceptions)

    @ViewBuilder
    private var emergencySection: some View {
        if activeSession != nil {
            VStack(spacing: Theme.Spacing.xs) {
                PrimaryButton(
                    title: Copy.lockStatus.emergencyUnlockTitle,
                    systemImage: "exclamationmark.triangle.fill",
                    style: .holdToCommit,
                    isEnabled: !isEmergencyUnlocking,
                    action: performEmergencyUnlock
                )
                Text(Copy.lockStatus.emergencyUnlockFootnote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func performEmergencyUnlock() {
        guard let session = activeSession else { return }
        isEmergencyUnlocking = true
        Analytics.shared.capture(event: "lock_emergency_unlock_started")
        Task {
            defer { isEmergencyUnlocking = false }
            do {
                try await LockEngineManager.shared.emergencyUnlock(sessionID: session.id)
                Analytics.shared.capture(event: "lock_emergency_unlock_succeeded")
            } catch {
                actionError = error.localizedDescription
                Analytics.shared.capture(
                    event: "lock_emergency_unlock_failed",
                    properties: ["reason": error.localizedDescription]
                )
            }
        }
    }

    // MARK: - Derived state

    private var voice: CoachVoice { users.first?.coachVoice ?? .hype }
    private var activeSession: LockSession? { lockSessions.first(where: \.isActive) }

    private var remainingRequiredGoalCount: Int {
        requiredGoals.filter { !isGoalDoneToday($0) }.count
    }

    private var todaysTimeBank: TimeBank? {
        timeBanks.first { Calendar.current.isDateInToday($0.date) }
    }

    // MARK: - Per-goal progress (see TodayView.swift for the same computation and why it's
    // duplicated rather than shared — each Feature screen stays self-contained in this batch).

    private func todaysPlan(for goal: Goal) -> DailyPlan? {
        dailyPlans.first { $0.goal?.id == goal.id && Calendar.current.isDateInToday($0.date) }
    }

    private func todaysEvents(for goal: Goal) -> [GoalEvent] {
        goalEvents.filter { $0.goal?.id == goal.id && Calendar.current.isDateInToday($0.ts) }
    }

    private func isGoalDoneToday(_ goal: Goal) -> Bool {
        progress(for: goal).fraction >= 1
    }

    private func progress(for goal: Goal) -> (fraction: Double, valueText: String) {
        let events = todaysEvents(for: goal)
        let hasCompletion = events.contains { [.complete, .verify, .planB].contains($0.kind) }
        let target = todaysPlan(for: goal)?.plannedValue ?? goal.targetValue

        guard let target, target > 0 else {
            return (hasCompletion ? 1 : 0, hasCompletion ? "Done" : "Not yet")
        }

        let loggedSum = events.compactMap(\.value).reduce(0, +)
        let fraction = hasCompletion ? 1 : min(1, loggedSum / target)
        let unit = goal.unit ?? ""
        let valueText = "\(Int(loggedSum.rounded()))/\(Int(target.rounded()))\(unit)"
        return (fraction, valueText)
    }
}

#Preview {
    NavigationStack {
        LockStatusView()
            .modelContainer(for: [
                User.self, Goal.self, DailyPlan.self, GoalEvent.self,
                LockSet.self, LockSession.self, TimeBank.self
            ], inMemory: true)
    }
}
