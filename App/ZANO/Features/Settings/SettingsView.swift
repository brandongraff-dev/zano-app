// SettingsView.swift
// App / Features / Settings
//
// Owned by: this session's task (orchestrator batch, 2026-09-22; design pass 2026-09-23). Do not
// edit from another session — see CLAUDE.md "Stay strictly inside your assigned file list."
//
// docs/spec.md §15 (Screens: "... Settings ..."), §5.13 (Coach Voice — picker, switchable
// anytime), §3/§9.4 and §6/§25.1 (entry rows into Gym setup and NFC tags — both screens live in
// their own feature folders now), §21 (Monetization & Paywall —
// tiers, "restore purchases visible" is an App Review requirement per §24), §25.6 (In-app store
// behavior — "Settings → Gear, contextual offers ..."), §24 (Safety — privacy visibility), §5.10
// (★ Bedtime Gate & Sunrise Alarm — this screen's entry points into both setup screens), §5.17
// (Trophy Case & Cosmetics — this screen's entry points into both), §20.2/§27 (Always-Allowed
// immunity gotcha), §23 (Instrument from day one — `Analytics.shared.capture`).
//
// ---------------------------------------------------------------------------------------------
// POLISH PASS (2026-09-24) — supersedes the notes below where they disagree:
//   * Hard paywall (spec §21): the Free/"Go Pro"/Upgrade upsell and the RevenueCatUI sheet are gone.
//     The hero is a plan *status* card (ZANO Pro, Active/Free trial, renew/trial-end date, "Manage
//     subscription"). Restore goes through `RevenueCatManager` and refreshes `EntitlementGate`.
//   * New rows: Goals (`GoalsEditorView`), Notifications (Nudges → `NudgeSettingsView`, plus iOS
//     notification settings), Help & feedback, Pause for health reasons (spec §24; real pause via
//     `Core/Retention/HealthPause.swift`, with a status capsule at the top while it's on), Terms of
//     use, Privacy policy, Delete all my data.
//   * Monochrome rows: `SettingsIconBadge` is always `textSecondary` on `surface2`, outline
//     symbols; no per-row ring tints. Disabled = `muted` text, never stacked opacity.
//   * Coach-voice tiles: no border unselected, accent stroke at `Metrics.selectedStroke` selected;
//     the sample quote sits on the card with no recessed box.
//   * Gear store row + offer hidden until `SettingsReferenceData.gearStoreURL` is real.
//   * Confirmations name the thing ("Delete <gym>?", "Remove <tag>?"), ellipsis menus say "More
//     options for <name>", and no alert shows raw `error.localizedDescription` text.
//
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
//   - The coach-voice field on `User` has no dedicated manager, so this file writes it directly
//     through `ModelContext`.
//   - Wave 1A/1B (2026-09-25): Gym setup moved to `Features/GymSetup/GymSetupView.swift` and NFC
//     tag setup to `Features/NFC/NFCTagsView.swift`; this file only links to them (and pushes
//     `GymSetupView` when `AppRouter.isGymSetupPresented` is set by `zano://gym`).
//   - `RevenueCat` / `RevenueCatUI` are referenced only inside `#if canImport(...)` (neither is in
//     `project.yml` yet), mirroring `Analytics.swift`'s guarded-import pattern.
//   - `ProgressView` in this module is the Progress *tab* (`ProgressView.swift`), which shadows
//     `SwiftUI.ProgressView` (composition-audit offender 2). Every spinner in this file is spelled
//     `SwiftUI.ProgressView()` for that reason.

