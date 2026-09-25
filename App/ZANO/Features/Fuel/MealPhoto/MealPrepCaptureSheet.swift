// App/ZANO/Features/Fuel/MealPhoto/MealPrepCaptureSheet.swift
//
// Spec 3, "Meal prep (weekly)" row (Tier B): "Photo of prepped containers, vision model confirms
// 'multiple meal containers'"; anti-cheat "Weekly only". Everything goes through
// `MealPrepVerifier` (weekly cap, GoalEvent write, `GoalCompletionCoordinator`).
//
// Two paths, picked at log time:
//   - Vision: `MealPrepVerifier.hasVisionBackend` AND `MealVisionClient.isConfigured` -> upload the
//     JPEG to `meal-photos`, then `verifyMealPrep(goalID:photoPath:)`. Not confirmed -> retake
//     with the model's note.
//   - Honor tier (today's reality: meal-vision has no container-count mode, so nothing calls
//     `setBackend`): `MealPrepVerifier.logHonorTier(goalID:)`, with the review screen saying
//     plainly that this one counts on the user's word. Fully local; works offline.
// Photo dedupe applies to both (a photo already counted for protein can't also count as prep).
//
// Presented by Today: `.sheet(item:) { MealPrepCaptureSheet(goalID: $0.id) }`. It dismisses
// itself.

import SwiftUI
import UIKit
import Core

struct MealPrepCaptureSheet: View {
    let goalID: UUID

    init(goalID: UUID) {
        self.goalID = goalID
    }

    private enum Phase {
        case loading
        case alreadyDone(nextDay: String)
        case capture
        case checking(UIImage)
        case duplicate
        case review(UIImage, PreparedMealPhoto)
        case submitting(UIImage)
        case success(honor: Bool)
        case rejected(notes: String)
        case failed(message: String)

        var key: Int {
            switch self {
            case .loading: 0
            case .alreadyDone: 1
            case .capture: 2
            case .checking: 3
            case .duplicate: 4
            case .review: 5
            case .submitting: 6
            case .success: 7
            case .rejected: 8
            case .failed: 9
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .loading
    @State private var visionAvailable = false
    @State private var successTick = 0
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background.ignoresSafeArea())
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: phase.key)
                .navigationTitle(Copy.fuel.mealPhoto.mealPrepTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if phase.key != 6 && phase.key != 7 {
                            Button(Copy.common.cancel) {
                                work?.cancel()
                                dismiss()
                            }
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: successTick)
        .interactiveDismissDisabled(phase.key == 6)
        .task { await load() }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            SwiftUI.ProgressView()
                .controlSize(.large)
                .tint(Theme.Colors.accent)
        case .alreadyDone(let nextDay):
            MealPhotoMessageView(
                systemImage: "checkmark.circle.fill",
                tint: Theme.Colors.Ring.mealPrep,
                title: Copy.fuel.mealPhoto.mealPrepAlreadyDoneTitle,
                message: Copy.fuel.mealPhoto.mealPrepAlreadyDoneMessage(nextDay: nextDay)
            ) {
                PrimaryButton(title: Copy.fuel.mealPhoto.doneButton, tint: .neutral) { dismiss() }
            }
        case .capture:
            MealPhotoCaptureStage(
                headline: Copy.fuel.mealPhoto.mealPrepHeadline,
                hint: Copy.fuel.mealPhoto.mealPrepHint,
                onImage: { handle($0) }
            )
            .transition(.opacity)
        case .checking(let image):
            MealPhotoWorkingView(image: image, caption: Copy.fuel.mealPhoto.checkingPhoto)
        case .duplicate:
            MealPhotoMessageView(
                systemImage: "photo.on.rectangle.angled",
                tint: Theme.Colors.warning,
                title: Copy.fuel.mealPhoto.duplicateTitle,
                message: Copy.fuel.mealPhoto.duplicateMessage
            ) {
                PrimaryButton(title: Copy.fuel.mealPhoto.retakeButton, systemImage: "camera") { phase = .capture }
            }
        case .review(let image, let prepared):
            review(image: image, prepared: prepared)
                .transition(.opacity)
        case .submitting(let image):
            MealPhotoWorkingView(image: image, caption: Copy.fuel.mealPhoto.mealPrepChecking)
        case .success(let honor):
            MealPhotoMessageView(
                systemImage: "checkmark.seal.fill",
                tint: Theme.Colors.Ring.mealPrep,
                title: honor ? Copy.fuel.mealPhoto.mealPrepHonorTitle : Copy.fuel.mealPhoto.mealPrepConfirmedTitle,
                message: honor ? Copy.fuel.mealPhoto.mealPrepHonorMessage : Copy.fuel.mealPhoto.mealPrepConfirmedMessage
            ) {
                PrimaryButton(title: Copy.fuel.mealPhoto.doneButton, tint: .accent) { dismiss() }
            }
        case .rejected(let notes):
            MealPhotoMessageView(
                systemImage: "square.stack.3d.up",
                tint: Theme.Colors.warning,
                title: Copy.fuel.mealPhoto.mealPrepRejectedTitle,
                message: notes.isEmpty
                    ? Copy.fuel.mealPhoto.mealPrepRejectedMessage
                    : "\(Copy.fuel.mealPhoto.mealPrepRejectedMessage) \(notes)"
            ) {
                PrimaryButton(title: Copy.fuel.mealPhoto.retakeButton, systemImage: "camera") { phase = .capture }
            }
        case .failed(let message):
            MealPhotoMessageView(
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.Colors.warning,
                title: Copy.fuel.mealPhoto.mealPrepTitle,
                message: message
            ) {
                PrimaryButton(title: Copy.fuel.mealPhoto.retakeButton, systemImage: "camera") { phase = .capture }
            }
        }
    }

