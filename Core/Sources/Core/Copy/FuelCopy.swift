// FuelCopy.swift
// Core / Copy
//
// `Copy.fuel` — every user-facing string `App/ZANO/Features/Fuel/FuelView.swift` calls, under the
// `Copy.<area>.<key>` umbrella this codebase actually uses (see `Copy.swift`'s header;
// `OnboardingCopy.swift`/`SunriseAlarmScreenCopy.swift` are the precedent this follows). This is a
// reconciliation, not new scope: `FuelView.swift`'s own "ASSUMED API" header comment already
// documents this exact key list, member for member (including which ones are "NEW" additions from
// its own barcode-scan and Kitchen Staples work) — this file adds the umbrella shape that view
// already calls rather than re-deriving it. Repo-wide sweep (2026-09-22): this namespace was
// referenced across ~90 call sites in `FuelView.swift` but never declared anywhere in
// `Core/Sources/Core/Copy`, which would have failed to compile.
//
// `Copy.common.delete`/`Copy.common.save` are added in `CommonCopy.swift` alongside this file (this
// same sweep) — `FuelView.swift`'s own header already flags both as "already assumed by
// LockSetupView"/"already assumed by SettingsView.swift", but neither had actually been declared.

import Foundation

extension Copy {
    public enum fuel {
        public static let screenTitle = "Fuel"
        public static let proteinLabel = "Protein"
        public static let waterLabel = "Water"

        public static let emptyGoalsTitle = "No fuel goals yet"
        public static let emptyGoalsMessage = "Add a protein or water goal to start logging here."
        /// The empty state's one action: opens the goals editor.
        public static let addGoalButton = "Add a goal"
        /// Empty-states pass 2026-09-24: the ways to log that this screen fills with once a goal
        /// exists, shown as a quiet preview under the empty rings.
        public static let emptyGoalsPreviewTitle = "Log it your way"
        public static let emptyGoalsPreviewQuickAdd = "One-tap amounts"
        public static let emptyGoalsPreviewBarcode = "Barcode scan"
        public static let emptyGoalsPreviewNFC = "NFC tap"

        public static let logCustomButtonLabel = "Log custom amount"
        public static func customAmountSheetTitle(goalLabel: String) -> String { "Log \(goalLabel)" }
        public static let amountFieldLabel = "Amount"

        // Units. "25 g", "500 mL": a space before the unit, and SI's capital L.
        public static let gramsUnit = "g"
        public static let millilitersUnit = "mL"
        public static func grams(_ grams: Int) -> String { "\(grams) g" }
        public static func milliliters(_ milliliters: Int) -> String { "\(milliliters) mL" }

        /// VoiceOver for a quick-add chip: "Log 25 g of protein" / "Log 500 mL of water".
        public static func quickAddProteinAccessibilityLabel(grams: Int) -> String {
            "Log \(Self.grams(grams)) of protein"
        }
        public static func quickAddWaterAccessibilityLabel(milliliters: Int) -> String {
            "Log \(Self.milliliters(milliliters)) of water"
        }
        /// VoiceOver value for a metric card: "72 of 150 g" (or "72 g" with no target yet).
        public static func metricAccessibilityValue(current: Int, target: Int?, unit: String) -> String {
            guard let target else { return "\(current) \(unit)" }
            return "\(current) of \(target) \(unit)"
        }

        // Undo toast after a quick-add.
        public static func undoToastProteinMessage(grams: Int) -> String { "Logged \(Self.grams(grams)) of protein" }
        public static func undoToastWaterMessage(milliliters: Int) -> String { "Logged \(Self.milliliters(milliliters)) of water" }
        // (The Undo button itself is `Copy.today.undoTitle`: Fuel reuses Today's `UndoToast`.)
        public static let undoFailedTitle = "Couldn't undo that"
        public static let undoFailedMessage = "It's still logged. You can try again from the goal's history."

