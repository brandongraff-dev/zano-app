# Session 16 — Age 13+ and the Family Link design

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §24 (age), §5.23 (new: independent use and Family Link)
- **Status:** Done for the documents; no code yet
- **Started / Last updated:** 2026-10-05

## Founder decisions (2026-10-05)

1. Age rating is **13+**, replacing 16+ (2026-10-02).
2. Anyone 13+ uses ZANO independently with no parent control. Parents can optionally link a teen, only with the teen's acceptance.
3. Features to build next: work-hours focus lock with calendar sync, sleep wind-down, smart unlock rules by context, each with on-device learning that optimises for wellbeing; then Family Link chores/homework with photo proof.

## What changed

`docs/spec.md` (§24 age, new §5.23), `docs/legal/terms-of-service.md`, `docs/legal/privacy-policy.md`, `docs/launch/terms-of-use.md`, `docs/launch/privacy-policy.md`, `docs/launch/app-store-listing.md`, `docs/launch/review-notes.md`, `docs/marketing/app-store-listing.md`. All now say 13+.

## Open items

- **Counsel review is required** before submission: COPPA stays out (no under-13s), but EU countries with a digital-consent age of 14-16 apply the higher local age, and teen data rules (UK Age Appropriate Design Code, US state laws) need a lawyer's read. The App Store Connect age questionnaire has not been checked live.
- Family Link defaults chosen (change if wrong): teen-consented link, teen sees everything the parent sees, teen can leave (parent is told), proof photos are view-once: deleted 10 minutes after first opened, or 24 hours if never opened (founder, 2026-10-05; replaces the earlier 7 days), and never used for training, parent has the final say over any AI check.
- Family Link needs Apple's Family Controls entitlement for any enforcement beyond ZANO's own locks, which needs Apple Developer enrollment (not done).
