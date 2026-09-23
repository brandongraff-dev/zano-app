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

        public static let logCustomButtonLabel = "Log custom amount"
        public static func customAmountSheetTitle(goalLabel: String) -> String { "Log \(goalLabel)" }
        public static let amountFieldLabel = "Amount"

        // Protein Gap Planner (spec §5.20)
        public static let gapPlannerTitle = "Protein Gap Planner"
        public static func gapPlannerSubtitle(gapGrams: Int) -> String { "You're \(gapGrams)g behind today" }
        public static let gapOptionStapleTitle = "From your kitchen"
        public static let gapOptionRestaurantTitle = "Nearby restaurant"
        public static let gapOptionRestaurantDetail = "Find something high-protein close by"
        public static let gapOptionSnackTitle = "Quick snack"

        // Quick Repeat (spec §5.19)
        public static let quickRepeatSectionTitle = "Quick Repeat"
        public static let quickRepeatEmptyMealLabel = "your usual meal"
        public static func quickRepeatPrompt(label: String, grams: Int) -> String {
            "Your usual \(label) (\(grams)g)?"
        }

        public static let logFailedTitle = "Couldn't log that"

        // Barcode scan (VisionKit DataScannerViewController)
        public static let barcodeScanButtonLabel = "Scan barcode"
        public static let barcodeScanTitle = "Scan Barcode"
        public static let barcodeScanInstructions = "Point your camera at a barcode"
        public static let barcodeManualEntryTitle = "Enter barcode manually"
        public static let barcodeManualEntryFieldLabel = "Barcode number"
        public static let barcodeManualEntrySubmitLabel = "Look up"
        public static let barcodeUnavailableMessage = "Barcode scanning isn't available on this device."
        public static let barcodeUnknownProductLabel = "Scanned item"
        public static func barcodeResultProteinLabel(grams: Int) -> String { "\(grams)g protein per serving" }
        public static func barcodeServingPromptTitle(productName: String) -> String {
            "How much \(productName) are you having?"
        }
        public static let barcodeServingGramsFieldLabel = "Grams"
        public static func barcodeServingProteinPreview(grams: Int) -> String { "≈ \(grams)g protein" }
        public static let barcodeLogButtonLabel = "Log this"
        public static let barcodeRetryButtonLabel = "Try again"
        public static let barcodeErrorInvalidBarcode = "That doesn't look like a valid barcode."
        public static let barcodeErrorProductNotFound = "Couldn't find that product."
        public static let barcodeErrorNoNutritionData = "That product has no protein data on file."
        public static let barcodeErrorTransport = "Couldn't reach the product database — try again."

        // Kitchen Staples (spec §5.20, §10)
        public static let kitchenStaplesSectionTitle = "Kitchen Staples"
        public static let kitchenStaplesEmptyMessage = "Save a few go-to high-protein foods so the gap planner can suggest them first."
        public static let kitchenStapleAddButtonLabel = "Add"
        public static let kitchenStapleAddSheetTitle = "Add Kitchen Staple"
        public static let kitchenStapleNameFieldLabel = "Name"
        public static let kitchenStapleProteinFieldLabel = "Protein (g)"
        public static let kitchenStapleSaveFailedTitle = "Couldn't save that staple"
    }
}
