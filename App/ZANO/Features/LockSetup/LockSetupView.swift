// LockSetupView.swift
// App / Features / LockSetup
//
// Owned by: Session "LockSetup" (this file's task). Do not edit from another session — see
// CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §4 (v1 — Launch): "App picker (FamilyActivityPicker) with saved 'lock sets' (e.g.,
// Social, Games, All)." §11 Architecture puts `LockEngine` (shields, schedules, unlock rules, Time
// Bank) in Core, and lists `FamilyControls, ManagedSettings, DeviceActivity` as the frameworks
// that ever see real app identity. This screen is the v1 admin surface for that: create/rename a
// named `LockSet`, pick its apps/categories/web domains (via `AppPickerView`, this session's other
// owned file), and choose which saved set is the default (`LockSet.isDefault` — "The lock set
// applied when the user hasn't chosen one explicitly," per that model's own doc comment, e.g. an
// NFC tap with no tag mapping, or a schedule with no override).
//
// CLAUDE.md's "any lock/shield feature must always keep an emergency-unlock path" rule is
// deliberately N/A to this specific screen: this view only manages saved app *selections* — it
// never starts, ends, or holds an active lock/shield itself (that's `LockEngineManager`, a
// separate Core module owned by a different session), so there is no lock state here that could
// trap anyone.
//
// `LockSetManager` API (cross-checked against the real `Core/Sources/Core/LockEngine/
// LockSetManager.swift`): id-based, `async throws`, `static let shared`.
//
//     createLockSet(name:selection:makeDefault:) / updateSelection(_:for:) / rename(lockSetID:to:)
//     setDefault(lockSetID:) / delete(lockSetID:) / selection(for: LockSet) -> FamilyActivitySelection
//
// - Mutations take ids, not `LockSet` instances, on purpose: this view's `@Query` results live on the
//   environment's `ModelContext`, while the manager persists through its own context — ids sidestep
//   any cross-context object-identity hazard.
// - `selection(for:)` is the one synchronous, instance-taking call: a pure decode of an
//   already-in-memory `appTokensBlob`, so rows can call it inline while building their text.
// - `setDefault` clears `isDefault` on every other set in the same write (no server-side unique
//   index enforces "at most one default"; the client owns that invariant), and `createLockSet`
//   makes the user's first set the default. This view deliberately special-cases neither.
//
// All user-facing strings come from `Copy.lockSetup` / `Copy.common` (plain, tone-neutral admin copy —
// no coach voice threaded through).

import SwiftUI
import SwiftData
import FamilyControls
import Core

// MARK: - Visual pass (design wave 2026-09-23)
//
// `docs/design/composition-audit.md` graded this screen F ("the most tutorial-grade screen"): a stock
// `List` on the system's pure-black grouped background, rows in system fonts and `.primary/
// .secondary` (the only Feature file that bypassed `Theme` outright), no identity for the product's
// core object, a `Toggle` that snapped back when switched off (a radio wearing a switch's clothes),
// and the app picker rendered as a settings line. What it is now, composition and visual only (every
// `LockSetManager` call, the free-tier error alert path and the delete confirmation are unchanged):
//
//   * Lock sets are cards (the shared `zanoCard`) with the picked apps' real icons as an overlapped
//     stack and a `+N` overflow tile, instead of a name and a count. The system-rendered `Label(token)`
//     keeps the token-privacy rule intact (see `AppPickerView.swift`).
//   * The default set is *visibly* the default without a word of copy: it sorts first, wears an
//     accent wash and an accent-dim edge, and its control is a filled accent star. Every other set
//     carries an outline star. The control is an explicit radio-style button (an off-tap on the current
//     default is a no-op, `LockSetManager.setDefault` is the only writer) with a 44pt target. Its
//     symbol swap and the row reorder both honor Reduce Motion (the swap used to be ungated).
//   * The empty state is the same card language (a dashed outline with one CTA), not a system
//     `ContentUnavailableView`, and the only time the screen carries a backdrop glow: an invitation,
//     not decoration on an admin list.
//   * The editor sheet leaves `Form` for a themed scroll view; the Always-Allowed warning that the
//     audit noted "exists and is never used here" appears directly under the picker when the current
//     selection could be affected by it (it uses `AlwaysAllowedCheck`'s own acknowledgement flag, so a
//     user who dismissed it once is not nagged). The name field is an input well that lights an accent
//     ring while focused.
//   * `.tint(Theme.Colors.accent)` at this screen's root so the toolbar "+"/Save/Cancel are not system
//     blue (`docs/design/typography-color-findings.md` C2). The app-wide tint belongs in `ZANOApp`/
//     `ContentView`, which this wave does not own; this is the local fix until that lands.
//
// Copy gap (recorded, not hardcoded): a visible "Default" pill would read better than the star alone,
// but it needs a new `Copy.lockSetup` member and `Core/Sources/Core/Copy` is outside this wave's edit
// list. The star, the sort order, the accent edge and the existing
// `Copy.lockSetup.defaultToggleAccessibilityLabel(name:)` carry the state meanwhile.

