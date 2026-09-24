// SettingsView.swift
// App / Features / Settings
//
// Owned by: this session's task (orchestrator batch, 2026-09-22; design pass 2026-09-23). Do not
// edit from another session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §15 (Screens: "... Settings ..."), §5.13 (Coach Voice — picker, switchable
// anytime), §3/§9.4 (Workout-gym Tier A verification needs a saved, confirmed `Gym` — this screen
// owns the manual CRUD half of that; live dwell verification is `GymVerifier`, called elsewhere),
// §6/§25.1 (NFC tag setup: "app maps it to an action in one screen"), §21 (Monetization & Paywall —
// tiers, "restore purchases visible" is an App Review requirement per §24), §25.6 (In-app store
// behavior — "Settings → Gear, contextual offers ..."), §24 (Safety — privacy visibility), §5.10
// (★ Bedtime Gate & Sunrise Alarm — this screen's entry points into both setup screens), §5.17
// (Trophy Case & Cosmetics — this screen's entry points into both), §20.2/§27 (Always-Allowed
// immunity gotcha), §23 (Instrument from day one — `Analytics.shared.capture`).
//
// ---------------------------------------------------------------------------------------------
// DESIGN PASSES (2026-09-23) — what changed and why. Nothing here was ever rendered (no Mac); every
// size below is arithmetic against a 393 x 852 pt iPhone, 16 pt gutters (361 pt content width).
// Sources: docs/design/composition-audit.md §5.2 + S-2/S-4/S-6/S-8, better-layout-findings.md
// §1.5/§1.12/§2.5/§3.2/§5.4, better-ui-findings.md (DEP-01/05, HIT-02/05, RAD-01/02, ICO-03/05,
// MOT-02), typography-color-findings.md (C3/C7/C9, T5/T7), 2026-ios-trends.md §3.3/§6,
// competitive-research.md §3.10.
//
// PASS 1 rebuilt a stock `List` of eight sections (four coach-voice radio rows first, the Pro pitch
// buried in "Subscription", bare SF Symbol rows, four pushed sub-screens in stock `List`/`Form`s on
// a pure-black `#000` system background) into the structure below. PASS 2 (this one) landed after
// Wave A shipped the shared pieces pass 1 had to fake, and fixes what a read-through found:
//   1. Order = importance x frequency. Always-Allowed warning (when it applies) -> plan/profile
//      hero (tier, streak, the one accent-filled CTA) -> lock + verification setup -> coach voice ->
//      sleep -> rewards (incl. the gear store) -> subscription admin -> about.
//   2. One card language, now the shared one: `.zanoCard` (surface + 1 px top-lit edge + optional
//      on-hue tint wash + a static glow for earned states) and `.zanoWell` (recessed `surface2`).
//      The private `settingsCard`/`SettingsSurface`/`SettingsPressStyle`/`SettingsMotion` stand-ins
//      and their hand-derived edge (`text` @ 0.10) are gone; `Theme.Colors.hairline` is now a real
//      white 12% edge (1.40:1 on `surface`), so rows, dividers and field borders use it directly.
//      Group cards clip their content to the card's corners first (`settingsClippedCard`), because
//      `.zanoCard` does not clip and a pressed first/last row would otherwise square off the corner.
//      Cards sit `Radius.medium`; the plan hero `Radius.large`; nested wells follow `outer - inset`
//      (28 - 16 = 12, 20 - 8 = 12 = `Radius.small`), so corners are concentric.
//   3. Rows carry the shared `IconBadge(.small)` (32 pt circle, `Theme.Colors.wash` disc). It scales
//      with Dynamic Type (the old private badge was a fixed 32 pt), so the row divider's title inset
//      now scales with it (`SettingsRowDivider`) instead of being a fixed 60 pt. Goal-world rows take that goal's `Theme.Colors.Ring` hue; meta rows stay neutral (`text`), the
//      same neutral `SelectableCard` uses. Accent stays reserved for the CTA fill, selection, and
//      earned/confirmed states (S-8). Accent tints are `accentWash`/`accentDim`, never
//      `accent.opacity(...)` (which composites to a drab olive on near-black).
//   4. Coach voice is the brand's personality: a four-tile picker with a live sample-line preview
//      (tap a voice, hear it). The preview line is `headline`-sized now (it was 15 pt italic — the
//      one moment of voice on the screen was body copy). Disabled until a profile exists.
//   5. The plan hero: bigger tier lockup (`titleLarge`), Pro-benefit rows carry the same contextual
//      glyphs the paywall uses (`infinity`, `brain.head.profile`, `person.3.fill`) instead of a
//      generic checklist, and an entitled account gets the earned glow. The Upgrade CTA no longer
//      does nothing silently (see `presentPaywall`).
//   6. Rows show state, not just destinations: Lock sets and Gym setup carry a trailing count once
//      the user has any (a bare numeral — no new copy). An unconfirmed gym wears a warning wash.
//   7. Pressed rows highlight with `hairline` (`surface2` on `surface` is 1.08:1 — a press you
//      could not see). Buttons are the shared capsules (`PrimaryButton(.secondary)`); only the
//      in-card "Confirm" keeps a file-private capsule style: `PrimaryButton` is 52 pt and
//      accent-*filled*, and one accent fill per unconfirmed gym card would spend the accent on
//      every to-do in a list (accent budget: one filled control per view).
//   8. Bug fixes found while reading, all in code that had never compiled: the one-shot location
//      fetcher asked CoreLocation for a fix on *every* authorization callback — including the one
//      delivered when the sheet merely opened — and declared its delegate conformance with an
//      `@preconcurrency extension` spelling the language reference does not list; delegate methods
//      are now `nonisolated` and hop to the main actor, and only act while a fetch is pending.
//   9. Every touch target is >= 44 pt (`Menu` 44 x 44, rows 56 pt, tiles 64 pt, buttons 44-52 pt);
//      every tappable row has a `contentShape`; every custom animation is gated by
//      `@Environment(\.accessibilityReduceMotion)` (the prior wave's rule — preserved, not regressed).
//
// Copy: every string here is an existing `Copy.settings.*` / `Copy.common.*` / `Copy.lockSetup.*`
// member or a `CoachVoice`/`NFCTagSetupInstructions` value from Core. No member was added
// (`SettingsCopy.swift` is outside this task's file list) — see this task's `knownIssues` for the
// strings a follow-up should add (a Lock/verification group header, a "Paywall unavailable" pair,
// unit suffixes for the NFC action summary, and VoiceOver expanded/collapsed values if the
// disclosure groups are ever replaced with custom ones).
//
// Earlier waves' notes that still apply:
//   - Sunrise Alarm / Bedtime Gate / Trophy Case / Cosmetics Shop rows were each added in the
//     2026-09-22 gap-filling pass (all four screens existed with no entry point). Lock Sets
//     (`LockSetupView`, `Copy.lockSetup.screenTitle`) is added now — its own header, and
//     composition-audit offender 7, both call it out as unreachable.
//   - The Always-Allowed warning (`AlwaysAllowedCheck` / `AlwaysAllowedWarningView`) is computed
//     from every saved `LockSet`'s decoded selection via `LockSetManager.shared.selection(for:)`;
//     this file never hand-decodes `LockSet.appTokensBlob`. It is now the first thing on the
//     screen when it applies (better-layout §1.5), and computed once per render instead of twice.
//   - `Gym` and the coach-voice field on `User` have no dedicated manager, so this file writes them
//     directly through `ModelContext`. `GymVerifier` is deliberately not called from here.
//   - NFC setup reuses `NFCReader` / `NFCTagMapper` / `NFCTagSetupInstructions` exactly as that
//     file's header invites ("a settings/setup screen renders these into whatever UI it wants").
//   - `RevenueCat` / `RevenueCatUI` are referenced only inside `#if canImport(...)` (neither is in
//     `project.yml` yet), mirroring `Analytics.swift`'s guarded-import pattern.
//   - `ProgressView` in this module is the Progress *tab* (`ProgressView.swift`), which shadows
//     `SwiftUI.ProgressView` (composition-audit offender 2). Every spinner in this file is spelled
//     `SwiftUI.ProgressView()` for that reason.

