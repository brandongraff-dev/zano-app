// SunriseAlarmSetupView.swift
// App / Features / SunriseAlarm
//
// Owned by: this session's task (App/ZANO/Features/SunriseAlarm/*). Do not edit from another
// session — CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §5.10 "★ Bedtime Gate & Sunrise Alarm (tap-to-dismiss)" — the Sunrise Alarm half's
// settings surface. Builds exactly what that section's "Variants (settings)" list describes:
//
//   - Tag dismiss (default) — Sunrise Tag.
//   - Steps dismiss — walk N steps (Core Motion) if a tag isn't available yet.
//   - Focus dismiss — 3-minute journal/stretch timer.
//   - Squad alarm — a friend gets notified if you don't dismiss within 10 min (opt-in).
//
// plus the wake time itself and the "never promise this will always wake you... keep a standard
// alarm" safety copy §5.10's Technical path paragraph calls for in the setup flow, and which tier
// (AlarmKit vs. the iOS 17–18 notification fallback) this device supports, per §5.10: "Be explicit
// in onboarding about which tier the user's phone supports."
//
// `BedtimeGateSetupView.swift` (same directory, same session) owns the bedtime half of the same
// on-disk `SunriseAlarmManager.Settings` row — see that file's header for how the two screens
// share one settings struct without clobbering each other's fields.
//
// ============================================================================================
// ASSUMED API — Core/Sources/Core/Verification/SunriseAlarmManager.swift
//
// Per this task's brief: not present on disk when this session started (confirmed — no
// `SunriseAlarmManager` or `AlarmKit` reference anywhere in the repo as of this task). A sibling
// session may land the real file around the same time as this one. This shape is this session's
// own design, built to fit exactly how spec §5.10 describes the feature and to reuse the real,
// already-on-disk pieces it depends on (`SunriseKeyIntent`, `NFCTagMapper`, `NFCReader`,
// `LockEngineManager`, `StreakEngine`) rather than re-invent them:
//
//   @MainActor @Observable
//   public final class SunriseAlarmManager {
//       public static let shared = SunriseAlarmManager()
//
//       public enum DismissVariant: String, Codable, Sendable, CaseIterable {
//           case tag, steps, focus, squad
//       }
//       public enum EscapeReason: String, Sendable { case imNotHome, other }
//
//       public struct Settings: Sendable, Equatable {
//           public var bedtime: Date                 // BedtimeGateSetupView owns this field
//           public var wakeTime: Date                // this screen owns the rest
//           public var dismissVariant: DismissVariant
//           public var windDownReminderEnabled: Bool  // BedtimeGateSetupView
//           public var stepsTarget: Int                // .steps variant's N
//           public var squadIDToNotify: UUID?           // .squad variant's target squad
//
//           // Memberwise, all-defaulted (spec-reasonable defaults: 22:30 bedtime, 6:30 wake,
//           // .tag variant, wind-down on, 40 steps, no squad) so both setup screens can seed
//           // `@State` with a plain `Settings()` before their `.task` load replaces it.
//           public init(
//               bedtime: Date = /* today at 22:30 */,
//               wakeTime: Date = /* today at 06:30 */,
//               dismissVariant: DismissVariant = .tag,
//               windDownReminderEnabled: Bool = true,
//               stepsTarget: Int = 40,
//               squadIDToNotify: UUID? = nil
//           )
//       }
//
//       // Never throws / never nil — mirrors TimeBankEngine.remainingMinutes' and
//       // StreakEngine.currentStreak's "read methods always return a safe default" convention.
//       // Returns spec-reasonable defaults (bedtime 22:30, wake 6:30, .tag, wind-down on, 40
//       // steps, no squad) the first time it's called for a user with no saved row yet.
//       public func currentSettings() async -> Settings
//       public func saveSettings(_ settings: Settings) async throws
//
//       // Ringing state — read live by AlarmRingingView.swift via @Observable tracking.
//       public private(set) var isRinging: Bool
//       public private(set) var ringingSince: Date?
//       public private(set) var snoozesRemainingToday: Int   // spec: "1 snooze max (5 min)"
//       public private(set) var stepsWalked: Int               // live Core Motion count, .steps variant
//
//       // Dismiss paths. Each records the morning goal + arms the day's lock (spec §5.10 step 4)
//       // and silences the ringing state/sound/Live Activity. `dismissViaTag` is expected to
//       // internally do the same GoalEvent-recording `SunriseKeyIntent.perform()` already does
//       // (that intent exists for real — Core/Sources/Core/Intents/SunriseKeyIntent.swift — and
//       // this manager either wraps it or the same effect) PLUS stop the audio/haptics/Live
//       // Activity that intent knows nothing about, which is why AlarmRingingView.swift calls
//       // BOTH `NFCTagMapper.shared.scanAndHandle` (the real dispatch → SunriseKeyIntent) AND
//       // this method — see that file's header for the full two-step rationale.
//       public func dismissViaTag(tagID: UUID) async throws
//       public func dismissViaSteps() async throws
//       public func dismissViaFocusCompletion() async throws
//       public func dismissViaSquadConfirmation() async throws
//       @discardableResult public func snooze() async throws -> Date   // throws if 0 remaining
//       public func triggerEscapeHatch(reason: EscapeReason) async throws
//   }
//
// If the real file lands with a different shape, reconcile call sites here and in
// `BedtimeGateSetupView.swift`/`AlarmRingingView.swift` against it — do not silently keep calling
// a stale assumed signature (mirrors `NFCTagMapper.swift`'s own "reconciled against the real
// intents" precedent in this codebase).
// ============================================================================================
//
// ASSUMED API — `Copy.sunriseAlarm.*` / `Copy.common.*` (Core/Sources/Core/Copy, not this
// session's file to create — see `LockSetupView.swift`'s header for the exact same precedent this
// follows). Keys this file references: screenTitle, wakeTimeSectionHeader, wakeTimeLabel,
// dismissMethodSectionHeader, dismissMethodFooter, variantTitle(DismissVariant),
// variantDescription(DismissVariant), tagSectionHeader, tagMappedStatus(count: Int),
// tagScanButtonLabel, tagScanAlertMessage, tagScanNoMatchMessage, tagScanErrorTitle,
// tagPlacementHeader, tagBackgroundReadHeader, tagBackgroundReadFooter, tagTroubleshootingHeader,
// defaultTagLabel, forgetTagButtonLabel, forgetTagConfirmTitle, stepsSectionHeader,
// stepsTargetLabel(target: Int), stepsHelperText, focusSectionHeader, focusHelperText,
// squadSectionHeader, squadPickerLabel, squadNoneOption, squadEmptyStateText, squadHelperText,
// techSectionHeader, techTierAlarmKitLabel, techTierAlarmKitDetail, techTierFallbackLabel,
// techTierFallbackDetail, standardAlarmReminderText, saveButtonLabel, saveErrorTitle. Plus
// `Copy.common.cancel` / `Copy.common.ok`, already assumed by `LockSetupView.swift` — reused here
// rather than re-assumed under a different name.

