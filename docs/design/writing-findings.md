# ZANO copy audit: writing findings

Date: 2026-09-23. Method: `interfaces:better-writing` applied to every file in `Core/Sources/Core/Copy/` (23 files), cross-checked against `docs/spec.md` §5.1, §5.13, §7, §8, §21, §24, §25.3 and against the call sites that decide whether a claim is true (`PaywallView.swift`, `EmergencyUnlock.swift`, `GearOffersEngine.swift`, `OnboardingFlowState.swift`, `GhostMode.swift`, `StartLockIntent.swift`). Source-only: nothing here has been rendered on a device.

**This document is read-only output. No Copy file was edited.** A later phase rewrites. Every finding cites `file:line` and quotes the current string.

**Verdict: Block.** Several HIGH findings remain (internal spec citations rendered to users, a false emergency-unlock claim, a live paywall with no subscription terms, fabricated stats and testimonials shown as real, and contradictory alarm instructions). The rest is work to do, not a reason to stop.

---

## 0. The short version

The copy layer reads like what it is: about 14 agents, each writing a self-contained file against a header comment, none reading the others. The seam shows in five ways.

1. **Voice is a feature of two files, not of the product.** Only `ShieldCopy` (+ `CoachVoiceTone`) and `OnboardingDripCopy` take a voice. `SunriseAlarmCopy`'s header claims voice-aware ring/wind-down/confirmation copy, but none of those functions accepts a voice. Everything else defaults to one unmarked, friendly, slightly-Hype middle voice ("Let's fix that", "Let's do this", "Let's go", "Nice", "No worries"). A Data or Tough Love user leaves the shield and lands in Hype.
2. **Even inside the voice-aware files the four voices are thin.** They differ in punctuation and vocabulary, not in *what they say*. Spec §5.13's samples work because each is specific ("3 more grams", "You said 4 days. It's Thursday. You're at 2.", "the gym's open till 11", "Protein 72/150g. Avg completion 81%"). None of the shipped lines reference the user's own commitment, a real number, or a real fact. Chill is one catchphrase ("whenever") repeated 11 times.
3. **The shield never says the app's name.** `ShieldCopy.content` computes `name` and only uses it in fallbacks that cannot be reached (§3.2). Spec §5.1's lead example, "TikTok unlocks after your workout", is not implemented.
4. **Spec §8 is only half-honoured.** No shame is mostly respected, but after a miss the copy never names the next smallest step (rule 9), identity framing (rule 5) does not exist anywhere, the variable-reward "coach voice line" (rule 4) does not exist, and "n of m" progress (rule 2) has no Today string.
5. **Internal language and unverified claims leak to users.** `spec §5.2`, `spec §5.10`, `spec §24` appear inside user-facing string literals; a hardcoded `$6.99/month`; fake testimonials; a fake "Built for you in 2:14."; invented usage statistics in Data-voice pushes.

### Priority order for the rewrite phase

| # | Work | Why first |
| --- | --- | --- |
| 1 | Fix all HIGH rows in §5.1 to §5.3 (leaks, false claims, paywall terms, errors, alarm contradictions) | Ship-blockers; small edits |
| 2 | Shield: use the app name, add next-smallest-step to after-miss, rebalance the four voices (§3) | Most-seen surface; the product's signature |
| 3 | Adopt a single voice bible (§2.2) and thread `CoachVoice` through Celebration, First Win, Today status line, Alarm ring/confirm, Locked-out card | Closes the "14 people" seam |
| 4 | Add identity framing + coach-voice reward line (§4) | Spec §8 rules 4 and 5 are unimplemented |
| 5 | Consolidate duplicates into `Copy.common` (§6) and fix terminology (§5.4) | Prevents the seam re-opening |
| 6 | Capitalization, pluralization, fragments (§5.5, §5.6) | Mechanical, do last so it applies to final strings |

---

## 1. Scope and what was not audited

Read in full: `Copy.swift`, `CoachVoice.swift`, `CommonCopy`, `OnboardingCopy`, `OnboardingDripCopy`, `PaywallCopy`, `ShieldCopy`, `WidgetCopy`, `SunriseAlarmCopy`, `SunriseAlarmScreenCopy`, `TodayCopy`, `FuelCopy`, `LockStatusCopy`, `LockSetupCopy`, `ProgressCopy`, `SettingsCopy`, `ShareCopy`, `TrophyCosmeticsCopy`, `AlwaysAllowedCopy`, `AutoFocusSetupInstructions`, `GearOffersCopy`, `CelebrationCopy`, `FounderSeriesCopy`.

Not audited, deliberately:

- `Watch/ZANOWatch/WatchCopy.swift` (`Copy.watch`, 39 call sites). It lives outside `Core/Sources/Core/Copy/` and belongs to the concurrent workflow that owns `Watch/**`. **Re-run this audit against it once that workflow lands**, especially for voice (a wrist haptic-plus-one-line surface is where a voice matters most).
- `Core/Sources/Core/Verification/NFCTagSetupInstructions.swift`. Deliberately outside `Copy` (per `AutoFocusSetupInstructions.swift` header); not read.
- Screen files. Only two hardcoded `Text("...")` literals exist in `App/ZANO` (both in `ContentView.swift`, the scaffold; owned by the concurrent workflow). The "no strings in views" rule is being honoured. The exceptions are strings routed around Copy in Core, listed in §7.

Localization: the entire layer is plain Swift interpolation and ternaries (`"\(n) categor\(n == 1 ? "y" : "ies")"`, `LockSetupCopy.swift:37-39`). None of it is localizable as written. Not a v1 blocker (the spec has no localization requirement) but noted where it changes a recommendation.

---

## 2. Voice: the seam, mapped

### 2.1 Which surfaces are voice-aware

| Surface | File | Takes a voice? | Should it? | Verdict |
| --- | --- | --- | --- | --- |
| Shield title/subtitle | `ShieldCopy.swift:140` | Yes | Yes | Voiced, but thin (§3) |
| Shield notifications | `ShieldCopy.swift:253,273` | Yes | Yes (emergency: light touch only) | Voiced |
| Streak / goals-left / miss clauses | `CoachVoice.swift:80-112` | Yes | Yes | Voiced, thin, one plural bug |
| Post-onboarding drip pushes | `OnboardingDripCopy.swift` | Yes (`NudgeTone`) | Yes | Voiced; Data lines fabricate stats; Tough Love lines shame |
| Sunrise alarm ring / wind-down / confirm | `SunriseAlarmCopy.swift:60,110,166` | **No**, though header (`:17-19`) says "used where it adds real texture — the escalating ring copy, the wind-down nudge, the dismissed confirmation" | Yes for ring, wind-down, dismissed | **Header contradicts code.** Fixed strings only |
| Unlock celebration | `CelebrationCopy.swift` | No | **Yes, most of all** | The emotional peak has no voice. Spec §8.4 lists "coach voice line" as a variable reward |
| Onboarding screens 9-14 | `OnboardingCopy.swift:99-237` | No | Yes (voice is chosen on screen 8) | First moment a voice could carry; every CTA is Hype-flavoured for all users |
| Today status line + CTAs | `TodayCopy.swift` | No | Yes for the status line only | Most-viewed screen has zero personality |
| Widgets / Live Activities | `WidgetCopy.swift:12-16` | No (declared debt) | Status line only; keep chrome fixed | See §3.5 |
| Locked-out share card | `ShareCopy.swift:23` | No | Neutral is right (shared publicly) but `acknowledgementLine` is wrong | §5.1 |
| Progress / recap / trophy | `ProgressCopy`, `TrophyCosmeticsCopy` | No | Recap insight yes, chrome no | Fine for chrome |
| Gear offers | `GearOffersCopy.swift:17-21` | No (documented assumption) | No | **Agree.** Commerce prompts should stay neutral |
| Settings, Lock Sets, Always Allowed, Auto-Focus how-to | various | No | No | **Agree**, but must be plain (see §5.4) |
| Safety (escape hatch, snooze rule, no-guarantee disclaimer) | `SunriseAlarmCopy.swift:132-153` | No, by design | No | **Agree.** Keep fixed |

