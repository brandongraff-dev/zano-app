# Session 36 — Lock: centre the padlock in the vault rings

- **Branch:** `claude/focused-keller-41j9sk`
- **Spec sections:** §15 (Lock screen), §5.1 (lock vault)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-13
- **Last updated:** 2026-10-13

## Log

### 2026-10-13 — Centre the padlock

- **Files touched:** `App/ZANO/Features/Today/LockVaultCard.swift`
- **What changed:** the founder flagged the padlock in the middle of Lock's goal rings as off-centre.
  In the "resting" mood (no goal done yet) `VaultLockCharacter` tilted the whole disc −12° around its
  bottom edge and pushed it down 4%, so the disc sat low and to the side. Now the disc never moves;
  the droop (−12° tilt, 80% opacity) and the wobble on each completed goal apply to the lock glyph
  only, around its centre.
- **Decisions made and why:** kept the droop/perk/open moods (they carry the "body language"), just
  moved them onto the glyph.
- **CI:** run 168 green; `tab-lock` and `light-tab-lock` read, disc centred.
- **Needs verification on:** the wobble on a device.
