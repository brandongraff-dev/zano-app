// BreakCoachCard.swift
// App / ZANO / Features / Today
//
// After a verified focus block: "Nice block. Take 5 minutes." with one thing to do (water, stretch, look
// away, walk) from `BreakCoach` (session 25; docs/spec.md §5.29). Shows for 15 minutes, never while a
// block is running, and "Done" hides it for that block. It only suggests rest: nothing is locked.

import SwiftUI
import SwiftData
import Core

struct BreakCoachCard: View {
    @Query private var events: [GoalEvent]
    @AppStorage("breakCoach.dismissedEndedAt") private var dismissedAt: Double = 0

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        _events = Query(filter: #Predicate<GoalEvent> { $0.ts >= start })
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let suggestion = suggestion(now: context.date) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    StoredBuddySprite(pose: icon(for: suggestion.activity), size: 48)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(Copy.breakCoach.title(suggestion))
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Copy.breakCoach.line(suggestion.activity))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(Copy.breakCoach.done) { dismissedAt = suggestion.expiresAt.timeIntervalSince1970 }
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(minHeight: Theme.Metrics.minTapTarget)
                            .buttonStyle(.pressable(scale: 0.96))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.Spacing.md)
                .zanoCard(radius: Theme.Radius.medium)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func suggestion(now: Date) -> BreakSuggestion? {
        let blocks = events
            .filter { $0.verified && $0.source == .timer && $0.kind != .miss && $0.goal?.type == .focusSession }
            .map { BreakCoach.Block(endedAt: $0.ts, minutes: $0.value ?? 0) }
        let result = BreakCoach.suggestion(
            blocks: blocks,
            isFocusing: FocusSessionVerifier.shared.activeSession != nil,
            now: now
        )
        guard let result, result.expiresAt.timeIntervalSince1970 != dismissedAt else { return nil }
        return result
    }

    private func icon(for activity: BreakActivity) -> BuddyPose {
        switch activity {
        case .water: return .sipping
        case .stretch: return .yawning
        case .lookAway: return .happy
        case .walk: return .proud
        }
    }
}
