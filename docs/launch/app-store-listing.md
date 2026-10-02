# ZANO — App Store listing (v1.0)

Status: **draft for the first submission, 2026-10-02.** Supersedes `docs/marketing/app-store-listing.md`,
which predates the hard-paywall decision (spec §21, 2026-09-23) and still describes a Free tier and
"ZANO Pro". Don't paste from that file.

Sources: `docs/spec.md` §1 (positioning), §5 (features), §7 (onboarding), §21 (monetization),
§22 (launch), §24 (safety, claims, age); `Core/Sources/Core/Copy/*` (brand voice: short, second
person, verb first, no guilt, "Earn it." / "Tap in."); `App/ZANO/ScreenshotGallery.swift` (screenshot
names). Character counts below were computed with a script (Unicode characters, the way App Store
Connect counts them), not by eye.

Placeholders: `[COMPANY LEGAL NAME]`, `[SUPPORT EMAIL]`, `[WEBSITE]`, `[PRICE_MONTHLY]`,
`[PRICE_YEARLY]`, `[PRICE_LIFETIME]`. Spec §21's test prices are $6.99/mo, $39.99/yr, $59.99
lifetime (test only). Prices are never written into the description or screenshots, so a price test
doesn't force a metadata update.

**Listing rule:** only advertise what works in the build under review. As of today these are
visible in the app but **not live** (they say "goes live soon" / "coming soon" in-app), so they are
**not** in the name, subtitle, description, screenshots or preview: Squads/duels/nudges, gym
leaderboards, referral redemption, AI meal-photo protein estimates. Add them back the release they
go live.

---

## 1. App name (limit 30)

| | Name | Chars |
|---|---|---|
| **Recommended** | `ZANO: Earn Your Screen Time` | 27/30 |
| Alt 1 | `ZANO: Screen Time Blocker` | 25/30 |
| Alt 2 | `ZANO: App Blocker for Gym` | 25/30 |
| Alt 3 | `ZANO – Lock In, Earn It` | 23/30 |

Why: the name is the heaviest-weighted search field. "Screen time" is the category's head term and
"earn" is the mechanic nobody else in the category owns (Opal/one sec/Brick sell restriction; ZANO
sells earning it back). Alt 1 trades the hook for a stronger exact-match on "screen time blocker";
use it if search traffic after launch says ranking matters more than conversion. Alt 3 is pure brand
with almost no search value; only for a later, brand-led phase.

The `ZANO` brand still needs the attorney clearance search noted at the top of spec.md before the
listing goes live.

## 2. Subtitle (limit 30)

| | Subtitle | Chars |
|---|---|---|
| **Recommended** | `App Blocker for Gym & Focus` | 27/30 |
| Alt 1 | `Lock apps until you work out` | 28/30 |
| Alt 2 | `Gym first. Then your apps.` | 26/30 |
| Alt 3 | `Focus, lift, then scroll` | 24/30 |

Why: adds "app blocker" (the term people literally type), "gym" and "focus" (the two goals a
reviewer can verify in minutes) without repeating any word already in the name. Alt 1 is the
spec §1 positioning line in 28 characters and converts better on the product page, but it spends
characters on low-value words ("until", "you"). Pair it with Alt 1 of the name if you go that way.

## 3. Promotional text (limit 170, editable without a new build)

**Recommended (evergreen, launch):**

```
Apps stay locked until you hit the gym, finish a focus session or hit your protein. Do the thing, earn them back. Emergency unlock always works.
```
144/170

Alternates:

```
Gym, focus, protein, done? Then your apps open. ZANO keeps distracting apps locked until you earn them back. Emergency unlock always works.
```
139/170

```
New: Earn Mode. Every goal you hit banks minutes you can spend on your locked apps, a few at a time. The lock comes back on its own.
```
132/170 (use for a feature push in week 2–3)

No trial wording here on purpose: the 7-day trial is only on the yearly plan, and promotional text
that says "free for 7 days" without the plan qualifier invites a 3.1.2 metadata complaint.

## 4. Description (limit 4000)

**2,889/4,000.** The first three lines (what shows before "more") are the hook, the mechanic, and
the safety promise. Section headers are ALL CAPS because the App Store renders plain text only.