import SwiftUI
import SwiftData
import MapKit
// CoreLocation's delegate protocol predates Swift's Sendable/concurrency audit, same situation
// `Core/Sources/Core/Verification/NFCReader.swift` documents for `@preconcurrency import CoreNFC` —
// mirrored here for `GymOneShotLocationFetcher`'s `CLLocationManagerDelegate` conformance below.
@preconcurrency import CoreLocation
// Needed for `FamilyActivitySelection` (`LockSetManager.shared.selection(for:)`'s return type) in
// `alwaysAllowedAssessment` below — same import `App/ZANO/Features/LockSetup/
// AlwaysAllowedWarningView.swift` and `AppPickerView.swift` (this same app target) already carry
// for the same reason.
import FamilyControls
import Core
#if canImport(RevenueCat)
import RevenueCat
#endif
#if canImport(RevenueCatUI)
import RevenueCatUI
#endif

// MARK: - Settings root

struct SettingsView: View {
    @Query private var users: [User]
    @Query private var subscriptions: [Subscription]
    @Query(sort: \GoalEvent.ts, order: .reverse) private var recentEvents: [GoalEvent]
    @Query private var streaks: [Streak]
    // Read only for `alwaysAllowedAssessment` below — same `LockSet` model/sort
    // `MapTagSheet` (this file, further down) already queries for its lock-set picker.
    @Query(sort: \LockSet.name) private var lockSets: [LockSet]
    // Read only for the trailing count on the "Gym setup" row; `GymSetupDetailView` owns the CRUD.
    @Query private var gyms: [Gym]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var errorAlert: SettingsErrorAlert?
    // Seeded once from the persisted flag so a user who already acknowledged the warning in a
    // past session doesn't see it again this session either — see `alwaysAllowedSection` below.
    @State private var alwaysAllowedWarningDismissed = AlwaysAllowedCheck.hasAcknowledgedWarning
    @State private var isRestoringPurchases = false
    @State private var isPaywallPresented = false

