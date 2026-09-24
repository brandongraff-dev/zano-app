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
// `BedtimeGateSetupView.swift` (same directory) owns the bedtime half of the same on-disk
// `SunriseAlarmManager.Settings` row: each screen loads the whole `Settings` value, mutates only the
// fields it renders UI for, and saves the whole value back, so they never clobber each other. The
// manager is real now (`Core/Sources/Core/Verification/SunriseAlarmManager.swift`); the "ASSUMED
// API" block that used to live here has been reconciled with it and removed. Copy keys are the real
// `Copy.sunriseAlarm.*` / `Copy.common.*` (`Core/Sources/Core/Copy/SunriseAlarmScreenCopy.swift`).
//
// VISUAL DESIGN (design-quality wave, 2026-09-23). The previous version was a stock `Form` on the
// system grouped background: a one-line `DatePicker` for the value the whole feature exists to set,
// four identical radio rows for the dismiss method, a system `Stepper`, a toolbar-only Save that
// gave no feedback, and `ProgressView()` resolving to the app's Progress *screen* inside a button
// (docs/design/composition-audit.md offender 9, better-layout 1.11 / 3.7, better-ui BRK-01 /
// DEP-05 / HIT-05 / HIT-07). Now:
//   * The wake time is the hero: a card with the time at 64pt (Dynamic-Type scaled), tap to reveal
//     an inline wheel picker. `SleepTimeCard` is shared with `BedtimeGateSetupView`.
//   * The dismiss method is a 2x2 tile grid (icon + title, accent border + check when selected)
//     with the selected method's description underneath, instead of a screen-tall radio list. The
//     chosen method's configuration follows, in cards.
//   * The steps target is a big numeral with 44pt minus/plus buttons; VoiceOver gets a native-style
//     adjustable element (swipe up/down) instead of the two visual buttons.
//   * Saving is a pinned `PrimaryButton` that dismisses on success with a `.success` haptic. It is
//     disabled until the settings have loaded, so an early tap can no longer overwrite the saved
//     row with defaults. (Cards + `ScrollView` replace `Form`, so per-row swipe-to-delete on tags is
//     now an explicit "Remove" button with a 44pt target.)
//   * Cards use `surface` with a top-lit 1px edge, on `background`, with `.tint(accent)` so pickers
//     and menus stop rendering system blue (there is no root tint yet — that lives in `ZANOApp`).
//
// The shared building blocks (`SleepSetup*`, `SleepTimeCard`) are `internal` at the bottom of this
// file because `BedtimeGateSetupView.swift` reuses them; they are not a general design-system
// component (they would move to Core/UI if a third screen needed them).

import SwiftUI
import Core

