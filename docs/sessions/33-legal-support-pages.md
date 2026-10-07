# Session 33 — Privacy, Terms and Support pages

- **Branch:** `claude/dazzling-hypatia-ed6q5d`
- **Spec sections:** §24 (privacy, App Store rules), §22 (landing site); `docs/launch/final-checklist.md` §C
- **Status:** Support page Done (static page, checked in headless Chromium at 390px and 1280px). Privacy and
  Terms: generator Done, pages blocked on the lawyer-approved text (82 placeholders left).
- **Started:** 2026-10-07
- **Last updated:** 2026-10-07

## Scope

- The app links to `https://zano.app/privacy` and `/terms`, and App Store Connect needs a Support URL. App
  Review opens all three; a 404 is a rejection (final checklist §C).
- Publishing the draft legal text with its placeholders would be worse than a 404 (session 26 decision).

## Log

### 2026-10-07 — pages and generator

- **Files touched:** `scripts/build-legal-pages.py` (new), `landing/support.html` (new), `landing/style.css`
  (`.legal` styles appended), `landing/index.html` (footer links), `landing/README.md` (§5), `.gitignore`
  (`build/`).
- **What changed:** `build-legal-pages.py` turns `docs/launch/privacy-policy.md` and `terms-of-use.md` into
  `landing/privacy.html` / `terms.html` in the site's style, dropping the internal `>` notes. It refuses to
  write while any `[PLACEHOLDER]` / `[CONFIRM …]` marker is left (it handles markers that wrap across lines
  and one level of nesting such as `[CONFIRM WHEN POSTHOG IS LIVE: [N] days]`) and lists each with its line.
  `--draft` writes a "Do not publish" preview with `noindex` into `build/legal-draft/` instead. `support.html`
  is hand-written: emergency unlock, stuck locks, stopping locks, gym check-ins, manual logging, cancelling
  and refunds (Apple), Restore purchases, deleting data, contact email (`support@zano.app`, same as
  `Copy.settings.supportEmail`).
- **Decisions:** no Markdown dependency (a small converter for the subset the two documents use), so it runs
  anywhere with Python 3. The generated HTML is not committed until it can be built for real.
- **Found while checking RevenueCat (not this session's files, handed to session 34):** the ZANO target's
  `REVENUECAT_API_KEY: ""` build setting overrides environment variables and Codemagic never passes the key
  to `xcodebuild`, so a key added in Codemagic would be ignored.
- **Known issues:** the privacy policy says Sign in with Apple and sync don't exist; session 34 adds Sign in
  with Apple, so §3 Accounts needs the lawyer's update before publishing. Pretty URLs (`/privacy` →
  `privacy.html`) depend on the host; check after deploying.
- **Needs verification on:** the deployed host (URLs resolve without `.html`).

## Blockers

- Lawyer-approved text and business details (company name, state, address, email, prices, trial length,
  effective date) for Privacy and Terms.
- A host and the `zano.app` DNS (final checklist §D).