    /// The sign-off at the bottom of Settings: the wordmark, the tagline and the build, the way
    /// premium apps close their settings (docs/brand/brand-kit.md).
    private var brandFooter: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZanoWordmark(height: 22, style: .mono(Theme.Colors.muted))
            Text(Copy.brand.taglineEarn)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
            Text(Copy.brand.versionLine(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            ))
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var currentUser: User? { users.first }
    private var subscription: Subscription? { subscriptions.first }
    private var isPro: Bool { currentUser?.planTier == .pro }
    private var currentStreak: Int { streaks.first?.current ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                alwaysAllowedSection
                planCard
                verificationSetupSection
                coachVoiceSection
                dailyRhythmSection
                rewardsSection
                subscriptionSection
                aboutSection
                brandFooter
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            // Animates the Always-Allowed banner in/out (see its `.transition`), nothing else.
            .animation(
                Theme.Motion.standard(reduceMotion: reduceMotion),
                value: alwaysAllowedWarningDismissed
            )
        }
        // The shared backdrop paints `background` behind the safe area (not on the scroll view), so
        // the canvas reaches the bottom edge behind the tab bar instead of falling back to the
        // system background there. No `glow:` — this is an admin screen, not a moment.
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        // No root tint exists yet (`ZANOApp`/`ContentView` belong to another workflow this run), so
        // toolbar buttons, sliders, and menus in this screen would otherwise render system blue.
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.screenTitle)
        .onAppear {
            // Mirrors `ProgressView.swift`'s exact `"<screen>_viewed"` precedent (read, not
            // edited, for the convention) — synchronous, fire-and-forget, so `.onAppear` over
            // `.task` (no async work needed just to fire this).
            Analytics.shared.capture(event: "settings_viewed")
        }
        .settingsErrorAlert($errorAlert)
        .sheet(isPresented: $isPaywallPresented) { paywallSheet }
    }

    // MARK: - Always-Allowed warning (spec §20.2, §27)
    //
    // Computed from every saved `LockSet`'s decoded app selection — a real, on-device signal
    // (not a guess) for whether this warning is actually relevant right now, using the exact
    // public entry points `AlwaysAllowedCheck`/`LockSetManager` already expose for this
    // (`AlwaysAllowedCheck.assessment(for:)`, `LockSetManager.shared.selection(for:)`). Promoted to
    // the top of the screen (it says shielded apps may never actually block — that outranks every
    // preference below it). `AlwaysAllowedWarningView` already has the app's one visible card
    // stroke and is left untouched (it lives in `LockSetup/`, not this file's list).
    @ViewBuilder
    private var alwaysAllowedSection: some View {
        if !alwaysAllowedWarningDismissed {
            // Computed once here; the pre-redesign code evaluated this (and its `LockSet` token
            // decode) twice per render via `shouldShowAlwaysAllowedWarning` + the view's argument.
            let assessment = alwaysAllowedAssessment
            // Reduce Motion: a plain fade; otherwise a fade + slight top-anchored shrink.
            let bannerTransition: AnyTransition = reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
            if assessment.shouldWarn {
                AlwaysAllowedWarningView(assessment: assessment) {
                    AlwaysAllowedCheck.recordAcknowledged()
                    alwaysAllowedWarningDismissed = true
                }
                .transition(bannerTransition)
            }
        }
    }

    /// Every saved `LockSet`'s app/category/web-domain token counts, summed — a user can have
    /// several lock sets, and Always Allowed can plausibly affect any app across all of them, not
    /// just whichever one happens to be currently armed.
    private var alwaysAllowedAssessment: AlwaysAllowedCheck.Assessment {
        let selections = lockSets.map { LockSetManager.shared.selection(for: $0) }
        return AlwaysAllowedCheck.Assessment(
            appCount: selections.reduce(0) { $0 + $1.applicationTokens.count },
            categoryCount: selections.reduce(0) { $0 + $1.categoryTokens.count },
            webDomainCount: selections.reduce(0) { $0 + $1.webDomainTokens.count }
        )
    }

    // MARK: - Plan / profile hero (spec §21, §24)
    //
    // Leads the screen (composition-audit §5.2: "Lead with a profile/plan card — plan tier, streak,
    // 'Upgrade' CTA"). Free: tier + the pitch + the screen's one accent-filled control (a neutral
    // card — the CTA is the focal point). Pro: tier + renewal date on the shared card's *active*
    // treatment (accent wash + a static glow): an entitled account is the earned state, which is
    // exactly what `zanoCard(active:)` is reserved for.
    // Manage/Restore live in the "Subscription" group below (App Review wants Restore visible,
    // spec §24, and it stays visible regardless of tier).

    private var planCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsEyebrow(text: Copy.settings.planLabel)
                    HStack(spacing: Theme.Spacing.xs) {
                        // `titleLarge` (28 pt bold), not `title` (22): the tier is the anchor of the
                        // screen's first card, and a 22 pt line beside 22 pt row headlines is no anchor.
                        Text(isPro ? Copy.settings.planProLabel : Copy.settings.planFreeLabel)
                            .zanoText(.titleLarge)
                            .foregroundStyle(Theme.Colors.text)
                        if isPro {
                            Image(systemName: "checkmark.seal.fill")
                                .font(Theme.Typography.icon(.large))
                                .foregroundStyle(Theme.Colors.accent)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: Theme.Spacing.sm)

                // Same component + same VoiceOver phrasing `TodayView` uses for the pill. Hidden
                // at 0 so a brand-new user isn't greeted by a zero in the app's most prominent card
                // (spec §8: never show an empty/shaming state).
                if currentStreak > 0 {
                    StreakPill(
                        count: currentStreak,
                        accessibilityLabelOverride: CoachVoiceTone.streakClause(
                            currentUser?.coachVoice ?? .hype,
                            streak: currentStreak
                        )
                    )
                }
            }

            if isPro {
                proPlanDetails
            } else {
                proUpsell
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(
            radius: Theme.Radius.large,
            tint: isPro ? Theme.Colors.accent : nil,
            active: isPro
        )
    }

    @ViewBuilder
    private var proPlanDetails: some View {
        if let renewsAt = subscription?.renewsAt {
            HStack {
                Text(Copy.settings.renewsLabel)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                Spacer(minLength: Theme.Spacing.sm)
                Text(renewsAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
            }
            .padding(Theme.Spacing.sm)
            // 28 (hero) - 16 (card padding) = 12 = `Radius.small`, `zanoWell`'s default radius:
            // concentric with the hero card.
            .zanoWell()
            .accessibilityElement(children: .combine)
        }
    }

    /// Glyphs for `Copy.settings.proBenefits`, by position. They are the ones `PaywallView` shows
    /// for the same three benefits (`infinity` / `brain.head.profile` / `person.3.fill`), so the
    /// pitch looks the same on both screens. Positional because `proBenefits` is a plain `[String]`
    /// (it is deliberately the paywall's own titles); a fourth benefit falls back to a checkmark
    /// instead of dropping its badge.
    private static let benefitSymbols = ["infinity", "brain.head.profile", "person.3.fill"]

    private static func benefitSymbol(at index: Int) -> String {
        benefitSymbols.indices.contains(index) ? benefitSymbols[index] : "checkmark"
    }

    /// Free-tier upsell (spec §21, §16 P5 "annual plan card"). Repo-wide Copy/API sweep
    /// (2026-09-22): this used to call `Core.PaywallCard` with a guessed initializer that never
    /// matched the real component (a single selectable plan *row*, no benefits list, no CTA), so it
    /// stays a file-local composition built from `Copy.settings.*` and Theme tokens. Benefit badges
    /// are neutral (`text` on a `wash` disc), not accent — accent is spent once, on the CTA below
    /// (`docs/design/typography-color-findings.md` C7: decorative accent dilutes "earned").
    private var proUpsell: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SettingsHairline()

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(Copy.settings.proHeadline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: Theme.Spacing.sm)
                Text(Copy.settings.proPriceLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(Copy.settings.proBenefits.enumerated()), id: \.offset) { index, benefit in
                    HStack(spacing: Theme.Spacing.sm) {
                        SettingsIconBadge(systemImage: Self.benefitSymbol(at: index))
                        Text(benefit)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            PrimaryButton(
                title: Copy.settings.proCtaLabel,
                systemImage: "sparkles",
                action: presentPaywall
            )
        }
    }

    // Cross-module seam (Session 6 `feat/onboarding` — Paywall, spec §17 row 6). The app's own
    // `PaywallView` (`Features/Onboarding/PaywallView.swift`) takes an `OnboardingFlowState` and
    // calls `flowState.advance()` on purchase/skip — there is no onboarding container to advance in
    // a Settings sheet, so a purchase would leave the user stranded on it. RevenueCatUI's own
    // paywall is the standalone answer, so that is what this presents *once RevenueCatUI is linked*
    // (it is not in `project.yml` yet, hence the `canImport` guards, same as `restorePurchases`).
    // Until then the CTA says so out loud instead of doing nothing: a dead primary button was the
    // audit's loudest complaint about Today (composition-audit §2.1). The fallback strings are the
    // generic `Copy.common` pair; a "Plans aren't available yet" pair is a `SettingsCopy.swift`
    // follow-up (outside this file list). `displayCloseButton:` is recalled from RevenueCatUI's
    // API, not compiled against — verify when the package is added.
    private func presentPaywall() {
        #if canImport(RevenueCatUI)
        isPaywallPresented = true
        #else
        errorAlert = SettingsErrorAlert(
            title: Copy.common.somethingWentWrongTitle,
            message: Copy.common.somethingWentWrongMessage
        )
        #endif
    }

    @ViewBuilder
    private var paywallSheet: some View {
        #if canImport(RevenueCatUI)
        // Module-qualified: the app target's own `PaywallView` shadows RevenueCatUI's.
        RevenueCatUI.PaywallView(displayCloseButton: true)
        #else
        EmptyView()
        #endif
    }

    // MARK: - Lock + verification setup (spec §3, §6, §9.4, §25.1)
    //
    // Lock Sets is new here (the screen existed with no entry point anywhere — composition-audit
    // offender 7). Deliberately headerless: `Copy.settings` has no title for this cluster (see
    // this task's `knownIssues`), and it sits directly under the hero where its purpose is obvious.
    //
    // Lock sets and gyms show a trailing count once any exist: a bare numeral (no copy needed) that
    // turns a menu of destinations into a status readout — "3" next to Lock sets says the setup is
    // done without opening it. Hidden at 0 rather than showing a zero (spec §8: no empty/shaming
    // states). The Ring.focus hue is used only as an icon glyph on its own wash disc (a graphic:
    // 3.15:1 there, over the 3:1 graphics bar) and never as text (3.9:1 on `background`, under the
    // 4.5:1 text bar — `Theme.Colors.Ring` doc), so the row's count and title stay `muted`/`text`.

    private var verificationSetupSection: some View {
        SettingsSection(footer: currentUser == nil ? Copy.settings.finishSetupFooter : nil) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.lockSetup.screenTitle,
                    systemImage: "lock.rectangle.stack.fill",
                    tint: Theme.Colors.Ring.focus,
                    value: lockSets.isEmpty ? nil : "\(lockSets.count)"
                ) {
                    LockSetupView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.gymSetupRowLabel,
                    systemImage: "figure.strengthtraining.traditional",
                    tint: Theme.Colors.Ring.workout,
                    value: gyms.isEmpty ? nil : "\(gyms.count)"
                ) {
                    GymSetupDetailView(userID: currentUser?.id)
                }
                .disabled(currentUser == nil)

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.nfcTagSetupRowLabel,
                    systemImage: "wave.3.right.circle.fill",
                    tint: Theme.Colors.Ring.water
                ) {
                    NFCTagSetupDetailView()
                }
            }
        }
    }

    // MARK: - Coach Voice (spec §5.13)

    private var coachVoiceSection: some View {
        SettingsSection(
            title: Copy.settings.coachVoiceSectionTitle,
            footer: Copy.settings.coachVoiceSectionFooter
        ) {
            CoachVoiceCard(selected: currentUser?.coachVoice, onSelect: selectCoachVoice)
                // Same rule as the Gym row above: with no profile yet a tap would silently do
                // nothing (`selectCoachVoice` guards on `currentUser`), so the tiles say so by
                // dimming instead.
                .disabled(currentUser == nil)
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

    // MARK: - Sunrise Alarm + Bedtime Gate entries (spec §5.10)
    //
    // Both screens were fully built in an earlier wave with no entry point anywhere — see this
    // file's header. Neither owns navigation chrome itself (both push cleanly onto this screen's
    // existing `NavigationStack`, same convention `GymSetupDetailView`/`NFCTagSetupDetailView`
    // below already use). Hues are the existing `Ring.sunriseAlarm` / `Ring.sleepOnTime` tokens.

    private var dailyRhythmSection: some View {
        SettingsSection(title: Copy.settings.dailyRhythmSectionTitle) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.sunriseAlarmRowLabel,
                    systemImage: "sunrise.fill",
                    tint: Theme.Colors.Ring.sunriseAlarm
                ) {
                    SunriseAlarmSetupView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.bedtimeGateRowLabel,
                    systemImage: "moon.zzz.fill",
                    tint: Theme.Colors.Ring.sleepOnTime
                ) {
                    BedtimeGateSetupView()
                }
            }
        }
    }

    // MARK: - Rewards: Trophy Case, Cosmetics Shop, Gear store (spec §5.17, §25.6)
    //
    // Trophy Case / Cosmetics Shop: same gap as Sunrise Alarm/Bedtime Gate — both screens exist,
    // fully built, with no entry point until the 2026-09-22 pass. "paintpalette.fill" (not
    // "bag.fill") for the Cosmetics Shop row so it can't be confused with the physical gear
    // store's "bag.fill" below (better-ui ICO-05).
    //
    // The Gear store used to be its own one-row section under its own header; better-layout §2.5
    // says not to give a one-row section a header, and earned-card/shaker offers are rewards, so
    // it now lives here, with its contextual offer (spec §25.6) as a callout directly above it.

    private var rewardsSection: some View {
        SettingsSection(title: Copy.settings.rewardsSectionTitle) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.trophyCaseRowLabel,
                    systemImage: "trophy.fill"
                ) {
                    TrophyCaseView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.cosmeticsShopRowLabel,
                    systemImage: "paintpalette.fill"
                ) {
                    CosmeticsShopView()
                }

                SettingsRowDivider()

                if let offer = contextualGearOffer {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        SettingsIconBadge(systemImage: "gift.fill")
                        Text(offer)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .accessibilityElement(children: .combine)

                    SettingsRowDivider()
                }

                SettingsActionRow(
                    title: Copy.settings.gearRowLabel,
                    systemImage: "bag.fill",
                    accessory: .external
                ) {
                    openURL(SettingsReferenceData.gearStoreURL)
                }
            }
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

    // MARK: - Subscription admin (spec §21, §24)
    //
    // Both rows stay visible for every tier (App Review: "restore purchases visible", spec §24).
    // Restore now shows an in-row spinner while the RevenueCat call runs — it previously gave no
    // feedback at all until an error alert.

    private var subscriptionSection: some View {
        SettingsSection(title: Copy.settings.subscriptionSectionTitle) {
            SettingsGroupCard {
                SettingsActionRow(
                    title: Copy.settings.manageSubscriptionButtonLabel,
                    systemImage: "creditcard.fill",
                    accessory: .external
                ) {
                    openURL(SettingsReferenceData.manageSubscriptionsURL)
                }

                SettingsRowDivider()

                SettingsActionRow(
                    title: Copy.settings.restorePurchasesButtonLabel,
                    systemImage: "arrow.clockwise",
                    accessory: .none,
                    isBusy: isRestoringPurchases
                ) {
                    Task { await restorePurchases() }
                }
            }
        }
    }

    private func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
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

    // MARK: - About (spec §24)

    private var aboutSection: some View {
        SettingsSection(title: Copy.settings.aboutSectionTitle) {
            SettingsGroupCard {
                SettingsRowLabel(
                    title: Copy.settings.versionLabel,
                    systemImage: "info.circle.fill",
                    value: appVersionString,
                    accessory: .none
                )
                .accessibilityElement(children: .combine)

                SettingsRowDivider()

                SettingsActionRow(
                    title: Copy.settings.privacyPolicyButtonLabel,
                    systemImage: "hand.raised.fill",
                    accessory: .external
                ) {
                    openURL(SettingsReferenceData.privacyPolicyURL)
                }
            }
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

private extension View {
    /// The one error-alert shape every screen and sheet in this file shares (4 call sites: root,
    /// Gym Setup, NFC Setup, map-tag sheet — over CLAUDE.md's "three similar call sites" bar).
    func settingsErrorAlert(_ alert: Binding<SettingsErrorAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { alert.wrappedValue != nil },
                set: { isPresented in if !isPresented { alert.wrappedValue = nil } }
            ),
            presenting: alert.wrappedValue
        ) { _ in
            Button(Copy.common.ok, role: .cancel) { alert.wrappedValue = nil }
        } message: { value in
            Text(value.message)
        }
    }
}

