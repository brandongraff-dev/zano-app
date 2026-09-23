# Typography + Color Audit (design-quality wave)

Audit of `Core/Sources/Core/UI/**` and `App/ZANO/Features/**` against `docs/spec.md` §15, using the
`interfaces:better-typography` and `interfaces:better-colors` rubrics (translated from web/CSS to
SwiftUI). **Read-only pass — no source file was edited.** Nothing in this app has ever been rendered
(no Mac/Simulator), so every finding below is derived from reading the code and from contrast math on
the declared token values; see "Verification" for exactly what was and was not checked.

Files audited: every file under `App/ZANO/Features/**` (33 files), every file under
`Core/Sources/Core/UI/**` (17 files) — each opened and read, with every `.font(`/colour site read in
context and long header comments skimmed — plus a repo-wide grep for raw colors/fonts, `Copy/*`,
`Extensions/ZANOWidgets/Support/ZANOWidgetColor.swift`,
`Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift`, `project.yml`, and the two
files in the forbidden set that decide global appearance (`ZANOApp.swift`, `ContentView.swift` — read
only, not edited). Prior corroborating docs: `docs/design/ui-stress-test-findings.md` (§1.2 Dynamic
Type, §8 onboarding Reduce Motion).

**Verdict: Block.** Five HIGH findings remain (T1, T2, C1, C2, C4). The design *system* is sound and
disciplined at the token level; the *application* of it is what reads as tutorial-grade.

---

## 0. The short version

**Typography.** The scale is followed almost perfectly (77% of `.font(` calls use `Theme.Typography`;
only 3 text sites use ad-hoc sizes, 3 more use system text styles; the other 57 non-token calls are
SF Symbol icon sizes). The problem is the opposite of drift: the scale is *too small a
vocabulary* and the numeral tiers the spec calls out ("big numerals for grams/minutes/streak") are
barely used — **numeral tokens are 17 of 222 token references (7.7%); `caption` + `captionEmphasized`
are 113 (51%)**. The three headline numbers of the product — protein grams, focus/time-bank minutes,
streak — all render at 13–17pt. There is no display tier, no eyebrow tier, no unit tier, no tracking,
no leading control, and nothing scales with Dynamic Type.

**Color.** The ONE-accent rule is *not* violated by literals: there is not a single `.blue`,
`.green`, `Color(...)`, `.white`, `.black`, or raw hex in `Features/**` or `Core/UI/Components/**`
(only `Theme.swift` defines hex). The violations are implicit: **no global tint exists**, so every
un-styled system control renders system blue (`#0A84FF`); ~12 screens use raw `List`/`Form`; the
accent has accreted five jobs; and the ring palette has hue collisions. Body/muted contrast on solid
surfaces is fine (muted 5.2–6.1:1). The real contrast failures are *composite* backgrounds
(hold-to-commit fill, alarm tint pulse, dimmed locked tiles) and near-invisible surface/track/hairline
separation (1.06–1.16:1).

### Fix-first order (highest leverage per hour)