import SwiftUI
import SwiftData
// Needed for `FamilyActivitySelection` (`LockSetManager.shared.selection(for:)`'s return type) in
// `alwaysAllowedAssessment` below — same import `App/ZANO/Features/LockSetup/
// AlwaysAllowedWarningView.swift` and `AppPickerView.swift` (this same app target) already carry
// for the same reason.
import FamilyControls
import Core

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
    // Read only for the trailing count on the "Goals" row; `GoalsEditorView` owns the edits.
    @Query(filter: #Predicate<Goal> { $0.active }) private var activeGoals: [Goal]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var errorAlert: SettingsErrorAlert?
    // Seeded once from the persisted flag so a user who already acknowledged the warning in a
    // past session doesn't see it again this session either — see `alwaysAllowedSection` below.
    @State private var alwaysAllowedWarningDismissed = AlwaysAllowedCheck.hasAcknowledgedWarning
    @State private var isRestoringPurchases = false
    @State private var isConfirmingDeleteAll = false
    @State private var isDeletingData = false
    /// Founder Series card dismissed (spec §5.22: optional, never annoying). Per-device.
    @AppStorage("zano.founderSeriesCard.dismissed") private var founderCardDismissed = false
    /// Mirrors `AutoFocusIntegration.isSetUp` for the row's trailing value; refreshed on appear.
    @State private var autoFocusIsSetUp = AutoFocusIntegration.isSetUp
    @State private var calendarAwarenessOn = false

    /// The sign-off at the bottom of Settings: the wordmark, the tagline and the build, the way
    /// premium apps close their settings (docs/brand/brand-kit.md). The version line is plain
    /// `muted` — no extra opacity stacked on top of an already-quiet token.
    private var brandFooter: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZanoWordmark(height: 12, style: .mono(Theme.Colors.muted))
            Text(Copy.brand.taglineEarn)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
            Text(Copy.brand.versionLine(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            ))
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var currentUser: User? { users.first }
    private var subscription: Subscription? { subscriptions.first }
    private var currentStreak: Int { streaks.first?.current ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Only renders while a health pause is on (spec §24; SettingsSupportViews.swift).
                HealthPauseStatusCapsule()
                alwaysAllowedSection
                planCard
                verificationSetupSection
                coachVoiceSection
                dailyRhythmSection
                rewardsSection
                notificationsSection
                subscriptionSection
                aboutSection
                dataSection
                founderSeriesCard
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
        .tint(Theme.Colors.accent)
        .navigationTitle(Copy.settings.screenTitle)
        .onAppear {
            Analytics.shared.capture(event: "settings_viewed")
            autoFocusIsSetUp = AutoFocusIntegration.isSetUp
        }
        .settingsErrorAlert($errorAlert)
        .confirmationDialog(
            Copy.settings.deleteAllDataConfirmTitle,
            isPresented: $isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button(Copy.settings.deleteAllDataConfirmButtonLabel, role: .destructive) {
                Task { await deleteAllData() }
            }
            Button(Copy.common.cancel, role: .cancel) {}
        } message: {
            Text(Copy.settings.deleteAllDataConfirmMessage)
        }
    }

    // MARK: - Always-Allowed warning (spec §20.2, §27)
    //
    // Computed from every saved `LockSet`'s decoded app selection — a real, on-device signal
    // (not a guess) for whether this warning is actually relevant right now, using the exact
    // public entry points `AlwaysAllowedCheck`/`LockSetManager` already expose for this. Promoted to
    // the top of the screen (it says shielded apps may never actually block — that outranks every
    // preference below it).
    @ViewBuilder
    private var alwaysAllowedSection: some View {
        if !alwaysAllowedWarningDismissed {
            let assessment = alwaysAllowedAssessment
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
    /// several lock sets, and Always Allowed can plausibly affect any app across all of them.
    private var alwaysAllowedAssessment: AlwaysAllowedCheck.Assessment {
        let selections = lockSets.map { LockSetManager.shared.selection(for: $0) }
        return AlwaysAllowedCheck.Assessment(
            appCount: selections.reduce(0) { $0 + $1.applicationTokens.count },
            categoryCount: selections.reduce(0) { $0 + $1.categoryTokens.count },
            webDomainCount: selections.reduce(0) { $0 + $1.webDomainTokens.count }
        )
    }

    // MARK: - Plan status (spec §21 hard paywall)
    //
    // There is no free tier (decision 2026-09-23): anyone who can see this screen is on the trial
    // or paid, so this is a status card, not a pitch. The old "Free / Go Pro / Upgrade" upsell and
    // the RevenueCatUI paywall sheet it opened (which failed without RevenueCatUI linked) are gone.
    //
    // Trial vs paid: nothing in Core stores the trial flag yet. `Subscription.status` is
    // RevenueCat's passthrough string, so "trial" appearing in it is treated as the trial state;
    // otherwise the plan reads "Active". Flagged in this pass's report: a real `periodType` field
    // (RevenueCat `EntitlementInfo.periodType == .trial`) should replace this string check.

    private var isOnTrial: Bool {
        subscription?.status?.lowercased().contains("trial") == true
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    SettingsEyebrow(text: Copy.settings.planLabel)
                    Text(Copy.settings.planProLabel)
                        .zanoText(.titleLarge)
                        .foregroundStyle(Theme.Colors.text)
                    ZanoStatusCapsule(
                        dotColor: Theme.Colors.accent,
                        text: isOnTrial ? Copy.settings.planStatusTrial : Copy.settings.planStatusActive
                    )
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: Theme.Spacing.sm)

                // Hidden at 0 so a brand-new user isn't greeted by a zero (spec §8).
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

            if let renewsAt = subscription?.renewsAt {
                HStack {
                    Text(isOnTrial ? Copy.settings.trialEndsLabel : Copy.settings.renewsLabel)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(renewsAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                }
                .padding(Theme.Spacing.sm)
                .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            Text(Copy.settings.planManagedByAppleNote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                title: Copy.settings.manageSubscriptionButtonLabel,
                systemImage: "arrow.up.right",
                style: .secondary
            ) {
                openURL(SettingsReferenceData.manageSubscriptionsURL)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.large)
    }

    // MARK: - Setup: goals, lock sets, gyms, tags (spec §3, §6, §9.4, §25.1)
    //
    // Rows show state, not just destinations: a trailing count once any exist (hidden at 0 —
    // spec §8, no empty/shaming states). Monochrome badges (polish pass 2026-09-24): the ring hues
    // belong to goal progress, not to a settings menu.

    private var verificationSetupSection: some View {
        SettingsSection(footer: currentUser == nil ? Copy.settings.finishSetupFooter : nil) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.goalsRowLabel,
                    systemImage: "target",
                    value: activeGoals.isEmpty ? nil : "\(activeGoals.count)"
                ) {
                    GoalsEditorView()
                }
                .disabled(currentUser == nil)

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.lockSetup.screenTitle,
                    systemImage: "lock.rectangle.stack",
                    value: lockSets.isEmpty ? nil : "\(lockSets.count)"
                ) {
                    LockSetupView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.gymSetupRowLabel,
                    systemImage: "dumbbell",
                    value: gyms.isEmpty ? nil : "\(gyms.count)"
                ) {
                    GymSetupView()
                }
                .disabled(currentUser == nil)
                // `zano://gym` / `AppRouter.openGymSetup()` land here (Wave 1A).
                .navigationDestination(isPresented: Binding(
                    get: { appRouter.isGymSetupPresented },
                    set: { appRouter.isGymSetupPresented = $0 }
                )) {
                    GymSetupView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.nfcTagSetupRowLabel,
                    systemImage: "wave.3.right"
                ) {
                    NFCTagsView()
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
            errorAlert = SettingsErrorAlert(title: Copy.settings.saveErrorTitle, message: Copy.settings.saveErrorMessage)
        }
    }

    // MARK: - Sunrise Alarm + Bedtime Gate entries (spec §5.10)

    private var dailyRhythmSection: some View {
        SettingsSection(title: Copy.settings.dailyRhythmSectionTitle) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.sunriseAlarmRowLabel,
                    systemImage: "sunrise"
                ) {
                    SunriseAlarmSetupView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.bedtimeGateRowLabel,
                    systemImage: "moon.zzz"
                ) {
                    BedtimeGateSetupView()
                }

                SettingsRowDivider()

                // Spec §5.12 one-tap setup guide (Wave 3L).
                SettingsNavRow(
                    Copy.settings.autoFocusRowLabel,
                    systemImage: "moon.circle",
                    value: autoFocusIsSetUp ? Copy.settings.autoFocusRowValueOn : nil
                ) {
                    AutoFocusGuideView()
                }

                SettingsRowDivider()

                // Today's "light day" card (Wave 2F) asks once; this is the way back on or off.
                HStack(spacing: Theme.Spacing.sm) {
                    SettingsIconBadge(systemImage: "calendar.badge.clock")
                    Toggle(isOn: Binding(
                        get: { calendarAwarenessOn },
                        set: { newValue in Task { await setCalendarAwareness(newValue) } }
                    )) {
                        Text(Copy.settings.calendarAwarenessRowLabel)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                    }
                    .tint(Theme.Colors.accentFill)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: Theme.Metrics.minTapTarget)
            }
        }
        .task { calendarAwarenessOn = await CalendarAwareness.shared.accessState() == .granted }
    }

    private func setCalendarAwareness(_ on: Bool) async {
        if on {
            let granted = (try? await CalendarAwareness.shared.optIn()) ?? false
            if !granted { await CalendarAwareness.shared.optOut() }
            calendarAwarenessOn = granted
            if !granted { errorAlert = SettingsErrorAlert(title: Copy.settings.calendarAwarenessDeniedTitle, message: Copy.settings.calendarAwarenessDenied) }
        } else {
            await CalendarAwareness.shared.optOut()
            calendarAwarenessOn = false
        }
    }

    // MARK: - Rewards: Trophy Case, Cosmetics Shop (spec §5.17)
    //
    // The Gear store row (spec §25.6) and its contextual offer callout are hidden until a real
    // store exists: the row opened a placeholder domain, and the offer pointed at it. Re-enable by
    // setting `SettingsReferenceData.gearStoreURL` to the live store URL — the row and the offer
    // both key off it.

    private var rewardsSection: some View {
        SettingsSection(title: Copy.settings.rewardsSectionTitle) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.trophyCaseRowLabel,
                    systemImage: "trophy"
                ) {
                    TrophyCaseView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.cosmeticsShopRowLabel,
                    systemImage: "paintpalette"
                ) {
                    CosmeticsShopView()
                }

                SettingsRowDivider()

                // Spec §4 v2 referrals (Wave 3K): the code works offline; redeeming says it needs
                // the network until the backend is live.
                SettingsNavRow(
                    Copy.settings.inviteFriendsRowLabel,
                    systemImage: "person.2"
                ) {
                    ReferralView()
                }
                .disabled(currentUser == nil)

                if let gearStoreURL = SettingsReferenceData.gearStoreURL {
                    SettingsRowDivider()

                    if let offer = contextualGearOffer {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            SettingsIconBadge(systemImage: "gift")
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
                        systemImage: "bag",
                        accessory: .external
                    ) {
                        openURL(gearStoreURL)
                    }
                }
            }
        }
    }

    /// One contextual offer at a time (spec §25.6; earned-card prompts at streak milestones,
    /// spec §25.3). Reads only already-fetched `@Query` rows, capped defensively.
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

    // MARK: - Founder Series (spec §5.22)
    //
    // "A 'Building ZANO' feed card (optional)... visible without being annoying." Settings is the
    // quiet place for it (not Today, which is the lock's screen). No founder content URL exists
    // yet, so the card has no button and makes no promise; dismissing it hides it for good. It
    // never links to gear (the Gear row stays hidden until `SettingsReferenceData.gearStoreURL`).

    @ViewBuilder
    private var founderSeriesCard: some View {
        if !founderCardDismissed {
            FounderSeriesCard(
                headline: Copy.founderSeries.defaultHeadline,
                bodyText: Copy.settings.founderCardBody,
                dismissAccessibilityLabel: Copy.founderSeries.dismissAccessibilityLabel,
                onDismiss: {
                    founderCardDismissed = true
                    Analytics.shared.capture(event: "founder_card_dismissed")
                }
            )
            .transition(.opacity)
        }
    }

    // MARK: - Notifications
    //
    // "Nudges" pushes ZANO's own nudge settings (`NudgeSettingsView`: on/off, kinds, quiet hours,
    // the 2/day cap). The second row deep-links to this app's page in the iPhone Settings app
    // (`openNotificationSettingsURLString`, iOS 16+), which still owns sounds/banners/all-off.

    private var notificationsSection: some View {
        SettingsSection(title: Copy.settings.notificationsSectionTitle, footer: Copy.settings.notificationsFooter) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.nudgesRowLabel,
                    systemImage: "bell.badge"
                ) {
                    NudgeSettingsView()
                }

                SettingsRowDivider()

                SettingsActionRow(
                    title: Copy.settings.systemNotificationsRowLabel,
                    systemImage: "bell",
                    accessory: .external
                ) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
    }

    // MARK: - Subscription admin (spec §21, §24 "restore purchases visible")

    private var subscriptionSection: some View {
        SettingsSection(title: Copy.settings.subscriptionSectionTitle) {
            SettingsGroupCard {
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

    /// Goes through `RevenueCatManager` (the only file that talks to the SDK), then refreshes the
    /// hard-paywall gate so a restored subscription takes effect immediately.
    private func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        do {
            let restored = try await RevenueCatManager.shared.restorePurchases()
            await EntitlementGate.shared.refresh()
            errorAlert = restored
                ? SettingsErrorAlert(
                    title: Copy.settings.restoreSucceededTitle,
                    message: Copy.settings.restoreSucceededMessage
                )
                : SettingsErrorAlert(
                    title: Copy.settings.restoreNothingFoundTitle,
                    message: Copy.settings.restoreNothingFoundMessage
                )
        } catch RevenueCatManagerError.notConfigured {
            errorAlert = SettingsErrorAlert(
                title: Copy.settings.restoreUnavailableTitle,
                message: Copy.settings.restoreUnavailableMessage
            )
        } catch {
            errorAlert = SettingsErrorAlert(
                title: Copy.settings.restoreFailedTitle,
                message: Copy.settings.restoreFailedMessage
            )
        }
    }

    // MARK: - About: help, legal, health pause (spec §24)

    private var aboutSection: some View {
        SettingsSection(title: Copy.settings.aboutSectionTitle) {
            SettingsGroupCard {
                SettingsNavRow(
                    Copy.settings.helpRowLabel,
                    systemImage: "questionmark.circle"
                ) {
                    HelpFeedbackView()
                }

                SettingsRowDivider()

                SettingsNavRow(
                    Copy.settings.pauseRowLabel,
                    systemImage: "heart"
                ) {
                    PauseForHealthView()
                }

                SettingsRowDivider()

                SettingsActionRow(
                    title: Copy.settings.termsOfUseButtonLabel,
                    systemImage: "doc.text",
                    accessory: .external
                ) {
                    openURL(SettingsReferenceData.termsOfUseURL)
                }

                SettingsRowDivider()

                SettingsActionRow(
                    title: Copy.settings.privacyPolicyButtonLabel,
                    systemImage: "hand.raised",
                    accessory: .external
                ) {
                    openURL(SettingsReferenceData.privacyPolicyURL)
                }
            }
        }
    }

    // MARK: - Delete all data (spec §24 privacy)

    private var dataSection: some View {
        SettingsSection(
            title: Copy.settings.dataSectionTitle,
            footer: Copy.settings.deleteAllDataFooter
        ) {
            SettingsGroupCard {
                SettingsActionRow(
                    title: Copy.settings.deleteAllDataRowLabel,
                    systemImage: "trash",
                    accessory: .none,
                    isBusy: isDeletingData,
                    isDestructive: true
                ) {
                    isConfirmingDeleteAll = true
                }
            }
        }
    }

    /// Wipes this device's ZANO data. Order matters:
    ///   1. End any active lock through the emergency path, which also clears the shields
    ///      (`LockEngineManager.emergencyUnlock` -> `ManagedSettingsStore.clearAllSettings()`). Never
    ///      leave someone shielded with no data left to unlock against (CLAUDE.md: never trap).
    ///   2. Delete every SwiftData row of every registered model type
    ///      (`ModelContainer.appGroupModelTypes`, the store's own schema list).
    ///   3. Clear the App Group defaults domain (streak mirrors, active-lock ids, tag mappings,
    ///      acknowledgement flags — every `SharedDefaults` key and every manager that shares the
    ///      suite) and the onboarding-completed flag.
    /// Remote (Supabase) rows are NOT deleted here — see this pass's report. The subscription is
    /// Apple's and is untouched.
    private func deleteAllData() async {
        isDeletingData = true
        defer { isDeletingData = false }

        if let sessionID = SharedDefaults.activeLockSessionID {
            try? await LockEngineManager.shared.emergencyUnlock(sessionID: sessionID)
        }

        do {
            // Saved per type so a later fetch never sees rows a cascade already removed.
            for modelType in ModelContainer.appGroupModelTypes {
                try SettingsDataReset.deleteAll(modelType, in: modelContext)
                try modelContext.save()
            }
        } catch {
            errorAlert = SettingsErrorAlert(
                title: Copy.settings.deleteAllDataFailedTitle,
                message: Copy.settings.deleteAllDataFailedMessage
            )
            return
        }

        SettingsDataReset.clearDefaults()
        Analytics.shared.capture(event: "settings_all_data_deleted")
        errorAlert = SettingsErrorAlert(
            title: Copy.settings.deleteAllDataDoneTitle,
            message: Copy.settings.deleteAllDataDoneMessage
        )
    }
}

/// The non-UI half of "Delete all my data".
private enum SettingsDataReset {
    /// `AppRouter.onboardingCompletedKey` (private there, in `App/ZANO/AppRouter.swift`). Duplicated
    /// because AppRouter exposes no reset API — clearing it sends the next launch to onboarding. A
    /// live `AppRouter.shared` keeps its in-memory `hasCompletedOnboarding` until relaunch, hence
    /// the "close and reopen" message. Follow-up: `AppRouter.resetOnboarding()`.
    static let onboardingCompletedKey = "zano.app.hasCompletedOnboarding.v1"

    /// Opens `any PersistentModel.Type` into a concrete `T` (SE-0352) so it can build a
    /// `FetchDescriptor<T>`. Row-by-row delete (not the batch `delete(model:)`) so SwiftData runs
    /// each relationship's delete rule.
    @MainActor
    static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }

    static func clearDefaults() {
        UserDefaults(suiteName: AppGroup.identifier)?.removePersistentDomain(forName: AppGroup.identifier)
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
    }
}