// MARK: - Design primitives
//
// Almost everything visual is a Wave A piece now (`zanoCard`/`zanoWell`, `IconBadge`,
// `PressableStyle`, `PrimaryButton`, `zanoBackdrop`, `zanoText`). What is left here is what is
// genuinely Settings-shaped: the row/section layout, the tile picker, and the radar graphic.

/// The two fixed sizes this file needs that `Theme.Metrics` has no token for. Spacing, radii, tap
/// targets, badge diameters and button heights all come from `Theme`.
private enum SettingsMetrics {
    static let fieldHeight: CGFloat = 48
    static let choiceTileHeight: CGFloat = 64
}

/// Field chrome: the shared card recipe at `Radius.small`, >= 48 pt tall.
private struct SettingsFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: SettingsMetrics.fieldHeight)
            .zanoCard(radius: Theme.Radius.small)
    }
}

private extension View {
    /// `zanoCard` for a card that holds *full-bleed* children (a pressed row's highlight, a map).
    /// `zanoCard` paints a background and an edge but does not clip, so the content is clipped to
    /// the card's own continuous corners first; the edge is then drawn over the clipped content.
    func settingsClippedCard(radius: CGFloat = Theme.Radius.medium) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .zanoCard(radius: radius)
    }

    func settingsField() -> some View {
        modifier(SettingsFieldChrome())
    }
}

/// The badge every row uses: the shared `IconBadge(.small)` (32 pt, `wash` disc, scales with
/// Dynamic Type). `tint == nil` means a *meta* row — neutral `text`, the same neutral
/// `SelectableCard` uses for an unselected leader — so the goal hues stay meaningful.
private struct SettingsIconBadge: View {
    let systemImage: String
    var tint: Color? = nil

    var body: some View {
        IconBadge(systemName: systemImage, tint: tint ?? Theme.Colors.text, size: .small)
    }
}

/// Small-caps section label. `isHeader` adds the VoiceOver heading trait (only true section
/// headers set it; the "Plan" label inside the hero card does not).
private struct SettingsEyebrow: View {
    let text: String
    var isHeader = false

    var body: some View {
        // `zanoText(.eyebrow)`: footnote semibold, uppercased, +0.8 pt tracking (T5) — SF only
        // auto-tracks mixed-case runs, so caps need it by hand, and `Font` cannot carry it.
        Text(text)
            .zanoText(.eyebrow)
            .foregroundStyle(Theme.Colors.muted)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

/// Eyebrow header + content + optional caption footer. Gap within the group is `Spacing.xs`; the
/// gap between groups (set by the parent stack) is `Spacing.lg` — 3x, past the 2x proximity rule.
private struct SettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let title {
                SettingsEyebrow(text: title, isHeader: true)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            content
            if let footer {
                Text(footer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}

/// A card that holds a stack of rows; rows are separated with `SettingsRowDivider` by the caller.
private struct SettingsGroupCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsClippedCard()
    }
}

/// Hairline that is exactly one device pixel tall (a literal 1 pt line is 2-3 px on iPhone and
/// reads heavy on a dark card). `Theme.Colors.hairline` is white @ 12% (1.40:1 on `surface`) — the
/// old `surface2 @ 0.8` version measured 1.06:1 and drew nothing.
private struct SettingsHairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

/// Inset row divider, aligned with the row *title* (not the icon badge) so it reads as belonging
/// to the text column. With no `inset` it tracks the badge: 16 + the badge's diameter + 12, where
/// the diameter scales with Dynamic Type exactly as `IconBadge` does (`@ScaledMetric(.body)`,
/// clamped to 1.4x) — a fixed 60 pt inset would drift left of the title once the badge grows.
private struct SettingsRowDivider: View {
    private let inset: CGFloat?

    @ScaledMetric(relativeTo: .body) private var badgeScale: CGFloat = 1

    // Explicit so the memberwise initializer's access level never depends on the private wrapper.
    init(inset: CGFloat? = nil) {
        self.inset = inset
    }

    var body: some View {
        let titleInset = Theme.Spacing.md
            + Theme.Metrics.iconBadgeSmall * min(badgeScale, 1.4)
            + Theme.Spacing.sm
        SettingsHairline()
            .padding(.leading, inset ?? titleInset)
    }
}

/// The visual for a navigation/action row: badge, title, optional trailing value, accessory.
/// >= 56 pt tall (32 pt badge + 2 x `Spacing.sm`), full-width `contentShape` so taps in the empty
/// middle of the row register (better-ui HIT-05). A `value` is a short trailing readout (a count);
/// it is `muted` metadata in tabular digits so it never jiggles as it changes.
private struct SettingsRowLabel: View {
    enum Accessory {
        case chevron
        case external
        case none
    }

    let title: String
    let systemImage: String
    var tint: Color? = nil
    var value: String? = nil
    var accessory: Accessory = .chevron
    var isBusy = false

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            SettingsIconBadge(systemImage: systemImage, tint: tint)

            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let value {
                Text(value)
                    .font(Theme.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.muted)
            }

            trailing
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Metrics.minTapTarget)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var trailing: some View {
        if isBusy {
            // `SwiftUI.ProgressView` explicitly: this module's own `ProgressView` (the Progress
            // tab, `ProgressView.swift`) shadows the unqualified name.
            SwiftUI.ProgressView()
                .controlSize(.small)
                .tint(Theme.Colors.muted)
        } else {
            switch accessory {
            // `Theme.Typography.icon(.small)` is footnote-based, so the accessory tracks the row's
            // text size instead of staying a fixed 13 pt.
            case .chevron:
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            case .external:
                Image(systemName: "arrow.up.right")
                    .font(Theme.Typography.icon(.small))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
            case .none:
                EmptyView()
            }
        }
    }
}

/// Full-row highlight on press (the native grouped-list feel). The highlight is `hairline` (white
/// @ 12%): the old `surface2` was 1.08:1 against the `surface` card, i.e. a press you could not
/// see. `Theme.Motion.press(reduceMotion:)` is a flat 100 ms ease under Reduce Motion — the
/// highlight is information ("the interface heard you"), the spring is not.
private struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.Colors.hairline : Color.clear)
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The "Confirm this gym" control: a compact (>= 44 pt) capsule *inside* a card, tinted rather than
/// filled — `accentWash` + `accentDim` edge + accent label (11.2:1 on the wash). It stays a
/// file-private style on purpose: `PrimaryButton` is 52 pt and accent-*filled*, and a filled accent
/// button per unconfirmed gym card would break the one-accent-fill-per-screen budget (2026-ios-trends
/// A6). A capsule, like every other control in the app since iOS 26's concentric shapes.
private struct SettingsConfirmButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget)
            .background(Theme.Colors.accentWash, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.accentDim, lineWidth: Theme.Metrics.edgeWidth))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(Theme.Motion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// A row that pushes a destination. `destination` is a closure so the pushed screen (and its
/// `@Query`s) is only built when actually navigated to. `value` is the optional trailing readout
/// (see `SettingsRowLabel`).
private struct SettingsNavRow<Destination: View>: View {
    let title: String
    let systemImage: String
    let tint: Color?
    let value: String?
    let destination: () -> Destination

    init(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        value: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint, value: value)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }
}

