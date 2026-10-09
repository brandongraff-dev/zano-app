# Session 35 — Lock: glossy pass

- **Branch:** `claude/focused-keller-41j9sk` (stacked on sessions 33–34)
- **Spec sections:** §15 (design system, Lock), §5.1 (lock vault), CLAUDE.md emergency-unlock rule
- **Status:** Reverted (2026-10-09)
- **Started:** 2026-10-08
- **Last updated:** 2026-10-08

## Scope

Third page of the glossy rollout (founder: "yes go ahead with lock"). Visual only: no lock logic,
intent or copy changes. The emergency unlock stays in its calm look on purpose (design doc §12).

## Log

### 2026-10-08 — Vault card, facts, coins

- **Files touched:** `App/ZANO/Features/Today/LockVaultCard.swift`, `App/ZANO/Features/Today/GoalActionList.swift`,
  `App/ZANO/Features/Lock/LockStatusView.swift`, `App/ZANO/ScreenshotGallery.swift`
- **What changed:**
  - Vault card: the lock medallion is a `ZanoPopBadge` (steel while locked, ZANO Blue with a
    sparkle once earned). Goal rings are lit tubes (a thin white highlight along the inside) and glow
    in their colour once done. The padlock in the middle is a lit disc (glossy blue with a white rim
    and glow once open).
  - "Blocking your apps" / "Ends when your goals are done": glossy badges instead of tinted stickers.
  - Earn Mode bank card: glossy badge in its top row.
  - Minute coins (borrow) and spend chips: the picked one is lit, rimmed and glows.
  - The "Required to unlock" tiles already got meters and badges in session 34 (shared tile).
  - Gallery: `lock-bottom` (Lock scrolled to the end).
- **Decisions made and why:** emergency unlock bar untouched (it must read as serious and always
  available). The locked state stays steel grey rather than a colour: red is reserved for emergency.
- **CI:** run 164 failed on a `? :` type mismatch in the padlock rim (fixed with `AnyShapeStyle`);
  run 165 green but showed Lock's required tiles had no meters (Lock builds its items without
  `goalType`, which would also switch them to buddy faces). Added `GoalActionItem.meterGoal` so Lock
  shows the meter and keeps its badge; run 166 green, screenshots read. Run 165's dark `tab-lock`
  shot caught the home screen (launch didn't foreground); run 166's is correct.
- **Needs verification on:** motion on a device.

## Reverted (2026-10-09)

The founder didn't like the new style on Today and Lock and asked for those pages to go back to how
they were; Fuel (session 33) stays. All code from sessions 34–35 was rolled back to the session 33
state: `ZanoPopBadge` and the `GoalMeters` files are gone from Core, Fuel uses its own local badge and
protein bar again, and the design doc's "Pass 4: glossy" section was removed. The pass 3 (restraint)
rules apply to Today and Lock as before. Kept here as a record of what was tried and rejected.
