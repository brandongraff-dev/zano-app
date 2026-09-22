"""Tests for app/train_risk_model.py (docs/spec.md §9.2) against SYNTHETIC data.

There is no real `goal_events`/`user_day_features` or onboarding-answers data to train on yet
(see that module's docstring), so these tests generate synthetic rows with a known, hand-picked
relationship between features and label, fit the real model classes against them, and assert the
fitted models actually learned the direction of that relationship — not just that the code runs
without raising. `random.Random(<fixed seed>)` keeps generation reproducible across runs.
"""

from __future__ import annotations

import random

import pytest

from app.features import LABEL_COLUMN, POPULATION_PRIOR_P_MISS, to_frame
from app.train_risk_model import (
    ColdStartRiskModel,
    TrainedRiskModel,
    train_coldstart_logistic,
    train_lightgbm,
)

# ---------------------------------------------------------------------------
# Synthetic user_day_features rows for the LightGBM path
# ---------------------------------------------------------------------------


def _synthetic_user_day_rows(n: int, seed: int = 42) -> list[dict[str, object]]:
    """`n` synthetic user_day_features-shaped rows. Ground truth: higher `streak_length` and
    `yesterday_completed=True` push P(missed all goals) DOWN; the model should learn that
    direction."""
    rng = random.Random(seed)
    rows: list[dict[str, object]] = []
    for _ in range(n):
        streak = rng.randint(0, 20)
        yesterday_completed = rng.random() < min(0.15 + streak * 0.035, 0.95)
        events_count = rng.randint(0, 5)
        p_miss = 0.75 - 0.03 * streak - (0.25 if yesterday_completed else 0.0)
        p_miss = min(max(p_miss, 0.03), 0.95)
        rows.append(
            {
                "day_of_week": rng.randint(0, 6),
                "hour_of_first_event": rng.randint(0, 23),
                "streak_length": streak,
                "days_since_last_miss": rng.randint(0, 30),
                "events_count": events_count,
                "verified_events_count": rng.randint(0, events_count),
                "active_goal_count": rng.randint(1, 3),
                "avg_difficulty_step": rng.uniform(-2.0, 2.0),
                "sleep_hours": None,
                "calendar_density": None,
                "yesterday_completed": yesterday_completed,
                "any_plan_b_offered": rng.random() < 0.1,
                "travel_flag": None,
                "onboarding_fall_off_pattern": None,
                "weather": None,
                LABEL_COLUMN: rng.random() < p_miss,
            }
        )
    return rows


def _protective_row() -> dict[str, object]:
    """A row from the 'clearly safe' end of the synthetic relationship: long streak, completed
    yesterday."""
    return {
        "day_of_week": 2,
        "hour_of_first_event": 8,
        "streak_length": 18,
        "days_since_last_miss": 25,
        "events_count": 3,
        "verified_events_count": 3,
        "active_goal_count": 2,
        "avg_difficulty_step": 0.0,
        "sleep_hours": None,
        "calendar_density": None,
        "yesterday_completed": True,
        "any_plan_b_offered": False,
        "travel_flag": None,
        "onboarding_fall_off_pattern": None,
        "weather": None,
    }


def _risky_row() -> dict[str, object]:
    """A row from the 'clearly at-risk' end: zero streak, missed yesterday."""
    return {
        "day_of_week": 5,
        "hour_of_first_event": 20,
        "streak_length": 0,
        "days_since_last_miss": 0,
        "events_count": 0,
        "verified_events_count": 0,
        "active_goal_count": 2,
        "avg_difficulty_step": 0.0,
        "sleep_hours": None,
        "calendar_density": None,
        "yesterday_completed": False,
        "any_plan_b_offered": False,
        "travel_flag": None,
        "onboarding_fall_off_pattern": None,
        "weather": None,
    }


def test_train_lightgbm_returns_trained_model_with_expected_feature_columns() -> None:
    rows = _synthetic_user_day_rows(400)
    frame = to_frame(rows, include_label=True)
    trained = train_lightgbm(frame)
    assert isinstance(trained, TrainedRiskModel)
    assert trained.model_version == "lightgbm_v1"
    assert "streak_length" in trained.feature_columns
    assert "yesterday_completed" in trained.feature_columns


def test_train_lightgbm_predict_p_miss_is_a_valid_probability() -> None:
    rows = _synthetic_user_day_rows(400)
    frame = to_frame(rows, include_label=True)
    trained = train_lightgbm(frame)
    preds = trained.predict_p_miss([_protective_row(), _risky_row()])
    assert len(preds) == 2
    for p in preds:
        assert 0.0 <= p <= 1.0