/// A row that runs an action (open a URL, kick off a restore). `isBusy` swaps the accessory for a
/// spinner and ignores taps without dimming the row.
private struct SettingsActionRow: View {
    let title: String
    let systemImage: String
    var tint: Color? = nil
    var accessory: SettingsRowLabel.Accessory = .external
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(
                title: title,
                systemImage: systemImage,
                tint: tint,
                accessory: accessory,
                isBusy: isBusy
            )
        }
        .buttonStyle(SettingsRowButtonStyle())
        .allowsHitTesting(!isBusy)
    }
}

/// One selectable tile (icon over label). Selected = `accentWash` fill + a 1.5 pt accent stroke
/// (`strokeBorder`, so no layout shift) + accent glyph; unselected = `surface2` + `hairline`.
/// Serves the coach-voice picker (four across) and the NFC tag-kind grid (3 x 2). It is *not*
/// `SelectableCard`: that is a full-width horizontal card (leader + title + subtitle + radio), and
/// four of those would put back the ~300 pt of stacked voice rows this screen replaced; a tile is
/// the same selected/unselected language at a quarter of the footprint. Disabled tiles dim.
private struct SettingsChoiceTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(isSelected ? Theme.Colors.interactive : Theme.Colors.muted)
                    .frame(height: 24)
                Text(title)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.choiceTileHeight)
            // Selection is chrome, so it's white (decision 2026-09-24: green only for earned states).
            .background(isSelected ? Theme.Colors.interactiveWash : Theme.Colors.surface2, in: shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.interactive : Theme.Colors.hairline,
                    lineWidth: isSelected ? 1.5 : Theme.Metrics.edgeWidth
                )
            )
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.pressable(scale: 0.96))
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One selectable list row (optional leading badge, title, trailing radio). Used where the options
/// are too many or too wordy for tiles: the map-tag action list and the lock-set list.
private struct SettingsChoiceRow: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Same-family symbol swap (empty ring -> filled check): `.symbolEffect(.replace)`, or a
        // plain cross-fade under Reduce Motion — the split `StreakPill` makes for its flame swap.
        let indicatorTransition: ContentTransition = reduceMotion ? .opacity : .symbolEffect(.replace)
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    SettingsIconBadge(systemImage: systemImage)
                }
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Unselected ring is `muted` (5.6:1 on `surface`), not the 1.4:1 hairline tone —
                // the empty radio is a control and has to be findable. Same glyph pair and sizing
                // as `SelectableCard`'s trailing indicator.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.icon(.large))
                    .foregroundStyle(isSelected ? Theme.Colors.interactive : Theme.Colors.muted)
                    .contentTransition(indicatorTransition)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Concentric-ring graphic (a "radar"): the visual for a geofence radius and an NFC read field.
/// Purely static — no looping pulse, so nothing to gate on Reduce Motion and no idle battery cost.
/// The core disc is `Theme.Colors.wash(tint)` and the accent's rings are `accentDim`: an
/// `accent.opacity(...)` tint composites to a drab olive on near-black (Theme header), and the
/// accent is what the workout and NFC-scan radars are drawn in.
private struct SettingsRadarBadge: View {
    let systemImage: String
    let tint: Color
    var diameter: CGFloat = 132

    var body: some View {
        let ring = tint == Theme.Colors.accent ? Theme.Colors.accentDim : tint.opacity(0.4)
        ZStack {
            Circle().strokeBorder(ring.opacity(0.55), lineWidth: Theme.Metrics.edgeWidth)
            Circle().strokeBorder(ring, lineWidth: Theme.Metrics.edgeWidth).padding(diameter * 0.14)
            Circle().fill(Theme.Colors.wash(tint)).padding(diameter * 0.28)
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.2, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Coach voice card (spec §5.13)

/// Four voice tiles + a live sample-line preview. Selecting a voice writes it immediately (same
/// behavior as the old radio rows) and swaps the preview quote, so the user *hears* the coach they
/// just picked — the delight moment onboarding's voice screen already builds, now revisitable.
/// Nested surfaces sit `Spacing.xs` (8) inside a `Radius.medium` (20) card, so their `Radius.small`
/// (12) corners are exactly concentric (20 - 8 = 12).
private struct CoachVoiceCard: View {
    let selected: CoachVoice?
    let onSelect: (CoachVoice) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // Four equal columns: (361 - 16 inset - 3 x 8 gap) / 4 = ~80 pt each; the longest name
            // ("Tough Love", 13 pt semibold ~ 66 pt) fits, and `SettingsChoiceTile` allows two
            // lines + a 0.8 scale floor if a localized name doesn't.
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(CoachVoice.allCases, id: \.self) { voice in
                    SettingsChoiceTile(
                        title: voice.displayName,
                        systemImage: voice.settingsSymbol,
                        isSelected: selected == voice
                    ) {
                        onSelect(voice)
                    }
                }
            }

            if let selected {
                preview(for: selected)
            }
        }
        .padding(Theme.Spacing.xs)
        .zanoCard()
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func preview(for voice: CoachVoice) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        // The sample line is the spec §5.13 line verbatim (`CoachVoice.sampleLine`); curly quotes
        // are punctuation around it, not copy. It is `headline` (17 pt), not 15 pt italic body: the
        // coach's voice is the one moment of personality on this screen and it was set like a
        // footnote. Height is held at two lines' worth (2 x 22 + 2 x 12 = 68 -> 72) so switching
        // between a one-line and a two-line voice doesn't jolt the layout below; it still grows
        // if Dynamic Type needs a third line.
        return Text("\u{201C}\(voice.sampleLine)\u{201D}")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 72)
            .background(Theme.Colors.background, in: shape)
            .overlay(shape.strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(voice.displayName), \(voice.sampleLine)")
    }
}

private extension CoachVoice {
    /// Reuses the coach-pack glyph vocabulary `CosmeticsShopView` already defines
    /// (`megaphone.fill` / `flame.fill` / `leaf.fill` / `chart.bar.fill`) so a voice looks the same
    /// wherever it appears (better-ui ICO-03).
    var settingsSymbol: String {
        switch self {
        case .hype: "megaphone.fill"
        case .toughLove: "flame.fill"
        case .chill: "leaf.fill"
        case .data: "chart.bar.fill"
        }
    }
}

private extension NFCTagKind {
    var settingsSymbol: String {
        switch self {
        case .sunrise: "sunrise.fill"
        case .bottle: "drop.fill"
        case .shaker: "fork.knife"
        case .desk: "desktopcomputer"
        case .gymBag: "figure.strengthtraining.traditional"
        case .custom: "wave.3.right"
        }
    }

    /// The goal ring hue the tag's placement belongs to; `nil` (neutral) for a custom tag.
    var settingsTint: Color? {
        switch self {
        case .sunrise: Theme.Colors.Ring.sunriseAlarm
        case .bottle: Theme.Colors.Ring.water
        case .shaker: Theme.Colors.Ring.protein
        case .desk: Theme.Colors.Ring.focus
        case .gymBag: Theme.Colors.Ring.workout
        case .custom: nil
        }
    }
}

