# Better-layout findings: grouping, alignment, reading order, progressive disclosure

**Status:** read-only static audit. The only file this task wrote is this one. **Nothing below was
rendered, built, or run.** There is no Mac, Simulator, device, or Swift compiler in this
environment (CLAUDE.md "Current environment status"). Every claim is a read of the SwiftUI source
plus arithmetic on `Theme` token values. Where a figure is arithmetic I give the reference size it
was computed against: **393x852 pt** (iPhone 15 Pro, 59 pt top / 34 pt bottom safe area) and
**375x667 pt** (SE / mini class). Treat every "would clip / would overflow" as a prediction.

**Skill applied:** `interfaces:better-layout` (group with space, controls distinct from content,
shared edges, order by importance, hint at hidden content, breathing room, inset/bleed/float, hold
structure, plan for growth). Hit-area sizing, focus, radius/shadow/motion, and line length belong to
`better-accessibility`, `better-ui`, and `better-typography`; where a finding touches them I
cross-reference instead of re-deriving. Existing sibling docs already cover motion, VoiceOver, and
Dynamic Type (`ui-stress-test-findings.md` 1.2 says `Theme.Typography` never scales; that makes every
fixed-height and one-line clamp below worse, and I do not repeat it per row).

**Scope read (every file, in full unless noted):** all 33 files under `App/ZANO/Features/**` and all
17 files under `Core/Sources/Core/UI/**`, plus `Theme.swift`, `Copy/TodayCopy.swift`,
`Copy/LockStatusCopy.swift`, `Copy/ShareCopy.swift`, spec section 15/16, and the three existing
`docs/design/*` reviews. Header comment blocks of `SunriseAlarmSetupView`, `BedtimeGateSetupView`,
`AlarmRingingView` (lines 1-89), `PaywallView`, `Screen11`-`Screen14` were skimmed rather than read
line by line (they are assumed-API notes). `OnboardingFlowState.swift` is state only (grep for view
code returned nothing) and was not read line by line. Forbidden paths (`ZANOApp`, `ContentView`,
`AppRouter`, `LockEngineManager`, `LockSetManager`, `project.yml`, `Assets.xcassets`, `ZANOUITests`,
`Core/Watch`, `Watch/ZANOWatch`) were read for context only where noted and are not audited.

**Severity key (from the skill):** HIGH = blocks content or an action at a supported viewport.
MEDIUM = harms hierarchy, reading order, or adaptability. LOW = isolated alignment or spacing polish.

**Verdict: Block.** Six HIGH findings remain (section 0). None needs new design work to fix; they
are layout decisions that were never checked against a real viewport.

---

## 0. The short version

The screens are built from the right tokens and the right components, and the individual cards are
tidy. What is missing is **composition**. Almost every screen is a vertical stack of same-weight
surface cards with the numbers demoted to 13 pt muted captions, and the things a person must act on
(paywall CTA, alarm escape hatch, third goal ring, Focus ring, the free path) sit where a real phone
will clip them. That is the "tutorial-grade" feel: nothing on any screen is clearly the point.

### HIGH (fix before anything else)

| # | Finding | Where | Detail |
| --- | --- | --- | --- |
| H1 | Today's third ring (Focus) is off-screen on every iPhone | 4.1 | `RingCluster(.large, .row)` is 500 pt wide inside a 361 pt scroller |
| H2 | Paywall CTA and the "continue free" path are below the fold | 7.1 | Single ScrollView, CTA is the last child |
| H3 | Alarm escape hatch starts ~80% down and duplicates the primary ring | 7.2 | 148 pt danger ring at the end of a ~1000 pt scroll |
| H4 | Share card preview and export are two different layouts, and the ring strip overflows | 8.1 | Fixed-pt tokens rendered on a 1080 pt canvas; 44 pt rings do not fit 320 pt |
| H5 | Six `ProgressView()` calls render the Progress **screen**, not a spinner | 9.1 | Module type shadows `SwiftUI.ProgressView` |
| H6 | (see 5.1) Today can show "2 goals left" while none of the goals is visible | 5.1 | Only workout/protein/focus rings exist; lock counts every required goal |

H6 is HIGH only if you accept that hiding the unlock blocker on the home screen blocks the action;
if you read it as MEDIUM (the Lock screen lists the goals), the verdict is unchanged.

### Ten changes that would move the whole app

1. **Put the number in the ring.** Ring centre = the value in numeral type, target as a caption
   ("of 150g"). Apply to Today, Fuel, Lock, Progress, celebration, share card (row 1.1).
2. **One sticky action bar component** (`safeAreaInset` + material + 16 pt inset) used by Today,
   Paywall, Lock (emergency), onboarding, and the alarm sheet. Nothing critical scrolls (section 7).
3. **One `SelectableRow`** in Core/UI. There are five selection idioms and three copy-pasted rows
   today (row 4.2).
4. **One 16 pt screen margin.** Onboarding mixes 16, 24, and 32 (row 4.3).
5. **Metric card = ring + numeral + its own quick actions** on Fuel, so logging controls sit inside
   the thing they change (row 2.1).
6. **Settings re-ordered by priority and by frequency**, coach voice behind one row (rows 1.5, 5.4).
7. **Cosmetics shop: one filled button per screen, not five** (row 3.5).
8. **Render share cards at logical 360x640 at 3x**, not 1080x1920 at 1x (H4).
9. **Fix the `ProgressView` shadowing** (H5); it is a one-line qualifier at six sites.
10. **A `numeralHero` type token (~64 pt)** for the two screens whose whole job is one number: Today
    hero and onboarding Wake-up. `numeralLarge` (44 pt) is the largest size the ramp has.

---

## 1. Order by importance (reading order, hero numbers)