def test_train_lightgbm_learns_the_synthetic_relationship_direction() -> None:
    """The core correctness check: a long-streak/completed-yesterday profile should score
    meaningfully LOWER risk than a zero-streak/missed-yesterday profile, matching how the
    synthetic labels were generated above."""
    rows = _synthetic_user_day_rows(600)
    frame = to_frame(rows, include_label=True)
    trained = train_lightgbm(frame)

    protective_preds = trained.predict_p_miss([_protective_row()] * 5)
    risky_preds = trained.predict_p_miss([_risky_row()] * 5)

    avg_protective = sum(protective_preds) / len(protective_preds)
    avg_risky = sum(risky_preds) / len(risky_preds)
    assert avg_protective < avg_risky - 0.1, (
        f"expected protective profile risk ({avg_protective:.3f}) to be well below "
        f"risky profile risk ({avg_risky:.3f})"
    )


def test_train_lightgbm_raises_on_missing_label_column() -> None:
    frame = to_frame(_synthetic_user_day_rows(10), include_label=False)
    with pytest.raises(ValueError, match="label column"):
        train_lightgbm(frame)


def test_train_lightgbm_raises_when_only_one_class_present() -> None:
    rows = _synthetic_user_day_rows(20)
    for r in rows:
        r[LABEL_COLUMN] = False  # collapse to a single class
    frame = to_frame(rows, include_label=True)
    with pytest.raises(ValueError, match="one class"):
        train_lightgbm(frame)


# ---------------------------------------------------------------------------
# Synthetic onboarding-answer rows for the cold-start logistic-regression path
# ---------------------------------------------------------------------------


def _synthetic_onboarding_rows(n: int, seed: int = 7) -> tuple[list[dict[str, object]], list[bool]]:
    """`n` synthetic onboarding-answer rows + labels. Ground truth: higher `daily_phone_hours`
    and a bigger workout gap (current far below target) push P(missed first tracked day) UP."""
    rng = random.Random(seed)
    fall_off_options = ["weekends", "evenings", "when_stressed", "after_a_few_good_days", "travel"]
    rows: list[dict[str, object]] = []
    labels: list[bool] = []
    for _ in range(n):
        phone_hours = rng.randint(1, 10)
        current = rng.randint(0, 4)
        target = rng.randint(max(current, 1), 6)
        gap_ratio = max(target - current, 0) / target
        p_miss = 0.15 + 0.05 * phone_hours * gap_ratio
        p_miss = min(max(p_miss, 0.02), 0.9)
        rows.append(
            {
                "fall_off_pattern": rng.choice(fall_off_options),
                "daily_phone_hours": phone_hours,
                "current_workouts_per_week": current,
                "target_workouts_per_week": target,
            }
        )
        labels.append(rng.random() < p_miss)
    return rows, labels


def test_train_coldstart_logistic_below_min_samples_falls_back_to_prior() -> None:
    rows, labels = _synthetic_onboarding_rows(10)
    model = train_coldstart_logistic(rows, labels, min_samples=20)
    assert model.classifier is None
    preds = model.predict_p_miss(rows)
    assert preds == [POPULATION_PRIOR_P_MISS] * len(rows)


def test_train_coldstart_logistic_fits_a_classifier_with_enough_samples() -> None:
    rows, labels = _synthetic_onboarding_rows(200)
    model = train_coldstart_logistic(rows, labels, min_samples=20)
    assert isinstance(model, ColdStartRiskModel)
    assert model.classifier is not None


def test_train_coldstart_logistic_predict_p_miss_is_a_valid_probability() -> None:
    rows, labels = _synthetic_onboarding_rows(200)
    model = train_coldstart_logistic(rows, labels, min_samples=20)
    preds = model.predict_p_miss(rows[:5])
    assert len(preds) == 5
    for p in preds:
        assert 0.0 <= p <= 1.0


def test_train_coldstart_logistic_learns_the_synthetic_relationship_direction() -> None:
    rows, labels = _synthetic_onboarding_rows(300)
    model = train_coldstart_logistic(rows, labels, min_samples=20)

    safe_profile = {
        "fall_off_pattern": "travel",
        "daily_phone_hours": 1,
        "current_workouts_per_week": 4,
        "target_workouts_per_week": 4,
    }
    risky_profile = {
        "fall_off_pattern": "when_stressed",
        "daily_phone_hours": 10,
        "current_workouts_per_week": 0,
        "target_workouts_per_week": 6,
    }
    safe_pred = model.predict_p_miss([safe_profile])[0]
    risky_pred = model.predict_p_miss([risky_profile])[0]
    assert safe_pred < risky_pred


def test_train_coldstart_logistic_raises_on_length_mismatch() -> None:
    rows, labels = _synthetic_onboarding_rows(20)
    with pytest.raises(ValueError, match="labels"):
        train_coldstart_logistic(rows, labels[:-1])
