// GymLeaderboardView.swift
// App / Features / Progress
//
// docs/spec.md §5.8 Gym Home Turf (opt-in): "Users who save the same gym form an anonymous
// leaderboard: 'You're #4 most consistent at this gym this month.' Optional handle." Wave 3J.
//
// Offline-first. The backend that assembles a gym's board doesn't exist yet
// (`GymLeaderboardManager.isBackendConfigured == false`), so the screen is built around what is
// always true locally:
//   1. Your own 30-day gym consistency, computed on this iPhone (`myConsistencyScore`).
//   2. The opt-in toggle and optional handle. Opting in is a local fact (App Group defaults) plus a
//      queued outbox sync, so it works offline too.
//   3. The board itself: with no backend, a plain "needs the network" state instead of a spinner
//      or an error. With one, ranked rows, your own row marked.
// Privacy (spec §5.8, §24): off by default; the footer says exactly what others see.

import SwiftUI
import SwiftData
import Core

struct GymLeaderboardView: View {
    @Query(filter: #Predicate<Gym> { $0.confirmed }) private var confirmedGyms: [Gym]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedGymID: UUID?
    @State private var score: GymConsistencyScore?
    @State private var optIn: GymLeaderboardOptIn = .notOptedIn
    @State private var handleDraft = ""
    @State private var handleError: String?
    @State private var board: BoardState = .loading
    @State private var toggleTick = 0

    enum BoardState: Equatable {
        case loading
        case offline
        case failed
        case loaded(GymLeaderboardResult)
    }

    private var selectedGym: Gym? {
        confirmedGyms.first { $0.id == selectedGymID } ?? confirmedGyms.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if confirmedGyms.isEmpty {
                    noGymState
                } else {
                    if confirmedGyms.count > 1 { gymPicker }
                    yourConsistencyCard
                    boardSection
                }
                privacySection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.progress.gymBoardScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: toggleTick)
        .task(id: selectedGym?.id) { await load() }
        .onAppear { Analytics.shared.capture(event: "gym_board_opened") }
    }

    // MARK: - Sections