// MARK: - File-scoped supporting types

private struct SettingsErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Reference URLs. The strings live in `Copy.settings` (one place for the founder to confirm).
/// `manageSubscriptionsURL` is Apple's documented subscription-management page. Terms and privacy
/// are PLACEHOLDERS that must point at real, published pages before release. `gearStoreURL` is
/// `nil` until a real store exists (spec §25.5 names Shopify, not a domain) — `nil` hides the Gear
/// row and its offer callout.
enum SettingsReferenceData {
    static let manageSubscriptionsURL = URL(string: Copy.settings.manageSubscriptionsURLString)!
    static let termsOfUseURL = URL(string: Copy.settings.termsOfUseURLString)!
    static let privacyPolicyURL = URL(string: Copy.settings.privacyPolicyURLString)!
    static let supportMailURL = URL(string: "mailto:\(Copy.settings.supportEmail)")!
    static let gearStoreURL: URL? = nil
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

/// The badge every row uses: monochrome, always `textSecondary` on a `surface2` disc (polish pass
/// 2026-09-24 — Opal/Spotify-style settings; ring hues belong to goal progress, not menus). Same
/// 32 pt base diameter and Dynamic Type scaling (clamped to 1.4x) as `IconBadge(.small)`, which
/// `SettingsRowDivider`'s inset math relies on. Disabled rows dim the glyph to `muted`.
private struct SettingsIconBadge: View {
    let systemImage: String

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let diameter = Theme.Metrics.iconBadgeSmall * min(scale, 1.4)
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.45, weight: .medium))
            .foregroundStyle(isEnabled ? Theme.Colors.textSecondary : Theme.Colors.muted)
            .frame(width: diameter, height: diameter)
            .background(Theme.Colors.surface2, in: Circle())
            .accessibilityHidden(true)
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
    var value: String? = nil
    var accessory: Accessory = .chevron
    var isBusy = false
    /// Destructive rows ("Delete all my data") set the title in `danger`.
    var isDestructive = false

    @Environment(\.isEnabled) private var isEnabled

    /// Disabled = `muted` text, not a stacked opacity over the whole row.
    private var titleColor: Color {
        guard isEnabled else { return Theme.Colors.muted }
        return isDestructive ? Theme.Colors.danger : Theme.Colors.text
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            SettingsIconBadge(systemImage: systemImage)

            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(titleColor)
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

/// A row that pushes a destination. `destination` is a closure so the pushed screen (and its
/// `@Query`s) is only built when actually navigated to. `value` is the optional trailing readout
/// (see `SettingsRowLabel`).
private struct SettingsNavRow<Destination: View>: View {
    let title: String
    let systemImage: String
    let value: String?
    let destination: () -> Destination

    init(
        _ title: String,
        systemImage: String,
        value: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, value: value)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }
}

