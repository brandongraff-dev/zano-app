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
//
// DESIGN PASS (2026-09-23, docs/design/{competitive-research,2026-ios-trends,better-ui-findings,
// better-layout-findings,typography-color-findings,composition-audit}.md). Composition and visual
// treatment only — every data/intent/analytics path above is unchanged. What moved and why:
//   - Rings + chip rows -> one card per metric. Protein is the hero card (112pt ring, 64pt
//     numeral, "72 / 150 g" counts UP — never a remaining-budget figure, competitive-research 2.2),
//     water a compact card. The number now lives beside its ring, and the logging chips live
//     INSIDE the card they change (better-layout 2.1, composition-audit offender 3). The old
//     3x148pt `RingCluster(.row)` scroller is gone (500pt in a 361pt column, better-ui BRK-05).
//   - Ring track is the ring's own hue at 30% (`GoalRing`), not `surface2` (1.08:1 on its card,
//     better-ui DEP-03) so an empty ring still reads as "that goal's ring".
//   - Cards get a top-lit 1pt edge and, on the two metric cards only, a faint wash of the metric's
//     own hue — the flat `surface`-on-`background` pairing is 1.08:1 (trends 3.1).
//   - Every tap target is >= 44pt (chips were ~32pt, staple delete 32pt, manual-entry link ~16pt).
//   - Gap-planner / quick-repeat / staples no longer use `GoalRow`'s trailing empty circle (it
//     reads "unchecked to-do" on rows that are actually *tap to log*): each row now ends in the
//     amount it will log, or an external-link glyph for the Maps option. The engine-internal
//     "#rank" prefix is dropped.
//   - Logging fires a `.success` haptic (spec §15 "haptics on every verified event").
//   - `ProgressView()` here is qualified as `SwiftUI.ProgressView()`: this module declares its own
//     `ProgressView` screen (`Features/Progress/ProgressView.swift`) which shadows the spinner.
//   - Every animation below is gated on `accessibilityReduceMotion` (nil / plain ease / opacity).
//
// CONSOLIDATION PASS (2026-09-23, later the same day). The pass above was written while `Theme` and
// the shared Core UI pieces were still being built in a parallel wave, so it carried file-scoped
// copies of them (`FuelSurface`, `FuelPressStyle`, `FuelMetricRing`, `FuelIconBadge`, a private
// hairline, an inline eyebrow, `FuelMetrics.minTapTarget`). Those now exist for real, so this file
// uses them instead of re-implementing them (CLAUDE.md: one place to change each):
//   - cards          -> `.zanoCard(radius:tint:active:)` / `.zanoWell(radius:)`. The two metric cards
//                       pass `active: goal met`, which is the design system's *earned* glow — the only
//                       glow on this screen, and only once the goal is actually met.
//   - rings          -> `GoalRing` (`.custom(112)` for the protein hero, `.medium` for water; own-hue
//                       track, static glow, completion pulse and Reduce Motion handling all live
//                       there once). The center glyph swaps to a checkmark when the goal is met.
//   - badges/presses -> `IconBadge`, `PressableStyle`.
//   - text           -> `zanoText(.eyebrow)`, `Theme.Typography.unit`, `Theme.Typography.icon(_)`,
//                       `Theme.Typography.numeral(size:weight:)` for the two numeral sizes that are
//                       container-driven (`@ScaledMetric`, so they follow Dynamic Type).
//   - edges/dividers -> `Theme.Colors.hairline` / `hairlineStrong`, `Theme.Metrics.minTapTarget`.
//   - washes         -> `Theme.Colors.wash(_)` instead of `color.opacity(0.14/0.16)`.
// Three judgment calls beyond swapping in the shared pieces:
//   - The wash is now reserved for the two metric cards (protein, water). Quick Repeat, the gap
//     planner and the staples list sit on a plain `surface` card — before, the top of this screen
//     stacked two-to-three orange-washed cards, which flattened the hierarchy again (the hero
//     protein card should be the one thing tinted). Their hue still shows in the badge, eyebrow and
//     amount pills.
//   - Dividers inside a card run margin to margin instead of being inset to the leading badge, so
//     they stay aligned at every Dynamic Type size (the shared `IconBadge` grows with the text).
//   - Gap-planner rows are titled by the food ("Greek yogurt"), with the tier ("Quick snack") as the
//     muted second line. The rows had it inverted: the food was a 13pt muted caption under a 15pt
//     tier name, so the one thing the user is deciding on was the quietest text on the row.

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Only for `KitchenStaple` CRUD — see this file's header "INTEGRATION GAP" note for why this
    /// goes through a plain, `try?`-guarded `ModelContext` fetch/insert/delete rather than `@Query`.
    @Environment(\.modelContext) private var modelContext

    @State private var proteinPlan: DailyPlan?
    @State private var waterPlan: DailyPlan?
    @State private var activeSheet: FuelSheet?
    @State private var errorAlert: FuelErrorAlert?
    @State private var isLogging = false
    /// Bumped once per successfully logged amount; drives the `.success` haptic below.
    @State private var logTick = 0

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
            // Reading order = likelihood of the next tap (better-layout 1.4): the one-tap quick
            // repeat when it exists, then the two metrics with their own logging controls, then the
            // "you're behind" planner, then the saved staples. Sections are 24pt apart; everything
            // inside a section is 8-16pt, so the groups read as groups without divider lines.
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if proteinGoal == nil && waterGoal == nil {
                    emptyState
                } else {
                    if let quickRepeatMeal {
                        quickRepeatSection(for: quickRepeatMeal)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    metricsSection
                    if isGapPlannerEligible && !gapOptions.isEmpty {
                        gapPlannerSection
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    if proteinGoal != nil {
                        kitchenStaplesSection
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: quickRepeatMeal?.id)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: gapOptions.count)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: kitchenStaples.count)
        }
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.fuel.screenTitle)
        .sensoryFeedback(.success, trigger: logTick)
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

    /// No protein or water goal yet. Two dashed, empty rings in the goals' own hues (the "empty slot
    /// is an add-circle in the same grid" idea from competitive-research 3.10) instead of a stock
    /// `ContentUnavailableView` — the screen previews what will live here. Not interactive: goal
    /// setup isn't reachable from this screen, so no plus glyph pretends it is.
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                FuelPlaceholderRing(systemImage: "fork.knife", color: Theme.Colors.Ring.protein)
                FuelPlaceholderRing(systemImage: "drop.fill", color: Theme.Colors.Ring.water)
            }
            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.fuel.emptyGoalsTitle)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.fuel.emptyGoalsMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Metrics (protein hero + water)

    /// One card per metric: ring, the number beside it, and that metric's own quick-add controls
    /// inside the same surface (proximity ties "+25g" to the protein ring — better-layout 2.1).
    /// Protein is the hero when both exist (spec §3: it's the Tier B goal with the richest logging
    /// paths); water is the compact card. With only one goal, that goal is the hero.
    private var metricsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if proteinGoal != nil {
                FuelMetricCard(
                    style: .hero,
                    title: Copy.fuel.proteinLabel,
                    systemImage: "fork.knife",
                    color: Theme.Colors.Ring.protein,
                    current: proteinToday,
                    target: proteinTarget,
                    unit: "g"
                ) {
                    FuelQuickAddRow(
                        presets: FuelReferenceData.proteinPresetsGrams,
                        unit: "g",
                        color: Theme.Colors.Ring.protein,
                        customLabel: Copy.fuel.logCustomButtonLabel,
                        onPreset: { grams in Task { await log(goalType: .protein, amount: Double(grams), source: .manual) } },
                        onCustom: { activeSheet = FuelSheet(goalType: .protein) },
                        trailingSystemImage: "barcode.viewfinder",
                        trailingLabel: Copy.fuel.barcodeScanButtonLabel,
                        onTrailing: {
                            Analytics.shared.capture(event: "fuel_barcode_scan_opened")
                            isBarcodeSheetPresented = true
                        }
                    )
                }
            }
            if waterGoal != nil {
                FuelMetricCard(
                    style: proteinGoal == nil ? .hero : .compact,
                    title: Copy.fuel.waterLabel,
                    systemImage: "drop.fill",
                    color: Theme.Colors.Ring.water,
                    current: waterToday,
                    target: waterTarget,
                    unit: "ml"
                ) {
                    FuelQuickAddRow(
                        presets: FuelReferenceData.waterPresetsMl,
                        unit: "ml",
                        color: Theme.Colors.Ring.water,
                        customLabel: Copy.fuel.logCustomButtonLabel,
                        onPreset: { ml in Task { await log(goalType: .water, amount: Double(ml), source: .manual) } },
                        onCustom: { activeSheet = FuelSheet(goalType: .water) }
                    )
                }
            }
        }
        .disabled(isLogging)
    }

    // MARK: - Gap Planner (spec §5.20, via `ProteinGapPlanner` for Tier 1)

    private var isGapPlannerEligible: Bool {
        guard proteinGoal != nil else { return false }
        return ProteinGapPlanner.isEligible(gapGrams: Double(proteinGapGrams))
    }

    /// One grouped card (header + a row per option, hairlines only between rows — the "dense list"
    /// case where lines beat five sibling cards, better-layout 2.2). The tier order from
    /// `ProteinGapPlanner` already ranks the options, so the order alone carries "best first"; the
    /// engine-internal "#rank" prefix the old rows showed is gone.
    private var gapPlannerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                FuelEyebrow(text: Copy.fuel.gapPlannerTitle, color: Theme.Colors.Ring.protein)
                Text(Copy.fuel.gapPlannerSubtitle(gapGrams: proteinGapGrams))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(gapOptions) { option in
                FuelHairline()
                    .padding(.horizontal, Theme.Spacing.md)
                FuelOptionRow(
                    title: gapOptionTitle(for: option),
                    detail: gapOptionDetail(for: option),
                    systemImage: gapOptionIcon(for: option.tier),
                    trailing: option.tier == .restaurant ? .external : .logs(grams: Int(option.proteinGrams.rounded())),
                    action: { Task { await performGapOption(option) } }
                )
            }
        }
        .zanoCard(radius: Theme.Radius.medium)
        .disabled(isLogging)
    }

    /// The answer to "what should I eat?" leads the row: a staple or snack is named ("Greek
    /// yogurt"), not filed under its tier. Before, the food's name was the 13pt muted second line
    /// under a 15pt "From your kitchen" — the decisive words were the quietest on the row
    /// (typography-color T10).
    private func gapOptionTitle(for option: ProteinGapOption) -> String {
        switch option.tier {
        case .kitchenStaple, .quickSnack: option.name
        case .restaurant: Copy.fuel.gapOptionRestaurantTitle
        }
    }

    private func gapOptionIcon(for tier: ProteinGapTier) -> String {
        switch tier {
        case .kitchenStaple: "refrigerator"
        case .restaurant: "mappin.and.ellipse"
        case .quickSnack: "takeoutbag.and.cup.and.straw.fill"
        }
    }

    /// Kitchen-staple / snack rows say where the suggestion comes from (the amount it logs is the
    /// trailing pill); the restaurant row says what tapping does.
    private func gapOptionDetail(for option: ProteinGapOption) -> String {
        switch option.tier {
        case .kitchenStaple: Copy.fuel.gapOptionStapleTitle
        case .quickSnack: Copy.fuel.gapOptionSnackTitle
        case .restaurant: Copy.fuel.gapOptionRestaurantDetail
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

    /// A single compact, tappable banner (not a section + `GoalRow`): the prompt sentence keeps its
    /// grams (2 lines allowed — the old row truncated the deciding number first), and the trailing
    /// plus says "this logs", where the old trailing empty circle said "unchecked to-do".
    private func quickRepeatSection(for meal: Meal) -> some View {
        let prompt = Copy.fuel.quickRepeatPrompt(
            label: mealDisplayName(meal),
            grams: Int((meal.proteinG ?? 0).rounded())
        )
        return Button {
            Task { await logQuickRepeat(meal) }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: "arrow.counterclockwise", tint: Theme.Colors.Ring.protein)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    FuelEyebrow(text: Copy.fuel.quickRepeatSectionTitle, color: Theme.Colors.Ring.protein)
                    Text(prompt)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.xs)

                // The verb: same tinted-disc treatment as the "+25 g" chips below, so "tap = adds"
                // is one learned gesture across the screen.
                IconBadge(systemName: "plus", tint: Theme.Colors.Ring.protein, size: .small)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            // Surface lives INSIDE the label so the press feedback moves the whole card, not just
            // the text on a static slab (better-ui HIT-04 / MOT-02).
            .zanoCard(radius: Theme.Radius.medium)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(prompt)
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
            logTick += 1
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(Copy.fuel.kitchenStaplesSectionTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: 0)
                FuelAddPill(title: Copy.fuel.kitchenStapleAddButtonLabel) {
                    openKitchenStapleAddSheet()
                }
                .disabled(currentUser == nil)
            }

            if kitchenStaples.isEmpty {
                // An empty slot is just an "add" tile in the same grid (competitive-research 3.10):
                // dashed outline + plus + the explanatory line, and the whole tile is the button.
                FuelEmptyStapleTile(message: Copy.fuel.kitchenStaplesEmptyMessage) {
                    openKitchenStapleAddSheet()
                }
                .disabled(currentUser == nil)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(kitchenStaples.enumerated()), id: \.element.id) { index, staple in
                        if index > 0 {
                            FuelHairline()
                                .padding(.horizontal, Theme.Spacing.md)
                        }
                        FuelKitchenStapleRow(
                            staple: staple,
                            onLog: { Task { await logKitchenStaple(staple) } },
                            onDelete: { pendingStapleDeletion = staple }
                        )
                    }
                }
                .zanoCard(radius: Theme.Radius.medium)
            }
        }
        .disabled(isLogging)
    }

    private func openKitchenStapleAddSheet() {
        Analytics.shared.capture(event: "fuel_kitchen_staple_add_opened")
        isKitchenStapleAddSheetPresented = true
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
            logTick += 1
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

// MARK: - Screen-local primitives
//
// What the shared design system does not express: this screen's metric card, its numeral + unit
// pairing, the quick-add controls and the chrome around its text-entry sheets. Everything else
// (cards, rings, badges, press feedback, eyebrows) is `Core`'s — see the CONSOLIDATION PASS note in
// this file's header.

/// Sizes that are container-driven on this screen rather than design-system tokens.
private enum FuelMetrics {
    /// Diameter of the protein (hero) ring. `GoalRing.Size.large` (148) leaves too little of a 329pt
    /// card interior for a 64pt numeral beside it; `.medium` (88) is too small for a hero.
    static let heroRingDiameter: CGFloat = 112
    /// The hero numeral. Roughly 5x the 13pt captions around it (trends doc: aim for >= 3:1).
    static let heroNumeralPoints: CGFloat = 64
    /// The compact-card numeral: `Theme.Typography.numeralLarge()`'s size, but scalable.
    static let largeNumeralPoints: CGFloat = 44
    /// The non-interactive "+25 g" pill trailing a row; the row around it is the tap target.
    static let pillHeight: CGFloat = 32
    /// A row inside a grouped card: a 44pt target plus `Spacing.sm` of breathing room.
    static let rowMinHeight: CGFloat = Theme.Metrics.minTapTarget + Theme.Spacing.sm
}

/// Uppercase, tracked micro-label ("PROTEIN") in the shared eyebrow style (SF auto-tracks mixed case
/// but not an all-caps run; the style adds the +0.8pt).
private struct FuelEyebrow: View {
    let text: String
    var color: Color = Theme.Colors.muted

    var body: some View {
        Text(text)
            .zanoText(.eyebrow)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// A 1-physical-pixel divider in the shared `hairline` tone, for the dense-list case inside a card
/// where a line beats stacking sibling cards.
private struct FuelHairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

/// The number that IS the screen: value large, "/ target unit" as the small suffix. Counts up only
/// (spec §1/§24: additive goals — there is no "remaining" figure anywhere on this screen). Both
/// sizes are `@ScaledMetric` and capped at accessibility2, so they follow Dynamic Type without
/// blowing out the card; `ViewThatFits` drops the suffix under the number if it doesn't fit beside
/// it. The face is the shared numeral face (`Theme.Typography.numeral`), the suffix the shared
/// `unit` style — the same digit-over-unit pairing `NumeralText` draws elsewhere. `NumeralText`
/// itself is not used here because it is a single line that can only shrink, and this one needs to
/// re-flow into a stack first.
private struct FuelNumeral: View {
    enum Size { case hero, large }

    let value: Int
    let suffix: String
    var size: Size = .large
    var tint: Color = Theme.Colors.text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroPoints: CGFloat = FuelMetrics.heroNumeralPoints
    @ScaledMetric(relativeTo: .title) private var largePoints: CGFloat = FuelMetrics.largeNumeralPoints

    private var numeralFont: Font {
        switch size {
        case .hero: Theme.Typography.numeral(size: heroPoints, weight: .heavy)
        case .large: Theme.Typography.numeral(size: largePoints, weight: .bold)
        }
    }

    /// Display sizes want to sit a little tighter (the same values `NumeralText` uses per tier).
    private var numeralTracking: CGFloat {
        switch size {
        case .hero: -0.5
        case .large: -0.3
        }
    }

    private var number: some View {
        Text(value.formatted(.number))
            .font(numeralFont)
            .tracking(numeralTracking)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText(value: Double(value)))
            .animation(reduceMotion ? nil : Theme.Motion.springStandard, value: value)
    }

    private var suffixText: some View {
        Text(suffix)
            .font(Theme.Typography.unit)
            .foregroundStyle(Theme.Colors.muted)
            .lineLimit(1)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                number
                suffixText
            }
            VStack(alignment: .leading, spacing: 0) {
                number
                suffixText
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// One metric (protein or water): ring + number on top, that metric's own controls underneath, all
/// on one surface. Hero = radius `.large`, big ring and numeral; compact = radius `.medium`.
/// Padding is `Spacing.md`, so inside a `.large` card the concentric inner radius is exactly
/// `Radius.small` (28 - 16 = 12). The card carries a faint wash of the metric's own hue (its
/// identity) and, once the goal is met, the design system's earned glow.
private struct FuelMetricCard<Actions: View>: View {
    enum Style { case hero, compact }

    let style: Style
    let title: String
    let systemImage: String
    let color: Color
    let current: Double
    let target: Double
    let unit: String
    let actions: Actions

    init(
        style: Style,
        title: String,
        systemImage: String,
        color: Color,
        current: Double,
        target: Double,
        unit: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.style = style
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.current = current
        self.target = target
        self.unit = unit
        self.actions = actions()
    }

    private var isHero: Bool { style == .hero }
    private var progress: Double { target > 0 ? current / target : 0 }
    /// Same threshold `GoalRing` uses for its own completion pulse, so glow, check and pulse land
    /// together.
    private var isComplete: Bool { progress >= 1 }
    private var currentInt: Int { Int(current.rounded()) }
    private var suffix: String {
        target > 0 ? "/ \(Int(target.rounded()).formatted(.number)) \(unit)" : unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                // The ring carries the goal's glyph (glyph-first: never identify a goal by hue
                // alone) and turns into a check when the goal is met. The number lives beside it,
                // where it can be big enough to be the hero.
                GoalRing(
                    progress: progress,
                    color: color,
                    size: isHero ? .custom(FuelMetrics.heroRingDiameter) : .medium,
                    center: .icon(systemName: isComplete ? "checkmark" : systemImage)
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    FuelEyebrow(text: title, color: color)
                    FuelNumeral(value: currentInt, suffix: suffix, size: isHero ? .hero : .large)
                }

                Spacer(minLength: 0)
            }
            // The ring is decorative and the numeral/suffix are split across two Texts, so speak
            // one coherent phrase instead — same "72/150g" shape the old ring cell announced.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(target > 0 ? "\(currentInt)/\(Int(target.rounded()))\(unit)" : "\(currentInt)\(unit)")

            actions
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(
            radius: isHero ? Theme.Radius.large : Theme.Radius.medium,
            tint: color,
            active: isComplete
        )
    }
}

/// One row of quick-add controls: equal-width preset chips, then square icon buttons (custom
/// amount, and — protein only — barcode scan). Everything is 44pt tall, so the barcode scan that
/// used to sit off-screen at the end of a horizontal scroller is always visible.
private struct FuelQuickAddRow: View {
    let presets: [Int]
    let unit: String
    let color: Color
    let customLabel: String
    let onPreset: (Int) -> Void
    let onCustom: () -> Void
    var trailingSystemImage: String? = nil
    var trailingLabel: String? = nil
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(presets, id: \.self) { preset in
                Button {
                    onPreset(preset)
                } label: {
                    FuelAmountPill(
                        amount: "+\(preset)",
                        unit: unit,
                        color: color,
                        minHeight: Theme.Metrics.minTapTarget,
                        expands: true
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }

            FuelIconButton(systemImage: "plus", accessibilityLabel: customLabel, action: onCustom)

            if let trailingSystemImage, let trailingLabel, let onTrailing {
                FuelIconButton(systemImage: trailingSystemImage, accessibilityLabel: trailingLabel, action: onTrailing)
            }
        }
    }
}

/// An amount capsule ("+25 g"): numeral in `numeralSmall`, unit in `captionEmphasized`, both in the
/// metric's hue on its `wash` with a 1pt hue edge. Non-interactive on its own — used as a chip label
/// (44pt) and as the trailing "this is what tapping logs" pill on rows (32pt).
private struct FuelAmountPill: View {
    let amount: String
    let unit: String
    let color: Color
    var minHeight: CGFloat = FuelMetrics.pillHeight
    var expands = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(amount)
                .font(Theme.Typography.numeralSmall())
            Text(unit)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, expands ? Theme.Spacing.xxs : Theme.Spacing.sm)
        .frame(maxWidth: expands ? CGFloat.infinity : nil, minHeight: minHeight)
        .background(Theme.Colors.wash(color), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: Theme.Metrics.edgeWidth))
    }
}

