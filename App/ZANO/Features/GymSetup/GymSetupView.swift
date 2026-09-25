// GymSetupView.swift
// App / ZANO / Features / GymSetup
//
// spec §3 (Workout (gym) Tier A needs a saved, confirmed `Gym`), §9.4 (an auto-detected gym is a
// suggestion until confirmed), §24 (Always location only here, after an explanation; manual
// fallback). The saved-gyms list, moved out of `SettingsView.swift` (was the private
// `GymSetupDetailView`) and extended:
//
//   * add / edit (tap a card, or its menu) / delete (menu or context menu, confirmed by name);
//   * a "Check in now" row into `GymCheckInView` once a confirmed gym exists;
//   * the location permission card (`LocationPermissionPrimer(.always)`) whenever auto check-in
//     isn't fully on, and the Always explainer as a sheet right after the first save;
//   * every save/confirm/delete re-syncs the geofences (`GymPresenceService`).
//
// No `NavigationStack` of its own: pushed from Settings (and Today), so it uses the caller's.

import SwiftUI
import SwiftData
import Core

public struct GymSetupView: View {
    @Query private var gyms: [Gym]
    @Query private var users: [User]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editor: GymEditorTarget?
    @State private var pendingDeletion: Gym?
    @State private var showsSaveError = false
    @State private var isAlwaysPrimerPresented = false
    /// Set by a save from the editor sheet; the primer opens once that sheet has fully dismissed
    /// (presenting a sheet while another is still animating away is dropped by SwiftUI).
    @State private var showsAlwaysPrimerAfterEditor = false
    /// Bumped on confirm / save, for the success haptic (spec §15: haptics on verified events).
    @State private var successTick = 0

    public init() {}

    private var authorization: GymLocationAuthorization { .shared }
    private var userID: UUID? { users.first?.id }

