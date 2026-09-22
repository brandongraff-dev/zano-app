# First time opening ZANO on a Mac

Run through this once when a Mac is available. Update `docs/PROGRESS.md` and `CLAUDE.md`'s
"Current environment status" block when done — that unblocks the sessions listed in
`docs/setup/windows-workflow.md` as Mac-blocked.

## 1. Install tooling

```sh
xcode-select --install          # Xcode Command Line Tools
brew install xcodegen            # generates the .xcodeproj from project.yml — never hand-edit the project
brew install supabase/tap/supabase
brew install fastlane            # TestFlight automation, used by CI later
```
Install Xcode itself from the App Store (match the version needed for iOS 17+ SDK; check current
Xcode/iOS SDK compatibility before picking a version).

## 2. Generate and open the project

```sh
cd zano-app        # repo root
xcodegen generate
open ZANO.xcodeproj
```

`project.yml` is the source of truth for targets, entitlements, and build settings — if you change
anything in Xcode's project settings UI, port it back to `project.yml` and regenerate, or it'll be
silently lost next time someone regenerates.

## 3. Verify the extension stubs

The extension targets (`Extensions/ZANOWidgets`, `ZANOShieldConfig`, `ZANOShieldAction`,
`ZANOMonitor`, `ZANOReport`) were written from Windows without a compiler, based on documented
Apple APIs — treat them as **first-draft, not verified**. Specifically:

- Cross-check each extension's `NSExtensionPointIdentifier` (in `project.yml`) against a
  freshly-generated Xcode template of that same extension type (File → New → Target). Apple's
  template identifiers are the authoritative source, not this repo's guess.
- Confirm the Family Controls (Development) capability is attached to: `ZANO`, `ZANOShieldConfig`,
  `ZANOShieldAction`, `ZANOMonitor`, `ZANOReport`. This works on a real device without Apple's
  approval; it just can't ship to TestFlight (spec §24).
- Fix whatever doesn't compile — that's expected for a first Mac build, not a regression. Log fixes
  in `docs/sessions/00-repo-and-stack-setup.md`.

## 4. First build

```sh
xcodebuild -scheme ZANO -destination 'platform=iOS Simulator,name=iPhone 15' build
```
This should succeed for the *app* target even though FamilyControls/HealthKit/NFC won't function in
Simulator (spec §27) — it's just a compile check. Real verification needs a physical device signed
into a dev team.

## 5. Update status

- `docs/PROGRESS.md`: flip environment rows for Mac to ✅, update Session 0 status once it actually
  builds (and, later, once it ships to TestFlight — that also needs Apple Developer enrollment,
  see `docs/setup/apple-developer.md`).
- `CLAUDE.md`: update the "Current environment status" block.
- Append a dated log entry to `docs/sessions/00-repo-and-stack-setup.md` with what you had to fix.

## 6. Reference repos (optional but recommended before Session 2/4)

See `docs/references/README.md` — clone the Screen Time API reference repos locally (gitignored)
before starting Lock Engine (Session 2) or NFC (Session 4) work.
