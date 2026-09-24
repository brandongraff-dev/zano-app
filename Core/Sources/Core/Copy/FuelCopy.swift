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
