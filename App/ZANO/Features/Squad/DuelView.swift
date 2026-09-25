// DuelView.swift
// App / ZANO / Features / Squad
//
// docs/spec.md §5.7 "Duel: 7-day head-to-head, points per verified goal" and §5.4 Ghost Mode.
//
//   - `DuelView`: a head-to-head duel's scoreboard, countdown and result. Your side is recomputed
//     from this phone's verified goals on appear (`DuelManager.recomputeLocalPoints`); the
//     opponent's side only exists once the backend syncs it, so offline it reads "–" with a note
//     rather than a fake 0.
//   - `SoloDuelView`: "Beat last week" — the same scoring against your own previous week, day by
//     day, from local history only. Always works offline.
//
// No shame (spec §8 rule 9): a lost duel is "slipped", with the next step right there.

import SwiftUI
import Core

// MARK: - Shared pieces

/// "3d 4h left" to `end`, refreshed each minute by the caller's `TimelineView`.
private func countdownText(to end: Date, now: Date) -> String {
    let remaining = max(0, end.timeIntervalSince(now))
    guard remaining >= 3600 else { return Copy.squad.endsSoon }
    let totalHours = Int(remaining / 3600)
    return Copy.squad.countdown(days: totalHours / 24, hours: totalHours % 24)
}

/// Thin progress bar for how far through the 7 days we are.
private struct DuelTimeBar: View {
    let start: Date
    let end: Date
    let now: Date

