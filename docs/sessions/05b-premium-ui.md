# Session 05b — Premium UI + UX pass

- **Branch:** `claude/sharp-euler-npwt08`
- **Spec sections:** §15 (design system, amended 2026-09-24), §16 P1/P3/P4/P5, §5.1, §5.15, §5.17, §7, §21
- **Plan:** `docs/design/premium-ui-plan.md`
- **Status:** Compiles + tested in CI (device verification open)
- **Started:** 2026-09-24
- **Last updated:** 2026-09-24

## Scope

A visual and UX redo of Session 5's screens so ZANO feels like a top-tier app, driven by the
design skills vendored in `.claude/skills/` (see its README). The user skipped the HTML-mockup phase
and asked for the Swift directly, verified through CI screenshots.

Decisions (2026-09-24): palette option A (keep near-black + acid green; green only for earned
states, chrome achromatic); references Spotify (content-first darkness) and Nike (condensed type).

## Definition of done

- Every main tab, onboarding screen and the paywall renders in the new system in CI screenshots.
- Flow fixes decided in the spec are in code: hard paywall (no free path), notification priming
  after the paywall.
- Build green, Core tests green.
- Device-only surfaces (real locked-app icons in the vault, haptics, shield, widgets) listed as
  unverified.

## Log

### 2026-09-24 — Round 1: design system, Today, Lock, Progress, Trophy, onboarding, paywall

- **Files touched:** `Core/Sources/Core/UI/Theme.swift`, `Components/{PrimaryButton,SelectableCard,
  ZanoSurface,HeroGlow,GoalRing,NumeralText,PaywallCard,OnboardingQuestion}.swift`,
  `Copy/{Today,Progress,Paywall,OnboardingReveal,OnboardingPaywallFirstWin,TrophyCosmetics}Copy.swift`,
  `App/ZANO/{ZANOApp,ContentView,ScreenshotGallery}.swift`, `Features/Today/{TodayView,LockVaultCard (new),
  GoalActionList (new)}.swift`, `Features/Lock/LockStatusView.swift`, `Features/Progress/ProgressView.swift`,
  `Features/Trophy/*`, `Features/SunriseAlarm/*`, `Features/Onboarding/*`, `Features/Fuel/FuelView.swift`,
  `Features/Celebration/UnlockCelebrationView.swift`.
- **What changed:**
  - Design system: achromatic chrome (`Colors.interactive`), `PrimaryButton` defaults to a white
    capsule (`.accent` only for earned moments), white selection, tab bar and onboarding progress
    white. Numerals and display type are SF Pro condensed/compressed (heavy, 88pt hero). Eyebrows are
    sentence case (no tracked all caps). New depth levels: `zanoAmbient` (state-driven screen light:
    cool when locked, warming with progress, accent when earned), `zanoHero` (elevated gradient
    surface with a real shadow). Rings: gradient sweep with a lit leading cap. Large navigation
    titles use the same condensed heavy face (UIKit appearance proxy, the only way to set it).
  - Today: the vault hero (`LockVaultCard`) shows the lock as one huge number, the locked apps
    dimmed behind a lock (device only), and a segment per required goal that fills in the goal's
    color. Goals are rows with an in-place action (`GoalActionList`): +25g protein / +250ml water log
    through the App Intents, focus and gym check-in start from their row. Grouped as "To unlock" /
    "Also today". The bottom bar only carries what a row can't (start today's lock, setup, live
    status). Removed the "Log the rest on Fuel" detour.
  - Lock: same vault and rows (read-only), large title, ambient light.
  - Progress / Trophy / Sunrise (helper agent): see the agent summary in the round-1 commit.
  - Onboarding / paywall (helper agent): hard paywall, priming after paywall, visual pass.
- **Decisions made and why:** see `docs/design/premium-ui-plan.md` §3–§5.
- **Known issues / TODOs left behind:** Settings and Fuel only got the system-level changes.
- **Needs verification on:** CI build + screenshots (pending), real device for locked-app icons,
  haptics, 120Hz motion.