/// 44x44 circular icon button on `surface2` with the secondary-control edge (custom amount, barcode
/// scan) — the same treatment `PrimaryButton.secondary` draws, at icon size.
private struct FuelIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                .background(Theme.Colors.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.hairlineStrong, lineWidth: Theme.Metrics.edgeWidth))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// "Add" pill for a section header: a 32pt visual with a 44pt hit area.
private struct FuelAddPill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "plus")
                    .font(Theme.Typography.icon(.xsmall, weight: .bold))
                Text(title)
                    .font(Theme.Typography.captionEmphasized)
            }
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.hairlineStrong, lineWidth: Theme.Metrics.edgeWidth))
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}

/// A gap-planner row: badge, title + detail (2 lines allowed), and what tapping does — the grams it
/// logs, or an external-link glyph for the Maps search. The whole row is the button.
private struct FuelOptionRow: View {
    enum Trailing {
        case logs(grams: Int)
        case external
    }

    let title: String
    let detail: String
    let systemImage: String
    let trailing: Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                IconBadge(systemName: systemImage, tint: Theme.Colors.Ring.protein, size: .small)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(2)
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                switch trailing {
                case .logs(let grams):
                    FuelAmountPill(amount: "+\(grams)", unit: "g", color: Theme.Colors.Ring.protein)
                case .external:
                    Image(systemName: "arrow.up.right")
                        .font(Theme.Typography.icon(.small))
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(width: Theme.Metrics.iconBadgeSmall, height: Theme.Metrics.iconBadgeSmall)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: FuelMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        switch trailing {
        case .logs(let grams): "\(title), \(detail), \(grams)g"
        case .external: "\(title), \(detail)"
        }
    }
}

