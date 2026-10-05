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
