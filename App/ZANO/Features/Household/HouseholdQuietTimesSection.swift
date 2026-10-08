// HouseholdQuietTimesSection.swift
// App / ZANO / Features / Household
//
// "Screen-free times" on the Household screen (session 44; docs/spec.md §5.31): the household's shared windows
// (dinner, bedtime), each with a "Join" switch for THIS phone and, once joined, which of this phone's lock sets
// it locks. Joining, leaving and the lock set never leave the phone (`HouseholdQuietTimeStore`); nobody can
// lock anyone else's phone. The creator or the owner can edit or delete a window. Wording: `Copy.household`.
// Only reachable inside `HouseholdView`, which is itself hidden until `HouseholdAvailability.isLive`.

import SwiftUI
import SwiftData
import Core

struct HouseholdQuietTimesSection: View {
    let household: Household
    let me: UUID?
    let members: [HouseholdMember]
    let quietTimes: [HouseholdQuietTime]
    /// Called after an add, edit or delete so the screen re-fetches.
    let onChanged: () -> Void

    @Query(sort: \LockSet.name) private var lockSets: [LockSet]
    @State private var optIns: [HouseholdQuietTimeOptIn] = []
    @State private var editing: EditTarget?
    @State private var notes: [UUID: String] = [:]

    enum EditTarget: Identifiable {
        case new
        case edit(HouseholdQuietTime)

        var window: HouseholdQuietTime? {
            if case .edit(let window) = self { return window }
            return nil
        }

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let window): window.id.uuidString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.household.quietTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.household.quietIntro)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if quietTimes.isEmpty {
                Text(Copy.household.quietEmpty)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            ForEach(quietTimes) { window in
                row(window)
            }
            PrimaryButton(title: Copy.household.quietAdd, systemImage: "plus", style: .secondary) {
                editing = .new
            }
            Text(Copy.household.quietPrivacyNote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
        .onAppear { optIns = HouseholdQuietTimeStore.optIns }
        .onChange(of: quietTimes) { _, _ in optIns = HouseholdQuietTimeStore.optIns }
        .sheet(item: $editing) { target in
            HouseholdQuietTimeEditor(
                householdID: household.id,
                existing: target.window,
                onSaved: onChanged
            )
        }
    }

    // MARK: Row

    private func row(_ window: HouseholdQuietTime) -> some View {
        let optIn = optIns.first { $0.windowID == window.id }
        let joined = HouseholdQuietTimeStore.joinedWindows
        let canJoin = optIn != nil || HouseholdQuietTimePlanner.canJoin(window, joined: joined)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.household.quietWindowLine(startMinute: window.startMinute, endMinute: window.endMinute, weekdays: window.weekdaySet))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                    if let who = HouseholdBoard.name(for: window.createdBy, members: members, me: me) {
                        Text(Copy.household.quietCreatedBy(who))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(Copy.household.quietJoin, isOn: joinBinding(window))
                    .labelsHidden()
                    .disabled(!canJoin)
                    .accessibilityLabel(Copy.household.quietJoin + ", " + window.name)
            }
            if optIn != nil {
                Picker(Copy.household.quietAppsLabel, selection: lockSetBinding(window)) {
                    Text(Copy.household.quietDefaultApps).tag(UUID?.none)
                    ForEach(lockSets, id: \.id) { set in
                        Text(set.name).tag(UUID?.some(set.id))
                    }
                }
                .pickerStyle(.menu)
                Text(Copy.household.quietJoinedNote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !canJoin {
                Text(Copy.household.quietTooMany)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = notes[window.id] {
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canEdit(window) {
                Button(Copy.household.quietEdit) { editing = .edit(window) }
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func canEdit(_ window: HouseholdQuietTime) -> Bool {
        guard let me else { return false }
        return window.createdBy == me || household.ownerId == me
    }

    // MARK: Bindings (this phone only)

    private func joinBinding(_ window: HouseholdQuietTime) -> Binding<Bool> {
        Binding(
            get: { optIns.contains { $0.windowID == window.id } },
            set: { on in
                Task {
                    let scheduler = HouseholdQuietTimeScheduler.shared
                    if on {
                        let underWay = window.occurrence(containing: .now) != nil
                        let ok = await scheduler.join(window, lockSetID: nil)
                        notes[window.id] = ok ? (underWay ? Copy.household.quietStartsNextTime : nil) : Copy.household.quietTooMany
                    } else {
                        await scheduler.leave(window)
                        notes[window.id] = nil
                    }
                    optIns = HouseholdQuietTimeStore.optIns
                }
            }
        )
    }

    private func lockSetBinding(_ window: HouseholdQuietTime) -> Binding<UUID?> {
        Binding(
            get: { optIns.first { $0.windowID == window.id }?.lockSetID },
            set: { value in
                Task {
                    await HouseholdQuietTimeScheduler.shared.join(window, lockSetID: value)
                    optIns = HouseholdQuietTimeStore.optIns
                }
            }
        )
    }
}
