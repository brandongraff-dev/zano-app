# Better-UI audit — `App/ZANO/Features/**` + `Core/Sources/Core/UI/**`

**Date:** 2026-09-23 · **Mode:** read-only (no Swift file was edited) · **Skill:** `interfaces:better-ui` v1.6.3
**Audit axes (from the task):** concentric radius · optical alignment · surface depth (§15 background / surface / surface-2) · contextual icons · 44pt hit areas. The skill's press-scale, icon-swap and enter/exit recipes are covered in §2.7 because they change what "polished" means here.

> **Nothing in this document was rendered.** There is no Mac, Simulator, device or compiler in this environment. Every finding is either (a) read from source, or (b) arithmetic on `Theme`'s hex values (contrast and layout math; reproducible, numbers in §1). Anything that needs eyes on a screen is listed in §7 as `Not verified`. Line numbers are as of this read and drift on edit.

**Read:** all 33 files under `App/ZANO/Features/**` and all 17 under `Core/Sources/Core/UI/**` (executable code in full; long file-header comment blocks skimmed). **Not audited:** anything owned by the concurrent workflow (`ContentView` tab-bar chrome, `AppRouter`, `Assets.xcassets`, Watch, `project.yml`), the widgets, and the real Shield extension the user actually sees when blocked (`Extensions/ZANOShieldConfig`). `ShieldPreview` and `FounderSeriesCard` have **no call sites** in `App/` (grep), so they were audited as components only. `Screen13Paywall.swift` is dead code (container routes to `PaywallView`); it repeats the same patterns and is not listed separately.

Prior docs (`ui-stress-test-findings.md`, `apple-design-review.md`) were checked so nothing here repeats them; items they raised that are **now fixed** are credited in §5.

---

## 0. Verdict

**Block.** 7 HIGH findings (§2.1, HIT-01, HIT-06) are visible breakage or unusable controls. Counts are in the footer.