// MARK: - Gym Setup (spec §3, §9.4)

/// CRUD for saved `Gym` rows. Does not call `GymVerifier` (a system contract owned by dwell
/// tracking during a live visit) — see this file's header note.
///
/// Was a stock `List` of text rows with an always-visible 13 pt "Confirm" text button and a
/// swipe-only delete. Now: a designed empty state, one card per gym (name, radius, a status pill,
/// and — only while unconfirmed — a full-width 44 pt-plus "Confirm" button, since confirming is
/// what makes a gym count for Tier A verification), and delete behind a visible `Menu` (plus a
/// context menu) instead of an undiscoverable swipe.
private struct GymSetupDetailView: View {
    let userID: UUID?

    // Sorted in a computed property, not via `@Query(sort:)`, because `Gym.name` is `String?`
    // (`Core/Sources/Core/Models/Gym.swift`) and this session has no Mac/compiler available to
    // verify SwiftData's `SortDescriptor` handling of an optional-Comparable key path on this SDK
    // version — sorting the already-fetched array in plain Swift sidesteps the question entirely.
    @Query private var gyms: [Gym]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAddingGym = false
    @State private var pendingDeletion: Gym?
    @State private var errorAlert: SettingsErrorAlert?
    /// Bumped when a gym is confirmed, for the success haptic (spec §15: "haptics on every
    /// verified event" — a confirmed gym is what makes workouts verifiable, spec §9.4).
    @State private var confirmTick = 0

    private var sortedGyms: [Gym] {
        gyms.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        ScrollView {
            if gyms.isEmpty {
                emptyState
            } else {
                gymList
            }
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: confirmTick)
        .navigationTitle(Copy.settings.gymSetupTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        .settingsErrorAlert($errorAlert)
    }

    // MARK: Empty state (competitive-research §3.10: context, one next step, a visual)

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SettingsRadarBadge(systemImage: "mappin.and.ellipse", tint: Theme.Colors.Ring.workout)

            VStack(spacing: Theme.Spacing.xs) {
                Text(Copy.settings.gymEmptyTitle)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .multilineTextAlignment(.center)
                Text(Copy.settings.gymEmptyMessage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(
                title: Copy.settings.gymAddButtonLabel,
                systemImage: "plus",
                isEnabled: userID != nil
            ) {
                isAddingGym = true
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: Gym cards

    private var gymList: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(sortedGyms) { gym in
                gymCard(gym)
            }
        }
        .padding(Theme.Spacing.md)
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: gyms.count)
    }

    private func gymCard(_ gym: Gym) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                SettingsIconBadge(
                    systemImage: "figure.strengthtraining.traditional",
                    tint: Theme.Colors.Ring.workout
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(gym.name ?? Copy.settings.gymUnnamedLabel)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detailLine(for: gym))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                    statusPill(confirmed: gym.confirmed)
                        .padding(.top, Theme.Spacing.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                removeMenu(for: gym)
                    // Pull the 44 pt target back so the glyph, not the box, aligns to the card's
                    // trailing padding (visual stays put, target stays 44 pt).
                    .padding(.trailing, -Theme.Spacing.sm)
                    .padding(.top, -Theme.Spacing.xs)
            }

            if !gym.confirmed {
                Button(Copy.settings.gymConfirmButtonLabel) { confirm(gym) }
                    .buttonStyle(SettingsConfirmButtonStyle())
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // An unconfirmed gym does not count for Tier A verification, so its card wears the warning
        // wash ("needs attention", not "failed": `warning`, never `danger` — typography-color C9)
        // and reads as a to-do from across the list; a confirmed gym is a plain card.
        .zanoCard(tint: gym.confirmed ? nil : Theme.Colors.warning)
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = gym
            } label: {
                Label(Copy.common.delete, systemImage: "trash")
            }
        }
    }

    private func detailLine(for gym: Gym) -> String {
        let radius = Copy.settings.gymRadiusFieldLabel(meters: gym.radiusMeters)
        return gym.autoDetected ? "\(radius) · \(Copy.settings.gymAutoDetectedLabel)" : radius
    }

    /// Confirmed = accent (earned/complete); unconfirmed = warning (needs attention). Both are a
    /// glyph + a word, never hue alone (2026-ios-trends A1: "glyph-first").
    private func statusPill(confirmed: Bool) -> some View {
        let tint = confirmed ? Theme.Colors.accent : Theme.Colors.warning
        return HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(Theme.Typography.icon(.xsmall))
                .accessibilityHidden(true)
            Text(confirmed ? Copy.settings.gymConfirmedLabel : Copy.settings.gymUnconfirmedLabel)
                .font(Theme.Typography.captionEmphasized)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        // `wash`, not `tint.opacity(0.14)`: for the accent that opacity tint composites to olive.
        .background(Theme.Colors.wash(tint), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func removeMenu(for gym: Gym) -> some View {
        Menu {
            Button(role: .destructive) {
                pendingDeletion = gym
            } label: {
                Label(Copy.common.delete, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.muted)
                .minTapTarget()
        }
        .accessibilityLabel(Copy.common.delete)
    }

    // MARK: Persistence (unchanged)

    private func confirm(_ gym: Gym) {
        gym.confirmed = true
        do {
            try modelContext.save()
            confirmTick += 1
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

/// Add-a-gym flow: location first (a live map with the geofence circle once a fix exists), then
/// radius (a 50-500 m slider in 10 m steps — the old `Stepper` needed up to 45 taps to cross the
/// range), then name. Save is disabled until a coordinate has actually been captured —
/// `Gym.lat`/`Gym.lng` are non-optional (`Core/Sources/Core/Models/Gym.swift`), so there is no
/// meaningful placeholder coordinate to fall back to; the accent "Use current location" button is
/// the screen's only primary action until then, which explains *why* Save is greyed out
/// (better-layout §1.12).
private struct AddGymSheet: View {
    let onSave: (String, CLLocationCoordinate2D, Int) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var radius: Double = 150
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLocating = false
    @State private var locationErrorMessage: String?
    @State private var locateSuccessTick = 0
    // Created on the first tap, not as the property's default value: a `@State` default is
    // re-evaluated on every re-init of this view (each parent update while the sheet is up) and
    // would build, then discard, a `CLLocationManager` each time. Kept in `@State` afterwards so
    // a second tap reuses the same manager.
    @State private var fetcher: GymOneShotLocationFetcher?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    locationBlock
                    radiusBlock
                    nameBlock
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .zanoBackdrop()
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
        // A sheet is a separate presentation: set scheme + tint explicitly rather than relying on
        // inheritance from the presenter (`.preferredColorScheme` propagation into sheets is not
        // verified on device — typography-color-findings §7).
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: locateSuccessTick)
        .sensoryFeedback(.selection, trigger: Int(radius))
    }

    // MARK: Location

    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            mapCard

            locateButton

            if let locationErrorMessage {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.icon(.xsmall))
                        .accessibilityHidden(true)
                    Text(locationErrorMessage)
                        .font(Theme.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.Colors.danger)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private var mapCard: some View {
        ZStack {
            if let coordinate {
                // No radius chip over the map: the "Radius: 150m" headline sits directly under the
                // map + button (all on one screen at 393 x 852), so a chip repeated the same string
                // twice within ~250 pt. The circle *is* the map's label.
                GymRadiusMap(coordinate: coordinate, radiusMeters: radius)
            } else {
                SettingsRadarBadge(systemImage: "location.fill", tint: Theme.Colors.Ring.workout, diameter: 148)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        // Clipped: the map is full-bleed inside the card, and `zanoCard` does not clip.
        .settingsClippedCard()
    }

    @ViewBuilder
    private var locateButton: some View {
        if isLocating {
            HStack(spacing: Theme.Spacing.xs) {
                SwiftUI.ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Colors.muted)
                Text(Copy.settings.gymLocatingLabel)
            }
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.muted)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.primaryButtonHeight)
            .accessibilityElement(children: .combine)
        } else if coordinate != nil {
            // Already located: re-running it is the second-tier action, so it is the shared
            // secondary capsule; the map above is what confirms success. Only the not-yet-located
            // state gets the accent-filled primary, which is also what explains why Save is off.
            PrimaryButton(
                title: Copy.settings.gymLocateButtonLabel,
                systemImage: "location.fill",
                style: .secondary
            ) {
                Task { await locate() }
            }
        } else {
            PrimaryButton(
                title: Copy.settings.gymLocateButtonLabel,
                systemImage: "location.fill"
            ) {
                Task { await locate() }
            }
        }
    }

    // MARK: Radius

    private var radiusBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.settings.gymRadiusFieldLabel(meters: Int(radius)))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Slider(value: $radius, in: 50...500, step: 10) {
                Text(Copy.settings.gymRadiusFieldLabel(meters: Int(radius)))
            }
            .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Name

    private var nameBlock: some View {
        SettingsSection(title: Copy.settings.gymNameFieldLabel) {
            TextField(
                text: $name,
                prompt: Text(Copy.settings.gymNameFieldPlaceholder).foregroundStyle(Theme.Colors.muted)
            ) {
                Text(Copy.settings.gymNameFieldLabel)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.text)
            .textInputAutocapitalization(.words)
            .settingsField()
        }
    }

    private func locate() async {
        isLocating = true
        locationErrorMessage = nil
        defer { isLocating = false }
        let activeFetcher = fetcher ?? GymOneShotLocationFetcher()
        fetcher = activeFetcher
        do {
            coordinate = try await activeFetcher.fetch()
            locateSuccessTick += 1
        } catch {
            locationErrorMessage = error.localizedDescription
        }
    }
}

/// A muted, non-interactive map centred on the captured fix with the geofence radius drawn as an
/// accent circle — the one place this file shows the user exactly what "radius" means on the
/// ground. `interactionModes: []` + `allowsHitTesting(false)` so it never steals the parent scroll
/// view's drags. The camera re-frames (animated, unless Reduce Motion) whenever the radius or fix
/// changes. Written from MapKit-for-SwiftUI knowledge (iOS 17 `Map(position:interactionModes:)`,
/// `MapCircle`, `MapStyle.standard`) with no Mac to compile against — see this task's
/// `needsVerification`.
private struct GymRadiusMap: View {
    let coordinate: CLLocationCoordinate2D
    let radiusMeters: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, radiusMeters: Double) {
        self.coordinate = coordinate
        self.radiusMeters = radiusMeters
        _position = State(initialValue: .region(Self.region(center: coordinate, radiusMeters: radiusMeters)))
    }

    var body: some View {
        Map(position: $position, interactionModes: []) {
            MapCircle(center: coordinate, radius: radiusMeters)
                .foregroundStyle(Theme.Colors.accent.opacity(0.18))
                .stroke(Theme.Colors.accent, lineWidth: 2)
            // Centre dot, sized as a fraction of the radius so it stays proportionate at any zoom.
            MapCircle(center: coordinate, radius: max(4, radiusMeters * 0.04))
                .foregroundStyle(Theme.Colors.accent)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .onChange(of: [coordinate.latitude, coordinate.longitude, radiusMeters]) { _, _ in
            withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) {
                position = .region(Self.region(center: coordinate, radiusMeters: radiusMeters))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.settings.gymRadiusFieldLabel(meters: Int(radiusMeters)))
        .accessibilityAddTraits(.isImage)
    }

    /// Frames the circle with breathing room; the map is ~345 x 220 pt, so the longitudinal span is
    /// roughly 1.6x the latitudinal one to keep the circle centred and unclipped.
    private static func region(center: CLLocationCoordinate2D, radiusMeters: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 3,
            longitudinalMeters: radiusMeters * 4.8
        )
    }
}

