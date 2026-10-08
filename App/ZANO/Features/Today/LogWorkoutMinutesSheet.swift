// LogWorkoutMinutesSheet.swift
// App / ZANO / Features / Today
//
// Session 42: "Log minutes" for both workout goals (docs/spec.md §3, Tier C: honesty + friction). People
// work out at home, in a park, in a hotel room; a workout goal must never need a saved gym, location,
// Apple Health or Strava. Pick the minutes (stepper or quick picks, starting at what's left of today's
// target), hold to confirm (`PrimaryButton(.holdToCommit)`, the same friction as the gym's honor
// check-in), and the entry goes through `LogWorkoutMinutesIntent` (CLAUDE.md: every user action is an
// intent), which writes through `HomeWorkoutVerifier.logManualMinutes`. Entries add up across the day,
// with no daily cap, and are listed here as "logged by hand" (spec §9.8: honest, never accusing).
//
// Opened from Today's workout tile and from the gym check-in screen. The optional secondary link offers
// the automatic route (connect Apple Health, or save a gym) without making it a requirement.

import SwiftUI
import SwiftData
import Core

struct LogWorkoutMinutesSheet: View {
    /// The automatic route offered under the form, if any.
    enum SecondaryLink: Equatable {
        case connectHealth
        case setUpGym
    }

    let goalID: UUID
    /// Minutes the day's total has to reach (`HomeWorkoutVerifier.manualRequiredMinutes`).
    let requiredMinutes: Int
    /// Today's tracked workouts (Health + Strava, deduped), for the running total.
    let tracked: ManualWorkoutMinutes.Tracked
    var secondaryLink: SecondaryLink?
    var onSecondary: () -> Void = {}

    @Query private var todaysEvents: [GoalEvent]
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int
    @State private var isSaving = false
    @State private var failed = false
    @State private var successTick = 0

    init(
        goalID: UUID,
        requiredMinutes: Int,
        tracked: ManualWorkoutMinutes.Tracked,
        manualMinutesSoFar: Int,
        secondaryLink: SecondaryLink? = nil,
        onSecondary: @escaping () -> Void = {}
    ) {
        self.goalID = goalID
        self.requiredMinutes = requiredMinutes
        self.tracked = tracked
        self.secondaryLink = secondaryLink
        self.onSecondary = onSecondary
        let progress = ManualWorkoutMinutes.progressMinutes(tracked: tracked, manualMinutes: manualMinutesSoFar)
        _minutes = State(initialValue: ManualWorkoutMinutes.suggestedMinutes(requiredMinutes: requiredMinutes, progressMinutes: progress))
        let startOfDay = Calendar.current.startOfDay(for: .now)
        _todaysEvents = Query(
            filter: #Predicate<GoalEvent> { $0.ts >= startOfDay },
            sort: \GoalEvent.ts
        )
    }

    // MARK: Derived

    private var goalEvents: [GoalEvent] {
        todaysEvents.filter { $0.goal?.id == goalID }
    }

    private var entries: [GoalEvent] {
        goalEvents.filter(ManualWorkoutMinutes.isEntry)
    }

    private var manualMinutes: Int {
        ManualWorkoutMinutes.loggedMinutes(in: goalEvents)
    }

    private var totalMinutes: Int {
        ManualWorkoutMinutes.progressMinutes(tracked: tracked, manualMinutes: manualMinutes)
    }