    private var noGymState: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "dumbbell", tint: Theme.Colors.muted)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Copy.progress.gymBoardNoGymTitle)
                    .zanoText(.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.progress.gymBoardNoGymMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .zanoWell(radius: Theme.Radius.medium)
    }

    private var gymPicker: some View {
        Picker(Copy.progress.gymBoardPickerLabel, selection: Binding(
            get: { selectedGym?.id },
            set: { selectedGymID = $0 }
        )) {
            ForEach(confirmedGyms, id: \.id) { gym in
                Text(gym.name ?? Copy.progress.gymBoardUnnamedGym).tag(Optional(gym.id))
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.Colors.accent)
    }

    private var yourConsistencyCard: some View {
        let days = score?.consistentDays ?? 0
        let total = score?.trailingDays ?? GymLeaderboardManager.defaultTrailingDays
        let myRank: Int? = {
            if case .loaded(let result) = board { return result.currentUserEntry?.rank }
            return nil
        }()
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.progress.gymBoardYourConsistencyTitle)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                GoalRing(
                    progress: score?.consistency ?? 0,
                    color: Theme.Colors.accent,
                    size: .medium,
                    center: .text(Copy.progress.gymBoardPercent(Int(((score?.consistency ?? 0) * 100).rounded())))
                )
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.progress.gymBoardConsistencyLabel(days: days, total: total))
                        .zanoText(.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let myRank {
                        Text(Copy.progress.gymBoardYourRankLabel(rank: myRank))
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var boardSection: some View {
        switch board {
        case .loading:
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
        case .offline:
            infoWell(icon: "wifi.slash", title: Copy.progress.gymBoardOfflineTitle, message: Copy.progress.gymBoardOfflineMessage)
        case .failed:
            infoWell(icon: "exclamationmark.arrow.triangle.2.circlepath", title: nil, message: Copy.progress.gymBoardErrorMessage)
        case .loaded(let result):
            if result.entries.isEmpty || (result.entries.count == 1 && result.currentUserEntry != nil) {
                infoWell(icon: "person.2", title: nil, message: Copy.progress.gymBoardEmptyMessage)
            } else {
                VStack(spacing: 0) {
                    ForEach(result.entries) { entry in
                        BoardRow(entry: entry)
                        if entry.id != result.entries.last?.id {
                            Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                                .padding(.leading, Theme.Spacing.md)
                        }
                    }
                }
                .zanoCard(radius: Theme.Radius.medium)
            }
        }
    }

    private func infoWell(icon: String, title: String?, message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            IconBadge(systemName: icon, tint: Theme.Colors.muted)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if let title {
                    Text(title)
                        .zanoText(.headline)
                        .foregroundStyle(Theme.Colors.text)
                }
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoWell(radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { optIn.optedIn },
                    set: { newValue in Task { await setOptIn(newValue) } }
                )) {
                    Text(Copy.progress.gymBoardPrivacyTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                }
                .tint(Theme.Colors.accentFill)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: Theme.Metrics.minTapTarget + Theme.Spacing.xs)

                if optIn.optedIn {
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                        .padding(.leading, Theme.Spacing.md)
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField(Copy.progress.gymBoardHandlePlaceholder, text: $handleDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .submitLabel(.done)
                            .onSubmit { Task { await saveHandle() } }
                        Button(Copy.progress.gymBoardHandleSave) {
                            Task { await saveHandle() }
                        }
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.accent)
                        .disabled(handleDraft == (optIn.handle ?? ""))
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
            .zanoCard(radius: Theme.Radius.medium)

            Text(handleError ?? Copy.progress.gymBoardPrivacyFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(handleError == nil ? Theme.Colors.muted : Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xs)
        }
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: optIn.optedIn)
    }

    // MARK: - Actions

    private func load() async {
        let manager = GymLeaderboardManager.shared
        optIn = await manager.optInStatus()
        handleDraft = optIn.handle ?? ""
        score = try? await manager.myConsistencyScore()

        guard let gymID = selectedGym?.id else { return }
        guard await manager.isBackendConfigured else {
            board = .offline
            return
        }
        do {
            board = .loaded(try await manager.leaderboard(gymID: gymID))
        } catch GymLeaderboardManagerError.backendUnavailable {
            board = .offline
        } catch {
            board = .failed
        }
    }

    private func setOptIn(_ on: Bool) async {
        toggleTick += 1
        handleError = nil
        let manager = GymLeaderboardManager.shared
        if on {
            do {
                optIn = try await manager.optIn(handle: handleDraft)
            } catch GymLeaderboardManagerError.invalidHandle {
                // Opt in anonymously; keep the draft so it can be fixed.
                optIn = (try? await manager.optIn(handle: nil)) ?? optIn
                handleError = Copy.progress.gymBoardHandleInvalid
            } catch {
                handleError = Copy.progress.gymBoardErrorMessage
            }
        } else {
            await manager.optOut()
            optIn = await manager.optInStatus()
        }
        await load()
    }

    private func saveHandle() async {
        handleError = nil
        do {
            optIn = try await GymLeaderboardManager.shared.updateHandle(handleDraft)
            handleDraft = optIn.handle ?? ""
        } catch {
            handleError = Copy.progress.gymBoardHandleInvalid
        }
    }
}

/// One ranked row. Your own row is marked in accent; everyone else is a rank, a handle (or
/// "Anonymous") and a percentage — nothing else about them is ever shown.
private struct BoardRow: View {
    let entry: GymLeaderboardEntry

    private var name: String {
        let base = entry.handle ?? Copy.progress.gymBoardAnonymous
        return entry.isCurrentUser ? "\(base) \(Copy.progress.gymBoardYouSuffix)" : base
    }

    private var percent: Int { Int((entry.consistency * 100).rounded()) }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(Copy.progress.gymBoardRankLabel(entry.rank))
                .font(Theme.Typography.numeral(size: 20, weight: .heavy))
                .foregroundStyle(entry.isCurrentUser ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .frame(minWidth: 40, alignment: .leading)
            Text(name)
                .font(entry.isCurrentUser ? Theme.Typography.captionEmphasized : Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            Text(Copy.progress.gymBoardPercent(percent))
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: Theme.Metrics.minTapTarget + Theme.Spacing.xs)
        .background(entry.isCurrentUser ? Theme.Colors.accentWash : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.progress.gymBoardRowAccessibility(rank: entry.rank, name: name, percent: percent))
    }
}
