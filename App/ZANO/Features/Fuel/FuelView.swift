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
// deep link, or a quick snack."), §9.1 (Adaptive Goal Engine — today's actual bar comes from
// `AdaptiveGoalEngine.dailyPlan`, not the goal's static `targetValue`), §14 (App Intents Catalog —
// `LogProteinIntent(grams, source)`, `LogWaterIntent(ml, source)`, `QuickRepeatMealIntent(mealId)`).
//
// Reads `Goal`/`GoalEvent`/`Meal` directly via `@Query` (all three are Session 1's frozen models —
// see `Core/Sources/Core/Models`, read in full before writing this file) exactly the way
// `LockSetupView.swift` reads `LockSet` directly: cheap, declarative, display-only. Every *write*
// (logging protein/water, replaying a quick-repeat meal) goes through the App Intents catalog
// (CLAUDE.md: "Every user action is an App Intent... never duplicate the same logic in two
// places"), never a direct `ModelContext` insert — this view has no goal-verification logic of its
// own to duplicate.
//
// SYSTEM CONTRACTS actually used here: none of `LockEngineManager` / `FocusSessionVerifier` /
// `GymVerifier` / `TimeBankEngine` apply to a protein/water screen. `AdaptiveGoalEngine.dailyPlan(
// for:on:)` (exact contract shape) is called to resolve *today's* actual bar for the Protein/Water
// goals — the static `Goal.targetValue` is only a fallback for the (expected, early-app-life) case
// where no `DailyPlan` has been generated yet.
//
// ASSUMED API — `LogProteinIntent` / `LogWaterIntent` / `QuickRepeatMealIntent` (`Core/Sources/
// Core/Intents`, owned by a different agent this batch, spec §14) are not yet on disk. Their shape
// is not guessed from scratch: `LogProteinIntent`/`LogWaterIntent` are called with the *exact*
// property-setting shape `Core/Sources/Core/Verification/NFCTagMapper.swift` (already on disk, a
// different agent's file, read in full before writing this one) already established —
// `var intent = LogProteinIntent(); intent.grams = Int; intent.source = GoalLogSource; try await
// intent.perform()` — reusing that precedent rather than inventing a second one.
// `QuickRepeatMealIntent` has no such precedent yet; its shape here is inferred from spec §14's row
// (`QuickRepeatMealIntent | mealId | Logs remembered meal`) plus the already-built `MealEntity`
// (`Core/Sources/Core/Intents/IntentSupport.swift`) that every other entity-taking intent in that
// file uses instead of a raw `UUID` parameter (`StartFocusIntent.focusGoal: GoalEntity?`, etc.):
// `var intent = QuickRepeatMealIntent(); intent.meal = MealEntity(id:label:); try await
// intent.perform()`. `GoalLogSource` is real and already on disk (`IntentSupport.swift`); this file
// always passes `.manual` (every log here originates from a direct tap inside the Fuel screen, not
// NFC/widget/Siri). Flagged in this task's `decisions`/`knownIssues`.
//
// ASSUMED API — `Copy.fuel.*` / `Copy.common.*` (`Core/Sources/Core/Copy`, not owned by this
// session — see `Core/Sources/Core/Copy/CoachVoice.swift`/`ShieldCopy.swift`, both read in full;
// neither defines a `Copy` aggregate type, and neither does any file on disk yet). This file
// follows the exact precedent `App/ZANO/Features/LockSetup/LockSetupView.swift` already set for
// this exact situation (read in full before writing this file): reference `Copy.<feature>.*` by
// name and list every assumed member here for whoever implements `Copy` next.
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
//   Copy.fuel.quickRepeatSectionTitle: String                   // "Quick Repeats"
//   Copy.fuel.quickRepeatEmptyMealLabel: String                 // fallback meal name
//   Copy.fuel.logFailedTitle: String
//   Copy.common.ok / Copy.common.cancel / Copy.common.save: String   // already assumed by LockSetupView
//
// Quick-snack suggestions (name + grams) and gap-option SF Symbol icons are kept as small,
// file-scoped static reference data instead of routed through `Copy`, following the same
// reasoning `Core/Sources/Core/Verification/NFCTagSetupInstructions.swift` already gives for its
// own plain-text steps: this is a fixed, non-voiced reference list (not persona/coach-voice
// motivational copy — spec §5.13's four voices never apply to "2 eggs, 12g"), so centralizing it
// in `Copy` would add an indirection with no actual voice-variance to justify it. If a future
// session wants these swapped for a real nutrition database, this is the one place to change.

