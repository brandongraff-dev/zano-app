// GymCheckInView.swift
// App / ZANO / Features / GymSetup
//
// spec §3 (Workout (gym), Tier A: geofence arrival + dwell + HR corroboration), §5.11 (elapsed
// time at the gym and "verified in 12 min"), §24 (manual check-in fallback), §15 (haptics on
// every verified event). The live check-in screen, presented from Today's gym row (Wave 1D) and
// from Gym setup. Reads SwiftData itself; `GymPresenceService` supplies the live dwell state.
//
// States, in priority order:
//   * no confirmed gym → set one up;
//   * today's gym workout already complete → success (verified, or honest "checked in manually");
//   * a dwell is running → the big ring counting toward the target;
//   * a dwell ended short → "You left at 22 min" + resume;
//   * otherwise → "Head to <gym>" + Start check-in.
// "Can't verify? Check in manually" (`ManualCheckInSheet`) is available in every state that isn't
// already complete.
//
// No `NavigationStack` of its own — it's pushed.

import SwiftUI
import SwiftData
import Core

public struct GymCheckInView: View {
    @Query private var gyms: [Gym]
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]
    @Query private var todaysEvents: [GoalEvent]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var isManualPresented = false
    @State private var isStarting = false
    @State private var startNote: String?
    @State private var manualTick = 0

    public init() {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        _todaysEvents = Query(
            filter: #Predicate<GoalEvent> { $0.ts >= startOfDay },
            sort: \GoalEvent.ts,
            order: .reverse
        )
    }

    private var presence: GymPresenceService { .shared }
    private var authorization: GymLocationAuthorization { .shared }

    // MARK: Derived state

    private var confirmedGyms: [Gym] {
        gyms.filter(\.confirmed).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// The gym this screen is about: the one with a session today, else the one the phone is in,
    /// else the first confirmed gym.
    private var gym: Gym? {
        let candidates = confirmedGyms
        return candidates.first { presence.sessions[$0.id]?.isActive == true }
            ?? candidates.first { presence.regionStates[$0.id] == .inside }
            ?? candidates.first { presence.sessions[$0.id] != nil }
            ?? candidates.first
    }

    private var gymName: String {
        let trimmed = gym?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Copy.gym.fallbackName : trimmed
    }

    private var gymGoal: Goal? {
        activeGoals.filter { $0.type == .workoutGym }.max { $0.createdAt < $1.createdAt }
    }

    private var todaysCompletion: GoalEvent? {
        guard let goalID = gymGoal?.id else { return nil }
        return todaysEvents.first { $0.goal?.id == goalID && $0.kind == .complete && $0.verified }
    }

    private var targetMinutes: Int { presence.requiredMinutes }

    private enum Phase: Equatable {
        case noGym
        case verified(minutes: Int)
        case manual
        case dwelling(enteredAt: Date)
        case leftEarly(minutes: Int)
        case away
    }

    private var phase: Phase {
        guard let gym else { return .noGym }
        if let completion = todaysCompletion {
            return completion.source == .manual
                ? .manual
                : .verified(minutes: Int(completion.value ?? Double(targetMinutes)))
        }
        if let session = presence.sessions[gym.id] {
            if session.isVerified { return .verified(minutes: session.dwellMinutes) }
            if session.isActive { return .dwelling(enteredAt: session.enteredAt) }
            return .leftEarly(minutes: session.dwellMinutes)
        }
        return .away
    }

    private var heartRate: Bool? {
        guard let gym else { return nil }
        return presence.sessions[gym.id]?.heartRateCorroborated
    }

    // MARK: Body

    public var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                content
                if phase != .noGym {
                    LocationPermissionPrimer(kind: .always, authorization: authorization)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: phase)
        }
        .zanoActionBar { actionBar }
        .zanoAmbient(reduceTransparency ? .neutral : ambient)
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.gym.checkInTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: presence.verificationCount)
        .sensoryFeedback(.success, trigger: manualTick)
        .task {
            presence.start()
            await presence.refresh()
        }
        .sheet(isPresented: $isManualPresented) {
            ManualCheckInSheet(gymID: gym?.id) {
                manualTick += 1
            }
        }
    }

    private var ambient: ZanoAmbientState {
        switch phase {
        case .verified, .manual: .earned
        case .dwelling(let enteredAt): .progress(progress(since: enteredAt, at: .now))
        case .noGym, .leftEarly, .away: .neutral
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .noGym:
            noGymState
        case .verified(let minutes):
            completeState(
                icon: "checkmark.seal.fill",
                title: Copy.gym.verifiedTitle,
                detail: Copy.gym.verifiedDetail(minutes: minutes, gym: gymName),
                badge: nil
            )
        case .manual:
            completeState(
                icon: "hand.raised.fill",
                title: Copy.gym.manualDoneTitle,
                detail: Copy.gym.manualDoneDetail,
                badge: Copy.gym.manualTierBadge
            )
        case .dwelling(let enteredAt):
            dwellingState(enteredAt: enteredAt)
        case .leftEarly(let minutes):
            ringHero(progress: Double(minutes) / Double(max(targetMinutes, 1)), color: Theme.Colors.muted, minutes: minutes)
            statusText(
                title: Copy.gym.leftEarlyTitle(minutes: minutes),
                message: Copy.gym.leftEarlyMessage(target: targetMinutes)
            )
            startNoteView
        case .away:
            awayState
        }
    }

    // MARK: States

    private var noGymState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            IconBadge(systemName: "mappin.and.ellipse", tint: Theme.Colors.accent, size: .large)
                .padding(.top, Theme.Spacing.xl)
            statusText(title: Copy.gym.noGymTitle, message: Copy.gym.noGymMessage)
        }
    }

    private var awayState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZanoStatusCapsule(dotColor: Theme.Colors.muted, text: gymName)
            GoalRing(
                progress: 0,
                color: Theme.Colors.accent,
                size: .custom(220),
                center: .icon(systemName: "figure.strengthtraining.traditional"),
                label: Copy.gym.ringLabel
            )
            statusText(title: Copy.gym.headTo(gym: gymName), message: Copy.gym.awayMessage)
            startNoteView
        }
    }

    private func dwellingState(enteredAt: Date) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.gym.atGym(gymName))
            // Minutes are derived from `enteredAt` locally so the ring moves between the service's
            // 30 s refreshes.
            TimelineView(.periodic(from: .now, by: 5)) { context in
                let minutes = minutes(since: enteredAt, at: context.date)
                ringHero(
                    progress: progress(since: enteredAt, at: context.date),
                    color: Theme.Colors.accent,
                    minutes: minutes
                )
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let remaining = max(0, targetMinutes - minutes(since: enteredAt, at: context.date))
                statusText(title: Copy.gym.verifiesIn(minutes: remaining), message: Copy.gym.stayHint)
            }
            if let heartRate {
                heartRateChip(heartRate)
            }
        }
    }

    private func completeState(icon: String, title: String, detail: String, badge: String?) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                GoalRing(progress: 1, color: Theme.Colors.accent, size: .custom(220), center: .none, label: title)
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .symbolEffect(.bounce, value: presence.verificationCount + manualTick)
                    .accessibilityHidden(true)
            }
            .padding(.top, Theme.Spacing.md)
            statusText(title: title, message: detail)
            if let badge {
                ZanoStatusCapsule(dotColor: Theme.Colors.warning, text: badge)
            }
            if let heartRate, badge == nil {
                heartRateChip(heartRate)
            }
        }
    }

    // MARK: Pieces

    private func ringHero(progress: Double, color: Color, minutes: Int) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            GoalRing(
                progress: progress,
                color: color,
                size: .custom(236),
                center: .value("\(minutes)", unit: Copy.gym.minutesUnit),
                label: Copy.gym.ringLabel
            )
            Text(Copy.gym.verifiesAt(minutes: targetMinutes))
                .zanoText(.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    private func statusText(title: String, message: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .zanoText(.titleLarge)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .zanoText(.paragraph)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func heartRateChip(_ elevated: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: elevated ? "heart.fill" : "heart")
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(elevated ? Theme.Colors.accent : Theme.Colors.muted)
                .symbolEffect(.pulse, isActive: elevated && !reduceMotion)
                .accessibilityHidden(true)
            Text(elevated ? Copy.gym.heartRateUp : Copy.gym.heartRateSteady)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .zanoGlass()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var startNoteView: some View {
        if let startNote {
            Text(startNote)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.warning)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    // MARK: Action bar

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            switch phase {
            case .noGym:
                NavigationLink {
                    GymSetupView()
                } label: {
                    Label(Copy.gym.setUpGymButton, systemImage: "mappin.and.ellipse")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.primaryButtonHeight)
                        .background(Theme.Colors.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)
            case .away, .leftEarly:
                PrimaryButton(
                    title: phase == .away ? Copy.gym.startCheckInButton : Copy.gym.resumeCheckInButton,
                    systemImage: "figure.strengthtraining.traditional",
                    isEnabled: !isStarting
                ) {
                    Task { await startCheckIn() }
                }
                manualLink
            case .dwelling:
                manualLink
            case .verified, .manual:
                EmptyView()
            }
        }
    }

    private var manualLink: some View {
        Button {
            isManualPresented = true
        } label: {
            Text(Copy.gym.manualLink)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func startCheckIn() async {
        guard let gymID = gym?.id else { return }
        isStarting = true
        defer { isStarting = false }
        // Starting a check-in is the moment the Always ask is explained on this screen (the card
        // above); the tap itself never triggers a permission prompt.
        let result = await presence.startCheckIn(gymID: gymID)
        switch result {
        case .started, .alreadyRunning:
            startNote = nil
        case .notAtGym:
            startNote = Copy.gym.notAtGymYet(gym: gymName)
        case .unavailable:
            startNote = Copy.gym.checkInUnavailable
        }
    }

    // MARK: Math

    private func minutes(since enteredAt: Date, at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(enteredAt) / 60))
    }

    private func progress(since enteredAt: Date, at now: Date) -> Double {
        Double(minutes(since: enteredAt, at: now)) / Double(max(targetMinutes, 1))
    }
}