/// Empty-staples slot: a dashed outline (the "unconfigured, tap to set up" language) with a plus,
/// instead of a bare muted caption under the header.
private struct FuelEmptyStapleTile: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: Theme.Metrics.iconBadgeMedium, height: Theme.Metrics.iconBadgeMedium)
                    .overlay(
                        Circle().strokeBorder(
                            Theme.Colors.hairlineStrong,
                            style: StrokeStyle(lineWidth: Theme.Metrics.edgeWidth, dash: [3, 3])
                        )
                    )
                    .accessibilityHidden(true)

                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(
                    Theme.Colors.hairlineStrong,
                    style: StrokeStyle(lineWidth: Theme.Metrics.edgeWidth, dash: [6, 5])
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Empty-state stand-in for a ring that doesn't exist yet: a dotted outline + the goal's glyph, both
/// in the goal's hue at reduced strength, at the same size and stroke as a `.medium` `GoalRing` so
/// the real ring replaces it without the layout moving.
private struct FuelPlaceholderRing: View {
    let systemImage: String
    let color: Color

    private let ring = GoalRing.Size.medium

    var body: some View {
        Circle()
            .strokeBorder(
                color.opacity(0.45),
                style: StrokeStyle(lineWidth: ring.lineWidth, lineCap: .round, dash: [2, 14])
            )
            .frame(width: ring.diameter, height: ring.diameter)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: ring.diameter * 0.34, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
            )
            .accessibilityHidden(true)
    }
}