import SwiftUI
import SwiftData
import CoreLocation
import Core

struct FuelView: View {
    @Query(filter: #Predicate<Goal> { $0.active }, sort: \Goal.createdAt)
    private var activeGoals: [Goal]

    @Query private var verifiedEventsToday: [GoalEvent]

    @Query(filter: #Predicate<Meal> { $0.confirmed }, sort: \Meal.ts, order: .reverse)
    private var confirmedMeals: [Meal]

    @Environment(\.openURL) private var openURL

    @State private var proteinPlan: DailyPlan?
    @State private var waterPlan: DailyPlan?
    @State private var activeSheet: FuelSheet?
    @State private var errorAlert: FuelErrorAlert?
    @State private var isLogging = false

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
                    if isGapPlannerEligible {
                        gapPlannerSection
                    }
                    if !quickRepeats.isEmpty {
                        quickRepeatSection
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.fuel.screenTitle)
        .task { await loadDailyPlans() }
        .refreshable { await loadDailyPlans() }
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
                    onCustom: { activeSheet = FuelSheet(goalType: .protein) }
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
        onCustom: @escaping () -> Void
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
            }
            .padding(.horizontal, Theme.Spacing.xxs)
        }
        .disabled(isLogging)
    }

    // MARK: - Gap Planner (spec §5.20)

    private var isGapPlannerEligible: Bool {
        guard proteinGoal != nil else { return false }
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 16 && proteinGapGrams > 0
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
                        title: option.title,
                        detail: "#\(index + 1) · \(option.detail)",
                        icon: option.systemImage,
                        color: Theme.Colors.Ring.protein,
                        status: .pending,
                        action: { Task { await option.action() } }
                    )
                }
            }
        }
    }

    /// Ranked gap-close options (spec §5.20: "ranked by proximity and effort"). Proximity = how
    /// close the option's grams are to the remaining gap; effort is a fixed weight per category
    /// (kitchen staple lowest, quick snack middle, a restaurant trip highest) that breaks ties and
    /// nudges the lower-effort option ahead when two options are similarly close.
    private var gapOptions: [FuelGapOption] {
        let gap = proteinGapGrams
        var options: [FuelGapOption] = []

        if let staple = quickRepeats.min(by: {
            abs($0.proteinGrams - Double(gap)) < abs($1.proteinGrams - Double(gap))
        }) {
            options.append(
                FuelGapOption(
                    title: Copy.fuel.gapOptionStapleTitle,
                    detail: "\(staple.label) · \(Int(staple.proteinGrams))g protein",
                    systemImage: "refrigerator",
                    proximityScore: abs(staple.proteinGrams - Double(gap)),
                    effortWeight: 0,
                    action: { await self.logQuickRepeat(staple) }
                )
            )
        }

        options.append(
            FuelGapOption(
                title: Copy.fuel.gapOptionRestaurantTitle,
                detail: Copy.fuel.gapOptionRestaurantDetail,
                systemImage: "fork.knife",
                // No real menu data source yet (spec §10 territory) — treated as able to hit the
                // gap close to exactly, but weighted with the highest effort (leaving the house).
                proximityScore: 0,
                effortWeight: 10,
                action: { await self.openNearbyRestaurantSearch() }
            )
        )

        if let snack = FuelReferenceData.quickSnacks.min(by: {
            abs($0.grams - gap) < abs($1.grams - gap)
        }) {
            options.append(
                FuelGapOption(
                    title: Copy.fuel.gapOptionSnackTitle,
                    detail: "\(snack.name) · \(snack.grams)g",
                    systemImage: "bolt.fill",
                    proximityScore: Double(abs(snack.grams - gap)),
                    effortWeight: 4,
                    action: { await self.log(goalType: .protein, amount: Double(snack.grams), source: .manual) }
                )
            )
        }

        return options.sorted {
            let lhs = $0.proximityScore + Double($0.effortWeight)
            let rhs = $1.proximityScore + Double($1.effortWeight)
            return lhs < rhs
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

    // MARK: - Quick Repeats (spec §5.19)

    private var quickRepeatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.fuel.quickRepeatSectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(quickRepeats) { repeatMeal in
                        FuelQuickAddChip(
                            title: "\(repeatMeal.label) · \(Int(repeatMeal.proteinGrams))g",
                            color: Theme.Colors.Ring.protein,
                            systemImage: "arrow.counterclockwise"
                        ) {
                            Task { await logQuickRepeat(repeatMeal) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xxs)
            }
        }
        .disabled(isLogging)
    }

    /// Groups recently confirmed meals (spec §5.19: "Meal photos build a personal library") by a
    /// simple item-name signature, keeps only meals repeated at least twice, and ranks candidates
    /// by how close their typical hour-of-day is to right now, then by frequency — a lightweight
    /// stand-in for a real recommendation model, matching this screen's scope (rings + gap
    /// suggestions + quick-repeat chips), not a new ML system.
    private var quickRepeats: [FuelQuickRepeat] {
        var groups: [String: [Meal]] = [:]
        for meal in confirmedMeals.prefix(150) {
            guard meal.proteinG != nil, !meal.items.isEmpty else { continue }
            let signature = meal.items
                .map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .sorted()
                .joined(separator: "|")
            groups[signature, default: []].append(meal)
        }

        let currentHour = Calendar.current.component(.hour, from: .now)
        let candidates: [FuelQuickRepeat] = groups.values.compactMap { meals in
            guard meals.count >= 2, let mostRecent = meals.max(by: { $0.ts < $1.ts }) else { return nil }
            let proteinValues = meals.compactMap(\.proteinG)
            guard !proteinValues.isEmpty else { return nil }
            let avgProtein = proteinValues.reduce(0, +) / Double(proteinValues.count)
            let hours = meals.map { Calendar.current.component(.hour, from: $0.ts) }.sorted()
            let typicalHour = hours[hours.count / 2]
            let label = mostRecent.items.first?.name.capitalized ?? Copy.fuel.quickRepeatEmptyMealLabel
            return FuelQuickRepeat(
                mealID: mostRecent.id,
                label: label,
                proteinGrams: avgProtein,
                occurrenceCount: meals.count,
                typicalHour: typicalHour
            )
        }

        return candidates
            .sorted { lhs, rhs in
                let lhsDistance = hourDistance(lhs.typicalHour, currentHour)
                let rhsDistance = hourDistance(rhs.typicalHour, currentHour)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
            .prefix(6)
            .map { $0 }
    }

    private func hourDistance(_ a: Int, _ b: Int) -> Int {
        let diff = abs(a - b)
        return min(diff, 24 - diff)
    }

    private func logQuickRepeat(_ repeatMeal: FuelQuickRepeat) async {
        isLogging = true
        defer { isLogging = false }
        do {
            var intent = QuickRepeatMealIntent()
            intent.meal = MealEntity(id: repeatMeal.mealID, label: repeatMeal.label)
            _ = try await intent.perform()
        } catch {
            errorAlert = FuelErrorAlert(title: Copy.fuel.logFailedTitle, message: error.localizedDescription)
        }
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

    // MARK: - Daily plan (spec §9.1 Adaptive Goal Engine)

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

/// One ranked Protein Gap Planner suggestion (spec §5.20).
private struct FuelGapOption: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let proximityScore: Double
    let effortWeight: Int
    let action: () async -> Void
}

/// One Quick Repeat candidate (spec §5.19), derived from grouped `Meal` history.
private struct FuelQuickRepeat: Identifiable {
    let mealID: UUID
    let label: String
    let proteinGrams: Double
    let occurrenceCount: Int
    let typicalHour: Int

    var id: UUID { mealID }
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

#Preview {
    NavigationStack {
        FuelView()
    }
    .modelContainer(for: [Goal.self, GoalEvent.self, Meal.self], inMemory: true)
}
