// SettingsView.swift
// App / Features / Settings
//
// Owned by: this session's task (orchestrator batch, 2026-09-22). Do not edit from another
// session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §15 (Screens: "... Settings ..."), §5.13 (Coach Voice — picker, switchable
// anytime), §3/§9.4 (Workout-gym Tier A verification needs a saved, confirmed `Gym` — this screen
// owns the manual CRUD half of that; live dwell verification is `GymVerifier`, called elsewhere),
// §6/§25.1 (NFC tag setup: "app maps it to an action in one screen"), §21 (Monetization & Paywall —
// tiers, "restore purchases visible" is an App Review requirement per §24), §25.6 (In-app store
// behavior — "Settings → Gear, contextual offers ... Sunrise Alarm setup prompting a tag pack,
// reorder prompts..., earned-card shipping prompts at milestones"), §24 (Safety — privacy
// visibility).
//
// Reads `User` / `Subscription` / `Gym` / `Streak` / `GoalEvent` / `LockSet` directly via `@Query`
// — all Session 1's frozen models (`Core/Sources/Core/Models`, read in full before writing this
// file). `Gym` and the coach-voice field on `User` have no dedicated manager in this batch's
// SYSTEM CONTRACTS, so this file writes them directly through `ModelContext` — the same choice
// `App/ZANO/Features/LockSetup/LockSetupView.swift` makes for reading `LockSet` (frozen model, no
// invariant beyond what SwiftData itself enforces). `GymVerifier` (a system contract) is
// deliberately **not** called from this file: its job is live dwell tracking during an active gym
// visit, not managing the saved `Gym` rows this screen's "Gym Setup" entry CRUDs — that's a
// different screen/moment's concern (Today, or a background visit monitor), left as this file's
// one explicit cross-module note rather than a guess at how those wire together.
//
// NFC tag setup reuses `NFCReader` / `NFCTagMapper` / `NFCTagSetupInstructions`
// (`Core/Sources/Core/Verification`, already fully built by another agent this batch — read in
// full before writing this file) exactly as `NFCTagSetupInstructions`'s own header comment invites:
// "Not a SwiftUI view — a settings/setup screen (owned elsewhere) renders these into whatever UI it
// wants." This file is that screen.
//
// ASSUMED API — `LogWaterIntent`/`LogProteinIntent` are not referenced here (no quick-log buttons
// in Settings); `RevenueCat`'s `Purchases` SDK is referenced only inside `#if canImport(RevenueCat)`
// (not yet added to `project.yml` — `docs/dependencies.md`, "Add in: Session 6"), mirroring the
// exact guarded-import pattern `Core/Sources/Core/Analytics/Analytics.swift` already established
// for PostHog/Sentry, so this file compiles cleanly both before and after that package is linked.
//
// ASSUMED API — `PaywallCard` (`Core/Sources/Core/UI/Components`, spec §15's component list, not
// yet on disk / not in this batch's fixed SYSTEM CONTRACTS). Used once, for the Free-tier upsell
// row, with a deliberately simple guessed initializer per this task's own instruction ("if you must
// guess an initializer, keep it simple"):
//
//     PaywallCard(headline: String, benefits: [String], priceLabel: String, ctaTitle: String, onContinue: @escaping () -> Void)
//
// ASSUMED API — `Copy.settings.*` / `Copy.common.*` (`Core/Sources/Core/Copy`, not owned by this
// session). Follows the same precedent `LockSetupView.swift` set: reference `Copy.<feature>.*` by
// name, list every assumed member here. Every Copy member below takes only primitive parameters
// (String/Int/Date) or none — this file always does its own enum-branching locally rather than
// asking a Copy function to accept one of this file's own `private` types, so whoever implements
// `Copy` never needs to know this file's internal types exist.
//
//   Copy.settings.screenTitle: String
//   Copy.settings.coachVoiceSectionTitle / .coachVoiceSectionFooter: String
//   Copy.settings.saveErrorTitle: String
//   Copy.settings.gymSetupRowLabel / .gymSetupTitle: String
//   Copy.settings.gymEmptyTitle / .gymEmptyMessage: String
//   Copy.settings.gymAddButtonLabel / .gymAddSheetTitle: String
//   Copy.settings.gymNameFieldLabel / .gymNameFieldPlaceholder: String
//   Copy.settings.gymRadiusFieldLabel(meters: Int) -> String
//   Copy.settings.gymLocateButtonLabel / .gymLocatingLabel / .gymLocationFailedMessage: String
//   Copy.settings.gymUnnamedLabel: String
//   Copy.settings.gymConfirmedLabel / .gymUnconfirmedLabel / .gymConfirmButtonLabel: String
//   Copy.settings.gymAutoDetectedLabel: String
//   Copy.settings.nfcTagSetupRowLabel / .nfcSetupTitle: String
//   Copy.settings.nfcScanButtonLabel / .nfcScanAlertMessage / .nfcScanFailedTitle: String
//   Copy.settings.nfcUnavailableMessage: String
//   Copy.settings.nfcYourTagsSectionTitle / .nfcHowItWorksSectionTitle / .nfcTroubleshootingSectionTitle: String
//   Copy.settings.nfcMapSheetTitle / .nfcMapKindSectionTitle / .nfcMapKindFieldLabel: String
//   Copy.settings.nfcMapActionSectionTitle / .nfcMapActionFieldLabel / .nfcMapAmountFieldLabel: String
//   Copy.settings.nfcMapLabelSectionTitle / .nfcMapLabelFieldPlaceholder: String
//   Copy.settings.nfcMapLockSetFieldLabel / .nfcMapLockSetNoneLabel: String
//   Copy.settings.nfcKindSunriseLabel / .nfcKindBottleLabel / .nfcKindShakerLabel / .nfcKindDeskLabel / .nfcKindGymBagLabel / .nfcKindCustomLabel: String
//   Copy.settings.nfcActionStartLockLabel / .nfcActionLogWaterLabel / .nfcActionLogProteinLabel / .nfcActionLogCreatineLabel / .nfcActionSunriseKeyLabel: String
//   Copy.settings.nfcForgetTagButtonLabel: String
//   Copy.settings.subscriptionSectionTitle / .planLabel / .renewsLabel: String
//   Copy.settings.planFreeLabel / .planProLabel: String
//   Copy.settings.manageSubscriptionButtonLabel / .restorePurchasesButtonLabel: String
//   Copy.settings.restoreFailedTitle / .restoreUnavailableTitle / .restoreUnavailableMessage: String
//   Copy.settings.proBenefits: [String]
//   Copy.settings.proPriceLabel / .proHeadline / .proCtaLabel: String
//   Copy.settings.gearSectionTitle / .gearRowLabel: String
//   Copy.settings.gearOfferShaker(tapCount: Int) -> String
//   Copy.settings.gearOfferEarnedCard(streakDays: Int) -> String
//   Copy.settings.aboutSectionTitle / .versionLabel / .privacyPolicyButtonLabel: String
//   Copy.settings.finishSetupFooter: String
//   Copy.common.ok / .cancel / .save / .delete: String   // ok/cancel/save already assumed by LockSetupView

