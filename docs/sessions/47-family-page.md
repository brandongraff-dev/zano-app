# Session 47 — The Family page ("the family of characters")

- **Branch:** worktree branch, based on `origin/claude/dazzling-hypatia-ed6q5d` at `6dc5dd3`, on top of session 46
- **Spec sections:** §5.31 (Household; the Family page), §5.23 (Family Link: teen consent wording kept), §5.17a / §15 (buddies, glass system), §21 (Family Sharing, honest plan wording), §24 (privacy, never non-working controls)
- **Status:** Scaffolded — Unverified (not compiled yet; screenshot `family` renders demo data in CI; the live parts need the Supabase project with 0011 + 0012 applied and sign-in)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Founder (2026-10-08): "do we need special pages for someone with the family subscription to manage easily ... we can
do something cute with all of the characters and make a family of the characters page that all of that stuff is
on. Something that looks good and clean and maintains the aesthetic."

1. Hero: the family portrait (every member as their buddy, in their outfit, on a soft glass stage, names under them,
   idle bob respecting Reduce Motion, tap for a member card). Members' buddy choice shared (nullable `buddy` and
   small `outfit` json on the member row), set from the device, display only. Empty/single: my buddy + "Invite your
   family" with the join code.
2. Family plan card (owner vs "shared with you by your family"), "Manage Family Sharing", Apple-decides explainer.
3. Coming up: next shared events (session 46), next screen-free time (session 44) with join state.
4. Chores: open household tasks for me / not taken.
5. Family Link: send minutes (parent) / recent rewards (teen), consent wording intact.
6. Household management: invite code, members (rename self, leave), owner actions, by reusing Household screens.
7. Entry: Settings card, small dismissable Today card, `zano://family`. Five-tab bar unchanged.
8. Visible only when Household is live or the user has a family plan; never non-working controls.
9. ScreenshotGallery `family` entry with a 4-member demo; copy in a Copy file; accessibility.

## Definition of done

- CI compiles; `FamilyHubTests` pass; `shots/family.png` shows four different buddies on the stage, the plan card,
  Coming up, Chores, Family Link and Household.
- Live project, two phones in one household: each sees the other's buddy and outfit in the portrait after
  reopening; changing the buddy on A shows on B after B reopens. "Change my name" renames A everywhere. Settings'
  Family card and `zano://family` open the page; the Today card hides for good after "Hide".