```
The app that won't let you open your feed until you hit the gym.

ZANO locks the apps that eat your day until you do what you said you'd do: train, focus, hit your protein. Do the goal, and they open back up. Skip it, and they stay locked.

No willpower required. No calorie counting. And never a trap: calls always work, and emergency unlock is always one long press away.

HOW IT WORKS
1. Pick the apps that pull you in. Apple's own Screen Time picker, so ZANO never sees what's in them.
2. Set your goals: a gym session, a focus block, steps, protein, water, bedtime.
3. Lock in with a tap, a schedule, or a ZANO tag.
4. Do the thing. ZANO verifies it for you.
5. Unlocked. Streak +1.

VERIFIED, NOT HONOR SYSTEM
• Gym: save your gym once. Show up, stay, and your workout verifies on its own using your location and Apple Health. No logging.
• Focus: a real timer with your apps shielded, right on your Lock Screen and Dynamic Island.
• Steps and sleep: read straight from Apple Health.
• Protein and water: one tap on a widget, a ZANO NFC tag, or a barcode scan.
Basement gym or no signal? A manual check-in is always there.

EARN MODE AND YOUR TIME BANK
Not ready for all-or-nothing? Every goal you hit banks minutes. Spend them on your locked apps a few at a time, and the lock comes back on its own.

THE SHIELD MOMENT
Reach for a locked app and you'll see exactly what's standing between you and it, and how close you are. That's the moment you put the phone down and go.

STREAKS THAT FORGIVE ONE BAD DAY
Streak freezes, Never Miss Twice and Plan B days keep one rough day from wiping out a good month. Your plan starts easy and grows as you show up.

WORKS WITHOUT OPENING THE APP
• Home Screen, Lock Screen and StandBy widgets
• Control Center and Action Button controls
• Siri and Shortcuts: "Lock in with ZANO"
• ZANO NFC tags: tap to log a shake, start a lock or check in
• Sunrise Alarm: turn it off by doing your morning goal

PICK YOUR COACH
Hype, Tough Love, Chill or Data. Same goals, your kind of push.

PRIVATE BY DESIGN
• Your Screen Time data never leaves your iPhone. Apple's frameworks keep it on device.
• Health and location data are used on your iPhone to verify goals. We never sell them.
• No account needed. Locks and goals work offline.

ADDITIVE GOALS ONLY
ZANO only asks you to do more of the good stuff. No calorie limits, no weight targets, no fasting.

SUBSCRIPTION
ZANO is a subscription app with a free trial. The yearly plan includes a 7-day free trial; we'll remind you before it ends. Payment is charged to your Apple ID when you confirm (or when the trial ends) and renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple ID settings.

Terms of Use: [WEBSITE]/terms
Privacy Policy: [WEBSITE]/privacy

Your phone, working for your goals instead of against them. Earn it.
```

