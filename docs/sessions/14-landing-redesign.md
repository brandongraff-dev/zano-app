# Session 14 — Landing page redesign

- **Branch:** `claude/gracious-johnson-tl2jf4`
- **Spec sections:** §22 (Phase 0: landing page + waitlist), §5.13 (coach voices, buddy)
- **Status:** Done (static page; verified in headless Chromium at 1360px and 390px, no JS errors)
- **Started / Last updated:** 2026-10-05

## Log

### 2026-10-05 — Simplified plain-white landing page (v2 after feedback: less copy, no gradients)

- **Files touched:** `landing/index.html`, `landing/style.css` (rewritten), `landing/assets/*.webp` (new: 5 app screens + buddy crop)
- **What changed:** light theme, glass cards/nav, animated blobs, floating phone mockups with pointer parallax/tilt, rotating headline word, LOCKED/DONE marquee, scroll reveals, bento goals with progress bars, streak counter, raccoon buddy in hero/buddy/streak/CTA sections (speech bubble cycles coach voices). Respects `prefers-reduced-motion`.
- **Decisions:** waitlist form + Supabase script kept as-is (same ids). Buddy is cropped from the supplied screenshot and shown in a dark orb since there is no transparent asset.
- **Known issues:** screenshots are ~385px wide sources, so slightly soft on retina; swap in real exports when available. Buddy cutout/transparent PNG would look better. Inter loads from Google Fonts (falls back to system font).

### 2026-10-05 — Scroll story + buddy picker

- **Files touched:** `landing/index.html`, `landing/style.css`
- **What changed:** sticky scroll story (phone stays, 4 screens + raccoon bubble swap by scroll position); buddy picker (Raccoon, Fox, Frog, Cat) with name, trait and sample coach line.
- **Decisions:** Fox/Frog/Cat are placeholder 16x16 pixel sprites drawn in JS for the page only. They are NOT app assets and no buddy species list exists in docs/spec.md — confirm the real roster before shipping.

### 2026-10-05 — Real app buddies on the landing page, no phone, cuter

- **Files touched:** `scripts/buddies/*` (copied from `origin/claude/sharp-euler-npwt08`, then edited), `landing/assets/buddies/*.webp` (new, 9 buddies x content/happy), `landing/index.html`, `landing/style.css`; removed `landing/assets/buddy.webp`.
- **What changed:** the picker now shows the app's real nine buddies (Stash, Zib, Lox, Pip, Moko, Brick, Tank, Volt, Howl). In `buddies.py`: Stash no longer holds a phone (paws clasped on belly); eyes enlarged on Lox, Moko, Brick, Tank, Volt, Howl; Brick's head rounder with softer jowls; Howl's hoodie lightened.
- **Decisions:** the buddy source lives on `claude/sharp-euler-npwt08`, not `main`. These generator edits are on this branch only; the app's `BuddySprites.swift` / `WatchBuddySprites.swift` still need regenerating (`export_swift.py`) after merging the two branches. Expect a merge conflict in `scripts/buddies/buddies.py`.
- **Known issues:** PNGs here are 48x48 upscaled 8x; the monster/gear art is untouched.

### 2026-10-05 — Layered hero and page depth

- **Files touched:** `landing/index.html`, `landing/style.css`
- **What changed:** hero has no copy (h1 kept sr-only): giant "zano" wordmark, disc + orbiting ring, three phones at different depths, six floating buddies, glass icon chips, glass sign-up bar over the cropped phone. Pointer + scroll parallax on every `.fl` layer. Goals/CTA are stacked rounded "sheets" with buddies peeking over the edge; story has ghost phones behind; picker stage has a disc; CTA shows all nine buddies. Reduced-motion disables animation and parallax.

### 2026-10-05 — Hero/story polish

- **What changed:** removed the giant "zano" backdrop text; replaced the blurred side phones with illustrated screens (blue "zano" splash, "Social is locked", "Unlocked"). These three are marketing illustrations built in HTML/CSS, NOT captures of the real app. Story now has 5 steps (locked, today, unlocked, streak, settings). Mobile hero is one clean phone. Bottom-of-page buddies bob 4px and barely parallax.
- **Still needed:** real captures of more screens (workout/focus session, protein logging, buddy picker, Live Activity). CI's screenshot gallery (`App/ZANO/ScreenshotGallery.swift`) is the likely source.

### 2026-10-05 — Scroll Monster section

- **Files touched:** `landing/index.html`, `landing/style.css`, `landing/assets/buddies/monster-{0,1,2}-{healthy,hurt,defeated}.webp` (rendered from `scripts/buddies/monster.py`).
- **What changed:** sticky "Beat the Scroll Monster." section between the story and Goals. Scrolling drains its HP bar; the monster goes healthy -> hurt -> defeated, Stash cheers and a "+50 coins" tag pops. Copy follows `Copy.buddy` in the app (weekly boss; locked minutes and finished goals reduce HP; coins). The "+50" amount is illustrative, not from the app.

### 2026-10-05 — Hero screens + NFC tags + Sunrise alarm sections

- **What changed:** hero centre phone is now the real dark Today screen (buddy + goals), flanked by the real 30-day streak card and the illustrated "Unlocked" screen. New sections: "Tap to log." (NFC tags: animated tag ripple + phone logging +750 ml) and "Get up to turn it off." (Sunrise alarm: rising sun, tag on the mirror, buddy waking up). Copy follows spec §5.10 / §6 (Sunrise Tag dismisses the alarm; tags log water/protein/focus/gym). The "+750 ml" and "6:30" screens are illustrations, not app captures.

### 2026-10-05 — Hero centre screen: made-up "1 goal to unlock"

- Light-theme illustrated screen (not an app capture): happy buddy, "1 goal to unlock", three goals done, Focus in progress with a filling bar, "Social locked" chip that flips to "Social open". Built in HTML/CSS (`.mock--home`). Gotcha: cqw padding on a container element resolves against the *parent* container (or svw), so padding on `.mock--home` uses %.
