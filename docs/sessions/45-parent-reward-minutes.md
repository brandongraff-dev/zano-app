# Session 45 — Parent reward minutes (Family Link)

- **Branch:** worktree branch, based on `origin/claude/dazzling-hypatia-ed6q5d` at `54b6dab`
- **Spec sections:** §5.23 (Family Link: teen-consented, teen sees everything, teen can leave), §5.2 (Time Bank: minutes expire at midnight), §24 (teens, emergency unlock, never trap)
- **Status:** Scaffolded — Unverified (no Mac here; awaiting a CI compile and `FamilyRewardTests`; the migration has never run against a live Supabase project)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Founder asked directly: a linked parent can send their teen bonus Time Bank minutes with a short note
("+30 min — nice work on the homework"), inside Family Link's rules.

1. Backend: `family_rewards` with RLS (parent of an active link inserts for its teen; both sides read; only
   the teen claims), server-side caps, rewards on a left link are void.
2. Client: `FamilyLinkClient` send / fetch / claim on the same auth seam.
3. Parent UI in the Family Link screen: chips 10/15/30/60, optional note (80 chars, plain text).
4. Teen: on open/foreground, unclaimed rewards show as a card (buddy, note, "+30 min") → claim → deposit into
   the Time Bank as "from family", not counted as earned by goals; expires at midnight.
5. Never a punishment path; emergency unlock untouched; hidden unless `FamilyLinkAvailability.isLive`.
6. Copy in `FamilyCopy.swift`; Core tests; spec §5.23 and the privacy-policy Family Link row.

## Definition of done

- A parent on an active link can send 10/15/30/60 minutes with an optional note; the server refuses more than
  120 per reward or 240 per link per rolling 24 hours, and refuses non-parents.
- The teen sees the reward next time the app comes to the foreground, adds it once, and today's Time Bank goes
  up by exactly that amount; it is gone at midnight.
- Leaving the link voids anything not yet added. Both sides see the same list.
- Core tests pass in CI.

## Log

### 2026-10-08 — Reward minutes end to end (scaffold)

- **Files touched:**
  - new `backend/supabase/migrations/0010_family_rewards.sql`
  - new `Core/Sources/Core/Family/FamilyRewards.swift` (`FamilyReward`, `FamilyRewardRules`, `FamilyRewardLedger`, `FamilyRewardDepositResult`, `FamilyRewardClaim`)
  - modified `Core/Sources/Core/Family/FamilyLinkClient.swift` (`sendReward`, `rewards`, `claimReward`, `currentUserID`, `userID(fromJWT:)`, private `insert`)
  - modified `Core/Sources/Core/LockEngine/TimeBankEngine.swift` (`depositFamilyReward`)
  - modified `Core/Sources/Core/Copy/FamilyCopy.swift`
  - new `App/ZANO/Features/Family/FamilyRewardPresenter.swift` (presenter, `.zanoFamilyRewards()`, card view)
  - modified `App/ZANO/Features/Family/FamilyLinkView.swift` (Send minutes, shared reward list, side from user id)
  - modified `App/ZANO/ContentView.swift` (foreground check + modifier)
  - modified `App/ZANO/Features/Lock/LockStatusView.swift` ("Includes N min from family, not from goals." under the Earn Mode bank)
  - new `Core/Tests/CoreTests/FamilyRewardTests.swift`
  - modified `docs/spec.md` §5.23, `docs/launch/privacy-policy.md` (Family Link row, still behind its `[CONFIRM WHEN FAMILY LINK IS LIVE]` marker)
- **What changed:** see Scope. Migration number is **0010**: 0008 is Strava and a parallel session may take
  0009 (household quiet times). Nothing here depends on 0009.
- **Decisions made and why:**
  - **Caps in SQL, not an Edge Function.** A `before insert` trigger (`family_rewards_enforce`) checks 1..120
    per reward and 240 per link in a *rolling* 24 hours (the server doesn't know anyone's time zone), takes a
    per-link advisory lock so two quick sends can't both slip under, and overwrites `created_at` /
    `claimed_at` / `voided_at` so a client can't backdate or pre-claim. A check constraint also caps
    `minutes` and the note (≤ 80 chars, no control characters). Fewer moving parts than a function, and the
    rule holds for every path into the table.
  - **Insert via RLS, claim via RPC.** The founder asked for RLS on insert, so the parent inserts directly
    (policy: `from_user = auth.uid()`, parent of an active link, `to_user` is that link's teen). There is no
    update/delete policy at all (and `update, delete` are revoked): claiming is `claim_family_reward`
    (security definer, teen only, returns the minutes; raises `already_claimed` / `void` / `not_found`).
  - **Void on leave.** An `after update of status` trigger on `family_links` stamps `voided_at` on every
    unclaimed reward when the link becomes `left`; the claim RPC also refuses any link that isn't active.
  - **Server claim first, then local deposit.** A void reward can never add a minute. `already_claimed` from
    the server deposits nothing (covers a second device or a retry). Trade-off: if the claim succeeds and the
    local deposit then throws (no local `User` row), those minutes are lost rather than doubled.
  - **Deposit once.** `FamilyRewardLedger` (App Group defaults, like `ReclaimedOpens`) keeps the ids already
    deposited plus an in-flight set in `TimeBankEngine` for overlapping taps; a second claim/deposit of the
    same reward is `.alreadyDeposited`.
  - **"From family" without a schema change.** The minutes go into the same `TimeBank` row as goal minutes
    (`earnedMin`), so they spend, mirror to widgets and expire at midnight with no new code paths. How much of
    a day came from family is kept in `FamilyRewardLedger` (per local day) and shown on the Lock tab's Earn
    Mode card. I did not add a column to `TimeBank`: the store has a versioned schema (V1, no stages yet) and
    a model change needs a V2 + migration stage, which is more than this session should carry.
  - **Weekly recap:** already doesn't count Time Bank *earned* minutes at all (it counts earned unlock
    days from lock sessions and minutes *spent*), so family minutes can't show up as goal wins there. No
    recap change needed.
  - **Side from the signed-in id.** The Family Link screen used to guess parent/teen and, after a relaunch,
    showed a teen the parent's controls. It now reads the user id from the access token's `sub`
    (`FamilyLinkClient.currentUserID`) and the reward card only appears for rewards addressed to that id.
  - Card presentation mirrors `MilestonePresenter`: never over the alarm, the unlock celebration or a
    milestone moment; "Later" hides it until the next launch. The foreground check is fire-and-forget so the
    alarm poll in `runForegroundChecks` never waits on the network.
- **Known issues / TODOs left behind:**
  - No push to the teen when a reward arrives (checked on foreground only).
  - `TimeBank.earnedMin` (and so the widget's "earned today" and the unlock celebration's total) include
    family minutes; only the Lock tab card calls them out. A separate column would need a schema V2.
  - The Supabase `time_bank` sync row's `earned_min` also includes them.
  - Ledger is per device: on a second device the server's `already_claimed` keeps it from depositing twice,
    so the minutes land only on the device that claimed them.
  - PostgREST `Prefer: return=representation` on insert and the RPC returning a bare integer are written from
    memory of the REST API (same caveat as session 23).
- **Needs verification on:** Mac build (CI), Core tests in CI, a live Supabase project (migration, RLS,
  trigger caps, void on leave), two signed-in devices (parent sends, teen claims).

## Blockers

- No Mac or device here; CI is the compiler. No live Supabase project or sign-in yet, so the feature stays
  hidden (`FamilyLinkAvailability.isLive` is false).
