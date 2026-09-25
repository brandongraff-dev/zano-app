// WriteTagFlow.swift
// App / ZANO / Features / NFC
//
// "Add a tag", start to finish, in one sheet: scan → (program a blank tag with a fresh
// `zano://tag/<uuid>` | recognize an existing ZANO tag) → map it (`NFCMapTagSheet`). Blank NTAG
// stickers used to fail with a generic "couldn't read" error; now they just work.
//
// Present as a sheet. It owns its own NavigationStack (and swaps to the map sheet's stack after a
// successful scan), so don't wrap it in another one.

import SwiftUI
import Core

struct WriteTagFlow: View {
    /// Placement the map step starts from (`.lockCard` when pairing a Lock Card).
    var initialKind: NFCTagKind = .custom
    /// Called once: with the saved mapping, or `nil` if the user backed out.
    let onFinished: (NFCTagMapping?) -> Void

    private enum Stage: Equatable {
        case ready
        case scanning(NFCWriteStage)
        case succeeded(NFCWriteOutcome)
        case alreadyMapped(tagID: UUID)
        case failed(NFCWriteFailure)
    }

    private struct MapTarget: Identifiable {
        let tagID: UUID
        let existing: NFCTagMapping?
        var id: UUID { tagID }
    }

    @State private var stage: Stage = .ready
    @State private var mapTarget: MapTarget?
    @State private var existingMapping: NFCTagMapping?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let mapTarget {
                NFCMapTagSheet(
                    tagID: mapTarget.tagID,
                    existing: mapTarget.existing,
                    initialKind: initialKind,
                    onSaved: { onFinished($0) },
                    onCancel: { onFinished(nil) }
                )
                .transition(.opacity)
            } else {
                NavigationStack {
                    scanContent
                        .navigationTitle(Copy.nfc.writeTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(Copy.common.cancel) {
                                    NFCWriter.shared.stop()
                                    onFinished(nil)
                                }
                            }
                        }
                }
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
            }
        }
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: mapTarget?.id)
        .onDisappear {
            if case .scanning = stage { NFCWriter.shared.stop() }
        }
    }

    // MARK: Scan screen

    private var scanContent: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                TagTapScene(phase: scenePhase, style: initialKind == .lockCard ? .card : .sticker)
                    .padding(.top, Theme.Spacing.md)

                VStack(spacing: Theme.Spacing.xs) {
                    Text(title)
                        .zanoText(.title)
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .zanoText(.paragraph)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                stageDetail
            }
            .padding(Theme.Spacing.md)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: stage)
        }
        .scrollBounceBehavior(.basedOnSize)
        .zanoBackdrop(glow: Theme.Colors.accent, intensity: scenePhase == .failure ? 0.05 : 0.14)
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var scenePhase: TagTapScene.Phase {
        switch stage {
        case .ready: .idle
        case .scanning: .active
        case .succeeded, .alreadyMapped: .success
        case .failed: .failure
        }
    }

    private var title: String {
        switch stage {
        case .ready, .scanning: Copy.nfc.writeReadyTitle
        case .succeeded(.wroteNew): Copy.nfc.writeSuccessNewTitle
        case .succeeded(.alreadyZano): Copy.nfc.writeSuccessExistingTitle
        case .alreadyMapped: Copy.nfc.writeAlreadyMappedTitle
        case .failed: Copy.nfc.writeFailedTitle
        }
    }

    private var message: String? {
        switch stage {
        case .ready, .scanning:
            return NFCWriter.isAvailable ? Copy.nfc.writeReadyMessage : Copy.nfc.writeFailureUnsupported
        case .succeeded:
            return nil
        case .alreadyMapped:
            guard let existingMapping else { return nil }
            return Copy.nfc.writeAlreadyMappedMessage(
                label: existingMapping.nfcDisplayName,
                summary: existingMapping.action.nfcSummary()
            )
        case .failed(let failure):
            return Self.message(for: failure)
        }
    }

    @ViewBuilder
    private var stageDetail: some View {
        switch stage {
        case .ready:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                NFCStepRow(number: 1, title: Copy.nfc.writeStepStick)
                NFCStepRow(number: 2, title: Copy.nfc.writeStepHold)
                NFCStepRow(number: 3, title: Copy.nfc.writeStepPick)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
        case .scanning(let current):
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                progressRow(Copy.nfc.writeStageWaiting, index: 0, current: current)
                progressRow(Copy.nfc.writeStageConnecting, index: 1, current: current)
                progressRow(Copy.nfc.writeStageWriting, index: 2, current: current)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoCard()
        case .succeeded, .alreadyMapped, .failed:
            EmptyView()
        }
    }

    private func progressRow(_ text: String, index: Int, current: NFCWriteStage) -> some View {
        let currentIndex: Int = switch current {
        case .waitingForTag: 0
        case .connecting: 1
        case .writing: 2
        }
        let done = index < currentIndex
        let active = index == currentIndex
        return HStack(spacing: Theme.Spacing.sm) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                } else if active {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Colors.accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(Theme.Colors.hairlineStrong)
                }
            }
            .font(Theme.Typography.icon(.medium))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            Text(text)
                .font(active ? Theme.Typography.headline : Theme.Typography.body)
                .foregroundStyle(active || done ? Theme.Colors.text : Theme.Colors.muted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            switch stage {
            case .ready:
                PrimaryButton(
                    title: Copy.nfc.writeStartButton,
                    systemImage: "wave.3.right",
                    isEnabled: NFCWriter.isAvailable
                ) {
                    Task { await scan(overwrite: false) }
                }
            case .scanning, .succeeded:
                EmptyView()
            case .alreadyMapped(let tagID):
                PrimaryButton(title: Copy.nfc.editTagButton, systemImage: "slider.horizontal.3") {
                    mapTarget = MapTarget(tagID: tagID, existing: existingMapping)
                }
                PrimaryButton(title: Copy.common.done, style: .secondary) {
                    onFinished(existingMapping)
                }
            case .failed(let failure):
                if failure == .foreignContent {
                    PrimaryButton(title: Copy.nfc.writeOverwriteButton, systemImage: "eraser", tint: .warning) {
                        Task { await scan(overwrite: true) }
                    }
                    PrimaryButton(title: Copy.nfc.writeRetryButton, style: .secondary) {
                        Task { await scan(overwrite: false) }
                    }
                } else {
                    PrimaryButton(
                        title: Copy.nfc.writeRetryButton,
                        systemImage: "arrow.clockwise",
                        isEnabled: failure != .unsupportedDevice && failure != .unavailablePlatform
                    ) {
                        Task { await scan(overwrite: false) }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: Logic

    private func scan(overwrite: Bool) async {
        stage = .scanning(.waitingForTag)
        do {
            let outcome = try await NFCWriter.shared.programTag(
                overwriteForeignContent: overwrite,
                messages: Copy.nfc.writerMessages,
                onStage: { newStage in stage = .scanning(newStage) }
            )
            var written = false
            if case .wroteNew = outcome { written = true }
            Analytics.shared.capture(
                event: "nfc_tag_scanned_for_setup",
                properties: ["outcome": written ? "written" : "existing"]
            )
            let existing = await NFCTagMapper.shared.mapping(for: outcome.tagID)
            existingMapping = existing
            if existing != nil {
                stage = .alreadyMapped(tagID: outcome.tagID)
                return
            }
            stage = .succeeded(outcome)
            // Let the check land before moving on to "what does it do".
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 900))
            mapTarget = MapTarget(tagID: outcome.tagID, existing: nil)
        } catch NFCWriteFailure.cancelled {
            stage = .ready
        } catch let failure as NFCWriteFailure {
            stage = .failed(failure)
        } catch {
            stage = .failed(.invalidatedWithError(error.localizedDescription))
        }
    }

    private static func message(for failure: NFCWriteFailure) -> String {
        switch failure {
        case .unsupportedDevice, .unavailablePlatform: Copy.nfc.writeFailureUnsupported
        case .notNDEFCompatible: Copy.nfc.writeFailureNotNDEF
        case .readOnly: Copy.nfc.writeFailureReadOnly
        case .foreignContent: Copy.nfc.writeFailureForeign
        case .insufficientCapacity: Copy.nfc.writeFailureCapacity
        case .tagCommunicationFailed: Copy.nfc.writeFailureCommunication
        case .sessionAlreadyActive, .cancelled, .invalidatedWithError: Copy.nfc.writeFailureGeneric
        }
    }
}
