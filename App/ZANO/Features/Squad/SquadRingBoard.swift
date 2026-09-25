// SquadRingBoard.swift
// App / ZANO / Features / Squad
//
// docs/spec.md §5.7: "each member's daily rings visible; one-tap 'nudge'". One card per member:
// name, owner/lock badges, streak, full-day stars, and seven small day rings (Monday first, today
// emphasized). Your own row is computed live from this phone; squadmates' rows come from the
// backend's ring source, so without it they show an honest "syncs when live" line instead of
// empty rings pretending to be zero.
//
// `NudgeButton` enforces the squad nudge cap (2 per member per day, `SquadManager.
// dailyNudgeCapPerMember`, spec §8 rule 7) by showing what's left and disabling at zero; the
// manager enforces it again on send.

import SwiftUI
import Core

struct SquadRingBoard: View {
    let rows: [SquadMemberRow]
    let weekStart: Date
    let backendConnected: Bool
    let onNudge: @MainActor (SquadMemberRow) async -> String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(rows) { row in
                SquadMemberCard(row: row, weekStart: weekStart, backendConnected: backendConnected, onNudge: onNudge)
            }
        }
    }
}

private struct SquadMemberCard: View {
    let row: SquadMemberRow
    let weekStart: Date
    let backendConnected: Bool
    let onNudge: @MainActor (SquadMemberRow) async -> String

    private var todayIndex: Int? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let days = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: .now)).day ?? -1
        return (0..<7).contains(days) ? days : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if row.dataAvailable, row.days.count == 7 {
                dayRings
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.muted)
                        .accessibilityHidden(true)
                    Text(Copy.squad.ringsPendingSync)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard(tint: row.isMe ? Theme.Colors.accent : nil, active: row.fullDays >= 7)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(row.name)
                        .zanoText(.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                    if row.isOwner {
                        Text(Copy.squad.ownerBadge)
                            .zanoText(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                statusLine
            }
            Spacer(minLength: Theme.Spacing.xs)
            if !row.isMe {
                NudgeButton(row: row, backendConnected: backendConnected, onNudge: onNudge)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(row.isMe ? Theme.Colors.accentWash : Theme.Colors.surface2)
            Image(systemName: row.isMe ? "person.fill" : "person")
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(row.isMe ? Theme.Colors.accent : Theme.Colors.textSecondary)
        }
        .frame(width: 40, height: 40)
        .overlay(alignment: .bottomTrailing) {
            if let locked = row.isLocked {
                Circle()
                    .fill(locked ? Theme.Colors.lockedAmbient : Theme.Colors.accent)
                    .overlay(
                        Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.Colors.onAccent)
                    )
                    .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 1.5))
                    .frame(width: 16, height: 16)
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let locked = row.isLocked {
                Text(locked ? Copy.squad.lockedBadge : Copy.squad.unlockedBadge)
                    .zanoText(.caption)
                    .foregroundStyle(locked ? Theme.Colors.textSecondary : Theme.Colors.accent)
            } else {
                Text(Copy.squad.lockUnknown)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            if row.dataAvailable {
                Label(Copy.squad.starsLabel(row.fullDays), systemImage: "star.fill")
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(row.fullDays > 0 ? Theme.Colors.Ring.sunriseAlarm : Theme.Colors.muted)
                    .accessibilityLabel(Copy.squad.starsAccessibility(row.fullDays))
            }
            if let streak = row.streak {
                Label(Copy.squad.streakLabel(streak), systemImage: "flame.fill")
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(streak > 0 ? Theme.Colors.Ring.protein : Theme.Colors.muted)
                    .accessibilityLabel(Copy.squad.streakAccessibility(streak))
            }
        }
    }

    private var dayRings: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.days.enumerated()), id: \.offset) { index, day in
                let isToday = index == todayIndex
                let isFuture = todayIndex.map { index > $0 } ?? false
                VStack(spacing: 4) {
                    GoalRing(
                        progress: isFuture ? 0 : day.fraction,
                        color: isToday ? Theme.Colors.accent : Theme.Colors.textSecondary,
                        size: .custom(isToday ? 30 : 24)
                    )
                    .opacity(isFuture ? 0.35 : 1)
                    .frame(height: 30)
                    Text(Copy.squad.dayLetters[index])
                        .font(.system(size: 10, weight: isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? Theme.Colors.text : Theme.Colors.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.squad.dayRingAccessibility(
                    day: Copy.squad.dayLetters[index],
                    completed: day.completedGoals,
                    total: day.totalGoals
                ))
            }
        }
    }
}

/// Icon + numeral, tight, in caption type.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(Theme.Typography.icon(.xsmall))
            configuration.title.font(Theme.Typography.captionEmphasized).monospacedDigit()
        }
    }
}

// MARK: - Nudge

/// One-tap nudge with the per-member daily cap shown right on it.
struct NudgeButton: View {
    let row: SquadMemberRow
    let backendConnected: Bool
    let onNudge: @MainActor (SquadMemberRow) async -> String

    @State private var isSending = false
    @State private var feedback: String?
    @State private var sentTick = 0

    private var capped: Bool { row.nudgesLeft <= 0 }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                guard !isSending, !capped else { return }
                isSending = true
                Task { @MainActor in
                    let message = await onNudge(row)
                    feedback = message
                    sentTick += 1
                    isSending = false
                }
            } label: {
                HStack(spacing: 4) {
                    if isSending {
                        SwiftUI.ProgressView().controlSize(.mini).tint(Theme.Colors.onAccent)
                    } else {
                        Image(systemName: "hand.wave.fill")
                            .font(Theme.Typography.icon(.xsmall))
                    }
                    Text(Copy.squad.nudgeButton)
                        .font(Theme.Typography.captionEmphasized)
                }
                .foregroundStyle(capped ? Theme.Colors.muted : Theme.Colors.onAccent)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(minHeight: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(capped ? Theme.Colors.surface2 : Theme.Colors.accentFill)
                )
                .contentShape(Capsule())
                .frame(minHeight: Theme.Metrics.minTapTarget)
            }
            .buttonStyle(.pressable(scale: 0.94))
            .disabled(capped || isSending)
            .sensoryFeedback(.impact(weight: .light), trigger: sentTick)
            .accessibilityLabel(Copy.squad.nudgeAccessibility(name: row.name))
            .accessibilityValue(capped ? Copy.squad.nudgeCapReached : Copy.squad.nudgesLeft(row.nudgesLeft))

            Text(feedback ?? (capped ? Copy.squad.nudgeCapReached : Copy.squad.nudgesLeft(row.nudgesLeft)))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140, alignment: .trailing)
                .accessibilityHidden(feedback == nil)
        }
        .task(id: sentTick) {
            guard sentTick > 0 else { return }
            try? await Task.sleep(for: .seconds(3))
            feedback = nil
        }
    }
}