/// Lock Set management screen: list of saved `LockSet`s with a default-set control, plus create /
/// rename / re-pick-apps / delete. Reads `LockSet` rows directly via `@Query` (cheap, declarative,
/// and this screen is the only v1 place that lists them) but never writes to one directly — every
/// mutation goes through `LockSetManager` so blob encoding and default-set exclusivity stay owned by
/// the Lock Engine module, not duplicated here.
///
/// Expected to be pushed from within an existing `NavigationStack` (Settings links here), so this view
/// sets `.navigationTitle`/`.toolbar` but does not own a `NavigationStack` itself; only the preview and
/// the modal editor sheet below provide one.
struct LockSetupView: View {
    @Query(sort: \LockSet.name) private var lockSets: [LockSet]

    @State private var editorTarget: EditorTarget?
    @State private var pendingDeletion: LockSet?
    @State private var errorAlert: LockSetupErrorAlert?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cards sit 8pt apart (4pt above + 4pt below each), inside the standard 16pt screen gutter.
    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: Theme.Spacing.xxs,
            leading: Theme.Spacing.md,
            bottom: Theme.Spacing.xxs,
            trailing: Theme.Spacing.md
        )
    }

    /// The default set first, then by name. `@Query` sorts by name only; leading with the default is
    /// how the list says "this is the one that applies" without a label.
    private var orderedLockSets: [LockSet] {
        lockSets.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        let ordered = orderedLockSets
        return List {
            if ordered.isEmpty {
                emptyState
                    .listRowInsets(rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .transition(.opacity)
            } else {
                ForEach(ordered) { lockSet in
                    lockSetRow(lockSet)
                        .listRowInsets(rowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(rowTransition)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .zanoBackdrop(glow: ordered.isEmpty ? Theme.Colors.accent : nil, intensity: 0.12)
        // Explicit row insertion/removal/reorder choreography, distinct from `List`'s own default row
        // animation: a new lock set (created via the "+" sheet), a deleted one (swipe-to-delete) or a
        // change of default now settles with this design system's own spring rather than the system
        // default slide, and — unlike the system default — is explicitly gated for Reduce Motion.
        // Keyed on the ordered id list (not just `.count`) so a rename or a new default that moves a
        // row also animates as a genuine reorder, not a silent jump.
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : Theme.Motion.springStandard,
            value: ordered.map(\.id)
        )
        .navigationTitle(Copy.lockSetup.screenTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorTarget = .create
                } label: {
                    Label(Copy.lockSetup.newLockSetButtonLabel, systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            LockSetEditorSheet(target: target)
        }
        .confirmationDialog(
            Copy.lockSetup.deleteConfirmTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletion = nil }
                }
            ),
            presenting: pendingDeletion
        ) { lockSet in
            Button(Copy.lockSetup.deleteButtonLabel, role: .destructive) {
                delete(lockSet)
            }
            Button(Copy.common.cancel, role: .cancel) {
                pendingDeletion = nil
            }
        } message: { lockSet in
            Text(Copy.lockSetup.deleteConfirmMessage(name: lockSet.name))
        }
        .alert(
            errorAlert?.title ?? "",
            isPresented: Binding(
                get: { errorAlert != nil },
                set: { isPresented in
                    if !isPresented { errorAlert = nil }
                }
            ),
            presenting: errorAlert
        ) { _ in
            Button(Copy.common.ok, role: .cancel) { errorAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .tint(Theme.Colors.accent)
        // `Theme.swift`'s own header: this is a fixed, dark-only design system, not
        // light/dark-adaptive — screens force `.preferredColorScheme(.dark)` themselves. Without
        // this, a Light/Automatic system appearance leaves this screen's own dark surfaces intact
        // but every native `.confirmationDialog`/`.alert` above (both heavily used here) and the
        // status bar/nav chrome follow the *system* appearance instead. See
        // `docs/design/ui-stress-test-findings.md` §2.1.
        .preferredColorScheme(.dark)
    }

    /// A newly-created row settles in (fade + gentle scale-up from 0.96) and a deleted one simply
    /// fades rather than sliding — sliding is already `List`'s own default for the swipe-to-delete
    /// path, so this only covers the fade half to avoid two competing motions stacking on the same
    /// row. Reduce Motion: plain opacity both ways, no scale.
    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
                removal: .opacity
            )
    }

    // MARK: - Empty state

    /// A dashed, outlined tile in the same card language as a real row, with one CTA. The glyph is
    /// `text` on a neutral disc (not accent): the accent's one job on this screen is the CTA itself.
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            IconBadge(systemName: "lock.shield.fill", tint: Theme.Colors.text, size: .large)

            VStack(spacing: Theme.Spacing.xxs) {
                Text(Copy.lockSetup.emptyStateTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.lockSetup.emptyStateMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(
                title: Copy.lockSetup.newLockSetButtonLabel,
                systemImage: "plus"
            ) {
                editorTarget = .create
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(
                    Theme.Colors.hairlineStrong,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                )
        }
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: - Row

    private func lockSetRow(_ lockSet: LockSet) -> some View {
        // Decoded once per row render: both the icon stack and the summary read from it.
        let selection = LockSetManager.shared.selection(for: lockSet)
        let isDefault = lockSet.isDefault
        return Button {
            editorTarget = .edit(lockSet)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                LockSetIconStack(items: selection.pickedActivityItems)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(lockSet.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                    Text(selection.lockSetupSummary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(2)
                }

                // Room for the default control overlaid below, so the text column never runs under it.
                Spacer(minLength: Theme.Metrics.minTapTarget)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard(radius: Theme.Radius.medium, tint: isDefault ? Theme.Colors.accent : nil)
            .overlay {
                if isDefault {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .strokeBorder(Theme.Colors.accentDim, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.pressable)
        // A sibling of the row button, not a child of its label: a control nested inside another
        // button's label is what made the old switch fight the row tap.
        .overlay(alignment: .trailing) {
            defaultControl(for: lockSet)
                .padding(.trailing, Theme.Spacing.xs)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = lockSet
            } label: {
                Label(Copy.lockSetup.deleteButtonLabel, systemImage: "trash")
            }
        }
    }

    /// Radio-style "make this the default" control. Same semantics as the old `Toggle`: turning one
    /// lock set on calls `LockSetManager.setDefault`, which is the only place that clears every other
    /// set's flag; tapping the *current* default is a no-op rather than a dead end, because turning
    /// it off would leave zero defaults and every consumer of `LockSet.isDefault` (NFC tap with no
    /// tag mapping, schedules with no override) needs something to resolve to. Picking a different
    /// set is the only way to change the default — exactly a radio button, now presented as one.
    private func defaultControl(for lockSet: LockSet) -> some View {
        let isDefault = lockSet.isDefault
        return Button {
            guard !isDefault else { return }
            setDefault(lockSet)
        } label: {
            Image(systemName: isDefault ? "star.fill" : "star")
                .font(Theme.Typography.icon(.small))
                // `onFill`, not `background`: the one label color for anything drawn on an accent fill.
                .foregroundStyle(isDefault ? Theme.Colors.onFill : Theme.Colors.muted)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
                .background(isDefault ? Theme.Colors.accent : Theme.Colors.track, in: Circle())
                .minTapTarget()
        }
        .buttonStyle(.pressable(scale: 0.92))
        .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isDefault)
        .accessibilityLabel(Copy.lockSetup.defaultToggleAccessibilityLabel(name: lockSet.name))
        .accessibilityAddTraits(isDefault ? .isSelected : [])
        // Only the set that just *became* default buzzes: the set that lost the flag flips too, but
        // the user did not touch it.
        .sensoryFeedback(.selection, trigger: isDefault) { _, newValue in newValue }
    }

    private func setDefault(_ lockSet: LockSet) {
        Task {
            do {
                try await LockSetManager.shared.setDefault(lockSetID: lockSet.id)
            } catch {
                errorAlert = LockSetupErrorAlert(
                    title: Copy.lockSetup.saveErrorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func delete(_ lockSet: LockSet) {
        pendingDeletion = nil
        Task {
            do {
                try await LockSetManager.shared.delete(lockSetID: lockSet.id)
            } catch {
                errorAlert = LockSetupErrorAlert(
                    title: Copy.lockSetup.saveErrorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }
}

/// The lock set's identity: up to three real app icons, overlapped, with a `+N` tile for the rest.
/// Each tile sits on a 2pt `surface` halo (a background shape that extends past the tile's edge) so
/// the overlap reads as layered tiles rather than merged shapes — the same cutout idea `ShieldPreview`'s
/// lock badge uses, drawn *behind* the tile so it never covers the tile's own hairline edge. An empty
/// set (created with no apps yet) shows a lock-shield glyph tile instead of nothing.
private struct LockSetIconStack: View {
    let items: [PickedActivityItem]

    private static let maxTiles = 3
    private static let tileSize: CGFloat = 40

    var body: some View {
        let visible = Array(items.prefix(Self.maxTiles))
        let overflow = items.count - visible.count
        return HStack(spacing: -Theme.Spacing.sm) {
            if visible.isEmpty {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Theme.Colors.surface2)
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                    }
                    .overlay {
                        Image(systemName: "lock.shield")
                            .font(Theme.Typography.icon(.large))
                            .foregroundStyle(Theme.Colors.muted)
                    }
            } else {
                ForEach(visible) { item in
                    ActivityTokenTile(item: item, size: Self.tileSize)
                        .background { halo }
                }
                if overflow > 0 {
                    ActivityOverflowTile(count: overflow, size: Self.tileSize)
                        .background { halo }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var halo: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.small + 2, style: .continuous)
            .fill(Theme.Colors.surface)
            .padding(-2)
    }
}

/// Which lock set the editor sheet is working on: a brand-new one, or an existing one being
/// renamed / having its app selection changed. `Identifiable` so it can drive `.sheet(item:)`
/// directly — file-scoped, not a shared model.
private enum EditorTarget: Identifiable {
    case create
    case edit(LockSet)

    var id: String {
        switch self {
        case .create:
            "create"
        case .edit(let lockSet):
            lockSet.id.uuidString
        }
    }
}

/// File-scoped alert payload — plain `Identifiable` glue for SwiftUI's `.alert(_:isPresented:
/// presenting:actions:message:)`, not a shared model.
private struct LockSetupErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// The create / rename / re-pick-apps form, shared by both the "+" toolbar button and tapping an
/// existing row. Everything here talks to `LockSetManager` — never to `ModelContext` directly.
private struct LockSetEditorSheet: View {
    /// See the name `TextField`'s own comment (§4.3) — an arbitrary but generous ceiling, well
    /// past any real lock-set name, that keeps this field's length bounded for every downstream
    /// consumer.
    static let maxNameLength = 40

    let target: EditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name: String = ""
    @State private var selection = FamilyActivitySelection()
    @State private var isSaving = false
    @State private var errorAlert: LockSetupErrorAlert?
    @FocusState private var isNameFocused: Bool
    /// Set when the user closes the Always-Allowed banner in this sheet; paired with
    /// `AlwaysAllowedCheck.hasAcknowledgedWarning` (the cross-session "don't nag forever" flag).
    @State private var hasDismissedAlwaysAllowedWarning = false

    private var existingLockSet: LockSet? {
        if case .edit(let lockSet) = target {
            lockSet
        } else {
            nil
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelection = !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
        return hasName && hasSelection
    }

    /// The banner is honest, not a detector (see `AlwaysAllowedCheck`'s header): it appears whenever
    /// the picked apps or categories *could* be exempted by Settings > Screen Time > Always Allowed.
    private var shouldShowAlwaysAllowedWarning: Bool {
        AlwaysAllowedCheck.shouldWarn(for: selection)
            && !hasDismissedAlwaysAllowedWarning
            && !AlwaysAllowedCheck.hasAcknowledgedWarning
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    nameSection

                    AppPickerView(selection: $selection)

                    if shouldShowAlwaysAllowedWarning {
                        AlwaysAllowedWarningView(selection: selection) {
                            AlwaysAllowedCheck.recordAcknowledged()
                            hasDismissedAlwaysAllowedWarning = true
                        }
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                    }
                }
                .padding(Theme.Spacing.md)
                .animation(
                    reduceMotion ? nil : Theme.Motion.springStandard,
                    value: shouldShowAlwaysAllowedWarning
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .zanoBackdrop()
            .navigationTitle(
                existingLockSet == nil ? Copy.lockSetup.newLockSetTitle : Copy.lockSetup.editLockSetTitle
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.lockSetup.saveButtonLabel) {
                        save()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear(perform: populateFromExistingLockSet)
            .alert(
                errorAlert?.title ?? "",
                isPresented: Binding(
                    get: { errorAlert != nil },
                    set: { isPresented in
                        if !isPresented { errorAlert = nil }
                    }
                ),
                presenting: errorAlert
            ) { _ in
                Button(Copy.common.ok, role: .cancel) { errorAlert = nil }
            } message: { alert in
                Text(alert.message)
            }
        }
        .tint(Theme.Colors.accent)
        // Same fixed-dark rationale as `LockSetupView`; a presented sheet does not reliably inherit
        // the presenter's `preferredColorScheme`.
        .preferredColorScheme(.dark)
    }

    /// An eyebrow label over an input well (`surface2`, edge-lit). The well lights an accent ring while
    /// focused, so it reads as *the* field being edited.
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.lockSetup.nameFieldLabel)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xs)

            TextField(Copy.lockSetup.nameFieldPlaceholder, text: $name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .textInputAutocapitalization(.words)
                .focused($isNameFocused)
                .padding(Theme.Spacing.md)
                .frame(minHeight: Theme.Metrics.minTapTarget)
                .zanoCard(radius: Theme.Radius.medium, fill: Theme.Colors.surface2)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                        .opacity(isNameFocused ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: isNameFocused)
                // No consumer-side length cap existed anywhere in this flow — a
                // pathologically long name would still degrade gracefully downstream
                // (every real display site already applies its own `lineLimit`), but
                // nothing enforced a sane ceiling at the point of entry. Capped here so
                // every new consumer can trust the string is already bounded, rather than
                // each one independently re-guarding it. See
                // `docs/design/ui-stress-test-findings.md` §4.3.
                .onChange(of: name) { _, newValue in
                    guard newValue.count > Self.maxNameLength else { return }
                    name = String(newValue.prefix(Self.maxNameLength))
                }
        }
    }

    private func populateFromExistingLockSet() {
        guard let existingLockSet else { return }
        name = existingLockSet.name
        selection = LockSetManager.shared.selection(for: existingLockSet)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            do {
                if let existingLockSet {
                    try await LockSetManager.shared.rename(lockSetID: existingLockSet.id, to: trimmedName)
                    try await LockSetManager.shared.updateSelection(selection, for: existingLockSet.id)
                } else {
                    _ = try await LockSetManager.shared.createLockSet(name: trimmedName, selection: selection)
                }
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorAlert = LockSetupErrorAlert(
                    title: Copy.lockSetup.saveErrorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        LockSetupView()
    }
    .modelContainer(for: LockSet.self, inMemory: true)
}
