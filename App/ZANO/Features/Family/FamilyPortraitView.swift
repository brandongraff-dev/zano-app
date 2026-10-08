// FamilyPortraitView.swift
// App / ZANO / Features / Family
//
// "The family portrait" (session 47; docs/spec.md §5.31): every household member as the buddy they picked, in their
// outfit, standing together on a soft glass stage with their names underneath. Up to four stand in one row; a
// bigger family stands in two (`FamilyPortrait.rows`). Each buddy breathes with a gentle idle bob, out of step with
// its neighbours, and holds still under Reduce Motion. Tapping a buddy opens that person's card
// (`FamilyMemberCard`): name, buddy, and what you share with them.
//
// Accessibility: one element per member ("Sam, Lox"), a button; the stage and glow are decorative and hidden.
// The buddies are drawn with the same pixel pipeline as `BuddySprite` (`Buddy.image(pose:gear:outfit:)`); my own
// buddy is my stored `BuddySprite`, so it matches everywhere else in the app.

import SwiftUI
import Core

struct FamilyPortraitView: View {
    let title: String
    /// Everyone in the household. Empty = just me (no household yet, or Household isn't live).
    let members: [HouseholdMember]
    let me: UUID?
    let onSelect: (HouseholdMember) -> Void

    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var myBuddy: Buddy = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [[HouseholdMember]] { FamilyPortrait.rows(members) }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xxs) {
                Text(title)
                    .zanoText(.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.familyHub.memberCount(max(members.count, 1)))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            ZStack(alignment: .bottom) {
                stage
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    VStack(spacing: -Theme.Spacing.xs) {
                        if rows.isEmpty {
                            soloBuddy(t: t)
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                                let isBack = rows.count > 1 && rowIndex == 0
                                HStack(alignment: .bottom, spacing: isBack ? Theme.Spacing.md : Theme.Spacing.xs) {
                                    ForEach(Array(row.enumerated()), id: \.element.id) { index, member in
                                        standing(member, size: CGFloat(FamilyPortrait.spriteSize(count: members.count, isBackRow: isBack)),
                                                 bob: bobOffset(t: t, seed: rowIndex * 4 + index))
                                    }
                                }
                                .opacity(isBack ? 0.92 : 1)
                            }
                        }
                    }
                    .padding(.bottom, Theme.Spacing.sm)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .zanoHero(tint: Theme.Colors.Aurora.violet)
    }

    /// The soft glass floor they stand on, with a little light from above. Decorative.
    private var stage: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(
                    colors: [Theme.Colors.Aurora.violet.opacity(0.35), .clear],
                    center: .center, startRadius: 4, endRadius: 160
                ))
                .frame(height: 120)
                .offset(y: -40)
            Ellipse()
                .fill(Theme.Colors.glassFill)
                .overlay(Ellipse().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
                .frame(height: 36)
                .padding(.horizontal, Theme.Spacing.md)
        }
        .accessibilityHidden(true)
    }

    /// Up to 3pt of bob, each buddy out of step with its neighbours.
    private func bobOffset(t: TimeInterval, seed: Int) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let period = Theme.Motion.idleBobPeriod + Double(seed % 3) * 0.4
        return CGFloat(sin(t * 2 * .pi / period + Double(seed) * 1.3)) * 3
    }

    private func soloBuddy(t: TimeInterval) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            BuddySprite(myBuddy, pose: .happy, size: 96)
                .offset(y: bobOffset(t: t, seed: 0))
            nameTag(Copy.familyHub.you)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.familyHub.memberLabel(name: Copy.familyHub.you, buddy: myBuddy))
    }

    private func standing(_ member: HouseholdMember, size: CGFloat, bob: CGFloat) -> some View {
        let isMe = member.userId == me
        let buddy = isMe ? myBuddy : member.buddyChoice
        let name = isMe ? Copy.familyHub.you : member.displayName
        return Button { onSelect(member) } label: {
            VStack(spacing: Theme.Spacing.xxs) {
                HouseholdMemberBuddy(member: member, isMe: isMe, pose: isMe ? .happy : .idle, size: size)
                    .offset(y: bob)
                nameTag(name)
                    .frame(maxWidth: size + Theme.Spacing.md)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.familyHub.memberLabel(name: name, buddy: buddy))
        .accessibilityHint(Copy.familyHub.memberHint)
        .accessibilityAddTraits(.isButton)
    }

    private func nameTag(_ name: String) -> some View {
        Text(name)
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// One household member's buddy in their outfit (display only). My own is my stored `BuddySprite`. Decorative.
struct HouseholdMemberBuddy: View {
    let member: HouseholdMember?
    let isMe: Bool
    var pose: BuddyPose = .idle
    var size: CGFloat = 32

    var body: some View {
        if isMe {
            StoredBuddySprite(pose: pose, size: size)
        } else {
            // Someone who left (or isn't cached yet) shows as the default buddy, bare.
            let buddy = member?.buddyChoice ?? .default
            Group {
                if let image = buddy.image(pose: pose, gear: .bare, outfit: member?.outfit ?? BuddyOutfit()) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                } else {
                    Color.clear
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

/// A member's card, from tapping their buddy: name, buddy, role, and what you share with them.
struct FamilyMemberCard: View {
    let member: HouseholdMember
    let isMe: Bool
    let isOwner: Bool
    let sharedEventCount: Int

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Buddy.storageKey, store: SharedDefaults.store) private var myBuddy: Buddy = .default

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        HouseholdMemberBuddy(member: member, isMe: isMe, pose: .happy, size: 96)
                        Text(isMe ? Copy.familyHub.you : member.displayName)
                            .zanoText(.title)
                            .foregroundStyle(Theme.Colors.text)
                        Text(Copy.familyHub.buddyLine(isMe ? myBuddy : member.buddyChoice))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                        if isOwner {
                            ZanoGlassChip(Copy.familyHub.owner, systemImage: "house.fill")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(Copy.familyHub.whatYouShare)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .accessibilityAddTraits(.isHeader)
                        shareLine(Copy.familyHub.shareChores, systemImage: "checklist")
                        shareLine(Copy.familyHub.shareQuietTimes, systemImage: "moon.stars.fill")
                        shareLine(Copy.familyHub.shareBuddy, systemImage: "face.smiling")
                        if !isMe && sharedEventCount > 0 {
                            shareLine(Copy.familyHub.shareEvents(sharedEventCount), systemImage: "calendar")
                        }
                        Text(Copy.familyHub.privateNote)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zanoCard()
                }
                .padding(Theme.Spacing.md)
            }
            .zanoBackdrop()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.familyHub.close) { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents([.medium, .large])
    }

    private func shareLine(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.Colors.accent)
        }
    }
}