import SwiftUI
import SwiftData
// CoreLocation's delegate protocol predates Swift's Sendable/concurrency audit, same situation
// `Core/Sources/Core/Verification/NFCReader.swift` documents for `@preconcurrency import CoreNFC` —
// mirrored here for `GymOneShotLocationFetcher`'s `CLLocationManagerDelegate` conformance below.
@preconcurrency import CoreLocation
import Core
#if canImport(RevenueCat)
import RevenueCat
#endif

struct SettingsView: View {
    @Query private var users: [User]
    @Query private var subscriptions: [Subscription]
    @Query(sort: \GoalEvent.ts, order: .reverse) private var recentEvents: [GoalEvent]
    @Query private var streaks: [Streak]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var errorAlert: SettingsErrorAlert?

    private var currentUser: User? { users.first }
    private var subscription: Subscription? { subscriptions.first }

    var body: some View {
        List {
            coachVoiceSection
            verificationSetupSection
            subscriptionSection
            gearSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.settings.screenTitle)
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

    // MARK: - Coach Voice (spec §5.13)

    private var coachVoiceSection: some View {
        Section {
            ForEach(CoachVoice.allCases, id: \.self) { voice in
                Button {
                    selectCoachVoice(voice)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.displayName)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.text)
                            Text(voice.sampleLine)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        if currentUser?.coachVoice == voice {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(Copy.settings.coachVoiceSectionTitle)
        } footer: {
            Text(Copy.settings.coachVoiceSectionFooter)
        }
    }

    private func selectCoachVoice(_ voice: CoachVoice) {
        guard let currentUser else { return }
        currentUser.coachVoice = voice
        do {
            try modelContext.save()
            SharedDefaults.coachVoice = voice.rawValue
        } catch {
            errorAlert = SettingsErrorAlert(title: Copy.settings.saveErrorTitle, message: error.localizedDescription)
        }
    }

    // MARK: - Gym Setup + NFC Tag Setup entries

    private var verificationSetupSection: some View {
        Section {
            NavigationLink {
                GymSetupDetailView(userID: currentUser?.id)
            } label: {
                Label(Copy.settings.gymSetupRowLabel, systemImage: "figure.strengthtraining.traditional")
            }
            .disabled(currentUser == nil)

            NavigationLink {
                NFCTagSetupDetailView()
            } label: {
                Label(Copy.settings.nfcTagSetupRowLabel, systemImage: "wave.3.right.circle")
            }
        } footer: {
            if currentUser == nil {
                Text(Copy.settings.finishSetupFooter)
            }
        }
    }

    // MARK: - Subscription (spec §21, §24)

    private var subscriptionSection: some View {
        Section {
            HStack {
                Text(Copy.settings.planLabel)
                Spacer()
                Text(currentUser?.planTier == .pro ? Copy.settings.planProLabel : Copy.settings.planFreeLabel)
                    .foregroundStyle(Theme.Colors.muted)
            }

            if currentUser?.planTier == .pro, let renewsAt = subscription?.renewsAt {
                HStack {
                    Text(Copy.settings.renewsLabel)
                    Spacer()
                    Text(renewsAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Theme.Colors.muted)
                }
            }

            Button(Copy.settings.manageSubscriptionButtonLabel) {
                openURL(SettingsReferenceData.manageSubscriptionsURL)
            }

            Button(Copy.settings.restorePurchasesButtonLabel) {
                Task { await restorePurchases() }
            }

            if currentUser?.planTier != .pro {
                PaywallCard(
                    headline: Copy.settings.proHeadline,
                    benefits: Copy.settings.proBenefits,
                    priceLabel: Copy.settings.proPriceLabel,
                    ctaTitle: Copy.settings.proCtaLabel,
                    onContinue: presentPaywall
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } header: {
            Text(Copy.settings.subscriptionSectionTitle)
        }
    }

    private func restorePurchases() async {
        #if canImport(RevenueCat)
        do {
            _ = try await Purchases.shared.restorePurchases()
        } catch {
            errorAlert = SettingsErrorAlert(title: Copy.settings.restoreFailedTitle, message: error.localizedDescription)
        }
        #else
        errorAlert = SettingsErrorAlert(
            title: Copy.settings.restoreUnavailableTitle,
            message: Copy.settings.restoreUnavailableMessage
        )
        #endif
    }

    // TODO(cross-module, Session 6 `feat/onboarding` — Paywall screen, spec §17 row 6): this
    // Settings entry point needs somewhere real to send a Free-tier user once the Paywall screen
    // exists. Presenting RevenueCatUI's paywall directly from here (guarded the same way
    // `restorePurchases` is above) is the most likely real implementation; left as a narrow,
    // explicitly-called-out integration seam rather than a guess at a screen this session doesn't
    // own and RevenueCat isn't linked yet to drive.
    private func presentPaywall() {
        #if canImport(RevenueCat)
        // Real presentation wired once RevenueCatUI is linked (Session 6).
        #endif
    }

    // MARK: - Gear (spec §25.6)

    private var gearSection: some View {
        Section {
            if let offer = contextualGearOffer {
                Text(offer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            Button {
                openURL(SettingsReferenceData.gearStoreURL)
            } label: {
                Label(Copy.settings.gearRowLabel, systemImage: "bag.fill")
            }
        } header: {
            Text(Copy.settings.gearSectionTitle)
        }
    }

    /// One contextual offer at a time (spec §25.6: "You've logged 40 shakes — here's the bottle
    /// that logs itself"; earned-card shipping prompts at streak milestones, spec §25.3). Reads
    /// only already-fetched `@Query` rows — no unbounded new fetch — capped defensively since
    /// `recentEvents` itself is an unbounded history query (flagged in this task's `knownIssues`:
    /// a later session should pre-aggregate this instead of re-scanning full history on appearance).
    private var contextualGearOffer: String? {
        let shakerTaps = recentEvents.prefix(1000).filter { $0.source == .nfc && $0.goal?.type == .protein }.count
        if shakerTaps >= 40 {
            return Copy.settings.gearOfferShaker(tapCount: shakerTaps)
        }
        if let streak = streaks.first, [30, 100, 365].contains(streak.current) {
            return Copy.settings.gearOfferEarnedCard(streakDays: streak.current)
        }
        return nil
    }

    // MARK: - About (spec §24)

    private var aboutSection: some View {
        Section {
            HStack {
                Text(Copy.settings.versionLabel)
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(Theme.Colors.muted)
            }
            Button(Copy.settings.privacyPolicyButtonLabel) {
                openURL(SettingsReferenceData.privacyPolicyURL)
            }
        } header: {
            Text(Copy.settings.aboutSectionTitle)
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - File-scoped supporting types

private struct SettingsErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Small reference URLs. `manageSubscriptionsURL` is Apple's real, documented subscription-
/// management deep link (App Review expects "restore purchases visible", spec §24, and this is the
/// standard way to satisfy the adjacent "manage" affordance without RevenueCat linked yet).
/// `gearStoreURL`/`privacyPolicyURL` are placeholders pending real domains (spec §25.5 names
/// Shopify as the store platform but not a domain) — flagged in this task's `decisions`.
private enum SettingsReferenceData {
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let gearStoreURL = URL(string: "https://gear.zano.app")!
    static let privacyPolicyURL = URL(string: "https://zano.app/privacy")!
}

// MARK: - Gym Setup (spec §3, §9.4)

/// CRUD for saved `Gym` rows. Does not call `GymVerifier` (a system contract owned by dwell
/// tracking during a live visit) — see this file's header note.
private struct GymSetupDetailView: View {
    let userID: UUID?

    // Sorted in a computed property, not via `@Query(sort:)`, because `Gym.name` is `String?`
    // (`Core/Sources/Core/Models/Gym.swift`) and this session has no Mac/compiler available to
    // verify SwiftData's `SortDescriptor` handling of an optional-Comparable key path on this SDK
    // version — sorting the already-fetched array in plain Swift sidesteps the question entirely.
    @Query private var gyms: [Gym]
    @Environment(\.modelContext) private var modelContext

    @State private var isAddingGym = false
    @State private var pendingDeletion: Gym?
    @State private var errorAlert: SettingsErrorAlert?

    private var sortedGyms: [Gym] {
        gyms.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        List {
            if gyms.isEmpty {
                ContentUnavailableView {
                    Label(Copy.settings.gymEmptyTitle, systemImage: "mappin.and.ellipse")
                } description: {
                    Text(Copy.settings.gymEmptyMessage)
                }
            } else {
                ForEach(sortedGyms) { gym in
                    gymRow(gym)
                }
            }
        }
        .navigationTitle(Copy.settings.gymSetupTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingGym = true
                } label: {
                    Label(Copy.settings.gymAddButtonLabel, systemImage: "plus")
                }
                .disabled(userID == nil)
            }
        }
        .sheet(isPresented: $isAddingGym) {
            AddGymSheet(
                onSave: { name, coordinate, radius in
                    isAddingGym = false
                    save(name: name, coordinate: coordinate, radiusMeters: radius)
                },
                onCancel: { isAddingGym = false }
            )
        }
        .confirmationDialog(
            Copy.common.delete,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in if !isPresented { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { gym in
            Button(Copy.common.delete, role: .destructive) { delete(gym) }
            Button(Copy.common.cancel, role: .cancel) { pendingDeletion = nil }
        } message: { gym in
            Text(gym.name ?? Copy.settings.gymUnnamedLabel)
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

    private func gymRow(_ gym: Gym) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(gym.name ?? Copy.settings.gymUnnamedLabel)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                    if gym.autoDetected {
                        Text(Copy.settings.gymAutoDetectedLabel)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                Text(gym.confirmed ? Copy.settings.gymConfirmedLabel : Copy.settings.gymUnconfirmedLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(gym.confirmed ? Theme.Colors.accent : Theme.Colors.warning)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if !gym.confirmed {
                Button(Copy.settings.gymConfirmButtonLabel) { confirm(gym) }
                    .font(Theme.Typography.captionEmphasized)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = gym
            } label: {
                Label(Copy.common.delete, systemImage: "trash")
            }
        }
    }

    private func confirm(_ gym: Gym) {
        gym.confirmed = true
        do {
            try modelContext.save()
        } catch {
            errorAlert = SettingsErrorAlert(title: Copy.settings.saveErrorTitle, message: error.localizedDescription)
        }
    }

    private func save(name: String, coordinate: CLLocationCoordinate2D, radiusMeters: Int) {
        guard let userID else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let gym = Gym(
            userID: userID,
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            radiusMeters: radiusMeters,
            name: trimmedName.isEmpty ? nil : trimmedName,
            autoDetected: false,
            confirmed: true
        )
        modelContext.insert(gym)
        do {
            try modelContext.save()
        } catch {
            errorAlert = SettingsErrorAlert(title: Copy.settings.saveErrorTitle, message: error.localizedDescription)
        }
    }

    private func delete(_ gym: Gym) {
        pendingDeletion = nil
        modelContext.delete(gym)
        do {
            try modelContext.save()
        } catch {
            errorAlert = SettingsErrorAlert(title: Copy.settings.saveErrorTitle, message: error.localizedDescription)
        }
    }
}

/// Error this file raises for the one-shot location fetch below (authorization denied/restricted,
/// or never granted at all).
private enum GymLocationError: Error, LocalizedError {
    case denied

    var errorDescription: String? { Copy.settings.gymLocationFailedMessage }
}

/// Add-a-gym form: name, radius, and a "use current location" one-shot fix via `CLLocationManager`.
/// Save is disabled until a coordinate has actually been captured — `Gym.lat`/`Gym.lng` are
/// non-optional (`Core/Sources/Core/Models/Gym.swift`), so there is no meaningful placeholder
/// coordinate to fall back to.
private struct AddGymSheet: View {
    let onSave: (String, CLLocationCoordinate2D, Int) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var radius: Double = 150
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLocating = false
    @State private var locationErrorMessage: String?
    @State private var fetcher = GymOneShotLocationFetcher()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.settings.gymNameFieldPlaceholder, text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text(Copy.settings.gymNameFieldLabel)
                }

                Section {
                    Stepper(value: $radius, in: 50...500, step: 10) {
                        Text(Copy.settings.gymRadiusFieldLabel(meters: Int(radius)))
                    }
                }

                Section {
                    Button {
                        Task { await locate() }
                    } label: {
                        if isLocating {
                            Text(Copy.settings.gymLocatingLabel)
                        } else if coordinate != nil {
                            Label(Copy.settings.gymLocateButtonLabel, systemImage: "checkmark.circle.fill")
                        } else {
                            Text(Copy.settings.gymLocateButtonLabel)
                        }
                    }
                    .disabled(isLocating)

                    if let locationErrorMessage {
                        Text(locationErrorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.danger)
                    }
                }
            }
            .navigationTitle(Copy.settings.gymAddSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.save) {
                        guard let coordinate else { return }
                        onSave(name, coordinate, Int(radius))
                    }
                    .disabled(coordinate == nil)
                }
            }
        }
    }

    private func locate() async {
        isLocating = true
        locationErrorMessage = nil
        defer { isLocating = false }
        do {
            coordinate = try await fetcher.fetch()
        } catch {
            locationErrorMessage = error.localizedDescription
        }
    }
}

/// One-shot current-location fetch wrapped as `async`, mirroring the `CheckedContinuation` pattern
/// `Core/Sources/Core/Verification/NFCReader.swift` already established for a similar single-shot,
/// user-attended system API. `@MainActor` because `CLLocationManager` is created and driven from
/// SwiftUI's main-actor context here and every delegate callback below is expected to land back on
/// that same thread — the standard, widely-relied-upon (if not contractually documented) behavior
/// for a `CLLocationManager` created and used entirely from the main thread. Written from Apple API
/// knowledge with no Mac/compiler available to verify (this task's `knownIssues`): the exact
/// `CLAuthorizationStatus` cases switched on below are correct as of recent iOS SDKs, but the
/// delegate-callback threading guarantee in particular should get a once-over the first time this
/// builds on a Mac.
@MainActor
private final class GymOneShotLocationFetcher: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func fetch() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                resume(.failure(GymLocationError.denied))
            }
        }
    }

    private func resume(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

// `@preconcurrency` mirrors `NFCReader.swift`'s treatment of `NFCNDEFReaderSessionDelegate`: a
// pre-Swift-6-concurrency-audit ObjC delegate protocol, trusted here on the strength of this type
// being `@MainActor` and only ever driven from the main actor (see the type's doc comment above).
@preconcurrency
extension GymOneShotLocationFetcher: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(.failure(GymLocationError.denied))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        resume(.success(location.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(.failure(error))
    }
}

// MARK: - NFC Tag Setup (spec §6, §25.1)

/// Lists saved tag mappings, scans + maps a fresh tag, and surfaces
/// `NFCTagSetupInstructions`'s background-read/troubleshooting copy — exactly the job that file's
/// own header comment describes as belonging to "a settings/setup screen (owned elsewhere)".
private struct NFCTagSetupDetailView: View {
    @State private var mappings: [NFCTagMapping] = []
    @State private var isScanning = false
    @State private var pendingScan: PendingTagScan?
    @State private var pendingRemoval: NFCTagMapping?
    @State private var errorAlert: SettingsErrorAlert?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await scan() }
                } label: {
                    Label(Copy.settings.nfcScanButtonLabel, systemImage: "wave.3.right")
                }
                .disabled(isScanning || !NFCReader.isAvailable)

                if !NFCReader.isAvailable {
                    Text(Copy.settings.nfcUnavailableMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }

            if !mappings.isEmpty {
                Section(Copy.settings.nfcYourTagsSectionTitle) {
                    ForEach(mappings) { mapping in
                        mappingRow(mapping)
                    }
                }
            }

            Section(Copy.settings.nfcHowItWorksSectionTitle) {
                Text(NFCTagSetupInstructions.backgroundReadExplainer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                ForEach(NFCTagSetupInstructions.shortcutsAutomationSteps) { step in
                    instructionRow(step)
                }
            }

            Section(Copy.settings.nfcTroubleshootingSectionTitle) {
                ForEach(NFCTagSetupInstructions.troubleshooting, id: \.self) { tip in
                    Text(tip)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
        }
        .navigationTitle(Copy.settings.nfcSetupTitle)
        .task { await reloadMappings() }
        .sheet(item: $pendingScan) { scan in
            MapTagSheet(
                scanResult: scan.result,
                onSaved: {
                    pendingScan = nil
                    Task { await reloadMappings() }
                },
                onCancel: { pendingScan = nil }
            )
        }
        .confirmationDialog(
            Copy.settings.nfcForgetTagButtonLabel,
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in if !isPresented { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { mapping in
            Button(Copy.settings.nfcForgetTagButtonLabel, role: .destructive) {
                Task { await remove(mapping) }
            }
            Button(Copy.common.cancel, role: .cancel) { pendingRemoval = nil }
        } message: { mapping in
            Text(mapping.label)
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

    private func instructionRow(_ step: NFCTagSetupInstructions.Step) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(step.id). \(step.title)")
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
            Text(step.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    private func mappingRow(_ mapping: NFCTagMapping) -> some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "wave.3.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                Text("\(kindLabel(mapping.kind)) · \(actionSummary(mapping.action))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            Spacer(minLength: Theme.Spacing.sm)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingRemoval = mapping
            } label: {
                Label(Copy.settings.nfcForgetTagButtonLabel, systemImage: "trash")
            }
        }
    }

    private func kindLabel(_ kind: NFCTagKind) -> String {
        switch kind {
        case .sunrise: Copy.settings.nfcKindSunriseLabel
        case .bottle: Copy.settings.nfcKindBottleLabel
        case .shaker: Copy.settings.nfcKindShakerLabel
        case .desk: Copy.settings.nfcKindDeskLabel
        case .gymBag: Copy.settings.nfcKindGymBagLabel
        case .custom: Copy.settings.nfcKindCustomLabel
        }
    }

    private func actionSummary(_ action: NFCTagAction) -> String {
        switch action {
        case .startLock:
            Copy.settings.nfcActionStartLockLabel
        case .logWater(let ml):
            "\(Copy.settings.nfcActionLogWaterLabel) · \(ml)ml"
        case .logProtein(let grams):
            "\(Copy.settings.nfcActionLogProteinLabel) · \(grams)g"
        case .logCreatine:
            Copy.settings.nfcActionLogCreatineLabel
        case .sunriseKey:
            Copy.settings.nfcActionSunriseKeyLabel
        }
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            let result = try await NFCReader.shared.scanOnce(alertMessage: Copy.settings.nfcScanAlertMessage)
            if await NFCTagMapper.shared.mapping(for: result.tagUUID) != nil {
                await reloadMappings()
            } else {
                pendingScan = PendingTagScan(result: result)
            }
        } catch NFCReaderFailure.cancelled {
            // User backed out of the system sheet — not an error worth surfacing.
        } catch {
            errorAlert = SettingsErrorAlert(title: Copy.settings.nfcScanFailedTitle, message: error.localizedDescription)
        }
    }

    private func reloadMappings() async {
        mappings = await NFCTagMapper.shared.allMappings()
    }

    private func remove(_ mapping: NFCTagMapping) async {
        pendingRemoval = nil
        _ = await NFCTagMapper.shared.removeMapping(for: mapping.id)
        await reloadMappings()
    }
}

/// Wraps `NFCScanResult` (not `Identifiable` itself — a type owned by
/// `Core/Sources/Core/Verification/NFCReader.swift`, another agent's file) for `.sheet(item:)`,
/// same reasoning as `FuelSheet` in `FuelView.swift`: no retroactive conformance on a shared type.
private struct PendingTagScan: Identifiable {
    let result: NFCScanResult
    var id: UUID { result.tagUUID }
}

/// The one-screen "map this tag" flow (spec §25.1): choose kind → choose action (+ amount for
/// Water/Protein, or a `LockSet` for Start Lock) → name it → save. Matches
/// `NFCTagSetupInstructions.mapTagInApp`'s four steps exactly.
private struct MapTagSheet: View {
    let scanResult: NFCScanResult
    let onSaved: () -> Void
    let onCancel: () -> Void

    @Query(sort: \LockSet.name) private var lockSets: [LockSet]

    @State private var kind: NFCTagKind = .custom
    @State private var actionKind: MapActionKind = .logWater
    @State private var amountText: String = "250"
    @State private var selectedLockSetID: UUID?
    @State private var label: String = ""
    @State private var isSaving = false
    @State private var errorAlert: SettingsErrorAlert?

    private enum MapActionKind: String, CaseIterable, Identifiable {
        case startLock, logWater, logProtein, logCreatine, sunriseKey
        var id: String { rawValue }
    }

    private var canSave: Bool {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch actionKind {
        case .startLock: return selectedLockSetID != nil
        case .logWater, .logProtein: return (Int(amountText) ?? 0) > 0
        case .logCreatine, .sunriseKey: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Copy.settings.nfcMapKindSectionTitle) {
                    Picker(Copy.settings.nfcMapKindFieldLabel, selection: $kind) {
                        ForEach(NFCTagKind.allCases) { kindOption in
                            Text(kindLabel(kindOption)).tag(kindOption)
                        }
                    }
                    Text(NFCTagSetupInstructions.placementGuidance(for: kind))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }

                Section(Copy.settings.nfcMapActionSectionTitle) {
                    Picker(Copy.settings.nfcMapActionFieldLabel, selection: $actionKind) {
                        ForEach(MapActionKind.allCases) { option in
                            Text(actionLabel(option)).tag(option)
                        }
                    }
                    if actionKind == .logWater || actionKind == .logProtein {
                        TextField(Copy.settings.nfcMapAmountFieldLabel, text: $amountText)
                            .keyboardType(.numberPad)
                    }
                    if actionKind == .startLock {
                        Picker(Copy.settings.nfcMapLockSetFieldLabel, selection: $selectedLockSetID) {
                            Text(Copy.settings.nfcMapLockSetNoneLabel).tag(UUID?.none)
                            ForEach(lockSets) { lockSet in
                                Text(lockSet.name).tag(Optional(lockSet.id))
                            }
                        }
                    }
                }

                Section(Copy.settings.nfcMapLabelSectionTitle) {
                    TextField(Copy.settings.nfcMapLabelFieldPlaceholder, text: $label)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle(Copy.settings.nfcMapSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.save) { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                if let suggested = kind.suggestedAction {
                    apply(suggested)
                }
            }
            .onChange(of: kind) { _, newValue in
                if let suggested = newValue.suggestedAction {
                    apply(suggested)
                }
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
    }

    private func apply(_ action: NFCTagAction) {
        switch action {
        case .startLock:
            actionKind = .startLock
        case .logWater(let ml):
            actionKind = .logWater
            amountText = String(ml)
        case .logProtein(let grams):
            actionKind = .logProtein
            amountText = String(grams)
        case .logCreatine:
            actionKind = .logCreatine
        case .sunriseKey:
            actionKind = .sunriseKey
        }
    }

    private func kindLabel(_ kind: NFCTagKind) -> String {
        switch kind {
        case .sunrise: Copy.settings.nfcKindSunriseLabel
        case .bottle: Copy.settings.nfcKindBottleLabel
        case .shaker: Copy.settings.nfcKindShakerLabel
        case .desk: Copy.settings.nfcKindDeskLabel
        case .gymBag: Copy.settings.nfcKindGymBagLabel
        case .custom: Copy.settings.nfcKindCustomLabel
        }
    }

    private func actionLabel(_ option: MapActionKind) -> String {
        switch option {
        case .startLock: Copy.settings.nfcActionStartLockLabel
        case .logWater: Copy.settings.nfcActionLogWaterLabel
        case .logProtein: Copy.settings.nfcActionLogProteinLabel
        case .logCreatine: Copy.settings.nfcActionLogCreatineLabel
        case .sunriseKey: Copy.settings.nfcActionSunriseKeyLabel
        }
    }

    private func save() {
        guard let action = resolvedAction() else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapping = NFCTagMapping(id: scanResult.tagUUID, kind: kind, label: trimmedLabel, action: action)
        isSaving = true
        Task {
            await NFCTagMapper.shared.saveMapping(mapping)
            isSaving = false
            onSaved()
        }
    }

    /// `nil` only when `canSave` should already have disabled the Save button — a defensive guard,
    /// not an expected runtime path.
    private func resolvedAction() -> NFCTagAction? {
        let amount = max(0, Int(amountText) ?? 0)
        switch actionKind {
        case .startLock:
            guard let selectedLockSetID else { return nil }
            // v1 simplification: NFC-mapped locks always start in `.full` mode with no specific
            // required goals (matching `NFCTagAction`'s own doc comment: "requiredGoalIDs is
            // usually [] for a tag-triggered lock"). An Earn-mode picker here is a reasonable
            // follow-up, not required by this task's scope.
            return .startLock(lockSetID: selectedLockSetID, mode: .full, requiredGoalIDs: [])
        case .logWater:
            return .logWater(milliliters: amount)
        case .logProtein:
            return .logProtein(grams: amount)
        case .logCreatine:
            return .logCreatine
        case .sunriseKey:
            return .sunriseKey
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [User.self, Subscription.self, GoalEvent.self, Streak.self, Gym.self, LockSet.self], inMemory: true)
}
