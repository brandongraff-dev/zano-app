// FuelView.swift
// App / Features / Fuel
//
// Owned by: this session's task (orchestrator batch, 2026-09-22). Do not edit from another
// session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §15 (Design System & UI Direction — "Screens: ... Fuel ..."), §16 image-gen intent
// (protein/water rings, quick actions), §3 (Goal Catalog & Verification — Protein/Water are Tier B:
// "NFC tap ... meal photo ... barcode scan, quick-repeat of recent meals" / "NFC tap on bottle ...,
// widget button"), §5.19 (Quick Repeats & Food Memory — "Your usual chicken bowl (48g)?"), §5.20
// (Protein Gap Planner — "At ~4 PM, if the user is behind: three concrete options ranked by
// proximity and effort — something in their saved kitchen staples, a nearby restaurant item with a
// deep link, or a quick snack."), §10 (Food, Protein & Ordering Integrations — "Kitchen staples:
// user saves 10-20 staples once; the gap planner uses them first." / "Barcode -> product: Open Food
// Facts"), §9.1 (Adaptive Goal Engine — today's actual bar comes from `AdaptiveGoalEngine.dailyPlan`,
// not the goal's static `targetValue`), §14 (App Intents Catalog — `LogProteinIntent(grams, source)`,
// `LogWaterIntent(ml, source)`, `QuickRepeatMealIntent(mealId)`), §23 (Instrument from day one).
//
// Reads `Goal`/`GoalEvent`/`User` directly via `@Query` (all frozen Session 1 models — see
// `Core/Sources/Core/Models`, read in full before writing this file) exactly the way
// `LockSetupView.swift` reads `LockSet` directly: cheap, declarative, display-only. `Meal` is used
// only as a type here (the quick-repeat suggestion's payload) — this file no longer `@Query`s
// `Meal` history itself, since `QuickRepeatSuggester` now owns mining it (see SYSTEM CONTRACTS
// below); the previous version's own `confirmedMeals` `@Query` is removed as now-dead code. Every
// *write* that has a real App Intent (logging protein/water, replaying a quick-repeat meal) goes
// through the Intents catalog (CLAUDE.md: "Every user action is an App Intent... never duplicate
// the same logic in two places"). `KitchenStaple` CRUD has no dedicated manager/intent (confirmed:
// nothing under `Core/Sources/Core/Intents` references it) — this file writes it directly through
// `ModelContext`, the exact same choice `App/ZANO/Features/Settings/SettingsView.swift` already
// makes for `Gym` for the identical reason ("no dedicated manager in this batch's SYSTEM CONTRACTS").
//
// SYSTEM CONTRACTS actually used here (this task's own read of each real file, in full, before
// writing this one — not memory):
//   - `AdaptiveGoalEngine.dailyPlan(for:on:)` resolves today's actual protein/water bar; the static
//     `Goal.targetValue` is only a fallback for the (expected, early-app-life) case where no
//     `DailyPlan` has been generated yet. Unchanged from this file's previous version.
//   - `QuickRepeatSuggester.shared.suggestedQuickRepeat(at:)` (`Core/Sources/Core/Verification`,
//     this batch's Phase A) replaces this file's own previous, independently-written meal-grouping
//     heuristic — that file's own header explicitly flagged the duplication and asked "whichever
//     session next owns FuelView.swift" to point at it instead; that session is this one. Its
//     contract is singular ("is *now* one of the times the user typically eats one of their
//     recurring meals, and if so, which meal"), matching spec §5.19's own "Your usual chicken bowl
//     (48g)?" singular framing — so the UI below is a single one-tap prompt, not the previous
//     horizontal multi-chip list (which is also *removed* here since it duplicated real, on-device
//     time-of-day pattern mining that this suggester already does properly, circular-mean clustering
//     included).
//   - `ProteinGapPlanner.shared.rankedOptions(for:verifiedProteinEventsToday:on:)` (`Core/Sources/
//     Core/Verification`, also this batch's Phase A) replaces this file's own previous ad hoc Tier-1
//     "kitchen staple" heuristic, which that file's own header flagged as a real, if soft, bug: it
//     was actually built from recent `Meal` history (because `KitchenStaple` didn't exist yet from
//     this file's point of view when it was first written), not `KitchenStaple` rows at all — so a
//     user who saved Kitchen Staples never saw them in the gap planner. `ProteinGapPlanner`'s own
//     Tier 1 (kitchen staples) is real and used here. Its Tier 2 (restaurant) and Tier 3 (quick
//     snack) are deliberate, clearly-documented empty stubs pending spec §28's unresolved vendor
//     question — `ProteinGapPlanner.swift`'s own header explicitly says a future session can
//     "promote `FuelView.FuelReferenceData.quickSnacks` into a shared Core reference list" but does
//     NOT say this file's already-shipped, no-vendor-needed restaurant deep link (Apple Maps search)
//     and quick-snack reference list should be deleted while that's still unresolved — removing them
//     would regress the gap planner to showing nothing at all for any user who hasn't saved a
//     staple, which spec §5.20 ("three concrete options") doesn't intend. So: real `KitchenStaple`
//     tier 1 comes from `ProteinGapPlanner`; tiers 2/3 stay locally sourced here (unchanged data,
//     now expressed as `Core.ProteinGapOption` values so both sources share one ranked, `Identifiable`
//     list) until a future session takes path (1) or (2) from that file's own header.
//   - `BarcodeProteinLookup.shared.lookupProtein(barcode:)` (`Core/Sources/Core/Verification`, same
//     Phase A batch) is the barcode-scan entry point's data layer. Its own header is explicit that
//     it "does not scan anything itself... a barcode-scanning UI is a different, not-yet-built
//     caller's job" — this file is that caller. No prior scanner UI exists anywhere in this repo
//     (checked before writing this), so `BarcodeScanSheet`/`DataScannerRepresentable` below are new,
//     file-scoped VisionKit wrapper code, not a reuse of an existing component.
//   - `KitchenStaple` (`Core/Sources/Core/Models`, same Phase A batch) backs the new Kitchen Staples
//     list/add UI. *** INTEGRATION GAP, not fixed here (out of this task's owned file list; flagged
//     identically by `KitchenStaple.swift`'s and `ProteinGapPlanner.swift`'s own headers, and by
//     `Monetization/GearOffersEngine.swift`'s) *** — `Store/ModelContainer+AppGroup.swift`'s
//     `appGroupModelTypes` does not yet list `KitchenStaple.self`, so a fetch/insert against the real
//     App Group container silently sees/persists nothing today. Mitigation chosen here specifically
//     *because* of that gap: this file reads/writes `KitchenStaple` through a plain, caller-owned
//     `ModelContext` fetch/insert/delete (via `@Environment(\.modelContext)`, `try?`-guarded,
//     matching `ProteinGapPlanner.kitchenStapleOption(gapGrams:userID:)`'s own identical
//     try/catch-to-empty precedent) rather than `@Query`, which cannot degrade the same way if the
//     container's `Schema` doesn't recognize the type — flagged in this task's `knownIssues` as
//     unverified without a compiler which failure mode (thrown/caught vs. a hard crash) SwiftData
//     actually produces for an unregistered `@Model` type, and as a functional blocker (Kitchen
//     Staples will add/list nothing against the real store) until that array is updated.
//
// ASSUMED API — `LogProteinIntent` / `LogWaterIntent` / `QuickRepeatMealIntent` (`Core/Sources/
// Core/Intents`) are on disk now (this task re-read all three in full — not guessed): the exact
// property-setting shape this file already used is confirmed correct — `var intent =
// LogProteinIntent(); intent.grams = Double; intent.source = GoalLogSource; try await
// intent.perform()` (`LogProteinIntent.grams` is `Double`, not `Int` — re-verified against the real
// file) — and `QuickRepeatMealIntent`'s shape (`var intent = QuickRepeatMealIntent(); intent.meal =
// MealEntity(id:label:); try await intent.perform()`) matches exactly what this file already had.
// `GoalLogSource` (`IntentSupport.swift`) has five real cases — `.nfc/.widget/.manual/.siri/
// .barcode` — confirmed directly; this file passes `.manual` for every direct-tap log (rings,
// kitchen staples, quick snack) and `.barcode` only for a barcode-scan-derived log, matching
// `GoalEventSource.barcode`'s own already-real case (`Models/GoalEvent.swift`, confirmed directly).
//
// ASSUMED API — `Copy.fuel.*` / `Copy.common.*` (`Core/Sources/Core/Copy`, not owned by this
// session — still not on disk as of this task's own check of `Core/Sources/Core/Copy`). Follows the
// exact precedent `App/ZANO/Features/LockSetup/LockSetupView.swift` already set: reference
// `Copy.<feature>.*` by name (the `Copy.<area>` umbrella pattern `Copy.swift`/`OnboardingCopy.swift`
// establish — never a flat standalone enum) and list every assumed member here. Members already
// assumed by this file before this task are unchanged; new members this task adds are marked NEW.
//
//   Copy.fuel.screenTitle: String
//   Copy.fuel.proteinLabel: String                             // "Protein"
//   Copy.fuel.waterLabel: String                                // "Water"
//   Copy.fuel.emptyGoalsTitle: String
//   Copy.fuel.emptyGoalsMessage: String
//   Copy.fuel.logCustomButtonLabel: String                      // "Log custom amount"
//   Copy.fuel.customAmountSheetTitle(goalLabel: String) -> String
//   Copy.fuel.amountFieldLabel: String                          // "Amount"
//   Copy.fuel.gapPlannerTitle: String                           // "Protein Gap Planner"
//   Copy.fuel.gapPlannerSubtitle(gapGrams: Int) -> String        // "You're 42g behind today"
//   Copy.fuel.gapOptionStapleTitle: String                      // "From your kitchen"
//   Copy.fuel.gapOptionRestaurantTitle: String                  // "Nearby restaurant"
//   Copy.fuel.gapOptionRestaurantDetail: String                 // "Find something high-protein close by"
//   Copy.fuel.gapOptionSnackTitle: String                       // "Quick snack"
//   Copy.fuel.quickRepeatSectionTitle: String                   // "Quick Repeat"
//   Copy.fuel.quickRepeatEmptyMealLabel: String                 // fallback meal name
//   Copy.fuel.logFailedTitle: String
//   Copy.fuel.quickRepeatPrompt(label: String, grams: Int) -> String          // NEW — "Your usual \(label) (\(grams)g)?"
//   Copy.fuel.barcodeScanButtonLabel: String                                  // NEW — "Scan barcode"
//   Copy.fuel.barcodeScanTitle: String                                       // NEW — scan sheet nav title
//   Copy.fuel.barcodeScanInstructions: String                                // NEW — "Point your camera at a barcode"
//   Copy.fuel.barcodeManualEntryTitle: String                                // NEW — "Enter barcode manually"
//   Copy.fuel.barcodeManualEntryFieldLabel: String                           // NEW — "Barcode number"
//   Copy.fuel.barcodeManualEntrySubmitLabel: String                          // NEW — "Look up"
//   Copy.fuel.barcodeUnavailableMessage: String                              // NEW — device/Simulator can't scan
//   Copy.fuel.barcodeUnknownProductLabel: String                             // NEW — "Scanned item"
//   Copy.fuel.barcodeResultProteinLabel(grams: Int) -> String                // NEW — "12g protein per serving"
//   Copy.fuel.barcodeServingPromptTitle(productName: String) -> String       // NEW — "How much \(productName) are you having?"
//   Copy.fuel.barcodeServingGramsFieldLabel: String                          // NEW — "Grams"
//   Copy.fuel.barcodeServingProteinPreview(grams: Int) -> String             // NEW — "≈ 12g protein"
//   Copy.fuel.barcodeLogButtonLabel: String                                  // NEW — "Log this"
//   Copy.fuel.barcodeRetryButtonLabel: String                                // NEW — "Try again"
//   Copy.fuel.barcodeErrorInvalidBarcode: String                             // NEW
//   Copy.fuel.barcodeErrorProductNotFound: String                            // NEW
//   Copy.fuel.barcodeErrorNoNutritionData: String                            // NEW
//   Copy.fuel.barcodeErrorTransport: String                                  // NEW — generic network/decoding failure
//   Copy.fuel.kitchenStaplesSectionTitle: String                             // NEW — "Kitchen Staples"
//   Copy.fuel.kitchenStaplesEmptyMessage: String                             // NEW
//   Copy.fuel.kitchenStapleAddButtonLabel: String                            // NEW — "Add"
//   Copy.fuel.kitchenStapleAddSheetTitle: String                             // NEW
//   Copy.fuel.kitchenStapleNameFieldLabel: String                            // NEW — "Name"
//   Copy.fuel.kitchenStapleProteinFieldLabel: String                        // NEW — "Protein (g)"
//   Copy.fuel.kitchenStapleSaveFailedTitle: String                           // NEW
//   Copy.common.ok / Copy.common.cancel / Copy.common.save: String   // already assumed by LockSetupView
//   Copy.common.delete: String                                       // already assumed by SettingsView.swift
//
// Quick-snack suggestions (name + grams) and gap-option SF Symbol icons are kept as small,
// file-scoped static reference data instead of routed through `Copy`, following the same
// reasoning `Core/Sources/Core/Verification/NFCTagSetupInstructions.swift` already gives for its
// own plain-text steps: this is a fixed, non-voiced reference list (not persona/coach-voice
// motivational copy — spec §5.13's four voices never apply to "2 eggs, 12g"), so centralizing it
// in `Copy` would add an indirection with no actual voice-variance to justify it. Unit-suffix
// literals ("g", "g protein") follow this same file's own pre-existing `quickAddRow`/`ringItems`
// precedent of inline unit strings, not `Copy` members. If a future session wants the quick-snack
// list swapped for a real nutrition database, `ProteinGapPlanner.swift`'s header already names this
// as the place to do it.
//
// `import UIKit` is added below (previously not needed in this file) specifically for
// `UIViewControllerRepresentable`/`DataScannerViewController` — CLAUDE.md "No UIKit unless an API
// requires it": VisionKit's barcode-scanning UI is UIKit-only, no SwiftUI-native equivalent exists.
//
// ASSUMED API — VisionKit's `DataScannerViewController` (`BarcodeScanSheet`/
// `DataScannerRepresentable` below). No Mac/compiler exists to build-check this file (CLAUDE.md
// environment status), and this framework's surface is exactly the kind CLAUDE.md working rule 5
// asks to verify rather than guess from training memory alone — this task did that: it queried
// Apple's real documentation page and several independent, current tutorials/sample repos during
// this session (2026-09-22) and cross-checked the initializer's parameter list (`recognizedDataTypes:
// qualityLevel:recognizesMultipleItems:isHighFrameRateTrackingEnabled:isPinchToZoomEnabled:
// isGuidanceEnabled:isHighlightingEnabled:`), the delegate method signatures (`dataScanner(_:didAdd:
// allItems:)`), `RecognizedItem.barcode(let barcode)`/`barcode.payloadStringValue`, and the static
// `isSupported`/`isAvailable` gates against real, current sources rather than presenting this as
// certain from memory alone. Still explicitly NOT verified (flagged, not guessed past):
//   - Whether `DataScannerViewControllerDelegate`'s requirements carry a `@MainActor` annotation in
//     the current SDK under Swift 6 strict concurrency, or are plain `nonisolated`. Worked around,
//     not resolved: `Coordinator`'s delegate method here only extracts a `String` and calls a plain
//     closure — it never touches actor-isolated state directly — and the closure itself explicitly
//     re-enters `@MainActor` (`Task { @MainActor in ... }`) before mutating any `@State`, so this
//     compiles correctly either way that annotation turns out to be. If a real build disagrees, the
//     fix is local to `DataScannerRepresentable.Coordinator`, not this file's control flow.
//   - Whether every `DataScannerViewControllerDelegate` requirement has a default (no-op) protocol
//     extension implementation, letting this file implement only `didAdd`. Every current sample this
//     task found does exactly that (only `didAdd` and/or `didTapOn`), which is strong but not
//     compiler-verified evidence.
//   - The project's deployment target is iOS 17 (`project.yml`), comfortably above
//     `DataScannerViewController`'s iOS 16 minimum, so no `if #available` gate is needed for
//     compilation — only the runtime `isSupported`/`isAvailable` device/Simulator gate, which this
//     file does check.
//   - `NSCameraUsageDescription` is already declared in `project.yml` (added for meal-photo capture)
//     and is reused as-is for barcode scanning rather than edited — `project.yml` is outside this
//     task's owned file list; its current copy ("...to estimate protein from meal photos") doesn't
//     mention barcode scanning, which is a minor, non-blocking copy gap for a future session owning
//     that file to tidy up, not a functional blocker (iOS doesn't require the string to describe
//     every camera use).

