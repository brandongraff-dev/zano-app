// FocusLockSettingsView.swift
// App / ZANO / Features / FocusLock
//
// Settings > Focus lock (session 17; docs/spec.md §5.24): lock distracting apps during meetings and
// focus blocks on the user's calendar, open them again when the block ends. One switch (which asks for
// Calendar access), what to lock for (meetings, focus blocks), which lock set to shield, the questions
// waiting for a yes or no ("Lock during 'Design review'?"), and the locks coming up. The calendar is
// read on this phone only; the learning (two yes answers and it locks by itself, two no's and it
// stops asking) lives in `FocusLockStore`. Everything here is plain copy from `Copy.focusLock`.

import SwiftUI
import SwiftData
import UIKit
import Core

struct FocusLockSettingsView: View {
    @Query(sort: \LockSet.name) private var lockSets: [LockSet]
    @Environment(\.openURL) private var openURL

    @State private var settings = FocusLockStore.settings
    @State private var pending = FocusLockStore.pendingProposals
    @State private var upcoming = FocusLockStore.armedWindows
    @State private var accessDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.focusLock.intro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                masterToggle

                if accessDenied { accessOffCard }

                if settings.isEnabled {
                    whatSection
                    appsSection
                    if !pending.isEmpty { askSection }
                    upcomingSection
                }

                Text(Copy.focusLock.privacyNote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.focusLock.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if settings.isEnabled { FocusLockScheduler.shared.refresh() }
            reload()
        }
    }

    // MARK: Pieces

    private var masterToggle: some View {
        Toggle(Copy.focusLock.toggleLabel, isOn: enabledBinding)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .padding(Theme.Spacing.md)
            .zanoCard()
    }

    private var accessOffCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.focusLock.accessOffTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(Copy.focusLock.accessOffMessage)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: Copy.focusLock.openSettingsButton, style: .secondary) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.focusLock.whatSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Toggle(isOn: setting(\.includeMeetings)) {
                    detailLabel(Copy.focusLock.meetingsLabel, Copy.focusLock.meetingsDetail)
                }
                Toggle(isOn: setting(\.includeFocusBlocks)) {
                    detailLabel(Copy.focusLock.focusBlocksLabel, Copy.focusLock.focusBlocksDetail(keywords: settings.keywords))
                }
            }
            .padding(Theme.Spacing.md)
            .zanoCard()
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.focusLock.appsSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Picker(Copy.focusLock.appsSectionTitle, selection: lockSetBinding) {
                Text(Copy.focusLock.defaultAppsLabel).tag(UUID?.none)
                ForEach(lockSets, id: \.id) { set in
                    Text(set.name).tag(UUID?.some(set.id))
                }
            }
            .pickerStyle(.menu)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
        }
    }

    private var askSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.focusLock.askSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            ForEach(pending) { proposal in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Copy.focusLock.askTitle(eventTitle: proposal.window.title))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Copy.focusLock.windowLine(start: proposal.window.start, end: proposal.window.end))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                    HStack(spacing: Theme.Spacing.xs) {
                        PrimaryButton(title: Copy.focusLock.yesButton) {
                            FocusLockScheduler.shared.accept(proposal)
                            reload()
                        }
                        PrimaryButton(title: Copy.focusLock.noButton, style: .secondary) {
                            FocusLockScheduler.shared.decline(proposal)
                            reload()
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .zanoCard()
            }
            Text(Copy.focusLock.askFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.focusLock.upcomingSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            if upcoming.isEmpty {
                Text(Copy.focusLock.upcomingEmpty)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(upcoming) { window in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(window.title.isEmpty ? Copy.focusLock.reasonLabel(window.reason, mergedCount: window.mergedCount) : window.title)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.text)
                                .lineLimit(2)
                            Text(Copy.focusLock.windowLine(start: window.start, end: window.end))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                        Spacer(minLength: Theme.Spacing.xs)
                        Button(Copy.focusLock.askAgainButton) {
                            FocusLockScheduler.shared.forget(patternKey: window.patternKey)
                            reload()
                        }
                        .font(Theme.Typography.captionEmphasized)
                        .buttonStyle(.pressable(scale: 0.94))
                    }
                    .padding(Theme.Spacing.md)
                    .zanoCard()
                }
            }
            Text(Copy.focusLock.emergencyNote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: State

    private func reload() {
        settings = FocusLockStore.settings
        pending = FocusLockStore.pendingProposals
        upcoming = FocusLockStore.armedWindows
    }

    private func commit(_ next: FocusLockSettings) {
        settings = next
        FocusLockScheduler.shared.save(next)
        reload()
    }

    private func setting(_ keyPath: WritableKeyPath<FocusLockSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var next = settings
                next[keyPath: keyPath] = value
                commit(next)
            }
        )
    }

    private var lockSetBinding: Binding<UUID?> {
        Binding(
            get: { settings.lockSetID },
            set: { value in
                var next = settings
                next.lockSetID = value
                commit(next)
            }
        )
    }

    /// Turning the switch on asks for Calendar access; if it's refused the switch stays off and the
    /// card explains how to allow it.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { value in
                guard value else {
                    var next = settings
                    next.isEnabled = false
                    commit(next)
                    return
                }
                Task {
                    let granted = FocusLockCalendarSource.hasAccess
                        ? true
                        : await FocusLockCalendarSource.shared.requestAccess()
                    accessDenied = !granted
                    var next = settings
                    next.isEnabled = granted
                    commit(next)
                }
            }
        )
    }
}

#Preview {
    NavigationStack { FocusLockSettingsView() }
        .preferredColorScheme(.dark)
}