    var body: some View {
        let total = max(1, end.timeIntervalSince(start))
        let fraction = min(1, max(0, now.timeIntervalSince(start) / total))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.track)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// One side of a scoreboard: label over a big numeral.
private struct ScoreColumn: View {
    let label: String
    let value: String
    let highlighted: Bool
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xxs) {
            Text(label)
                .zanoText(.captionEmphasized)
                .foregroundStyle(highlighted ? Theme.Colors.accent : Theme.Colors.muted)
                .lineLimit(1)
            Text(value)
                .font(Theme.Typography.numeral(size: 56, weight: .heavy))
                .foregroundStyle(highlighted ? Theme.Colors.text : Theme.Colors.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Head-to-head

struct DuelView: View {
    let myUserID: UUID
    let opponentName: String
    let backendConnected: Bool

    @State private var duel: DuelSnapshot
    @State private var burstTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(duel: DuelSnapshot, myUserID: UUID, opponentName: String, backendConnected: Bool) {
        self.myUserID = myUserID
        self.opponentName = opponentName
        self.backendConnected = backendConnected
        _duel = State(initialValue: duel)
    }

    private var isA: Bool { duel.aUser == myUserID }
    private var myPoints: Int { isA ? duel.aPoints : duel.bPoints }
    private var theirPoints: Int { isA ? duel.bPoints : duel.aPoints }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                switch duel.status {
                case .pending:
                    pendingCard
                case .active, .complete, .declined:
                    scoreboard
                    if duel.status == .complete {
                        resultCard
                    }
                }
                rulesCard
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .overlay { CelebrationBurst(trigger: burstTick) }
        .zanoAmbient(duel.status == .complete && duel.winner == myUserID ? .earned : .neutral)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.squad.duelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .sensoryFeedback(.success, trigger: burstTick)
    }

    private func refresh() async {
        let manager = DuelManager.shared
        _ = try? await manager.refreshStatuses()
        let id = duel.id
        if let updated = try? await manager.recomputeLocalPoints(duelID: id) {
            withAnimation(Theme.Motion.standard(reduceMotion: reduceMotion)) { duel = updated }
        }
        if duel.status == .complete, duel.winner == myUserID, !reduceMotion {
            burstTick += 1
        }
    }

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .bottom) {
                ScoreColumn(label: Copy.squad.youLabel, value: "\(myPoints)", highlighted: myPoints >= theirPoints, alignment: .leading)
                Text(Copy.squad.versus)
                    .zanoText(.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.bottom, Theme.Spacing.sm)
                    .accessibilityHidden(true)
                ScoreColumn(
                    label: opponentName,
                    value: backendConnected ? "\(theirPoints)" : Copy.squad.opponentScoreUnknown,
                    highlighted: backendConnected && theirPoints > myPoints,
                    alignment: .trailing
                )
            }
            Text(Copy.squad.pointsUnit)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            if duel.status == .active {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        DuelTimeBar(start: duel.startDate, end: duel.endDate, now: context.date)
                        HStack {
                            ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.squad.activeStatus)
                            Spacer()
                            Text(countdownText(to: duel.endDate, now: context.date))
                                .zanoText(.captionEmphasized)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if !backendConnected {
                Label(Copy.squad.opponentScorePending, systemImage: "icloud.and.arrow.down")
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .padding(Theme.Spacing.lg)
        .zanoHero(tint: Theme.Colors.accent, active: duel.status == .complete && duel.winner == myUserID)
    }

    private var resultCard: some View {
        let winner = duel.winner
        let title: String
        let subtitle: String?
        if winner == nil {
            title = Copy.squad.resultTie
            subtitle = nil
        } else if winner == myUserID {
            title = Copy.squad.resultWin
            subtitle = nil
        } else {
            title = Copy.squad.resultLoss
            subtitle = Copy.squad.resultSubtitleLoss
        }
        return HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            IconBadge(systemName: winner == myUserID ? "trophy.fill" : "flag.checkered", tint: winner == myUserID ? Theme.Colors.accent : Theme.Colors.muted)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .zanoText(.title)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.squad.scoreLine(me: myPoints, them: theirPoints))
                    .zanoText(.captionEmphasized)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                if let subtitle {
                    Text(subtitle)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .zanoCard(tint: winner == myUserID ? Theme.Colors.accent : nil, active: winner == myUserID)
    }

    private var pendingCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            IconBadge(systemName: "hourglass", size: .large)
            Text(Copy.squad.pendingTitle)
                .zanoText(.titleLarge)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.squad.pendingBody)
                .zanoText(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Text(Copy.squad.friendDuelRowTitle(name: opponentName))
                .zanoText(.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .zanoHero()
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label(Copy.squad.pointsRule, systemImage: "checkmark.seal")
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Label(Copy.squad.tauntNote, systemImage: "shield.lefthalf.filled")
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }
}

// MARK: - Solo ("Beat last week")

struct SoloDuelView: View {
    @State private var solo: SoloWeekDuel?
    @State private var previous: SoloWeekDuel?
    @State private var loaded = false
    @State private var beatTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    ZanoStatusCapsule(dotColor: Theme.Colors.accent, text: Copy.squad.worksOffline)
                    Spacer()
                }
                if let solo {
                    scoreboard(solo)
                    dailyBreakdown(solo)
                    if let previous, previous.thisWeekPoints > 0 || previous.lastWeekTotal > 0 {
                        previousResult(previous)
                    }
                } else if loaded {
                    Text(Copy.squad.errorNoUser)
                        .zanoText(.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .zanoCard()
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                        .fill(Theme.Colors.surface)
                        .frame(height: 240)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .overlay { CelebrationBurst(trigger: beatTick) }
        .zanoAmbient(solo.map { $0.lastWeekTotal > 0 && $0.pointsToBeatLastWeek == 0 } == true ? .earned : .neutral)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.squad.soloDuelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: beatTick)
    }

    private func load() async {
        let manager = DuelManager.shared
        let current = await manager.soloWeekDuel()
        var earlier: SoloWeekDuel?
        if let current {
            earlier = await manager.soloWeekDuel(asOf: current.weekStart.addingTimeInterval(-60))
        }
        withAnimation(Theme.Motion.standard(reduceMotion: reduceMotion)) {
            solo = current
            previous = earlier
            loaded = true
        }
        if let current, current.hasLastWeek, current.pointsToBeatLastWeek == 0, !reduceMotion {
            beatTick += 1
        }
    }

    private func scoreboard(_ solo: SoloWeekDuel) -> some View {
        let delta = solo.thisWeekPoints - solo.lastWeekPointsToDate
        let pace: String = delta > 0 ? Copy.squad.paceAhead(delta)
            : delta < 0 ? Copy.squad.paceBehind(-delta)
            : Copy.squad.paceTied
        let target: String = !solo.hasLastWeek ? Copy.squad.noLastWeek
            : solo.pointsToBeatLastWeek == 0 ? Copy.squad.beatenLastWeek
            : Copy.squad.toBeat(solo.pointsToBeatLastWeek)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .bottom) {
                ScoreColumn(label: Copy.squad.youLabel, value: "\(solo.thisWeekPoints)", highlighted: delta >= 0, alignment: .leading)
                Text(Copy.squad.versus)
                    .zanoText(.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.bottom, Theme.Spacing.sm)
                    .accessibilityHidden(true)
                ScoreColumn(label: Copy.squad.lastWeekLabel, value: "\(solo.lastWeekPointsToDate)", highlighted: delta < 0, alignment: .trailing)
            }
            Text(pace)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(target)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    DuelTimeBar(start: solo.weekStart, end: solo.weekEnd, now: context.date)
                    HStack {
                        Text(Copy.squad.pointsRule)
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(countdownText(to: solo.weekEnd, now: context.date))
                            .zanoText(.captionEmphasized)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .zanoHero(tint: Theme.Colors.accent, active: solo.hasLastWeek && solo.pointsToBeatLastWeek == 0)
    }

    private func dailyBreakdown(_ solo: SoloWeekDuel) -> some View {
        let maxValue = max(1, (solo.thisWeekDaily + solo.lastWeekDaily).max() ?? 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SquadSectionLabel(text: Copy.squad.dailyBreakdownTitle)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    let isFuture = index >= solo.elapsedDays
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 3) {
                            bar(value: solo.lastWeekDaily[index], max: maxValue, color: Theme.Colors.track)
                            bar(value: isFuture ? 0 : solo.thisWeekDaily[index], max: maxValue, color: Theme.Colors.accent)
                        }
                        .frame(height: 72, alignment: .bottom)
                        Text(Copy.squad.dayLetters[index])
                            .font(.system(size: 10, weight: index == solo.elapsedDays - 1 ? .bold : .semibold))
                            .foregroundStyle(index == solo.elapsedDays - 1 ? Theme.Colors.text : Theme.Colors.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(isFuture ? 0.6 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Copy.squad.soloDayAccessibility(day: Copy.squad.dayLetters[index], you: solo.thisWeekDaily[index], lastWeek: solo.lastWeekDaily[index]))
                }
            }
            HStack(spacing: Theme.Spacing.md) {
                legend(color: Theme.Colors.accent, text: Copy.squad.youLabel)
                legend(color: Theme.Colors.track, text: Copy.squad.lastWeekLabel)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private func bar(value: Int, max maxValue: Int, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: 9, height: max(3, 72 * CGFloat(value) / CGFloat(maxValue)))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
                .zanoText(.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .accessibilityHidden(true)
    }

    private func previousResult(_ week: SoloWeekDuel) -> some View {
        let this = week.thisWeekPoints
        let before = week.lastWeekTotal
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SquadSectionLabel(text: Copy.squad.lastWeekResultTitle)
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                IconBadge(systemName: this > before ? "trophy.fill" : "flag.checkered",
                          tint: this > before ? Theme.Colors.accent : Theme.Colors.muted,
                          size: .small)
                Text(Copy.squad.soloResult(won: this > before, tied: this == before, this: this, previous: before))
                    .zanoText(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .zanoCard(tint: this > before ? Theme.Colors.accent : nil)
        }
    }
}