1. **C1** Hold-to-commit label goes 1.1:1 as the fill sweeps (safety-critical: Emergency Unlock uses it).
2. **C2/C13** Set a global tint + AccentColor asset + forced-dark root (needs the parallel workflow's files).
3. **T2** Make `Theme.Typography` Dynamic-Type-aware (single-file change, fixes every screen).
4. **T3** Add a `NumeralText(value:unit:)` treatment and put real numerals on Today, Fuel, Lock, Progress.
5. **T1** Fix ShareCard export scale (exported text is 3.4x smaller relative to canvas than the preview).
6. **C4** Alarm screen: text on the pulsing tint fails AA for most of the cycle.
7. **T4/T5** Add `display`, `eyebrow`, `unit`, icon tokens + a `zanoText(_:)` modifier (tracking/leading).
8. **C5** Raise track/hairline/surface separation; **C8** de-collide the ring palette.

---

## 1. Measured facts (derived from the code, reproducible)

| Fact | Value | Where |
| --- | --- | --- |
| `.font(` call sites in Features + Core/UI (excl. Theme.swift) | 283 | grep |
| via `Theme.Typography.*` | 218 (77%) | grep |
| `.font(.system(size:...))` | 60 (57 are SF Symbol icons, 3 are text) | grep |
| system text styles (`.body`, `.caption`, `.footnote`) | 3 (the only Dynamic-Type-aware fonts in the app) | `LockSetupView.swift:219,222`, `Screen4AppSelection.swift:77` |
| Distinct ad-hoc icon point sizes | 17 (11,12,13,14,15,16,17,18,20,22,24,32,36,40,44,56,64) | grep |
| Token references: numeralLarge / Medium / Small | 5 / 4 / 8 | grep |
| Token references: title / headline / body | 16 / 36 / 40 | grep |
| Token references: caption / captionEmphasized | 81 / 32 (= 51% of all) | grep |
| `.tracking` / `.kerning` / `.lineSpacing` / `@ScaledMetric` / `.dynamicTypeSize` | 0 / 0 / 0 / 0 / 0 | grep |
| Raw hex / `Color(...)` / `.blue` etc. in Features + Core/UI | 0 | grep |
| `.tint(...)` calls in the whole app | 7 (all local; none at root) | grep |
| `.preferredColorScheme(.dark)` real call sites | 22 (+11 more inside `#Preview` blocks). `AlarmRingingView` and `UnlockCelebrationView` set it only in previews | grep |
| Raw `List` / `Form` screens and sheets | 11 | see C3 |
| Files in Onboarding using `accessibilityReduceMotion` | 0 of 17 | grep |

Full contrast table is in Appendix A.

---

## 2. Typography findings

### 2.1 Type scale — the numeral system exists but is not applied

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM (design priority P0) | **T3.** Today: `TodayView.swift:226,229` (ring `centerIcon` only), `RingCluster.swift:153-162` (value in `caption` under ring), `StreakPill.swift:58-60` (streak at `numeralSmall` 17pt). Fuel: `FuelView.swift:402,414` (`"72/150g"` flat string), rings `.large` with icon center. Lock: `LockStatusView.swift:250-252` ("N min available" at 17pt), `TimeBankBar.swift:58-59` (13pt label). Progress: `ProgressView.swift:181` (streak = 17pt pill; only Time Reclaimed gets `numeralLarge` at `:154`). Recap/Share: `RecapCard.swift:146-148`, `ShareCard.swift:101-103` (stats as one caption/headline sentence). Paywall: `PaywallCard.swift:89-91`. `GoalRing.swift:173` picks `numeralMedium` for `.medium` **and** `.large`, never `numeralLarge`, contradicting the doc on `Theme.swift:150` ("the Today ring's center number"). | The three numbers the spec says must be big (grams, minutes, streak) are 13–17pt `muted` text. Values are composed into flat `String`s (`"72/150g"`, `"2h 10m unlocked"`) so the unit cannot be styled separately. | Introduce a structured numeral treatment: number at `numeralLarge`/`numeralMedium`, unit at a new `unit` style (15pt semibold, `muted`, baseline-aligned, `.baselineOffset` if needed). Today/Fuel `.large` ring centers show the value (`GoalRing.center` becomes `.value(String, unit: String?)`); streak becomes a hero numeral with the pill as a secondary chip; Lock shows minutes remaining as `numeralLarge`; ShareCard stats become 3 numeral+unit cells (spec P7: "chunky bold numerals"). `RingClusterItem.valueText: String?` becomes `value: String?` + `unit: String?`. | Spec §15 "big numerals for grams/minutes/streak"; the hierarchy currently makes the *label* louder than the *data*. This is the single biggest reason the screens will read as generic. |
| LOW | **T3b.** Numeral tokens applied to whole sentences: `FuelView.swift:1176-1178` ("12g protein per serving" at 28pt, will wrap), `LockStatusView.swift:250-252`, `UnlockCelebrationView.swift:163-167` (the word "Earned." in `numeralLarge`), `Screen6Workouts.swift:59-61` ("3x/week" at 28pt), `Screen5PhoneTime.swift:24-26` ("6.5h" whole string at 44pt), `Screen9WakeUp.swift:154-155` (`OnboardingAnimatedCount` only holds the bare integer; the unit is a 13pt caption). | Rounded + `.monospacedDigit()` face applied to words and units. | Numerals for digits only; units via the `unit` style; words ("Earned.") via a new `display` token. Also `.contentTransition(.numericText(value:))` instead of `.animation(value:)` on `Screen5PhoneTime.swift:24-27` and the `Screen6` stepper text. | `monospacedDigit` is meaningless on letters; unit and digit share weight/size so the number does not read as the hero. |
| LOW | **T3c.** Numbers/units composed inside Views instead of `Copy`: `TodayView.swift:194` and `LockStatusView.swift:141,250` (`"\(n) min banked/available"`), `TodayView.swift:468` (`"Done"` / `"Not yet"`), `FuelView.swift:434,974` (`"+\(preset)\(unit)"`, `"\(Int(g))g protein"`). | Ad hoc strings in views. | Move to `Copy.*` when the numeral/unit split lands (CLAUDE.md copy rule). | Same root cause as T3: no structured value type. |

### 2.2 Missing tiers, hero/title inconsistency

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | **T4.** No display tier. `AlarmRingingView.swift:188-193` says so in a comment ("`Theme.Typography` has no numeral size larger than `.numeralLarge()`... flagging that gap"). Hero headlines are three different sizes: 22 (`Theme.Typography.title` on Screens 9-12, 14, `OnboardingQuestion.swift:55`), 30 rounded (`PaywallView.swift:159-160`), 34 rounded (`Screen1Hook.swift:39-40`). `UnlockCelebrationView.swift:164` borrows `numeralLarge` for a word. Alarm clock is 44pt = 11% of screen width on the most urgent screen. | Ad hoc `.system(size: 30/34, design: .rounded)` in two views; 22pt "hero" question titles. | Add `display` (34pt bold, rounded or default — pick one) for onboarding/celebration hero headlines; add `numeralHero` (64-96pt) for the alarm clock, the Today streak, and Time Bank. Replace the two ad-hoc calls. Decide once whether words may use `.rounded`; today rounded is "numerals and two hero lines". | Heading scale must descend by level and be named by use; three hero sizes with no token is drift by omission. |
| MEDIUM | **T4b.** Three screen-title treatments: Today draws its own 22pt `Text` (`TodayView.swift:165-167`); Lock/SunriseAlarm/BedtimeGate use `.inline` nav titles (`LockStatusView.swift:79-80`, `SunriseAlarmSetupView.swift:162-163`, `BedtimeGateSetupView.swift:90-91`); Progress/Fuel/Settings/Trophy/Cosmetics/LockSetup use the default **system large title** (34pt SF Pro Display, not from `Theme`): `ProgressView.swift:135`, `FuelView.swift:274`, `SettingsView.swift:172`, `TrophyCaseView.swift:110`, `CosmeticsShopView.swift:101`, `LockSetupView.swift:129`. | Three different sizes/weights for the same role, one of them outside the design system. | One tab-root header component (`display`-sized custom title + trailing accessory such as `StreakPill`) and `.toolbar(.hidden, for: .navigationBar)` on tab roots; pushed screens stay `.inline`. Coordinate with the `AppRouter`/tab-shell owner (forbidden path this run). | Consistent hierarchy; Today's "title + streak pill" is the right pattern, generalize it. |

### 2.3 Dynamic Type

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **T2.** `Theme.swift:151-171` (every token is `Font.system(size:)`); 60 more `.system(size:)` sites (icons); zero `@ScaledMetric` / `.dynamicTypeSize`. Only `LockSetupView.swift:219,222` and `Screen4AppSelection.swift:77` use system text styles — so at large accessibility sizes those three rows grow and everything around them does not. Already reported at `ui-stress-test-findings.md` §1.2 and still unfixed. | Fixed-size fonts do not respond to the user's text-size setting. | Build tokens from text styles (mapping below), `@ScaledMetric(relativeTo: .largeTitle)` for the 44+ numerals via a `NumeralText` view, and clamp with `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` on ring centers/pills. Pair with a `lineLimit`/`fixedSize` pass on `GoalRow`, `LockStatusCard`, `RingClusterCell`. | Low-vision users cannot enlarge any text in the app; this is the highest-leverage single-file fix. |

Proposed mapping (iOS default "Large" sizes, so nothing changes visually at the default setting):

| Token | Today | Proposed |
| --- | --- | --- |
| `caption` / `captionEmphasized` | 13 | `.footnote` (13) / + `.semibold` |
| `body` | 15 | `.subheadline` (15) |
| `headline` | 17 semibold | `.headline` (17 semibold) |
| `title` | 22 bold | `.title2` (22) `.bold` |
| `numeralSmall` | 17 rounded semibold | `.headline` + `.rounded` + `.monospacedDigit()` |
| `numeralMedium` | 28 rounded bold | `.title` (28) + `.rounded` + `.bold` + `.monospacedDigit()` |
| `numeralLarge` (44) / new `numeralHero` (64-96) | fixed | `@ScaledMetric(relativeTo: .largeTitle)` inside `NumeralText`, clamped |
| icons (17 ad-hoc sizes) | fixed | 3-4 named sizes (12 / 16 / 20 + hero 36 / 64) built from `.footnote`/`.body`/`.title3` so they track text |

### 2.4 Spacing: tracking and leading

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | **T5.** Uppercase eyebrows with no tracking (8 shipped + 1 dev): `Screen9WakeUp.swift:86-89`, `Screen10PlanReveal.swift:104-107`, `Screen11Commitment.swift:45-48`, `Screen12PermissionPriming.swift:41-44`, `Screen14FirstWin.swift:146-149`, `PaywallView.swift:197-200`, `GhostProgressBanner.swift:94-97`, `AlarmRingingView.swift:183-186`, `PreviewCatalog.swift:305-308`. "BEST VALUE" badge: `PaywallCard.swift:72-77`. Multi-line body with default leading (SF `subheadline` is ~1.33): `RecapCard.swift:88-91` (up to ~60 words), `SettingsView.swift:891-904` (NFC instructions), `OnboardingQuestion.swift:58-60`, onboarding subtitles (Screens 9-14), paywall disclaimers. Zero `.tracking` / `.lineSpacing` anywhere. | `captionEmphasized` + `.textCase(.uppercase)`, default tracking, default leading. | Add `Theme.Typography.eyebrow` (13 semibold caps, `.tracking(0.8)`) and `paragraph` (15, `.lineSpacing(3)`), and expose them through a `zanoText(_:)` `ViewModifier` — `Font` cannot carry tracking or leading, which is why no screen has them. `numeralLarge/Hero`: `.tracking(-0.5...-1)`. | Small caps need positive tracking; wrapped copy at 3+ lines needs about 1.4-1.5 leading. SF already applies size-based tracking to mixed case, so only caps and display sizes need manual values. |

### 2.5 Rendering surfaces

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **T1.** `ShareCard.swift:162-172`: `renderImage(size: 1080x1920 pt, scale: 1)` renders the same fixed-point type used on screen — title 22 (`:94`), stat 17 (`:102`), highlight 15 (`:109`), footer/day labels 13 (`:121`, `:139`), `GoalRing(.small)` 44pt (`:137`). Callers use the defaults: `WeeklyRecapShareView.swift:179`, `LockedOutMomentView.swift:334`. On-screen preview is capped at `maxWidth: 320` (`WeeklyRecapShareView.swift:160`, `LockedOutMomentView.swift:308`). | Title is 22/320 = 6.9% of card width in the preview the user approves, but 22/1080 = **2.0%** in the exported image (3.4x smaller relative to the canvas). The 44pt rings are 4% of width. The export is the thing that goes on Instagram/TikTok. | Render at the design size and scale up: `renderImage(content:, size: CGSize(width: 360, height: 640), scale: 3)` (still 1080x1920 px). Then design the card's own ramp for that 360pt canvas (numeral+unit cells per T3, `display` title). | Exported text is effectively unreadable and the export looks nothing like the preview. Derived from code (no render was possible). |

### 2.6 Truncation, tabular numerals, wrapping, size floor, punctuation, bidi

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | **T7.** Raw system chrome carries system fonts: `SettingsView.swift:159,563,722,866,1084`, `SunriseAlarmSetupView.swift:156`, `BedtimeGateSetupView.swift:47`, `LockSetupView.swift:106,364`, `FuelView.swift:917,1021`, `AppPickerView.swift` (says so at `:36-37`: "intentionally plain SwiftUI defaults. Session 5 ... owns final visual polish"). Rows with no `.font` render 17pt system body (`SettingsView.swift:244,251,314,320,340,346,358,366,373,377,473,501,506`); `LockSetupView.swift:219-223` uses `.font(.body)`/`.font(.caption)` (12pt) + `.primary/.secondary`; `AppPickerView.swift:53` `.secondary`. In `SettingsView` a 15pt `Theme.Typography.body` row (`:204`) sits next to a 17pt system row (`:358`) inside one `List`. | Mixed 17/15/13/12 in a single list. | One `zanoList()` / `zanoForm()` modifier pair: fonts on rows via `.font(Theme.Typography.body)`, header/footer via `eyebrow`/`caption`, `.listRowBackground(surface)`, `.scrollContentBackground(.hidden)`, hairline separators, tint (see C2/C3). | The "secondary screens" look like a stock Form next to the themed tabs. |
| MEDIUM | **T8.** Decision text truncated to one line: `GoalRow.swift:112,117` (`lineLimit(1)` on title and detail). `FuelView.swift:608-611` passes the whole prompt `"Your usual <meal> (48g)?"` as the title; `FuelView.swift:505-507` detail `"#3 - Find something high-protein close by"` (~37 chars in about 230pt). | Ellipsis cuts the answer to a yes/no question. | `lineLimit(2)` (or 1 for title / 2 for detail) with `fixedSize(horizontal: false, vertical: true)`; drop the `#rank` prefix. | Truncation must not hide the content the user is deciding on. |
| MEDIUM | **T10.** 15pt body + 13pt caption carry primary data and safety copy: ring values (`RingCluster.swift:159`), `AlwaysAllowedWarningView.swift:97-104` (13pt muted warning body), `Screen14FirstWin.swift:559-561` (emergency hold label, 13pt muted), `ShieldPreview.swift:133-137` (Emergency link 13pt muted). 10pt earned-date at `TrophyCaseView.swift:329`. | Below the 12-13pt floor for content the user needs (10pt). | Caption is metadata only; primary data >= 15 in `text` colour; nothing below 12pt. | Size floor; safety affordances should not be the smallest text on screen. |
| LOW | **T9.** `Core/Sources/Core/Copy/*` (144 strings with an ASCII `'`, 0 with U+2019): `OnboardingCopy.swift` hook "Let's flip that.", `TodayCopy.swift:39` "I'm at the gym". ALL-CAPS stored: `OnboardingCopy.swift:101,119,170,184,207,215`, `PaywallCopy.swift:35` ("THE MATH", "YOUR PLAN", "LAST STEP", "STAY IN THE LOOP", "BEST VALUE", "YOUR FIRST WIN") while views also apply `.textCase(.uppercase)`. `"1x/week"` (`OnboardingCopy.swift:86`). Duration strings break between number and unit: `CelebrationCopy.swift:57-62`, `ProgressView.swift:311-316`, `WeeklyRecapShareView.swift:403-408` (`"2h 10m"`). (`Screen8CoachVoice.swift:66` correctly uses curly quotes.) | Straight quotes, stored caps, `x`, breakable `"2h 10m"`. | Curly apostrophes; store natural case and apply `.textCase`; `1x/week` -> `1\u{00D7}/week`; NBSP (`\u{00A0}`) inside `"2h\u{00A0}10m"`. (Copy files are outside this wave's edit list; route to the Copy owner.) | Smart punctuation and natural-case storage. |
| LOW | **T11.** Ticking values without tabular digits: `Screen14FirstWin.swift:559-561,574-578` (`"\(secondsRemaining)s"` in `caption`), `Copy.today.verifyingAtGymTitle(minutes:)` inside `PrimaryButton` (`TodayView.swift:321-327`). Numeral tokens are already `.monospacedDigit()` (good). | Digits jitter as they tick. | `.monospacedDigit()` on those two. | Tabular numbers on changing values. |
| LOW | **T13.** Centered multi-line headlines with no wrap control: `Screen1Hook.swift:39-45` (51 chars at 34pt in about 345pt: likely a one-word last line), `ShieldPreview.swift:109-113`, `Screen9WakeUp.swift:91-100`. | Default greedy wrapping. | Constrain measure (`.frame(maxWidth: ~300)`) and/or editorial line breaks in Copy. (SwiftUI has no `text-wrap: balance` equivalent that I could confirm — Not verified on the iOS 26 SDK.) | Widow/orphan control. |
| LOW | **T14.** `chevron.right` hard-coded: `ProgressView.swift:229`, `Screen4AppSelection.swift:76` (elsewhere `chevron.forward`: `LockStatusCard.swift:95`, `GhostProgressBanner.swift:113`, `TrophyCaseView.swift:150`). | Does not mirror in RTL. | `chevron.forward`. | Bidi (already flagged for Trophy at stress-test §2.4; regressed here). |

**Decision for the design owner (numeral face).** Spec §15 offers "SF Pro (or one variable display
font for numerals, e.g., a condensed grotesque)" and the style paragraph asks for "chunky bold
numerals". `.rounded` bold on near-black reads friendly/consumer-wellness, which fights "ranked mode x
premium minimal, not childish". Recommendation: try SF Pro **Expanded/Heavy** numerals (system width
axis, no asset needed — API availability is *Not verified*, no SDK here) or bundle one condensed
variable face (needs `UIAppFonts`/asset changes in forbidden files). Keep `.monospacedDigit()` either way.

