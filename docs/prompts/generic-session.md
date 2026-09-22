Read CLAUDE.md and docs/spec.md (sections §<...> — fill in from docs/PROGRESS.md's session table).
Also read docs/PROGRESS.md for current status before starting.

Task: Session <N> — <name>.

Scope:
- <bullet list, copied from docs/spec.md §17 row for this session>

Constraints:
- Shared logic in Core. Extensions read App Group only, no networking.
- Follow §8 (retention psychology) and §24 (safety/legal) rules where relevant.
- If this environment has no Mac available, say so up front and scope the session to what's
  actually verifiable — see docs/setup/windows-workflow.md.

Definition of done:
- <copied from docs/spec.md §17>

Step 1: give me a plan with the exact files you'll create/modify and any Apple APIs you'll use,
with a note on anything that needs a real device or an entitlement. Wait for approval.

Step 2 (after approval): implement, then update docs/sessions/NN-<name>.md and docs/PROGRESS.md
per CLAUDE.md's reporting protocol — after each coding task, not just at the end.