    private var isDoneToday: Bool {
        goalEvents.contains(where: GoalDayProgress.isVerifiedCompletion)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    IconBadge(systemName: "figure.run", tint: Theme.Colors.Ring.workout, size: .large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.md)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(Copy.workoutMinutes.headline)
                            .zanoText(.titleLarge)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Copy.workoutMinutes.message)
                            .zanoText(.paragraph)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        ZanoStatusCapsule(dotColor: Theme.Colors.warning, text: Copy.workoutMinutes.tierBadge)
                        Spacer(minLength: 0)
                    }

                    progressSummary
                    minutesPicker
                    quickPicks

                    if !entries.isEmpty {
                        entryList
                    }

                    if let secondaryLink {
                        secondaryButton(secondaryLink)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .zanoActionBar { actionBar }
            .zanoBackdrop()
            .navigationTitle(Copy.workoutMinutes.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel) { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: successTick)
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: Pieces

    @ViewBuilder
    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(Copy.workoutMinutes.progressLine(total: totalMinutes, required: requiredMinutes))
                .zanoText(.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
            if isDoneToday {
                Text(Copy.workoutMinutes.alreadyDone)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if requiredMinutes > totalMinutes {
                Text(Copy.workoutMinutes.leftLine(requiredMinutes - totalMinutes))
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Minus / minutes / plus. One adjustable VoiceOver element, like the goals editor's stepper.
    private var minutesPicker: some View {
        HStack(spacing: Theme.Spacing.md) {
            stepButton(systemImage: "minus", isEnabled: minutes > ManualWorkoutMinutes.range.lowerBound) {
                minutes = ManualWorkoutMinutes.clamped(minutes - ManualWorkoutMinutes.step)
            }
            .accessibilityLabel(Copy.workoutMinutes.decreaseLabel)

            Text(Copy.workoutMinutes.minutesValue(minutes))
                .font(Theme.Typography.score(size: 40))
                .foregroundStyle(Theme.Colors.text)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            stepButton(systemImage: "plus", isEnabled: minutes < ManualWorkoutMinutes.range.upperBound) {
                minutes = ManualWorkoutMinutes.clamped(minutes + ManualWorkoutMinutes.step)
            }
            .accessibilityLabel(Copy.workoutMinutes.increaseLabel)
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.workoutMinutes.stepperSpokenLabel)
        .accessibilityValue(Copy.workoutMinutes.stepperSpokenValue(minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = ManualWorkoutMinutes.clamped(minutes + ManualWorkoutMinutes.step)
            case .decrement: minutes = ManualWorkoutMinutes.clamped(minutes - ManualWorkoutMinutes.step)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.medium, weight: .bold))
                .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.muted)
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .background(Circle().fill(Theme.Colors.Ring.workout.opacity(0.18)))
        }
        .buttonStyle(.pressable(scale: 0.92))
        .disabled(!isEnabled)
    }

    private var quickPicks: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(ManualWorkoutMinutes.quickPicks, id: \.self) { pick in
                let isSelected = pick == minutes
                Button {
                    minutes = pick
                } label: {
                    Text(Copy.workoutMinutes.chipLabel(pick))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                        .background {
                            Capsule(style: .continuous)
                                .fill(isSelected ? Theme.Colors.accentFill : Theme.Colors.Ring.workout.opacity(0.14))
                        }
                }
                .buttonStyle(.pressable(scale: 0.95))
                .accessibilityLabel(Copy.workoutMinutes.chipSpoken(pick))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.workoutMinutes.entriesHeader)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries) { entry in
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "hand.raised.fill")
                        .font(Theme.Typography.icon(.xsmall))
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityHidden(true)
                    Text(Copy.workoutMinutes.entryLine(minutes: ManualWorkoutMinutes.entryMinutes(entry) ?? 0))
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer(minLength: 0)
                    Text(entry.ts, format: .dateTime.hour().minute())
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    private func secondaryButton(_ link: SecondaryLink) -> some View {
        Button {
            dismiss()
            onSecondary()
        } label: {
            Text(link == .connectHealth ? Copy.workoutMinutes.connectHealthLink : Copy.workoutMinutes.setUpGymLink)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.accent)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if failed {
                Text(Copy.workoutMinutes.failed)
                    .zanoText(.captionEmphasized)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            PrimaryButton(
                title: Copy.workoutMinutes.holdButton(minutes: minutes),
                systemImage: "hand.raised.fill",
                style: .holdToCommit,
                isEnabled: !isSaving
            ) {
                Task { await commit() }
            }
        }
    }

    // MARK: Commit

    private func commit() async {
        guard !isSaving else { return }
        isSaving = true
        failed = false
        defer { isSaving = false }
        let logged = ManualWorkoutMinutes.clamped(minutes)
        Analytics.shared.capture(event: "workout_minutes_logged", properties: ["minutes": logged])
        do {
            _ = try await LogWorkoutMinutesIntent(minutes: logged, source: .manual, goalID: goalID).perform()
        } catch {
            failed = true
            AccessibilityNotification.Announcement(Copy.workoutMinutes.failed).post()
            return
        }
        successTick += 1
        AccessibilityNotification.Announcement(Copy.workoutMinutes.savedAnnouncement(minutes: logged)).post()
        // Let the haptic land and the hold's settle finish before the sheet goes.
        try? await Task.sleep(for: .milliseconds(450))
        dismiss()
    }
}
