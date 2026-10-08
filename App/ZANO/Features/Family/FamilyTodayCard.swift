// FamilyTodayCard.swift
// App / ZANO / Features / Family
//
// A small Today card for someone in a household (session 47; docs/spec.md §5.31): the family's buddies side by
// side, the household's name, and "Open" to the Family page. "Hide" puts it away for good on this phone (the
// Family page stays in Settings). Draws nothing when Household isn't live or there is no household in the cache.

import SwiftUI
import Core

struct FamilyTodayCard: View {
    let onOpen: () -> Void

    @AppStorage("today.familyCardDismissed") private var dismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var household: Household? = HouseholdEventStore.household
    @State private var members: [HouseholdMember] = HouseholdEventStore.members
    @State private var me: UUID? = HouseholdEventStore.me

    var body: some View {
        Group {
            if !dismissed, HouseholdAvailability.isLive, let household {
                HStack(spacing: Theme.Spacing.sm) {
                    // The family, small and overlapping, like a group photo. Decorative: the text says it.
                    HStack(spacing: -Theme.Spacing.sm) {
                        ForEach(FamilyPortrait.ordered(members).prefix(4)) { member in
                            HouseholdMemberBuddy(member: member, isMe: member.userId == me, size: 32)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(household.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        Text(Copy.familyHub.todayDetail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(Copy.familyHub.todayOpen, action: onOpen)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                    Button {
                        withAnimation(Theme.Motion.standard(reduceMotion: reduceMotion)) { dismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(Theme.Typography.icon(.xsmall, weight: .bold))
                            .foregroundStyle(Theme.Colors.muted)
                            .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Copy.familyHub.todayHide)
                }
                .padding(.leading, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .zanoCard(radius: Theme.Radius.medium)
                .accessibilityElement(children: .contain)
                .transition(.opacity)
            }
        }
        .onAppear {
            household = HouseholdEventStore.household
            members = HouseholdEventStore.members
            me = HouseholdEventStore.me
        }
    }
}
