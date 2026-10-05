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