/// One-shot current-location fetch wrapped as `async`, mirroring the `CheckedContinuation` pattern
/// `Core/Sources/Core/Verification/NFCReader.swift` already established for a similar single-shot,
/// user-attended system API. `@MainActor` because `CLLocationManager` is created and driven from
/// SwiftUI's main-actor context, and a `MainActor` class is implicitly `Sendable`, so the delegate
/// hop below can capture `self` safely.
///
/// Two defects fixed in the design pass (all of this was written without a compiler):
///  * `locationManagerDidChangeAuthorization` is delivered once *immediately* whenever a manager's
///    delegate is set — i.e. when the Add Gym sheet merely opened. The old handler answered every
///    authorized callback with `requestLocation()`, so opening the sheet with permission already
///    granted fired an unprompted GPS fix. It now acts only while a `fetch()` is pending.
///  * The conformance was declared `@preconcurrency extension … : CLLocationManagerDelegate`.
///    The language reference lists imports and type/member declarations as `@preconcurrency`
///    targets, not extensions, and the conformance form is `extension T: @preconcurrency P`
///    (SE-0423, Swift 6) — so that placement was at best unverified (`NFCReader.swift` uses the
///    same spelling; flagged in `knownIssues`, not this file's to change). The delegate methods are
///    instead `nonisolated` — which satisfies the protocol whether or not the SDK annotates it —
///    and each hops to the main actor with a `Task` (`write-swift` §4: prefer that to
///    `MainActor.assumeIsolated`, which would trap, not race, if a callback ever arrived off the
///    main thread). Only `Sendable` values cross the hop: a status enum, a coordinate (a struct of
///    two doubles), an `Error`.
///
/// Still unverified on a device: that `requestLocation()` after a fresh `whenInUse` grant reports
/// once, and the `CLAuthorizationStatus` cases below (correct as of recent SDKs).
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

    /// The reaction to an authorization change, only while a fetch is waiting on one. See the type
    /// doc comment for why it must not run unconditionally.
    fileprivate func authorizationDidChange(to status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(.failure(GymLocationError.denied))
        default:
            break
        }
    }

    fileprivate func resume(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension GymOneShotLocationFetcher: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationDidChange(to: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.resume(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(.failure(error)) }
    }
}

// MARK: - NFC Tag Setup (spec §6, §25.1)

/// Lists saved tag mappings, scans + maps a fresh tag, and surfaces
/// `NFCTagSetupInstructions`'s background-read/troubleshooting copy — exactly the job that file's
/// own header comment describes as belonging to "a settings/setup screen (owned elsewhere)".
///
/// Was three sections of caption text with a plain-text "Scan a new tag" button on top. Now leads
/// with the action (a big Scan card — the one accent-filled control), then the user's tags as
/// rows with per-tag icons, then the how-it-works and troubleshooting prose folded into native
/// `DisclosureGroup`s (better-layout §5.4: "prefer a short view that links deeper"). The how-it-works
/// group opens by itself only when the user has no tags yet — when the prose is what they need.
private struct NFCTagSetupDetailView: View {
    @State private var mappings: [NFCTagMapping] = []
    @State private var isScanning = false
    @State private var pendingScan: PendingTagScan?
    @State private var pendingRemoval: NFCTagMapping?
    @State private var errorAlert: SettingsErrorAlert?
    @State private var isHowItWorksExpanded = false
    @State private var isTroubleshootingExpanded = false
    @State private var hasAppliedInitialDisclosure = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var stepBadgeDiameter: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                scanCard

                if !mappings.isEmpty {
                    yourTagsSection
                }

                helpSection(
                    title: Copy.settings.nfcHowItWorksSectionTitle,
                    isExpanded: $isHowItWorksExpanded
                ) {
                    // Multi-line supporting copy: `textSecondary` (11.8:1) with 3 pt of extra
                    // leading via `.paragraph`, not `muted` metadata grey at default leading
                    // (typography-color T5/C15). Same for the step details and tips below.
                    Text(NFCTagSetupInstructions.backgroundReadExplainer)
                        .zanoText(.paragraph)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(NFCTagSetupInstructions.shortcutsAutomationSteps) { step in
                        instructionRow(step)
                    }
                }

