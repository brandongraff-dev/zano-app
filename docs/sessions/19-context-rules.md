# Session 19 — Smart unlock rules

- **Branch:** `claude/quirky-wozniak-bf8h1v`
- **Spec sections:** §5.26, §2, §24
- **Status:** Scaffolded — Unverified
- **Started / Last updated:** 2026-10-05

## Log

### 2026-10-05

- **Files touched:** new `Core/Sources/Core/LockEngine/ContextRules.swift`, `Copy/ContextRulesCopy.swift`, `App/ZANO/Features/ContextRules/ContextRulesView.swift`, `ContextRulesTests.swift`; edited `LockEngineManager.applyZanoShield` (subtracts exempt apps), `ScheduledLockMonitor`, `LockSchedule`, `SettingsView`
- **What changed:** Up to 3 rules keep a lock set's apps open on chosen days and hours; a suggester offers a rule after 3 emergency unlocks on the same weekday in a 2h span within 6 weeks. Rules only open more apps.
- **Known issues / not done:** iOS opens or closes whole apps only. Rule boundaries rely on the monitor extension.
- **Needs verification on:** CI compile and tests; device for the monitor boundary

## Blockers

- No Mac or device here; CI is the compiler.