/// Numeric text-field chrome: a `zanoWell` (`surface2`, `Radius.small`) with a hairline edge.
/// Replaces `.roundedBorder`, which paints a light system field inside a dark sheet.
private struct FuelFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Metrics.minTapTarget + Theme.Spacing.xs)
            .zanoWell(radius: Theme.Radius.small)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
            )
    }
}

private extension View {
    func fuelFieldChrome() -> some View { modifier(FuelFieldChrome()) }
}

/// Large centered numeric entry ("250 ml"): the amount is the only thing on the sheet, so it is the
/// biggest thing on the sheet. Owns its own focus state.
private struct FuelBigAmountField: View {
    let label: String
    let unit: String
    let tint: Color
    var autoFocus = false
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            FuelEyebrow(text: label)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                TextField(
                    label,
                    text: $text,
                    prompt: Text("0").foregroundStyle(Theme.Colors.muted.opacity(0.5))
                )
                .keyboardType(.numberPad)
                .focused($isFocused)
                .font(Theme.Typography.numeralLarge())
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 180)

                Text(unit)
                    .font(Theme.Typography.unit)
                    .foregroundStyle(Theme.Colors.muted)
            }

            Capsule()
                .fill(tint.opacity(isFocused ? 0.6 : 0.28))
                .frame(width: 220, height: 2)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if autoFocus { isFocused = true }
        }
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

    private var parsedAmount: Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Unit + hue follow the goal (same inline "g"/"ml" convention as the rest of this file).
    private var unit: String { goalType == .protein ? "g" : "ml" }
    private var tint: Color { goalType == .protein ? Theme.Colors.Ring.protein : Theme.Colors.Ring.water }

    var body: some View {
        NavigationStack {
            // One job: type a number. It is set at `numeralLarge` in the goal's hue with a unit and an
            // underline, instead of a stock `Form` row (a 17pt system field on `#000`).
            VStack {
                Spacer(minLength: 0)
                FuelBigAmountField(label: fieldLabel, unit: unit, tint: tint, autoFocus: true, text: $text)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background.ignoresSafeArea())
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
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        // Toolbar Cancel/Save would otherwise render system blue (no root tint is set app-wide yet).
        .tint(Theme.Colors.accent)
    }
}