---

## 3. Color findings

### 3.1 HIGH

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **C1.** `PrimaryButton.swift:99` sets the `.holdToCommit` label to `Theme.Colors.text` while the fill (`:104-108`, `accent.opacity(0.9)`) sweeps left-to-right *under* it. Used by Today "Begin lock" (`TodayView.swift:297-304`), Onboarding commitment (`Screen11Commitment.swift:72-77`), **Emergency Unlock** (`LockStatusView.swift:277-283`), Alarm squad confirm (`AlarmRingingView.swift:326`). | `#F5F5F7` on `#B8FF3C` = **1.11:1** (1.35:1 on the actual composite, accent@0.9 over surface2). At 100% hold the whole label is unreadable, exactly at the moment of commitment. | Render the label twice: `text` beneath, and a `background`-coloured copy on top masked to the fill's width (same `holdProgress`), so each glyph flips colour as the fill crosses it. `.standard` (`:233`, `background` on accent) is fine at 16.4:1. | Unreadable content on a safety-critical control (spec §24, CLAUDE.md "emergency unlock must always exist" — it must also be legible). |
| HIGH | **C2.** No global tint. `ZANOApp.swift:52-64` and `ContentView.swift` set no `.tint`; `project.yml` sets no accent; `App/ZANO/Assets.xcassets` does not exist on disk yet. SwiftUI falls back to system blue (`#0A84FF`, 5.43:1 on background). Blue appears on: toolbar Save/Cancel/+ (`FuelView.swift:929-938,1033-1042`, `SettingsView.swift:578-585,760-769,1124-1131`, `SunriseAlarmSetupView.swift:164-169`, `BedtimeGateSetupView.swift:92-97`, `LockSetupView.swift:130-138`), Settings icons and buttons (`SettingsView.swift:244,251,314,320,340,346,373,377,470-473,506`), `DatePicker` (`SunriseAlarmSetupView.swift:213`, `BedtimeGateSetupView.swift:49`), `Picker`/`Stepper` (`SettingsView.swift:731,1086-1107`, `SunriseAlarmSetupView.swift:363,393`), nav back buttons, alert and dialog buttons, `TextField` caret, `ProgressView` (`AlarmRingingView.swift:235,264`, `SunriseAlarmSetupView.swift:319`). `Toggle` (`LockSetupView.swift:247`, `BedtimeGateSetupView.swift:57`) renders system green `#30D158`, a second green next to the acid accent. `Theme.Colors.Ring.sleepOnTime` (`Theme.swift:83`) is *exactly* system blue. | A second accent (blue) plus a second green on ~11 screens. | Root `.tint(Theme.Colors.accent)` + `AccentColor` = `#B8FF3C` in the asset catalog + root `.preferredColorScheme(.dark)` and `Theme.Colors.background`. **These live in forbidden files this run — route to the `ZANOApp`/`ContentView`/`Assets.xcassets` owner.** Do not adopt `.borderedProminent` (white label on acid = 1.1:1); none exists today. Verify tinted `Toggle` knob contrast on device. | Spec §15 "ONE accent only" is a hard rule; today the violation is by default rather than by literal, which is why grep finds nothing. |
| HIGH | **C4.** `AlarmRingingView.swift:139-141`: phase tint at 0.10-0.32 alpha behind the whole screen; secondary text sits directly on it (headline `:196-199`, snooze `:359-360`, escape hatch `:378-393`, footnote `:402-405`). Reduce Motion freezes it at 0.22. | Muted text on the tint: waking (`#FFD60A`) 5.09 -> **3.65** (0.22) -> **2.64** (0.32); urgent (`#FFB020`) 5.24 -> **3.97** -> **3.01**; critical (`#FF453A`) 5.60 -> 4.77 -> **4.00**. Critical eyebrow tint text at 0.32: **3.83**. `#FFD60A` and `#FFB020` are 11 degrees apart, so waking and urgent are also barely distinguishable. | Keep body/secondary copy off the tint (on a `surface` card) or lift it to `text`; cap the tint at <= 0.14 (waking) / 0.17 (urgent) / 0.22 (critical) if muted text must stay on it; separate the waking/urgent hues. | Users read this screen half-awake, and the escape-hatch instructions are in the failing text. Under Reduce Motion the failure is permanent, not momentary. |

