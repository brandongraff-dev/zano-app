// App/ZANO/Features/Fuel/MealPhoto/MealEstimateConfirmView.swift
//
// Spec 9.5 Meal Vision: "User confirms/edits ... Confirmed values are stored as the user's food
// memory." The photo, what the model spotted, and the protein number as the one editable thing,
// then "Log 38 g". Also the manual fallback: same screen, blank estimate (no backend, offline,
// estimate failed, or the user chose to type it).
//
// Logging goes through `LogProteinIntent` (CLAUDE.md: every user action is an intent), then — only
// once that succeeded — the bookkeeping: count the photo in `PhotoDedupe`, save the `Meal` row
// (feeds Quick Repeats, spec 5.19), and tell meal-vision the confirmed values (best effort).
//
// Source: `GoalLogSource` has no `.photo` case yet (`Intents/IntentSupport.swift`, not owned by
// this change), though `GoalEventSource.photo` exists. `photoSource` below resolves `"photo"` by
// raw value, so it becomes `.photo` the moment that case is added (with its `eventSource` mapping)
// and falls back to `.manual` until then.

import SwiftUI
import SwiftData
import UIKit
import Core

/// Why there's no (usable) estimate, shown as a one-line note above the amount.
enum MealEstimateNote: Equatable {
    case notConfigured
    case offline
    case failed
    case noFood

    var text: String {
        switch self {
        case .notConfigured: Copy.fuel.mealPhoto.notConfiguredNote
        case .offline: Copy.fuel.mealPhoto.offlineNote
        case .failed: Copy.fuel.mealPhoto.estimateFailedNote
        case .noFood: Copy.fuel.mealPhoto.noFoodFoundNote
        }
    }
}

/// Everything the confirm screen needs from the capture flow.
struct MealEstimateDraft {
    var image: UIImage?
    var prepared: PreparedMealPhoto?
    var estimate: MealVisionEstimate?
    var note: MealEstimateNote?

    var initialGrams: Int {
        guard let estimate else { return 0 }
        return min(MealEstimateConfirmView.maxGrams, Int(estimate.totalProteinG.rounded()))
    }

    /// Typed in, no photo at all.
    static let blank = MealEstimateDraft()
}

struct MealEstimateConfirmView: View {
    let draft: MealEstimateDraft
    /// Called once, after the log succeeded, with the grams logged.
    let onLogged: (Int) -> Void

    static let maxGrams = 300
    static let quickSetGrams = [20, 30, 40, 50]
    static var photoSource: GoalLogSource { .photo }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var users: [User]

    @State private var grams: Int
    @State private var hasAdjusted = false
    @State private var isLogging = false
    @State private var errorMessage: String?

    init(draft: MealEstimateDraft, onLogged: @escaping (Int) -> Void) {
        self.draft = draft
        self.onLogged = onLogged
        _grams = State(initialValue: draft.initialGrams)
    }