// MARK: - Kitchen Staples supporting views

/// One saved `KitchenStaple` row, as part of the staples card. The main area is the frequent action
/// — tap to log its protein straight to today's Protein goal — and it says what it will log (the
/// trailing "+25 g" pill). Delete is the rare action, so it sits behind a 44pt "more" menu instead
/// of being permanent, always-visible chrome 12pt from the log target (better-layout 3.4); it is
/// still one visible control, two taps, and never a hidden long-press. The whole card no longer
/// nests a second surface per row: rows are separated by hairlines inside one card.
private struct FuelKitchenStapleRow: View {
    let staple: KitchenStaple
    let onLog: () -> Void
    let onDelete: () -> Void

    private var grams: Int { Int(staple.proteinG.rounded()) }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onLog) {
                HStack(spacing: Theme.Spacing.sm) {
                    IconBadge(systemName: "refrigerator", tint: Theme.Colors.Ring.protein, size: .small)

                    Text(staple.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    FuelAmountPill(amount: "+\(grams)", unit: "g", color: Theme.Colors.Ring.protein)
                }
                .padding(.leading, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: FuelMetrics.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(staple.name), \(grams)g \(Copy.fuel.proteinLabel.lowercased())")
            .accessibilityAddTraits(.isButton)

            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label(Copy.common.delete, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Copy.common.delete)
        }
    }
}