    /// Sorted in Swift: `Gym.name` is optional, and this codebase avoids `SortDescriptor` on an
    /// optional key path it couldn't compile-check.
    private var sortedGyms: [Gym] {
        gyms.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var hasConfirmedGym: Bool { gyms.contains(where: \.confirmed) }

    public var body: some View {
        ScrollView {
            if gyms.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if hasConfirmedGym {
                        checkInRow
                        LocationPermissionPrimer(kind: .always, authorization: authorization)
                    }
                    gymList
                }
                .padding(Theme.Spacing.md)
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: gyms.count)
            }
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: successTick)
        .navigationTitle(Copy.gym.setupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = .add
                } label: {
                    Label(Copy.gym.addButtonLabel, systemImage: "plus")
                }
                .disabled(userID == nil)
            }
        }
        .sheet(item: $editor, onDismiss: {
            if showsAlwaysPrimerAfterEditor {
                showsAlwaysPrimerAfterEditor = false
                isAlwaysPrimerPresented = true
            }
        }) { target in
            AddGymSheet(
                existing: target.draft,
                onSave: { draft in
                    editor = nil
                    save(draft, editing: target.gymID)
                },
                onCancel: { editor = nil }
            )
        }
        .sheet(isPresented: $isAlwaysPrimerPresented) {
            AlwaysLocationPrimerSheet(authorization: authorization) {
                isAlwaysPrimerPresented = false
            }
        }
        .confirmationDialog(
            Copy.gym.deleteConfirmTitle(name: pendingDeletion?.name ?? Copy.gym.unnamedLabel),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in if !isPresented { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { gym in
            Button(Copy.common.delete, role: .destructive) { delete(gym) }
            Button(Copy.common.cancel, role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text(Copy.gym.deleteConfirmMessage)
        }
        .alert(Copy.gym.saveErrorTitle, isPresented: $showsSaveError) {
            Button(Copy.common.ok, role: .cancel) {}
        } message: {
            Text(Copy.gym.saveErrorMessage)
        }
        .task {
            GymPresenceService.shared.start()
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            IconBadge(systemName: "mappin.and.ellipse", tint: Theme.Colors.accent, size: .large)

            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.gym.emptyTitle)
                    .zanoText(.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.gym.emptyMessage)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: Copy.gym.addButtonLabel, systemImage: "plus", isEnabled: userID != nil) {
                editor = .add
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: Check-in row

    private var checkInRow: some View {
        NavigationLink {
            GymCheckInView()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "figure.strengthtraining.traditional", tint: Theme.Colors.accent, size: .medium)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Copy.gym.checkInRowTitle)
                        .zanoText(.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.gym.checkInRowSubtitle)
                        .zanoText(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zanoCard()
    }

    // MARK: Gym cards

    private var gymList: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(sortedGyms) { gym in
                gymCard(gym)
            }
        }
    }

    private func gymCard(_ gym: Gym) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Button {
                    editor = .edit(gym)
                } label: {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        IconBadge(systemName: "dumbbell", tint: Theme.Colors.textSecondary, size: .small)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(gym.name ?? Copy.gym.unnamedLabel)
                                .zanoText(.headline)
                                .foregroundStyle(Theme.Colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detailLine(for: gym))
                                .zanoText(.caption)
                                .foregroundStyle(Theme.Colors.muted)
                            statusPill(confirmed: gym.confirmed)
                                .padding(.top, Theme.Spacing.xxs)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Copy.gym.editLabel)

                moreMenu(for: gym)
                    .padding(.trailing, -Theme.Spacing.sm)
                    .padding(.top, -Theme.Spacing.xs)
            }

            if !gym.confirmed {
                // An unconfirmed (auto-detected) gym doesn't count for Tier A until confirmed.
                PrimaryButton(title: Copy.gym.confirmButtonLabel, systemImage: "checkmark", style: .secondary) {
                    confirm(gym)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(tint: gym.confirmed ? nil : Theme.Colors.warning)
        .contextMenu {
            Button {
                editor = .edit(gym)
            } label: {
                Label(Copy.gym.editLabel, systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDeletion = gym
            } label: {
                Label(Copy.common.delete, systemImage: "trash")
            }
        }
    }

    private func detailLine(for gym: Gym) -> String {
        let radius = Copy.gym.radiusLabel(meters: gym.radiusMeters)
        return gym.autoDetected ? "\(radius) · \(Copy.gym.autoDetectedLabel)" : radius
    }

    /// Glyph + word, never hue alone. Confirmed = accent; unconfirmed = warning.
    private func statusPill(confirmed: Bool) -> some View {
        let tint = confirmed ? Theme.Colors.accent : Theme.Colors.warning
        return HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(Theme.Typography.icon(.xsmall))
                .accessibilityHidden(true)
            Text(confirmed ? Copy.gym.confirmedLabel : Copy.gym.unconfirmedLabel)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Theme.Colors.wash(tint), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func moreMenu(for gym: Gym) -> some View {
        Menu {
            Button {
                editor = .edit(gym)
            } label: {
                Label(Copy.gym.editLabel, systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDeletion = gym
            } label: {
                Label(Copy.common.delete, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.muted)
                .minTapTarget()
        }
        .accessibilityLabel(Copy.common.moreOptions(for: gym.name ?? Copy.gym.unnamedLabel))
    }

    // MARK: Persistence

    private func confirm(_ gym: Gym) {
        gym.confirmed = true
        guard persist() else { return }
        successTick += 1
        offerAlwaysPrimerIfNeeded()
    }

    private func save(_ draft: GymDraft, editing gymID: UUID?) {
        let name: String? = draft.name.isEmpty ? nil : draft.name
        if let gymID, let gym = gyms.first(where: { $0.id == gymID }) {
            gym.name = name
            gym.lat = draft.latitude
            gym.lng = draft.longitude
            gym.radiusMeters = draft.radiusMeters
        } else {
            guard let userID else { return }
            // A gym the person placed themselves is confirmed by construction.
            modelContext.insert(Gym(
                userID: userID,
                lat: draft.latitude,
                lng: draft.longitude,
                radiusMeters: draft.radiusMeters,
                name: name,
                autoDetected: false,
                confirmed: true
            ))
        }
        guard persist() else { return }
        successTick += 1
        showsAlwaysPrimerAfterEditor = shouldOfferAlwaysPrimer
    }

    private func delete(_ gym: Gym) {
        pendingDeletion = nil
        modelContext.delete(gym)
        persist()
    }

    /// Saves, then re-syncs the geofences with what's saved. `false` (and an alert) on failure.
    @discardableResult
    private func persist() -> Bool {
        do {
            try modelContext.save()
        } catch {
            showsSaveError = true
            return false
        }
        Task { await GymPresenceService.shared.refreshMonitoredGyms() }
        return true
    }

    /// spec §24: Always is asked for at gym setup, with the explanation — once, right after a gym
    /// is saved or confirmed, and never again once the one system prompt has been used.
    private var shouldOfferAlwaysPrimer: Bool {
        authorization.level != .always && authorization.level != .denied && !authorization.hasRequestedAlways
    }

    private func offerAlwaysPrimerIfNeeded() {
        if shouldOfferAlwaysPrimer {
            isAlwaysPrimerPresented = true
        }
    }
}

/// What the editor sheet is open for.
private enum GymEditorTarget: Identifiable {
    case add
    case edit(Gym)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let gym): gym.id.uuidString
        }
    }

    var gymID: UUID? {
        if case .edit(let gym) = self { return gym.id }
        return nil
    }

    var draft: GymDraft? {
        guard case .edit(let gym) = self else { return nil }
        return GymDraft(
            name: gym.name ?? "",
            latitude: gym.lat,
            longitude: gym.lng,
            radiusMeters: gym.radiusMeters
        )
    }
}