### 3.2 MEDIUM

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | **C3.** Raw `List`/`Form` surfaces (11 screens/sheets: see T7 for the list). Only `SettingsView.swift:169-170` hides the scroll background, and even there rows keep the system cell fill (no `.listRowBackground`); `GymSetupDetailView` (`:563`), `NFCTagSetupDetailView` (`:866`) and every `Form` do not hide it at all. | System grouped black `#000` + cell `#1C1C1E` (about `surface2`) instead of `background #0A0A0B` / `surface #141416`. | `zanoList()` modifier (see T7). | Stepping from a themed tab into Settings changes both luminance steps and hierarchy. (System values from memory of UIKit dark defaults — Not verified.) |
| MEDIUM | **C5.** Separation is below perceivable: `surface` vs `background` **1.08:1**; `surface2` track vs `surface` **1.08:1**, vs `background` **1.16:1**; `hairline` (`Theme.swift:54`, surface2@0.8) **1.06-1.12:1**. Used at `GoalRing.swift:105` (track sits directly on `background` on Today), `TimeBankBar.swift:68`, `ProgressView.swift:341` (28-day grid: empty cells 1.08:1 so only earned cells are visible and the grid structure disappears), `OnboardingContainerView.swift:172`, `Screen2SocialProof.swift:72`, unselected option cards `Screen3MainGoal.swift:105-112` (also `Screen7FallOff.swift:62-69`, `Screen8CoachVoice.swift:72-79`), `PaywallCard.swift:98-106` unselected border. | The style paragraph promises "crisp 1px hairline dividers"; at 1.06:1 they do not exist, and unselected cards are not delineated from the page. | New opaque tokens: `track` and `hairline` about `#38383D` (**1.70:1** vs background, **1.58:1** vs surface); or `white@0.16` (1.53-1.61:1). Optionally lift `surface` one step. | WCAG 1.4.11 asks 3:1 for graphics needed to understand content; a pragmatic floor here is about 1.5:1 for tracks/dividers. Contrast is a design decision — measured and reported, not changed. |
| MEDIUM | **C6.** Locked trophy tiles: `TrophyCaseView.swift:334` `.opacity(0.55)` on the whole tile (title `:322-326`, icon `:307-309`). | Title muted@0.55 on surface = **2.56:1**; lock icon **2.46:1**. Earned-date 10pt (`:329`). | Do not dim text; dim only the icon disc. Keep the title `muted` (5.64:1). | Milestone names are the content being unlocked. |
| MEDIUM | **C7.** Accent has five jobs (`Theme.swift:43-44` reserves it for CTAs, workout ring, unlock/earned). (a) primary action fill (correct); (b) earned/complete (correct: `GoalRow.swift:174`, `LockStatusCard.swift:72-76`, `StreakPill.swift:56`); (c) selection state (`Screen3MainGoal.swift:101,110`, `Screen4AppSelection.swift:70,86`, `Screen7FallOff.swift:58,67`, `Screen8CoachVoice.swift:63,77`, `PaywallCard.swift:64,102`); (d) **decorative brand tint on icons/eyebrows that carry no state**: `Screen10PlanReveal.swift:106`, `Screen11Commitment.swift:47`, `TimeBankBar.swift:57` (hourglass stays accent while the bar turns warning), `RecapCard.swift:144` (three different glyphs), `SettingsView.swift:412`, `PaywallView.swift:178-181`, `TrophyCaseView.swift:139`, `SunriseAlarmSetupView.swift:413`, `AlarmRingingView.swift:317`, `Screen1Hook.swift:36`, `Screen12PermissionPriming.swift:37`, `Screen14FirstWin.swift:142,228`, `FounderSeriesCard.swift:131-134`; (e) text links: `FounderSeriesCard.swift:103`, `PaywallView.swift:237`, `SettingsView.swift:645`. Also `Screen14FirstWin.swift:598-604` confetti uses accent + protein + focus + water + warning while spec P3 and `CelebrationBurst` are accent-only. | One hue means "chosen", "earned", "do this", and "brand decoration". | Reserve accent for: fill of the one primary action per view, earned/complete state, and selection. Make decorative icons `text`/`muted`; tertiary links `text` + underline; confetti accent-only (reuse `CelebrationBurst`). | "One color, one meaning": when everything is acid green, earned no longer stands out. |
| MEDIUM | **C8.** Ring palette hue collisions (within 15 degrees): `warning #FFB020` (39) ~ `protein #FF7A00` (29) ~ `sunriseAlarm #FFD60A` (50); `water #32ADE6` (199) = `coldShowerSauna #5AC8FA` (199, 0.3 apart) ~ `sleepOnTime #0A84FF` (210) = system blue; `creatine #FF375F` (348) is about 15 from `danger #FF453A` (3); `steps #32D74B` is iOS systemGreen (same as the toggle green). `Ring.focus #5E5CE6` is 3.91:1 on background / 3.64:1 on surface / 3.15:1 on its own 16% tint, so it must never be text (currently it is only ring/icon, fine). `Theme.swift:73-94` labels the extras "assumption". | On Progress/Recap rings, water and cold-shower are indistinguishable; creatine looks like an alert; protein looks like a warning. | Keep the four spec hues; give every other goal type the neutral `custom` ring + a distinctive icon, or hue-separate to >= 30 degrees (there is not room for 13 distinct hues alongside accent/danger/warning). Design decision. | "One color, one meaning" and colour-blind separability. |
| MEDIUM | **C9.** Status colours doing many jobs. `warning`: in-progress (`GoalRow.swift:178`), low balance (`TimeBankBar.swift:71`), behind ghost (`GhostProgressBanner.swift:65`), Always-Allowed warning (`AlwaysAllowedWarningView.swift:121-130`), **currency coins** (`TrophyCaseView.swift:376`, `CosmeticsShopView.swift:349`), Pro-lock (`CosmeticsShopView.swift:136`), unconfirmed gym (`SettingsView.swift:638`), alarm urgent (`AlarmRingingView.swift:669`). `danger`: locked (`LockStatusCard.swift:72-76`), errors, emergency-hold fill (`Screen14FirstWin.swift:553`, `AlarmRingingView.swift:414`), lock badge (`ShieldPreview.swift:177`), **loss stat** (`Screen9WakeUp.swift:103`), critical alarm (`:670`). | Currency and in-progress read as caution; a neutral stat reads as a lock. | `warning` = needs attention soon; `danger` = blocked/failed. Coins -> neutral or accent-dim; in-progress -> `text`/`muted`; loss stat -> designer's call (spec §8 rule 10 permits it, but make it deliberate). | Semantic clarity. |
| MEDIUM | **C10.** Disabled primary state is the most common Today state: `TodayView.swift:296,313,322-331` — 5 of 8 `PrimaryAction` cases pass `isEnabled: false`, and `PrimaryButton.swift:70,117` applies `.opacity(0.5)` to the accent slab. | A muddy olive block (about `#618524` composite; label 4.58:1) that is not in the palette, for states that are really *status* ("Focus session running...", "All goals done - unlocking..."), not disabled actions. | Informational states become a `surface2` row with `muted`/`text` label (5.2:1) — not a button; true disabled = `surface2` + `muted`. | Off-palette colour that fires on the primary screen; status is not a disabled button. |
| MEDIUM | **C11.** Root appearance: `project.yml:56` `UILaunchScreen: {}` (no colour) and no `UIUserInterfaceStyle`; `ContentView.swift:4-16` (scaffold) has no background/scheme/tint; dark mode is forced per screen (22 real `.preferredColorScheme(.dark)` sites). `AlarmRingingView.swift:685` and `UnlockCelebrationView.swift:247,257` set it only in `#Preview`, so both full-screen presentations depend on the presenter's scheme (not verified whether `.fullScreenCover` inherits it). | Light-mode users see a white launch flash and any root-level chrome (tab bar, root alerts) follows the system. | `UIUserInterfaceStyle: Dark`; `UILaunchScreen` with `UIColorName` `#0A0A0B`; root `.preferredColorScheme(.dark)`/`.background`/`.tint`; tab bar appearance (selected = accent, unselected = muted, label = `captionEmphasized`). **Forbidden files this run — route.** | Fixed dark design system needs a fixed dark root. |
| MEDIUM | **C12.** Three parallel palettes: `Theme.swift`; `Extensions/ZANOWidgets/Support/ZANOWidgetColor.swift:19-35` (full hex copy, header says "delete in favor of Theme once it ships"); `Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift:46-66` (`UIColor(white:1)` / `.black` / accent hex). `Theme.Colors.*` are `public` and the Shield extension already `import Core`. | Drift risk; shield uses pure white/black rather than `text #F5F5F7` / `background #0A0A0B`. | Delete `ZANOWidgetColor`, point widgets and the shield at `Theme.Colors` (UIColor bridge in the shield). Outside this wave's edit list — route. | Single source of truth. |