The honest design read: the *tokens* are disciplined (only three hard-coded radii in 50 files, every corner is `.continuous`, no stray hex) but the *surfaces are flat*. The three-step background → surface → surface-2 hierarchy sits **1.08 / 1.08 / 1.16 : 1** apart, `Theme.Colors.hairline` is **1.06 : 1** against the card it outlines, and across all of Features + Core/UI there are **0 `.shadow`, 0 `.blur`, 1 `LinearGradient` (a share card), 1 material (Today's bottom bar)**. §16's "subtle inner glow on active elements" was never implemented. 31 call sites in 20 files hand-inline the same `background(surface, in: RoundedRectangle…)` recipe, so there is no single place to add depth. The result reads as a correct dark-mode tutorial, not "ranked mode in a game". Most of the fix is **one token, one modifier, and a handful of hero glows** (§3).

### Do these first (opinionated order)

1. **Qualify the seven `ProgressView()` calls** (BRK-01) — the paywall/alarm/barcode "spinners" mount the whole Progress tab.
2. **Invert the hold-to-commit label under the fill** (BRK-02) — the label is unreadable mid-hold on the app's signature interaction.
3. **Re-scale the `ShareCard` export and its ring strip** (BRK-03/04) — the shared image does not match the preview and text is ~2 % of image width.
4. **Give the palette an edge:** `hairline` → white 8 %, add a `track` token and one `card` modifier (DEP-01…03).
5. **44pt targets** on every glyph-only close/back/emergency control (HIT-01…06), then **Today's hero ring row + hero numerals** (BRK-05, TYP-01/02).

---

## 1. The numbers behind the findings

Computed from `Theme.swift` hex values (WCAG relative-luminance contrast; alpha composited over the stated backdrop). Script output, not eyeballing.

| Pair | Ratio | Read |
| --- | --- | --- |
| `background` `#0A0A0B` → `surface` `#141416` | **1.08** | Card edge is a 1-step fill change only |
| `surface` → `surface2` `#1C1C1F` | **1.08** | Nested well barely separates from its card |
| `background` → `surface2` | **1.16** | Also the ring track / progress track / pager-dot colour |
| `hairline` (`surface2` @ 0.8) over `surface`, vs `surface` | **1.06** | The "1px hairline" (Theme.swift:54) is invisible on cards |
| `hairline` over `background`, vs `background` | 1.12 | |
| pure white @ 8 % over `surface`, vs `surface` | **1.23** | The skill's dark-mode ring value (`0 0 0 1px white/0.08`) — perceptible edge |
| pure white @ 10 % over `surface` | 1.32 | Skill's image-outline value |
| `text` `#F5F5F7` on `accent` `#B8FF3C` | **1.11** | Hold-to-commit label under the fill |
| `text` on `accent`@0.9 over `surface2` (real fill colour) | **1.35** | |
| `background` on `accent` | 16.4 | Correct pairing (standard CTA) |
| disabled CTA: `accent`@0.5 over `background` | olive `#618424`, 4.56 vs bg | Still reads "green button", not "disabled" |
| locked trophy label: `muted`@0.55 over `surface` | **2.56** | Fails 4.5 for a label that says what to earn |
| `muted` on `surface` | 5.64 | fine |

**Radius scale insight (drives §2.4):** 12 → 20 → 28 is an **8pt step = `Spacing.xs`**. `inner = outer − inset` therefore holds *exactly* when a nested surface sits `Spacing.xs` (8) inside its parent. Every nested surface in the app instead sits 12–16pt inside and reuses the next token down, so each is ~8pt "too round" for its parent.

---

## 2. Findings

Severity per the skill: **HIGH** breaks an interaction / makes a state unreadable; **MEDIUM** visible inconsistency in surfaces, icons or motion; **LOW** isolated polish. One row per root cause, every location listed. SwiftUI mappings of the skill's web recipes are given in *After*.

### 2.1 Visible breakage found while auditing

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| BRK-01 | HIGH | `FuelView.swift:1106` · `PaywallView.swift:222, 319, 351` · `AlarmRingingView.swift:235, 264` · `SunriseAlarmSetupView.swift:319` | `ProgressView()` / `ProgressView().tint(…)` | `SwiftUI.ProgressView()` (already done at `LockedOutMomentView.swift:476`, `WeeklyRecapShareView.swift:318`). Longer term rename the screen (`ProgressTabView`) — needs `ContentView`/`AppRouter`, owned by the concurrent workflow | The `ZANO` module declares `struct ProgressView: View` (`ProgressView.swift:111`). A module-local type shadows the imported one, and it compiles because the screen has an implicit `init()`. So the paywall loading state, the spinner laid over the purchase CTA, the restore button, the barcode-lookup state, the alarm's loading and NFC-scan states, and the Sunrise scan button each mount the **entire Progress tab** (its `@Query`s, `NavigationLink`, scroll view) in a spinner slot; `.tint()` lands on that view, not a spinner. Two files' own comments describe exactly this trap. *Not verified by build.* |
| BRK-02 | HIGH | `PrimaryButton.swift:97-118` (label foreground `:99`, fill `:104-109`). Hits: `Screen11Commitment.swift:72-77`, `TodayView.swift:298-304`, `LockStatusView.swift:277-283`, `AlarmRingingView.swift:326` | `.foregroundStyle(Theme.Colors.text)` over an `accent` fill that sweeps under it: **1.11 : 1** (1.35 at the real 0.9-alpha fill) | Two stacked copies of the label: `text` underneath, `background` (16.4 : 1) on top, the top copy `.mask(alignment: .leading)`-ed to the fill width, so text inverts exactly where the fill passes. Also clip the fill to the button shape with a straight trailing edge (currently a `RoundedRectangle(r12)` whose corners clamp below 24pt width, `:105`) | At 40–100 % of the hold the label is near-invisible on the signature interaction of Onboarding 11, Today "begin lock", the Lock screen's emergency unlock and the alarm's squad confirm. Skill: a state must never be readable only mid-animation, and here it is *unreadable* mid-animation. |
| BRK-03 | HIGH | `ShareCard.swift:161-172` (default `size: 1080×1920`, `scale: 1`), layout `:78-131`, `Theme.Typography.title` 22pt `:94` | Exported image is laid out at **1080 pt wide** with 22pt title / 17pt stat text / 44pt rings; the on-screen preview is ≤ 320pt wide, so text is ~3.4× larger there. Export ≠ preview; text is ~2 % of image width | Render at the preview's logical size: `renderImage(size: CGSize(width: 360, height: 640), scale: 3)` (= 1080×1920 px, same layout as preview). Also drop `.clipShape` from the export path (`:130` bakes **transparent rounded corners** into the PNG that IG/iMessage turn black/white); clip only in the preview wrapper. Keep content out of the top and bottom ~250 px story-UI bands (footer wordmark `:117-125` sits in the reply-bar zone) | The one artefact the user posts publicly is the least designed and doesn't match what they approved. Arithmetic, *not verified by render*. |
| BRK-04 | HIGH | `ShareCard.swift:133-145`; call sites `WeeklyRecapShareView.swift:159-160, 370-378`, `PreviewCatalog.swift:232` (220pt wide) | `HStack` of `GoalRing(.small)` — fixed 44pt frames — each in `frame(maxWidth: .infinity)` | Let the ring flex: give `GoalRing` a fill-width mode (`aspectRatio(1)`, no fixed frame) or lay the strip in `ViewThatFits`/`LazyVGrid` with adaptive columns | 5 rings need 5×44+4×12 = 268pt but a 320pt-wide preview leaves 320−64 = 256; from 5 rings up the strip overflows and the card's `clipShape` cuts it. The P7 mock's 7 daily rings need 380pt and can never fit. |
| BRK-05 | HIGH | `TodayView.swift:202` → `RingCluster.swift:98-106` (`.row`, spacing `:99`); milder at `FuelView.swift:360` | `RingCluster(items:, ringSize: .large, layout: .row)` = 3 × 148 + 2 × 24 + 8 = **500pt** in a 361pt column | Use `.medium` ×3 (312pt) centred, or hero (`.large` workout) + two `.medium`; make `.row` a `ViewThatFits { flexible centred HStack; horizontal ScrollView }` so it only scrolls when it must | On every iPhone the Today hero row is a horizontal scroller with the third ring cut off — on the screen that is the product's face. Fuel (2 rings = 328pt) fits but hugs the leading edge with a dead 33pt on the right (ALN-02). |

### 2.2 Hit areas (44 × 44 pt)

Pattern that already works and should be copied: `ShieldPreview.swift:133-146` keeps the small visual and grows only the target (`.frame(minHeight: 44)` + `.contentShape(Rectangle())`).

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIT-01 | HIGH | `AlwaysAllowedWarningView.swift:172-180` (11pt `xmark`, **no padding**) · `FounderSeriesCard.swift:140-150` (≈ 23pt) · `LockedOutMomentView.swift:371-378`, `WeeklyRecapShareView.swift:214-220` (22pt glyph) · `OnboardingContainerView.swift:154-162` (32×32 back) · `FuelView.swift:985-991` (32×32 trash next to the log button) | Glyph-only controls sized to the glyph | `Theme.Metrics.minTapTarget = 44`; `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`. For corner "×" pull the 44pt frame back with a matching negative offset so the visual stays put | Close/back targets on full-screen moments and a safety banner are the hardest to hit and the ones people mash. The Always-Allowed × is the smallest target in the app. |
| HIT-02 | MEDIUM | `PaywallView.swift:346-360` (restore — App Review requires it visible), `:362-374` (continue free), `:233-238` (retry) · `Screen12PermissionPriming.swift:68-75` · `LockedOutMomentView.swift:424-427`, `WeeklyRecapShareView.swift:267-270` · `FounderSeriesCard.swift:99-107` · `AlwaysAllowedWarningView.swift:157-170` · `AlarmRingingView.swift:352-362` (snooze, half-asleep user) · `FuelView.swift:1132-1137` (manual-entry link over a live camera) · `SettingsView.swift:642-646` · `ProgressView.swift:221-235` (Trophy Case header link, ≈ 22pt) | 13–17pt text buttons, hit height ≈ 16–22pt | Same `minTapTarget` modifier | The paywall's two escape hatches and the alarm snooze are exactly where a missed tap costs the user. `FuelView.swift:1132` is also white 13pt text directly over camera video with no backing — give it the capsule the instruction pill above it already has (`:1128-1130`). |
| HIT-03 | MEDIUM | `FuelView.swift:873-897` (`FuelQuickAddChip`, ≈ 32pt, five per row — the Fuel tab's primary logging action) · `CosmeticsShopView.swift:170-191` (category chips, ≈ 32pt) | `padding(.vertical, 8)` capsule is the whole target | Keep the 32pt capsule; add `.padding(.vertical, 6).contentShape(Rectangle())` *outside* the `.background(Capsule())` and offset row spacing by −6 | |
| HIT-04 | MEDIUM | `LockStatusCard.swift:45-48, 59-62` · `GoalRow.swift:80-91` · `GhostProgressBanner.swift:68-71, 79-84` | `.padding()` + `.background()` are applied **outside** the `Button`, so the target is the inner row only: LockStatusCard **40pt** tall, GoalRow icon variant ≈ 38pt, with a dead 12–16pt ring around each card; the press style scales/dims the *label inside a static card* | Move padding + background inside the Button label so the whole card is the target and the press effect moves the whole card | `LockStatusCard` is Today's main navigation affordance. Also see MOT-02 (no press state at all on it). |
| HIT-05 | MEDIUM | `SettingsView.swift:198-217` (coach-voice rows) · `LockSetupView.swift:212-229` · `SunriseAlarmSetupView.swift:241-265` | `.buttonStyle(.plain)` label = `HStack { … Spacer() … }` with no `contentShape` | `.contentShape(Rectangle())` on the label (`FuelView.swift:981` already does this) | Taps in the empty middle of these rows do nothing. `LockSetupView.swift:216-227` additionally nests a `Toggle` inside the row `Button`. |
| HIT-06 | HIGH | `Screen14FirstWin.swift:544-572` (`EmergencyHoldControl`: 160×6pt bar, 13pt caption; target ≈ 26pt tall) | Emergency exit is a hairline bar | Make it a ring like `AlarmRingingView.swift:411-444` (148pt, danger) or at minimum a 44pt-tall hold target; see also MOT-05 | CLAUDE.md: never trap the user. The app has **three different visual grammars for "emergency hold"**: a 6pt bar here, a 148pt ring in the alarm, and a full-width `PrimaryButton` hold in `LockStatusView.swift:277-283`. One grammar, ≥ 44pt. |
| HIT-07 | LOW | `Screen6Workouts.swift:58-62` · `SettingsView.swift:731` · `SunriseAlarmSetupView.swift:363` | System `Stepper` (≈ 94×32) | Custom − / + buttons ≥ 44pt for the onboarding Q4 primary input; system is fine in Settings | |

### 2.3 Surface depth

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| DEP-01 | MEDIUM | `Theme.swift:54`; users: `PaywallCard.swift:103`, `Screen3MainGoal.swift:110`, `Screen4AppSelection.swift:86`, `Screen7FallOff.swift:67`, `Screen8CoachVoice.swift:77`, `FounderSeriesCard.swift:118`, `GhostProgressBanner.swift:143`, `AlarmRingingView.swift:375` | `hairline = surface2.opacity(0.8)` → 1.06 : 1 against the card | `hairline = Color.white.opacity(0.08)` and `edgeStrong = 0.13`. **Pure white, not `Colors.text`** — the skill is explicit that a tinted near-white edge reads as dirt | Skill dark-mode rule: *one* transparent white ring for depth, borders kept for structure/selection. Eight call sites already ask for a hairline and currently get nothing; the unselected onboarding option rows and the monthly paywall card have effectively no border. One-line token fix, biggest visual payoff in the audit. |
| DEP-02 | MEDIUM | 31 inlined recipes (`grep "surface2?, in: RoundedRectangle"`) across 20 files, e.g. `LockStatusCard.swift:48`, `GoalRow.swift:91`, `RecapCard.swift:101`, `ProgressView.swift:159, 194, 253, 292`, `LockStatusView.swift:178, 237, 260`, `TrophyCaseView.swift:161, 193, 237` | Flat fill only; each screen repeats the recipe | One `Theme` card modifier: fill + `strokeBorder(Theme.Colors.edge, 1)` + inner top highlight optional; `well` variant = `surface2`, no ring. No drop shadow on dark (skill: layered shadows are invisible on dark); use the ring for structure and reserve an accent glow (`shadow(color: accent.opacity(0.25), radius: 16)`) for *earned/unlocked* surfaces only | Also the only way to change the depth model app-wide later without a 20-file diff. |
| DEP-03 | MEDIUM | `GoalRing.swift:105` (track `surface2`); `TimeBankBar.swift:67-68`; `OnboardingContainerView.swift:172` (progress bar); `Screen2SocialProof.swift:72` (pager dots); `ProgressView.swift:341` (unearned streak days) | Neutral `surface2` tracks: 1.16 : 1 on `background`, 1.08 : 1 on `surface` | Rings: track = the ring's own hue @ 0.22 (Activity-ring style) so a 0 % ring still reads as *that goal's* ring; bars/dots/tiles: `Theme.Colors.track = white @ 0.10` | An empty ring, the unspent part of the Time Bank, and every un-earned day in the streak grid vanish into the card. The "empty" half of every progress visual is the informational half. |
| DEP-04 | MEDIUM | `ShareCard.swift:80-84, 129-130`; shown at `LockedOutMomentView.swift:307-308`, `WeeklyRecapShareView.swift:159-160` | Gradient runs `background` → `surface`; its **top edge equals the page background** so the card dissolves into the screen | 1px inside outline, white @ 10 % (`strokeBorder`, the skill's image-outline value, pure white), preview-only; optional faint accent radial behind the card | The card is meant to be seen as an *object about to be shared*; its top boundary currently doesn't exist. |
| DEP-05 | MEDIUM | `SettingsView.swift:158-170` (rows are system `secondarySystemGroupedBackground` ≈ `#1C1C1E`, not `surface` `#141416`), `GymSetupDetailView` `:562-576`, `NFCTagSetupDetailView` `:865-907`, `LockSetupView.swift:105-116` (+ `:217-223` uses `.font(.body)`, `.foregroundStyle(.primary/.secondary)` — not Theme), `AppPickerView.swift:46-60`, `SunriseAlarmSetupView.swift:156-161`, `BedtimeGateSetupView.swift:47-89`, and every sheet: `FuelView.swift:915-941, 1019-1047, 1083-1094`, `SettingsView.swift:720-772, 1082-1155`, `LockSetupView.swift:362-416` | Stock `List`/`Form`; only Settings' root hides the grouped background, its pushed details do not (bg is pure `#000`, a seam against `#0A0A0B`) | A `themedList()` modifier: `.scrollContentBackground(.hidden)`, `.background(Theme.Colors.background)`, `.listRowBackground(Theme.Colors.surface)`, `.listRowSeparatorTint(Theme.Colors.hairline)`; swap raw `.primary/.secondary` for `Theme.Colors.text/muted` | Every admin/sheet screen visibly changes design language the moment you leave a tab root. `AppPickerView.swift:36-37` even says "plain SwiftUI defaults … Session 5 owns final visual polish" — it never got it. `.roundedBorder` `TextField`s (`FuelView.swift:1153, 1199`) are the same problem. |
| DEP-06 | MEDIUM | `ShieldPreview.swift:152` · `UnlockCelebrationView.swift:152` · `Screen1Hook.swift:29` · `Screen10PlanReveal.swift` (no backdrop) · `AlarmRingingView.swift:139-141` (flat tint wash) | Hero/"moment" screens are flat `#0A0A0B` | One `HeroGlow` backdrop: `RadialGradient([tint @ 0.12, .clear], center: .top, endRadius ≈ 320)` — accent for earned/unlock, `danger` for the shield, phase tint for the alarm; no new hex | These are the screens §16 describes as "acid-green particles", "dark, calm, motivating". Currently identical black rectangles with an icon. |
| DEP-07 | LOW | `PrimaryButton.swift:234` | Flat accent fill | Optional 1px top inner highlight (`strokeBorder(LinearGradient(white 0.28 → 0, top→bottom))`) | Small, only after DEP-01…03 land. |
| DEP-08 | LOW | `TodayView.swift:105-111` | `.ultraThinMaterial` bar, no top edge; not a `Theme` token (prior doc proposed one) | `overlay(alignment: .top) { Theme.Colors.hairline 1px }` once hairline is real | |

### 2.4 Concentric radius

Rule: `outer = inner + inset`. With the 12/20/28 scale, concentric = **8pt inset**. Where an inner surface must stay at 16pt inset (content padding), compute `max(outer − inset, 0)` via a helper rather than reusing the next token down. Padding ≥ 24 is treated as separate surfaces (skill) — `AlarmRingingView.swift:332-345` (r28 card, 24pt inset, `PrimaryButton` r12) is therefore **correct** and should not be "fixed".

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| RAD-01 | MEDIUM | `RecapCard.swift:88-98` (r12, `:94`) in card r20 (`:100-101`), inset 16 · `TrophyCaseView.swift:134-158` (link r12 `:155`) in card r20 (`:161`) · `TrophyCaseView.swift:215-233` (rows r12 `:232`) in card r20 (`:237`) | Well r12 at 16pt inset in r20 → concentric would be **4** | Preferred: let the well sit **8pt** from the card edge (`.padding(-Theme.Spacing.xs)` on the well, card padding stays 16) so r12 = 20 − 8 is exact. Otherwise `Theme.Radius.nested(.medium, inset: 16) = 4` | The corner gap between the two arcs is ≈ 19.3pt vs 16pt on the straight edge — a "loose corner" that is small per instance but repeated on every nested surface. |
| RAD-02 | MEDIUM | `CosmeticsShopView.swift:279-286` (44pt r12 tile in the card's **top-left corner** at 16 inset; card r20 `:313`) · `:319-332` (`PrimaryButton` r12 at the bottom corner) · `SettingsView.swift:423-431` (`PrimaryButton` r12 in `proUpsellCard` r20) | Corner-hugging r12 inside r20 | Tile → `Circle()` (every other icon badge in the app is a circle: `LockStatusCard.swift:71`, `GhostProgressBanner.swift:128`, `FounderSeriesCard.swift:130`, `GoalRow.swift:157`) — removes the concentricity problem *and* the shape outlier. Buttons: RAD-01 rule | `Screen14FirstWin.swift:328-330` has the same outlier: a 96pt tile at r12 (12.5 % of its side; iOS icons ≈ 22 %) → `Theme.Radius.medium`. |
| RAD-03 | LOW | `ProgressView.swift:340` (`RoundedRectangle(cornerRadius: 3)`, tiles ≈ 43.6pt) | Magic number (one of only three in the repo); 7 % of the tile vs 20–28 % everywhere else | `Theme.Radius.small`, or the `nested` helper (concentric for a 16 inset in r20 is 4 — so 3 is "accidentally right" but unowned) | Grid spacing `4`/`4` (`:335, :338`) is also not a `Spacing` token. |
| RAD-04 | LOW | `PrimaryButton.swift:100-110` | Hold fill is a `RoundedRectangle(r12)` *inside* an r12 track, sized by `width * progress` | Clip a `Rectangle` fill with the button's shape | At < 24pt width the radius clamps and the fill draws as a squashed pill; the trailing edge shouldn't be rounded while it's moving. |
| RAD-05 | LOW | Icon-badge diameters: 32 (`GoalRow.swift:163`, `AlwaysAllowedWarningView.swift:132`, `PaywallView.swift:183`, `FuelView.swift:967`), 36 (`SettingsView.swift:964`), 40 (`LockStatusCard.swift:73`, `GhostProgressBanner.swift:134`, `FounderSeriesCard.swift:136`), 44 (`CosmeticsShopView.swift:282`), 52 (`ProgressView.swift:359`), 60 (`TrophyCaseView.swift:295`), 96 (`ShieldPreview.swift:166`, `Screen12PermissionPriming.swift:34`, `Screen14FirstWin.swift:139`) | Seven sizes, no scale, ≥ 12 hand-built copies of "circle @ 0.16 + glyph" | `IconBadge(systemName:tint:size: .small 32 / .medium 44 / .large 96)`; glyph = 0.45 × diameter | Prior review (`apple-design-review.md` §8.2) flagged 32/40 only; it's seven. |

### 2.5 Optical alignment

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| ALN-01 | LOW (latent) | `GoalRow.swift:151-165` | Leading slot is a 44pt ring **or** a 32pt icon circle, so the title's x-position differs by 12pt between rows in one list. `PreviewCatalog.swift:165-187` already mixes them; no live call site passes `progress:` yet (Fuel, Onboarding 10 and Paywall all use the icon variant), so it bites the day one does | Fixed 44pt leading slot; centre the 32pt badge inside it | Columns of text should share a left edge. |
| ALN-02 | MEDIUM | `RingCluster.swift:98-106` (`.row` in `ScrollView(.horizontal)`) | Content is leading-aligned; when it fits it hugs the left with dead space on the right (Fuel: 33pt; 3×`.medium`: 41pt) | `ViewThatFits` (BRK-05): centred / equal-width cells when it fits, scroll only when it can't | |
| ALN-03 | LOW | `StreakPill.swift:40, 55` (13pt flame vs 17pt digits) · `TrophyCaseView.swift:373-386` & `CosmeticsShopView.swift:346-359` (12pt seal vs 17pt digits) · `TimeBankBar.swift:54-62` · `RecapCard.swift:141-149` | `HStack` default `.center`; symbol smaller than the text's cap height (≈ 0.76 em) | `HStack(alignment: .firstTextBaseline)`; symbol ≈ 1 em of the adjacent text (skill: 1–1.25 em) | The `.firstTextBaseline` is already right at `TodayView.swift:164` and `SettingsView.swift:410`. |
| ALN-04 | LOW | `lock.fill`/`lock.open.fill` in circles: `LockStatusCard.swift:74`, `ShieldPreview.swift:180`, `TrophyCaseView.swift:307` · `bell.badge.fill` `Screen12PermissionPriming.swift:35` · `flag.checkered` `GhostProgressBanner.swift:130` | Geometrically centred asymmetric glyphs | Nudge: locks up ≈ 1pt (body sits low in the glyph box), bell ≈ +2pt x (badge widens the box), flag ≈ −1pt x | Skill "asymmetric icons". *Not verified visually.* |
| ALN-05 | LOW | `UnlockCelebrationView.swift:189` (`weight: .bold` beside a semibold label) · `Screen14FirstWin.swift:343` | Icon weight one step heavier than adjacent text | Match: semibold beside semibold (2px-equivalent) | Skill: stroke tracks text weight. |
| ALN-06 | LOW | `FuelView.swift:422-450` | `quickAddRow(label:)` takes a `label` and never renders it; the two chip rows (protein, water) are distinguished only by colour and unit | Render the label (or drop the param) | Colour-only differentiation. |

### 2.6 Contextual icons

"After" symbols are named from memory of the SF Symbols catalog; verify each in the SF Symbols app before shipping (no Mac here).

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| ICO-01 | MEDIUM | `TrophyCaseView.swift:307-310` | Every locked milestone is the same `lock.fill` — six identical padlocks for a new user | Show the milestone's *own* glyph at ≈ 30 % with a small lock badge (reuse the cutout ring from `ShieldPreview.swift:184`) | The point of a trophy case is to show what there is to win; today the icons carry zero information. Also raise the locked label above 2.56 : 1 (`:334`, `.opacity(0.55)` on the whole tile). |
| ICO-02 | MEDIUM | `CosmeticsShopView.swift:279-286, 380-419` | A shop of *visual* goods with abstract glyphs (`circle.lefthalf.filled`, `circle.dashed`, `target`, `waveform.circle.fill`) | Preview the thing: theme = colour swatches, ring style = a live mini `GoalRing`, shield = a thumbnail, coach pack = its icon | Most "slop" per pixel on this screen: you're asked to spend coins on something you can't see. |
| ICO-03 | MEDIUM | `Screen3MainGoal.swift:94-103` · `Screen7FallOff.swift:51-60` · `Screen8CoachVoice.swift:55-70` · `SettingsView.swift:201-215` | Onboarding Q1/Q5/Q6 and the Settings voice picker are text-only rows | Q1: `dumbbell.fill`, `fork.knife`, `iphone.slash`, `book.closed.fill`, `sparkles`. Q5: `calendar`, `moon.stars.fill`, `waveform.path.ecg`, `chart.line.downtrend.xyaxis`, `airplane`. Voices: reuse the cosmetics coach-pack vocabulary already defined at `CosmeticsShopView.swift:401-405` (`megaphone.fill`, `flame.fill`, `leaf.fill`, `chart.bar.fill`) | Scannability and personality on the highest-attention screens; it also makes the voice picker feel like a *choice of coach*. |
| ICO-04 | MEDIUM | `FuelView.swift:472-479, 607-616` (`GoalRow(status: .pending)` used as an action) | The trailing empty `circle` reads as an unchecked checkbox on rows that are *tap-to-log* | Trailing `plus.circle.fill` (add a `GoalRow.trailing` style) | Semantics of the indicator are "goal not done", not "tap to add". |
| ICO-05 | MEDIUM | `TrophyCaseView.swift:138` (`bag.fill` → Cosmetics Shop) vs `SettingsView.swift:346` (`paintpalette.fill` → same destination, with a comment at `:332-334` explaining `bag.fill` is reserved for the physical gear store at `:473`) | Two icons for one destination; one contradicts the codebase's own rule | `paintpalette.fill` | |
| ICO-06 | MEDIUM | `hourglass` for three concepts: `TimeBankBar.swift:55` (balance remaining), `RecapCard.swift:132` (weekly reclaimed), `ProgressView.swift:146` (lifetime reclaimed). `seal.fill` for coins (`TrophyCaseView.swift:374`, `CosmeticsShopView.swift:347, 328`) while `checkmark.seal.fill` = goals completed (`RecapCard.swift:129`) and `checkmark.seal` = *not verified* (`Screen14FirstWin.swift:261`) | Overloaded glyphs | Bank: `hourglass.bottomhalf.filled`; reclaimed: `clock.arrow.circlepath`; coins: `centsign.circle.fill`; not-verified: `arrow.counterclockwise.circle` (calm, no shame — spec §8 rule 9) | A muted *checkmark* seal on the "not verified" screen tells the wrong story. |
| ICO-07 | LOW | `PaywallView.swift:210` (every "your plan" goal is `target`) | Generic | The goal-type glyphs used everywhere else (`dumbbell.fill`, `fork.knife`, `timer`); `BuiltPlanSummary` needs to carry the type | |
| ICO-08 | LOW | `GhostProgressBanner.swift:141-145` (`person.fill` vs `person`) | "You vs ghost" as filled/outline person | `figure.run` at full colour vs the same glyph at ≈ 0.4 opacity | The feature is literally *racing a ghost*; the banner's `flag.checkered` (`:130`) is the right register, the scoreboard isn't. |
| ICO-09 | LOW | `ProgressView.swift:387-397`, `TrophyCaseView.swift:171-176`, `UnlockCelebrationView.swift:56-60, 245` (the sample badge) | `star.circle.fill`, `fork.knife.circle.fill`, `flag.checkered.circle.fill`, `arrow.uturn.forward.circle.fill` rendered *inside* a 52/60pt circle | Non-circled variants (`star.fill`, `fork.knife`, `flag.checkered`, `arrow.uturn.forward`) | Circle inside a circle; mixed with bare-glyph siblings (`dumbbell.fill`) in one grid. |
| ICO-10 | LOW | `FuelView.swift:494-500` | Restaurant tier = `fork.knife` (already the protein ring's glyph: `TodayView.swift:219`, `FuelView.swift:403`, `Screen10PlanReveal.swift:182`); snack = generic `bolt.fill` | Restaurant → `mappin.and.ellipse`; snack → a food glyph | `refrigerator` for kitchen staples is the model of a contextual pick. |
| ICO-11 | LOW | `AlwaysAllowedWarningView.swift:128` | `exclamationmark.triangle.fill` | `lock.trianglebadge.exclamationmark` (lock-bypass warning) | Same tone, contextual. |
| ICO-12 | LOW | `Screen10PlanReveal.swift:55-59` | `LockStatusCard(isLocked: true)` — danger-red padlock — on the "starting easy on purpose" reveal, before the user has committed | Neutral/accent variant for a *proposed* lock | Tone ("calm, motivating, not punishing", §16 P2/P4). |

### 2.7 Press states, icon swaps, motion recipes, button states

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| MOT-01 | LOW | `PrimaryButton.swift:235` (0.97), hold `:116` (0.98), `GoalRow.swift:205` / `GhostProgressBanner.swift:189` (0.98), `AlarmRingingView.swift:418` (0.97) | Four values | Skill: press scale is exactly **0.96**. Buttons/chips → 0.96; full-width rows may keep 0.98 as a *documented* deviation (a 4 % shrink of a 361pt card is 14pt) — implementer's call | Consistency; add a `static` opt-out. |
| MOT-02 | MEDIUM | No press state: `LockStatusCard.swift:60-61`, `PaywallCard.swift:108`, `Screen3MainGoal.swift:115` / `Screen4AppSelection.swift:91` / `Screen7FallOff.swift:72` / `Screen8CoachVoice.swift:82`, `FuelView.swift:894`, `TrophyCaseView.swift:158`, `CosmeticsShopView.swift:185`, `LockedOutMomentView.swift:399`, `WeeklyRecapShareView.swift:242`. Duplicated: `GoalRow.swift:200-209` = `GhostProgressBanner.swift:184-193` | `.buttonStyle(.plain)` swallows the press state on the most-tapped cards (Today's lock card, the paywall plan cards, onboarding options) | One `PressableStyle` in `Core/UI` (scale + opacity, `springGesture`, reduce-motion gated, `static` variant). Two copies + ≥ 10 missing sites clears CLAUDE.md's "three call sites" bar | Response on touch-down. |
| MOT-03 | MEDIUM | Icon swaps: `LockStatusCard.swift:74` (`lock.fill` ↔ `lock.open.fill` — the product's core moment — has **no** `contentTransition`, unlike `StreakPill.swift:51` / `GoalRow.swift:188`); `PaywallCard.swift:62`; bare-`if` check marks at `Screen3MainGoal.swift:99-102`, `Screen7FallOff.swift:56-59`, `Screen8CoachVoice.swift:61-64`, `SunriseAlarmSetupView.swift:259-262`, `SettingsView.swift:211-214` | Pop in/out | Same-family swaps: `.contentTransition(.symbolEffect(.replace))` (opacity when Reduce Motion). Appear/disappear: skill values — scale 0.25 → 1, opacity 0 → 1, blur 4 → 0 (`.transition(.scale(scale: 0.25).combined(with: .opacity))` + a blur modifier), driven by `.spring(duration: 0.3, bounce: 0)`. `Theme.Motion.springStandard` (`Theme.swift:191`, damping 0.82) has bounce ≈ 0.18; skill: icon bounce is always 0 → add `Theme.Motion.iconSwap` | Lock → unlock is where this should sing (add one `.symbolEffect(.bounce)` on the earned edge only). |
| MOT-04 | MEDIUM | `PrimaryButton.swift:70, 117`; states at `TodayView.swift:296, 313, 322-327, 329, 330-331` | Disabled = accent @ 50 % (olive `#618424`). Five of Today's eight primary-action states are disabled buttons — including **"Open Fuel", a CTA that does nothing** (`:330-331`) | Disabled = `surface2` fill + `muted` label. "Focus running", "verifying at gym", "all done" are *status*, not actions: render them as a status row (icon + live text) and keep accent fill for actionable CTAs only | A dimmed acid-green button still reads as "the primary thing". The screen has no honest primary state half the time. |
| MOT-05 | MEDIUM | `LockStatusView.swift:277-283` → `PrimaryButton.swift:104-114` | Emergency unlock uses the *earned/unlock* accent (hold fill + border hard-coded) | `PrimaryButton(tint: .danger)` / `.warning`; the alarm ring (`AlarmRingingView.swift:414`) and `Screen14FirstWin.swift:553` already use `danger` | Spec §15: one accent = earned. The exit that costs a streak shouldn't wear it. |
| MOT-06 | MEDIUM | `CosmeticsShopView.swift:316-333` | A full-width accent `PrimaryButton` on every card, 5 per category; "Equipped" is a *disabled* 50 % accent button next to an accent "Equipped" capsule (`:293-301`) | Compact trailing pill (price / Equip); accent only on the one primary action; equipped = a checkmark state, not a dead button | Five equal CTAs = no CTA. |
| MOT-07 | LOW | `Screen1Hook`, `9`, `10`, `11`, `12`, `14` (static blocks); `OnboardingContainerView.swift:120-125` (full-width slide **both** in and out) | One chunk per screen | Skill: infrequent staged entrances → 100ms stagger per semantic chunk (icon → headline → subline → CTA), `opacity 0→1` + 8pt rise, ease-out `timingCurve(0.2, 0, 0, 1)`; exits softer than enters (opacity + ≈ 12pt) | Onboarding is once-ever; sequence can carry hierarchy. |
| MOT-08 | MEDIUM | Ungated motion (the rule is "everywhere"): `UnlockCelebrationView.swift:213-230` · `FuelView.swift:895` · `OnboardingContainerView.swift:97, 120-125, 176` · `PaywallView.swift:261` · `PaywallCard.swift:109` · `Screen2SocialProof.swift:74` · `Screen3MainGoal.swift:116` · `Screen5PhoneTime.swift:27` · `Screen7FallOff.swift:73` · `Screen8CoachVoice.swift:83` · `Screen9WakeUp.swift:191` · `Screen14FirstWin.swift:229, 336 (`.repeating` pulse), 569, 624-627` · `TrophyCaseView.swift:310` | 13 live files still animate under Reduce Motion (`Screen13Paywall.swift:130` is dead code) | `reduceMotion ? nil : …` (`Theme.Motion.standard(reduceMotion:)` exists) | Preserve the prior wave's rule; `UnlockCelebrationView` is the worst — its own comment says it respects Reduce Motion but only the *delays* are skipped, the 0.86 → 1 spring still plays. |
| MOT-09 | LOW | `Screen5PhoneTime.swift:24-27` | `.animation(springStandard)` on a `Text` whose string changes — nothing to interpolate, so the hero number snaps | `.contentTransition(.numericText())` (as `Screen9WakeUp.swift:178` does) + `.sensoryFeedback(.selection, trigger:)` per step | |
| MOT-10 | LOW | `TimeBankBar.swift:88-92` | `repeatCount(3, autoreverses: true)` on a `toggle()` — odd count ends on the target, so after the warning pulse the fill stays at 0.7 opacity | Animate an `Int` pulse counter / `keyframeAnimator` and return to 1.0 | *Not verified by render.* |

### 2.8 Hierarchy / "is it slop?" — type tokens and screen verdicts

| ID | Sev | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| TYP-01 | MEDIUM | `Theme.swift:149-172` (largest token 44pt); ad-hoc `.system(size:)` display type at `Screen1Hook.swift:40` (34 rounded), `PaywallView.swift:160` (30 rounded), 56/64pt heroes at `Screen14FirstWin.swift:227`, `Screen1Hook.swift:35`; `AlarmRingingView.swift:192-194` (alarm clock = 44pt; its own comment admits the token gap); `Screen9WakeUp.swift:103, 118-123` (the wake-up numbers 44/28); `UnlockCelebrationView.swift:164` ("Earned." 44) | No display/hero step; three different headline sizes/designs (34r, 30r, 22 default) | `Theme.Typography.display` (34 bold rounded) and `numeralHero` (72–96 bold rounded, `monospacedDigit`) | The emotional peaks (wake-up stat, alarm clock, earned unlock) are the same weight as body UI. 66 `.system(size:)` calls in 29 files — most are icons, but the display ones are the tokens Theme is missing. |
| TYP-02 | MEDIUM | `GoalRing.swift:173`; `RingCluster.swift:145-152` | `.large` (148pt) ring centre text uses `numeralMedium` (28pt) — same as `.medium` (88pt); `numeralLarge` is documented for "the Today ring's center number" (`Theme.swift:150-153`) yet no ring uses it; cluster cells only ever pass `centerIcon`, so the grams/minutes sit as a 13pt caption *under* the ring | `GoalRingCenter.value(String, unit: String?)` — big number (44 at `.large`) over a small unit; cluster passes the number into the ring | §15: "big numerals for grams/minutes/streak". The alarm steps/focus rings and first-win countdown show the same undersized centre. |
| TYP-03 | LOW | `TodayView.swift:163-175` (custom 22pt in-content title) vs `.navigationTitle` large titles at `FuelView.swift:274`, `ProgressView.swift:135`, `SettingsView.swift:172`, `TrophyCaseView.swift:110`, `CosmeticsShopView.swift:101`; inline at `LockStatusView.swift:79-80` | Three title treatments across sibling tabs | One pattern | |
| TYP-04 | LOW | `FuelView.swift:1175-1178` | A whole sentence ("12g protein per serving") set in `numeralMedium` | Number in `numeralMedium`, unit/sentence in `body` | Type role misuse. |
| TYP-05 | LOW | `TrophyCaseView.swift:329` | `.font(.system(size: 10))` earned-date | `Theme.Typography.caption` | 10pt is below the smallest token (13) and off-token. |

#### Screen-by-screen verdict (opinionated)

| Screen | Verdict | Direction |
| --- | --- | --- |
| **Today** | Three stacked flat cards; hero row scrolls (BRK-05); rings carry an icon, the number is a caption; five disabled-button states (MOT-04) | One hero ring (workout) with a big centre numeral + two `.medium`; lock card becomes the status header; status rows instead of dead CTAs |
| **Lock** | Four near-identical `surface` cards (`LockStatusView.swift:123-261`); the answer to "how long?" is `"N min available"` in 17pt (`:250`); hand-rolled `goalRow` (`:213-238`) duplicates `GoalRow` with different padding | Hero = remaining Time Bank as `numeralHero` over a glowing bar; use `GoalRow`; emergency in danger tint at the bottom |
| **Fuel** | Two large rings hugging the left, chip rows with a 32pt target and the barcode scan hidden at the end of a scroll (`:431-448`); sheets are stock `Form` | Rings in one card with centre numerals; chips 44pt, "Scan barcode" as a real secondary button; themed sheets |
| **Progress** | Time Reclaimed hero is right (`numeralLarge`, `:154`) but flat; the streak grid starts 27 days ago so columns aren't weekdays and there is no today marker, legend or labels (`:327-334`); unearned days 1.08 : 1 | Weekday-aligned grid, today ring, DEP-03 track; badges keep the accent |
| **Settings** | Stock iOS list in a different design language (DEP-05); voice picker is the brand's personality and is text rows | `themedList()`; voice picker as icon cards (ICO-03) |
| **Onboarding 1** | `lock.iphone` + one headline on black — first impression is a tutorial | Hero visual + `HeroGlow`, staged entrance, `display` type |
| **Onboarding 2** | Plain centred quotes; pager dots 1.16 : 1 (`Screen2SocialProof.swift:72`) | Quote cards with attribution/stars; visible dots |
| **Onboarding 3–8** | Text-only rows; Q4 is two system steppers; Q3's hero number snaps | Icons (ICO-03), custom steppers with a visible current → target relationship, `numericText` |
| **Onboarding 9** | The emotional peak uses 44/28pt numerals | `numeralHero`, danger → accent contrast, staged reveal |
| **Onboarding 10** | Spec says "looks bespoke" (§7.10); it is `LockStatusCard` + `GoalRow`s + a text card, no app icons | Compose one plan card; show the picked apps' icons with FamilyControls' `Label(token)` (API not verified here); "starting easy on purpose" tag |
| **Onboarding 11** | The commitment gesture is a 46pt bar with an unreadable label (BRK-02), spec P4 says "progress *outline*" | Ring hold (same grammar as the alarm's) with the count-up haptics already there |
| **Onboarding 13 (Paywall)** | Scrolling page; the CTA is the last item inside the scroll view (`PaywallView.swift:306-326`); restore/free links 16pt (HIT-02); 3 loading spinners are the Progress tab (BRK-01) | Pin the CTA in `safeAreaInset`; plan cards unchanged (selection state is the best in the app) |
| **Onboarding 14** | First win reuses none of `UnlockCelebrationView`; its own multi-colour confetti (`:598-604`, 5 hues) breaks "ONE accent"; weaker than every later unlock | Reuse `UnlockCelebrationView` + `CelebrationBurst`; the *first* earned unlock should be the biggest |
| **Shield / Celebration** | Flat black + a 96pt circle (`ShieldPreview.swift:162-195`); the payoff "2h 10m unlocked" is a 13pt label (`TimeBankBar.swift:58-60`) | `HeroGlow`; the minutes as `numeralHero` |
| **Alarm** | 44pt clock, `ProgressView()` bug, 22pt snooze target | `numeralHero` clock, 44pt snooze, keep the ring escape hatch |
| **Trophy / Shop** | Six identical padlocks; shop shows nothing (ICO-01/02) | Silhouettes + previews |
| **Share cards** | Export is the least designed artefact (BRK-03/04, DEP-04); the Locked-Out card is three lines of text on a gradient (`LockedOutMomentView.swift:513-520`, `dayRings: []`) | Big padlock/app glyph + numeral hero; safe-zone aware |

*Reference patterns recalled from memory, not fetched this run:* Apple Activity rings (track = darker tint of the ring's own hue, round caps); glanceable fitness dashboards (one hero number + unit, everything else subordinate); dark-mode products (Linear, Arc) that separate surfaces with a 1px translucent white edge instead of shadows.

---

## 3. Proposed `Theme` / component additions (for the fix wave — `Theme.swift` was not edited)

Each is justified by ≥ 3 call sites in this audit (CLAUDE.md's abstraction bar).

```swift
// Theme.Colors
static let edge       = Color.white.opacity(0.08)   // card ring. Pure white — never `text` (tinted edge reads as dirt)
static let edgeStrong = Color.white.opacity(0.13)   // pressed / selected-neutral
static let track      = Color.white.opacity(0.10)   // bars, dots, empty tiles
static let hairline   = edge                        // fixes the 8 existing call sites (DEP-01)
// Theme.Radius
static func nested(_ outer: CGFloat, inset: CGFloat) -> CGFloat { max(outer - inset, 0) }
// Theme.Metrics
static let minTapTarget: CGFloat = 44
// Theme.Typography
static func display() -> Font      // 34 bold rounded
static func numeralHero() -> Font  // 72–96 bold rounded, monospacedDigit
// Theme.Motion
static let iconSwap: Animation = .spring(duration: 0.3, bounce: 0)
```

| Piece | Replaces | Sites |
| --- | --- | --- |
| `.zanoCard(radius:)` / `.zanoWell()` | inline `background(surface…, in: RoundedRectangle…)` | 31 (DEP-02) |
| `IconBadge(size:)` | hand-built "circle @ 0.16 + glyph" | ≥ 12 (RAD-05) |
| `PressableStyle` | two duplicated `RowPressStyle`s + missing states | ≥ 12 (MOT-02) |
| `.minTapTarget()` | ad-hoc `frame`/`contentShape` | ≥ 20 (§2.2) |
| `HeroGlow` | flat hero backdrops | 5 (DEP-06) |
| `themedList()` | stock `List`/`Form` | ≥ 12 (DEP-05) |
| `PrimaryButton(tint:)` + `.disabled` restyle | accent-only, 50 % dim | MOT-04/05 |

`ZANOWidgetColor` and the Watch theme duplicate token values; if `hairline`/`track` change, those copies are not updated automatically.

---

## 4. Already right — don't regress

- Token discipline: only 3 raw radii repo-wide (`ProgressView.swift:340`, `CelebrationBurst.swift:161, 163`); every corner `.continuous`.
- `ShieldPreview`: cut-out ring on the lock badge (`:184`), staged one-shot reveal, and the 44pt emergency target (`:143-144`).
- `PaywallCard`: selection border is `strokeBorder` (no layout shift when 1 → 2pt); the strongest selected state in the app.
- `TodayView` header uses `.firstTextBaseline` (`:164`); `SettingsView.proUpsellCard` too (`:410`).
- Contextual picks worth copying: `refrigerator` (`FuelView.swift:496`), `barcode.viewfinder`, `zzz` snooze, `sunrise.fill` / `moon.zzz.fill`, `infinity` / `brain.head.profile` / `person.3.fill` (`PaywallView.swift:169-171`), OS-tier-aware `alarm.waves.left.and.right.fill` vs `bell.badge.fill` (`SunriseAlarmSetupView.swift:412`), `flame` → `flame.fill` streak ramp (`ProgressView.swift:391-392`).
- `RecapCard` / `UnlockCelebrationView` staged reveals, `TrophyTile` earned-edge celebration structure, `GoalRing` completion pulse.
- Reduce-Motion gating in Core components (GoalRing, RingCluster, StreakPill, GoalRow, LockStatusCard, TimeBankBar, PrimaryButton, ShieldPreview, RecapCard) is in place.

## 5. Fixed since the earlier design docs (credited, not repeated)

`PrimaryButton` horizontal padding (`:91-92`); `ShieldPreview` emergency 44pt; `RowPressStyle` on `GoalRow`/`GhostProgressBanner`; `GoalRow` haptic direction gate; `TrophyCaseView` `chevron.forward`; `StreakPill` frozen label; reduce-motion in the components above. Still open from those docs and re-confirmed: `ProgressView.swift:229` and `Screen4AppSelection.swift:76` still use non-mirroring `chevron.right` (LOW, RTL).

## 6. Suggested batching for the fix wave (to avoid file collisions)

1. **`Theme.swift` + new `Core/UI` files** (tokens, `.zanoCard`, `IconBadge`, `PressableStyle`, `.minTapTarget`, `HeroGlow`, `themedList`) — everything else depends on this.
2. **`Core/UI/Components/*`**: BRK-02, BRK-03/04, DEP-02/03, RAD-04, HIT-04, ALN-01/02/03, MOT-01…05, TYP-02.
3. **One-line/mechanical app fixes:** BRK-01, HIT-01…03/05, MOT-08, chevrons.
4. **Screen redesigns** (Today, Lock, Fuel, Progress, Onboarding 1/9/10/11/13/14, Shield/Celebration, Alarm, Trophy/Shop) — per §2.8, after 1–2 land.
5. **Coordinate with the concurrent workflow:** renaming `ProgressView` and any tab-bar/`Assets` change touch its files.

## 7. Not verified (could not be run here)

- **Every visual claim.** No render of any screen; contrast/ratio numbers are computed, geometry claims (500pt row, 380pt strip, 40pt target) are layout arithmetic on the code's own constants and standard iPhone widths (393pt).
- Whether `ProgressView()` really resolves to the app's screen (Swift shadowing rule + the repo's own comments say yes; no compiler).
- Optical nudges (ALN-04/05) and the exact feel of every recommended radius/inset — need a Simulator pass.
- SF Symbol names in §2.6 "After" (from memory) and `Label(ApplicationToken)` for app icons (Onboarding 10) — check availability/behaviour on a Mac.
- Dynamic Type, VoiceOver, RTL: covered by `ui-stress-test-findings.md`, not re-run.
- State coverage per the skill (hover/focus/active/loading/empty): read from code only; loading (BRK-01) and disabled (MOT-04) states are the ones this audit found broken.
- Motion timing at 10 % speed: no browser/Simulator; durations and curves read from code only.

---

**Result: Block** — 7 HIGH remain (BRK-01…05, HIT-01, HIT-06). Everything else is queued work in the tables above.

**Counts:** 58 root-cause rows — 7 HIGH · 27 MEDIUM · 24 LOW (BRK 5 · HIT 7 · DEP 8 · RAD 5 · ALN 6 · ICO 12 · MOT 10 · TYP 5).
