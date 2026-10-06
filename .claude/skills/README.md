# Project skills

Third-party design skills vendored for the premium-UI effort (`docs/design/premium-ui-plan.md`).
Claude Code loads every folder here as a skill in any session on this repo.

All were read before install: scripts only make network calls to Iconify (icons), GitHub
(`VoltAgent/awesome-design-md` brand styles), Google Fonts and Pexels. Nothing sends project data out.
Unused sub-skills from the source repos (slides, banners, logo generation, shadcn/Tailwind tooling)
were left out on purpose.

| Skill | Source (commit) | License | Role in ZANO |
|---|---|---|---|
| `frontend-design` | anthropics/skills (`34040c9`) | see `LICENSE.txt` | Aesthetic direction, anti-generic self-critique |
| `mobile-app-ui-design` | ceorkm/mobile-app-ui-design (`4c67a0e`) | MIT | Mobile patterns, 8pt grid, peak-end emotional design |
| `ui-ux-pro-max` | nicohodt/claude-code-ui-ux-skill (`29dc4c5`) | MIT | Searchable style/color/type/UX database, design-system generator |
| `mobile-figma-designer` | Klionskiy/claude-mobile-mvp-skills (`3f99ba4`) | MIT | Screen-package structure (system → flow → screens → edge states → handoff) |
| `swiftui-from-figma` | Klionskiy/claude-mobile-mvp-skills (`3f99ba4`) | MIT | Design → SwiftUI conversion rules and state checklist |
| `appstore-mvp-review` | Klionskiy/claude-mobile-mvp-skills (`3f99ba4`) | MIT | App Store readiness, paywall placement, differentiation review |
| `make-mobile-design` | trmquang93/mobile-design-kit (`d2a3f24`) | MIT | HTML iPhone mockups with HIG rules (the prototype layer) |
| `ios-icon-gen` | trmquang93/mobile-design-kit (`d2a3f24`) | MIT | App/UI icon `.imageset` generation (needs macOS `sips`, so CI or a Mac) |
| `ux-designer` | szilu/ux-designer-skill (`da9e9d0`) | MIT | UX critique: accessibility, onboarding, notifications, ethics, microcopy |

Notes for this environment:
- The Figma skills expect a Figma MCP connection. None is connected, so the HTML mockups from
  `make-mobile-design` stand in for Figma frames until one is.
- `make-mobile-design/scripts/fetch_design_style.py list` hits the GitHub API, which can return 403
  behind the cloud proxy. `git clone https://github.com/VoltAgent/awesome-design-md` works instead.

To update a skill, re-copy it from its source repo and bump the commit in this table.