Rule: the most important thing sits top and leading, is the largest and highest-contrast element, and
never sits under secondary detail.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | 1.1 Numbers are captions, icons are heroes.<br>`App/ZANO/Features/Today/TodayView.swift:216-230`<br>`Core/Sources/Core/UI/Components/RingCluster.swift:157-162`<br>`Core/Sources/Core/UI/Components/GoalRing.swift:167-173`<br>`App/ZANO/Features/Fuel/FuelView.swift:393-420`<br>`Core/Sources/Core/UI/Components/TimeBankBar.swift:52-63`<br>`App/ZANO/Features/Lock/LockStatusView.swift:242-261`<br>`App/ZANO/Features/Celebration/UnlockCelebrationView.swift:177-184`<br>`Core/Sources/Core/UI/Components/ShareCard.swift:100-106`<br>`Core/Sources/Core/UI/Components/RecapCard.swift:126-150`<br>`App/ZANO/Features/Progress/ProgressView.swift:174-195`<br>`Core/Sources/Core/UI/Components/PaywallCard.swift:80-84` | Ring centre is an SF Symbol. "72/150g" is 13 pt muted under the title. Time Bank minutes are a 13 pt label above the bar, then a 17 pt number below it. The celebration's payoff ("2h 10m unlocked") is the 13 pt bar label. Recap stats, streak, and the trial terms are 13-17 pt. `GoalRing` uses `numeralMedium` (28 pt) for centre text even at `.large`. | Ring centre carries the value: `.text("72")` in `numeralMedium` (`.large` uses `numeralLarge`), caption underneath reads "of 150g". Time Bank leads with minutes in `numeralMedium`, bar second. Celebration shows "2h 10m" in `numeralLarge` directly under "Earned." Recap and share stats become a 2x2 numeral grid. Trial length goes in the plan card title row, not a muted detail line. | Spec 15: "big numerals for grams/minutes/streak." The reader's first question (how far am I?) is answered in the smallest type on screen. One root cause, eleven locations. |
| MEDIUM | 1.2 Today has no focal point.<br>`App/ZANO/Features/Today/TodayView.swift:88-99, 163-175, 179-189` | Title "Today" (22 pt) + streak pill, then a 17 pt lock card, then rings, then a 15 pt ghost banner. Nothing on the screen is larger than 17 pt because ring centres hold icons. | Lead with one hero: "1 goal left" as a `numeralHero` count (or the running-session state) inside the lock card, rings directly under it. Drop the in-scroll "Today" title for a date eyebrow (the tab already says Today). Streak pill stays trailing. | Reading order should match priority: state of the lock, then what unlocks it, then how far along each goal is. Today currently reads as five equal cards. |
| MEDIUM | 1.3 Lock screen leads with what it already told you.<br>`App/ZANO/Features/Lock/LockStatusView.swift:55-73, 123-129, 148-179, 213-238` | Card (same summary the user just tapped on Today), then a "time context" card (locked since / trigger / next lock), then required goals, then Time Bank, then emergency. Goal rows are hand-rolled (12 pt padding) and not tappable. | Card, then **required goals** (use `GoalRow`; tap goes to the verifying surface), then Time Bank (earn mode), then time context folded into the card's detail line or a footer, emergency pinned (section 7). | Actionable content first, trivia last. "Locked since 7:00, started by schedule" outranks "what do I need to do" today. |
| MEDIUM | 1.4 Fuel order buries the fastest action.<br>`App/ZANO/Features/Fuel/FuelView.swift:253-267` | Rings and chips, then gap planner, then Quick Repeat, then Kitchen Staples. Quick Repeat only appears at the user's typical meal time and is the one-tap path. | Quick Repeat (when present) first, then per-metric cards (row 2.1), then gap planner (when behind), then staples. | When a suggestion exists it is the most likely next tap; when it does not, nothing moves. |
| MEDIUM | 1.5 Settings puts the least-changed setting first and the safety warning second.<br>`App/ZANO/Features/Settings/SettingsView.swift:158-168, 195-224, 274-285, 355-389, 403-432` | Order: Coach Voice (4 inline rows with sample lines, est. 40% of the first screen), Always-Allowed warning (conditional), Gym/NFC, Sleep, Rewards, Subscription (6th), Gear, About. Inside Subscription the upsell card is **last** under "Manage subscription" and "Restore purchases". | Warning banner first (when relevant), then plan card (Free: pitch + one filled CTA; Pro: renewal date), then Lock and verification (lock sets, gym, NFC), then Coach (one row, value on the right), Mornings and Sleep, Rewards, More (gear, restore, manage (Pro only), privacy, version). Sketch in section 10. | Order by importance and by frequency. "Manage subscription" is meaningless to a Free user; the pitch belongs above the admin rows, not under them. |
| MEDIUM | 1.6 Progress leads with lifetime, not with the streak.<br>`App/ZANO/Features/Progress/ProgressView.swift:120-128, 143-160, 174-195, 237-250, 258-266` | Order: lifetime Time Reclaimed (44 pt), Streak (17 pt pill), Trophy grid (unbounded), This Week recap. The streak (spec section 8's retention driver) is a small pill; the recap payoff is last, under every earned badge. | Two-up hero row: Streak (`numeralLarge`, best and freezes beneath) beside Time Reclaimed. Then This Week recap. Then badges capped to one row (next row peeks) with the header linking to Trophy Case. | The number that changes daily and drives return visits should out-rank the lifetime total. |
| MEDIUM | 1.7 Headings inverted inside the recap section.<br>`App/ZANO/Features/Progress/ProgressView.swift:260-266`<br>`Core/Sources/Core/UI/Components/RecapCard.swift:108-110` | Outer heading "This Week" is `headline` (17 pt); the card inside titles itself "Week of Mar 3" in `title` (22 pt). The other three cards on the screen keep their headings **inside** the card. | Delete the outer heading (the card already titles itself), or make the card title `headline`. Keep all headings inside cards. | The subordinate heading is bigger than its parent, and the screen uses two different heading conventions. |
| MEDIUM | 1.8 The object of the screen is not shown: chosen apps are only counted.<br>`App/ZANO/Features/LockSetup/AppPickerView.swift:46-60`<br>`App/ZANO/Features/LockSetup/LockSetupView.swift:212-227, 364-384`<br>`App/ZANO/Features/Onboarding/Screen4AppSelection.swift:63-101`<br>`App/ZANO/Features/Onboarding/Screen10PlanReveal.swift:55-59` | "Select apps: 3 apps." Onboarding Q2 is one card on an otherwise empty screen (about 70% blank), then a text-only "Locked: 3 apps" on the plan reveal. | Render the selection with FamilyControls' own `Label(applicationToken)` chips (system-rendered, so the token-privacy rule holds): a wrapping row of icons under the picker row, and the same row on the plan card and lock card. Spec 16 P4 asks for an app-icons row. | The apps are the product. Showing only a count removes the payoff of the most effortful step in onboarding. |
| MEDIUM | 1.9 Safety warning is caption-sized and non-actionable-looking.<br>`App/ZANO/Features/LockSetup/AlwaysAllowedWarningView.swift:95-108, 157-170` | Title `captionEmphasized` 13 pt, message caption 13 pt, "Open Settings" is 13 pt borderless text. The message says shielded apps may never actually block. | Title `headline`, message `body`, "Open Settings" as a bordered/filled button, warning icon stays. Placed first in Settings (row 1.5). | Severity of the message and the weight of its type disagree; the fix is one tap away and styled as a footnote. |
| LOW | 1.10 Alarm: the modifier comes after the action.<br>`App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift:382-388` | "I'm not home" toggle sits below the 60 s hold ring, but its value is read when the hold completes. | Toggle above the ring. | Controls that configure an action precede it. |
| LOW | 1.11 Wake time and bedtime are just rows.<br>`App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:211-219`<br>`App/ZANO/Features/SunriseAlarm/BedtimeGateSetupView.swift:48-54` | A compact `DatePicker` in a section headed "Wake time". | Show the time as `numeralLarge` at the top, tap to edit. | The one value the screen exists to set should be the largest thing on it. |
| LOW | 1.12 Add-gym: the field that gates Save is last.<br>`App/ZANO/Features/Settings/SettingsView.swift:722-756` | Name, then radius (stepper), then "use current location". Save stays disabled until location exists. | Location first (or as a header row showing the fix), then name, then radius (a `Slider`, 50-500 in steps of 10 is 45 stepper taps). | Required step first; explain why Save is disabled. |

---

## 2. Group with space, not lines

Rule: gap between groups is at least 2x the gap within one; cards only where a group must read as
one unit; lines last.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | 2.1 Fuel: logging controls are not grouped with the metric they change.<br>`App/ZANO/Features/Fuel/FuelView.swift:358-391, 422-450` | Rings row, then a protein chip row, then a water chip row, all 16 pt apart (`md`). The `label:` parameter of `quickAddRow` (line 423) is never rendered, so the two rows are told apart by colour only. Gap within (16) vs gap between sections (24) is 1.5x, under the 2x rule. | One card per metric: ring (`.medium`), value in numeral type, "of 150g", and its chips **inside** the card. 24 pt between cards. | Proximity is the only thing tying "+25g" to the protein ring. |
| MEDIUM | 2.2 Plan reveal is five sibling cards, not one plan.<br>`App/ZANO/Features/Onboarding/Screen10PlanReveal.swift:52-88` | `LockStatusCard`, then N `GoalRow` cards, then a schedule card, each its own surface. | One "Your Lock-In Plan" card with three internal groups (apps, goals, schedule), 16 pt inside, hairlines only between groups (dense list case). Add the difficulty tag from spec 16 P4. | Spec 16 P4 describes "a bespoke card." Five equal cards read as a settings list. |
| LOW | 2.3 Eyebrow detached from its headline.<br>`App/ZANO/Features/Onboarding/Screen9WakeUp.swift:83-100` (vs `Screen11Commitment.swift:44-60`, `Screen12PermissionPriming.swift:40-56`) | Screen 9 separates eyebrow and headline by `xl` (32 pt); screens 11/12/14 group them at `sm` (12 pt). | Wrap eyebrow, headline, and count in one inner VStack(`sm`). | Same pattern, two gaps; the 32 pt one splits a thought. |
| LOW | 2.4 Streak summary detached from the pill.<br>`App/ZANO/Features/Progress/ProgressView.swift:176-191` | Pill trails the header; "Best: 21" and "2 freezes left" sit under a 184 pt grid. | Best and freezes sit beside the count in the hero (row 1.6). | The summary numbers belong with the number they summarise. |
| LOW | 2.5 Settings sections of two rows each.<br>`App/ZANO/Features/Settings/SettingsView.swift:309-351, 463-478, 498-512` | Sleep (2 rows), Rewards (2), Gear (1 row plus a caption), About (2). | Fold Gear and About into "More"; fold Rewards and Sleep into one "Extras" or keep, but do not give a one-row section a header. | Fewer, denser groups; an eight-section List is one flat list with headers. |

---

## 3. Keep controls distinct from content

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | 3.1 The sticky Today button is a status label in 5 of 8 states.<br>`App/ZANO/Features/Today/TodayView.swift:295-297, 312-313, 321-327, 328-329, 330-331` | `.setupIncomplete`, `.focusRunning`, `.verifyingAtGym`, `.waitingToUnlock`, `.openFuel` all render `PrimaryButton(isEnabled: false, action: {})` at 50% opacity. `.openFuel` says "Log the rest on Fuel" and does nothing. | States that are status become a non-interactive status row (icon + text in a `surface2` capsule). States that are next steps stay a button and navigate (`.openFuel` switches tab; `.setupIncomplete` opens setup). | A disabled accent bar reads as broken. Content styled as a control collects dead taps. |
| MEDIUM | 3.2 Real actions styled as borderless small text.<br>`Core/Sources/Core/UI/Components/FounderSeriesCard.swift:99-107, 140-150`<br>`App/ZANO/Features/LockSetup/AlwaysAllowedWarningView.swift:157-180`<br>`App/ZANO/Features/Settings/SettingsView.swift:641-646`<br>`App/ZANO/Features/Onboarding/PaywallView.swift:346-374`<br>`App/ZANO/Features/Onboarding/Screen12PermissionPriming.swift:68-75`<br>`App/ZANO/Features/Share/WeeklyRecapShareView.swift:267-270`<br>`App/ZANO/Features/Share/LockedOutMomentView.swift:424-427`<br>`App/ZANO/Features/Fuel/FuelView.swift:1132-1137`<br>`App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift:349-362` | 13 pt muted or accent text buttons with no shape: Gym "Confirm" (required for gym verification), Founder CTA, "Open Settings", Restore, Continue with limited free, notification Skip, Share Close, barcode manual entry (over a live camera feed), Snooze. | Two tiers only: filled (`PrimaryButton`) and secondary (bordered capsule, `surface2` fill, 44 pt min height). Truly optional exits (Skip, Close) may stay text but get a 44 pt frame and 24 pt clearance. | Borderless controls need the most clearance because nothing marks their edges. The no-dark-pattern exit ("continue free") is the smallest thing on the paywall. |
| MEDIUM | 3.3 Status glyph on rows that are not status.<br>`Core/Sources/Core/UI/Components/GoalRow.swift:167-190`<br>`App/ZANO/Features/Fuel/FuelView.swift:472-479, 607-616`<br>`App/ZANO/Features/Onboarding/Screen10PlanReveal.swift:62-74`<br>`App/ZANO/Features/Onboarding/PaywallView.swift:208-212` | `GoalRow(status: .pending)` draws an empty circle (a checkbox) on gap-planner options, Quick Repeat, plan-preview goals, and the paywall's "your plan" list. Tapping a staple/snack gap option or Quick Repeat **logs protein immediately** (the restaurant option opens Maps); the plan and paywall rows are inert. | Add `GoalRowStatus.none` plus an optional trailing accessory (`.chevron`, `.add`). Gap options and Quick Repeat get a trailing "+ 25g"; plan rows get nothing. | The trailing glyph is read as state. Here it is either wrong (an action) or misleading (a todo on a paywall). |
| MEDIUM | 3.4 Kitchen staple row: the primary tap has no affordance, the destructive one does.<br>`App/ZANO/Features/Fuel/FuelView.swift:952-996` | Row body (logs protein on tap) looks like static text. A muted trash icon (32x32) is always visible beside it. | Trailing "+" (log) as the visible control; delete via swipe action or an Edit mode. | Inverted: the frequent action is invisible, the rare destructive one is permanent chrome and 12 pt from the log target. |
| MEDIUM | 3.5 Cosmetics shop shows five filled accent buttons at once.<br>`App/ZANO/Features/Trophy/CosmeticsShopView.swift:195-211, 276-334` | Each item card ends in a full-width `PrimaryButton`. Categories hold five items each. Owned/Equipped and Buy share the same fill. | Compact trailing control on the title row: price capsule (bordered) or "Equip" (bordered), "Equipped" as plain text. At most one filled button on screen. Add a real preview tile (44 pt SF Symbol is the only "product image"). | One primary action per view; the accent means "earned/unlock" (Theme.swift line 43-44), not "another row". Cards also shrink from ~170 pt to ~90 pt. |
| MEDIUM | 3.6 Default-set toggle has no visible label.<br>`App/ZANO/Features/LockSetup/LockSetupView.swift:212-259` | Each row: name, app summary, and an unlabelled switch (label exists only for VoiceOver). Uses `.font(.body)` and `.foregroundStyle(.primary)`, not `Theme`. | Visible "Default" caption or a "Default" pill on the one default row; leave others empty. Use `Theme.Typography`. | A switch with no label is an unknown control; the behaviour is radio-like (off-tap is a no-op), which a switch does not communicate. |
| MEDIUM | 3.7 Save lives in the nav bar and gives no feedback.<br>`App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:164-169, 429-443`<br>`App/ZANO/Features/SunriseAlarm/BedtimeGateSetupView.swift:92-97, 120-134` | Pushed screens with a top-trailing Save that does not dismiss and shows no success. | Auto-save on change with an inline "Saved" check, or a bottom action bar (section 7) that dismisses. | The control sits far from the edit and the result is invisible. |
| LOW | 3.8 Radio rows are plain buttons with a `Spacer`.<br>`App/ZANO/Features/Settings/SettingsView.swift:198-217`<br>`App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:237-265`<br>`App/ZANO/Features/LockSetup/LockSetupView.swift:213-229` | `Button` + `.buttonStyle(.plain)` + `Spacer()` with no `contentShape`. In List/Form rows the empty area is often not hit-testable. | `.contentShape(Rectangle())` on the label, or move to `SelectableRow` (row 4.2). | Not verified (needs a device); listed because the fix is one modifier. Hit-area sizing is `better-accessibility`'s. |
| LOW | 3.9 Four emergency-unlock idioms.<br>`App/ZANO/Features/Lock/LockStatusView.swift:277-283` (2 s hold button)<br>`App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift:411-444` (148 pt ring, 60 s)<br>`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:544-579` (160x6 pt bar, 60 s)<br>`Core/Sources/Core/UI/Components/ShieldPreview.swift:133-146` (underlined caption) | Same job, four shapes and three sizes. The onboarding one is a 6 pt bar with 13 pt text (about 26 pt tall hit area). | One `EmergencyHold` component in Core/UI: same shape, same copy slot, 44 pt minimum. | CLAUDE.md: the way out must always exist. It should also always look the same. |

---

## 4. Align to shared edges

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **4.1 (H1)** Today ring row overflows the screen.<br>`App/ZANO/Features/Today/TodayView.swift:201-203`<br>`Core/Sources/Core/UI/Components/RingCluster.swift:98-105, 164`<br>`Core/Sources/Core/UI/Components/GoalRing.swift:36-42`<br>`Core/Sources/Core/UI/PreviewCatalog.swift:92` | `RingCluster(items: 3, ringSize: .large, layout: .row)`. Cells are 148 pt wide, 24 pt apart, plus a 4 pt inset: 3x148 + 2x24 + 2x4 = **500 pt** in a horizontal `ScrollView` that is 361 pt wide (393 minus two 16 pt margins). Ring 3 starts at x=348: a 13 pt sliver on 393 pt phones, 50 pt on a 430 pt phone, **fully hidden on 375 pt phones**. `PreviewCatalog` only previews the 3-ring row at `.medium`, so the overflow was never on screen. | Three equal columns: `HStack` of cells each `frame(maxWidth: .infinity)`, ring diameter derived from width (`min(.large, (available - 2*lg) / 3)`; 88 pt `.medium` gives 3x88 + 2x24 = 312, fits with slack). Keep the horizontal scroller only for `.row` callers that opt in and add a 16-32 pt peek. Add a 3x`.large` case to `PreviewCatalog`. | Spec 16 P1: three rings side by side. The screen's core content is off the edge with no cue (hold structure; hint at hidden content). |
| MEDIUM | 4.2 Five selection idioms, three copy-pasted rows.<br>`App/ZANO/Features/Onboarding/Screen3MainGoal.swift:89-117`<br>`App/ZANO/Features/Onboarding/Screen7FallOff.swift:46-74`<br>`App/ZANO/Features/Onboarding/Screen8CoachVoice.swift:50-84`<br>`Core/Sources/Core/UI/Components/PaywallCard.swift:62-64`<br>`App/ZANO/Features/Settings/SettingsView.swift:198-217`<br>`App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:235-271`<br>`App/ZANO/Features/LockSetup/LockSetupView.swift:246-259` | (a) card with trailing check and 2 pt accent border (onboarding), (b) leading radio glyph (paywall), (c) trailing check in a List row (Settings coach voice), (d) leading icon and trailing check (alarm variant), (e) trailing switch (lock sets). Coach voice is the same content in onboarding (cards with italic quote) and Settings (plain rows). | `SelectableRow` in Core/UI: one leading icon slot, title, optional detail, trailing check; selected = `surface2` + 2 pt accent border. Use it in all five places; Settings coach voice and onboarding Q6 share one view. | Edges and affordances should be learned once. |
| MEDIUM | 4.3 Onboarding uses three horizontal margins, so the CTA jumps.<br>`Core/Sources/Core/UI/Components/OnboardingQuestion.swift:45` (16)<br>`App/ZANO/Features/Onboarding/OnboardingContainerView.swift:188` (16)<br>`App/ZANO/Features/Onboarding/Screen3MainGoal.swift:77`, `Screen4AppSelection.swift:107`, `Screen5PhoneTime.swift:46`, `Screen6Workouts.swift:41`, `Screen7FallOff.swift:34`, `Screen8CoachVoice.swift:38`, `Screen1Hook.swift:51`, `Screen2SocialProof.swift:54`, `Screen9WakeUp.swift:131`, `Screen11Commitment.swift:82`, `Screen12PermissionPriming.swift:77` (24)<br>`App/ZANO/Features/Onboarding/Screen10PlanReveal.swift:89` (16)<br>`App/ZANO/Features/Onboarding/PaywallView.swift:123` (24)<br>`App/ZANO/Features/Onboarding/Screen5PhoneTime.swift:40` (16+8 slider) | Question cards and progress bar sit at 16 pt; the pinned CTA sits at 24 pt; Plan Reveal's CTA is at 16 pt; hero text blocks at 24 and 32. Tapping through the flow, the button is 345 pt wide on most screens and 361 pt on screen 10. | One margin: `Theme.Spacing.md` (16) for cards, bars, and CTAs. Hero text blocks may inset to `lg` but the CTA does not. | Every stray edge reads as noise even when nobody can name it. |
| MEDIUM | 4.4 Settings mixes system and Theme type, sub-screens have no Theme background, no accent tint.<br>`App/ZANO/Features/Settings/SettingsView.swift:170, 204, 244-251, 314-320`<br>`App/ZANO/Features/Settings/SettingsView.swift:562-576` (Gym), `858-907` (NFC), `1082-1120` (Map tag)<br>`App/ZANO/Features/LockSetup/LockSetupView.swift:106`<br>`App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:156`<br>`App/ZANO/Features/SunriseAlarm/BedtimeGateSetupView.swift:47` | Row labels use the default 17 pt `Label`; the coach-voice rows use `Theme.Typography.body` (15 pt) in the same List. Only the Settings root sets `.scrollContentBackground(.hidden)` + `Theme.Colors.background`; pushed lists and forms show stock grouped black and system row fills. `.tint(...)` appears only on individual spinners, one Slider (`Screen5PhoneTime.swift:30`), and one Toggle (`AlarmRingingView.swift:387`), and `ZANOApp.swift` sets none app-wide, so toolbar Save/Cancel, steppers, toggles, and text-button rows would render system blue/green, not acid green. | Shared `themedList()` modifier (hidden scroll background, `background`, `listRowBackground(surface)`, `listRowSeparatorTint(hairline)`), used on every List/Form. Apply `.tint(Theme.Colors.accent)` at the app root (needs `ContentView`/`ZANOApp`, forbidden this run: see section 12). | Two visual languages inside one flow: cards on Today, stock iOS forms one tap deeper. |
| LOW | 4.5 A stray 4 pt inset on chip and ring rows.<br>`Core/Sources/Core/UI/Components/RingCluster.swift:105`<br>`App/ZANO/Features/Fuel/FuelView.swift:447` | `.padding(.horizontal, Theme.Spacing.xxs)` inside a scroller already at the 16 pt margin, so ring and chip rows start at 20 pt while cards start at 16 pt. | Drop the inset; let the scroller bleed (row 5.2). | One leading edge. |
| LOW | 4.6 Rows mix 44 pt ring and 32 pt icon leaders.<br>`Core/Sources/Core/UI/Components/GoalRow.swift:153-164` (44 vs 32); leaders elsewhere: 28 (`SunriseAlarmSetupView.swift:246`), 36 (`SettingsView.swift:964`), 40 (`LockStatusCard.swift:73`, `GhostProgressBanner.swift:134`, `FounderSeriesCard.swift:136`) | In a list mixing ring rows and icon rows the title x-position differs by 12 pt and row height by 12 pt. | Give the leader a fixed 44 pt slot (icon centred inside it); adopt the `Theme.Metrics.iconBadge*` tokens already proposed in `apple-design-review.md` section 8.2. | Grid discipline: title edge should not depend on whether progress exists. |
| LOW | 4.7 Grid cells are centre-aligned vertically, so circles do not line up across a row.<br>`App/ZANO/Features/Trophy/TrophyCaseView.swift:184-191, 322-331`<br>`App/ZANO/Features/Progress/ProgressView.swift:242-249, 364-369` | Earned tiles carry a date line (10 pt, off the type ramp) that locked neighbours lack; badge titles wrap to 1 or 2 lines. `GridItem` default alignment is centre. | `GridItem(.adaptive(minimum: 96), spacing: sm, alignment: .top)`; reserve the date line height on locked tiles; use `captionEmphasized`-scale text instead of a literal 10 pt. | Icons on one row share a top edge. Not verified (predicted from `LazyVGrid` defaults). |
| LOW | 4.8 Streak history grid has no weekday header and no "today" mark.<br>`App/ZANO/Features/Progress/ProgressView.swift:324-347` | 28 squares (about 43 pt each on a 393 pt phone, roughly 184 pt tall) in rolling 7-day columns; unearned squares are `surface2` on `surface`. | Mon-Sun header row, calendar-aligned weeks, today ringed, smaller cells. | The largest block on the screen cannot be read without labels. |
| LOW | 4.9 Share screens use three insets.<br>`App/ZANO/Features/Share/WeeklyRecapShareView.swift:161, 168, 222`<br>`App/ZANO/Features/Share/LockedOutMomentView.swift:317, 322, 379` | Title at 16, card centred (about 36 from edge), button at 32. | Title, card, and button on one 16 pt margin (card centred within it). | Three leading edges on a screen with three elements. |
| LOW | 4.10 Barcode sheet doubles its inset and centres the CTA in the middle of the screen.<br>`App/ZANO/Features/Fuel/FuelView.swift:1154, 1159, 1183-1186, 1200-1214` | Result and serving views pad `lg` on the stack **and** `lg` again on the field/button (48 pt from the edge), manual entry pads once (24). CTA floats mid-screen with content height. | 16 pt margin, CTA in a bottom action bar. | The button changes width between states of one sheet. |
| LOW | 4.11 Three title treatments across tabs.<br>`App/ZANO/Features/Today/TodayView.swift:163-175` (custom in-scroll header, plus an empty inline nav bar above it)<br>`App/ZANO/Features/Lock/LockStatusView.swift:79-80` (inline)<br>`App/ZANO/Features/Fuel/FuelView.swift:274`, `Progress/ProgressView.swift:135`, `Settings/SettingsView.swift:172` (large) | Today, Lock, and the rest each title themselves differently. | Pick one (large title for tab roots; inline for pushed). Not verified: the empty nav bar above Today's header is inferred from `NavigationStack` with no title. | The top edge should be predictable. |
| LOW | 4.12 Physical chevrons.<br>`App/ZANO/Features/Onboarding/Screen4AppSelection.swift:76`<br>`App/ZANO/Features/Progress/ProgressView.swift:229` | `chevron.right` does not mirror in RTL (`TrophyCaseView`, `LockStatusCard`, `GhostProgressBanner` already use `chevron.forward`). | `chevron.forward`. | Logical direction. |
| LOW | 4.13 Micro-gaps off the spacing scale.<br>`spacing: 2` in `GoalRow.swift:107`, `LockStatusCard.swift:79`, `RecapCard.swift:107`, `PaywallCard.swift:66`, `GhostProgressBanner.swift:92`, `FuelView.swift:461, 969`, `SettingsView.swift:202, 625, 949, 969`, `TrophyCaseView.swift:221`, `CosmeticsShopView.swift:288`, `SunriseAlarmSetupView.swift:248, 543`, `BedtimeGateSetupView.swift:79`, `LockStatusView.swift:218` | Title-to-detail gap of 2 pt in 17+ places (plus `GhostProgressBanner.swift:150`, `FounderSeriesCard.swift:106`, `AlwaysAllowedWarningView.swift:169`); `Theme.Spacing` starts at 4. | Use `Spacing.xxs` (4). | Theme.swift line 5-8: no magic numbers outside Theme. |

---

## 5. Hint at hidden content; progressive disclosure; do not overload the entry point

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **5.1 (H6)** Today cannot show the goals the lock is waiting on.<br>`App/ZANO/Features/Today/TodayView.swift:216-222, 410-414, 419-423` | Rings exist only for workout, protein, and focus. `remainingRequiredGoalCount` counts **every** goal in the session's `requiredGoalIDs` (creatine, steps, sunrise, reading...). The card can say "Locked: 2 goals left" with no ring for either. | Ring cluster driven by the lock's required goals (top 3 by remaining, then a "+2 more" row that opens the Lock screen), not by three hard-coded types. | The number on the card and the content under it disagree. |
| MEDIUM | 5.2 Fuel chip rows hide the barcode scanner and clip at the margin instead of the screen edge.<br>`App/ZANO/Features/Fuel/FuelView.swift:431-448, 873-897` | Protein row: 3 presets (about 52 pt each), "Log custom amount" (about 159 pt), "Scan barcode" (about 124 pt), 8 pt apart: roughly 470 pt of chips in a 361 pt scroller. "Scan barcode" starts near x=351 (a sliver). The scroller is inside the 16 pt padding, so chips cut off at an invisible wall (contrast `CosmeticsShopView.swift:158-165`, which bleeds correctly). | Presets in a fixed row; "Custom" and "Scan" as two trailing icon buttons in the card header. If a scroller stays, apply `.scrollClipDisabled()` and content margins so it bleeds to the screen edge with a 16-32 pt peek. | A headline feature (scan) is discoverable only by accident. |
| MEDIUM | 5.3 Recap ring row hides goals and truncates titles.<br>`Core/Sources/Core/UI/Components/RecapCard.swift:76`<br>`Core/Sources/Core/UI/Components/RingCluster.swift:98, 153-156, 164` | `.small` rings (44 pt) in the `.row` scroller, cells 64 pt wide, titles `lineLimit(1)`. Six goals need 6x64 + 5x24 = 504 pt inside a 297 pt card interior; user-titled goals ("Gallon a day") cut to about 8 characters. | Use `.grid` layout in the card (adaptive, wraps), titles under `.small` rings limited to two lines. | Content past the 4th ring is reachable only by an uncued horizontal scroll inside a vertical scroll. |
| MEDIUM | 5.4 Settings and setup screens show everything at level one.<br>`App/ZANO/Features/Settings/SettingsView.swift:195-224, 890-905`<br>vs `App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:343-358` | Coach voice: four rows with sample lines always expanded. NFC setup: "How it works" and "Troubleshooting" sections always open, under the user's tags. Sunrise setup already uses `DisclosureGroup` for the same content. | Coach voice as one row ("Coach voice: Hype >") pushing a picker (which can reuse the onboarding cards). NFC help under `DisclosureGroup` (open only when there are zero tags). | Prefer a short view that links deeper over a long view that shows everything. |
| MEDIUM | 5.5 Progress badge grid is unbounded and sits above the weekly recap.<br>`App/ZANO/Features/Progress/ProgressView.swift:237-250` | Every earned badge renders in the card; 20 badges is 7 rows before "This Week". | Cap at one row of 3-4 with the next tile peeking; header row (already a `NavigationLink`, line 221) is the "see all". | Growth-proof the entry screen. |
| MEDIUM | 5.6 Paywall shows benefits, the built plan, plans, three CTAs, and notes at level one.<br>`App/ZANO/Features/Onboarding/PaywallView.swift:114-122, 195-214` | Headline, 3 benefit rows, an N-row "your plan" list of `GoalRow` cards (68 pt each), plan cards, trial note, CTA, Restore, Continue free. | Benefits as three icon-over-label tiles in one row; "your plan" as a single caption line ("3 goals, 1 lock set") or chips; price cards and CTA fixed at the bottom (row 7.1). | A paywall is one decision. Each extra block is a reason to scroll before deciding. |
| LOW | 5.7 Screen 2 quote carousel hides its own paging.<br>`App/ZANO/Features/Onboarding/Screen2SocialProof.swift:33-46, 68-77` | Page indicator hidden, replaced by 6 pt dots that are not controls; auto-rotates every 3.5 s. | Fine as pacing; if kept, dots should be 8 pt and non-interactive or use the system page indicator. | Low: it is decorative pacing by design. |
| LOW | 5.8 Cosmetics category chips peek only by coincidence.<br>`App/ZANO/Features/Trophy/CosmeticsShopView.swift:157-185` | Four chips total about 480 pt of content; "Coach Voice Packs" shows about 36 pt at 393 pt width (within the 16-32 pt peek guidance by luck, gone with a shorter label or a wider phone). | Keep the full-bleed scroller; make chips 44 pt tall (row 6.4). | Do not rely on accident for a discoverability cue. |
| Good | Onboarding is one question per screen (Q1-Q6), so complexity is revealed gradually. The alarm setup reveals only the selected dismiss method's configuration (`SunriseAlarmSetupView.swift:275-283`). Map-tag sheet reveals amount and lock-set fields only for the actions that need them (`SettingsView.swift:1102-1113`). | | | Keep these patterns; they are the model for 5.4. |

---

## 6. Breathing room between targets

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | 6.1 Quick-add chips are small and tight.<br>`App/ZANO/Features/Fuel/FuelView.swift:432-446, 873-897` | Chip = 13 pt semibold text plus 8 pt vertical padding (about 32 pt tall), 8 pt apart. These are the app's most-tapped controls. | 44 pt tall, 12 pt apart (bordered/filled controls). | Adjacent filled controls: 12 pt; primary logging controls should not be mis-tappable. |
| MEDIUM | 6.2 Stacks of borderless links have 12-20 pt between them.<br>`App/ZANO/Features/Onboarding/PaywallView.swift:307, 346-374`<br>`App/ZANO/Features/Share/WeeklyRecapShareView.swift:230, 267-270`<br>`App/ZANO/Features/Share/LockedOutMomentView.swift:387, 424-427`<br>`App/ZANO/Features/Onboarding/Screen12PermissionPriming.swift:60-76` | Restore (16 pt tall) then Continue free (16 pt tall) 20 pt apart; "Close" sits 12 pt under the Share button. | 44 pt frames and at least 24 pt of clearance, or one row with a divider dot. | Borderless targets get 24 pt because the space is the only boundary. |
| MEDIUM | 6.3 Onboarding emergency exit is a 6 pt bar.<br>`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:547-565` | 160x6 pt capsule plus 13 pt caption, hit area about 26 pt tall, no visible "hold". | `EmergencyHold` (row 3.9), 44 pt minimum, label states the hold. | Safety-critical control at the smallest size in the app. Hit-area rules: `better-accessibility`. |
| LOW | 6.4 Cosmetic category chips are 32 pt tall with 8 pt gaps.<br>`App/ZANO/Features/Trophy/CosmeticsShopView.swift:159, 170-185` | Same as chips in 6.1. | 44 pt, 12 pt. | Same. |
| LOW | 6.5 Sub-44 pt dismiss/back glyphs.<br>`Core/Sources/Core/UI/Components/FounderSeriesCard.swift:140-149` (about 23 pt)<br>`App/ZANO/Features/LockSetup/AlwaysAllowedWarningView.swift:172-180` (11 pt, no padding)<br>`App/ZANO/Features/Share/WeeklyRecapShareView.swift:214-221`, `LockedOutMomentView.swift:371-377` (22 pt)<br>`App/ZANO/Features/Onboarding/OnboardingContainerView.swift:154-162` (32 pt)<br>`App/ZANO/Features/Fuel/FuelView.swift:985-991` (32 pt) | Visible glyph doubles as the hit area. | Keep the visual, grow the frame to 44 pt (`contentShape`) without moving the glyph. | Cross-reference only: sizing is `better-accessibility`; spacing between it and neighbours is this skill's. |

---

## 7. Content bleeds, controls float: critical actions live in stable chrome

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **7.1 (H2)** Paywall CTA and the free path scroll.<br>`App/ZANO/Features/Onboarding/PaywallView.swift:113-125, 306-326` | One `ScrollView`: headline, benefits, built-plan section, plan cards, then the CTA block last. Estimated content height (token arithmetic): about 740 pt for one built goal, about 890 pt for three, against about 700 pt visible under the onboarding header on a 393x852 phone (about 590 pt on 375x667). The CTA button is about at the fold with one goal, off-screen with three or on a small phone; Restore and Continue free are below the fold at every size. | `StickyActionBar` (safeAreaInset + material + 16 pt inset) holding trial note, CTA, and a 44 pt "Continue with limited free"; only benefits and plan cards scroll. Show price and trial above the fold. | A primary conversion action and the legally-expected free exit must never depend on scroll distance. |
| HIGH | **7.2 (H3)** Alarm escape hatch is at the end of a ~1000 pt scroll and duplicates the primary ring.<br>`App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift:143-153, 223-345, 372-409, 411-444` | `ScrollView` with padding `lg` + `xl` and `xl` between blocks. Steps/Focus variants stack **two 148 pt rings** (the dismiss task, then the danger-coloured escape ring). Estimated: escape ring spans about y=620-770 on a 759 pt safe area; its toggle, hint, and footnote are below. Entirely below the fold on smaller phones. | Header and dismiss card fill the screen; escape hatch becomes a pinned bottom bar: a 44-56 pt "Hold to turn off" bar (progress fill along the bar, seconds shown), toggle above it. Only one ring on screen. | CLAUDE.md and spec 5.10: no one gets trapped, on a screen used half asleep. The exit currently competes with the task at equal size and sits where scrolling is required. |
| MEDIUM | 7.3 Lock screen: the emergency unlock is last in the scroll.<br>`App/ZANO/Features/Lock/LockStatusView.swift:55-73, 273-290` | Hold-to-unlock plus footnote follows goals and Time Bank. | Pinned action bar; goals scroll above it. | "Always available" should also mean always visible. |
| MEDIUM | 7.4 Plan Reveal CTA is inline; every neighbour pins it.<br>`App/ZANO/Features/Onboarding/Screen10PlanReveal.swift:84-88` vs `Screen3MainGoal.swift:73-79` | With three goals (about 700 pt) the CTA scrolls off on a 375x667 phone. | Pinned bar like screens 3-8. | Consistent position of "Continue" through the flow. |
| MEDIUM | 7.5 Pinned CTAs have no backing, unlike Today.<br>`App/ZANO/Features/Today/TodayView.swift:105-111` (material)<br>vs `Screen3MainGoal.swift:73-79`, `Screen4AppSelection.swift:103-109`, `Screen8CoachVoice.swift:34-40` (bare) | On content that scrolls (screen 8 is about 630 pt of content against about 590 pt of room on SE) cards slide behind an unbacked button. | One `StickyActionBar` used by every pinned CTA (material, 16 pt inset, safe-area padding). | Sticky chrome floats above content, it does not fight it. |
| MEDIUM | 7.6 Onboarding chrome ignores the screen's phase.<br>`App/ZANO/Features/Onboarding/OnboardingContainerView.swift:150-167`<br>`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:176-209` | The progress bar renders on screen 1 (the "full-bleed" hook, spec 7.1); back chevron and bar both stay through screen 14's running lock session, and Back there returns to the paywall mid-session (the countdown is cancelled on disappear, the lock session is not). | Hide chrome on screen 1 and on 14's running/celebrating phases. Single row: [back] [progress bar] instead of two rows (saves about 48 pt per screen). | Content should own the screen; a destructive back during a live lock is a trap. |
| LOW | 7.7 Widget prompt CTA floats up the page.<br>`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:289-319` | `Spacer(minLength:)` inside a `ScrollView` does not expand, so the CTA sits under the steps card instead of at the bottom like the other four phases. | Pinned bar. | Position consistency. |

---

## 8. Hold structure; plan for growth and clipping

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | **8.1 (H4)** Share card: preview and export are different layouts, and 7 rings do not fit.<br>`Core/Sources/Core/UI/Components/ShareCard.swift:86-146, 162-172`<br>`App/ZANO/Features/Share/WeeklyRecapShareView.swift:160, 179`<br>`App/ZANO/Features/Share/LockedOutMomentView.swift:308, 334`<br>`Core/Sources/Core/UI/PreviewCatalog.swift:231-232` | (a) `renderImage` defaults to 1080x1920 **points** at scale 1, and every token is fixed-pt: title 22, stat 17, captions 13, rings 44, padding 32. Type is 2.0% of canvas width in the export vs 6.9% in the 320 pt on-screen preview (3.4x smaller): what the user previews is not what they share, and on a Story the text is tiny. (b) `dayRingsStrip` is `HStack` of `GoalRing(.small)` at fixed 44 pt: 7 rings need 7x44 + 6x12 = 380 pt; a 320 pt card has 256 pt inside its padding, so 5 or more rings (`WeeklyRecapShareView` makes one per goal) overflow the trailing edge and are cut by `clipShape` (line 130). `PreviewCatalog` draws 7 rings at 220 pt wide. (c) `lineLimit(2)` on the title: "My phone won't let me open TikTok until I hit the gym." (54 chars, `ShareCopy.swift:36`) wraps to 3 lines at 256 pt and truncates in the preview, not in the export. | Render at the logical size the card was designed at (about 360x640 pt) and use `renderer.scale = 3` for 1080x1920 px. Make the ring strip width-driven (`GeometryReader`, ring = (width - gaps) / n) and let `GoalRing` take a diameter. Keep title `lineLimit(3)` and shrink with `minimumScaleFactor`. Add a 7-ring case to `PreviewCatalog` at the real preview width. | The card is the "organic content engine" (spec 5.14). It must be legible as a standalone image and identical to its preview. Arithmetic, not observed. |
| MEDIUM | 8.2 Share card composition is top-heavy and carries an empty strip.<br>`Core/Sources/Core/UI/Components/ShareCard.swift:86-127`<br>`App/ZANO/Features/Share/LockedOutMomentView.swift:513-519` | Everything is top-anchored with a trailing `Spacer`; at 9:16 roughly the lower half is empty (more in the 1080 export). Locked-out passes `dayRings: []`, but the empty `HStack` still adds two 24 pt gaps. The hero stat is a 17 pt run-on line ("4 workouts . 1,020g protein . 6h 40m"). | Treat it as a poster: vertically centre the hero (title or the largest stat in `numeralLarge`), rings second, stats as a 2x2 numeral grid, wordmark bottom-trailing. Skip the strip when empty. | Spec 16 P7 shows big stats. Fixed top anchoring wastes the format. |
| MEDIUM | 8.3 One-line clamps on the text that carries the number.<br>`Core/Sources/Core/UI/Components/GoalRow.swift:112, 117`<br>`App/ZANO/Features/Fuel/FuelView.swift:607-616`<br>`Core/Sources/Core/UI/Components/RingCluster.swift:154-164`<br>`Core/Sources/Core/UI/Components/LockStatusCard.swift:88` | `GoalRow` title is `lineLimit(1)`. Quick Repeat's title is "Your usual chicken bowl (48g)?": the grams, the deciding fact, truncate first. Ring labels are 64 pt wide, one line. | Allow two lines in `GoalRow` (title and detail), move the number to the trailing accessory (row 3.3), widen ring cells to `max(diameter, available/n)`. | Never let the decisive number be the part that clips. |
| MEDIUM | 8.4 Fixed-height carousel.<br>`App/ZANO/Features/Onboarding/Screen2SocialProof.swift:44` | `TabView` `.frame(height: 140)` holds quotes of about 90 characters. | `minHeight` (or measure the tallest quote) and let pages grow. | No fixed heights on text containers; translations and larger text will clip. |
| LOW | 8.5 Badges inline with titles cannot wrap.<br>`Core/Sources/Core/UI/Components/PaywallCard.swift:66-79`<br>`App/ZANO/Features/Trophy/CosmeticsShopView.swift:289-301`<br>`App/ZANO/Features/Settings/SettingsView.swift:626-635` | "BEST VALUE", "Equipped", and "auto-detected" sit beside a title in an `HStack`; a long localised title squeezes or truncates the tag. | Badge trailing on its own line (ViewThatFits) or above the title. | A one-word label is the riskiest string on the screen. |
| LOW | 8.6 Fixed 280x280 burst frame and hand-tuned confetti offsets.<br>`App/ZANO/Features/Celebration/UnlockCelebrationView.swift:127`<br>`App/ZANO/Features/Onboarding/Screen14FirstWin.swift:606-622` | Burst frame sizes the headline block; confetti offsets `-140...140`, `y: 380` are absolute. | Size to container; derive offsets from `GeometryReader`. | Holds on 393 pt, drifts on other widths. |

---

## 9. Defects found while reading (not layout principles, but they break layout)

### 9.1 (H5) `ProgressView()` resolves to the app's Progress screen

`App/ZANO/Features/Progress/ProgressView.swift:111` declares `struct ProgressView: View` in the
`ZANO` module. Module declarations shadow imported ones, so an unqualified `ProgressView()` in this
target is the **Progress screen** (with its `@Query`s and nav title), not the spinner. The Share
views already know this (`LockedOutMomentView.swift:470-476`, `WeeklyRecapShareView.swift:312-318`
use `SwiftUI.ProgressView()`), but six other sites do not:

- `App/ZANO/Features/Fuel/FuelView.swift:1106` (barcode lookup state)
- `App/ZANO/Features/SunriseAlarm/AlarmRingingView.swift:235` (loading state **while the alarm rings**) and `:264` (tag scan, inside the card)
- `App/ZANO/Features/SunriseAlarm/SunriseAlarmSetupView.swift:319` (inside a button label)
- `App/ZANO/Features/Onboarding/PaywallView.swift:222`, `:319`, `:351` (offerings load, purchase, restore)

Fix: qualify all six as `SwiftUI.ProgressView()`, or rename the screen to `ProgressScreen` and stop
depending on a comment. Renaming is the durable fix; the qualifier is the one-line fix. Compile check
is not possible here (no toolchain); this is a name-lookup argument, not an observation.

### 9.2 Other broken or inert controls seen in passing

- `App/ZANO/Features/Settings/SettingsView.swift:455-459` `presentPaywall()` is empty, so the Free-tier upsell's filled CTA (line 423-427) does nothing.
- `App/ZANO/Features/Today/TodayView.swift:330-331` "Log the rest on Fuel" is a disabled button (row 3.1).
- Copy leaks in views (CLAUDE.md: no hard-coded user-facing strings): `"min banked"` (`TodayView.swift:194`, `LockStatusView.swift:141`), `"min available"` (`LockStatusView.swift:250`), `"Done"`/`"Not yet"` (`TodayView.swift:468`, `LockStatusView.swift:345`), `"+\(preset)\(unitSuffix)"` (`FuelView.swift:434`), `"\(Int(staple.proteinG))g protein"` (`FuelView.swift:974`). `Copy.lockStatus.timeBankFootnote` still cites "spec 5.2" (`LockStatusCopy.swift:28`; already noted in `ui-stress-test-findings.md` section 8).

### 9.3 Reduce Motion: existing gaps to close (or not regress) in the redesign

The redesign task said to preserve `accessibilityReduceMotion` gating. These existing animations are
still ungated, so whoever restyles those files should gate them as part of the same edit:
`PaywallCard.swift:109`, `FuelView.swift:895` (chip title animation), `Screen3MainGoal.swift:116`,
`Screen7FallOff.swift:73`, `Screen8CoachVoice.swift:83`, `Screen5PhoneTime.swift:27`,
`Screen2SocialProof.swift:74`, `OnboardingContainerView.swift:97, 176`, `PaywallView.swift:261`,
`Screen14FirstWin.swift:336` (`.symbolEffect(.pulse, options: .repeating)`), `:569`, `:624-627`.
`Screen9WakeUp.swift` count-up and `Screen14` were already flagged in
`ui-stress-test-findings.md` section 8.

---

## 10. Target layouts (opinionated sketches, token-only)

These are reading-order sketches, not pixel specs. Every number is an existing `Theme` token.

**Today** (393 pt phone; hero in `numeralHero`, everything else on the existing ramp)

```
eyebrow: Tue 23 Sep                                  [flame 14]      streak pill trailing
+-----------------------------------------------------------+
| 1            Locked                                    >  |  lock card = hero, count in numeralHero
| goal left    TikTok, Instagram, YouTube                   |  apps as system Label chips (row 1.8)
+-----------------------------------------------------------+
  (72)          (25)           (0)                             3 equal columns, ring .medium
  Protein      Focus         Workout                           value in ring, "of 150g" caption
  +2 more required goals >                                     (row 5.1)
+-----------------------------------------------------------+
| Ghost: 2 vs 3                                             |  ghost banner, unchanged
+-----------------------------------------------------------+
[ Start 25-min focus session ]                                 StickyActionBar (material, 16 pt inset)
```

**Fuel**: Quick Repeat row (when present) / Protein card [ring, 72 of 150g, chips inside] / Water
card [ring, 500 of 3000ml, chips inside] / Gap planner (when behind) / Staples (collapsed list, "Add"
in the header, swipe to delete).

**Settings**: warning banner (when relevant) / Plan card / Lock and verification (Lock sets, Gym,
NFC tags) / Coach (one row) / Mornings and sleep / Rewards / More.

**Paywall**: headline, three benefit tiles in one row, two price cards (annual visibly larger, trial
length in the title row), "3 goals, 1 lock set" caption; pinned bar: trial note, CTA, 44 pt "Continue
with limited free", restore as a small link beside it.

**Alarm**: clock (`numeralLarge`), dismiss card (one ring or one button), snooze as a bordered
secondary; pinned bottom bar with the escape hatch and its "I'm not home" toggle above it.

**Progress**: [Streak hero | Time reclaimed] / This Week recap card / badges (one row plus peek).

**New Core/UI pieces this implies** (only where three or more call sites already exist, per
CLAUDE.md): `StickyActionBar`, `SelectableRow`, `MetricCard` (ring + numeral + trailing accessory
slot), `EmergencyHold`, `SectionCard` (title inside the card). Theme additions: `Typography.numeralHero()`
(about 64 pt rounded, monospaced digits) and the `Metrics.iconBadge*` tokens already proposed in
`apple-design-review.md` section 8.2.

---

## 11. What is already right (so nobody "fixes" it)

- Section rhythm on Today, Progress, Fuel, and Lock: 24 pt between sections, 8-12 pt within, no divider lines. This passes the 2x rule (`TodayView.swift:88`, `ProgressView.swift:120`, `LockStatusView.swift:55`).
- `PrimaryButton` has its horizontal inset now (`PrimaryButton.swift:91`) and a 46 pt height.
- Component structure is consistent: leading icon, text column, trailing indicator (`LockStatusCard`, `GhostProgressBanner`, `GoalRow`).
- `OnboardingQuestion` is a good shell (title, subtitle, content, scrolling, room for a pinned CTA); the problem is the 24 pt CTA inset around it, not the shell.
- Selection state in the onboarding cards is unmistakable (2 pt accent border plus check).
- The alarm's centred single-axis layout and the celebration's staged reveal are the right structure.
- `ShieldPreview`'s emergency action is always present and its target is 44 pt (`ShieldPreview.swift:143`).
- Logical properties: leading/trailing everywhere except the two `chevron.right` uses (row 4.12); no `.left`/`.right` padding or alignment anywhere in the audited set.

---

## 12. Hand-offs to owners of the forbidden paths

- **`ContentView.swift` / `ZANOApp.swift`:** apply `.tint(Theme.Colors.accent)` and `.preferredColorScheme(.dark)` on the root so native controls (toolbar Save/Cancel, steppers, toggles, text-button rows, menu pickers) stop rendering system blue/green (row 4.4). `ContentView` is still the Session 0 scaffold, so the tab bar chrome is not yet reviewable; when it lands, check the bottom inset interplay with `TodayView`'s `safeAreaInset` (about 46 pt button plus 24 pt padding above a tab bar).
- **`LockSetManager.swift`:** no layout change; `LockSetupView` has no entry point anywhere (see `SettingsView.swift:265-271`); the Settings restructure (row 1.5) should add "Lock sets" as its first row.
- **`Assets.xcassets`:** if the redesign wants app icons or illustrations on onboarding heroes (Screens 1, 12, 14 all use a lone SF Symbol in a circle), they go here.

## 13. Not verified

- **No rendering at any width.** All sizes are token arithmetic against 393x852 and 375x667. Nothing was measured in a preview, Simulator, or device.
- **200% zoom / Dynamic Type:** not testable and not honoured (`Theme.Typography` uses fixed `Font.system(size:)`; `ui-stress-test-findings.md` 1.2). The one-line clamps and fixed frames in rows 8.3-8.5 will be worse than stated.
- **RTL mirror and pseudo-localisation:** not run. Only a static grep for physical left/right (two `chevron.right`).
- **`LazyVGrid` cell alignment, `Button` plain-style hit testing, and the empty inline nav bar above Today's header** (rows 4.7, 3.8, 4.11) are predictions from framework defaults.
- **The `ProgressView` shadowing** (9.1) is a Swift name-lookup argument; it needs one compile to confirm.
- **`OnboardingFlowState.swift`** and the header comment blocks listed at the top were skimmed, not line-read.
- **Widgets, Live Activities, and the shield extension** (`Extensions/**`) are out of scope for this pass.

---

**Verdict: Block.** H1-H6 are open (Today's hidden ring, paywall CTA, alarm escape hatch, share
card preview/export, `ProgressView` shadowing, Today's goal/lock mismatch). Everything else is
recorded above as work to do.