import SwiftUI
import SwiftData
import CoreLocation
import UIKit
import VisionKit
import Vision
import Core

struct FuelView: View {
    @Query(filter: #Predicate<Goal> { $0.active }, sort: \Goal.createdAt)
    private var activeGoals: [Goal]

    @Query private var verifiedEventsToday: [GoalEvent]

    /// Only used to resolve the current user's id for `KitchenStaple` CRUD (this file's own only
    /// direct-`ModelContext`-write model) — same `@Query private var users: [User]` +
    /// `currentUser: User? { users.first }` precedent `SettingsView.swift` already uses for the same
    /// need. Unused for anything Intent-driven (every intent resolves its own current user
    /// server-side via `IntentSupport.currentUser(in:)`).
    @Query private var users: [User]

    @Environment(\.openURL) private var openURL
    /// Only for `KitchenStaple` CRUD — see this file's header "INTEGRATION GAP" note for why this
    /// goes through a plain, `try?`-guarded `ModelContext` fetch/insert/delete rather than `@Query`.
    @Environment(\.modelContext) private var modelContext

    @State private var proteinPlan: DailyPlan?
    @State private var waterPlan: DailyPlan?
    @State private var activeSheet: FuelSheet?
    @State private var errorAlert: FuelErrorAlert?
    @State private var isLogging = false

    @State private var quickRepeatMeal: Meal?
    @State private var gapOptions: [ProteinGapOption] = []
    @State private var kitchenStaples: [KitchenStaple] = []
    @State private var isBarcodeSheetPresented = false
    @State private var isKitchenStapleAddSheetPresented = false
    @State private var pendingStapleDeletion: KitchenStaple?

    /// Custom initializer so `verifiedEventsToday`'s predicate can capture "the start of today" —
    /// `#Predicate` needs that as a plain `Date` value, not a computed instance property (same
    /// pattern `Core/Sources/Core/LockEngine/LockEngineManager.swift`'s `isGoalVerified` uses: only
    /// `Bool`/`Date` fields in the predicate itself; the goal-relationship filter happens afterward
    /// in plain Swift, since this codebase has no Mac/compiler available to verify how SwiftData's
    /// `#Predicate` macro handles optional-relationship chaining on this SDK version).
    init() {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        _verifiedEventsToday = Query(
            filter: #Predicate<GoalEvent> { $0.verified == true && $0.ts >= startOfDay },
            sort: [SortDescriptor(\.ts)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if proteinGoal == nil && waterGoal == nil {
                    emptyState
                } else {
                    ringsSection
                    if isGapPlannerEligible && !gapOptions.isEmpty {
                        gapPlannerSection
                    }
                    if let quickRepeatMeal {
                        quickRepeatSection(for: quickRepeatMeal)
                    }
                    if proteinGoal != nil {
                        kitchenStaplesSection
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.fuel.screenTitle)
        .task {
            Analytics.shared.capture(
                event: "fuel_viewed",
                properties: ["has_protein_goal": proteinGoal != nil, "has_water_goal": waterGoal != nil]
            )
            await refreshFuelState()
        }
        .refreshable { await refreshFuelState() }
        .sheet(item: $activeSheet) { sheet in
            ManualAmountSheet(
                goalType: sheet.goalType,
                fieldLabel: Copy.fuel.amountFieldLabel,
                titleLabel: Copy.fuel.customAmountSheetTitle(goalLabel: sheet.goalType == .protein ? Copy.fuel.proteinLabel : Copy.fuel.waterLabel),
                onSubmit: { amount in
                    activeSheet = nil
                    Task { await log(goalType: sheet.goalType, amount: amount, source: .manual) }
                },
                onCancel: { activeSheet = nil }
            )
        }
        .sheet(isPresented: $isBarcodeSheetPresented) {
            BarcodeScanSheet(
                onLogged: { grams, barcode in
                    isBarcodeSheetPresented = false
                    Analytics.shared.capture(
                        event: "fuel_barcode_scan_logged",
                        properties: ["barcode": barcode, "protein_grams": grams]
                    )
                    Task { await log(goalType: .protein, amount: grams, source: .barcode) }
                },
                onDismiss: { isBarcodeSheetPresented = false }
            )
        }
        .sheet(isPresented: $isKitchenStapleAddSheetPresented) {
            KitchenStapleAddSheet(
                onSave: { name, proteinGrams in
                    isKitchenStapleAddSheetPresented = false
                    addKitchenStaple(name: name, proteinGrams: proteinGrams)
                },
                onCancel: { isKitchenStapleAddSheetPresented = false }
            )
        }
        .confirmationDialog(
            Copy.common.delete,
            isPresented: Binding(
                get: { pendingStapleDeletion != nil },
                set: { isPresented in if !isPresented { pendingStapleDeletion = nil } }
            ),
            presenting: pendingStapleDeletion
        ) { staple in
            Button(Copy.common.delete, role: .destructive) { deleteKitchenStaple(staple) }
            Button(Copy.common.cancel, role: .cancel) { pendingStapleDeletion = nil }
        } message: { staple in
            Text(staple.name)
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Copy.fuel.emptyGoalsTitle, systemImage: "fork.knife.circle")
        } description: {
            Text(Copy.fuel.emptyGoalsMessage)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - Rings

    private var ringsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            RingCluster(items: ringItems, ringSize: .large, layout: .row)

            if proteinGoal != nil {
                quickAddRow(
                    label: Copy.fuel.proteinLabel,
                    color: Theme.Colors.Ring.protein,
                    presets: FuelReferenceData.proteinPresetsGrams,
                    unitSuffix: "g",
                    onPreset: { grams in Task { await log(goalType: .protein, amount: Double(grams), source: .manual) } },
                    onCustom: { activeSheet = FuelSheet(goalType: .protein) },
                    trailingChip: (
                        title: Copy.fuel.barcodeScanButtonLabel,
                        systemImage: "barcode.viewfinder",
                        action: {
                            Analytics.shared.capture(event: "fuel_barcode_scan_opened")
                            isBarcodeSheetPresented = true
                        }
                    )
                )
            }
            if waterGoal != nil {
                quickAddRow(
                    label: Copy.fuel.waterLabel,
                    color: Theme.Colors.Ring.water,
                    presets: FuelReferenceData.waterPresetsMl,
                    unitSuffix: "ml",
                    onPreset: { ml in Task { await log(goalType: .water, amount: Double(ml), source: .manual) } },
                    onCustom: { activeSheet = FuelSheet(goalType: .water) }
                )
            }
        }
    }

    private var ringItems: [RingClusterItem] {
        var items: [RingClusterItem] = []
        if let proteinGoal {
            items.append(
                RingClusterItem(
                    id: proteinGoal.id,
                    title: Copy.fuel.proteinLabel,
                    progress: safeProgress(current: proteinToday, target: proteinTarget),
                    color: Theme.Colors.Ring.protein,
                    valueText: "\(Int(proteinToday))/\(Int(proteinTarget))g",
                    centerIcon: "fork.knife"
                )
            )
        }
        if let waterGoal {
            items.append(
                RingClusterItem(
                    id: waterGoal.id,
                    title: Copy.fuel.waterLabel,
                    progress: safeProgress(current: waterToday, target: waterTarget),
                    color: Theme.Colors.Ring.water,
                    valueText: "\(Int(waterToday))/\(Int(waterTarget))ml",
                    centerIcon: "drop.fill"
                )
            )
        }
        return items
    }

    private func quickAddRow(
        label: String,
        color: Color,
        presets: [Int],
        unitSuffix: String,
        onPreset: @escaping (Int) -> Void,
        onCustom: @escaping () -> Void,
        trailingChip: (title: String, systemImage: String, action: () -> Void)? = nil
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(presets, id: \.self) { preset in
                    FuelQuickAddChip(title: "+\(preset)\(unitSuffix)", color: color) {
                        onPreset(preset)
                    }
                }
                FuelQuickAddChip(title: Copy.fuel.logCustomButtonLabel, color: Theme.Colors.muted, systemImage: "plus") {
                    onCustom()
                }
                if let trailingChip {
                    FuelQuickAddChip(title: trailingChip.title, color: Theme.Colors.muted, systemImage: trailingChip.systemImage) {
                        trailingChip.action()
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xxs)
        }
        .disabled(isLogging)
    }

    // MARK: - Gap Planner (spec §5.20, via `ProteinGapPlanner` for Tier 1)

    private var isGapPlannerEligible: Bool {
        guard proteinGoal != nil else { return false }
        return ProteinGapPlanner.isEligible(gapGrams: Double(proteinGapGrams))
    }

    private var gapPlannerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.fuel.gapPlannerTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(Copy.fuel.gapPlannerSubtitle(gapGrams: proteinGapGrams))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(gapOptions.enumerated()), id: \.element.id) { index, option in
                    GoalRow(
                        title: gapOptionTitle(for: option.tier),
                        detail: gapOptionDetail(for: option, rank: index + 1),
                        icon: gapOptionIcon(for: option.tier),
                        color: Theme.Colors.Ring.protein,
                        status: .pending,
                        action: { Task { await performGapOption(option) } }
                    )
                }
            }
        }
        .disabled(isLogging)
    }

    private func gapOptionTitle(for tier: ProteinGapTier) -> String {
        switch tier {
        case .kitchenStaple: Copy.fuel.gapOptionStapleTitle
        case .restaurant: Copy.fuel.gapOptionRestaurantTitle
        case .quickSnack: Copy.fuel.gapOptionSnackTitle
        }
    }

    private func gapOptionIcon(for tier: ProteinGapTier) -> String {
        switch tier {
        case .kitchenStaple: "refrigerator"
        case .restaurant: "fork.knife"
        case .quickSnack: "bolt.fill"
        }
    }

    private func gapOptionDetail(for option: ProteinGapOption, rank: Int) -> String {
        switch option.tier {
        case .kitchenStaple, .quickSnack:
            "#\(rank) · \(option.name) · \(Int(option.proteinGrams))g protein"
        case .restaurant:
            "#\(rank) · \(Copy.fuel.gapOptionRestaurantDetail)"
        }
    }

    /// Dispatches a tapped gap-planner option. Kitchen-staple and quick-snack tiers both close the
    /// gap the only way this screen has a real intent for — a direct `LogProteinIntent` — since
    /// there's no dedicated "log a kitchen staple" intent (this file's header). The restaurant tier
    /// has no real per-item protein figure to log yet (spec §28 unresolved vendor), so it opens the
    /// same best-effort Apple Maps search `openNearbyRestaurantSearch()` already provides.
    private func performGapOption(_ option: ProteinGapOption) async {
        switch option.tier {
        case .kitchenStaple, .quickSnack:
            Analytics.shared.capture(
                event: "fuel_gap_option_logged",
                properties: ["tier": option.tier.analyticsValue, "protein_grams": option.proteinGrams]
            )
            await log(goalType: .protein, amount: option.proteinGrams, source: .manual)
        case .restaurant:
            Analytics.shared.capture(event: "fuel_gap_option_restaurant_opened", properties: [:])
            await openNearbyRestaurantSearch()
        }
    }

    /// Merges `ProteinGapPlanner`'s real Tier 1 (kitchen staples) with this file's own local Tier
    /// 2/3 fallbacks (see this file's header for why those two tiers stay local for now), then
    /// ranks the combined list the same way `ProteinGapPlanner.rank(_:)` does internally (tier
    /// order first — spec §5.20's fixed "kitchen staples, ... restaurant ..., or ... quick snack"
    /// priority — then proximity within a tier). `ProteinGapPlanner.rank(_:)` itself isn't `public`
    /// (Core-internal), so this is a plain, local 2-line sort over the same public, `Comparable`
    /// `ProteinGapTier` — not a re-guess at its logic.
    private func loadGapOptions() async {
        guard let proteinGoal else {
            gapOptions = []
            return
        }

        let proteinEvents = verifiedEventsToday.filter { $0.goal?.id == proteinGoal.id }
        var combined = await ProteinGapPlanner.shared.rankedOptions(
            for: proteinGoal,
            verifiedProteinEventsToday: proteinEvents,
            on: .now
        )

        let gap = proteinGapGrams
        if gap > 0 {
            combined.append(
                ProteinGapOption(
                    tier: .restaurant,
                    name: Copy.fuel.gapOptionRestaurantTitle,
                    proteinGrams: Double(gap),
                    proximityScore: 0
                )
            )
            if let snack = FuelReferenceData.quickSnacks.min(by: { abs($0.grams - gap) < abs($1.grams - gap) }) {
                combined.append(
                    ProteinGapOption(
                        tier: .quickSnack,
                        name: snack.name,
                        proteinGrams: Double(snack.grams),
                        proximityScore: Double(abs(snack.grams - gap))
                    )
                )
            }
        }

        gapOptions = combined.sorted { lhs, rhs in
            lhs.tier != rhs.tier ? lhs.tier < rhs.tier : lhs.proximityScore < rhs.proximityScore
        }

        if !gapOptions.isEmpty {
            Analytics.shared.capture(
                event: "fuel_gap_planner_shown",
                properties: ["option_count": gapOptions.count, "gap_grams": gap]
            )
        }
    }

    private func openNearbyRestaurantSearch() async {
        // Best-effort location bias only — never prompts for authorization from this screen
        // (permission priming is onboarding's job, spec §7); reads whatever's already cached if
        // the user already granted location somewhere else (e.g. Gym Setup), and falls back to an
        // unbiased search otherwise.
        var components = URLComponents(string: "https://maps.apple.com/")!
        var queryItems = [URLQueryItem(name: "q", value: "high protein food")]
        if let coordinate = CLLocationManager().location?.coordinate {
            queryItems.append(URLQueryItem(name: "near", value: "\(coordinate.latitude),\(coordinate.longitude)"))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return }
        openURL(url)
    }

    // MARK: - Quick Repeat (spec §5.19, via `QuickRepeatSuggester`)

    private func quickRepeatSection(for meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.fuel.quickRepeatSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            GoalRow(
                title: Copy.fuel.quickRepeatPrompt(
                    label: mealDisplayName(meal),
                    grams: Int((meal.proteinG ?? 0).rounded())
                ),
                icon: "arrow.counterclockwise",
                color: Theme.Colors.Ring.protein,
                status: .pending,
                action: { Task { await logQuickRepeat(meal) } }
            )
        }
        .disabled(isLogging)
    }

    private func mealDisplayName(_ meal: Meal) -> String {
        meal.items.first?.name.capitalized ?? Copy.fuel.quickRepeatEmptyMealLabel
    }

    private func loadQuickRepeatSuggestion() async {
        let suggestion = await QuickRepeatSuggester.shared.suggestedQuickRepeat(at: .now)
        quickRepeatMeal = suggestion
        if let suggestion {
            Analytics.shared.capture(
                event: "fuel_quick_repeat_suggested",
                properties: ["meal_id": suggestion.id.uuidString, "protein_grams": suggestion.proteinG ?? 0]
            )
        }
    }

    private func logQuickRepeat(_ meal: Meal) async {
        isLogging = true
        defer { isLogging = false }
        Analytics.shared.capture(event: "fuel_quick_repeat_logged", properties: ["meal_id": meal.id.uuidString])
        do {
            var intent = QuickRepeatMealIntent()
            intent.meal = MealEntity(id: meal.id, label: mealDisplayName(meal))
            _ = try await intent.perform()
            // Consumed — clear immediately so the prompt doesn't sit there offering a second,
            // now-stale tap; `refreshFuelState()` (next pull-to-refresh or screen revisit) will
            // surface a fresh suggestion, if any, via the same anti-annoyance cooldown
            // `QuickRepeatSuggester` already enforces internally.
            quickRepeatMeal = nil
            await loadGapOptions()
        } catch {
            errorAlert = FuelErrorAlert(title: Copy.fuel.logFailedTitle, message: error.localizedDescription)
        }
    }

    // MARK: - Kitchen Staples (spec §10 — "user saves 10-20 staples once")

    private var kitchenStaplesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(Copy.fuel.kitchenStaplesSectionTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer()
                FuelQuickAddChip(title: Copy.fuel.kitchenStapleAddButtonLabel, color: Theme.Colors.muted, systemImage: "plus") {
                    Analytics.shared.capture(event: "fuel_kitchen_staple_add_opened")
                    isKitchenStapleAddSheetPresented = true
                }
                .disabled(currentUser == nil)
            }

            if kitchenStaples.isEmpty {
                Text(Copy.fuel.kitchenStaplesEmptyMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(kitchenStaples) { staple in
                        FuelKitchenStapleRow(
                            staple: staple,
                            onLog: { Task { await logKitchenStaple(staple) } },
                            onDelete: { pendingStapleDeletion = staple }
                        )
                    }
                }
            }
        }
        .disabled(isLogging)
    }

    private func loadKitchenStaples() {
        guard let userID = currentUser?.id else {
            kitchenStaples = []
            return
        }
        var descriptor = FetchDescriptor<KitchenStaple>(
            predicate: #Predicate<KitchenStaple> { $0.userID == userID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        // `try?`-guarded, not `@Query` — see this file's header "INTEGRATION GAP" note: until
        // `KitchenStaple.self` is added to `Store/ModelContainer+AppGroup.swift`'s
        // `appGroupModelTypes`, this degrades to an empty list against the real App Group
        // container rather than risking a harder failure.
        kitchenStaples = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func addKitchenStaple(name: String, proteinGrams: Double) {
        guard let userID = currentUser?.id else { return }
        let staple = KitchenStaple(userID: userID, name: name, proteinG: proteinGrams)
        modelContext.insert(staple)
        do {
            try modelContext.save()
            Analytics.shared.capture(event: "fuel_kitchen_staple_added", properties: ["protein_g": proteinGrams])
            loadKitchenStaples()
            Task { await loadGapOptions() }
        } catch {
            errorAlert = FuelErrorAlert(title: Copy.fuel.kitchenStapleSaveFailedTitle, message: error.localizedDescription)
        }
    }

    private func deleteKitchenStaple(_ staple: KitchenStaple) {
        pendingStapleDeletion = nil
        modelContext.delete(staple)
        do {
            try modelContext.save()
            Analytics.shared.capture(event: "fuel_kitchen_staple_deleted", properties: [:])
            loadKitchenStaples()
            Task { await loadGapOptions() }
        } catch {
            errorAlert = FuelErrorAlert(title: Copy.fuel.kitchenStapleSaveFailedTitle, message: error.localizedDescription)
        }
    }

    /// Logging a staple has no dedicated intent (this file's header) — it's a direct
    /// `LogProteinIntent` for the staple's own `proteinG`, same as a gap-planner kitchen-staple tap.
    private func logKitchenStaple(_ staple: KitchenStaple) async {
        Analytics.shared.capture(
            event: "fuel_kitchen_staple_logged",
            properties: ["protein_g": staple.proteinG]
        )
        await log(goalType: .protein, amount: staple.proteinG, source: .manual)
        await loadGapOptions()
    }

    // MARK: - Logging

    private func log(goalType: GoalType, amount: Double, source: GoalLogSource) async {
        isLogging = true
        defer { isLogging = false }
        do {
            switch goalType {
            case .protein:
                var intent = LogProteinIntent()
                intent.grams = max(0, amount.rounded())
                intent.source = source
                _ = try await intent.perform()
            case .water:
                var intent = LogWaterIntent()
                intent.milliliters = max(0, Int(amount.rounded()))
                intent.source = source
                _ = try await intent.perform()
            default:
                break
            }
        } catch {
            errorAlert = FuelErrorAlert(title: Copy.fuel.logFailedTitle, message: error.localizedDescription)
        }
    }

    // MARK: - Refresh (spec §9.1 Adaptive Goal Engine + §5.19/§5.20/§10 suggestion surfaces)

    private func refreshFuelState() async {
        await loadDailyPlans()
        await loadQuickRepeatSuggestion()
        await loadGapOptions()
        loadKitchenStaples()
    }

    private func loadDailyPlans() async {
        if let proteinGoal {
            proteinPlan = await AdaptiveGoalEngine.shared.dailyPlan(for: proteinGoal, on: .now)
        }
        if let waterGoal {
            waterPlan = await AdaptiveGoalEngine.shared.dailyPlan(for: waterGoal, on: .now)
        }
    }

    // MARK: - Derived values

    private var proteinGoal: Goal? { activeGoals.first { $0.type == .protein } }
    private var waterGoal: Goal? { activeGoals.first { $0.type == .water } }
    private var currentUser: User? { users.first }

    private var proteinToday: Double { sum(for: proteinGoal) }
    private var waterToday: Double { sum(for: waterGoal) }

    private func sum(for goal: Goal?) -> Double {
        guard let goal else { return 0 }
        return verifiedEventsToday
            .filter { $0.goal?.id == goal.id }
            .reduce(0) { $0 + ($1.value ?? 0) }
    }

    /// Today's actual bar (`AdaptiveGoalEngine`'s `DailyPlan.plannedValue`), falling back to the
    /// goal's static `targetValue` for the expected early-app-life case where no plan has been
    /// generated for today yet (see `loadDailyPlans`, which races the `@Query`/`.task` on first
    /// appearance).
    private var proteinTarget: Double { proteinPlan?.plannedValue ?? proteinGoal?.targetValue ?? 0 }
    private var waterTarget: Double { waterPlan?.plannedValue ?? waterGoal?.targetValue ?? 0 }

    private var proteinGapGrams: Int { max(0, Int((proteinTarget - proteinToday).rounded())) }

    private func safeProgress(current: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return current / target
    }
}

// MARK: - File-scoped supporting types

/// Which manual-amount sheet is open. A local wrapper (not a retroactive `Identifiable`
/// conformance on the shared `GoalType` enum, which is owned by another session/file —
/// `Core/Sources/Core/Models/Goal.swift` — and retroactively conforming it here would risk a
/// duplicate-conformance build error if another parallel agent does the same in a different file).
private struct FuelSheet: Identifiable {
    let goalType: GoalType
    var id: GoalType { goalType }
}

/// File-scoped alert payload — plain `Identifiable` glue for `.alert`, matching the convention
/// `LockSetupView.swift`'s `LockSetupErrorAlert` already established.
private struct FuelErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// PostHog-friendly, stable string per `ProteinGapTier` case — `ProteinGapTier` is a Core-public
/// `Int`-backed enum with no `String` raw value of its own (it's ordered by `rawValue`, not named),
/// so this file derives its own stable analytics label rather than sending a bare integer.
private extension ProteinGapTier {
    var analyticsValue: String {
        switch self {
        case .kitchenStaple: "kitchen_staple"
        case .restaurant: "restaurant"
        case .quickSnack: "quick_snack"
        }
    }
}

/// Small, non-voiced reference data — see this file's header comment for why this lives here
/// rather than in `Core/Sources/Core/Copy`.
private enum FuelReferenceData {
    static let proteinPresetsGrams = [15, 25, 40]
    static let waterPresetsMl = [250, 500, 750]

    struct QuickSnack {
        let name: String
        let grams: Int
    }

    static let quickSnacks: [QuickSnack] = [
        QuickSnack(name: "Greek yogurt", grams: 15),
        QuickSnack(name: "2 eggs", grams: 12),
        QuickSnack(name: "String cheese", grams: 7),
        QuickSnack(name: "Protein shake", grams: 25),
        QuickSnack(name: "Handful of almonds", grams: 6),
        QuickSnack(name: "Beef jerky", grams: 10),
        QuickSnack(name: "Cottage cheese", grams: 14),
    ]
}

/// A small capsule quick-action button, styled from `Theme` only.
private struct FuelQuickAddChip: View {
    let title: String
    let color: Color
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(Theme.Typography.captionEmphasized)
            }
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.springStandard, value: title)
    }
}

