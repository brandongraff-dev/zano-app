"""Turns raw rows into the slip-risk model's feature vector (docs/spec.md §9.2, §9.9).

Two feature paths, matching spec §9.2's two models:

- `to_frame` / `vectorize_row` — the v1-proper path. Input rows are shaped like
  `public.user_day_features` (backend/supabase/migrations/0004_ml_feature_job.sql), the nightly-
  materialized table §9.9 describes ("goal_events is the training table. Nightly job materializes
  user_day features."). `train_risk_model.py`'s `train_lightgbm` consumes `to_frame`'s output.
- `coldstart_features` — spec §9.2's cold-start path: "logistic regression on onboarding answers +
  population priors", for a user who has zero `user_day_features` rows yet (today, that's every
  user — see train_risk_model.py's module docstring). `train_risk_model.py`'s
  `train_coldstart_logistic` / `ColdStartRiskModel` consume this.

This module does no I/O and holds no state — it's a pure function of whatever rows/dicts callers
pass in (a Supabase query result, a pandas row, a hand-built dict in a test). Column names are
chosen to match `user_day_features` one-to-one so a raw query result can be passed straight
through without a translation layer.
"""

from __future__ import annotations

from typing import Any, Iterable, Mapping, Sequence

import pandas as pd

# ---------------------------------------------------------------------------
# Column contract — must match backend/supabase/migrations/0004_ml_feature_job.sql's
# public.user_day_features columns (feature columns only; user_id/date/materialized_at are
# identifiers/bookkeeping, not model inputs).
# ---------------------------------------------------------------------------

NUMERIC_FEATURE_COLUMNS: tuple[str, ...] = (
    "day_of_week",
    "hour_of_first_event",
    "streak_length",
    "days_since_last_miss",
    "events_count",
    "verified_events_count",
    "active_goal_count",
    "avg_difficulty_step",
    # Listed in spec §9.2 but not yet sourced from any table — see 0004_ml_feature_job.sql's
    # header comment. Always None today; kept here so the column contract (and a future
    # ingestion migration) doesn't require touching this module again.
    "sleep_hours",
    "calendar_density",
)

BOOLEAN_FEATURE_COLUMNS: tuple[str, ...] = (
    "yesterday_completed",
    "any_plan_b_offered",
    "travel_flag",  # not yet sourced (see above) — always None today
)

CATEGORICAL_FEATURE_COLUMNS: tuple[str, ...] = (
    "onboarding_fall_off_pattern",  # not yet sourced (see above) — always None today
    "weather",  # not yet sourced (see above) — always None today
)

ALL_FEATURE_COLUMNS: tuple[str, ...] = (
    NUMERIC_FEATURE_COLUMNS + BOOLEAN_FEATURE_COLUMNS + CATEGORICAL_FEATURE_COLUMNS
)

LABEL_COLUMN = "label_missed_all_goals"

# Cold-start population prior — matches app/main.py's RISK_BASELINE_P_MISS heuristic constant, so
# the cold-start model's fallback and the current heuristic stub agree on "no signal" risk.
POPULATION_PRIOR_P_MISS = 0.22

# Spec §7 Q5 ("When do you usually fall off?") options -> rough, hand-set prior nudges (population
# level, NOT fit to real data — there is no onboarding-answers table / production outcomes to fit
# this from yet; see 0004_ml_feature_job.sql's header comment). Positive = higher assumed miss
# risk. Kept here as documentation of the mapping; `coldstart_features` does not apply this
# adjustment itself (that blending happens once a real onboarding-answers table + labeled
# cold-start outcomes exist to fit it against, not as a hand-tuned constant baked into training
# code) — this dict is exposed for that future use and for tests that want to sanity-check it.
ONBOARDING_FALL_OFF_OPTIONS: tuple[str, ...] = (
    "weekends",
    "evenings",
    "when_stressed",
    "after_a_few_good_days",
    "travel",
)