### 3.3 LOW

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | **C13.** `TodayView.swift:110` `.ultraThinMaterial` under the primary button (not a token; a blurred neutral grey over `#0A0A0B`). | Off-palette blur. | `Theme.Colors.background.opacity(0.92)` + top hairline. | Token discipline. |
| LOW | **C14.** `ShareCard.swift:80-84` `LinearGradient(background -> surface)`: a 1.08:1 gradient, invisible on screen and prone to banding in an 8-bit 1080x1920 export. | No visible effect, banding risk. | Replace with a low-opacity accent radial glow (style paragraph: "subtle inner glow") or drop it. Space choice (oklab) is unavailable in this API; accept default. | Export quality. |
| LOW | **C15.** Two-tier text: `text` is 18.18:1 on background, `muted` 6.07:1; no middle tier, and `muted` doubles as disabled/placeholder. | Paragraph copy is either near-white glare or grey. | Optional `textSecondary` about `#C7C7CC` (11.75:1 on background / 10.09:1 on surface2) for paragraph copy. | Hierarchy headroom. |

---

## 4. Proposed additions (sketch for the implementation wave; not applied)

```swift
// Theme.Typography (Core/UI/Theme.swift) — Dynamic-Type-aware, semantic
public enum Style { case display, title, headline, body, paragraph, caption, captionEmphasized, eyebrow, unit }

public struct ZanoTextStyle: ViewModifier {           // Font cannot carry tracking/leading; a modifier can
    let style: Theme.Typography.Style
    func body(content: Content) -> some View {
        switch style {
        case .display:   content.font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.4)
        case .paragraph: content.font(.system(.subheadline)).lineSpacing(3)
        case .eyebrow:   content.font(.system(.footnote, weight: .semibold)).textCase(.uppercase).tracking(0.8)
        case .unit:      content.font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Theme.Colors.muted)
        // ... title/headline/body/caption map per section 2.3
        default: content
        }
    }
}
extension View { public func zanoText(_ s: Theme.Typography.Style) -> some View { modifier(ZanoTextStyle(style: s)) } }

public struct NumeralText: View {                      // one place for the numeral/unit split (T3)
    public enum Size { case hero, large, medium, small }
    let value: String; let unit: String?; let size: Size
    @ScaledMetric(relativeTo: .largeTitle) private var hero: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var large: CGFloat = 44
    // body: HStack(alignment: .firstTextBaseline) { number (.rounded/.expanded, .monospacedDigit, .contentTransition(.numericText)) ; unit (.zanoText(.unit)) }
    //       + .dynamicTypeSize(...DynamicTypeSize.accessibility2)
}

// Theme.Colors additions to decide (values are proposals, measured in Appendix A)
public static let track    = Color(zanoHex: 0x38_38_3D)   // rings/bars/streak empty cells
public static let hairline = Color(zanoHex: 0x38_38_3D)   // replaces surface2@0.8
// Icon sizes: Theme.Typography.icon(.small/.medium/.large) built from text styles so icons scale with type
```