The invariant surfaces are a *choice*, and mostly a good one. The defect is that the "neutral" default was never defined, so each agent invented one. Result: a fifth, accidental voice.

### 2.2 Proposed voice bible (for the rewrite phase to adopt)

One product voice underneath all four: **plain, second-person, forward-looking, never blaming.** The coach voices are dials on top of it, not separate writers.

| | Hype | Tough Love | Chill | Data |
| --- | --- | --- | --- | --- |
| Signature move | One CAPS word per line, lands on a specific number or goal | Quotes the user's own commitment back and states the gap | Offers permission plus one real fact (hours, distance) | Label: value. Numerator/denominator, comparison to own baseline |
| Sentence shape | Short, ends on `!` or a period, never both | Declarative, no `!`, no rhetorical questions | Soft imperatives, contractions | Fragments, no adjectives |
| Uses the user's numbers | "3 more grams", "12 min" | "You said 4 days. You're at 2." | "The gym's open till 11." | "72/150g", "81% 30-day avg" |
| Never | Sarcasm, insults, more than one caps word | "Prove it", "no excuses", "you failed", anything implying the user is making excuses | The catchphrase "whenever" in more than about 1 line in 5; false reassurance ("soon enough") | Invented statistics; threat framing after a slip |
| Emoji | 🔥 next to a streak only | None | None | None |
| After a slip | "Comeback day" plus the smallest step | "One slip. Not two." plus the smallest step | "That's fine." plus the smallest step | "1 slip logged. Streak holds." plus the smallest step |

Every voice, in every state, ends a slip message with the **next smallest step** (spec §8.9).

---

## 3. Coach-voice differentiation audit

### 3.1 What the spec promises vs what ships

| Voice | Spec §5.13 sample | What makes the sample work | In shipped copy? |
| --- | --- | --- | --- |
| Hype | "LET'S GO, 3 more grams" | Specific remaining amount | Half. Caps and energy yes; specific amount never (Shield has only a goal *count*) |
| Tough Love | "You said 4 days. It's Thursday. You're at 2." | Quotes the user's own stated target, compares to reality | **No.** Tough Love shipped as "Hype without the exclamation marks plus commands" ("Go do them.", "Prove it.", "Handle today.") |
| Chill | "Whenever you're ready, the gym's open till 11" | Permission plus a real, useful fact | Half. Permission yes (overused); the fact never |
| Data | "Protein 72/150g. Avg completion 81% this month." | Real quantities and a baseline | **No.** Data shipped as "terse Chill" ("Shield active.", "Status: locked.") with no numbers beyond a count |

The onboarding voice picker promises these exact samples (`CoachVoice.swift:58-68`, doc: "so what the user previews is what they actually get"). For Tough Love, Chill and Data that promise is not kept. The user picks "You said 4 days. It's Thursday. You're at 2." and never sees anything like it.

### 3.2 The app name is never used (bug that flattens every voice)

`ShieldCopy.swift:143-148` builds `name` from `context.shieldedName`. It is used only in `fallback:` arguments (`:159`, `:171`, `:178`), and `pick(...)` only calls the fallback when the voice table is empty. All four voices have non-empty tables (`:306-332`). So `name` is dead, and `ShieldContext.shieldedName` (`:78`) never reaches the screen.

Result: the shield says "Locked for now." to a user staring at a TikTok shield, instead of spec §5.1's "TikTok unlocks after your workout." Every voice loses its most concrete anchor.

Fix: interpolate `name` into the title of every non-verifying moment. Keep the "This app" fallback for category shields (`:147`).

### 3.3 Data the shield needs so the voices can be specific

`ShieldContext` (`ShieldCopy.swift:71-123`) carries only a count. To deliver the spec samples, the rewrite phase needs optional additions, mirrored into `SharedDefaults` by the app (extensions cannot read SwiftData, spec §11/§27). Each must degrade to today's line when `nil`:

| Field | Feeds | Example use |
| --- | --- | --- |
| `nextGoalSummary` (`"your workout"`, `"12g of protein"`, `"one focus session"`) | all voices, after-miss step | "TikTok unlocks after your workout." |
| `goalsDoneToday` / `goalsPlannedToday` | Data, Hype | "Goals 2/3 today." |
| `weeklyTarget` / `weeklyDone` (from onboarding Q4 + verified sessions) | Tough Love | "You said 4 days. You're at 2." |
| `completionRate30d` | Data | "30-day avg 81%." |
| `gymOpenUntil` / `gymMinutesAway` | Chill, Hype | "The gym's open till 11." |

This is a store/state change, so it is outside Copy's remit; the rewrite phase must sequence it with whoever owns `SharedDefaults`.

### 3.4 Per-voice findings

**Hype.** Good instincts: `"ONE goal from everything unlocking."` (`ShieldCopy.swift:307`) and `"\(remaining) goals between you and everything."` (`CoachVoice.swift:95`) are the best lines in the file. Problems: `"Time to unlock this."` (`:328`) has no energy; `"Locking in your last goal — this unlocks any second now."` (`:300`) uses "locking in" while the screen is a *lock*, which is confusing; `"Yesterday slipped — doesn't matter, TODAY'S the comeback."` (`CoachVoice.swift:107`) says "doesn't matter", which dismisses the miss and contradicts the streak's stakes.

**Tough Love.** Drifts to scolding: `"Prove it."` (`:322`) implies doubt; `"No excuses now."` (`:308`) accuses the user of excuse-making; `"Don't waste them stalling."` (`:202`) accuses of stalling; `"Go do them."` (`CoachVoice.swift:96`) is a bare command; `"Use it if you need it, not as a habit."` (`:278`) lectures at the emergency exit (§5.1). Tough Love should be *respectful and factual* (quote the user), not contemptuous.

**Chill.** "Whenever" appears in 11 user-facing strings across `ShieldCopy` (5), `OnboardingDripCopy` (4), `CoachVoice` (2). In the shield notification it stacks three times in one push: title `"Your goals, whenever."` (`:337`), body prefix `"Whenever you're ready — "` (`:259`) plus `goalsRemainingClause` `"2 goals whenever you're ready."` (`CoachVoice.swift:97`) yields `"Whenever you're ready — 2 goals whenever you're ready."` Also `"This'll open up soon enough."` (`:330`) is false reassurance when three goals remain. And `"1 days in, no rush."` (`CoachVoice.swift:85`) is a plural bug at streak 1.

**Data.** Never quantifies beyond the count. `"Yesterday: missed. 2-in-a-row is what breaks a streak — today doesn't have to."` (`CoachVoice.swift:110`) says "missed" (spec §8.9 says "slipped") and states the loss threat *after a miss* (§8.10 forbids exactly this). The drip Data lines invent statistics (§5.1).

### 3.5 Concrete rewrites (Shield)

`{name}` = `shieldedName ?? "This app"`. Second line of each cell is the fallback when the optional data (§3.3) is `nil`.

**Mid-lock title**

| Voice | Before (`ShieldCopy.swift:328-331`) | After (with data / fallback) |
| --- | --- | --- |
| Hype | "Let's earn it back!" / "Time to unlock this." | "{name} unlocks after {nextGoal}. LET'S GO." / "{name} unlocks after your goals. Let's GO." |
| Tough Love | "Locked until you earn it." / "This opens when you do the work." | "{name} is locked. You said 4 days. You're at 2." / "{name} is locked until your goals are done." |
| Chill | "Locked for now." / "This'll open up soon enough." | "{name}'s locked for now. The gym's open till 11." / "{name}'s locked for now." |
| Data | "Shield active." / "Status: locked." | "{name}: locked. Goals 2/3 today." / "{name}: locked. 3 goals open." |