                helpSection(
                    title: Copy.settings.nfcTroubleshootingSectionTitle,
                    isExpanded: $isTroubleshootingExpanded
                ) {
                    ForEach(NFCTagSetupInstructions.troubleshooting, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(Theme.Colors.muted)
                                .frame(width: 4, height: 4)
                                .accessibilityHidden(true)
                            Text(tip)
                                .zanoText(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: mappings.count)
        }
        .zanoBackdrop()
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.nfcSetupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reloadMappings()
            if !hasAppliedInitialDisclosure {
                hasAppliedInitialDisclosure = true
                isHowItWorksExpanded = mappings.isEmpty
            }
        }
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
        .settingsErrorAlert($errorAlert)
    }

    // MARK: Scan hero

    /// The card leads with the graphic + the one-line instruction (`nfcScanAlertMessage`, the same
    /// line the system NFC sheet shows) and ends in the screen's single accent-filled button. When
    /// the device has no NFC reader the instruction is swapped for the unavailable message and the
    /// button is disabled — no dead-looking control without an explanation next to it.
    private var scanCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            SettingsRadarBadge(systemImage: "wave.3.right", tint: Theme.Colors.accent)

            Text(NFCReader.isAvailable ? Copy.settings.nfcScanAlertMessage : Copy.settings.nfcUnavailableMessage)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                title: Copy.settings.nfcScanButtonLabel,
                systemImage: "wave.3.right",
                isEnabled: !isScanning && NFCReader.isAvailable
            ) {
                Task { await scan() }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        // No `tint:` wash: the accent radar and the accent-filled button already carry this card,
        // and a third accent use would dilute what accent means (typography-color C7 / trends A6).
        .zanoCard(radius: Theme.Radius.large)
    }

    // MARK: Your tags

    private var yourTagsSection: some View {
        SettingsSection(title: Copy.settings.nfcYourTagsSectionTitle) {
            SettingsGroupCard {
                ForEach(mappings) { mapping in
                    tagRow(mapping)
                    if mapping.id != mappings.last?.id {
                        SettingsRowDivider()
                    }
                }
            }
        }
    }

    private func tagRow(_ mapping: NFCTagMapping) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            SettingsIconBadge(systemImage: mapping.kind.settingsSymbol, tint: mapping.kind.settingsTint)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(mapping.label)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text("\(kindLabel(mapping.kind)) · \(actionSummary(mapping.action))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Menu {
                Button(role: .destructive) {
                    pendingRemoval = mapping
                } label: {
                    Label(Copy.settings.nfcForgetTagButtonLabel, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.muted)
                    .minTapTarget()
            }
            .accessibilityLabel(Copy.settings.nfcForgetTagButtonLabel)
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs)
        .contextMenu {
            Button(role: .destructive) {
                pendingRemoval = mapping
            } label: {
                Label(Copy.settings.nfcForgetTagButtonLabel, systemImage: "trash")
            }
        }
    }

    // MARK: Help (disclosure)

    /// Native `DisclosureGroup` (not a hand-rolled toggle) so VoiceOver announces expanded /
    /// collapsed for free — the copy for a custom "expanded"/"collapsed" value doesn't exist in
    /// `Copy.settings`. The chevron is tinted `muted` (the environment tint is accent).
    private func helpSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // Built once, up front: `DisclosureGroup`'s content closure is `@escaping`, and this
        // helper's `content` parameter is not, so calling `content()` inside it would not compile.
        let inner = content()
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                inner
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.sm)
        } label: {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTapTarget, alignment: .leading)
        }
        .tint(Theme.Colors.muted)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    private func instructionRow(_ step: NFCTagSetupInstructions.Step) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Step badges are neutral (`text` on `surface2`), not accent: they are decoration, and
            // accent means earned/selected/CTA (typography-color-findings C7).
            Text("\(step.id)")
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.text)
                // Scales with the step text it leads (a fixed 24 pt disc clips a scaled numeral).
                .frame(width: stepBadgeDiameter, height: stepBadgeDiameter)
                .background(Theme.Colors.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(step.title)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.text)
                Text(step.detail)
                    .zanoText(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
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

/// The one-screen "map this tag" flow (spec §25.1): choose kind -> choose action (+ amount for
/// Water/Protein, or a `LockSet` for Start Lock) -> name it -> save. Matches
/// `NFCTagSetupInstructions.mapTagInApp`'s four steps exactly.
///
/// Was a stock `Form` of three pickers. Now: a 3 x 2 grid of kind tiles (each with its own glyph,
/// with the placement guidance as the footer under the grid), a radio list of actions, and the
/// amount / lock-set / label controls as themed fields. Picking a kind still pre-fills the
/// suggested action (`NFCTagKind.suggestedAction`) — that logic is unchanged.
private struct MapTagSheet: View {
    let scanResult: NFCScanResult
    let onSaved: () -> Void
    let onCancel: () -> Void

    @Query(sort: \LockSet.name) private var lockSets: [LockSet]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    kindSection
                    actionSection
                    if actionKind == .logWater || actionKind == .logProtein {
                        amountSection
                            .transition(.opacity)
                    }
                    if actionKind == .startLock {
                        lockSetSection
                            .transition(.opacity)
                    }
                    labelSection
                }
                .padding(Theme.Spacing.md)
                .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: actionKind)
            }
            .scrollDismissesKeyboard(.interactively)
            .zanoBackdrop()
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
            .settingsErrorAlert($errorAlert)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        // One selection tick per kind change only: picking a kind also auto-applies its suggested
        // action (`onChange(of: kind)` below), and a second tick for that would double-buzz.
        .sensoryFeedback(.selection, trigger: kind)
    }

    // MARK: Sections

    private var kindSection: some View {
        SettingsSection(
            title: Copy.settings.nfcMapKindSectionTitle,
            footer: NFCTagSetupInstructions.placementGuidance(for: kind)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 3),
                spacing: Theme.Spacing.xs
            ) {
                ForEach(NFCTagKind.allCases) { option in
                    SettingsChoiceTile(
                        title: kindLabel(option),
                        systemImage: option.settingsSymbol,
                        isSelected: kind == option
                    ) {
                        kind = option
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.settings.nfcMapKindFieldLabel)
        }
    }

    private var actionSection: some View {
        SettingsSection(title: Copy.settings.nfcMapActionSectionTitle) {
            SettingsGroupCard {
                ForEach(MapActionKind.allCases) { option in
                    SettingsChoiceRow(
                        title: actionLabel(option),
                        systemImage: actionSymbol(option),
                        isSelected: actionKind == option
                    ) {
                        actionKind = option
                    }
                    if option != MapActionKind.allCases.last {
                        SettingsRowDivider()
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.settings.nfcMapActionFieldLabel)
        }
    }

    private var amountSection: some View {
        SettingsSection(title: Copy.settings.nfcMapAmountFieldLabel) {
            // Big numeral entry (composition-audit §2 offender 3: amounts belong in numeral type),
            // digits only — the unit is implied by the action chosen above.
            TextField(text: $amountText) {
                Text(Copy.settings.nfcMapAmountFieldLabel)
            }
            .font(Theme.Typography.numeralMedium())
            .foregroundStyle(Theme.Colors.text)
            .keyboardType(.numberPad)
            .settingsField()
        }
    }

    private var lockSetSection: some View {
        SettingsSection(title: Copy.settings.nfcMapLockSetFieldLabel) {
            SettingsGroupCard {
                SettingsChoiceRow(
                    title: Copy.settings.nfcMapLockSetNoneLabel,
                    isSelected: selectedLockSetID == nil
                ) {
                    selectedLockSetID = nil
                }
                ForEach(lockSets) { lockSet in
                    SettingsRowDivider(inset: Theme.Spacing.md)
                    SettingsChoiceRow(
                        title: lockSet.name,
                        isSelected: selectedLockSetID == lockSet.id
                    ) {
                        selectedLockSetID = lockSet.id
                    }
                }
            }
        }
    }

    private var labelSection: some View {
        SettingsSection(title: Copy.settings.nfcMapLabelSectionTitle) {
            TextField(
                text: $label,
                prompt: Text(Copy.settings.nfcMapLabelFieldPlaceholder).foregroundStyle(Theme.Colors.muted)
            ) {
                Text(Copy.settings.nfcMapLabelSectionTitle)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.text)
            .textInputAutocapitalization(.words)
            .settingsField()
        }
    }

    // MARK: Logic (unchanged from the pre-redesign file)

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

    /// Glyphs match the rest of the app: `drop.fill` = water and `fork.knife` = protein (the same
    /// symbols `TodayView`/`FuelView` use for those goals), `sunrise.fill` = the Sunrise Alarm row.
    private func actionSymbol(_ option: MapActionKind) -> String {
        switch option {
        case .startLock: "lock.fill"
        case .logWater: "drop.fill"
        case .logProtein: "fork.knife"
        case .logCreatine: "pills.fill"
        case .sunriseKey: "sunrise.fill"
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
