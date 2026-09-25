// App/ZANO/Features/Fuel/MealPhoto/MealCaptureSheet.swift
//
// Spec 3 (Protein, Tier B: "meal photo -> vision model estimate"; anti-cheat "photo dedupe"),
// spec 9.5 (Meal Vision), spec 9.8 (identical-photo detection, "never accuse — just don't count").
//
// capture -> checking (downscale, JPEG, perceptual hash) -> duplicate? -> analyzing (only when
// `MealVisionClient` is configured) -> confirm (`MealEstimateConfirmView`).
//
// Degrades to manual entry instead of failing: no Supabase project/auth configured, offline,
// upstream error, or an unreadable response all land on the confirm screen with a blank estimate
// and a one-line note saying why. Logging itself is local (`LogProteinIntent`), so the whole
// flow works with no network at all.

import SwiftUI
import UIKit
import Core

struct MealCaptureSheet: View {
    /// Called once after a successful log, with the grams logged. The caller dismisses.
    let onLogged: (Int) -> Void
    let onCancel: () -> Void

    private enum Phase {
        case capture
        case checking(UIImage)
        case duplicate
        case analyzing(UIImage)
        case confirm(MealEstimateDraft)

        var key: Int {
            switch self {
            case .capture: 0
            case .checking: 1
            case .duplicate: 2
            case .analyzing: 3
            case .confirm: 4
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .capture
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background.ignoresSafeArea())
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: phase.key)
                .navigationTitle(phase.key == 4 ? Copy.fuel.mealPhoto.confirmTitle : Copy.fuel.mealPhoto.captureTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.common.cancel) {
                            work?.cancel()
                            onCancel()
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .onAppear { Analytics.shared.capture(event: "fuel_meal_photo_opened") }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .capture:
            MealPhotoCaptureStage(
                headline: Copy.fuel.mealPhoto.captureHeadline,
                hint: Copy.fuel.mealPhoto.captureHint,
                onImage: { handle($0) },
                onManual: { phase = .confirm(.blank) }
            )
            .transition(.opacity)
        case .checking(let image):
            MealPhotoWorkingView(image: image, caption: Copy.fuel.mealPhoto.checkingPhoto)
                .transition(.opacity)
        case .analyzing(let image):
            MealPhotoWorkingView(image: image, caption: Copy.fuel.mealPhoto.analyzing)
                .transition(.opacity)
        case .duplicate:
            MealPhotoMessageView(
                systemImage: "photo.on.rectangle.angled",
                tint: Theme.Colors.warning,
                title: Copy.fuel.mealPhoto.duplicateTitle,
                message: Copy.fuel.mealPhoto.duplicateMessage
            ) {
                PrimaryButton(title: Copy.fuel.mealPhoto.retakeButton, systemImage: "camera") {
                    phase = .capture
                }
                PrimaryButton(title: Copy.fuel.mealPhoto.enterManuallyButton, style: .secondary) {
                    phase = .confirm(.blank)
                }
            }
            .transition(.opacity)
        case .confirm(let draft):
            MealEstimateConfirmView(draft: draft, onLogged: onLogged)
                .transition(.opacity)
        }
    }

    // MARK: Flow

    private func handle(_ image: UIImage) {
        phase = .checking(image)
        work?.cancel()
        work = Task {
            guard let prepared = await MealPhotoProcessing.prepare(image) else {
                // Couldn't encode the photo: still let them log, without the photo.
                phase = .confirm(MealEstimateDraft(image: nil, prepared: nil, estimate: nil, note: .failed))
                return
            }
            if Task.isCancelled { return }

            if let hash = prepared.hash, await PhotoDedupe.wouldBeDuplicate(hash: hash) {
                Analytics.shared.capture(event: "fuel_meal_photo_duplicate")
                phase = .duplicate
                return
            }

            guard await MealVisionClient.shared.isConfigured else {
                phase = .confirm(MealEstimateDraft(image: image, prepared: prepared, estimate: nil, note: .notConfigured))
                return
            }

            phase = .analyzing(image)
            let draft: MealEstimateDraft
            do {
                let estimate = try await MealVisionClient.shared.analyze(jpegData: prepared.jpeg)
                draft = MealEstimateDraft(
                    image: image,
                    prepared: prepared,
                    estimate: estimate,
                    note: estimate.items.isEmpty ? .noFood : nil
                )
                Analytics.shared.capture(
                    event: "fuel_meal_photo_estimated",
                    properties: ["items": estimate.items.count, "low_confidence": estimate.isLowConfidence]
                )
            } catch {
                let note: MealEstimateNote
                switch error as? MealVisionClientError {
                case .offline?: note = .offline
                case .notConfigured?: note = .notConfigured
                default: note = .failed
                }
                Analytics.shared.capture(event: "fuel_meal_photo_estimate_failed", properties: ["reason": String(describing: error)])
                draft = MealEstimateDraft(image: image, prepared: prepared, estimate: nil, note: note)
            }
            if Task.isCancelled { return }
            phase = .confirm(draft)
        }
    }
}