Screen-by-screen target (what each flagship screen should show at a glance): **Today** — ring centers
show the value (`72` + `g`), streak as hero numeral, primary button is the only accent fill;
**Fuel** — grams/ml as `numeralLarge` with `unit`, quick-add chips unchanged; **Lock** — minutes
remaining `numeralLarge` above the bar; **Progress** — streak hero numeral + 28-day grid using
`track` so empty days are visible; **Unlock celebration** — "Earned." in `display`, Time Bank
minutes as `numeralLarge` + unit; **Alarm** — clock at `numeralHero`, copy on a `surface` card;
**ShareCard** — three numeral+unit stat cells rendered at 360x640 pt x3.

---

## 5. Routing (findings that cannot be fixed inside the assigned edit list)

| Finding | Needs | Owner |
| --- | --- | --- |
| C2, C11 | Root `.tint`, root `.preferredColorScheme(.dark)`, root background, `AccentColor` asset, `LaunchBackground` colour asset, `UILaunchScreen.UIColorName`, `UIUserInterfaceStyle`, tab bar appearance | Parallel workflow: `ZANOApp.swift`, `ContentView.swift`, `AppRouter.swift`, `Assets.xcassets`, `project.yml` |
| T4b | One tab-root header component | `AppRouter`/tab shell owner + Features owner |
| T4 (if a bundled numeral font is chosen) | `UIAppFonts` + font assets | `project.yml` / `Assets.xcassets` owner |
| C12 | Delete `ZANOWidgetColor`, unify shield colours | Widgets/Shield owner |
| T9 | Curly quotes, natural case, NBSP, `x` -> `x` sign | `Core/Sources/Core/Copy/*` owner |
| Watch app palette | Not audited (`Watch/ZANOWatch/**` and `Core/Sources/Core/Watch/**` are off-limits this run) | Parallel workflow |