/// Sunrise Alarm setup: wake time, dismiss-variant picker (Tag/Steps/Focus/Squad), and the
/// per-variant configuration each one needs. Reads/writes the shared `SunriseAlarmManager.
/// Settings` row (see header) — never a local-only draft that could silently diverge from what
/// `BedtimeGateSetupView` or the ringing flow actually reads.
///
/// Reached from Settings and from `BedtimeGateSetupView`'s link.
@MainActor
struct SunriseAlarmSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var settings = SunriseAlarmManager.Settings()
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var saveTick = 0
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
    /// to own.
    private var supportsAlarmKit: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SleepTimeCard(
                    systemImage: "sunrise.fill",
                    tint: Theme.Colors.Ring.sunriseAlarm,
                    label: Copy.sunriseAlarm.wakeTimeLabel,
                    time: $settings.wakeTime
                )

                dismissMethodSection

                variantConfigurationSection

                technologySection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { Theme.Colors.background.ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Disabled until the saved settings have loaded: saving before then would write the
            // `Settings()` defaults over the user's real row.
            SleepSetupSaveBar(
                title: Copy.sunriseAlarm.saveButtonLabel,
                isEnabled: isLoaded && !isSaving
            ) {
                save()
            }
        }
        .navigationTitle(Copy.sunriseAlarm.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Colors.interactive)
        .sensoryFeedback(.success, trigger: saveTick)
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
        // Fixed, dark-only design system — see `docs/design/ui-stress-test-findings.md` §2.1.
        // Matters especially here: this screen's `.alert`/`.confirmationDialog` above are both
        // real, frequently-hit paths (forget-tag, save error).
        .preferredColorScheme(.dark)
    }

    // MARK: - Dismiss variant picker

    private var dismissMethodSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.sunriseAlarm.dismissMethodSectionHeader)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                ],
                spacing: Theme.Spacing.sm
            ) {
                ForEach(SunriseAlarmManager.DismissVariant.allCases, id: \.self) { variant in
                    variantTile(variant)
                }
            }

            // Only the selected method's description is shown (four sentences in a 2x2 grid would
            // be four tall tiles); each tile carries its own description as its VoiceOver hint.
            Text(Copy.sunriseAlarm.variantDescription(settings.dismissVariant))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xxs)

            Text(Copy.sunriseAlarm.dismissMethodFooter)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sensoryFeedback(.selection, trigger: settings.dismissVariant)
    }

    private func variantTile(_ variant: SunriseAlarmManager.DismissVariant) -> some View {
        let isSelected = settings.dismissVariant == variant
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
                settings.dismissVariant = variant
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    Image(systemName: variant.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.Colors.interactive : Theme.Colors.muted)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Colors.interactive)
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 0)

                Text(Copy.sunriseAlarm.variantTitle(variant))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: SleepSetupMetrics.tileHeight, alignment: .topLeading)
            .background { tileBackground(isSelected: isSelected) }
        }
        .buttonStyle(SleepSetupPressStyle())
        // The accent border and check are the only visual "this is the current choice" signal, and
        // neither is read by VoiceOver — without the trait, all four tiles announce identically. See
        // `docs/design/ui-stress-test-findings.md` §3.4.
        .accessibilityHint(Copy.sunriseAlarm.variantDescription(variant))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tileBackground(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        // Selected = achromatic (decision 2026-09-24: selection is chrome, green means earned): an
        // `interactiveWash` fill under a 2pt `interactive` edge.
        return shape
            .fill(isSelected ? Theme.Colors.interactiveWash : Theme.Colors.surface)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.interactive : SleepSetupDepth.edge,
                    lineWidth: isSelected ? 2 : 1
                )
            )
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

    /// `@ViewBuilder`: this returns *two* sibling blocks (the tag list/scan card, plus the
    /// background-read/troubleshooting disclosures) — an ordinary computed property body only
    /// implicitly returns a single trailing expression, so without this annotation the second block
    /// below would be a compile error, not silently dropped.
    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.sunriseAlarm.tagSectionHeader)

            SleepSetupCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if mappedSunriseTags.isEmpty {
                        Text(Copy.sunriseAlarm.tagMappedStatus(count: 0))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.muted)
                    } else {
                        ForEach(mappedSunriseTags) { tag in
                            tagRow(tag)
                        }
                    }

                    scanTagButton

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

                    Text(NFCTagSetupInstructions.placementGuidance(for: .sunrise))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        SleepSetupCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(NFCTagSetupInstructions.backgroundReadExplainer)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        NFCStepList(steps: NFCTagSetupInstructions.shortcutsAutomationSteps)
                    }
                    .padding(.top, Theme.Spacing.xs)
                } label: {
                    Text(Copy.sunriseAlarm.tagBackgroundReadHeader)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                }

                Rectangle()
                    .fill(SleepSetupDepth.edge)
                    .frame(height: 1)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(Array(NFCTagSetupInstructions.troubleshooting.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                } label: {
                    Text(Copy.sunriseAlarm.tagTroubleshootingHeader)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                }
            }
            .tint(Theme.Colors.muted)
        }
    }

    private func tagRow(_ tag: NFCTagMapping) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            SleepSetupIconBadge(systemImage: "wave.3.right", tint: Theme.Colors.Ring.sunriseAlarm)

            Text(tag.label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)

            Spacer(minLength: Theme.Spacing.sm)

            // Explicit control instead of a swipe action: this is a card, not a `List` row, and a
            // gesture-only delete is undiscoverable anyway.
            Button(Copy.sunriseAlarm.forgetTagButtonLabel, role: .destructive) {
                pendingTagRemoval = tag
            }
            .font(Theme.Typography.captionEmphasized)
            .foregroundStyle(Theme.Colors.danger)
            .frame(minHeight: SleepSetupMetrics.minTapTarget)
            .buttonStyle(SleepSetupPressStyle())
        }
    }

    private var scanTagButton: some View {
        Button {
            scanAndMapSunriseTag()
        } label: {
            Group {
                if isScanningTag {
                    // Qualified: the app declares its own `ProgressView` screen, which shadows
                    // SwiftUI's spinner for any bare `ProgressView()` in this module — this used to
                    // mount the whole Progress tab inside the button (better-ui BRK-01).
                    SwiftUI.ProgressView()
                } else {
                    Label(Copy.sunriseAlarm.tagScanButtonLabel, systemImage: "plus")
                }
            }
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, minHeight: SleepSetupMetrics.minTapTarget)
            .background(Theme.Colors.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(SleepSetupDepth.edge, lineWidth: 1))
        }
        .buttonStyle(SleepSetupPressStyle())
        .disabled(isScanningTag || !NFCReader.isAvailable)
        .opacity(NFCReader.isAvailable ? 1 : 0.5)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.sunriseAlarm.stepsSectionHeader)

            SleepSetupCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    StepsTargetStepper(
                        value: $settings.stepsTarget,
                        range: 20...300,
                        step: 10,
                        unitLabel: Copy.sunriseAlarm.stepsSectionHeader,
                        accessibilityLabel: Copy.sunriseAlarm.stepsTargetLabel(target: settings.stepsTarget)
                    )

                    Text(Copy.sunriseAlarm.stepsHelperText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.sunriseAlarm.focusSectionHeader)

            SleepSetupCard {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    SleepSetupIconBadge(systemImage: "wind", tint: Theme.Colors.Ring.focus)

                    Text(Copy.sunriseAlarm.focusHelperText)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var squadSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.sunriseAlarm.squadSectionHeader)

            SleepSetupCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
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
                        .pickerStyle(.menu)
                        .frame(minHeight: SleepSetupMetrics.minTapTarget)
                    }

                    Text(Copy.sunriseAlarm.squadHelperText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Technology / safety

    private var technologySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SleepSetupSectionHeader(title: Copy.sunriseAlarm.techSectionHeader)

            SleepSetupCard {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    // The fallback tier is a real caveat (weaker alarm), so it is `warning`; the
                    // full tier is neutral rather than accent, which is reserved for earned states.
                    SleepSetupIconBadge(
                        systemImage: supportsAlarmKit ? "alarm.waves.left.and.right.fill" : "bell.badge.fill",
                        tint: supportsAlarmKit ? Theme.Colors.text : Theme.Colors.warning
                    )

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(supportsAlarmKit ? Copy.sunriseAlarm.techTierAlarmKitLabel : Copy.sunriseAlarm.techTierFallbackLabel)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                        Text(supportsAlarmKit ? Copy.sunriseAlarm.techTierAlarmKitDetail : Copy.sunriseAlarm.techTierFallbackDetail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Spec §5.10: "Never promise 'this will always wake you'... Keep a standard-alarm
            // reminder in the setup flow."
            Text(Copy.sunriseAlarm.standardAlarmReminderText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await SunriseAlarmManager.shared.saveSettings(settings)
                isSaving = false
                saveTick += 1
                dismiss()
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
    /// SF Symbol shown in `variantTile` — display-only metadata, not user-facing copy, so this file
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

// MARK: - Steps target stepper

/// A big-numeral stepper for the Steps variant's N. Two 44pt circular buttons flank the number
/// (`numeralLarge`) with the unit under it. VoiceOver gets a single adjustable element (swipe up /
/// down to change by `step`), like a native `Stepper`, and the two visual buttons are hidden from
/// it, so there are no unlabelled "minus"/"plus" buttons to announce (this file may not add Copy
/// keys for them).
private struct StepsTargetStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// The muted unit caption under the number (an existing `Copy.sunriseAlarm` string).
    let unitLabel: String
    /// The VoiceOver label, e.g. "40 steps".
    let accessibilityLabel: String

    // Not `private`: this struct is built through its memberwise init from another type, and a
    // private stored property can make that synthesized init inaccessible.
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            stepButton(systemImage: "minus", isEnabled: value - step >= range.lowerBound) {
                adjust(by: -step)
            }

            VStack(spacing: 0) {
                Text("\(value)")
                    .font(Theme.Typography.numeralLarge())
                    .foregroundStyle(Theme.Colors.text)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
                Text(unitLabel)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .frame(maxWidth: .infinity)

            stepButton(systemImage: "plus", isEnabled: value + step <= range.upperBound) {
                adjust(by: step)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: step)
            case .decrement: adjust(by: -step)
            @unknown default: break
            }
        }
    }

    private func adjust(by delta: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + delta))
        guard next != value else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) {
            value = next
        }
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: SleepSetupMetrics.minTapTarget, height: SleepSetupMetrics.minTapTarget)
                .background(Theme.Colors.surface2, in: Circle())
                .overlay(Circle().strokeBorder(SleepSetupDepth.edge, lineWidth: 1))
        }
        .buttonStyle(SleepSetupPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared step-list renderer (used here for the NFC background-read disclosure)

/// Renders an ordered `[NFCTagSetupInstructions.Step]` as numbered rows. File-scoped (`internal`
/// would leak it outside this directory unnecessarily) since only this file's DisclosureGroups use
/// it today.
private struct NFCStepList: View {
    let steps: [NFCTagSetupInstructions.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    // Neutral disc (`text` on `surface2`), the same treatment Settings' NFC screen gives
                    // these same steps: they are decoration, and accent means earned/selected/CTA.
                    Text("\(step.id)")
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: 24, height: 24)
                        .background(Theme.Colors.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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

// MARK: - Shared setup building blocks (also used by BedtimeGateSetupView)
//
// `internal` on purpose: `BedtimeGateSetupView.swift` reuses these so the two companion screens
// read as one feature. Edges, hit targets and the card surface are the shared ones (review pass: the
// private edge tokens and `SleepSetupCardSurface` this file carried before `Theme.Colors.hairline` /
// `zanoCard` existed were removed).

enum SleepSetupMetrics {
    /// HIG minimum hit target.
    static let minTapTarget: CGFloat = Theme.Metrics.minTapTarget
    /// Minimum height of a dismiss-method tile, so all four match regardless of title length.
    static let tileHeight: CGFloat = 96
}

enum SleepSetupDepth {
    /// 1px edge for chrome and unselected tiles: the shared `hairline`.
    static let edge = Theme.Colors.hairline
}

/// A `zanoCard` (surface, top-lit edge, `Radius.medium`). Every block on the two sleep setup screens
/// is one of these, replacing the stock grouped-`Form` rows.
struct SleepSetupCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
    }
}

/// The section header above a card: a sentence-case headline in `text` (premium pass 2026-09-24
/// removed the tracked all-caps eyebrow; hierarchy comes from size and weight).
struct SleepSetupSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .zanoText(.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A 32pt circular icon badge tinted by `tint` (decorative, so hidden from VoiceOver). The shared
/// `IconBadge(.small)`: same 32pt disc, `Theme.Colors.wash(tint)` fill (an on-hue wash, not
/// `tint.opacity(...)`, which goes olive on the accent).
struct SleepSetupIconBadge: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        IconBadge(systemName: systemImage, tint: tint, size: .small)
    }
}