- Signed out with a family-shared plan: the page shows just my buddy, the plan card ("Shared with you by your
  family") and the Apple family invite note, and nothing else.

## Log

### 2026-10-08 — Member buddy column, hub, portrait, entry points, demo shot, docs

- **Files touched:**
  - new `backend/supabase/migrations/0012_household_member_buddy.sql`
  - new `Core/Sources/Core/Household/FamilyHub.swift` (`FamilyHubAvailability`, `FamilyPortrait`, `FamilyHubLists`, `HouseholdBuddySync`)
  - new `Core/Sources/Core/Copy/FamilyHubCopy.swift` (`Copy.familyHub`)
  - new `Core/Tests/CoreTests/FamilyHubTests.swift`
  - `Core/Sources/Core/Household/HouseholdModels.swift` (`HouseholdMember.buddy/outfit/buddyChoice`, lenient decoding)
  - `Core/Sources/Core/Household/HouseholdClient.swift` (`setBuddy`, `rename`)
  - new `App/ZANO/Features/Family/FamilyView.swift` (hub + `FamilyHubModel`)
  - new `App/ZANO/Features/Family/FamilyPortraitView.swift` (portrait, `HouseholdMemberBuddy`, `FamilyMemberCard`)
  - new `App/ZANO/Features/Family/FamilyTodayCard.swift`
  - `App/ZANO/Features/Settings/SettingsView.swift` (Family card after Buddy, `zano://family` destination; Household and Family Link rows removed, now on the page)
  - `App/ZANO/AppRouter.swift` (`AppDeepLink.family`, `isFamilyPresented`, `openFamily()`)
  - `App/ZANO/Features/Today/TodayView.swift` (card + push)
  - `App/ZANO/Features/Planner/PlannerView.swift` (creator's buddy on shared event rows), `PlannerZanoEventEditor.swift` (buddy on member chips)
  - `App/ZANO/Features/Household/HouseholdView.swift` (buddy sync after create/join; header)
  - `App/ZANO/Features/Buddy/BuddyPickerView.swift`, `BuddyClosetView.swift` (sync on leaving the screen)
  - `App/ZANO/ContentView.swift` (sync on foreground)
  - `App/ZANO/ScreenshotGallery.swift` (`family` + `FamilyDemo`), `.github/workflows/ci.yml` and `scripts/ci/screenshots.sh` (`family` in the tour)
  - `docs/spec.md` §5.31; `docs/launch/privacy-policy.md` (Household row, inside its marker); `docs/launch/supabase-setup.md` step 3
- **What changed:**
  - **Backend (0012).** `household_members.buddy` (one of the nine raw values, nullable) and `outfit` (jsonb object,
    ≤ 512 bytes, nullable). `set_household_buddy(p_buddy, p_outfit)` sets mine on every household I'm in;
    `rename_household_member(p_household_id, p_display_name)`. Both security definer, signed-in only. Reading uses
    the existing members policy (members read members).
  - **Sync.** `HouseholdBuddySync.syncIfNeeded` sends `Buddy.stored` + its stored outfit when the signature
    (buddy + sorted-keys JSON) changed since the last send, or when forced: after creating/joining a household and
    when the hub sees my row doesn't match. Called on foreground and when the buddy picker or closet closes.
  - **Hub.** `FamilyView` with `@Observable FamilyHubModel` (App Group caches first, then the server). Sections as in
    Scope; household management reuses `HouseholdView` and `FamilyLinkView` through navigation. Rename is an alert
    with a text field on my row.
  - **Portrait.** `FamilyPortraitView` on `zanoHero` (violet aurora tint), a glass ellipse stage with a soft radial
    light (hidden from VoiceOver), rows from `FamilyPortrait.rows`, sizes from `spriteSize` (multiples of 16), each
    buddy bobbing ±3pt on `Theme.Motion.idleBobPeriod` out of phase (a `TimelineView` paused under Reduce Motion).
    One accessibility element per member: "Name, Buddy", button, hint "Shows what you share with them".
    Other members' buddies are drawn with `Buddy.image(pose:gear:.bare, outfit:)` (the same pipeline as
    `BuddySprite`); mine is `StoredBuddySprite`.
  - **Entry points.** Settings: a "Family" card under Buddy (up to four buddies overlapped) when
    `FamilyHubAvailability` allows; `zano://family` → Settings tab + push, or Today when unavailable. Today:
    `FamilyTodayCard` when Household is live and a household is cached; "Hide" is permanent per phone.
- **Decisions made and why:**
  - **A new hub that links to `HouseholdView`, not HouseholdView evolved.** HouseholdView is a working board (start/
    join forms, the full task list, screen-free time editing, invite, leave); folding a portrait and plan/link cards
    into it would make one very long screen and change a screen other sessions own. The hub shows summaries and
    links into it; nothing is duplicated (chores tick-off is the same client call).
  - **Settings rows for Household and Family Link moved to the hub** (one way in, no duplicate rows). Both had the
    same availability as the hub (`AccountStatus.isLive`), so nobody loses access.
  - **"Manage Family Sharing" opens the App Store subscriptions page** (`https://apps.apple.com/account/subscriptions`)
    with plain instructions (Settings > your name > Family Sharing). UNVERIFIED: I know of no public URL that opens
    Family Sharing in the Settings app (the `App-prefs:` scheme is private API and an App Review risk). Shown only to
    the buyer once Family Sharing is on; a family member who didn't buy gets a note instead (they can't manage it).
  - **The buyer counts as "family plan" only once `PaywallFamilySharing.isEnabled`** (the founder's switch after App
    Store Connect). Before that, a Pro buyer who isn't in a household doesn't see the page.
  - **Signed out with a family-shared plan:** the invite card explains Apple's family group (text only); no household
    controls, since Household can't work signed out.
  - **Only buddy + outfit are shared,** not earned gear, level or XP (earned gear could hint at streaks and goals).
- **Known issues / TODOs left behind:**
  - Other phones see a changed buddy or name the next time they open ZANO (no push).
  - `FamilyHubAvailability.isVisible` reads `RevenueCatManager.lastProEntitlement`, which isn't observable; Settings
    re-evaluates on its next render (the plan card's entitlement check usually triggers one).
  - The portrait for 8 members on an iPhone SE is tight (4 × 64pt front row); not checked on a small screen.
  - TodayView is a very large body; the extra `navigationDestination` could, in theory, push it over the type
    checker's time limit (it compiles today with many). If CI says "unable to type-check", move the destination
    into a small modifier.
  - PostgREST jsonb RPC parameter (`p_outfit` as a JSON object) written from memory.
- **Needs verification on:** CI (compile + `FamilyHubTests` + the `family` screenshot); Simulator for VoiceOver on
  the portrait and Reduce Motion; a live project with two accounts for the buddy sync and rename.

## Founder steps

1. Apply `0012_household_member_buddy.sql` (after 0011): `supabase db push`.
2. When Family Sharing is switched on in App Store Connect and `PaywallFamilySharing.isEnabled` flipped (session 43),
   buyers see the Family page and the "Manage Family Sharing" button too.
3. Check the `family` screenshot from CI (`shots/family.png`) for the look.
4. When Household goes live, the privacy policy's `[CONFIRM WHEN HOUSEHOLD IS LIVE]` row now also lists the buddy and
   outfit shown to the household.

## Blockers

- No Mac or device here; CI is the compiler. Household needs the Supabase project and sign-in (session 34).

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status (left to the coordinating session)
- [x] No secrets committed