import SwiftUI
import Core

/// Sunrise Alarm setup: wake time, dismiss-variant picker (Tag/Steps/Focus/Squad), and the
/// per-variant configuration each one needs. Reads/writes the shared `SunriseAlarmManager.
/// Settings` row (see header) — never a local-only draft that could silently diverge from what
/// `BedtimeGateSetupView` or the ringing flow actually reads.
///
/// Expected to be pushed from a "Sunrise Alarm" row somewhere in Settings (this task explicitly
/// does not add that row — `SettingsView.swift` is owned by another, still-settling session; see
/// this task's `knownIssues`) or from `BedtimeGateSetupView`'s own link to this screen.
@MainActor
struct SunriseAlarmSetupView: View {
    @State private var settings = SunriseAlarmManager.Settings()
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var errorAlert: SunriseAlarmSetupErrorAlert?

    @State private var mappedSunriseTags: [NFCTagMapping] = []
    @State private var isScanningTag = false
    @State private var tagScanError: String?
    @State private var pendingTagRemoval: NFCTagMapping?

    @State private var mySquads: [SquadSnapshot] = []
    @State private var squadsLoadFailed = false

    /// Which alarm technology this OS/device supports, per spec §5.10's technical path: "iOS 26+:
    /// AlarmKit... iOS 17–18 fallback: scheduled local notifications... Be explicit in onboarding
    /// about which tier the user's phone supports." Computed locally with `#available` rather than
    /// asked of `SunriseAlarmManager` — this is a pure OS-version fact, not state the manager needs
    /// to own, so this screen doesn't widen its assumed API surface for it.
    private var supportsAlarmKit: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }

    var body: some View {
        Form {
            wakeTimeSection
            dismissMethodSection
            variantConfigurationSection
            technologySection
        }
        .navigationTitle(Copy.sunriseAlarm.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.sunriseAlarm.saveButtonLabel) { save() }
                    .disabled(isSaving)
            }
        }
        .task {
            guard !isLoaded else { return }
            settings = await SunriseAlarmManager.shared.currentSettings()
            isLoaded = true
            await loadMappedTags()
            await loadSquads()
        }
        .alert(
            errorAlert?.title ?? "",
            isPresented: Binding(
                get: { errorAlert != nil },
                set: { isPresented in if !isPresented { errorAlert = nil } }
            ),
            presenting: errorAlert
        ) { _ in
            Button(Copy.common.ok, role: .cancel) { errorAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            Copy.sunriseAlarm.forgetTagConfirmTitle,
            isPresented: Binding(
                get: { pendingTagRemoval != nil },
                set: { isPresented in if !isPresented { pendingTagRemoval = nil } }
            ),
            presenting: pendingTagRemoval
        ) { tag in
            Button(Copy.sunriseAlarm.forgetTagButtonLabel, role: .destructive) {
                forgetTag(tag)
            }
            Button(Copy.common.cancel, role: .cancel) { pendingTagRemoval = nil }
        }
    }

    // MARK: - Wake time

    private var wakeTimeSection: some View {
        Section(Copy.sunriseAlarm.wakeTimeSectionHeader) {
            DatePicker(
                Copy.sunriseAlarm.wakeTimeLabel,
                selection: $settings.wakeTime,
                displayedComponents: .hourAndMinute
            )
        }
    }

    // MARK: - Dismiss variant picker

    private var dismissMethodSection: some View {
        Section {
            ForEach(SunriseAlarmManager.DismissVariant.allCases, id: \.self) { variant in
                variantRow(variant)
            }
        } header: {
            Text(Copy.sunriseAlarm.dismissMethodSectionHeader)
        } footer: {
            Text(Copy.sunriseAlarm.dismissMethodFooter)
        }
    }

    private func variantRow(_ variant: SunriseAlarmManager.DismissVariant) -> some View {
        Button {
            withAnimation(Theme.Motion.springStandard) {
                settings.dismissVariant = variant
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: variant.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(settings.dismissVariant == variant ? Theme.Colors.accent : Theme.Colors.muted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.sunriseAlarm.variantTitle(variant))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.sunriseAlarm.variantDescription(variant))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }

                Spacer()

                if settings.dismissVariant == variant {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Per-variant configuration

    @ViewBuilder
    private var variantConfigurationSection: some View {
        switch settings.dismissVariant {
        case .tag: tagSection
        case .steps: stepsSection
        case .focus: focusSection
        case .squad: squadSection
        }
    }

    /// `@ViewBuilder`: this returns *two* sibling `Section`s (the tag list/scan section, plus the
    /// background-read/troubleshooting disclosures) — an ordinary computed property body only
    /// implicitly returns a single trailing expression, so without this annotation the second
    /// `Section` below would be a compile error, not silently dropped.
    @ViewBuilder
    private var tagSection: some View {
        Section {
            if mappedSunriseTags.isEmpty {
                Text(Copy.sunriseAlarm.tagMappedStatus(count: 0))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                ForEach(mappedSunriseTags) { tag in
                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundStyle(Theme.Colors.Ring.sunriseAlarm)
                        Text(tag.label)
                            .foregroundStyle(Theme.Colors.text)
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingTagRemoval = tag
                        } label: {
                            Label(Copy.sunriseAlarm.forgetTagButtonLabel, systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                scanAndMapSunriseTag()
            } label: {
                if isScanningTag {
                    ProgressView()
                } else {
                    Label(Copy.sunriseAlarm.tagScanButtonLabel, systemImage: "plus")
                }
            }
            .disabled(isScanningTag || !NFCReader.isAvailable)

            if let tagScanError {
                Text(tagScanError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }

            if !NFCReader.isAvailable {
                Text(Copy.sunriseAlarm.tagScanErrorTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
        } header: {
            Text(Copy.sunriseAlarm.tagSectionHeader)
        } footer: {
            Text(NFCTagSetupInstructions.placementGuidance(for: .sunrise))
        }

        Section {
            DisclosureGroup(Copy.sunriseAlarm.tagBackgroundReadHeader) {
                Text(NFCTagSetupInstructions.backgroundReadExplainer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                NFCStepList(steps: NFCTagSetupInstructions.shortcutsAutomationSteps)
            }
            DisclosureGroup(Copy.sunriseAlarm.tagTroubleshootingHeader) {
                ForEach(Array(NFCTagSetupInstructions.troubleshooting.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .padding(.vertical, Theme.Spacing.xxs)
                }
            }
        }
    }

    private var stepsSection: some View {
        Section {
            Stepper(
                Copy.sunriseAlarm.stepsTargetLabel(target: settings.stepsTarget),
                value: $settings.stepsTarget,
                in: 20...300,
                step: 10
            )
        } header: {
            Text(Copy.sunriseAlarm.stepsSectionHeader)
        } footer: {
            Text(Copy.sunriseAlarm.stepsHelperText)
        }
    }

    private var focusSection: some View {
        Section {
            Text(Copy.sunriseAlarm.focusHelperText)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
        } header: {
            Text(Copy.sunriseAlarm.focusSectionHeader)
        }
    }

    private var squadSection: some View {
        Section {
            if squadsLoadFailed || mySquads.isEmpty {
                Text(Copy.sunriseAlarm.squadEmptyStateText)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                Picker(Copy.sunriseAlarm.squadPickerLabel, selection: $settings.squadIDToNotify) {
                    Text(Copy.sunriseAlarm.squadNoneOption).tag(UUID?.none)
                    ForEach(mySquads) { squad in
                        Text(squad.name).tag(Optional(squad.id))
                    }
                }
            }
        } header: {
            Text(Copy.sunriseAlarm.squadSectionHeader)
        } footer: {
            Text(Copy.sunriseAlarm.squadHelperText)
        }
    }

    // MARK: - Technology / safety

    private var technologySection: some View {
        Section {
            HStack {
                Image(systemName: supportsAlarmKit ? "alarm.waves.left.and.right.fill" : "bell.badge.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text(supportsAlarmKit ? Copy.sunriseAlarm.techTierAlarmKitLabel : Copy.sunriseAlarm.techTierFallbackLabel)
                    .foregroundStyle(Theme.Colors.text)
            }
            Text(supportsAlarmKit ? Copy.sunriseAlarm.techTierAlarmKitDetail : Copy.sunriseAlarm.techTierFallbackDetail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        } header: {
            Text(Copy.sunriseAlarm.techSectionHeader)
        } footer: {
            Text(Copy.sunriseAlarm.standardAlarmReminderText)
        }
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        Task {
            do {
                try await SunriseAlarmManager.shared.saveSettings(settings)
                isSaving = false
            } catch {
                isSaving = false
                errorAlert = SunriseAlarmSetupErrorAlert(
                    title: Copy.sunriseAlarm.saveErrorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func loadMappedTags() async {
        let all = await NFCTagMapper.shared.allMappings()
        mappedSunriseTags = all.filter { mapping in
            if case .sunriseKey = mapping.action { return true }
            return false
        }
    }

    private func loadSquads() async {
        do {
            mySquads = try await SquadManager.shared.mySquads()
            squadsLoadFailed = false
        } catch {
            // Non-fatal: the Squad variant's picker just shows the empty state instead — this
            // screen never blocks the rest of setup over the Social module being unreachable.
            squadsLoadFailed = true
        }
    }

    /// Scans a physical tag and maps it straight to `.sunriseKey` (spec §5.10: the Sunrise Tag has
    /// exactly one job). Skips the generic "choose what it does" step of `NFCTagSetupInstructions.
    /// mapTagInApp` on purpose — a tag scanned from *this* screen's "add a Sunrise Tag" button has
    /// only one possible intended action, so asking the user to pick it again would be friction
    /// the multi-purpose tag-mapping screen (owned elsewhere) needs but this single-purpose flow
    /// does not.
    private func scanAndMapSunriseTag() {
        guard !isScanningTag else { return }
        isScanningTag = true
        tagScanError = nil
        Task {
            do {
                let result = try await NFCReader.shared.scanOnce(
                    alertMessage: Copy.sunriseAlarm.tagScanAlertMessage,
                    noMatchMessage: Copy.sunriseAlarm.tagScanNoMatchMessage
                )
                let mapping = NFCTagMapping(
                    id: result.tagUUID,
                    kind: .sunrise,
                    label: Copy.sunriseAlarm.defaultTagLabel,
                    action: .sunriseKey
                )
                await NFCTagMapper.shared.saveMapping(mapping)
                await loadMappedTags()
                isScanningTag = false
            } catch NFCReaderFailure.cancelled {
                isScanningTag = false
            } catch {
                isScanningTag = false
                tagScanError = error.localizedDescription
            }
        }
    }

    private func forgetTag(_ tag: NFCTagMapping) {
        pendingTagRemoval = nil
        Task {
            await NFCTagMapper.shared.removeMapping(for: tag.id)
            await loadMappedTags()
        }
    }
}

// MARK: - Variant display metadata

private extension SunriseAlarmManager.DismissVariant {
    /// SF Symbol shown in `variantRow` — display-only metadata, not user-facing copy, so this file
    /// owns it directly rather than routing single symbol names through `Copy`.
    var systemImage: String {
        switch self {
        case .tag: "wave.3.right"
        case .steps: "figure.walk"
        case .focus: "wind"
        case .squad: "person.3.fill"
        }
    }
}

// MARK: - Shared step-list renderer (used here and, for placement/troubleshooting text, implicitly
// by AlarmRingingView.swift via the same `NFCTagSetupInstructions` source)

/// Renders an ordered `[NFCTagSetupInstructions.Step]` as numbered rows. File-scoped (`internal`
/// would leak it outside this directory unnecessarily) since only this file's DisclosureGroups use
/// it today.
private struct NFCStepList: View {
    let steps: [NFCTagSetupInstructions.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("\(step.id)")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.background)
                        .frame(width: 18, height: 18)
                        .background(Theme.Colors.accent, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.text)
                        Text(step.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }
}

/// File-scoped alert payload — mirrors `LockSetupView.swift`'s `LockSetupErrorAlert`.
private struct SunriseAlarmSetupErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    NavigationStack {
        SunriseAlarmSetupView()
    }
    .preferredColorScheme(.dark)
}