### 2026-09-24 — Round 1 CI + round 2 fixes

- **CI:** run 35945717141 (commit 53ce3fe) green on the first try: app build, Core tests, 38
  screenshots. DemoData log confirms 15 sessions / 14 ended / 14 earned in the store.
- **Round 2 (commit 4385ffe), from reviewing those screenshots:** the vault's filled lock watermark
  read as a grey placeholder block → thin outline emblem with a fade; hero gained a line naming what
  the lock waits on; water progress in liters (the ml line truncated); alarm escape dock made opaque
  with a fade (content bled through it, snooze looked clipped; pre-existing); remaining green
  chrome made neutral (lock-set default star/tint, Settings coach-voice selection, share CTAs).
- **Known issues left:** Settings/Fuel got system-level changes only; `ZANOUITests/Flow1PaywallFreePathUITests.swift`
  still targets the removed free path (pre-existing, UI tests are compile-only in CI); workout ring
  is green by spec (§15 ring colors) even though it's not an earned state.
- **Needs verification on:** real device — locked-app icons in the vault (FamilyControls tokens),
  haptics, motion at 120 Hz, shield/widgets.

### 2026-09-24 — Rounds 3–5: paywall v4, brand, Opal-style Today, brand v2 palette

- **Paywall v4** (`PaywallView.swift`, `PaywallCopy.swift`): rebuilt from the founder's reference
  (trial headline, vertical trial timeline, Monthly/Annual tiles, "No payment due now", one CTA,
  terms, Terms · Privacy · Restore). Demo offerings for screenshots (`PaywallViewModel.loadDemoOfferings`, DEBUG).
- **Brand v1 → v2:** v1 was a custom wordmark (concept D). v2 uses the founder's own artwork: the
  swoosh-star mark and the geometric wordmark, traced to vectors (`ZanoLogo.swift`, `docs/brand/*`).
  New app icon (silver mark on black), launch lockup, landing logo. `docs/brand/brand-kit.md` v2.
- **Palette (decision 2026-09-24, founder):** acid green removed as not premium. Accent is platinum
  `#E4E2DC`, text pearl `#F2F1ED`, `Theme.Colors.metallic` (silver gradient), muted danger/warning,
  low-chroma goal rings (bronze / slate / glacier + sage, rose, champagne...). Mirrored in
  `ZANOWidgetColor`, `WatchTheme`, `landing/style.css`, `AccentColor` asset. Spec §15 amended.
- **Today (Opal reference):** concentric goal rings in a state-lit halo, status pill, and a new
  Screen time section drawn by the `ZANOReport` DeviceActivityReport extension (`ScreenTimeSummaryView`,
  `ScreenTimeCopy`); the default lock set is mirrored to `SharedDefaults.lockedSelectionData`.
- **CI:** runs 26/27 failed (report closure type; then demo-data `Int` → `TimeInterval`), both fixed. Run 28 (04d9c38) green: app + extensions build, Core tests pass, screenshots reviewed (no green left; new logo on Today, paywall, onboarding).
- **Known issues:** logo paths are traced from a raster (a vector master would be cleaner); the
  screen-time report is unverified on device (Simulator has no Screen Time data); code comments
  still mention "green" in places (history, harmless); shield/widget branding not done.

### 2026-09-24 — Living star: the logo charged by screen time (Opal's gem)

- **What:** `ZanoLivingMark` (Core) draws the ZANO star as Today's hero object. Its brushed
  silver fills left to right with `ScreenTimeSummary.charge`: the share of today's waking hours
  (from 6 AM) not spent on the phone, with locked-app time counted double. Animation: the glow
  breathes, a light sweep crosses the charged metal every 4 s, and the star slowly floats and turns.
  Low charge is dim graphite with a cold glow. Reduce Motion: still.