/// Press feedback for tappable cards and small controls: a slight scale plus an opacity dip. Under
/// Reduce Motion the scale is dropped and the settle becomes a flat ease, but the opacity dip stays
/// (it is real information: "the interface heard you").
struct SleepSetupPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.16, dampingFraction: 0.75),
                value: configuration.isPressed
            )
    }
}

/// The hero time card shared by the wake-time and bedtime screens: an eyebrow with a tinted icon,
/// the time itself as a 64pt numeral, and a tap-to-reveal inline wheel picker. The number is the
/// thing the screen exists to set, so it is the biggest thing on it (docs/design/
/// better-layout-findings.md 1.11); the wheel stays hidden until asked for so the screen opens
/// calm.
struct SleepTimeCard: View {
    private let systemImage: String
    private let tint: Color
    private let label: String
    @Binding private var time: Date

    @State private var isEditing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Hero time size; scales with Dynamic Type (Theme has no numeral step this large yet).
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 64

    init(systemImage: String, tint: Color, label: String, time: Binding<Date>) {
        self.systemImage = systemImage
        self.tint = tint
        self.label = label
        self._time = time
    }

    var body: some View {
        SleepSetupCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard) {
                        isEditing.toggle()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            SleepSetupIconBadge(systemImage: systemImage, tint: tint)

                            Text(label)
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.muted)

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.muted)
                                .rotationEffect(.degrees(isEditing ? 180 : 0))
                                .accessibilityHidden(true)
                        }

                        Text(time, format: .dateTime.hour().minute())
                            .font(Theme.Typography.numeral(size: timeSize, weight: .heavy))
                            .tracking(-1)
                            .foregroundStyle(Theme.Colors.text)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SleepSetupPressStyle())

                if isEditing {
                    DatePicker(label, selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

/// The pinned Save bar for the two setup screens: a `PrimaryButton` in the shared `StickyActionBar`
/// (a fade into the background, 16pt gutters), the same pinned-action chrome the onboarding, paywall
/// and share screens use.
struct SleepSetupSaveBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        StickyActionBar {
            PrimaryButton(title: title, isEnabled: isEnabled, action: action)
        }
    }
}

#Preview {
    NavigationStack {
        SunriseAlarmSetupView()
    }
    .preferredColorScheme(.dark)
}
