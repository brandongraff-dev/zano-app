# Session 31 — Tone down the blue

- **Branch:** `claude/sweet-mayer-a9hzwo` (rebuilt on `main` @ a520809)
- **Spec sections:** §15 (design tokens; `docs/design/visual-direction-v2.md` owns the palette)
- **Status:** Scaffolded — Unverified
- **Started:** 2026-10-06
- **Last updated:** 2026-10-06

## Scope

User request: "just tone down the blue or something to make it look better." Palette only: no
layout, component or character changes.

## Log

### 2026-10-06 — Palette retune

- **Files touched:** `Core/Sources/Core/UI/Theme.swift` (Tones + doc comments),
  `Watch/ZANOWatch/WatchTheme.swift` (accent mirror). Widgets and the shield read `Theme` directly,
  so they follow automatically.
- **What changed (dark / light):**
  - Canvas `#0B0E24` → `#0A0A0D` / `#F5F6FB` → `#F5F5F7`; deep `#06081A` → `#050507` /
    `#E8EAF4` → `#EBEBEF`.
  - Surfaces `#161A3A` → `#18181D`, surface-2 `#1F2450` → `#222228`, hero `#1D2248` → `#1D1D23`;
    light surface-2 `#ECEEF6` → `#EEEEF1`.
  - Text greys lose their lavender: dark text `#F4F3FF` → `#F4F4F6`, secondary `#D2D0EA` →
    `#D2D2D8`, muted `#A6A4C8` → `#A3A3AD`; light ink `#13142B` → `#141418`, secondary/muted to
    `#3D3D48` / `#63636E`.
  - Accent softened: `#3F7BFF` → `#5B8DEF` (dark), `#2A62E6` → `#3366CC` (light + filled buttons;
    white on it ≈5.3:1). Washes/dims and the interactive wash follow.
  - Aurora (the glow behind the buddy) desaturated: blue `#3F7BFF` → `#4F6FB8`, violet `#8F5BFF` →
    `#6E5BA8`. Locked ambient `#2A2F7A` → `#2A2A36`. Glass chrome tint follows the canvas.
- **Unchanged on purpose:** goal ring colours, buddy/character palettes (`Trio`), danger/warning,
  ember.
- **Context:** an earlier attempt in this session redesigned a 207-commit-stale base by mistake.
  Its commits remain in this branch's history, but a merge with the `ours` strategy discards their
  content: the branch tree is exactly `main` plus this change.
- **Needs verification on:** CI build + screenshot tour (dark and light).
