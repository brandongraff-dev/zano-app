# Edge Functions

None written yet. Planned (docs/spec.md §11 architecture diagram):

| Function | Purpose | Session |
|---|---|---|
| `sync` | Outbox sync endpoint the app's Core/Sync pushes to | Session 7 |
| `revenuecat-webhook` | Writes `subscriptions` table from RevenueCat events | Session 7 |
| `meal-vision` | Photo → vision LLM → strict JSON protein estimate (docs/spec.md §9.5) | Session 8 |
| `weekly-recap` | Sunday job: aggregate week, LLM-write recap card (docs/spec.md §9.6) | Session 8 |

Rule (CLAUDE.md, docs/spec.md §9, §11): API keys for any LLM/vision calls live ONLY here, never in
the app. The app calls these functions; these functions call third-party APIs.

Scaffold a function with `supabase functions new <name>` once the Supabase CLI is set up (see
`backend/supabase/README.md`).