/// Add-a-staple form (spec §10: "user saves 10-20 staples once"). File-scoped, mirrors
/// `ManualAmountSheet`'s own themed-canvas + toolbar Save/Cancel convention in this same file.
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
            // Two labelled fields on the app's own dark canvas, in `Theme` chrome, instead of a
            // stock `Form` (system grouped background + system row fill + 17pt system type).
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                fieldGroup(label: Copy.fuel.kitchenStapleNameFieldLabel) {
                    TextField(Copy.fuel.kitchenStapleNameFieldLabel, text: $name)
                        .focused($focusedField, equals: .name)
                        .fuelFieldChrome()
                }
                fieldGroup(label: Copy.fuel.kitchenStapleProteinFieldLabel) {
                    TextField(Copy.fuel.kitchenStapleProteinFieldLabel, text: $proteinText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .protein)
                        .fuelFieldChrome()
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.background.ignoresSafeArea())
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
    }

    private func fieldGroup<Field: View>(label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            FuelEyebrow(text: label)
            field()
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
                .background(Theme.Colors.background.ignoresSafeArea())
                .navigationTitle(Copy.fuel.barcodeScanTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.common.cancel, action: onDismiss)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
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
            // `SwiftUI.` is required: this module declares its own `ProgressView` screen, which
            // otherwise shadows the spinner and mounts the whole Progress tab here (better-ui BRK-01).
            SwiftUI.ProgressView()
                .controlSize(.large)
                .tint(Theme.Colors.accent)
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
                    .overlay(Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))

                // White 13pt text straight over live camera video had no backing and a ~16pt
                // target: it gets the same capsule as the instruction above and a 44pt floor.
                Button {
                    useManualEntryFallback = true
                } label: {
                    Text(Copy.fuel.barcodeManualEntryTitle)
                        .font(Theme.Typography.captionEmphasized)
                        .foregroundStyle(Theme.Colors.text)
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(minHeight: Theme.Metrics.minTapTarget)
                        .background(Theme.Colors.surface.opacity(0.9), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Colors.hairlineStrong, lineWidth: Theme.Metrics.edgeWidth))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
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
                .fuelFieldChrome()

            PrimaryButton(title: Copy.fuel.barcodeManualEntrySubmitLabel, isEnabled: !manualBarcodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                handleScanned(manualBarcodeText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        // One 16pt margin (the old form padded 24 on the stack and 24 again on the field).
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Scan result: product identity (title + brand) at the top, the protein amount as the hero
    /// numeral in protein's hue, one full-width Log button. Three things, in that order.
    private func resultView(for product: BarcodeProduct) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.xs) {
                Text(product.name ?? Copy.fuel.barcodeUnknownProductLabel)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                if let brand = product.brand {
                    Text(brand)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }

            if let grams = product.proteinGramsPerServing {
                let rounded = Int(grams.rounded())
                VStack(spacing: Theme.Spacing.xxs) {
                    FuelNumeral(value: rounded, suffix: "g", size: .hero, tint: Theme.Colors.Ring.protein)
                    Text(proteinPerServingCaption(grams: rounded))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.fuel.barcodeResultProteinLabel(grams: rounded))

                Spacer(minLength: 0)

                PrimaryButton(title: Copy.fuel.barcodeLogButtonLabel) {
                    onLogged(grams, product.barcode)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `Copy.fuel.barcodeResultProteinLabel` is one whole sentence ("12g protein per serving"). The
    /// number is already the hero above, so this shows only the descriptive remainder rather than
    /// repeating "12g" at 13pt directly under a 64pt "12 g". Falls back to the full sentence if the
    /// copy is ever reworded so it no longer starts with the number.
    private func proteinPerServingCaption(grams: Int) -> String {
        let full = Copy.fuel.barcodeResultProteinLabel(grams: grams)
        let leading = "\(grams)g"
        guard full.hasPrefix(leading) else { return full }
        let remainder = full.dropFirst(leading.count).trimmingCharacters(in: .whitespaces)
        return remainder.isEmpty ? full : remainder
    }

    private func servingSizeForm(for product: BarcodeProduct) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            Text(Copy.fuel.barcodeServingPromptTitle(productName: product.name ?? Copy.fuel.barcodeUnknownProductLabel))
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.sm) {
                FuelBigAmountField(
                    label: Copy.fuel.barcodeServingGramsFieldLabel,
                    unit: "g",
                    tint: Theme.Colors.Ring.protein,
                    autoFocus: true,
                    text: $manualServingGrams
                )

                // Live consequence of the number being typed, in protein's hue and the headline
                // weight — the answer to "what will this log?" (was a 13pt muted caption).
                if let grams = computedServingProtein(for: product) {
                    Text(Copy.fuel.barcodeServingProteinPreview(grams: Int(grams.rounded())))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.Ring.protein)
                }
            }

            Spacer(minLength: 0)

            PrimaryButton(title: Copy.fuel.barcodeLogButtonLabel, isEnabled: computedServingProtein(for: product) != nil) {
                guard let grams = computedServingProtein(for: product) else { return }
                onLogged(grams, product.barcode)
            }
        }
        .padding(Theme.Spacing.md)
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
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.md) {
                // A caution, not a failure state to be ashamed of: `warning` (not `danger`) and a
                // calm retry below. The same tinted disc every other "moment" icon uses.
                IconBadge(systemName: "exclamationmark.triangle.fill", tint: Theme.Colors.warning, size: .large)
                Text(message)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            PrimaryButton(title: Copy.fuel.barcodeRetryButtonLabel) {
                scannedBarcode = nil
                lookupState = .scanning
            }
        }
        .padding(Theme.Spacing.md)
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