**After-miss (must end in the smallest step, §8.9 and spec §5.1's own example "One focus session and you're back")**

| Voice | Before (`ShieldCopy.swift:321-324` + `CoachVoice.swift:107-110` + goals-left clause, e.g. "3 goals left") | After |
| --- | --- | --- |
| Hype | "Comeback day. Let's GO." + "Yesterday slipped — doesn't matter, TODAY'S the comeback. 3 goals between you and everything." | Title keep: "Comeback day. Let's GO." Subtitle: "Yesterday slipped. TODAY is the comeback. One focus session and you're back." |
| Tough Love | "Comeback day. Prove it." + "Yesterday slipped. Never miss twice. Handle today. 3 goals left. Go do them." | "One slip. Not two." + "Yesterday slipped. Today counts. One focus session and you're back." |
| Chill | "Fresh start today." + "Yesterday slipped, that's fine. Today's a reset. 3 goals whenever you're ready." | Title keep. Subtitle: "Yesterday slipped, and that's fine. One focus session gets you back." |
| Data | "Recovery day: 1 miss logged." + "Yesterday: missed. 2-in-a-row is what breaks a streak — today doesn't have to. 3 goals open." | "Recovery day. 1 slip logged." + "Streak holds through one slip. One focus session restores your pace." |

Rule: after a slip, show the *smallest* open goal, not the total. Showing "3 goals left" to someone who just slipped is the heaviest possible framing.

Also `ShieldCopy.Moment.resolve` (`:57-62`) checks `goalsRemaining == 1` *before* `recentMiss`, so a user who slipped yesterday and has exactly one goal left never sees the comeback acknowledgment. That is the highest-value comeback case (spec §5.6: "shield copy that acknowledges it"). Copy-adjacent logic bug; flag to the shield owner.

**Verifying (`:292-304`)**

| Voice | Before | After |
| --- | --- | --- |
| Tough Love title | "Verifying. Don't close the app." | "Verifying your last goal. One moment." ("the app" is ambiguous on a shield that sits over a *different* app) |
| Chill subtitle | "Wrapping up verification, then you're free." | "Wrapping up verification, then it opens." ("you're free" frames the lock as a cell) |
| Hype subtitle | "Locking in your last goal — this unlocks any second now." | "Checking your last goal. This opens any second." |

**Widgets and Live Activities.** `WidgetCopy.swift:12-16` says it is deliberately un-voiced because the extension must stay tiny. `CoachVoice.from(sharedDefaultsRaw:)` already works in an extension (it reads App Group state), so voicing *only* the single status line (`goalsRemaining`, `earnMeterGoalsRemaining`) is cheap: Hype "1 to go!", Tough Love "1 left.", Chill "1 goal left", Data "1 open". Keep all button/control labels fixed. Also stop imposing 🔥 on Data users: `WidgetCopy.streak` returns `"14🔥"` for everyone (`:41`).

### 3.6 Concrete rewrites (Celebration, First Win: voice is absent at the emotional peak)

`Copy.celebration.headline` = `"Earned."` (`CelebrationCopy.swift:34`) is a good brand anchor. **Keep it fixed across voices**; add voice only to a second line. The variable reward (§8.4, about 1 in 6) is a coach line:

| Voice | New `Copy.celebration.coachLine(voice:)` |
| --- | --- |
| Hype | "THAT'S the one. Same again tomorrow!" |
| Tough Love | "You said you would. You did." |
| Chill | "Nice and steady. Enjoy the rest of your day." |
| Data | "Goals 3/3 today. 30-day average 81%." |

`Copy.celebration.dismissButtonLabel = "Nice"` (`:80`) is a reaction, not a verb, and reads oddly for Tough Love and Data users. Use `Done`.

First win (`OnboardingCopy.swift:225-232`) is the first moment a chosen voice can appear. `firstWinNotVerifiedTitle = "No worries"` (`:231`) is Chill leaking as the default for everyone. Voice it: Hype "Not this time. Go again!", Tough Love "That one didn't count. Run it again.", Chill "No worries. Try again when you're ready.", Data "0 of 10 min verified. Try again." Keep the body (`"You can always try again — your plan is already saved."`); it is good.

---

## 4. Spec §8 retention psychology: compliance table

| Rule | Copy status | Evidence and fix |
| --- | --- | --- |
| 1 Early wins engineered | Pass | `OnboardingCopy.swift:151-153` "Starting at 2 workouts · target 4 workouts" makes the low start visible |
| 2 Progress always partially filled ("2 of 3") | **Partial** | `TodayCopy.swift` has no "n of m" string (only "Locked · 3 goals left", `:25-28`). `ringNotSet = "Not set"` (`:33`) is an empty ring with no next action; make it a forward prompt ("Add a workout goal"). `ProgressCopy.goalsCompletedLabel` does it correctly (`:39-41`); reuse |
| 3 Streaks have forgiveness | **Partial** | Shield after-miss and `streakFreezesLabel` exist. No copy at all for Plan B (§5.5), Comeback mode or Travel mode (§5.18). `EmergencyUnlock.swift:14` plans the string "This will end your streak", which contradicts Never Miss Twice (one miss does not end a streak) |
| 4 Variable reward with a coach voice line | **Missing** | No coach-voice reward string exists anywhere. See §3.6 |
| 5 Identity framing after 3-4 consistent weeks | **Missing** | Grep for identity/"consistent" language across `Core/Sources` finds none. Streak copy stays task-shaped forever ("Streak: 14 🔥"). Proposal below |
| 6 Fresh-start timing | **Missing** | No Monday/1st/birthday/challenge copy. Only `Copy.badges.title` for "Monthly Challenge" |
| 7 Nudge scarcity | Neutral | Drip pushes are one-time. The "widget not added" nudge does not change what the user does tonight; confirm with the drip owner that it passes the rule |
| 8 Effort asymmetry | n/a to copy | `Copy.today.beginLockTitle = "Hold to start today's lock"` (`:36`) adds a hold to a routine action; confirm a reason exists |
| 9 No shame; misses are "slipped" plus the next smallest step | **Violated** | See table below |
| 10 Loss aversion, ethically | **Partial** | Streak-at-stake before a lock is fine (`streakClause(.toughLove)`), and correctly omitted after a miss. Violated by Data `missAcknowledgment` (threat after a miss) and Tough Love `timeBankClause` |
| 11 Endowed progress | Partial | `firstWinCelebrationSubtitle` gives Day 1; no "head start" challenge copy |
| 12 Friction only where asked | **Violated** | Emergency notification (Tough Love): "Use it if you need it, not as a habit." Friction at the one exit the user must always have |

### No-shame (rule 9) violations

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `CoachVoice.swift:105-112`, `ShieldCopy.swift:169-174` | After-miss shows the total goals left ("3 goals left. Go do them.") | End with the smallest step (§3.5 table) | Rule 9: a slip is "always followed by the next smallest step". Currently followed by the heaviest possible count |
| MEDIUM | `CoachVoice.swift:110` | "Yesterday: missed. 2-in-a-row is what breaks a streak — today doesn't have to." | "Recovery day. 1 slip logged." + "Streak holds through one slip." | "Missed" vs the sanctioned "slipped"; threat framed after a miss (rule 10) |
| MEDIUM | `ShieldCopy.swift:322,308,202` | "Prove it." / "No excuses now." / "Don't waste them stalling." | "One slip. Not two." / "Last one. You've done the hard part." / "{n} min earned. Spend them when you finish." | Implies the user is doubting, excusing, or stalling |
| MEDIUM | `OnboardingDripCopy.swift:38,53,83` | "You skipped it during setup." / "You haven't saved a gym yet" / "You're doing this alone" | "Add your widget. It takes two taps." / "Save your gym so workouts verify themselves." / "Squads keep you honest. Start one." | Accusatory. "Doing this alone" is a guilt line; none changes what the user does tonight |
| MEDIUM | `SunriseAlarmCopy.swift:139` | "Morning goal missed — you used your one snooze already." | "Morning goal slipped: that was your second snooze. Tomorrow's alarm is a fresh start." | "Missed" plus blame ("you used"); no next step |
| MEDIUM | `OnboardingCopy.swift:91-92` | "When do you usually fall off?" / "This helps us catch you before it happens." | "When does your routine usually slip?" / "ZANO will plan extra support for those moments." | "Fall off" is off-lexicon ("slip" is the sanctioned word); "catch you" reads as surveillance |
| LOW | `FuelCopy.swift:35` | "You're 12g behind today" | "12g to go today" | Additive framing for food (spec §24 disordered-eating-safe copy); "behind" is a deficit word |
| LOW | `ProgressCopy.swift:46-50` | "Up 2" / "Down 1" / "No change" | "Up 2 ranks" / "Slipped 1 rank" / "Holding at {tier}" | "Up 2" of what? and "Down" is the only loss word in Progress |

### Identity framing (rule 5): proposed shape

Add `Copy.identity.line(voice:, consistentWeeks:)`, shown when `consistentWeeks >= 3`, never in the same session as a slip, and also usable by the weekly recap:

| Voice | Line |
| --- | --- |
| Hype | "4 weeks straight. You're a lifter now!" |
| Tough Love | "Four weeks. This isn't a streak anymore. It's who you are." |
| Chill | "Four weeks in. This is just what you do now." |
| Data | "4 consecutive weeks above 80%. New baseline." |

The Data line must only be emitted when the threshold it names is true (tie to the adaptive engine's real band, spec §9.1).

---

## 5. Findings by principle

Severity: HIGH misleads or hides recovery. MEDIUM breaks voice, terminology or capitalization consistency. LOW isolated polish.

### 5.1 Truthfulness, internal leaks, claims (HIGH)

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `LockStatusCopy.swift:28` | "Unused minutes expire at midnight — spec §5.2, no hoarding." | "Unused minutes expire at midnight." | Internal doc citation and a "no hoarding" rationale shown to users |
| HIGH | `AutoFocusSetupInstructions.swift:162,171` | "(like the Bedtime Gate, spec §5.10)" / "(spec §24, §5.10 point 6: "no one gets trapped")" | Drop both parentheticals. Second: "It also never affects Emergency Unlock: ending a lock early works the same with or without Auto-Focus." | Spec section numbers in setup instructions |
| HIGH | `Core/Sources/Core/Intents/StartLockIntent.swift:37` (outside Copy) | "Verified goals deposit minutes into today's Time Bank (spec §5.2)." | "Verified goals add minutes to today's Time Bank." | Shown in Shortcuts and Siri. Not in the Copy directory, so a Copy-only sweep would miss it |
| HIGH | `LockStatusCopy.swift:44` | "Always available. No streak penalty, no judgment." | "Always available." (or, once the penalty behaviour is settled: state it exactly) | Unverified claim on a consequence. `EmergencyUnlock` defaults `appliesStreakPenalty = true` (`EmergencyUnlock.swift:85`) and spec §4 lists a "streak penalty option". `LockStatusView` calls `LockEngineManager.emergencyUnlock` directly (`:299`), so this path may apply no penalty, but the two emergency paths disagree and the copy asserts a guarantee. Verify with the lock-engine owner before keeping any promise |
| HIGH | `PaywallCopy.swift` (absent); only `OnboardingCopy.swift:203` "Auto-renews unless canceled. Cancel anytime in Settings." | Live `PaywallView` (`:328-374`) shows a trial reminder, Restore, and the free link. The auto-renew/cancel text exists only for the superseded `Screen13Paywall` (`:97`) | Add to `Copy.paywall`: price-after-trial line, auto-renew and cancel note, Terms and Privacy link labels | Spec §24: "subscription terms in the paywall per App Store rules". The wired paywall has none of it |
| HIGH | `SettingsCopy.swift:101-107` | `proBenefits` = "Unlimited lock sets / Full coach voice library / Cosmetics Shop access"; `proPriceLabel = "$6.99/month"` | Source the price from StoreKit at render time; derive the benefit list from the same source as `Copy.paywall` (spec §21: unlimited goals and lock sets, schedules, adaptive plan, Earn Mode, protein photo AI, recaps, squads, 3 freezes, cosmetics) | Two lists for one subscription that disagree with each other (`PaywallCopy.swift:21-23`) and with spec §21. "Full coach voice library" is not in the Pro tier. Hardcoded price will go wrong the day the price test changes (spec §21) |
| HIGH | `GearOffersCopy.swift:75`, `SettingsCopy.swift:117-119` | "free, engraved, and on us. Confirm your shipping address." / "you've earned a card. Get it shipped." | "Free for subscribers. Confirm your shipping address." (gate the offer on subscription, or state the condition) | Spec §25.3: earned cards ship free to *paid subscribers*. `GearOffersEngine` has no subscription check, so free-tier users see "free" |
| HIGH | `OnboardingCopy.swift:32-36` | Three testimonials attributed to "early user (placeholder)", e.g. "My streak's at 32 days. Longest I've ever gone at anything." | Gate the whole screen behind `#if DEBUG` until real quotes exist, or replace with a product claim ("Locks until you've earned it") | The literal "(placeholder)" is user-visible. Fabricated endorsements are a ship risk (App Review and consumer-protection) even when marked |
| HIGH | `OnboardingCopy.swift:156` | `planBuiltInLabel = "Built for you in 2:14."` (constant) | `planBuiltInLabel(elapsed:)` with the real elapsed time, or delete | A fake number presented as fact; every user "built" their plan in exactly 2:14 |
| HIGH | `OnboardingDripCopy.swift:42,87` | "Users with the widget open ZANO 2x more often." / "Users in a squad complete goals more consistently." | "Widget: not installed. Two taps to add it." / "Squad: none. Join or start one." | Invented statistics. Data voice must be quantitative *about the user*, not fabricated about "users" |
| MEDIUM | `SettingsCopy.swift:99` | "Purchases aren't available in this build yet." | Ship-blocker: remove the string or show nothing | "This build" is developer speak |
| MEDIUM | `ShareCopy.swift:48` | "Turns friction into content. Might as well share it." | Drop; or a share prompt in the user's frame ("Still locked. Share it and keep yourself honest.") | Leaks the growth strategy (spec §5.16 rationale) onto a screen shown at the moment the user is most frustrated; flippant |
| LOW | `ShieldCopy.swift:210,216` | Comment quotes spec as "Show me my goals"; value is "Show my goals" | Pick one; the shorter is fine, fix the comment | Spec and code disagree |

### 5.2 Errors: say how to fix, next to where it broke

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `CommonCopy.swift:45-46`, `PaywallCopy.swift:71` | "Something went wrong" / "Please try again." | Per-cause: "Couldn't load plans. Check your connection and try again." Keep the generic pair only as a last resort that names the action ("Couldn't complete purchase. Try again.") | The exact bad example in the principle. No cause, no fix. `CosmeticsShopView` uses it as a catch-all for three distinct failures |
| HIGH | `OnboardingCopy.swift:55-57`, `LockSetupCopy.swift:54-55` | "Couldn't request permission" + "Something went wrong asking for Screen Time access. Try again in a moment." / "Couldn't request access" + "Something went wrong requesting Screen Time access. Try again." | One shared string: "Couldn't turn on Screen Time access. Check your connection and try again." | Same failure, two different wordings ("permission" vs "access"), neither with a cause |
| MEDIUM | `OnboardingCopy.swift:58-60`, `LockSetupCopy.swift:56-58` | "You can enable it in Settings > Screen Time." vs "Enable it in Settings > Screen Time > ZANO." | One string plus an **Open Settings** button (as `AlwaysAllowedCopy.swift:58` already does) | Two paths for the same fix; neither verified on a device (CLAUDE.md rule 5). A link beats a described path |
| MEDIUM | `SettingsCopy.swift:43` | "Check Settings > Privacy > Location Services." | "Check Location Services in Settings." + Open Settings | iOS 15+ calls it "Privacy & Security" |
| MEDIUM | `FuelCopy.swift:67-70` | "Couldn't find that product." / "That product has no protein data on file." | "Couldn't find that product. Try scanning again or log the protein by hand." / "No protein data for this product. Log it by hand." | No next step; a manual path exists (`logCustomButtonLabel`) |
| MEDIUM | `SunriseAlarmScreenCopy.swift:39-40,118` | "That tag isn't set up yet — hold it near your phone again to register it as your Sunrise Tag." / "That tag isn't registered yet — scan again to add it." | One string. In the *ringing* screen, "register a new tag" during an alarm is the wrong instruction: "This isn't your Sunrise Tag. Find the one you set up." | Two wordings for one event; and the ringing-state copy tells a half-asleep user to add a tag |
| LOW | `ShareCopy.swift:60` | "Couldn't prepare image — tap to try again" | "Couldn't prepare the image. Try again." | "Tap" is a device verb; fine to keep, but the retry control should be a labelled button |

### 5.3 Instructions a half-asleep user reads at 6 AM must not contradict

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `SunriseAlarmCopy.swift:70-71,104,193`, `SunriseAlarmScreenCopy.swift:53,103` | The squad variant is described as *tap the Sunrise Tag* (`ringingNotification`, `ringingActivitySubtitle`, `dismissVariantSummary`) **and** as *hold to confirm you're up* (`squadPromptLabel`, `variantDescription`) | Decide the mechanism (spec §5.10: squad alarm is an opt-in *add-on* on top of a dismiss variant) and say it once: "Tap your Sunrise Tag. A squadmate is pinged if you don't within 10 min." | Two different ways to stop the same alarm; the user cannot tell which is real |
| HIGH | `SunriseAlarmScreenCopy.swift:86-87` | "The only way to stop the alarm is completing the step you pick below — that's the point." | "To stop the alarm, complete the step you pick." | Contradicts the snooze (`snoozeConfirmation`) and the 60-second escape hatch. "Only way" erodes trust in the escape hatch that must never be doubted (spec §24). "Below" also couples the copy to layout |
| MEDIUM | `SunriseAlarmCopy.swift:82-83` | AlarmKit stop button for `.tag` and `.squad` reads "I'm up" | "Open ZANO" or "Scan tag" | A button that says "I'm up" implies self-attestation dismisses the alarm, which is the opposite of the tag mechanic |
| MEDIUM | `SunriseAlarmCopy.swift:134-137`, `SunriseAlarmScreenCopy.swift:60` | `snoozeUnavailable` = "No snoozes left today — a second snooze breaks your morning goal instead of delaying it." | "You've used your snooze. Snoozing again would break your morning goal." | "No snoozes left" and "a second snooze ... breaks" say two different things: is a second snooze possible or not? |
| MEDIUM | `SunriseAlarmCopy.swift:183-184` | "Picking up after bedtime breaks tonight's Sleep goal — gently noted, not a big deal. See you in the morning recap." | "Phone picked up after bedtime. It counts against tonight's Sleep goal. You'll see it in the morning recap." | Says the goal breaks and that it is not a big deal in one sentence; "gently noted" narrates its own tone |
| MEDIUM | `SunriseAlarmCopy.swift:38-39` | "ZANO makes getting up harder to skip, not impossible to sleep through." | "ZANO makes staying in bed harder. It can't guarantee you'll wake up." | Inverted: "harder to skip ... not impossible to sleep through" is a double negative for the one disclaimer that must be unmistakable |
| LOW | `SunriseAlarmCopy.swift:67`, `SunriseAlarmScreenCopy.swift:92` | "Walk it off" | "Walk to turn it off" | Idiom ("walk it off" means shake off pain); does not translate |

### 5.4 One voice, consistent terminology

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `SettingsCopy.swift:84`, `SunriseAlarmScreenCopy.swift:108,116,127`, `SunriseAlarmCopy.swift:65`, `SettingsCopy.swift:86` | The Sunrise Tag action is called "Sunrise Key" in Settings; the same object is "Sunrise Tag", "a tag", "NFC tag"; removal is "Forget Tag" vs "Remove" | "Sunrise Tag" everywhere; one verb for removal ("Remove") | Orphan term "Key" and two verbs for the same action |
| MEDIUM | `SettingsCopy.swift:62`, `SunriseAlarmScreenCopy.swift:109-118,116`, `OnboardingDripCopy.swift:64`, `SettingsCopy.swift:54` | Adding a tag is "Map Tag", "Scan a new tag", "Add a Sunrise Tag", "set up", "registered", "Map your first NFC tag!" | Choose one: "Add a tag" for the user action; "Set up" only for the whole flow | Five verbs for one action |
| MEDIUM | `LockSetupCopy.swift:22,52,58`, `OnboardingCopy.swift:46`, `SunriseAlarmCopy.swift:169`, `AutoFocusSetupInstructions.swift:72` | "shielded", "locked", "blocked", "distracting apps", "Silence blocked apps, not just block them" | "Locked" for the state and verb everywhere the user reads it; reserve "Shield" for the screen the app draws ("Shield Backgrounds" is fine) | Users learn "lock" (Lock Sets, Lock Card, Start Lock). "Shield" is an Apple/engineering term |
| MEDIUM | `SettingsCopy.swift:23`, `OnboardingCopy.swift:196`, `WidgetCopy.swift:55-57`, `TrophyCosmeticsCopy.swift:92` | "unlock" means: earn an app back (core), "unlock these options" (settings gate), "Unlock everything by doing what you already said" (paywall), "1h unlocked" (minutes left), "3 of 8 unlocked" (badges) | Reserve *unlock* for the lock mechanic. Settings: "Finish setup to use these options." Paywall: drop the second use. Badges: "3 of 8 earned" (matches "Earned Mar 3" and `lockedAccessibilityHint = "Not yet earned"`) | The product's core verb is diluted by four other uses; badge progress contradicts its own tile copy |
| MEDIUM | `TrophyCosmeticsCopy.swift:97`, `ProgressCopy.swift:29-30`, `TrophyCosmeticsCopy.swift:89` | "Trophy Case" / "badges" / "achievements" / "milestone" | "Trophy Case" for the place, "badge" for the item; drop "achievements" and "milestone" | Four nouns for one thing |
| MEDIUM | `OnboardingCopy.swift:132-149`, `TodayCopy.swift:30-32`, `SunriseAlarmCopy.swift:112-139` | Goal display names exist in three parallel sets: "Workout at the gym" (plan), "Workout" (rings), "Focus session" vs "Focus", and the alarm goal is "Morning routine" vs "Sunrise Alarm" vs "morning goal" | One `GoalType` display-name resolver in `Copy.common` (short and long form) | The same goal has different names on consecutive screens |
| MEDIUM | `CoachVoice.swift:83-86`, `WidgetCopy.swift:41`, `ShareCopy.swift:45`, `OnboardingCopy.swift:228`, `ProgressCopy.swift:24`, `SettingsCopy.swift:118`, `TrophyCosmeticsCopy.swift:47-51` | Streak appears as "Streak: 14 🔥", "14-day streak on the line.", "14 days in, no rush.", "Streak 14d.", "14🔥", "Streak 14", "Streak: 1 🔥 Day 1 starts now.", "Best: 14", "14-Day Streak" | Neutral surfaces: "14-day streak". 🔥 as a decorative glyph next to it, never instead of it. Voice variants only in `ShieldCopy` | Nine spellings of one number; the emoji-only widget form is unreadable by VoiceOver as a streak |
| MEDIUM | `OnboardingCopy.swift:49-53,124-128`, `LockSetupCopy.swift:35-41` | Onboarding: "2 apps selected" for 1 app + 1 category. Lock Sets: "1 app, 1 category" | Reuse the precise Lock Sets summary in onboarding | Same concept, two implementations; the onboarding one calls categories and websites "apps" |
| MEDIUM | `TrophyCosmeticsCopy.swift:148-178`, `SettingsCopy.swift:103` | Coach "voice packs" named "Captain Intensity", "Zen Minimal", "Data Stream", "Hype Squad", each "a more intense presentation for your coach's lines" | Explain what changes (visual? audio? different lines?) or cut. If it is only a presentation, do not call it a voice | Overlaps the four free voices (Hype/Chill/Data) and the description is vague; user cannot tell what they would buy |
| MEDIUM | `AlwaysAllowedCopy.swift:63,77-79` | "The "Always Allowed" gotcha" / "This isn't a ZANO bug to report — it's Apple's own Screen Time design ..." | "Apps that ignore your lock" / "This is how Screen Time works for every app blocker." | "Gotcha" is developer slang; the note pre-empts a complaint and is defensive |
| MEDIUM | `AlwaysAllowedCopy.swift:33-37` | Title "Some apps can't be locked" over body "If any of these apps are in ... Always Allowed" | "Check Always Allowed before you rely on this lock" | The title states as fact what the body hedges |
| MEDIUM | `GearOffersCopy.swift:51-54` | Headline "Set up your Sunrise Tag" with CTA "Get a Tag Pack" | "Get a Sunrise Tag Pack" (headline matches CTA) | Instruction headline over a purchase button; and "not the fallback" in the body refers to a variant the user has not met |
| MEDIUM | `SettingsCopy.swift:114-116` vs `GearOffersCopy.swift:45` | Settings: "check out the bottle that logs itself" | "check out the Shaker" | `GearOffersCopy.swift:30-37` explicitly reconciled the spec's "bottle" wording to the Shaker SKU; Settings still points at the wrong product |
| LOW | `WidgetCopy.swift:51-58` | `minutesRemaining` returns "1h 20m unlocked" | "1h 20m left" | The function name says remaining; "unlocked" reads as time already spent. The spec-verbatim "2h 10m unlocked" fits the celebration (`CelebrationCopy.swift:57`) but not a remaining-time widget |
| LOW | `PaywallCopy.swift:29-31`, `OnboardingCopy.swift:166` | "Locking: Distractions" | Show the apps or count ("Locking 4 apps") | The default lock set name is a label the user never chose |
| LOW | `SettingsCopy.swift:93-94,107`, `PaywallCopy.swift:35-39` | Plan tiers: "Free" / "Pro" (Settings) vs "Annual / Monthly / Weekly / Lifetime" (paywall) with no "Pro" | State that the plans are all Pro, once | User does not learn what "Pro" is called on the paywall |

### 5.5 Flow vocabulary and verb-first buttons

Onboarding advances with a different catchphrase on nearly every screen.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `OnboardingCopy.swift:26,115,157,237`, `CommonCopy.swift:16` | "I'm ready." / "Let's fix that" / "Let's do this" / "Let's go" (done) / "Continue" | Advance: "Continue". Specific verbs where they name the action: "See my plan" (screen 9 to 10), "Hold to commit", "Allow notifications", "Start free trial", "Start focus session". Finish: "Done" | One flow, five advance vocabularies; the "Let's ..." set also bakes Hype into everyone's buttons before/after they pick a voice |
| LOW | `OnboardingCopy.swift:26` | "I'm ready." | "I'm ready" (spec §7.1 wording; drop the period) | No other button ends in a period. Keep the words: this is the one earned, first-person entry line |
| MEDIUM | `CelebrationCopy.swift:80` | "Nice" | "Done" | Not a verb; a reaction |
| MEDIUM | `SettingsCopy.swift:95-96`, `PaywallCopy.swift:65` | "Manage Subscription" / "Restore Purchases" vs "Restore purchases" | One string in `Copy.common` | Same action, two capitalizations, two files |
| LOW | `SunriseAlarmScreenCopy.swift:64-65` | Button section "Emergency" beside a toggle "I'm not home" | Keep; consistent with `ShieldCopy.Buttons.emergency` | Pass |
| LOW | `LockStatusCopy.swift:43` | "Hold to emergency unlock" | "Hold to unlock in an emergency" | "Emergency unlock" is a noun used as a verb |
| LOW | `AutoFocusSetupInstructions.swift:76` | "Set it up (30 sec)" | "Set up Auto-Focus" | "it" needs its antecedent; time estimate belongs in the body |
| LOW | `PaywallCopy.swift:68` | "Continue with limited free" | Spec §7.13 verbatim, but "limited free" is an adjective stack. Suggest "Continue with Free" and let the plan detail carry the limits | Decide with the spec owner; do not change silently |
| LOW | `GearOffersCopy.swift:66` | "Reorder Protein" | "Reorder protein" | "Protein" is not a product name |
| LOW | `FounderSeriesCopy.swift:30` | "Watch" | "Watch the build log" | Link text should describe its destination |
| LOW | `OnboardingFlowState.swift:177` (outside Copy) | "Lock in on work-school" | "Lock in on work or school" | Spec shorthand shipped as UI text |

### 5.6 Capitalization: pick one policy

Mixed inside the same features, sometimes one screen apart (Settings pushes to Sunrise Alarm setup; the two use different styles).

Current state:

| Style | Examples |
| --- | --- |
| Title Case | `WidgetCopy`: "Start Lock", "Start Focus", "Log Water", "Log Shake", "Log Creatine", "Today's Plan"; `SettingsCopy`: "Add Gym", "Manage Subscription", "Restore Purchases", "Forget Tag", "Coach Voice", "How It Works", "Your Tags"; `LockSetupCopy`: "New Lock Set"; `FuelCopy:52,76`: "Scan Barcode", "Add Kitchen Staple"; `GearOffersCopy:66`: "Reorder Protein" |
| Sentence case | `FuelCopy:51,29,65`: "Scan barcode", "Log custom amount", "Log this"; `PaywallCopy:65`: "Restore purchases"; `OnboardingCopy`: "Choose apps", "Hold to commit", "Allow notifications"; `TodayCopy`: "Start 25-min focus session"; `SunriseAlarmScreenCopy`: "Wake time", "Alarm strength", "Wind-down reminder"; `ShieldCopy:216`: "Show my goals" |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | All of the above | Two policies in the same product; same feature spelled two ways in the same file (`FuelCopy.swift:51` "Scan barcode" vs `:52` "Scan Barcode"; `SettingsCopy:96` vs `PaywallCopy:65`) | **Sentence case** for buttons, labels, row titles, section headers, alert titles. Title Case only for proper feature names: Time Bank, Trophy Case, Lock Card, Sunrise Tag, Tag Pack, Bedtime Gate, Sunrise Alarm, Earn Mode, Ghost Mode | Highest-visibility flows (Onboarding, Today, Paywall, Shield) are already sentence case, so this is the cheaper flip and the one the skill recommends. iOS system apps use Title Case for nav titles and buttons; if the owner prefers that, flip Fuel/Onboarding/Today instead. Decide once |
| LOW | `OnboardingCopy.swift:101,119,170,184,215,207` | Eyebrows and badge stored in caps: "THE MATH", "YOUR PLAN", "LAST STEP", "STAY IN THE LOOP", "YOUR FIRST WIN", "BEST VALUE" (also duplicated at `PaywallCopy.swift:35`) | Store sentence case; apply `.textCase(.uppercase)` in the view | Casing is rendering (`better-typography`); stored caps localize badly and VoiceOver may spell them out. Recommend the view layer own it |

### 5.7 Plain words, fragments and pluralization

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `OnboardingCopy.swift:160-162` | `"We'll watch out for you on \(patternLabel.lowercased()) — that's usually when things slip."` with labels "Weekends", "Evenings", "When stressed", "After a few good days", "Travel" (`OnboardingFlowState.swift:195-201`) | Give each answer its own full sentence: "We'll watch weekends, when things usually slip." / "We'll watch for stressful days." / "We'll watch the days after a few good ones." / "We'll watch when you travel." | 3 of the 5 answers produce broken grammar ("on when stressed", "on after a few good days", "on travel") on the Plan Reveal screen, the peak of the flow. Sentence assembled around a variable |
| MEDIUM | `LockStatusCopy.swift:29-30` | `lockedSincePrefix = "Locked since"`, `nextLockPrefix = "Next lock:"` | `lockedSince(time:)`, `nextLock(time:)`; one form, no colon variance (`WidgetCopy.nextLock` has none) | Prefix-plus-value fragments are the pattern the skill bans; colon inconsistency |
| MEDIUM | `CoachVoice.swift:85`, `PaywallCopy.swift:51,75` | "\(streak) days in" / "\(trialDays) days free" / "\(daysBefore) days before" | Pluralize ("1 day") or use plural-aware helpers | "1 days" at value 1. Hardcoded "7-day" (`OnboardingCopy.swift:199`) vs param in `PaywallCopy.swift:60` will drift |
| MEDIUM | `AutoFocusSetupInstructions.swift:67-69` | "...every time a lock starts — so blocked apps stop buzzing you, not just blocking you." | "Want your phone quiet too? Set up Auto-Focus once and ZANO turns on a Focus mode whenever a lock starts, so blocked apps stop sending notifications." | Meaning inverted (apps do not "block" the user). Title `:72` "Silence blocked apps, not just block them" has the same inversion. Comment claims one line; it is two sentences |
| MEDIUM | `OnboardingCopy.swift:80-83` | Title "How many times do you work out?" | "How many workouts a week?" or "How often do you work out?" with "per week" in the subtitle | Title omits the period; the value format `3x/week` (`:85`) only appears after the choice |
| LOW | `OnboardingCopy.swift:64` | "How much time do you spend on your phone daily?" | "How long are you on your phone each day?" | Wordy |
| LOW | `OnboardingCopy.swift:227-229` | "Streak: 1 🔥 Day 1 starts now." | "Day 1 is on the board." | Says streak 1 then says Day 1 "starts now"; redundant and self-contradictory |
| LOW | `OnboardingCopy.swift:209-211` | "Billed per year" | "Billed yearly" | Awkward; string-typed `period == "once"` check is brittle |
| LOW | `TrophyCosmeticsCopy.swift:185-187,195-197` | "Buy · 250" / "Keep earning goals to close the gap." | "Buy for 250 coins" / "Complete goals to earn more coins." | Bare price beside real-money Pro copy reads as currency; "earn goals" wrong verb |
| LOW | `TodayCopy.swift:39` | key `goToGymTitle` renders "I'm at the gym" | Rename the key to match | Key/value mismatch invites a wrong edit |
| LOW | Idioms | "on us" (`GearOffersCopy:75`), "go-to" (`FuelCopy:74`), "no strings attached" (`OnboardingCopy:202`), "in public" (`FounderSeriesCopy:24`), "Neck and neck" (`GhostMode.swift:248`) | Plain equivalents | Translation risk; "no strings attached" also sits next to a paywall, where reassurance phrases read as dark-pattern-adjacent |
| LOW | `AutoFocusSetupInstructions.swift:81-85,160-173` | 60-80-word single sentences in explainer and limits | Split into 2 or 3 sentences; ~1 idea each | Dense for a how-to a user follows while switching between apps. "See Limits below", "see Emergency Unlock" are positional / unlinked references |
| LOW | `AutoFocusSetupInstructions.swift:90-133`, `SunriseAlarmScreenCopy` | Straight quotes around UI names (`"Set Focus"`) | Typographic quotes or bold | Cross-reference `better-typography` |

### 5.8 Empty states, links, placeholders, settings

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `FuelCopy.swift:26-27` | "No fuel goals yet" / "Add a protein or water goal to start logging here." | Add a CTA key ("Add a fuel goal") and confirm where it leads | Orients but has no next action in Copy; verify against `FuelView` |
| MEDIUM | `SunriseAlarmScreenCopy.swift:143` | "Join a squad to use this option." | Add a "Find a squad" action label | Dead-end with no route |
| MEDIUM | `TodayCopy.swift:33` | "Not set" | "Add a workout goal" | Empty ring with no forward path (spec §8.2) |
| LOW | `SettingsCopy.swift:23` | "Finish setting up your account to unlock these options." | "Finish setup to use these options." | Vague plus overloaded "unlock" (see §5.4) |
| Pass | Placeholders | `LockSetupCopy.swift:48` "e.g. Social, Games, All"; `SettingsCopy.swift:39,69` "e.g. Downtown Fitness", "e.g. Kitchen shaker" | None | Examples, not labels; every field also has a visible label |
| Pass | Settings toggles | `SunriseAlarmScreenCopy.swift:171` "Remind me 10 minutes before"; "I'm not home" | None | Describe the ON state |
| Pass | Second person | Whole layer uses "you"; errors avoid "we" | None | Meets the direct-address rule |

---

## 6. Duplication ledger (consolidation map for the rewrite)

These are the places the "14 agents" wrote the same thing independently. Each one is a drift risk.

| Concept | Where it appears | Consolidate into |
| --- | --- | --- |
| "Locked · N goals left" | `TodayCopy.swift:25-28`, `LockStatusCopy.swift:23-24`, `WidgetCopy.swift:37-39,68-71`, `ShareCopy.swift:43-46` (four implementations, identical output) | One `Copy.common.goalsLeft(n)` and `lockStatusLine(...)` |
| "Nh Nm unlocked" | `WidgetCopy.swift:51-58`, `CelebrationCopy.swift:57-64` (explicit reimplementation, `:51-56` justifies it) | One `Copy.common.duration(minutes:)` |
| Save / Delete / Cancel / OK | `CommonCopy`, `LockSetupCopy:49,24`, `SunriseAlarmScreenCopy:77,164`, `SettingsCopy` | `Copy.common` only |
| "Couldn't save" family | `LockSetupCopy:43`, `SettingsCopy:22`, `SunriseAlarmScreenCopy:78,165`, `FuelCopy:79` | `Copy.common.saveFailed` (+ optional subject) |
| "Try again" | `FuelCopy:66`, `PaywallCopy:70` | `Copy.common.tryAgain` |
| Screen Time permission error and denied | `OnboardingCopy:55-60`, `LockSetupCopy:54-58` | One shared pair plus an Open Settings action |
| Paywall (live vs superseded) | `OnboardingCopy:195-211` vs `PaywallCopy.swift` | Delete the `paywall*` block in `Copy.onboarding` once `Screen13Paywall` is removed; move the auto-renew text to `Copy.paywall` first (§5.1) |
| Pro benefits and price | `SettingsCopy:101-107` vs `PaywallCopy:21-23` | One source |
| Sunrise dismiss instruction | `SunriseAlarmCopy:65,101,190`, `SunriseAlarmScreenCopy:36,100` | One phrase per variant, referenced everywhere |
| Sunrise tier explanation | `SunriseAlarmCopy:43-52`, `SunriseAlarmScreenCopy:150-154` | One; header (`SunriseAlarmScreenCopy.swift:18-22`) claims safety strings live in one place, but tiers and tag-not-registered do not |
| Tag-not-registered | `SunriseAlarmScreenCopy:39,118` | One |
| Shaker offer | `SettingsCopy:114-116` vs `GearOffersCopy:42-47` | `GearOffersCopy` only (already reconciled) |
| Earned card offer | `SettingsCopy:117-119` vs `GearOffersCopy:71-77` | `GearOffersCopy` only |
| "Earned." | `OnboardingCopy:225` vs `CelebrationCopy:34` (`:28-33` defends the duplicate) | One constant |
| "BEST VALUE" | `OnboardingCopy:207` vs `PaywallCopy:35` | `Copy.paywall` |
| Streak formatting | nine forms (see §5.4) | One `Copy.common.streak(days:)` |
| Dismiss/close labels | "Not now" (`ShareCopy:49`, `OnboardingCopy:189`), "Close" (`ShareCopy:75`), "Dismiss" x3 (`AlwaysAllowedCopy:59`, `FounderSeriesCopy:31`, `GearOffersCopy:81`) | `Copy.common.notNow`, `.close`, `.dismiss` |

`Copy.common` currently holds five keys. Target set: `continue`, `done`, `cancel`, `ok`, `save`, `delete`, `remove`, `notNow`, `close`, `dismiss`, `tryAgain`, `openSettings`, `saveFailed`, `goalsLeft`, `streak`, `duration`, goal display names, `restorePurchases`.

---

## 7. Copy that lives outside `Copy/`, and copy that does not exist yet

**Outside `Copy/` (violates CLAUDE.md "no hardcoded user-facing strings")**

| Location | What | Note |
| --- | --- | --- |
| `Core/Sources/Core/Retention/GhostMode.swift:234-255` | Ghost Mode headlines: "Ghost You had already completed 2 goals by Tuesday.", "Neck and neck with Ghost You — ..." | Best-voiced copy in the codebase (specific, self-competitive, no shame), and it is not in Copy. Move as-is into `Copy.ghost`; add per-voice variants only if wanted |
| `Core/Sources/Core/Intents/StartLockIntent.swift:32-37` | "Full Lock" / "Earn Mode" subtitles (incl. the spec leak in §5.1) | Shown in Shortcuts and Siri |
| `Core/Sources/Core/Verification/NFCTagSetupInstructions.swift` | Tag setup how-to | Deliberate per its header; make sure it follows the same capitalization and terminology decisions |
| `App/ZANO/Features/Onboarding/OnboardingFlowState.swift:164-202` | Onboarding answer labels (`MainGoal`, `FallOffPattern`) | Justified in-code ("Core cannot reference an App type"), but the labels could be `Copy.onboarding.mainGoalLabel(rawValue:)`; they are also the source of the §5.7 grammar break |
| `Core/Sources/Core/UI/PreviewCatalog.swift` | Sample headlines | Preview data only; ignore |

**Missing Copy areas** that spec-defined features need:

| Feature | Spec | Note |
| --- | --- | --- |
| Emergency unlock hold flow (the `zano://emergency` screen) | §5.1, §24 | `EmergencyUnlock.swift:14` says the copy lives in Copy; there is no `Copy.emergency`. Must say what happens to the streak *exactly* (see §5.1). Must be calm |
| Pause for health reasons | §24 "Include a 'pause for health reasons' option and disordered-eating-safe copy" | Zero matches for "pause", "health reasons" or any related string across the repo. Product-safety item (CLAUDE.md), not polish |
| Squad and duels | §5.7 | Only one drip line mentions squads; no squad screen copy, no nudge text, no taunt copy |
| Plan B, Comeback mode, Travel mode | §5.5, §5.18 | Rule 3 depends on this copy ("no guilt copy") |
| Nudges and pushes beyond the drip | §8.7, §9.3 | No nudge copy files |
| Weekly report insight line | §5.14 | Screen chrome exists; the LLM-written line has no Copy contract or fallback |
| Earn Mode and Time Bank explanation | §5.2 | First seen on the shield as "You've already banked 45 min"; no onboarding or settings explainer |
| Fresh-start / challenge cards | §8.6, §5.9 | Monday, the 1st, birthday |

---

## 8. What is already good (keep and use as the bar)

| Where | String | Why it works |
| --- | --- | --- |
| `SettingsCopy.swift:28` | "Switch anytime — this changes how your coach talks to you, not what it asks of you." | Clear, honest, sets the right expectation for the voice picker |
| `OnboardingCopy.swift:172` | "Hold the button for 2 seconds. This is you, deciding." | Identity-forward, specific, short |
| `CelebrationCopy.swift:34` | "Earned." | A brand anchor; keep it fixed across voices |
| `ShieldCopy.swift:307` | "ONE goal from everything unlocking." | The Hype voice done right: one caps word, one image |
| `SunriseAlarmCopy.swift:178` | "Your phone's a clock now. See you at sunrise." | Warm, on-brand, lands the bedtime lock |
| `SunriseAlarmScreenCopy.swift:41` | "That's a different ZANO tag — find your Sunrise Tag instead." | Names the situation and the fix |
| `GhostMode.swift:246` | "Ghost You hadn't gotten started by Tuesday either — you're even so far." | Specific, self-competitive, never shaming |
| `OnboardingCopy.swift:232` | "You can always try again — your plan is already saved." | Calm, forward, reassures with a fact |
| `LockSetupCopy.swift:21-22`, `SettingsCopy.swift:34-35` | "No lock sets yet" + "Create a lock set to choose which apps get shielded." | Empty states that orient and point forward (fix the word "shielded") |
| `AlwaysAllowedCopy.swift:37-46` | "Worth a quick check." | Actionable, honest about uncertainty |
| `WidgetCopy.swift:89-90` | "Add a lock set in ZANO before locking from Control Center." | Names the problem and where to fix it |
| `SunriseAlarmCopy.swift:33-34` | "This is a real alarm that makes you get up — not a guaranteed wake-up." | Spec §5.10's no-guarantee rule stated plainly (rewrite only the shorter reminder, §5.3) |

---

## 9. Decisions the rewrite phase should get from the spec owner (do not change silently)

1. **Capitalization policy** (sentence vs Title Case for UI labels). Recommendation: sentence case.
2. **Spec-verbatim strings with wording problems**: "Continue with limited free", "I'm ready.", "Lock in on work-school", "Show me my goals" vs implemented "Show my goals", the spec §5.1 "unzanog" typo in `docs/spec.md` (do not copy that into the app).
3. **Emergency unlock and streak**: does emergency unlock cost a streak by default? The copy (`LockStatusCopy.swift:44`, `EmergencyUnlock.swift:14`) currently asserts three different things.
4. **Voice packs** (`Copy.cosmetics`): what do they actually change?
5. **Should the shield and widgets receive extra state** (§3.3) so Tough Love and Data can quote real numbers? This is the single change that makes the voice picker's promise true.
6. **Earned-card gating**: show only to subscribers, or state the condition in the copy.

## Verdict

**Block.** HIGH findings remain: §5.1 (internal citations, unverified emergency-unlock claim, missing paywall terms, price and benefits mismatch, free-card claim, fabricated testimonials, fake build time, invented Data statistics), §5.2 (generic errors), §5.3 (contradictory alarm instructions), and §4 (after-miss copy hides the recovery step). Everything in §5.4 to §5.8 is MEDIUM or LOW work that can proceed in parallel.