        // Protein gap planner (spec §5.20)
        public static let gapPlannerTitle = "Protein gap planner"
        /// Additive framing (spec §24 disordered-eating-safe copy): grams still to reach, never a
        /// deficit word like "behind".
        public static func gapPlannerSubtitle(gapGrams: Int) -> String { "\(grams(gapGrams)) to go today" }
        public static let gapOptionStapleTitle = "From your kitchen"
        public static let gapOptionRestaurantTitle = "Nearby restaurant"
        public static let gapOptionRestaurantDetail = "Find something high-protein close by"
        public static let gapOptionSnackTitle = "Quick snack"

        // Quick repeat (spec §5.19)
        public static let quickRepeatSectionTitle = "Quick repeat"
        public static let quickRepeatEmptyMealLabel = "your usual meal"
        public static func quickRepeatPrompt(label: String, grams: Int) -> String {
            "Your usual \(label) (\(Self.grams(grams)))?"
        }

        public static let logFailedTitle = "Couldn't log that"
        public static let logFailedMessage = "Nothing was logged. Try again in a moment."

        // Barcode scan (VisionKit DataScannerViewController)
        public static let barcodeScanButtonLabel = "Scan barcode"
        public static let barcodeScanTitle = "Scan barcode"
        public static let barcodeScanInstructions = "Point your camera at a barcode"
        public static let barcodeManualEntryTitle = "Enter barcode manually"
        public static let barcodeManualEntryFieldLabel = "Barcode number"
        public static let barcodeManualEntrySubmitLabel = "Look up"
        public static let barcodeUnavailableMessage = "Barcode scanning isn't available on this device."
        public static let barcodeUnknownProductLabel = "Scanned item"
        public static func barcodeResultProteinLabel(grams: Int) -> String { "\(Self.grams(grams)) protein per serving" }
        public static func barcodeServingPromptTitle(productName: String) -> String {
            "How much \(productName) are you having?"
        }
        public static let barcodeServingGramsFieldLabel = "Grams"
        public static func barcodeServingProteinPreview(grams: Int) -> String { "≈ \(Self.grams(grams)) protein" }
        public static let barcodeLogButtonLabel = "Log this"
        public static let barcodeRetryButtonLabel = "Try again"
        public static let barcodeErrorInvalidBarcode = "That doesn't look like a valid barcode."
        public static let barcodeErrorProductNotFound =
            "Couldn't find that product. Try scanning again or log the protein by hand."
        public static let barcodeErrorNoNutritionData = "No protein data for this product. Log it by hand."
        public static let barcodeErrorTransport = "Couldn't reach the product database — try again."

        // Kitchen Staples (spec §5.20, §10)
        public static let kitchenStaplesSectionTitle = "Kitchen staples"
        /// Empty-states pass 2026-09-24: the headline of the empty staples tile (the message below
        /// it says why).
        public static let kitchenStaplesEmptyTitle = "Save your first staple"
        public static let kitchenStaplesEmptyMessage = "Save a few high-protein foods you eat often so the gap planner can suggest them first."
        public static let kitchenStapleAddButtonLabel = "Add"
        public static let kitchenStapleAddSheetTitle = "Add a kitchen staple"
        public static let kitchenStapleNameFieldLabel = "Name"
        public static let kitchenStapleProteinFieldLabel = "Protein (g)"
        public static let kitchenStapleSaveFailedTitle = "Couldn't save that staple"
        public static let kitchenStapleSaveFailedMessage = "Nothing changed. Try again in a moment."
        /// VoiceOver for a staple row: "Greek yogurt, 15 g protein".
        public static func kitchenStapleAccessibilityLabel(name: String, grams: Int) -> String {
            "\(name), \(Self.grams(grams)) protein"
        }
        /// The staple row's "…" menu, named for the staple it acts on.
        public static func kitchenStapleMoreOptionsLabel(name: String) -> String { "More options for \(name)" }
    }
}

// MARK: - Meal photo (spec 9.5 meal photo -> protein; spec 3 meal prep row)
//
// Added 2026-09-25 for `App/ZANO/Features/Fuel/MealPhoto/`. Additive framing only (spec 24):
// every line is about what to add or confirm — nothing about eating less or a meal being "too
// much". Duplicate-photo copy follows spec 9.8's "never accuse — just don't count".

extension Copy.fuel {
    public enum mealPhoto {
        // Entry point (Fuel's protein card)
        public static let entryButtonLabel = "Log a meal photo"