/// A row that runs an action (open a URL, kick off a restore). `isBusy` swaps the accessory for a
/// spinner and ignores taps without dimming the row.
private struct SettingsActionRow: View {
    let title: String
    let systemImage: String
    var accessory: SettingsRowLabel.Accessory = .external
    var isBusy = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(
                title: title,
                systemImage: systemImage,
                accessory: accessory,
                isBusy: isBusy,
                isDestructive: isDestructive
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
                    .foregroundStyle(isSelected && isEnabled ? Theme.Colors.accent : Theme.Colors.muted)
                    .frame(height: 24)
                Text(title)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(isSelected && isEnabled ? Theme.Colors.text : Theme.Colors.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.choiceTileHeight)
            // Unselected: a plain `surface2` tile, no border. Selected: the accent stroke at
            // `Metrics.selectedStroke` (strokeBorder, so no layout shift). Polish pass 2026-09-24.
            .background(Theme.Colors.surface2, in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Theme.Colors.accent, lineWidth: Theme.Metrics.selectedStroke)
                }
            }
            .contentShape(shape)
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
        // The sample line is the spec §5.13 line verbatim (`CoachVoice.sampleLine`); curly quotes
        // are punctuation around it, not copy. It is `headline` (17 pt), not 15 pt italic body: the
        // coach's voice is the one moment of personality on this screen and it was set like a
        // footnote. Height is held at two lines' worth (2 x 22 + 2 x 12 = 68 -> 72) so switching
        // between a one-line and a two-line voice doesn't jolt the layout below; it still grows
        // if Dynamic Type needs a third line.
        Text("\u{201C}\(voice.sampleLine)\u{201D}")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.text)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 72)
            // No recessed box: the quote sits straight on the card (polish pass 2026-09-24).
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
        case .hype: "megaphone"
        case .toughLove: "flame"
        case .chill: "leaf"
        case .data: "chart.bar"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppRouter.shared)
    .modelContainer(for: [User.self, Subscription.self, GoalEvent.self, Streak.self, Gym.self, LockSet.self], inMemory: true)
}