Notes:
- **No third-party app names.** The earlier draft named TikTok/Instagram/YouTube. Spec §1's
  positioning line does too, but in metadata that is a trademark-use risk (guideline 5.2.1) and
  buys nothing in search (Apple doesn't index the description). "Your feed" carries the same
  meaning. Keep the brand names for TikTok content, where they belong.
- **No outcome claims** (spec §24, guideline 1.4.1): no "addiction", "detox", "ADHD", "lose
  weight", "better sleep". The copy says what the app does, not what it does to you.
- **Every feature named is in the build** (checked against `docs/PROGRESS.md` row 5b and the Copy
  files). Device verification of each is still open, so re-read this list against the build you
  actually submit.
- "Terms of Use" can be Apple's standard EULA (what `PaywallView` links today) or your own; either
  way the link must work and also go in App Store Connect's License Agreement / description.
- `[WEBSITE]`: the code already hard-codes `https://zano.app/privacy` (`PaywallView.swift`) and
  `https://zano.app/terms` (`SettingsCopy.swift`). Use those exact URLs here once the domain is
  confirmed and the pages are live, or change the code to match.

## 5. Keywords (limit 100)

**Recommended:**

```
doomscrolling,habit,workout,streak,discipline,lock,limit,social,media,self,control,protein,phone,nfc
```
100/100

**Alternate** (drops `phone` and `nfc` for `study`, the student "lock in on work/school" audience
from onboarding Q1; use if search data after launch shows NFC isn't a search driver):

```
doomscrolling,habit,workout,streak,discipline,lock,limit,social,media,self,control,protein,study
```
96/100. `detox` (also 5 letters) can replace `study`; it is fine as a hidden keyword, it just must
never appear as a claim in visible copy (§24).

Rules applied: no spaces after commas; singular only (Apple matches plurals); none of the words
already indexed from the name/subtitle (`zano`, `earn`, `your`, `screen`, `time`, `app`, `blocker`,
`gym`, `focus`); no competitor names (Opal, one sec, Brick, Jomo, ScreenZen) or platform trademarks
(TikTok, Instagram); no category name ("health", "fitness", "productivity" are already matched by
the categories).

Why these words (Apple combines words across name, subtitle and keywords, so single words build
phrases):

| Keyword | Phrases it unlocks with the name/subtitle | Why |
|---|---|---|
| doomscrolling | "doomscrolling blocker", "stop doomscrolling" | Exact Gen Z vocabulary; onboarding Q1 option "Stop doomscrolling". Low competition. |
| habit | "habit app", "habit tracker" (with nothing else) | Highest-volume adjacent category; ZANO is a habit app with teeth. |
| workout | "workout app blocker", "workout motivation" | Gym is the core goal; "gym" is already in the subtitle. |
| streak | "streak app", "gym streak" | Streaks are a top retention feature and a common search. |
| discipline | "discipline app", "self discipline" (with self) | Spec §1/§24 language; "locked in" culture. |
| lock | "app lock", "screen time lock", "lock apps" | Core verb; pairs with name + subtitle. |
| limit | "screen time limit", "app limit" | Very common phrasing for the Screen Time job. |
| social, media | "social media blocker", "social media limit" | The #1 thing people want blocked; two separate words cover both orders. |
| self, control | "self control", "self control app" | Classic blocker search; two words cover "self discipline" too. |
| protein | "protein tracker", "protein goal" | Second-biggest goal type; very little competition from blocker apps. |
| phone | "phone blocker", "phone lock", "phone limit" | Short and pairs with almost everything above. |
| nfc | "nfc lock", "nfc tag app" | Lock Card/tags are a differentiator (spec §25); small but high-intent. |

Words considered and dropped: `focus` (in subtitle), `study` (good, out of room — first in line),
`motivation` (10 chars, broad and expensive), `fitness`/`health` (category covers them),
`addiction` (reads as a health claim, §24), `dopamine` (claim-adjacent), competitor names (5.2.1).

**Unverified:** no live search-volume data was available here (no App Store Connect / ASO tool
access). These are reasoned picks. After 2–4 weeks, check App Store Connect → App Analytics →
Sources → App Store Search and swap the weakest two.

## 6. Category

- **Primary: Productivity.** The thing the app *does* is block apps (Screen Time). The category
  peers are Opal, one sec, Freedom, ScreenZen, all in Productivity or Health & Fitness, and
  Productivity charts are less crowded than Health & Fitness for a new app. It also keeps the
  first impression on "focus tool", not "health app", which lowers 1.4.1 scrutiny.
- **Secondary: Health & Fitness.** Gym verification, steps, protein.

Flip them if post-launch data shows the gym audience converting best. Primary category drives
chart placement, so decide on purpose, not by default.

## 7. Age rating

Spec §24 says "rate 17+ initially (avoid COPPA/teen data complexity). No under-13 users." Apple
replaced the 4+/9+/12+/17+ scale in 2025 with **4+ / 9+ / 13+ / 16+ / 18+** and a longer
questionnaire. **Verify the exact questions in App Store Connect; the answers below are written
against the questionnaire as last known, not checked live.**

Honest answers for ZANO 1.0:

| Question area | Answer | Why |
|---|---|---|
| Violence (cartoon, realistic, graphic) | None | — |
| Sexual content / nudity | None | — |
| Profanity / crude humor | None | Tough Love voice is blunt, never profane (`CoachVoice.swift`). |
| Horror / fear themes | None | — |
| Alcohol, tobacco, drugs | None | — |
| Mature / suggestive themes | None | — |
| Simulated gambling / contests / loot boxes | None | Variable rewards are cosmetic badges, no purchase, no chance-for-money. |
| Medical or treatment information | None | Goal verification only; no medical advice. |
| Health or wellness topics | **Yes** (if asked) | Fitness, protein, sleep goals. |
| Unrestricted web access | No | Only links to Terms/Privacy/Maps. |
| User-generated content | **No for 1.0** | Squads aren't live. Answer **Yes** the release squads ship (names, nudges). |
| Messaging / chat | No | — |
| Advertising | No | — |
| Parental controls | No | ZANO uses Family Controls in *individual* mode, not parental controls. |
| Age assurance | No | — |

**Recommendation: set the rating to 16+** (or 18+ if counsel prefers): the questionnaire will
likely compute 4+ or 9+, but spec §24 wants a higher floor, and App Store Connect lets you choose a
higher rating than the computed one (verify this option still exists). **Decision needed from the
founder:** spec §1's target audience is **17–27**, and Apple mapped the old 17+ to the new 18+. 18+
would exclude 17-year-olds from the listing; 16+ keeps the whole target audience and still keeps
under-13s and most COPPA complexity out. This conflicts with spec §24's literal "17+", so per
CLAUDE.md this is flagged, not decided here.

## 8. What's New (v1.0)

```
Welcome to ZANO.

Lock the apps that eat your day. Earn them back by training, focusing or hitting your protein.

• Gym visits verify on their own with your location and Apple Health
• Focus sessions with a Live Activity
• Earn Mode: bank minutes, spend them later
• Widgets, Controls, Siri and NFC tags
• Streak freezes so one bad day doesn't erase a good month

Emergency unlock always works. This is day one. Tell us what to build next: [SUPPORT EMAIL]
```
455/4,000 (with the placeholder; recount once the email is filled in)

## 9. Screenshot plan

Required set: 6.9" iPhone (1320 × 2868 portrait); App Store Connect scales it down for smaller
iPhones. iPhone only for v1 (`TARGETED_DEVICE_FAMILY: "1"`), so no iPad set. **Verify the
currently required size in App Store Connect before exporting.**

Format: dark background (brand), caption on top in the brand font, device frame below. Headline
≤ ~6 words, benefit first, sentence case. Screens come from the CI tour (`-ZANOScreen <name>`,
`App/ZANO/ScreenshotGallery.swift`) except where a real device is required.

| # | Headline | Subcaption | Screen | Notes |
|---|---|---|---|---|
| 1 | **Earn your apps back** | Locked until your goal is done. | **Device capture of the real shield** (ZANOShieldConfig). CI fallback: `lockedout` | The shield can't render in the Simulator (spec §27). This is the money shot; capture it on a device. Replace the demo app name "TikTok" in `lockedout` with a generic "Social" lock set (trademark). |
| 2 | **Do the goal. Get the scroll.** | Gym, focus, steps, protein, water. | `tab-today` | Today with rings partly filled (spec §8 rule 2: never empty). |
| 3 | **Hit the gym. Apps unlock.** | Verified by location + Apple Health. | `gym-checkin` | Show the dwell ring mid-way ("Verifies in 12 min"). |
| 4 | **Unlocked. You earned it.** | The best notification you'll get all day. | `celebration` | Demo: "Gym session · 42 min at the gym". |
| 5 | **Your first win in 2 minutes** | Start a focus lock right now. | `onboarding-7` | The first-win screen; tells the browser it pays off immediately. |
| 6 | **Bank minutes. Spend them later.** | Earn Mode, for days that aren't all-or-nothing. | `earn-settings` (or `tab-lock` with the Time Bank borrow card) | Pick whichever reads better at thumbnail size. |
| 7 | **Tap a tag. Logged.** | NFC tags for shakes, water and locks. | `nfc-tags` | Optional: composite with a photo of a tag on a shaker. Physical tags are sold separately; don't imply they ship with the app. |
| 8 | **See the time you took back** | Streaks, milestones and your monthly story. | `monthly-story` (or `milestone`, 30-day streak) | Shareable output; doubles as social proof without fake quotes. |

Not used, on purpose: `tab-squad` (squads aren't live: a "goes live soon" screen is a 2.1/2.3
risk); `paywall` (Apple discourages pricing screens in screenshots); `tab-progress` is a fine
swap-in for #8.

Demo-data check before export: the CI seed (`DemoData`) uses "Instagram"/"TikTok" app names in the
Screen Time summary on `tab-today`. Hide or rename those before exporting store screenshots.

### App Preview video (15–30 s)

Apple requires previews to be **captured footage of the app** (screen recording), no hands, no
device bezels in the recording itself, no live-action. Record on a device, because the shield and
Live Activity don't exist in the Simulator.

| Time | Shot (screen recording) | On-screen text |
|---|---|---|
| 0–3 s | Home Screen, thumb-less tap on a locked app → ZANO shield appears | "Locked." |
| 3–6 s | Shield close-up: "Gym session · 6 min away" / goals left | "Until you earn it." |
| 6–10 s | Today tab, rings 2 of 3; tap into Gym check-in, ring filling | "Hit the gym." |
| 10–13 s | "Workout verified" → unlock celebration | "Verified. Unlocked." |
| 13–17 s | Lock Screen: focus Live Activity counting down; widget tap logs 25 g protein | "Focus. Protein. Steps." |
| 17–21 s | Lock tab: Time Bank, borrow 10 min | "Bank minutes for later." |
| 21–24 s | Lock tab: press-and-hold emergency unlock begins (cut after 2 s) | "Always a way out." |
| 24–27 s | Streak milestone / monthly story card | "Earn it." + ZANO wordmark |

Poster frame: the shield (0–3 s). Keep text inside the safe area; first 3 seconds autoplay muted,
so the story must read without sound.

## 10. In-app purchases

Subscription group: **ZANO** (one group, so users can switch plans and Apple prorates). Product IDs
below are suggestions; they must match the RevenueCat offering (`RevenueCatManager`), which has no
product IDs in code yet. Display name limit 30, description limit 45 (verify in App Store Connect).

| Product | Suggested ID | Type | Display name | Description | Price | Trial |
|---|---|---|---|---|---|---|
| Yearly (highlighted) | `com.zano.app.yearly` | Auto-renewable, 1 year | `ZANO Yearly` (11/30) | `Everything in ZANO, billed yearly` (33/45) | `[PRICE_YEARLY]` | **7-day free trial** (introductory offer, new subscribers only) |
| Monthly | `com.zano.app.monthly` | Auto-renewable, 1 month | `ZANO Monthly` (12/30) | `Everything in ZANO, billed monthly` (34/45) | `[PRICE_MONTHLY]` | None |
| Lifetime (optional, test only per §21) | `com.zano.app.lifetime` | Non-consumable | `ZANO Lifetime` (13/30) | `Everything in ZANO, one payment` (31/45) | `[PRICE_LIFETIME]` | n/a |

Why no "Pro": there is no free tier (§21), so a "Pro" name implies a lesser free version that
doesn't exist. Every plan unlocks the same app.

Subscription group display name: `ZANO` (4). Group localization's "App Name Display" option:
use the app name.

**Trial framing** (matches `PaywallView`/`PaywallCopy` and §21's copy rules):
- Headline: "Start your 7-day free trial." only while the yearly plan is selected; monthly shows
  "Subscribe to continue." (already how `PaywallView.selectedTrialDays` works).
- The dated timeline: Today (full access) → Reminder in 5 days → Billing starts in 7 days, with
  "You'll be charged on [date] unless you cancel before then."
- "No payment due now" above the button; the full terms paragraph directly under it; Terms ·
  Privacy · Restore purchases links on the same screen.
- Never: fake countdowns, "offer ends" timers, post-close discount screens, guilt copy (§21).
- The pre-expiry reminder is promised in copy, so it has to actually fire (local notification two
  days before the trial ends). If notifications are off, the copy already says "if notifications are
  on". Verify on device before submission.

Review screenshot for each IAP (App Store Connect requires one): the `paywall` CI screen with the
corresponding plan selected.