/// A small sheet for entering an exact protein/water amount, used by the "+Custom" chip. Kept
/// file-scoped: this is a simple numeric-entry form, not a shared design-system component.
private struct ManualAmountSheet: View {
    let goalType: GoalType
    let fieldLabel: String
    let titleLabel: String
    let onSubmit: (Double) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var parsedAmount: Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(fieldLabel, text: $text)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                } header: {
                    Text(fieldLabel)
                }
            }
            .navigationTitle(titleLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.save) {
                        guard let parsedAmount, parsedAmount > 0 else { return }
                        onSubmit(parsedAmount)
                    }
                    .disabled((parsedAmount ?? 0) <= 0)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Kitchen Staples supporting views

/// One saved `KitchenStaple` row: tap the leading area to log its protein straight to today's
/// Protein goal, tap the trailing trash icon to delete it. Two independent `Button`s in an `HStack`
/// (not `GoalRow` + a hidden `.contextMenu`) so delete stays a single, discoverable tap rather than
/// a long-press a first-time user has no reason to discover — `GoalRow`'s own single full-row
/// `Button` has no room for a second, independent tap target.
private struct FuelKitchenStapleRow: View {
    let staple: KitchenStaple
    let onLog: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: onLog) {
                HStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle().fill(Theme.Colors.Ring.protein.opacity(0.16))
                        Image(systemName: "refrigerator")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.Ring.protein)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(staple.name)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        Text("\(Int(staple.proteinG))g protein")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