    private func review(image: UIImage, prepared: PreparedMealPhoto) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                        .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
                )
                .accessibilityLabel(Copy.fuel.mealPhoto.photoAccessibilityLabel)
                .accessibilityAddTraits(.isImage)

            if !visionAvailable {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: "hand.raised")
                        .font(Theme.Typography.icon(.small))
                        .accessibilityHidden(true)
                    Text(Copy.fuel.mealPhoto.mealPrepHonorExplainer)
                        .font(Theme.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.sm) {
                PrimaryButton(title: Copy.fuel.mealPhoto.mealPrepLogButton) { submit(image: image, prepared: prepared) }
                PrimaryButton(title: Copy.fuel.mealPhoto.retakeButton, style: .secondary) { phase = .capture }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: Flow

    private func load() async {
        guard case .loading = phase else { return }
        let verifier = MealPrepVerifier.shared
        let clientReady = await MealVisionClient.shared.isConfigured
        visionAvailable = verifier.hasVisionBackend && clientReady
        if verifier.isEligibleThisWeek(goalID: goalID) {
            phase = .capture
        } else {
            phase = .alreadyDone(nextDay: Self.nextWeekLabel())
        }
        Analytics.shared.capture(event: "meal_prep_photo_opened", properties: ["vision": visionAvailable])
    }

    private func handle(_ image: UIImage) {
        phase = .checking(image)
        work?.cancel()
        work = Task {
            guard let prepared = await MealPhotoProcessing.prepare(image) else {
                phase = .failed(message: Copy.fuel.mealPhoto.photoLoadFailedMessage)
                return
            }
            if Task.isCancelled { return }
            if let hash = prepared.hash, await PhotoDedupe.wouldBeDuplicate(hash: hash) {
                Analytics.shared.capture(event: "meal_prep_photo_duplicate")
                phase = .duplicate
                return
            }
            phase = .review(image, prepared)
        }
    }

    private func submit(image: UIImage, prepared: PreparedMealPhoto) {
        phase = .submitting(image)
        let goalID = goalID
        let useVision = visionAvailable
        work?.cancel()
        work = Task {
            do {
                let honor: Bool
                if useVision {
                    let photoPath = try await MealVisionClient.shared.uploadMealPhoto(jpegData: prepared.jpeg)
                    let result = try await MealPrepVerifier.shared.verifyMealPrep(goalID: goalID, photoPath: photoPath)
                    guard result.confirmed else {
                        Analytics.shared.capture(event: "meal_prep_photo_rejected", properties: ["containers": result.containersDetected])
                        phase = .rejected(notes: result.notes)
                        return
                    }
                    honor = false
                } else {
                    try await MealPrepVerifier.shared.logHonorTier(goalID: goalID)
                    honor = true
                }
                if let hash = prepared.hash {
                    await PhotoDedupe.recordAccepted(hash: hash)
                }
                Analytics.shared.capture(event: "meal_prep_logged", properties: ["honor": honor])
                successTick += 1
                phase = .success(honor: honor)
            } catch let error as MealPrepVerifierError {
                switch error {
                case .alreadyVerifiedThisWeek:
                    phase = .alreadyDone(nextDay: Self.nextWeekLabel())
                case .goalNotFound, .wrongGoalType, .userNotFoundForGoal:
                    phase = .failed(message: Copy.fuel.mealPhoto.mealPrepNotFoundMessage)
                case .emptyPhotoPath, .backendUnavailable:
                    phase = .failed(message: Copy.fuel.mealPhoto.mealPrepFailedMessage)
                }
            } catch MealVisionClientError.offline {
                phase = .failed(message: Copy.fuel.mealPhoto.mealPrepOfflineMessage)
            } catch {
                Analytics.shared.capture(event: "meal_prep_log_failed", properties: ["reason": String(describing: error)])
                phase = .failed(message: Copy.fuel.mealPhoto.mealPrepFailedMessage)
            }
        }
    }

    /// "Monday, Sep 28": the start of next calendar week, matching `MealPrepVerifier`'s own
    /// `.weekOfYear` boundary.
    private static func nextWeekLabel(now: Date = .now) -> String {
        let next = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end
            ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        return next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
