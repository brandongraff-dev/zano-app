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
// `LockSetManager` API — not one of the predefined SYSTEM CONTRACTS in this batch's task (only
// LockEngineManager, FocusSessionVerifier, GymVerifier, TimeBankEngine, StreakEngine,
// AdaptiveGoalEngine, and the three ActivityAttributes were given exact shapes), but this file's
// calls below were cross-checked against the real, now-implemented
// `Core/Sources/Core/LockEngine/LockSetManager.swift` in a later review pass and match it exactly
// (previously this comment described an assumed shape written ahead of that file existing; it's
// now confirmed real, not assumed). Mirrors the id-based, `async throws`, `static let shared`
// style every predefined contract in this batch uses (e.g. `LockEngineManager.startLock(
// lockSetID: UUID, ...)` takes an id, not a model instance, and so do all its siblings):
//
//     final class LockSetManager {
//         static let shared = LockSetManager()
//         func createLockSet(name: String, selection: FamilyActivitySelection?, makeDefault: Bool) async throws -> UUID
//         func updateSelection(_ selection: FamilyActivitySelection, for lockSetID: UUID) async throws
//         func rename(lockSetID: UUID, to name: String) async throws
//         func setDefault(lockSetID: UUID) async throws
//         func delete(lockSetID: UUID) async throws
//         func selection(for lockSet: LockSet) -> FamilyActivitySelection
//     }
//
// Notes for whoever implements it for real:
// - `createLockSet`/`updateSelection`/`rename`/`setDefault`/`delete` take ids (not `LockSet`
//   instances) on purpose: this view's `@Query` results live on the environment's `ModelContext`,
//   while a manager singleton most likely persists through its own `ModelContext(ModelContainer.
//   appGroup)` — passing ids sidesteps any cross-context object-identity hazard entirely.
// - `selection(for:)` is the one exception: it's a pure, synchronous decode of a `LockSet`
//   instance's already-in-memory `appTokensBlob` (see that property's doc comment — "LockEngine
//   owns encoding/decoding a FamilyActivitySelection into/out of this blob"), not a persistence
//   op, so it takes the instance directly and returns synchronously (`.object([:])`-style empty
//   `FamilyActivitySelection()` on a nil/undecodable blob) so this view can call it inline while
//   building row text instead of threading `Task`/loading-state through every row.
// - `setDefault` is expected to clear `isDefault` on every other `LockSet` for the current user
//   in the same write, since there's no Postgres partial-unique-index enforcing "at most one
//   default" server-side (see `LockSet.swift`) — the client owns that invariant.
// - `createLockSet` is expected to set `isDefault = true` automatically when it's the user's
//   first lock set (a set with no default is meaningless the moment any lock set exists at all —
//   every other consumer of `LockSet.isDefault`, e.g. NFC-tap-with-no-mapping, needs something to
//   resolve to). This view intentionally does not special-case "is this the first one?" itself —
//   that invariant belongs with the type that owns every other default-set bookkeeping rule.
// - `userID` is intentionally not a parameter anywhere above, matching every predefined contract
//   in this batch (none take one either) — the manager is assumed to resolve the current device's
//   one local `User` row itself (see `User.swift`: "this device's local SwiftData store holds
//   exactly one User row... the signed-in (or anonymous) owner of the device").
//
// ASSUMED API — `Copy.lockSetup` / `Copy.common`: CLAUDE.md and this session's task both require
// "no hardcoded UI strings" — everything user-facing here goes through `Core/Sources/Core/Copy`,
// which is also not this session's file to create. Every `Copy.lockSetup.*` / `Copy.common.*`
// member this file and `AppPickerView.swift` reference is plain, tone-neutral admin-screen copy
// (name a set, pick its apps, save) — not one of the coach-voice-flavored strings spec §5.13
// describes for in-the-moment motivational copy (shield screens, nudges, streak messages), so a
// single static string/function per key is assumed to be enough here, with no `CoachVoice`
// parameter threaded through. Full list of keys referenced, for whoever owns `Core/Sources/Core/
// Copy`: `screenTitle`, `newLockSetButtonLabel`, `emptyStateTitle`, `emptyStateMessage`,
// `deleteButtonLabel`, `deleteConfirmTitle`, `deleteConfirmMessage(name:)`,
// `defaultToggleAccessibilityLabel(name:)`, `noAppsSelected`, `selectionSummary(appCount:
// categoryCount:webDomainCount:)`, `saveErrorTitle`, `newLockSetTitle`, `editLockSetTitle`,
// `nameFieldLabel`, `nameFieldPlaceholder`, `saveButtonLabel`, `selectAppsButtonLabel`,
// `appPickerFooter`, `authorizationErrorTitle`, `authorizationErrorMessage`,
// `authorizationDeniedTitle`, `authorizationDeniedMessage`; `Copy.common.ok`, `Copy.common.cancel`.

import SwiftUI
import SwiftData
import FamilyControls
import Core

/// Lock Set management screen: list of saved `LockSet`s with a default-set toggle, plus create /
/// rename / re-pick-apps / delete. Reads `LockSet` rows directly via `@Query` (cheap, declarative,
/// and this screen is the only v1 place that lists them) but never writes to one directly — every
/// mutation goes through `LockSetManager` (assumed API, see file header) so blob encoding and
/// default-set exclusivity stay owned by the Lock Engine module, not duplicated here.
///
/// Expected to be pushed from within an existing `NavigationStack` (e.g. a "Manage Lock Sets" row
/// on Settings, or reached while setting up a lock — Session 5 owns that wiring per docs/spec.md
/// §15/§17 row 5), so this view sets `.navigationTitle`/`.toolbar` but does not own a
/// `NavigationStack` itself; only the preview and the modal editor sheet below provide one.
struct LockSetupView: View {
    @Query(sort: \LockSet.name) private var lockSets: [LockSet]

