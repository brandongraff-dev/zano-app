# Apple Developer Program enrollment & Family Controls entitlement

Status as of last update: **not enrolled**. Update this file and `docs/PROGRESS.md` the day each
step below completes.

## Why this blocks things

- No TestFlight or App Store submission without an active Apple Developer Program membership
  ($99/yr, individual or organization).
- The **Family Controls entitlement** (what lets ZANO actually shield apps in production) is
  Apple-approved per bundle ID — this app needs **4 separate requests**: main app + `ZANOShieldConfig`
  + `ZANOShieldAction` + `ZANOMonitor` (confirm whether `ZANOReport` also needs its own request when
  filing — Apple's requirements page is the source of truth, this repo's guess is 4). Approval can
  take days to weeks, so file the day enrollment completes, not the day it's needed.
- **Not blocked without enrollment:** local device testing via the **Family Controls (Development)**
  capability in Xcode — works fully on a real device, just can't ship anywhere. So Sessions 2–4 can
  still be built and tested on-device once there's a Mac + iPhone, even before enrollment finishes.

## Steps

1. Enroll at https://developer.apple.com/programs/ (individual is fine to start; can convert to
   organization later if needed for the eventual company/App Store listing name).
2. Once active, go to the Family Controls entitlement request page (search Apple's current developer
   portal / documentation for "Family Controls entitlement request" — the exact URL/form has moved
   before, don't hardcode a stale link) and file requests for all app/extension bundle IDs listed
   above. Explain the use case plainly: goal-gated screen time, not parental control resale.
3. While waiting: register the bundle IDs (`com.zano.app` and the 5 extension suffixes — see
   `project.yml`) in the portal, set up an App Store Connect app record, and get provisioning
   working for device builds using the Development capability.
4. When approved: switch `project.yml` entitlements from development to production Family Controls,
   regenerate the project, and note the approval date here.

## Also needed before TestFlight (Session 0's actual definition-of-done)

- App Store Connect API key or App Store Connect credentials for CI (fastlane) — see
  `.github/workflows/ci.yml`, TestFlight step is stubbed/disabled until these secrets exist.
- Code signing: recommend `fastlane match` once there's a Mac, storing certs in a private repo —
  don't commit `.p12`/`.mobileprovision` files (already in `.gitignore`).