        // Capture
        public static let captureTitle = "Meal photo"
        public static let captureHeadline = "Snap your plate"
        public static let captureHint = "Fit the whole plate in the frame"
        public static let shutterAccessibilityLabel = "Take photo"
        public static let takePhotoButton = "Take photo"
        public static let chooseFromLibraryButton = "Choose from library"
        public static let enterManuallyButton = "Enter protein by hand"
        public static let cameraUnavailableMessage =
            "The camera isn't available here. Pick a photo from your library or enter the protein by hand."
        public static let cameraDeniedMessage =
            "Camera access is off. Turn it on in Settings, or pick a photo from your library."
        public static let openSettingsButton = "Open Settings"
        public static let framingAccessibilityLabel = "Camera viewfinder"
        public static let photoLoadFailedMessage = "Couldn't open that photo. Try another one."

        // Checking / analyzing
        public static let checkingPhoto = "Checking photo…"
        public static let analyzing = "Estimating protein…"

        // Duplicate photo (spec 9.8: transparent, never accusing)
        public static let duplicateTitle = "This photo's already counted"
        public static let duplicateMessage =
            "It was logged a little while ago. Snap a fresh photo of this meal, or enter it by hand."
        public static let retakeButton = "Take a new photo"

        // Confirm
        public static let confirmTitle = "Confirm protein"
        public static let photoAccessibilityLabel = "Your meal photo"
        public static let detectedItemsHeader = "What we spotted"
        public static func itemAccessibilityLabel(name: String, grams: Int) -> String {
            "\(name), about \(Copy.fuel.grams(grams)) of protein"
        }
        public static let estimateCaption = "Estimated protein"
        public static let manualCaption = "Protein in this meal"
        public static let lowConfidenceNudge = "Rough estimate — adjust it if it looks off."
        public static let noFoodFoundNote = "Couldn't make out the food clearly. Add the protein yourself."
        public static let notConfiguredNote = "Photo estimates are coming soon. Add the protein yourself for now."
        public static let offlineNote = "You're offline, so no estimate this time. Add the protein yourself."
        public static let estimateFailedNote = "Couldn't get an estimate right now. Add the protein yourself."
        public static let stepperAccessibilityLabel = "Protein"
        public static let decreaseAccessibilityLabel = "Less protein"
        public static let increaseAccessibilityLabel = "More protein"
        public static func quickSetAccessibilityLabel(grams: Int) -> String { "Set to \(Copy.fuel.grams(grams))" }
        public static func logButton(grams: Int) -> String { "Log \(Copy.fuel.grams(grams))" }
        public static let logButtonEmpty = "Add protein to log"
        public static func loggedAnnouncement(grams: Int) -> String { "Logged \(Copy.fuel.grams(grams)) of protein" }
        public static let logFailedMessage = "Couldn't log that. Nothing changed — try again."

        // Meal prep (weekly)
        public static let mealPrepTitle = "Meal prep"
        public static let mealPrepHeadline = "Show off the prep"
        public static let mealPrepHint = "Get all your containers in one shot"
        public static let mealPrepChecking = "Checking your containers…"
        public static let mealPrepHonorExplainer =
            "Photo checks for meal prep aren't live yet, so this one counts on your honor."
        public static let mealPrepLogButton = "Log meal prep"
        public static let mealPrepConfirmedTitle = "Meal prep logged"
        public static let mealPrepConfirmedMessage = "This week's prep is done. Future you says thanks."
        public static let mealPrepHonorTitle = "Logged on your honor"
        public static let mealPrepHonorMessage = "This week's prep is in. Photo checks are coming soon."
        public static let mealPrepRejectedTitle = "Couldn't count that one yet"
        public static let mealPrepRejectedMessage =
            "We need to see a few containers in one shot. Try another angle."
        public static let mealPrepAlreadyDoneTitle = "Already logged this week"
        public static func mealPrepAlreadyDoneMessage(nextDay: String) -> String {
            "Your next meal prep counts from \(nextDay)."
        }
        public static let mealPrepFailedMessage = "Couldn't log meal prep. Try again."
        public static let mealPrepNotFoundMessage = "This meal prep goal isn't set up anymore."
        public static let doneButton = "Done"
    }
}