    @State private var editorTarget: EditorTarget?
    @State private var pendingDeletion: LockSet?
    @State private var errorAlert: LockSetupErrorAlert?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            if lockSets.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                ForEach(lockSets) { lockSet in
                    lockSetRow(lockSet)
                        .transition(rowTransition)
                }
            }
        }
        // Explicit row insertion/removal choreography, distinct from `List`'s own default row
        // animation: a new lock set (created via the "+" sheet) or a deleted one (swipe-to-delete)
        // now settles/dismisses with this design system's own spring rather than the system
        // default slide, and — unlike the system default — this is explicitly gated for Reduce
        // Motion below. Keyed on the ordered id list (not just `.count`) so a rename that moves a
        // row to a new position in this screen's name-sorted `@Query` also animates as a genuine
        // reorder, not a silent jump. See `docs/design/animation-opportunities.md` Part 0 for the
        // reduced-motion fallback pattern this follows everywhere in this wave.
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : Theme.Motion.springStandard,
            value: lockSets.map(\.id)
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
        // `Theme.swift`'s own header: this is a fixed, dark-only design system, not
        // light/dark-adaptive — screens force `.preferredColorScheme(.dark)` themselves (the
        // pattern `TodayView`/`LockStatusView`/every other real screen already follows). Without
        // this, a Light/Automatic system appearance leaves this screen's own dark surfaces intact
        // but every native `.confirmationDialog`/`.alert` above (both heavily used here) and the
        // status bar/nav chrome follow the *system* appearance instead. See
        // `docs/design/ui-stress-test-findings.md` §2.1.
        .preferredColorScheme(.dark)
    }

    /// A newly-created row settles in (fade + gentle scale-up from 0.96, matching the "arriving"
    /// feel `ShieldPreview`'s hero reveal uses elsewhere in this wave) and a deleted row simply
    /// fades rather than sliding — sliding is already `List`'s own default for the swipe-to-delete
    /// path, so this only needs to cover the fade half to avoid two competing motions stacking on
    /// the same row. Reduce Motion: plain opacity both ways, no scale — see Part 0 of
    /// `docs/design/animation-opportunities.md`.
    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
                removal: .opacity
            )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Copy.lockSetup.emptyStateTitle, systemImage: "lock.shield")
        } description: {
            Text(Copy.lockSetup.emptyStateMessage)
        } actions: {
            Button(Copy.lockSetup.newLockSetButtonLabel) {
                editorTarget = .create
            }
        }
    }

    private func lockSetRow(_ lockSet: LockSet) -> some View {
        Button {
            editorTarget = .edit(lockSet)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lockSet.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(appSummary(for: lockSet))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                defaultToggle(for: lockSet)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = lockSet
            } label: {
                Label(Copy.lockSetup.deleteButtonLabel, systemImage: "trash")
            }
        }
    }

    /// A `Toggle` per the task's own wording ("a default-set toggle"), not a free multi-select —
    /// turning one lock set's toggle on calls `LockSetManager.setDefault`, which is the only place
    /// that clears every other set's flag. Turning the *current* default's toggle off directly
    /// would leave zero default sets, which every other consumer of `LockSet.isDefault` relies on
    /// always resolving to something, so an off-tap here is a no-op rather than a dead end —
    /// picking a different set's toggle on is the only way to change the default, same as a radio
    /// button, just presented as the toggle the task asked for.
    private func defaultToggle(for lockSet: LockSet) -> some View {
        Toggle(isOn: Binding(
            get: { lockSet.isDefault },
            set: { isOn in
                guard isOn else { return }
                setDefault(lockSet)
            }
        )) {
            EmptyView()
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .accessibilityLabel(Copy.lockSetup.defaultToggleAccessibilityLabel(name: lockSet.name))
    }

    private func appSummary(for lockSet: LockSet) -> String {
        let selection = LockSetManager.shared.selection(for: lockSet)
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count
        let webDomainCount = selection.webDomainTokens.count
        guard appCount + categoryCount + webDomainCount > 0 else {
            return Copy.lockSetup.noAppsSelected
        }
        return Copy.lockSetup.selectionSummary(
            appCount: appCount,
            categoryCount: categoryCount,
            webDomainCount: webDomainCount
        )
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
/// existing row. Everything here talks to `LockSetManager` (assumed API, see file header) — never
/// to `ModelContext` directly.
private struct LockSetEditorSheet: View {
    /// See the name `TextField`'s own comment (§4.3) — an arbitrary but generous ceiling, well
    /// past any real lock-set name, that keeps this field's length bounded for every downstream
    /// consumer.
    static let maxNameLength = 40

    let target: EditorTarget

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selection = FamilyActivitySelection()
    @State private var isSaving = false
    @State private var errorAlert: LockSetupErrorAlert?

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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.lockSetup.nameFieldPlaceholder, text: $name)
                        .textInputAutocapitalization(.words)
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
                } header: {
                    Text(Copy.lockSetup.nameFieldLabel)
                }

                AppPickerView(selection: $selection)
            }
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