- **Data path:** only the report extension can read screen time (spec §27), so `ZANOReport` gains
  a second scene, `ChargeMarkReport` (`.zanoMark`), that renders `ScreenTimeChargeView`; Today
  embeds it with `DeviceActivityReport(.zanoMark, ...)`. Without access the star is uncharged with
  a hint; CI screenshots use demo data (charge 70%).
- **Hero change:** the concentric goal rings leave the hero (the star replaces them and the lock
  glyph); goal progress is a segment bar under the number, plus the rows below. Lock keeps its rings.
- **Unverified (device only):** TimelineView animation inside a DeviceActivityReport-hosted view,
  whether the hosted view's background is transparent over the halo, and tap pass-through.

### 2026-09-24 — Wordmark v3 (friendlier)

- Founder supplied a rounder wordmark (soft terminals, heavier strokes, stadium O) as "more friendly
  and less cold". Traced to vectors (815.59 × 100 units, 8.16 : 1) and swapped into
  `ZanoWordmarkShape`, `docs/brand/zano-wordmark*.svg`, the lockup + launch images and the landing
  page. The mark and app icon are unchanged.

### 2026-09-24 — Floating glass tab bar

- Founder reference: a floating dark-glass capsule with outline icons and a lit circle behind the
  selected tab. `App/ZANO/ZanoTabBar.swift` draws it; `MainTabView` hides the system bar per tab
  (`zanoTabContent()`, which also reserves 80 pt at the bottom) and overlays the capsule. `TabView`
  still owns state. Selection glides (matched geometry spring) with a selection haptic; Reduce
  Motion/Transparency respected. Fuel's icon is now the reference's fuel pump.
- UI tests query `otherElements["zano.tabBar"]` instead of the system `tabBars`.
- **Blocked (2026-09-24 13:30 UTC):** CI runs 31 and 32 (wordmark v3, tab bar) failed in ~5 s with
  no runner assigned and no log: the macOS job never started. Almost certainly the account's GitHub
  Actions minutes / spending limit for this private repo (macOS minutes bill at 10×; ~30 runs today).
  The wordmark v3 and tab bar commits are syntax-checked only, not compiled. Re-run CI once minutes
  are available (Settings → Billing → Actions).

### 2026-09-24 — Fuel clean-up, numeral spacing fix, Codemagic

- Fuel: quick-add chips and icon buttons are dark glass capsules (pearl number, muted unit) instead
  of hue-filled slabs; the goal's hue lives only on its ring; cards stay neutral until the goal is
  met. "Kitchen Staples" → "Kitchen staples" (sentence case).
- `NumeralText`: the space between numeric tokens is full size, so "56h 0m" no longer reads "56.0".
- `codemagic.yaml` + `scripts/ci/{screenshots,push-results}.sh`: second Mac builder; results on the
  `ci-results` branch once the `github` env group holds a GITHUB_TOKEN.

### 2026-09-24 — ZANO Blue, darker base, screen time under the star

- **Palette (founder: "dull and lifeless", background "grey and faint"):** accent is ZANO Blue
  `#3F7BFF` (white labels via `Theme.Colors.onAccent`); `interactive` = accent; `PrimaryButton`
  defaults to `.accent`; background `#050506`, surface `#111113`, surface2 `#19191C`;
  `lockedAmbient` is deep navy `#1C2B4D`, so ambient light reads blue-black instead of grey. The tab
  bar's lit tab glows blue. Mirrored in widget/watch tokens, landing CSS, AccentColor and
  LaunchBackground assets; spec §15 and brand kit updated.
- **Today hero:** under the star, Opal-style: "2h 34m" / "SCREEN TIME TODAY" / "Star 72% charged".
  Drawn by the report extension (`ScreenTimeChargeView`). The Screen time section below no longer
  repeats the total.

### 2026-09-24 — Features 1–6 (parallel agents)

