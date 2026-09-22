# Session 12 — ML service: slip risk + nudge bandit; pg_cron feature job

- **Branch:** `main`
- **Spec sections:** §9.2 (slip prediction), §9.3 (nudge optimizer), §9.9 (data pipeline)
- **Status:** Scaffolded — Unverified. The follow-up batch's `ml-real-pipeline` agent and harden
  pass are confirmed complete and committed (2026-09-22).

## What's confirmed done (Foundation phase, 2026-09-22)

- `ml-service/` — a FastAPI skeleton (`app/main.py`) exposing `POST /plan`, `/risk`, `/nudge` with
  pydantic request/response models. `/risk` currently returns a fixed baseline heuristic, not a
  real model — correct, since no `goal_events` history exists yet to train on (§9.2's own cold-
  start note: "logistic regression on onboarding answers + population priors" until real data
  accrues).
- Real, run pytest tests exist and **actually passed in this environment** (Python runs on
  Windows, unlike everything Swift) — this is the one piece of Session 1-11's work that got
  genuine automated verification rather than static review.

## What's landed (follow-up batch, confirmed complete)

- `backend/supabase/migrations/0004_ml_feature_job.sql` — materializes a `user_day` feature table
  per §9.9 and registers a nightly pg_cron job.
- `ml-service/app/features.py`, `train_risk_model.py` — LightGBM training pipeline skeleton per
  §9.2, exercised against synthetic data (no real data exists yet) with its own pytest coverage.

## Known issues (will carry forward once finalized)

- pg_cron availability on whatever Supabase plan eventually gets used is unconfirmed — flagged by
  the agent that wrote the migration.
- The nudge-optimizer bandit (§9.3) itself — not just `NudgeSender`'s client-side cap, which is
  Session 11 — is not built. Needs real delivered/acted_within_3h data to train against, same
  cold-start constraint as slip prediction.

## Needs verification on

Python (works today, on Windows): rerun `pytest` from `ml-service/` after the follow-up batch
lands. Everything else needs a real Supabase project with real `goal_events` history, which needs
the app actually running on real users first — this session cannot fully mature until then.
