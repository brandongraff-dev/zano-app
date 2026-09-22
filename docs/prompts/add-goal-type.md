Add a new goal type "<name>" per docs/spec.md §3 row: verification tier <A/B/C>, verification
method <...>, anti-cheat <...>.

Add:
- `GoalType` case (Core/Sources/Core/Models)
- Verifier in `Core/Sources/Core/Verification`
- App Intent (`Core/Sources/Core/Intents`) — see §14 catalog for the pattern
- Widget button, if tier B (`Extensions/ZANOWidgets`)
- Shield copy variants for all 4 coach voices (`Core/Sources/Core/Copy`) — see §5.13
- Onboarding option, if applicable (§7)
- Unit tests in `CoreTests`

Follow the existing Protein goal as the reference implementation once it exists (Session 2+).

After implementing: update the relevant docs/sessions/NN-*.md file and docs/PROGRESS.md per
CLAUDE.md's reporting protocol.