## 6. Adjacent items noticed (outside typography/color; not scored)

- **Layout:** `TodayView.swift:202` renders three `.large` rings (`GoalRing.swift:40`, 148pt) in a
  horizontal `RingCluster`: 3x148 + 2x24 = 492pt against 361pt available on a 393pt phone — the third
  ring (Focus) is off-screen and only reachable by scrolling. `ShareCard.swift:137` fixes each ring at
  44pt in a 7-column strip (380pt) inside a 256pt card body. Both are computed from constants.
- **Reduce Motion:** the "everywhere" claim does not hold for onboarding — 0 of 17 Onboarding files
  read `accessibilityReduceMotion` (`Screen9WakeUp.swift:147-199` count-up, `Screen14FirstWin.swift:229`
  `.symbolEffect(.bounce)`, `:336` `.symbolEffect(.pulse, options: .repeating)`, confetti `:585-642`,
  container transitions). Already noted at stress-test §8; still open.
- **Hit areas:** `AlwaysAllowedWarningView.swift:172-176` dismiss is an 11pt glyph with no padding;
  `FounderSeriesCard.swift:140-150` about 23pt.
- **Copy rule:** view-composed strings listed in T3c bypass `Copy.*`.

## 7. Verification

| Check | Status |
| --- | --- |
| Token values, hex parsing, contrast (WCAG 2.x relative luminance, sRGB) computed with a script from the declared tokens; composites (opacity over a known backdrop) computed analytically | Done (Appendix A) |
| Whole-repo grep for raw colours/fonts, `.tint`, `List`/`Form`, tracking/leading/Dynamic Type | Done |
| Every file in `Features/**` and `Core/UI/**` opened | Done (every `.font(`/colour site read in context; header comments and non-UI logic skimmed) |
| Any on-device/Simulator render (actual glyph metrics, wrapping, truncation, banding, P3 shift) | **Not verified** — no Mac |
| `Font.system(size:)` not scaling with Dynamic Type | Not verified on device; per SwiftUI semantics and `ui-stress-test-findings.md` §1.2 |
| System `List`/`Form` default colours (`#000`/`#1C1C1E`), default tint (`#0A84FF`), `Toggle` green | Not verified — from memory of iOS dark defaults |
| Whether `.preferredColorScheme` propagates into presented sheets | Not verified |
| `ImageRenderer` output proportions (T1) | Derived from code; not rendered |
| SwiftUI text balancing API, `Font` width axis availability (SF Expanded) on the current SDK | Not verified |
| Toggle/knob contrast with an acid-green tint | Not verified |
| Anything in `Watch/**`, `Core/Sources/Core/Watch/**`, widgets' fonts | Not audited |