    private var items: [MealItem] { draft.estimate?.items ?? [] }
    private var isManual: Bool { draft.estimate == nil }
    private var showsLowConfidenceNudge: Bool {
        guard let estimate = draft.estimate, !estimate.items.isEmpty else { return false }
        return estimate.isLowConfidence && !hasAdjusted
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let image = draft.image {
                        photo(image)
                    }
                    if let note = draft.note {
                        noteRow(note.text, systemImage: "info.circle")
                    }
                    if !items.isEmpty {
                        itemsSection
                    }
                    amountSection
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: Theme.Spacing.xs) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        .multilineTextAlignment(.center)
                }
                PrimaryButton(
                    title: grams > 0 ? Copy.fuel.mealPhoto.logButton(grams: grams) : Copy.fuel.mealPhoto.logButtonEmpty,
                    isEnabled: grams > 0 && !isLogging,
                    action: { log() }
                )
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        }
    }

    // MARK: Sections

    private func photo(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.fuel.mealPhoto.photoAccessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }

    private func noteRow(_ text: String, systemImage: String, tint: Color = Theme.Colors.textSecondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.fuel.mealPhoto.detectedItemsHeader)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let itemGrams = Int(item.proteinGramsEstimate.rounded())
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(item.confidence < MealVisionEstimate.lowConfidenceThreshold ? Theme.Colors.warning : Theme.Colors.Ring.protein)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(item.name.capitalized)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text("≈ \(Copy.fuel.grams(itemGrams))")
                            .font(Theme.Typography.numeralSmall())
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    .frame(minHeight: Theme.Metrics.minTapTarget)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Copy.fuel.mealPhoto.itemAccessibilityLabel(name: item.name, grams: itemGrams))
                    if index < items.count - 1 {
                        Rectangle().fill(Theme.Colors.hairline).frame(height: 1).padding(.leading, Theme.Spacing.sm)
                    }
                }
            }
            .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
    }

    private var amountSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(isManual ? Copy.fuel.mealPhoto.manualCaption : Copy.fuel.mealPhoto.estimateCaption)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.lg) {
                stepButton(systemImage: "minus", delta: -1)
                    .disabled(grams <= 0)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                    Text("\(grams)")
                        .font(Theme.Typography.numeralHero())
                        .foregroundStyle(Theme.Colors.Ring.protein)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(grams)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(Copy.fuel.gramsUnit)
                        .font(Theme.Typography.unit)
                        .foregroundStyle(Theme.Colors.muted)
                }
                .frame(minWidth: 120)
                stepButton(systemImage: "plus", delta: 1)
                    .disabled(grams >= Self.maxGrams)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.fuel.mealPhoto.stepperAccessibilityLabel)
            .accessibilityValue(Copy.fuel.grams(grams))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(grams + 1)
                case .decrement: set(grams - 1)
                @unknown default: break
                }
            }

            if showsLowConfidenceNudge {
                noteRow(Copy.fuel.mealPhoto.lowConfidenceNudge, systemImage: "hand.point.up.left", tint: Theme.Colors.warning)
                    .transition(.opacity)
            }

            if isManual {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Self.quickSetGrams, id: \.self) { value in
                        Button {
                            set(value)
                        } label: {
                            Text(Copy.fuel.grams(value))
                                .font(Theme.Typography.numeralSmall())
                                .foregroundStyle(grams == value ? Theme.Colors.onFill : Theme.Colors.text)
                                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
                                .background {
                                    if grams == value {
                                        Capsule(style: .continuous).fill(Theme.Colors.Ring.protein)
                                    } else {
                                        ZanoGlass(Capsule(style: .continuous))
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                        .accessibilityLabel(Copy.fuel.mealPhoto.quickSetAccessibilityLabel(grams: value))
                        .accessibilityAddTraits(grams == value ? .isSelected : [])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: grams)
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: showsLowConfidenceNudge)
        .sensoryFeedback(.selection, trigger: grams)
    }

    private func stepButton(systemImage: String, delta: Int) -> some View {
        Button {
            set(grams + delta)
        } label: {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.large))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: 52, height: 52)
                .background(ZanoGlass(Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        // Hold to keep counting — getting from 0 to 45 one tap at a time would be a chore.
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(delta > 0 ? Copy.fuel.mealPhoto.increaseAccessibilityLabel : Copy.fuel.mealPhoto.decreaseAccessibilityLabel)
    }

    private func set(_ value: Int) {
        let clamped = min(Self.maxGrams, max(0, value))
        guard clamped != grams else { return }
        grams = clamped
        hasAdjusted = true
    }

    // MARK: Logging

    private func log() {
        guard grams > 0, !isLogging else { return }
        isLogging = true
        errorMessage = nil
        let loggedGrams = grams
        let source: GoalLogSource = draft.image != nil ? Self.photoSource : .manual

        Task {
            do {
                let intent = LogProteinIntent(grams: Double(loggedGrams), source: source)
                _ = try await intent.perform()
            } catch {
                isLogging = false
                errorMessage = Copy.fuel.mealPhoto.logFailedMessage
                AccessibilityNotification.Announcement(Copy.fuel.mealPhoto.logFailedMessage).post()
                return
            }

            // Bookkeeping after a successful log. None of it can undo or block the log.
            if let hash = draft.prepared?.hash {
                await PhotoDedupe.recordAccepted(hash: hash)
            }
            saveMeal(grams: loggedGrams)
            if let estimate = draft.estimate {
                let mealID = estimate.mealID
                let items = estimate.items
                Task.detached(priority: .utility) {
                    try? await MealVisionClient.shared.confirm(mealID: mealID, items: items, totalProteinG: Double(loggedGrams))
                }
            }

            Analytics.shared.capture(
                event: "fuel_meal_photo_logged",
                properties: [
                    "grams": loggedGrams,
                    "had_photo": draft.image != nil,
                    "had_estimate": draft.estimate != nil,
                    "adjusted": hasAdjusted,
                    "note": draft.note.map { "\($0)" } ?? "none",
                ]
            )
            AccessibilityNotification.Announcement(Copy.fuel.mealPhoto.loggedAnnouncement(grams: loggedGrams)).post()
            isLogging = false
            onLogged(loggedGrams)
        }
    }

    /// Saves the confirmed meal as the user's food memory (spec 9.5 / 5.19). Only for photo or
    /// vision meals — a bare typed number is already covered by the goal event and would only add
    /// nameless rows to Quick Repeats. Items are kept only when the model named them; a manual
    /// meal with a photo stores `items: []`, which Quick Repeats skips by design.
    private func saveMeal(grams: Int) {
        guard draft.image != nil || draft.estimate != nil, let userID = users.first?.id else { return }
        let mealID = UUID()
        let localPath = draft.prepared.flatMap { MealPhotoStore.save(jpeg: $0.jpeg, id: mealID) }
        let meal = Meal(
            id: mealID,
            userID: userID,
            ts: .now,
            photoPath: localPath,
            items: items,
            proteinG: Double(grams),
            confirmed: true
        )
        modelContext.insert(meal)
        try? modelContext.save()
    }
}