- **Unlock moment** (`Features/Celebration/UnlockCelebrationView.swift`, new `UnlockStarStage.swift`):
  star charges 0.7→1, blue bloom + shockwave + burst, "Earned." in silver, Time Bank counts up; ≤1.2s;
  Reduce Motion path.
- **Shield** (`Extensions/ZANOShieldConfig/*` incl. new asset catalog `ShieldMark`, `ShieldCopy`):
  silver star icon, "N goals to unlock {app}", coach-voice subtitle, blue "Show my goals", grey
  "Emergency unlock" (always available). Also increments the shield impression count.
- **Widgets** (`ZANOHomeWidget`, `ZANOLockScreenWidget`, `ZANOWidgetComponents`, `WidgetCopy`): static
  charged star, charged by goals (widgets can't read Screen Time); new circular "Goals" metric
  (default). Small widget no longer has "Start lock" (large does).
- **Weekly recap** (`WeeklyRecapShareView`, new `RecapStoryPages.swift`, `ShareCopy`): six-page story
  pager, auto-advance 4s (off in screenshots and VoiceOver), ends on the existing share poster.
  No per-weekday data, so "toughest" is the lowest goal ring; rings alternate blue/silver (no goal
  types in the recap model).
- **Onboarding** (all screens except Paywall): header star charges with step/14, flow-wide backdrop
  brightening with progress, star heroes on 1/9/10/14, spring entrances.
- **Empty/first-day states** (Today checklist, Progress first week + bar scaling fix, Lock idle hero
  with next lock + "Start a lock now", Fuel empty panels). Bars looked equal because demo data used
  equal 4h locks; demo now varies lengths.
- **Unverified:** everything above is syntax-checked only (no Mac; Codemagic results need the
  GITHUB_TOKEN). Screenshot tour now also covers onboarding-10/14, celebration and recap.

### 2026-09-24 — Audit-driven polish pass (skills: ui-ux-pro-max, ux-designer, appstore-mvp-review)

Three read-only audits (visual, UX/accessibility, completeness/App Store) → six fixers by file
ownership. Highlights:
- **Core:** `accentFill` #2A62E6 for filled blue (white label 5.3:1); scalable numeralSmall/Medium;
  ZanoGlass + ZanoStatusCapsule; star throttled to 30 fps, paused in background, blended glow,
  hidden from VoiceOver except the screen-time hero; spoken durations; chart summary; navy/silver
  ShieldPreview; `StickyActionBar(extendsToBottomEdge:)` so the glass tab bar floats over content.
- **Today/Lock/shell:** emergency unlock = 60 s hold on Core `EmergencyUnlock` with streak toggle
  (spec §8), also above a lapsed-subscription paywall; red only for emergencies; undo toast after
  quick-add; every goal row has an action/status; goal-done bug fixed (one +25 g `.verify` no
  longer completes a 150 g goal); tab bar tokens, fork.knife, Large Content Viewer, lock dot.
- **Settings:** new `GoalsEditorView` (additive types only; Done button when shown as a sheet);
  plan status card + Manage subscription (no Free/Go Pro); Notifications, Help & feedback, Terms,
  Privacy, Pause for health reasons (explanatory only — no Core pause mechanism yet), Delete all my
  data; monochrome icons; LockSetup denial recovery.
- **Onboarding/paywall:** Screen Time denial → Open Settings / Try again; first win 2 min + "Do it
  later"; paywall lists only shipped benefits (no squads/duels), star hero, readable blue, lapsed
  context; Flow1 UI test rewritten.
- **Fuel/Progress/Trophy/Share:** shared glass, silver `TrophyBadgeDisc`, undo, add-goal entry,
  spoken durations, recap pause button + accessibility-aware auto-advance; cosmetics Pro gate removed
  (view and `CosmeticsStore`).
- **Review readiness:** PrivacyInfo.xcprivacy (app + 5 extensions), accurate camera/Health strings,
  background modes → location only, NSSupportsLiveActivities, ITSAppUsesNonExemptEncryption,
  AlarmKit/Calendars strings (key names unverified), demo data release-gated, review notes rewritten.

**Needs the founder:** RevenueCat package + API key (purchases can't complete without it — hard
paywall would block entry), real privacy/terms URLs (placeholders `zano.app/privacy|terms`), support
email (placeholder `support@zano.app`), product calls (streak freeze in emergency unlock, meal-prep
verification, pause-for-health mechanism).
**Unverified:** all of it is syntax-checked only; Flow2 UI test still expects the old free path.
- **CI green (2026-09-24):** after the repo went public, run 36053520709 (bc74bf4) built everything; only fix needed was a @MainActor on the widget quick-log helper. Screenshots reviewed.

### 2026-09-24 — NFC tags in onboarding (founder: tags are "a huge part" of ZANO)

Spec §3 (protein/water/creatine verified by NFC tap), §5.10 (Sunrise Tag), §6 (NFC), §7, §25.1,
§25.5–§25.6 (Tag Pack, gear store).
- **New screen 9, "Tap to prove it"** (`App/ZANO/Features/Onboarding/Screen9NFCTags.swift`): a
  SwiftUI-drawn illustration (phone, top edge first, taps a round silver tag with the ZANO star; blue
  NFC rings pulse, the goal ring around the tag fills, a check lands; three runs then rests; Reduce
  Motion = finished state, static), two lines + a proof line, three glass chips (Shaker / Water
  bottle / Sunrise alarm), and "Do you have ZANO tags?" — I have ZANO tags / Get tags / Skip for now.
  Continue is gated on an answer. The answer lives in `OnboardingFlowState.nfcTagAnswer` (transient)
  and goes out as analytics `onboarding_nfc_choice`; there is no persisted home for it.
- **Placement:** after the six questions (coach voice, 8), before wake-up and the plan. Flow is now
  **15 screens** (tags 9, wake-up 10, plan 11, commitment 12, paywall 13, notifications 14, first win
  15). Spec §7 targets 10–14 — **founder decision needed** (keep 15, or fold a screen).
- **Plan reveal:** a protein goal row now says "Verified by: NFC tap" (have tags), "… once your tags
  arrive" (get tags), or "Verified by: meal photo or barcode" (skip). Water/creatine get the NFC line
  too if they ever appear in the plan. Wake-up (screen 10) left alone: it is phone-time math, not
  mornings, so the Sunrise Tag has no natural place there (it is on the tags screen instead).
- **"Get tags" has no link:** `SettingsReferenceData.gearStoreURL` is `nil`, so the answer says tag
  packs aren't on sale yet; the screen shows an "Open the ZANO gear store" link automatically once
  that URL is set. No price and no "free with annual" claim (neither is offered anywhere yet).
- **Renumbering:** `OnboardingFlowState.lastScreen` 14 → 15; container switch; analytics
  `screen_number` for screens after 8 (+1); first-win star start charge 14/15; UI tests
  (`onboardingScreenCount` 15, new `chooseNFCSkip`, `driveOnboardingToPaywall` now matches the hard
  paywall order and ends on 13, Flow1 `paywallStep` 13, Flow2 permission 14 / first win 15); CI
  screenshot lists add `onboarding-15` (GitHub) and `onboarding-9/11/15` (Codemagic default), SE pass
  shoots `onboarding-9` and the paywall at `onboarding-13`.
- Copy: `Core/Sources/Core/Copy/OnboardingNFCCopy.swift` (`extension Copy.onboarding`).

**Unverified:** syntax-checked only (`swiftc -frontend -parse`); needs a CI compile and a look at the
screenshots (illustration geometry, chip wrap on SE). Flow2 test2 still taps the removed free-path
link (hard paywall), so it cannot pass as written — flagged in the test.
