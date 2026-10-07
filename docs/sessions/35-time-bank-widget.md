# Session 35 — Time Bank widget

- **Branch:** `worktree-agent-aa3c06448b7de78b1` (built on `origin/main` @ c586ea9)
- **Spec sections:** §5.2 (Earn Rate / Time Bank), §5.11 (Earn Meter, for the shared mirror), §6
  (widgets), §14 (App Intents: reuses `OpenTodayIntent`), §27 (extension limits)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

User request: a widget whose whole job is "you've earned 20 min" at a glance, the daily hook.
Home Screen small + medium, Lock Screen circular + rectangular + inline. Balance, earned and spent
today, lock state, and the next way to earn more. Medium gets one button. Copy in `Core/Copy`,
accessibility labels on everything, Core tests for the pure logic.

## Definition of done

- The widget shows today's balance, earned and spent, and redraws when minutes are earned or spent.
- All five families render in light and dark, with the placeholder in the widget gallery.
- The medium button opens the right place. No new intents and no duplicated logic.
- Core tests for the new pure logic pass in CI.

## Log

### 2026-10-07 — Time Bank widget

- **Files touched:**
  - `Extensions/ZANOWidgets/TimeBankWidget/ZANOTimeBankWidget.swift` (new): the widget, provider,
    and the five family views.
  - `Extensions/ZANOWidgets/ZANOWidgetsBundle.swift`: adds `ZANOTimeBankWidget()`.
  - `Extensions/ZANOWidgets/Support/ZANOWidgetSnapshot.swift`: adds `timeBankEarnedToday`,
    `timeBankSpentToday` and `timeBankNextEarn` (defaulted init params, so existing call sites are
    unchanged). The loader reads the new mirrors and works out the next goal that earns minutes.
  - `Extensions/ZANOWidgets/Support/ZANOWidgetComponents.swift`: gallery snapshots carry Time Bank
    numbers; adds `ZANOWidgetLink.timeBank` (`zano://timebank`).
  - `Core/Sources/Core/LockEngine/TimeBankGlance.swift` (new): pure value type. It normalizes the
    mirrors and picks the next earn.
  - `Core/Sources/Core/LockEngine/TimeBankEngine.swift`: `mirrorIfToday` also mirrors earned and
    spent, and calls `WidgetRefresh.reloadAll()`. This covers deposit, spend, spend-to-unlock,
    borrow and refund.
  - `Core/Sources/Core/Store/SharedDefaults.swift`: adds the `timeBankEarnedToday` and
    `timeBankSpentToday` mirrors.
  - `Core/Sources/Core/Store/WidgetRefresh.swift`: adds the `timeBankWidgetKind` constant.
  - `Core/Sources/Core/Copy/WidgetCopy.swift`: adds a "Time Bank widget" section.
  - `App/ZANO/AppRouter.swift`: adds the `zano://timebank` deep link, which opens the Lock tab.
  - `App/ZANO/ScreenshotGallery.swift`: demo data seeds the new mirrors (earned 90, spent 0).
  - `Core/Tests/CoreTests/TimeBankWidgetTests.swift` (new).
- **What changed:**
  - Small: the buddy (`ZANOWidgetBuddy`, posed by goal progress like the Home widget) over the big
    number ("35 min left" / "20 min earned"), plus a next-earn hint ("Gym +90 min") and a lock
    glyph. StandBy shows a bigger buddy and number with no hint.
  - Medium: the buddy on the left. On the right: the TIME BANK label and lock status line, the big
    number, "Earned 60 · spent 25", a draining bar (reuses `ZANOTimeBankBarView`, with today's
    earned total as the cap), the next-earn hint and one button.
  - Lock Screen: circular uses `accessoryCircularCapacity` (fraction of today's earnings still
    banked, with minutes in the centre). Rectangular shows "Time Bank · 35 min", a linear capacity
    gauge and the hint. Inline shows "35 min left".
  - Tapping anywhere opens `zano://timebank` (the Lock tab).
- **Decisions made and why:**
  - **The snapshot isn't Codable.** `ZANOWidgetSnapshot` is rebuilt from `SharedDefaults` and
    SwiftData on every timeline reload and never stored, so backward compatibility lives in the
    mirrors. The new keys read 0 when missing, and `TimeBankGlance` raises earned to at least
    `balance + spent`. An install from before this session therefore shows "earned 35", never
    "earned 0, 35 left". A stale mirror from before midnight reads as an empty bank.
  - **No daily cap field.** Spec §5.2 defines rates and midnight expiry but no cap, so the
    snapshot gets no cap field (CLAUDE.md: no future-proofing). The bar's ceiling is today's
    earned total, so it drains as minutes are spent.
  - **The medium button.** When locked with minutes in the bank, a "Spend" `Link` opens the Lock
    tab, where `LockStatusView` already runs `spendToUnlock`/`borrowToUnlock`. Spending can't run
    in the widget: it lifts shields, which needs the app's Family Controls entitlement, and it
    needs an amount chosen. Otherwise the button is Core's existing `OpenTodayIntent` ("Earn more",
    or "Open ZANO" when nothing is left to earn). No new intents.
  - **Next earn.** This is the unfinished active goal with the biggest `TimeBankEarnRates` payoff.
    The active lock's required goals come first, so they win ties. Only gym, focus and protein
    have rates (spec §5.2), so water and the rest never show up.
  - **Refresh.** The timeline safety net is 15 min, pulled in to local midnight when minutes
    expire. `WidgetRefresh.reloadAll()` reloads every widget kind, the new one included.
- **Known issues / TODOs left behind:**
  - `OpenTodayIntent` from a widget button foregrounds the app. It doesn't pick the Today tab
    (existing behaviour, see that intent's header).
  - The in-app screenshot tour (`ScreenshotGallery` / `scripts/ci/screenshots.sh`) renders app
    screens only. No widget is shown there today, so none was added. Widgets need a
    Simulator/device Home Screen or Xcode previews (`#Preview` blocks are included).
  - The gallery snapshot's "Gym" title is a literal, like the existing `remainingGoalTitles`
    placeholder.
- **Needs verification on:** CI build (Core + widget extension), CI Core tests, and a
  Simulator/device Home Screen + Lock Screen for layout (small/medium in light, dark and StandBy;
  three accessory families), the Spend link and the `OpenTodayIntent` button.

## Definition-of-done check (fill in when claiming Done)

- [ ] Every item in "Definition of done" above is actually true, not just "code exists for it"
- [ ] Verified where the spec requires real-device/Mac verification (not just "should work")
- [ ] `docs/PROGRESS.md` row updated to match this file's Status
- [ ] No secrets committed (check `.gitignore` coverage if you added new config/env files)
