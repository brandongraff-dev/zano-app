"""Slip-risk model training skeleton (docs/spec.md §9.2, §9.9).

    "Model: gradient-boosted trees (LightGBM). Cold start: logistic regression on onboarding
    answers + population priors." — spec.md §9.2

STATUS: `goal_events` (and therefore `public.user_day_features`,
backend/supabase/migrations/0004_ml_feature_job.sql) has no real production data yet, so:

- `ColdStartRiskModel` (logistic regression on onboarding answers, blended with a fixed
  population prior) is the one of these two paths that's actually usable today, for every
  brand-new user. It's fully implemented and exercised end-to-end against SYNTHETIC data by
  tests/test_train_risk_model.py.
- `train_lightgbm` / `TrainedRiskModel` is the v1-proper model spec §9.2 describes, for once
  enough `user_day_features` history exists to fit it. It is also fully implemented and unit-
  tested against SYNTHETIC data (tests/test_train_risk_model.py), so the training code path
  itself is proven to work end-to-end — but `main()` is not wired to a live Supabase connection
  or scheduled anywhere, and nothing calls it in production yet. app/main.py's `/risk` endpoint
  still serves the heuristic stub described there.

This module has no side effects at import time: no DB connection, no file I/O, no model fitting.
Only `main()` (gated behind `if __name__ == "__main__":`) touches the filesystem.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from typing import Any, Iterable, Mapping, Sequence

import lightgbm as lgb
import pandas as pd
from sklearn.linear_model import LogisticRegression

from app.features import (
    ALL_FEATURE_COLUMNS,
    CATEGORICAL_FEATURE_COLUMNS,
    LABEL_COLUMN,
    POPULATION_PRIOR_P_MISS,
    coldstart_frame,
    to_frame,
)

# ---------------------------------------------------------------------------
# v1-proper model — LightGBM on user_day_features history (spec.md §9.2)
# ---------------------------------------------------------------------------


@dataclass
class TrainedRiskModel:
    """A fitted LightGBM slip-risk classifier plus the metadata callers need to score with it."""

    booster: lgb.LGBMClassifier
    feature_columns: tuple[str, ...]
    model_version: str = "lightgbm_v1"

    def predict_p_miss(self, rows: Iterable[Mapping[str, Any]]) -> list[float]:
        """Score raw `user_day_features`-shaped rows -> P(missed all goals) for each."""
        frame = to_frame(rows)
        proba = self.booster.predict_proba(frame[list(self.feature_columns)])
        classes = list(self.booster.classes_)
        # Look up the positive ("missed") class's column index rather than assuming it's column
        # 1 — stays correct even for a degenerate fit that only ever saw one class.
        positive_idx = classes.index(True) if True in classes else len(classes) - 1
        return [float(p[positive_idx]) for p in proba]


def train_lightgbm(
    frame: pd.DataFrame,
    *,
    label_column: str = LABEL_COLUMN,
    random_state: int = 42,
) -> TrainedRiskModel:
    """Fit a LightGBM classifier on a `features.to_frame(rows, include_label=True)`-shaped frame.

    Deliberately small hyperparameters (few leaves, modest tree count, a minimum-samples-per-leaf
    floor) since this is sized for the first few thousand rows of real `user_day_features` data,
    not a large dataset — retune once there's real volume to validate against, per spec §9's
    "start rules-based/simple, replace with models as goal_events grows" philosophy.

    Rows whose label is unknown (`None`) are dropped before fitting — they can't supervise
    anything and would otherwise crash the `bool` cast below.
    """
    if label_column not in frame.columns:
        raise ValueError(f"train_lightgbm: frame is missing label column {label_column!r}")

    frame = frame.dropna(subset=[label_column])
    if frame.empty:
        raise ValueError("train_lightgbm: no labeled rows to train on after dropping nulls")
    if frame[label_column].nunique() < 2:
        raise ValueError(
            "train_lightgbm: labels contain only one class "
            f"({frame[label_column].unique().tolist()!r}) — need both a miss and a non-miss "
            "example to fit a classifier"
        )

    feature_columns = tuple(c for c in ALL_FEATURE_COLUMNS if c in frame.columns)
    x = frame[list(feature_columns)]
    y = frame[label_column].astype(bool)

    model = lgb.LGBMClassifier(
        objective="binary",
        n_estimators=100,
        num_leaves=15,
        learning_rate=0.05,
        min_child_samples=10,
        random_state=random_state,
        verbosity=-1,
    )
    categorical = [c for c in CATEGORICAL_FEATURE_COLUMNS if c in feature_columns]
    model.fit(x, y, categorical_feature=(categorical or "auto"))
    return TrainedRiskModel(booster=model, feature_columns=feature_columns)


# ---------------------------------------------------------------------------
# Cold-start model — logistic regression + population prior (spec.md §9.2)
# ---------------------------------------------------------------------------

_COLDSTART_NUMERIC_COLUMNS: tuple[str, ...] = ("daily_phone_hours", "workout_gap_ratio")


@dataclass
class ColdStartRiskModel:
    """Logistic regression on onboarding answers, blended with a fixed population prior.

    Used for every user who has zero `user_day_features` rows — today, that's every user (see
    this module's docstring). `classifier` is `None` when there wasn't enough labeled cold-start
    outcome data to fit one yet (see `train_coldstart_logistic`); in that case `predict_p_miss`
    falls back to the flat population prior for everyone, same as app/main.py's
    `RISK_BASELINE_P_MISS` heuristic does today.
    """

    classifier: LogisticRegression | None
    feature_columns: tuple[str, ...] = _COLDSTART_NUMERIC_COLUMNS
    prior_p_miss: float = POPULATION_PRIOR_P_MISS
    model_version: str = "coldstart_logistic_v1"

    def predict_p_miss(self, onboarding_rows: Iterable[Mapping[str, Any]]) -> list[float]:
        onboarding_rows = list(onboarding_rows)
        if self.classifier is None:
            return [self.prior_p_miss for _ in onboarding_rows]

        frame = coldstart_frame(onboarding_rows)[list(self.feature_columns)]
        frame = _fill_coldstart_defaults(frame)
        proba = self.classifier.predict_proba(frame)
        classes = list(self.classifier.classes_)
        positive_idx = classes.index(True) if True in classes else len(classes) - 1
        return [
            # Blend the fitted model with the population prior instead of trusting it outright:
            # a cold-start logistic regression is fit on very few labeled outcomes early on (see
            # the sample-size floor in train_coldstart_logistic), so this keeps individual
            # predictions from swinging on sparse data. 70/30 is a placeholder weighting, not
            # tuned against real outcomes yet — revisit once there's enough cold-start data to
            # tune it against.
            0.7 * float(p[positive_idx]) + 0.3 * self.prior_p_miss
            for p in proba
        ]


def train_coldstart_logistic(
    onboarding_rows: Sequence[Mapping[str, Any]],
    labels: Sequence[bool],
    *,
    min_samples: int = 20,
    random_state: int = 42,
) -> ColdStartRiskModel:
    """Fit the cold-start logistic regression on (onboarding_answers, missed_first_tracked_day)
    pairs.

    `labels[i]` is whether `onboarding_rows[i]`'s user missed all goals on their first tracked
    day — the only outcome a genuinely cold-start user (zero history) can be labeled on.

    Below `min_samples` total examples, or with only one class represented, returns a model whose
    `classifier` is `None` (falls back to the flat population prior — see `ColdStartRiskModel`)
    rather than fitting a classifier that would just be memorizing noise on a handful of rows.
    """
    if len(onboarding_rows) != len(labels):
        raise ValueError(
            f"train_coldstart_logistic: {len(onboarding_rows)} rows but {len(labels)} labels"
        )

    y = pd.Series(list(labels), dtype=bool)
    if len(y) < min_samples or y.nunique() < 2:
        return ColdStartRiskModel(classifier=None)

    frame = coldstart_frame(onboarding_rows)[list(_COLDSTART_NUMERIC_COLUMNS)]
    frame = _fill_coldstart_defaults(frame)

    classifier = LogisticRegression(max_iter=1000, random_state=random_state)
    classifier.fit(frame, y)
    return ColdStartRiskModel(classifier=classifier)


def _fill_coldstart_defaults(frame: pd.DataFrame) -> pd.DataFrame:
    """Median-impute the small numeric cold-start feature set — unlike LightGBM, scikit-learn's
    LogisticRegression can't take NaN natively. Falls back to 0.0 for a column that's entirely
    null (whose median is itself NaN)."""
    return frame.fillna(frame.median(numeric_only=True)).fillna(0.0)


# ---------------------------------------------------------------------------
# CLI skeleton — not wired to a live Supabase connection; reads a local export instead so this is
# runnable/testable without production data or credentials.
# ---------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    """`python -m app.train_risk_model --features path/to/user_day_features_export.csv`.

    Reads a local CSV/Parquet export of `public.user_day_features` (e.g. from `supabase db dump`
    or a `select * from user_day_features` -> CSV), trains the LightGBM model on it, and saves the
    fitted booster. NOT wired to a live Supabase connection yet — that's a future session's job
    once real `user_day_features` data exists to train against.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--features", required=True, help="Path to a user_day_features CSV or Parquet export."
    )
    parser.add_argument(
        "--out", default="risk_model.txt", help="Where to save the fitted LightGBM booster."
    )
    args = parser.parse_args(argv)

    frame = pd.read_parquet(args.features) if args.features.endswith(".parquet") else pd.read_csv(args.features)
    for col in CATEGORICAL_FEATURE_COLUMNS:
        if col in frame.columns:
            frame[col] = frame[col].astype("category")

    trained = train_lightgbm(frame)
    trained.booster.booster_.save_model(args.out)
    print(
        f"Saved {trained.model_version} ({len(trained.feature_columns)} features) to {args.out}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
