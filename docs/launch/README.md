# Launch docs

Everything needed to get ZANO through company formation, Apple Developer enrollment, App Review and
a public launch. All legal text here is a **draft for lawyer review**, and none of it is legal advice.

| File | What it is | Status |
|---|---|---|
| [privacy-policy.md](privacy-policy.md) | Public privacy policy, to publish at `[WEBSITE]/privacy` (the app already links `https://zano.app/privacy`). Written from a code audit. `[CONFIRM WHEN … IS LIVE]` marks flows that are coded but switched off | Draft, needs lawyer review + placeholders filled |
| [terms-of-use.md](terms-of-use.md) | Terms of Use / custom EULA, with the subscription terms required by Guideline 3.1.2 and Apple's minimum EULA terms. Publish at `[WEBSITE]/terms` | Draft, needs lawyer review |
| [app-privacy-labels.md](app-privacy-labels.md) | How to answer App Store Connect's App Privacy questionnaire, per data type, with code evidence. Also covers the `PrivacyInfo.xcprivacy` audit, the Info.plist usage-string review, and privacy risks to fix before launch | Ready to use. Re-audit when any service goes live |
| [app-store-listing.md](app-store-listing.md) | App Store name, subtitle, promo text, description, keywords (with reasoning), category, age rating, What's New, screenshot plan + App Preview storyboard, IAP names and trial framing. Every limited field has its character count. Supersedes `docs/marketing/app-store-listing.md` | Draft. Age rating needs a founder decision; keywords unverified against live search data |
| [family-controls-request.md](family-controls-request.md) | Paste-ready text for the Family Controls (Distribution) request: **5** bundle IDs (app + ShieldConfig + ShieldAction + Monitor + Report, from a per-target API grep), filing steps, what to do while waiting | Ready to file once enrolled. Form fields unverified |
| [review-notes.md](review-notes.md) | App Review notes for the 7-step flow (5-minute reviewer path, paste-ready notes), per-permission justifications, guideline pre-check, and the RISK list found in code. Supersedes `docs/setup/app-review-notes.md` | Draft. 4 blockers to fix before submitting (see its §1) |

**Placeholders used throughout:** `[COMPANY LEGAL NAME]`, `[STATE]`, `[CONTACT EMAIL]`, `[WEBSITE]`,
`[EFFECTIVE DATE]` (plus `[REGISTERED ADDRESS]`, `[PRICE]`, `[TRIAL LENGTH]`, `[SUPABASE REGION]`).
Fill them in with the same values in every file.

**Keep these four things in agreement:** the privacy policy, the App Store Connect privacy answers,
each target's `PrivacyInfo.xcprivacy`, and what the code actually sends. If you switch on a
service (Supabase, RevenueCat, PostHog, Sentry, meal vision), update all four in the same change.

**Older drafts:** `docs/legal/privacy-policy.md` and `docs/legal/terms-of-service.md` (2026-09-22)
are superseded by the files here. They describe Sign in with Apple and server sync as live, but
neither exists in the code.