/// Add-a-staple form (spec §10: "user saves 10-20 staples once"). File-scoped, mirrors
/// `ManualAmountSheet`'s own `Form` + toolbar Save/Cancel convention in this same file.
private struct KitchenStapleAddSheet: View {
    let onSave: (String, Double) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var proteinText: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, protein }

    private var parsedProtein: Double? {
        Double(proteinText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parsedProtein ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.fuel.kitchenStapleNameFieldLabel, text: $name)
                        .focused($focusedField, equals: .name)
                    TextField(Copy.fuel.kitchenStapleProteinFieldLabel, text: $proteinText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .protein)
                }
            }
            .navigationTitle(Copy.fuel.kitchenStapleAddSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.save) {
                        guard let parsedProtein, canSave else { return }
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), parsedProtein)
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { focusedField = .name }
        }
    }
}

// MARK: - Barcode scan (spec §3 Protein Tier B "barcode scan", §10, via `BarcodeProteinLookup`)

/// One `BarcodeScanSheet` screen state. File-scoped — see this file's header for the real,
/// live-verified `BarcodeProteinLookup`/`DataScannerViewController` shapes this is built against.
private enum BarcodeLookupState {
    case scanning
    case lookingUp
    case found(BarcodeProduct)
    /// Open Food Facts had only a per-100g protein figure, no serving size (`BarcodeProteinLookup`'s
    /// own header: the real, live-verified Nutella case) — needs the user to say how much they're
    /// having before there's a grams figure to log.
    case needsServingSize(BarcodeProduct)
    case failed(message: String)
}