def vectorize_row(row: Mapping[str, Any]) -> dict[str, Any]:
    """Build one model-ready feature dict from one `user_day_features`-shaped raw row.

    - Numeric columns pass through as `float`; `None` stays `None` (LightGBM's native
      missing-value handling treats that as "unknown" rather than a fabricated 0).
    - Boolean columns convert `True`/`False`/`None` -> `1.0`/`0.0`/`None`.
    - Categorical columns pass through unchanged (`str` or `None`); `to_frame` is what marks them
      as pandas 'category' dtype for LightGBM's categorical-feature support.
    """
    out: dict[str, Any] = {}
    for col in NUMERIC_FEATURE_COLUMNS:
        v = row.get(col)
        out[col] = float(v) if v is not None else None
    for col in BOOLEAN_FEATURE_COLUMNS:
        v = row.get(col)
        out[col] = None if v is None else (1.0 if v else 0.0)
    for col in CATEGORICAL_FEATURE_COLUMNS:
        out[col] = row.get(col)
    return out


def vectorize_rows(rows: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """`vectorize_row` applied to every row, materialized as a list."""
    return [vectorize_row(r) for r in rows]


def to_frame(rows: Iterable[Mapping[str, Any]], *, include_label: bool = False) -> pd.DataFrame:
    """Build a pandas DataFrame ready for `train_risk_model.train_lightgbm` / a fitted model's
    `.predict_proba`.

    Categorical columns get pandas 'category' dtype, which is how LightGBM's scikit-learn API
    auto-detects categorical features without needing manual integer encoding. `rows` is
    materialized to a list up front since it's read twice (once for features, once for the label)
    when `include_label=True`.
    """
    rows = list(rows)
    vectors = vectorize_rows(rows)
    frame = pd.DataFrame(vectors, columns=list(ALL_FEATURE_COLUMNS))
    # Force numeric/boolean dtype explicitly rather than trusting pandas' inference: a column
    # that's None for every row in this batch (e.g. sleep_hours/calendar_density/travel_flag
    # today — see the "not yet sourced" columns above) infers as object dtype, which LightGBM
    # rejects outright ("pandas dtypes must be int, float or bool"). astype("float64") turns
    # None -> NaN, which is exactly the "missing" representation LightGBM expects.
    for col in NUMERIC_FEATURE_COLUMNS + BOOLEAN_FEATURE_COLUMNS:
        frame[col] = frame[col].astype("float64")
    for col in CATEGORICAL_FEATURE_COLUMNS:
        frame[col] = frame[col].astype("category")
    if include_label:
        frame[LABEL_COLUMN] = [
            (bool(r[LABEL_COLUMN]) if r.get(LABEL_COLUMN) is not None else None) for r in rows
        ]
    return frame


def coldstart_features(onboarding_answers: Mapping[str, Any]) -> dict[str, Any]:
    """Cold-start feature set: onboarding answers only, no `goal_events`/`user_day_features`
    history yet (spec §9.2).

    Expects a dict shaped like the onboarding App Intent's payload / spec §7's questions:
    - `fall_off_pattern`: one of `ONBOARDING_FALL_OFF_OPTIONS` (§7 Q5), or None if unanswered.
    - `daily_phone_hours`: §7 Q3, a 1-10 slider value.
    - `current_workouts_per_week` / `target_workouts_per_week`: §7 Q4's two steppers.
    """
    fall_off = onboarding_answers.get("fall_off_pattern")
    daily_phone_hours = onboarding_answers.get("daily_phone_hours")
    current_workouts = onboarding_answers.get("current_workouts_per_week")
    target_workouts = onboarding_answers.get("target_workouts_per_week")

    gap_ratio: float | None = None
    if current_workouts is not None and target_workouts:
        # How much of a stretch the user's stated target is relative to where they are today;
        # 0 = already there, close to 1 = huge ask relative to target. Clamped at 0 so a target
        # already met (or exceeded) doesn't produce a negative "gap".
        gap_ratio = max(float(target_workouts) - float(current_workouts), 0.0) / float(target_workouts)

    return {
        "fall_off_pattern": fall_off,
        "daily_phone_hours": float(daily_phone_hours) if daily_phone_hours is not None else None,
        "workout_gap_ratio": gap_ratio,
    }


def coldstart_frame(onboarding_rows: Iterable[Mapping[str, Any]]) -> pd.DataFrame:
    """`coldstart_features` applied to many rows, as a DataFrame with the numeric-only columns
    `train_risk_model.train_coldstart_logistic` fits on (logistic regression needs numeric input;
    `fall_off_pattern` is carried through for callers that want it but isn't used by that fit —
    see that function's docstring)."""
    vectors = [coldstart_features(r) for r in onboarding_rows]
    return pd.DataFrame(vectors, columns=["fall_off_pattern", "daily_phone_hours", "workout_gap_ratio"])