Analogues used as design direction (from general knowledge of shipped apps, **not fetched this
session**): Apple Fitness/Activity (value + small unit, ring with number), Whoop/Oura (single hero
metric per screen), Strava/Nike Run Club (expanded heavy numerals). No web lookup was performed.

**Result: Block** (HIGH: T1, T2, C1, C2, C4).

---

## Appendix A — measured contrast (WCAG 2.x, sRGB)

Token pairs (text on surface):

| Foreground | on `background` | on `surface` | on `surface2` |
| --- | --- | --- | --- |
| `text #F5F5F7` | 18.18 | 16.90 | 15.61 |
| `muted #8E8E93` | 6.07 | 5.64 | 5.21 |
| `accent #B8FF3C` | 16.40 | 15.25 | 14.09 |
| `danger #FF453A` | 5.81 | 5.40 | 4.99 |
| `warning #FFB020` | 10.82 | 10.06 | 9.30 |

Ring colours as foreground: protein 7.57/7.04, water 7.78/7.23, steps 10.33/9.60, creatine 5.62/5.22,
sunrise 14.02/13.03, sleep 5.43/5.04, reading 6.43/5.98, mealPrep 11.20/10.41, stretch 5.62/5.22,
cold 10.44/9.70, **focus 3.91/3.64** (bg/surface). On its own 16% tint: focus **3.15**, danger 4.54.

Composite / non-text:

| Pair | Ratio |
| --- | --- |
| `background` label on `accent` (standard button) | 16.40 |
| `text` label on `accent` (hold-to-commit mid/full fill) | **1.11** |
| `text` label on accent@0.9 over surface2 | **1.35** |
| `background` label on accent@0.5 (Preparing share button / disabled primary) | 4.58 |
| `text` glyph on `danger` (ShieldPreview lock badge) | 3.13 |
| Locked trophy title muted@0.55 on surface | **2.56** |
| Locked trophy icon | **2.46** |
| `surface` vs `background` | **1.08** |
| `surface2` track vs `surface` / vs `background` | **1.08 / 1.16** |
| `hairline` (surface2@0.8) vs `background` / on `surface` | **1.12 / 1.06** |
| Proposed `#38383D` vs `background` / `surface` / `surface2` | 1.70 / 1.58 / 1.46 |
| iOS `.secondary` label on `surface` | 6.18 |
| System blue on `background` / `surface2` | 5.43 / 4.66 |
| Chip text on own 14% tint (protein / water / muted) | 6.39 / 6.50 / 5.19 |

Alarm tint (`AlarmRingingView.swift:139-141`), muted text / `text` / tint eyebrow on the pulsing
background:

| Phase | alpha 0.10 | alpha 0.22 (Reduce Motion) | alpha 0.32 (peak) | Max alpha for muted >= 4.5 |
| --- | --- | --- | --- | --- |
| waking `#FFD60A` | 5.09 / 15.25 / 11.77 | **3.65** / 10.92 / 8.42 | **2.64** / 7.91 / 6.10 | 0.145 |
| urgent `#FFB020` | 5.24 / 15.70 / 9.35 | **3.97** / 11.88 / 7.07 | **3.01** / 9.01 / 5.36 | 0.170 |
| critical `#FF453A` | 5.60 / 16.76 / 5.36 | 4.77 / 14.28 / 4.56 | 4.00 / 11.99 / **3.83** | 0.255 (eyebrow: 0.225) |

Hues (degrees): accent 82, danger 3, warning 39, protein 29, sunrise 50, creatine 348, steps 129,
water 199, coldShower 199, sleep 210 (= system blue), mealPrep 177, focus 241, stretch 280, reading 34
(29% sat). Pairs within 15 degrees at >30% saturation: warning~protein 10, warning~sunrise 11,
water~sleep 11, water~coldShower 0.3, sleep~coldShower 11.