/// Barcode-scan entry point for protein logging. Presents a live VisionKit scanner when the device
/// supports it, with a manual barcode-entry fallback always reachable (unsupported device/
/// Simulator, or a camera that isn't cooperating) — see this file's header for what's verified vs.
/// still unverified about the VisionKit surface this uses.
private struct BarcodeScanSheet: View {
    /// `(proteinGrams, barcode)` — called once, right before the caller dismisses this sheet.
    let onLogged: (Double, String) -> Void
    let onDismiss: () -> Void

    @State private var lookupState: BarcodeLookupState = .scanning
    @State private var scannedBarcode: String?
    @State private var useManualEntryFallback = false
    @State private var manualBarcodeText = ""
    @State private var manualServingGrams = "100"

    private var isDeviceScanningSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Copy.fuel.barcodeScanTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.common.cancel, action: onDismiss)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch lookupState {
        case .scanning:
            if isDeviceScanningSupported && !useManualEntryFallback {
                liveScannerView
            } else {
                manualEntryForm
            }
        case .lookingUp:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .found(let product):
            resultView(for: product)
        case .needsServingSize(let product):
            servingSizeForm(for: product)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var liveScannerView: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(onBarcodeScanned: { barcode in
                Task { @MainActor in handleScanned(barcode) }
            })
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.fuel.barcodeScanInstructions)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.text)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.surface.opacity(0.9), in: Capsule())

                Button(Copy.fuel.barcodeManualEntryTitle) {
                    useManualEntryFallback = true
                }
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                .buttonStyle(.plain)
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    private var manualEntryForm: some View {
        VStack(spacing: Theme.Spacing.md) {
            if !isDeviceScanningSupported {
                Text(Copy.fuel.barcodeUnavailableMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            TextField(Copy.fuel.barcodeManualEntryFieldLabel, text: $manualBarcodeText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, Theme.Spacing.lg)

            PrimaryButton(title: Copy.fuel.barcodeManualEntrySubmitLabel, isEnabled: !manualBarcodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                handleScanned(manualBarcodeText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.top, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func resultView(for product: BarcodeProduct) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(product.name ?? Copy.fuel.barcodeUnknownProductLabel)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            if let brand = product.brand {
                Text(brand)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            if let grams = product.proteinGramsPerServing {
                Text(Copy.fuel.barcodeResultProteinLabel(grams: Int(grams.rounded())))
                    .font(Theme.Typography.numeralMedium())
                    .foregroundStyle(Theme.Colors.Ring.protein)

                PrimaryButton(title: Copy.fuel.barcodeLogButtonLabel) {
                    onLogged(grams, product.barcode)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func servingSizeForm(for product: BarcodeProduct) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(Copy.fuel.barcodeServingPromptTitle(productName: product.name ?? Copy.fuel.barcodeUnknownProductLabel))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            TextField(Copy.fuel.barcodeServingGramsFieldLabel, text: $manualServingGrams)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, Theme.Spacing.lg)

            if let grams = computedServingProtein(for: product) {
                Text(Copy.fuel.barcodeServingProteinPreview(grams: Int(grams.rounded())))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }

            PrimaryButton(title: Copy.fuel.barcodeLogButtonLabel, isEnabled: computedServingProtein(for: product) != nil) {
                guard let grams = computedServingProtein(for: product) else { return }
                onLogged(grams, product.barcode)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func computedServingProtein(for product: BarcodeProduct) -> Double? {
        guard let servingGrams = Double(manualServingGrams.trimmingCharacters(in: .whitespacesAndNewlines)),
              servingGrams > 0,
              let per100g = product.proteinGramsPer100g
        else { return nil }
        return per100g / 100 * servingGrams
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.warning)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)
            PrimaryButton(title: Copy.fuel.barcodeRetryButtonLabel) {
                scannedBarcode = nil
                lookupState = .scanning
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleScanned(_ barcode: String) {
        // Ignores a second recognition while a lookup for the first is still in flight — VisionKit
        // can call `didAdd` again for the same/an adjacent frame before this state flips out of
        // `.scanning`.
        guard scannedBarcode == nil else { return }
        scannedBarcode = barcode
        lookupState = .lookingUp

        Task {
            do {
                let product = try await BarcodeProteinLookup.shared.lookupProtein(barcode: barcode)
                Analytics.shared.capture(
                    event: "fuel_barcode_scan_lookup_succeeded",
                    properties: ["barcode": product.barcode, "basis": product.proteinBasis.rawValue]
                )
                if product.proteinGramsPerServing != nil {
                    lookupState = .found(product)
                } else {
                    lookupState = .needsServingSize(product)
                }
            } catch {
                Analytics.shared.capture(
                    event: "fuel_barcode_scan_failed",
                    properties: ["barcode": barcode, "reason": String(describing: error)]
                )
                lookupState = .failed(message: Self.reasonText(for: error))
                scannedBarcode = nil
            }
        }
    }

    private static func reasonText(for error: Error) -> String {
        guard let lookupError = error as? BarcodeProteinLookupError else {
            return Copy.fuel.barcodeErrorTransport
        }
        switch lookupError {
        case .invalidBarcode: return Copy.fuel.barcodeErrorInvalidBarcode
        case .productNotFound: return Copy.fuel.barcodeErrorProductNotFound
        case .noNutritionData: return Copy.fuel.barcodeErrorNoNutritionData
        case .decodingFailure, .transportFailure: return Copy.fuel.barcodeErrorTransport
        }
    }
}

/// Thin `UIViewControllerRepresentable` around VisionKit's `DataScannerViewController`, scoped to
/// barcode recognition only (no free text). See `BarcodeScanSheet`'s enclosing file header for the
/// real, live-verified API shape this was built against and what's still unverified without a Mac.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void

    /// Common retail barcode symbologies — matches `BarcodeProteinLookup.normalizedBarcode(from:)`'s
    /// own 6...14-digit-bound reasoning (covers UPC-E/EAN-8/EAN-13/ITF-14/Code128 rather than
    /// narrowing to exactly one symbology).
    private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .itf14]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !context.coordinator.didStartScanning else { return }
        context.coordinator.didStartScanning = true
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcodeScanned: onBarcodeScanned)
    }

    /// Deliberately carries no actor-isolation annotation of its own — see this file's header for
    /// why: it never touches `@State`/actor-isolated data directly, only extracts a plain `String`
    /// from the recognized item and forwards to `onBarcodeScanned`, which the caller
    /// (`BarcodeScanSheet.liveScannerView`) already wraps in an explicit `Task { @MainActor in ... }`
    /// before it does anything state-mutating.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcodeScanned: (String) -> Void
        var didStartScanning = false

        init(onBarcodeScanned: @escaping (String) -> Void) {
            self.onBarcodeScanned = onBarcodeScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onBarcodeScanned(payload)
                    return
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FuelView()
    }
    .modelContainer(for: [Goal.self, GoalEvent.self, Meal.self, User.self, KitchenStaple.self], inMemory: true)
}
